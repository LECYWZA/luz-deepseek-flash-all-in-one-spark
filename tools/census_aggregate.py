#!/usr/bin/env python3
"""census_aggregate v3 — 跨窗聚合器：N 个窗口账 JSON → census_stream 兼容终件。

census v3 分窗流式采集（INC-20261004-UMA 重构）的聚合端。输入=census_window.py
产出的 `census_v3_window/1` 窗口账（精确 ns 整数账），输出=与现行
`*_census_*.json` / `*_arpeaks.json` 字段兼容的终件（下游 G2/p12 判据读数不改
即可用），另加 `windows` 段与分布读数（教义 #14）。

合并数学（全部整数，舍入前精确）：
  - steps            = Σ 窗 steps
  - 族 us_avg        = Σ sum_ns / Σ n            （按调用次数加权）
  - 族 ms_per_step   = Σ sum_ns / Σ steps / 1e6  （按步数加权）
  - 族 calls_per_step= Σ n / Σ steps
  - 族 us_max        = max 窗 max_ns
  - 族 share_pct     = Σ sum_ns / Σ total_kernel_ns
  - wall_ms_per_step = median(heapq.merge 各窗排序步差))  ← 池化中位，
                       与「整窗直读」逐位相等（离线测试对拍项）
  - v2_host_accounting: prb/sync 均值按 Σsteps 加权；sync_breakdown_us=
                       逐名 Σ 总量（census_stream 同口径，非 per-step）
  - decode_span_ms   = Σ 窗 span_ns / 1e6（仅计被采集时间；与整窗直读差
                       边界项 ≤ 每边界一个中位步时，见设计卡 §测试）
  - p50/p99          = 合并 log2 直方图（18 桶）桶内线性插值（近似读数，
                       桶界同报 `*_bucket` 字段；教义 #14 分布读）
  - arpeaks          = 逐窗累积拼接（量小），每条附 window 溯源；epoch 换算
                       与 census_stream 同式 off = base_ns/1000 - first_prb_ts

判别力自检（教义 #15，离线测试 tests/test_offline_aggregate.py 执行）：
  - 窗内不变量：Σ族 sum_ns == total_kernel_ns；Σ族 n == n_kernels；
    len(step_diffs_ns) == steps-1；每族 Σ直方图 == n → 违者拒聚（exit 47）
  - 窗身份唯一：window.id / trace_path 重复 → 拒聚（exit 46）
  - 权重敏感性：steps 是加权分母，喂错窗权重时对拍必红（测试 N3 合成案证明
    「朴素均值」与「加权均值」在本数据上可判别）

退出码：46=窗身份重复；47=窗内不变量破坏；48=无窗/短窗；49=窗数与预期不符。
"""
import argparse
import glob
import heapq
import json
import sys

from census_window import BUCKET_LABELS, N_BINS, THRESH_NS, median_sorted_ints

EXIT_DUP = 46
EXIT_INCONSISTENT = 47
EXIT_NOWINDOW = 48
EXIT_COUNT = 49


def load_windows(paths):
    wins = []
    seen_ids = {}
    seen_paths = {}
    for p in paths:
        with open(p) as f:
            w = json.load(f)
        if w.get("schema") != "census_v3_window/1":
            raise SystemExit("census_aggregate: %s: 非 census_v3_window/1（got %r）"
                             % (p, w.get("schema")))
        wid = w["window"]["id"]
        tpath = w["window"].get("trace_path", "")
        if wid in seen_ids:
            print("census_aggregate: REFUSE(46) 窗 id 重复: %d (%s 与 %s)"
                  % (wid, seen_ids[wid], p), file=sys.stderr)
            sys.exit(EXIT_DUP)
        if tpath and tpath in seen_paths:
            print("census_aggregate: REFUSE(46) 窗 trace_path 重复: %s (%s 与 %s)"
                  % (tpath, seen_paths[tpath], p), file=sys.stderr)
            sys.exit(EXIT_DUP)
        seen_ids[wid] = p
        seen_paths[tpath] = p
        w["_path"] = p
        wins.append(w)
    if not wins:
        print("census_aggregate: REFUSE(48) 无输入窗", file=sys.stderr)
        sys.exit(EXIT_NOWINDOW)
    wins.sort(key=lambda w: w["window"]["id"])
    return wins


