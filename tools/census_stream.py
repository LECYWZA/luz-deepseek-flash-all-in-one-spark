#!/usr/bin/env python3
"""census_stream v2 — 多行 pretty-printed kineto trace 流式 census（W0-1/2 直管版）

背景: r11 trace 是多行 pretty JSON（186M 行）。json.load 必爆内存；v2.1 raw_decode
逐对象解析对 with_stack 大行仍是小时级。本版逐行状态机:
  - 仅 4 空格缩进事件层字段（ph/cat/name/ts/dur）进解析，args 子树（>=6 空格）被缩进天然过滤
  - RSS 恒定 <100MB，全量单遍 5-15 分钟

口径与 kernel_census_v2.py v2.1 完全对齐（doc10/11 数字可比）:
  - 家族分类 FAMILY_RULES + V2_RULES 原样继承
  - 步数锚 user_annotation 'scheduler.process_batch_result' ts 中位差
  - 只计 cat=='kernel' 进族账; cuda_runtime Synchronize 单列（v2 剔纯等待口径）
  - raw_rows 键截 160 字符

新增: --arpeaks 输出 nccl.AR >1ms 事件（ts + baseTimeNanoseconds 换算 epoch_est），
      供 w06_align.py 做 RoCE 干扰 vs boot-early 判别。epoch 假设: baseTime 对应首事件。

内存护栏（2026-09-30 四节点冻结事故后新增，见 reports/23-census护栏设计-V41新基座.md）:

  【结构性保证 — 本解析器永不缓存全量 trace】
  本文件是逐行状态机（stream_events 的 for line in f 循环体）：
    - 任何时刻内存里只有 1 个正在累积的事件 dict（cur，几十字节级）+ 聚合 Counter
    - Counter 的键空间是「家族名/截断 160 字符的 raw 名」（有界，实测几千个键）
    - 唯一无界列表是 ar（nccl.AR>1ms 事件），量级为每步个位数，即便 10 万步也是 MB 级
    - 禁止引入 json.load / readlines() / f.read() —— 那是 v1 RSS 8.5G 事故的根因；
      禁止把逐事件 dict 存进列表再后处理 —— 那是 v2.1 raw_decode RSS 13.6G 事故的根因
    - 修改本文件时必须保持 O(1) 事件内存不变量；需要新聚合就加 Counter，不要加 list[dict]

  【运行时自检 — --mem-limit-mb】
    每 N 行（默认 200 万行 ≈ 每几十秒一次）用 resource.getrusage 查一次自身 RSS，
    超限 print 诊断 + sys.exit(42)。退出码 42 = 解析器自灭，供上层脚本区分于其他失败。
    这是兜底：正常情况下状态机 RSS 恒定 <100MB，永远不会触发。
"""
import argparse, gzip, json, os, re, resource, sys, time
from collections import Counter

