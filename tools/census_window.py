#!/usr/bin/env python3
"""census_window v3 — census_stream.py 的薄包装：单窗（num_steps 分窗）精确账。

census v3 = 分窗自动停流式采集（INC-20261004-UMA 后重构，见 CENSUS-V3-DESIGN.md）。
引擎侧每窗 `/start_profile {num_steps:N}` 到步自动停+自动 flush（v1 路径
profiler_manager.py `_profile_batch_predicate` → `_stop_profile` →
`export_chrome_trace`），本件只负责把「一窗 trace」变成「一窗精确账 JSON」。

内核零改动：`stream_events`/`family`/`MemGuard` 全部 import 自 census_stream.py
（~/v41-opt/tools/census_stream.py，a5ca6eae 世系），本文件只做包装层增量：

  1. 精确整数账（对拍零差的根基）：dur/ts 浮点按 Decimal 精确转纳秒（us×1000）
     整数累加。浮点直接累加有结合序误差，跨窗合并对拍不可能零差；整数账使
     Σ窗 与 整窗直读 在舍入前逐位相等。后缀 `_ns` 字段 = 纳秒整数。
  2. 分布读数（教义 #14：均值单价必须附分布读）：每族 log2 直方图（18 桶，
     <1us,1,2,4,...,131072us,≥131072us），跨窗整数合并后出 p50/p99。
     直方图是 Counter——键空间有界，保持 census_stream 的 O(1) 事件内存不变量。
  3. 步差池（wall_ms_per_step 跨窗精确池化）：每窗存排序步差 ns 列表
     （步差个数=步数-1，量级=窗步数），聚合器 heapq.merge 后取中位=整窗直读零差。
  4. arpeaks（≥1ms nccl.AR 尾事件）逐窗原样保留（量小），epoch 换算与
     census_stream 完全同式，由聚合器统一做。
  5. 兼容块：每窗 JSON 内嵌 census_stream 同字段同舍入的 `compat` 读数，
     单窗文件可独立人读；聚合器只吃 `_ns` 精确字段（双通道，见 schema）。

内存不变量（继承 census_stream 文件头契约）：本文件逐事件只持有 1 个事件 dict
（stream_events 产生）+ 有界 Counter/直方图 + 步差列表（=步数量级）；ar 列表
每步个位数。禁止 json.load/readlines/f.read()。--mem-limit-mb 兜底自检同源。

用法（census_capture_w3.sh 内嵌调用；也可手跑）:
  python3 census_window.py WIN.trace.json.gz --json WIN.census.json \
      --window-id 0 --phase decode --req-num-steps 100 \
      --meta mem_pre_mb=... --meta mem_post_mb=... [--mem-limit-mb 512]
"""
import argparse
import importlib.util
import json
import os
import sys
from bisect import bisect_right
from decimal import Decimal, ROUND_HALF_EVEN

DEFAULT_CENSUS_STREAM = os.path.expanduser("~/v41-opt/tools/census_stream.py")

# ── log2 直方图：18 桶。THRESH_NS[i] = 1000 * 2**i 纳秒（1us..65536us 的桶界）──
THRESH_NS = [1000 * (1 << i) for i in range(17)]  # 1us,2,...,65536us（共17界）
N_BINS = len(THRESH_NS) + 1  # 0=<1us, 1..16=[2^(i-1),2^i)us, 17=≥65536us
BUCKET_LABELS = (["<1us"] + ["%d-%dus" % (1 << i, 1 << (i + 1)) for i in range(16)]
                 + ["≥65536us"])

_NANO = Decimal(1000)


def to_nano(x) -> int:
    """浮点 us → 精确 ns 整数。trace 中 dur/ts 至多 3 位小数（us），
    Decimal(f) 是该二进制浮点的精确十进制展开，×1000 后按半偶取整恢复真值；
    直接 int(f*1000) 会被二进制尾差截偏 1ns。"""
    if x is None:
        return 0
    if isinstance(x, int):
        return x * 1000
    return int((Decimal(x) * _NANO).to_integral_value(rounding=ROUND_HALF_EVEN))


def bucket(nano: int) -> int:
    """ns → 桶号。bin0=<1us；bin i=[2^(i-1),2^i)us；bin17=≥131072us。"""
    return min(bisect_right(THRESH_NS, nano), N_BINS - 1)