def check_window(w):
    """窗内不变量。返回问题列表（空=通过）。全部整数精确比较。"""
    probs = []
    fam_sum = sum(e["sum_ns"] for e in w["families"].values())
    fam_n = sum(e["n"] for e in w["families"].values())
    raw_sum = sum(e["sum_ns"] for e in w["raw"].values())
    raw_n = sum(e["n"] for e in w["raw"].values())
    if fam_sum != w["total_kernel_ns"]:
        probs.append("families sum_ns=%d != total_kernel_ns=%d (Δ=%d)"
                     % (fam_sum, w["total_kernel_ns"], fam_sum - w["total_kernel_ns"]))
    if fam_n != w["n_kernels"]:
        probs.append("families n=%d != n_kernels=%d" % (fam_n, w["n_kernels"]))
    if raw_sum != w["total_kernel_ns"]:
        probs.append("raw sum_ns=%d != total_kernel_ns=%d" % (raw_sum, w["total_kernel_ns"]))
    if raw_n != w["n_kernels"]:
        probs.append("raw n=%d != n_kernels=%d" % (raw_n, w["n_kernels"]))
    if len(w["step_diffs_ns"]) != w["steps"] - 1:
        probs.append("len(step_diffs_ns)=%d != steps-1=%d"
                     % (len(w["step_diffs_ns"]), w["steps"] - 1))
    for f, e in w["families"].items():
        if sum(e["hist"]) != e["n"]:
            probs.append("family %s: Σhist=%d != n=%d" % (f, sum(e["hist"]), e["n"]))
        if e["max_ns"] > e["sum_ns"] and e["n"] > 0:
            probs.append("family %s: max_ns>sum_ns" % f)
    return probs


def hist_quantile(hist, q):
    """合并直方图 → 分位数（us）。桶内线性插值；返回 (est_us, bucket_label)。"""
    n = sum(hist)
    if n == 0:
        return None, None
    rank = q * (n - 1)  # 0-based，与「排序数组取值」定义一致
    cum = 0
    for b, c in enumerate(hist):
        if c == 0:
            continue
        if cum + c > rank or b == len(hist) - 1:
            frac = (rank - cum) / c if c else 0.0
            lo = 0.0 if b == 0 else THRESH_NS[b - 1] / 1000.0
            hi = THRESH_NS[b] / 1000.0 if b < len(THRESH_NS) else THRESH_NS[-1] * 2 / 1000.0
            return round(lo + frac * (hi - lo), 1), BUCKET_LABELS[b]
        cum += c
    return None, None


