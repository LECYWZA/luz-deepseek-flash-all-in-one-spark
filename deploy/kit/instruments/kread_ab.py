#!/usr/bin/env python3
"""kread_ab.py — indexer K 读回（gather）路径 A/B：修复前 vs 修复后

背景（2026-09-22）：dense/compressed indexer 每 (chunk, layer) 都要把 index K 从
页缓冲里读回。旧实现建的是两个 **int64 列矩阵**（[n,64]+[n,4]，544 B/行纯索引算术，
计临时 620 B/行），宽度随上下文增长 ⇒ expandable_segments:False 下每档一个段、
谁也不复用（绞死病）。新实现走页内两个 strided 视图，索引开销 16 B/行。

本脚本给出**算子级**归因：同一 n、同一页缓冲、同一 stub，分别在**新进程**里
（ru_maxrss 差才算得准）跑旧/新两个实现，报瞬态峰值与单次耗时。
端到端那一半在阶梯台账里（整机 eff_idle transient），两者口径不同、互相印证。

用法：
  kread_ab.py --old /tmp/dsv4_mem_pool.py --new <overlay>/deepseek_v4_memory_pool.py \
              --ns 16384,131072,524288 [--pagesize 256] [--reps 1]
  kread_ab.py --child <file> <func> <n> <pagesize> <reps>   # 内部用
"""
import argparse
import json
import os
import resource
import subprocess
import sys
import textwrap
import time

STOP_RE = ("    def ", "class ", "    @")


def extract(path, name):
    """按 def 块抽方法体（同类内下一个 def / class 即止），去 4 空格缩进。"""
    lines = open(path).read().splitlines()
    start = None
    for i, ln in enumerate(lines):
        if ln.startswith(f"    def {name}("):
            start = i
            break
    if start is None:
        raise SystemExit(f"{path}: 找不到 {name}")
    end = len(lines)
    for j in range(start + 1, len(lines)):
        ln = lines[j]
        if any(ln.startswith(p) for p in STOP_RE):
            end = j
            break
    return textwrap.dedent("\n".join(lines[start:end])).strip("\n")


def child(srcfile, func, n, pagesize, reps):
    import torch

    # 函数体内 import 的量化表：外场造一张等形表（本测量只关心分配与算术，不比数值）
    import types as _t
    mod = _t.ModuleType("sglang.srt.layers.quantization.fp8")
    mod.DSV4_DEQUANT_FP4_TABLE = torch.randn(16, dtype=torch.float32)
    sys.modules["sglang"] = _t.ModuleType("sglang")
    sys.modules["sglang.srt"] = _t.ModuleType("sglang.srt")
    sys.modules["sglang.srt.layers"] = _t.ModuleType("sglang.srt.layers")
    sys.modules["sglang.srt.layers.quantization"] = _t.ModuleType("sglang.srt.layers.quantization")
    sys.modules["sglang.srt.layers.quantization.fp8"] = mod
    from typing import Optional, Tuple  # noqa: F401  （被抽函数注解需要）

    src = extract(srcfile, func)
    ns = {"torch": torch, "Optional": Optional, "Tuple": Tuple}
    exec(compile(src, f"<{func}@{os.path.basename(srcfile)}>", "exec"), ns)
    fn = ns[func]

    pages = (n + pagesize - 1) // pagesize
    buf = torch.randint(0, 255, (pages, pagesize * 68), dtype=torch.uint8)
    stub = type("S", (), {})()
    stub.index_k_with_scale_buffer = [buf]
    stub.start_layer = 0
    stub.page_size = pagesize
    stub.size = pages
    stub.use_fp4_indexer = True

    slots = torch.arange(n, dtype=torch.int64)
    rss0 = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss  # KiB
    t0 = time.perf_counter()
    out = None
    for _ in range(reps):
        out = fn(stub, 0, slots)
    dt = time.perf_counter() - t0
    rss1 = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    shape = out[0].shape if isinstance(out, tuple) else out.shape
    print(json.dumps({"rss_delta_kib": rss1 - rss0, "ms_per_call": 1000.0 * dt / reps,
                      "out_shape": list(shape), "pages": pages}))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--old")
    ap.add_argument("--new")
    ap.add_argument("--ns", default="16384,131072,524288")
    ap.add_argument("--pagesize", type=int, default=256)
    ap.add_argument("--reps", type=int, default=1)
    ap.add_argument("--json")
    ap.add_argument("--child", nargs=5, metavar=("FILE", "FUNC", "N", "PS", "REPS"))
    a = ap.parse_args()

    if a.child:
        child(a.child[0], a.child[1], int(a.child[2]), int(a.child[3]), int(a.child[4]))
        return 0

    ns = [int(x) for x in a.ns.split(",")]
    rows = []
    for n in ns:
        for impl, path in (("old", a.old), ("new", a.new)):
            if not path:
                continue
            for func in ("get_index_k_fp4", "get_index_k_dequant"):
                r = subprocess.run([sys.executable, __file__, "--child", path, func, str(n),
                                    str(a.pagesize), str(a.reps)],
                                   capture_output=True, text=True)
                rec = json.loads(r.stdout) if r.stdout.strip() else {"rss_delta_kib": -1}
                rec.update({"n": n, "impl": impl, "func": func})
                rows.append(rec)
    hdr = f"{'n':>8} {'impl':>4} {'func':<20} {'transient_MiB':>13} {'ms/call':>9}"
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        print(f"{r['n']:>8} {r['impl']:>4} {r['func']:<20} "
              f"{r['rss_delta_kib'] / 1024:>13.1f} {r.get('ms_per_call', float('nan')):>9.2f}")
    # 节省比（同 n 同 func）
    print()
    for n in ns:
        for func in ("get_index_k_fp4", "get_index_k_dequant"):
            o = next((r for r in rows if r["n"] == n and r["impl"] == "old" and r["func"] == func), None)
            w = next((r for r in rows if r["n"] == n and r["impl"] == "new" and r["func"] == func), None)
            if o and w and w.get("rss_delta_kib", 0) > 0:
                print(f"n={n:<8} {func:<20} 瞬态 {o['rss_delta_kib']/1024:>8.1f} → "
                      f"{w['rss_delta_kib']/1024:>7.1f} MiB  （{o['rss_delta_kib']/max(w['rss_delta_kib'],1):.1f}×）")
    if a.json:
        json.dump(rows, open(a.json, "w"), ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