FAMILY_RULES = [
    ("moe_sharedkernelssilu", "MoE b12x Silu"),
    ("dense_blockscaled", "dense_b12x GEMM"),
    ("ncclDevKernel_AllReduce", "nccl.AR"),
    ("ncclDevKernel_AllGather", "nccl.AG"),
    ("ncclDevKernel_Broadcast", "nccl.BC"),
    ("ncclDevKernel_ReduceScatter", "nccl.RS"),
    ("ncclDevKernel_SendRecv", "nccl.SR"),
    ("wmma_tensorop_bf16", "lm_head wmma bf16"),
    ("_wo_a_partial", "wo_a partial"),
    ("_wo_a_reduce", "wo_a reduce"),
    ("_wo_a_bf16_gemv", "wo_a bf16 gemv"),
    ("_hc_mix_stats", "hc_mix_stats"),
    ("_hc_mix_reduce", "hc_mix_reduce"),
    ("_mhc_post_split_h", "mhc_post_split_h"),
    ("_hc_combine", "hc_combine"),
    ("sparse_mla", "sparse_mla attn"),
    ("tiny_n_gemm", "router tiny_n_gemm"),
    ("_router_triton", "router triton"),
    ("_repack_fp4", "kv_repack_fp4"),
    # CUDA port (anonymous namespace)::repack_fp4_to_v4_kernel -- no leading
    # underscore, so the Triton rule misses it and the tail-44 fallback shows
    # only template-arg noise (A6 census 2026-10-01).
    ("repack_fp4_to_v4_kernel", "kv_repack_fp4"),
    ("_remap_dead_rows", "verify_prune remap"),
    ("_page_split", "pagetable overlay"),
    ("_page_table_positions", "pagetable overlay"),
    ("_page_mark", "pagetable overlay"),
    ("_build_step_local", "pagetable overlay"),
    ("_engram", "engram"),
    ("_online_partial", "online_softmax"),
    ("_online_combine", "online_softmax"),
    ("_scatter_gather", "scatter_gather"),
    ("silu_mul_clamp", "silu_mul_clamp"),
    ("fused_k_norm_rope", "fused_k_norm_rope"),
    ("deepseek_rope", "rope"),
    ("_vocab_parallel_embedding", "vocab_embedding"),
    ("paged_mqa_logits", "mqa_logits_meta"),
    ("DeviceScanKernel", "cub.scan"),
    ("cub::", "cub.other"),
    ("memcpy", "memcpy"),
    ("memset", "memset"),
    ("elementwise", "elementwise(tiny)"),
    ("reduce", "reduce(tiny)"),
    ("norm", "norm"),
]
V2_RULES = [
    ("w4a8_phase1W4A8MaterializedPhase1Kernel", "MoE FC1 (w4a8 ph1)"),
    ("w4a8_phase2W4A8MaterializedPhase2Kernel", "MoE FC2 (w4a8 ph2)"),
    ("DeviceGemmMxfp8GemmSm120", "mxfp8 cutlass fb (K=576)"),
]
_NORM_RE = re.compile(r"[^A-Za-z0-9_]+")

def family(name):
    for pat, fam in V2_RULES:
        if pat in name:
            return fam
    low = name.lower()
    for pat, fam in FAMILY_RULES:
        if pat.lower() in low:
            return fam
    n = re.sub(r"^.*?::", "", name)
    n = re.sub(r"<.*?>", "", n)
    n = _NORM_RE.sub("_", n)
    return n[-44:] or "?"

FIELD = re.compile(r'^    "(ph|cat|name|ts|dur)": (.*?),?\s*$')
BASENS = re.compile(r'"baseTimeNanoseconds":\s*(\d+)')

def _rss_mb():
    """自身 RSS（MB）。Linux: getrusage ru_maxrss 单位 kB（峰值，非瞬时，作保守上界足够）。"""
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024.0

class MemGuard:
    """RSS 自检兜底：每 check_every_lines 行查一次，超限自杀退出码 42。
    注意 ru_maxrss 是峰值而非瞬时值 —— 对「防打爆」目的而言保守方向正确：
    峰值超限即拒，哪怕后来回落。"""
    def __init__(self, limit_mb, check_every_lines=2_000_000):
        self.limit_mb = limit_mb
        self.check_every = check_every_lines
        self.n = 0
        if limit_mb:
            cur = _rss_mb()
            print("MEMGUARD: limit=%dMB rss_now=%.0fMB (interval=%d lines)"
                  % (limit_mb, cur, check_every_lines), file=sys.stderr)

    def tick(self):
        if not self.limit_mb:
            return
        self.n += 1
        if self.n % self.check_every:
            return
        rss = _rss_mb()
        if rss > self.limit_mb:
            print("MEMGUARD: FATAL rss=%.0fMB > limit=%dMB after %d lines — "
                  "自灭(exit 42)。这不该发生：状态机应恒定 <100MB，"
                  "出现此错误说明有人破坏了 O(1) 事件内存不变量（见文件头注释）。"
                  % (rss, self.limit_mb, self.n), file=sys.stderr)
            sys.exit(42)