def aggregate(wins, top=45):
    steps = sum(w["steps"] for w in wins)
    total_ns = sum(w["total_kernel_ns"] for w in wins)
    n_kernels = sum(w["n_kernels"] for w in wins)
    span_ns = sum(w["span_ns"] for w in wins)
    prb_sum = sum(w["prb_sum_ns"] for w in wins)
    sync_sum = sum(w["sync_sum_ns"] for w in wins)
    sync_by_name = {}
    for w in wins:
        for k, v in w["sync_by_name_ns"].items():
            sync_by_name[k] = sync_by_name.get(k, 0) + v

    fams = {}
    for w in wins:
        for f, e in w["families"].items():
            m = fams.get(f)
            if m is None:
                m = fams[f] = {"sum_ns": 0, "n": 0, "max_ns": 0,
                               "hist": [0] * N_BINS}
            m["sum_ns"] += e["sum_ns"]
            m["n"] += e["n"]
            m["max_ns"] = max(m["max_ns"], e["max_ns"])
            for i in range(N_BINS):
                m["hist"][i] += e["hist"][i]
    raws = {}
    for w in wins:
        for nm, e in w["raw"].items():
            r = raws.get(nm)
            if r is None:
                r = raws[nm] = {"sum_ns": 0, "n": 0}
            r["sum_ns"] += e["sum_ns"]
            r["n"] += e["n"]

    pooled = list(heapq.merge(*(w["step_diffs_ns"] for w in wins)))
    med_ns = median_sorted_ints(pooled)
    span_ms = span_ns / 1e6

    prb_avg = prb_sum / steps / 1000.0
    sync_avg = sync_sum / steps / 1000.0

    rows = []
    for f, e in sorted(fams.items(), key=lambda kv: -kv[1]["sum_ns"])[:top]:
        p50, p50_b = hist_quantile(e["hist"], 0.50)
        p99, p99_b = hist_quantile(e["hist"], 0.99)
        rows.append({
            "family": f,
            "ms_per_step": round(e["sum_ns"] / steps / 1e6, 3),
            "calls_per_step": round(e["n"] / steps, 1),
            "us_avg": round(e["sum_ns"] / e["n"] / 1000.0, 1),
            "us_max": round(e["max_ns"] / 1000.0, 1),
            "share_pct": round(e["sum_ns"] / total_ns * 100, 1) if total_ns else 0.0,
            # 教义 #14 分布读（log2 直方图插值，桶界同报；直方图本档 18 桶）
            "us_p50": p50, "p50_bucket": p50_b,
            "us_p99": p99, "p99_bucket": p99_b,
        })

    out = {
        "steps": steps,
        "decode_span_ms": round(span_ms, 1),
        "wall_ms_per_step": round(med_ns / 1e6, 2),
        "span_over_steps_ms": round(span_ms / steps, 2),
        "gpu_busy_ms_per_step": round(total_ns / steps / 1e6, 2),
        "gpu_busy_pct": round(total_ns / span_ns * 100, 1) if span_ns else 0.0,
        "n_kernels_per_step": round(n_kernels / steps, 0),
        "n_families": len(fams),
        "v2_host_accounting": {
            "prb_annotation_avg_us": round(prb_avg, 1),
            "sync_wait_avg_us": round(sync_avg, 1),
            "net_bookkeeping_avg_us": round(prb_avg - sync_avg, 1),
            "note": "prb-sync=net bookkeeping (doc13 s1: sync is designed wait)",
            "sync_breakdown_us": {k: round(v / 1000.0, 1)
                                  for k, v in sorted(sync_by_name.items(),
                                                     key=lambda kv: -kv[1])[:5]},
        },
        "base_time_nanoseconds": wins[0]["base_time_nanoseconds"],
        "ar_peaks_n": sum(len(w["ar"]) for w in wins),
        "rows": rows,
        "raw_rows": [{"name": nm, "ms_per_step": round(e["sum_ns"] / steps / 1e6, 4),
                      "calls_per_step": round(e["n"] / steps, 1)}
                     for nm, e in sorted(raws.items(), key=lambda kv: -kv[1]["sum_ns"])[:60]],
        "windows": {
            "n": len(wins),
            "items": [{
                "id": w["window"]["id"], "label": w["window"].get("label", ""),
                "phase": w["window"].get("phase", ""),
                "req_num_steps": w["window"].get("req_num_steps", 0),
                "steps": w["steps"],
                "decode_span_ms": round(w["span_ns"] / 1e6, 1),
                "net_mem_mb": w["window"].get("meta", {}).get("net_mb", ""),
                "mem_pre_mb": w["window"].get("meta", {}).get("mem_pre_mb", ""),
                "mem_post_mb": w["window"].get("meta", {}).get("mem_post_mb", ""),
                "truncated": w["window"].get("meta", {}).get("truncated", "0"),
                "trace_mb": round(w["window"].get("trace_bytes", 0) / 1e6, 1),
                "source": w["_path"],
            } for w in wins],
        },
        "census_v3": {
            "aggregator": "census_aggregate.py/1",
            "window_schema": "census_v3_window/1",
            "merge_math": ("整数 ns 账：us_avg 按 Σn 加权；ms_per_step/calls_per_step "
                           "按 Σsteps 加权；wall_ms_per_step=池化步差中位；"
                           "us_max=跨窗 max；直方图逐桶整数合并"),
            "quantile_method": ("log2 直方图 18 桶（<1us,1..131072us,≥131072us）"
                                "桶内线性插值，近似读数，桶界见 *_bucket 字段"),
            "span_semantics": ("decode_span_ms=Σ各窗被采集跨度（窗间未采集间隙不计）；"
                               "与整窗直读差边界项≤每边界一个中位步时"),
        },
    }
    return out