def load_census_stream(path: str):
    spec = importlib.util.spec_from_file_location("census_stream_v3shim", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def median_sorted_ints(sorted_ns):
    n = len(sorted_ns)
    if n == 0:
        return 0
    m = n // 2
    if n % 2:
        return sorted_ns[m]
    return (sorted_ns[m - 1] + sorted_ns[m]) // 2


def census_window(cs, path, guard, min_steps=3):
    """cs = census_stream 模块。返回 window dict（schema census_v3_window/1）。"""
    fam_ns = {}   # family -> {"sum_ns","n","max_ns","hist"}
    raw_ns = {}   # name160 -> {"sum_ns","n"}
    sync_ns = {}  # runtime Synchronize name -> {"sum_ns"}（对齐 census_stream runtime_rows=总us口径）
    prb_ts = []   # (ts_nano, dur_nano) process_batch_result 锚
    ar = []       # [ts_float, dur_float] nccl.AR >1ms（原浮点，epoch 换算聚合器做）
    n_ev = n_kernel = 0
    total_kernel_ns = 0

    for ev in cs.stream_events(path, 0, guard=guard):
        if ev.get("ph") != "X":
            continue
        n_ev += 1
        cat = ev.get("cat")
        name = ev.get("name", "?")
        d = ev.get("dur", 0) or 0
        ts = ev.get("ts", 0) or 0
        if cat == "cuda_runtime":
            if "Synchronize" in name:
                e = sync_ns.setdefault(name, {"sum_ns": 0})
                e["sum_ns"] += to_nano(d)
            continue
        if cat == "user_annotation":
            if name == "scheduler.process_batch_result":
                prb_ts.append((to_nano(ts), to_nano(d)))
            continue
        if cat != "kernel":
            continue
        n_kernel += 1
        d_ns = to_nano(d)
        total_kernel_ns += d_ns
        f = cs.family(name)
        e = fam_ns.get(f)
        if e is None:
            e = fam_ns[f] = {"sum_ns": 0, "n": 0, "max_ns": 0, "hist": [0] * N_BINS}
        e["sum_ns"] += d_ns
        e["n"] += 1
        if d_ns > e["max_ns"]:
            e["max_ns"] = d_ns
        e["hist"][bucket(d_ns)] += 1
        rk = name[:160]
        r = raw_ns.get(rk)
        if r is None:
            r = raw_ns[rk] = {"sum_ns": 0, "n": 0}
        r["sum_ns"] += d_ns
        r["n"] += 1
        if f == "nccl.AR" and d > 1000:
            ar.append([ts, d])

    nsteps = len(prb_ts)
    if nsteps < min_steps:
        raise SystemExit("census_window: process_batch_result %d < %d, refusing"
                         % (nsteps, min_steps))
    prb_ts.sort()
    ts_l = [t for t, _ in prb_ts]
    diffs = sorted(b - a for a, b in zip(ts_l, ts_l[1:]))
    med_ns = median_sorted_ints(diffs)
    span_ns = (ts_l[-1] + med_ns - ts_l[0]) if nsteps else 0
    prb_sum_ns = sum(d for _, d in prb_ts)
    sync_sum_ns = sum(e["sum_ns"] for e in sync_ns.values())
    base_ns = cs.BASENS_CACHE[0]
    first_ts = min(ts_l) / 1000.0 if ts_l else 0.0
    last_ts = max(ts_l) / 1000.0 if ts_l else 0.0

    win = {
        "schema": "census_v3_window/1",
        "window": {},  # 由 CLI 填充（id/phase/meta）
        "steps": nsteps,
        "n_events": n_ev,
        "n_kernels": n_kernel,
        "total_kernel_ns": total_kernel_ns,
        "first_ts_ns": int(ts_l[0]) if ts_l else 0,
        "last_ts_ns": int(ts_l[-1]) if ts_l else 0,
        "span_ns": int(span_ns),
        "step_diffs_ns": diffs,           # 排序步差（聚合器池化用）
        "prb_sum_ns": prb_sum_ns,
        "sync_sum_ns": sync_sum_ns,
        "sync_by_name_ns": {k: e["sum_ns"] for k, e in sync_ns.items()},
        "base_time_nanoseconds": base_ns,
        "first_prb_ts_us": first_ts,
        "last_prb_ts_us": last_ts,
        "families": fam_ns,
        "raw": raw_ns,
        "ar": ar,
        "hist_bins": N_BINS,
        "hist_thresholds_ns": THRESH_NS,
    }
    win["compat"] = _compat_block(win)
    return win


def _compat_block(win):
    """census_stream 同字段同舍入的单窗读数（人读/兼容；聚合器不用这些）。"""
    nsteps = win["steps"]
    total = win["total_kernel_ns"]
    span_ms = win["span_ns"] / 1e6
    med_us = median_sorted_ints(win["step_diffs_ns"]) / 1000.0
    rows = sorted(win["families"].items(), key=lambda kv: -kv[1]["sum_ns"])
    prb_avg = win["prb_sum_ns"] / nsteps / 1000.0
    sync_avg = win["sync_sum_ns"] / nsteps / 1000.0
    out = {
        "steps": nsteps,
        "decode_span_ms": round(span_ms, 1),
        "wall_ms_per_step": round(med_us / 1000.0, 2),
        "span_over_steps_ms": round(span_ms / nsteps, 2),
        "gpu_busy_ms_per_step": round(total / nsteps / 1e6, 2),
        "gpu_busy_pct": round(total / (win["span_ns"]) * 100, 1) if win["span_ns"] else 0.0,
        "n_kernels_per_step": round(win["n_kernels"] / nsteps, 0),
        "n_families": len(win["families"]),
        "v2_host_accounting": {
            "prb_annotation_avg_us": round(prb_avg, 1),
            "sync_wait_avg_us": round(sync_avg, 1),
            "net_bookkeeping_avg_us": round(prb_avg - sync_avg, 1),
            "note": "prb-sync=net bookkeeping (doc13 s1: sync is designed wait)",
            "sync_breakdown_us": {k: round(v / 1000.0, 1)
                                  for k, v in sorted(win["sync_by_name_ns"].items(),
                                                     key=lambda kv: -kv[1])[:5]},
        },
        "base_time_nanoseconds": win["base_time_nanoseconds"],
        "ar_peaks_n": len(win["ar"]),
        "rows": [{"family": f, "ms_per_step": round(e["sum_ns"] / nsteps / 1e6, 3),
                  "calls_per_step": round(e["n"] / nsteps, 1),
                  "us_avg": round(e["sum_ns"] / e["n"] / 1000.0, 1),
                  "us_max": round(e["max_ns"] / 1000.0, 1),
                  "share_pct": round(e["sum_ns"] / total * 100, 1) if total else 0.0}
                 for f, e in rows[:45]],
        "raw_rows": [{"name": nm, "ms_per_step": round(e["sum_ns"] / nsteps / 1e6, 4),
                      "calls_per_step": round(e["n"] / nsteps, 1)}
                     for nm, e in sorted(win["raw"].items(),
                                         key=lambda kv: -kv[1]["sum_ns"])[:60]],
    }
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace")
    ap.add_argument("--json", required=True, help="输出窗口账 JSON")
    ap.add_argument("--window-id", type=int, default=0)
    ap.add_argument("--label", default="")
    ap.add_argument("--phase", default="decode", help="decode|prefill|mixed（采集脚本登记）")
    ap.add_argument("--req-num-steps", type=int, default=0, help="本窗 /start_profile num_steps")
    ap.add_argument("--profile-stages", default="", help="本窗 profile_stages（逗号分隔）")
    ap.add_argument("--meta", action="append", default=[],
                    help="附加 meta k=v（采集脚本传 mem_pre_mb/mem_post_mb/net_mb 等）")
    ap.add_argument("--min-steps", type=int, default=3)
    ap.add_argument("--mem-limit-mb", type=int, default=512)
    ap.add_argument("--census-stream", default=DEFAULT_CENSUS_STREAM)
    a = ap.parse_args()

    cs = load_census_stream(a.census_stream)
    guard = cs.MemGuard(a.mem_limit_mb)
    win = census_window(cs, a.trace, guard, min_steps=a.min_steps)

    meta = {}
    for kv in a.meta:
        k, _, v = kv.partition("=")
        meta[k] = v
    win["window"] = {
        "id": a.window_id, "label": a.label, "phase": a.phase,
        "req_num_steps": a.req_num_steps, "profile_stages": a.profile_stages,
        "trace_path": os.path.abspath(a.trace),
        "trace_bytes": os.path.getsize(a.trace), "meta": meta,
    }
    with open(a.json, "w") as f:
        json.dump(win, f, indent=1, ensure_ascii=False)

    c = win["compat"]
    print("window#%d(%s) steps=%d wall=%.2fms/step gpu_busy=%.2fms/step (%.1f%%) "
          "kernels/step=%d families=%d AR>1ms=%d" % (
              a.window_id, a.phase, c["steps"], c["wall_ms_per_step"],
              c["gpu_busy_ms_per_step"], c["gpu_busy_pct"], int(c["n_kernels_per_step"]),
              c["n_families"], c["ar_peaks_n"]))
    if a.mem_limit_mb:
        print("MEMGUARD: ok peak_rss=%.0fMB (limit=%dMB)"
              % (cs._rss_mb(), a.mem_limit_mb), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