def stream_events(path, max_events=0, guard=None):
    """逐行状态机: 4 缩进字段累积, 2 缩进 '}' 收口。yield 完整事件 dict。"""
    op = gzip.open if path.endswith(".gz") else open
    cur = {}
    base_ns = None
    n = 0
    with op(path, "rt", errors="replace") as f:
        for line in f:
            if guard is not None:
                guard.tick()
            if line.startswith('    "'):
                m = FIELD.match(line)
                if m:
                    k = m.group(1)
                    if k == "ph":
                        if cur:
                            n += 1
                            if max_events and n >= max_events:
                                return
                            yield cur
                        cur = {"ph": json.loads(m.group(2))}
                    elif cur is not None and cur != {}:
                        try:
                            cur[k] = json.loads(m.group(2))
                        except Exception:
                            pass
                else:
                    bm = BASENS.search(line)
                    if bm:
                        base_ns = int(bm.group(1))
            elif line.startswith("  }"):
                if cur:
                    n += 1
                    if max_events and n >= max_events:
                        return
                    yield cur
                cur = {}
    if cur:
        yield cur
    if base_ns is not None:
        BASENS_CACHE[0] = base_ns

BASENS_CACHE = [None]

def census(path, top, max_events=0, guard=None):
    per = Counter(); cnt = Counter(); raw = Counter(); rawcnt = Counter(); maxk = {}
    prb = []; runtime_rows = Counter()
    ar = []            # (mono_ts, dur) nccl.AR dur>1000us
    n_ev = n_kernel = 0
    for ev in stream_events(path, max_events, guard=guard):
        if ev.get("ph") != "X":
            continue
        n_ev += 1
        cat = ev.get("cat"); name = ev.get("name", "?"); d = ev.get("dur", 0) or 0
        ts = ev.get("ts", 0) or 0
        if cat == "cuda_runtime":
            if "Synchronize" in name:
                runtime_rows[name] += d
            continue
        if cat == "user_annotation":
            if name == "scheduler.process_batch_result":
                prb.append((ts, d))
            continue
        if cat != "kernel":
            continue
        n_kernel += 1
        f = family(name)
        per[f] += d; cnt[f] += 1
        maxk[f] = max(maxk.get(f, 0), d)
        rk = name[:160]
        raw[rk] += d; rawcnt[rk] += 1
        if f == "nccl.AR" and d > 1000:
            ar.append((ts, d))
    if max_events:
        print("SMOKE: events=%d kernels=%d families=%d top3=%s" % (
            n_ev, n_kernel, len(per), per.most_common(3)))
        return None
    if len(prb) < 3:
        raise SystemExit("census_stream: process_batch_result <3, refusing")
    prb.sort()
    ts_l = [p[0] for p in prb]
    diffs = sorted(b - a for a, b in zip(ts_l, ts_l[1:]))
    med = diffs[len(diffs) // 2]
    nsteps = len(prb)
    span_ms = (ts_l[-1] + med - ts_l[0]) / 1000.0
    total = sum(per.values())
    prb_avg_us = sum(d for _, d in prb) / nsteps
    sync_avg_us = sum(runtime_rows.values()) / nsteps
    rows = [{"family": f, "ms_per_step": round(per[f] / nsteps / 1000, 3),
             "calls_per_step": round(cnt[f] / nsteps, 1),
             "us_avg": round(per[f] / cnt[f], 1), "us_max": round(maxk[f], 1),
             "share_pct": round(per[f] / total * 100, 1)}
            for f, _ in per.most_common(top)]
    base_ns = BASENS_CACHE[0]
    first_ts = min((t for t, _ in prb), default=0)
    out = {"steps": nsteps, "decode_span_ms": round(span_ms, 1),
           "wall_ms_per_step": round(med / 1000.0, 2),
           "span_over_steps_ms": round(span_ms / nsteps, 2),
           "gpu_busy_ms_per_step": round(total / nsteps / 1000, 2),
           "gpu_busy_pct": round(total / (span_ms * 1000) * 100, 1),
           "n_kernels_per_step": round(sum(cnt.values()) / nsteps, 0),
           "n_families": len(per),
           "v2_host_accounting": {
               "prb_annotation_avg_us": round(prb_avg_us, 1),
               "sync_wait_avg_us": round(sync_avg_us, 1),
               "net_bookkeeping_avg_us": round(prb_avg_us - sync_avg_us, 1),
               "note": "prb-sync=net bookkeeping (doc13 s1: sync is designed wait)",
               "sync_breakdown_us": dict(runtime_rows.most_common(5))},
           "base_time_nanoseconds": base_ns,
           "ar_peaks_n": len(ar),
           "rows": rows,
           "raw_rows": [{"name": nm, "ms_per_step": round(raw[nm] / nsteps / 1000, 4),
                         "calls_per_step": round(rawcnt[nm] / nsteps, 1)}
                        for nm, _ in raw.most_common(60)]}
    return out, ar, base_ns, first_ts

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace")
    ap.add_argument("--top", type=int, default=45)
    ap.add_argument("--json", default="")
    ap.add_argument("--arpeaks", default="")
    ap.add_argument("--maxevents", type=int, default=0)
    ap.add_argument("--mem-limit-mb", type=int, default=0,
                    help="RSS 自检上限(MB)，超限自杀退出码 42；0=关闭。兜底护栏，正常永不触发")
    a = ap.parse_args()
    guard = MemGuard(a.mem_limit_mb)
    r = census(a.trace, a.top, a.maxevents, guard=guard)
    if r is None:
        return 0
    out, ar, base_ns, first_ts = r
    if a.mem_limit_mb:
        print("MEMGUARD: ok peak_rss=%.0fMB (limit=%dMB)" % (_rss_mb(), a.mem_limit_mb),
              file=sys.stderr)
    print("decode steps %s  wall %s ms/step  GPU busy %s ms/step (%s%%)  kernels %s/step  families %s  AR>1ms %d" % (
        out["steps"], out["wall_ms_per_step"], out["gpu_busy_ms_per_step"],
        out["gpu_busy_pct"], int(out["n_kernels_per_step"]), out["n_families"], out["ar_peaks_n"]))
    h = out["v2_host_accounting"]
    print("host(v2): prb %sus - sync %sus = net bookkeeping %sus/step" % (
        h["prb_annotation_avg_us"], h["sync_wait_avg_us"], h["net_bookkeeping_avg_us"]))
    print("%-30s%9s%11s%9s%9s%8s" % ("family", "ms/step", "calls/step", "us avg", "us max", "share"))
    for r2 in out["rows"]:
        print("%-30s%9.3f%11.1f%9.1f%9.1f%7.1f%%" % (
            r2["family"][:29], r2["ms_per_step"], r2["calls_per_step"],
            r2["us_avg"], r2["us_max"], r2["share_pct"]))
    if a.json:
        with open(a.json, "w") as f:
            json.dump(out, f, indent=1, ensure_ascii=False)
        print("json -> %s" % a.json)
    if a.arpeaks:
        off = (base_ns / 1000.0 - first_ts) if base_ns else 0.0
        json.dump([{"mono_ts": t, "epoch_est_us": t + off, "dur_us": d}
                   for t, d in sorted(ar)], open(a.arpeaks, "w"))
        print("ARPEAKS>1ms: %d -> %s (epoch offset %.1fs, baseTime对应首prb假设)" % (
            len(ar), a.arpeaks, off / 1e6))
    return 0

if __name__ == "__main__":
    sys.exit(main())