def merge_arpeaks(wins):
    entries = []
    for w in wins:
        base_ns = w["base_time_nanoseconds"]
        off = (base_ns / 1000.0 - w["first_prb_ts_us"]) if base_ns else 0.0
        for t, d in w["ar"]:
            entries.append({"mono_ts": t, "epoch_est_us": t + off,
                            "dur_us": round(d, 1), "window": w["window"]["id"]})
    entries.sort(key=lambda e: e["epoch_est_us"])
    return entries


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("window_jsons", nargs="+",
                    help="窗口账 JSON（census_window.py 产出；支持 glob）")
    ap.add_argument("--json", required=True, help="聚合终件（census 兼容格式）")
    ap.add_argument("--arpeaks", default="", help="聚合 arpeaks 终件")
    ap.add_argument("--top", type=int, default=45)
    ap.add_argument("--expect-windows", type=int, default=0,
                    help="预期窗数（不一致拒聚 exit 49）")
    ap.add_argument("--min-steps", type=int, default=3,
                    help="每窗最小 prb 步数（短窗拒聚 exit 48；0=放宽）")
    a = ap.parse_args()

    paths = []
    for pat in a.window_jsons:
        hit = sorted(glob.glob(pat))
        paths.extend(hit if hit else [pat])  # 无 glob 命中按字面路径（缺失时 open 报错）
    wins = load_windows(paths)

    for w in wins:
        if a.min_steps and w["steps"] < a.min_steps:
            print("census_aggregate: REFUSE(48) 窗 %d 步数 %d < %d（%s）"
                  % (w["window"]["id"], w["steps"], a.min_steps, w["_path"]),
                  file=sys.stderr)
            sys.exit(EXIT_NOWINDOW)
        probs = check_window(w)
        if probs:
            print("census_aggregate: REFUSE(47) 窗 %d 不变量破坏（%s）:"
                  % (w["window"]["id"], w["_path"]), file=sys.stderr)
            for p in probs:
                print("  - %s" % p, file=sys.stderr)
            sys.exit(EXIT_INCONSISTENT)

    if a.expect_windows and len(wins) != a.expect_windows:
        print("census_aggregate: REFUSE(49) 窗数 %d != 预期 %d" % (len(wins), a.expect_windows),
              file=sys.stderr)
        sys.exit(EXIT_COUNT)

    out = aggregate(wins, top=a.top)
    with open(a.json, "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    if a.arpeaks:
        with open(a.arpeaks, "w") as f:
            json.dump(merge_arpeaks(wins), f, ensure_ascii=False)

    print("AGG windows=%d steps=%d wall=%.2fms/step gpu_busy=%.2fms/step (%.1f%%) "
          "kernels/step=%d families=%d AR>1ms=%d -> %s"
          % (out["windows"]["n"], out["steps"], out["wall_ms_per_step"],
             out["gpu_busy_ms_per_step"], out["gpu_busy_pct"],
             int(out["n_kernels_per_step"]), out["n_families"], out["ar_peaks_n"],
             a.json))
    for w in out["windows"]["items"]:
        print("  win#%d %-7s steps=%-4d span=%-8.1fms trace=%-7.1fMB net_mem=%sMB"
              % (w["id"], w["phase"], w["steps"], w["decode_span_ms"],
                 w["trace_mb"], w["net_mem_mb"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
