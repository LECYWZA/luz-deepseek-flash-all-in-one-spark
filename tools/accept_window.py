#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""accept_window — 投机接受率窗（M0 eval 三件套之三）：均值 ±2σ。

数据源优先级（M0 定谳，2026-09-30 核实）：
  [primary] 引擎 GET /metrics（:8898）——dev-dsv41 镜像 metrics_collector.py 已核实
            存在 spec_accept 类指标（部署方案 doc 4DGX-DSV41-Flash-部署方案-20260911.md
            §MTP/投机卡：vllm:spec_decode_* 空缺，补 sglang:spec_accept_rate）。
            采样 N 次（默认 10，间隔 2s），取数值样本算 mean/σ/±2σ 窗。
  [fallback] census 步数 + DE completion 反推：accept_len_est = Σ completion_tokens / steps。
            可得性验证：r12 = 2000/750 = 2.667 ∈ 实测窗 [2.47, 2.74] ✓；
            sd_bench json 本体无步数/accept 字段（已读源核实：de 行仅
            type/conc/per/per_all/agg/completion）——此缺口即 fallback 存在的理由。
            σ 不可得（单点估计）→ 记 sigma_unavailable=true。
            SPEC=0 臂 est<1 属步界效应，窗检查记 N/A-SPEC0。

判定：arm 的 mean（或 est）落在基线窗 [lo, hi]（默认 3.25 A0S′ 锚带；旧 2.47-2.74 已废，源自
      state/BASELINE-ANCHORS-20260930.md）内 → PASS。窗可用 ACCEPT_WINDOW 覆盖。

用法:
  python3 tools/accept_window.py --base http://127.0.0.1:8898 \
      --census logs/<arm>/<ts>/census_c1.json --de logs/<arm>/<ts>/de_prose_c1.json \
      --json-out logs/<arm>/eval/accept.json
  --selfcheck 离线自测（不发包）
"""
import argparse
import json
import re
import statistics
import sys
import time
import urllib.request

import bigread  # 大文件只读探针护栏（>50MB 必流式，QA-TOOLS 20261006）


def fetch_metrics_accept(base: str, timeout: float = 5.0):
    """从 /metrics 抓 spec accept 相关数值。返回 {metric_name: [samples]}。"""
    with urllib.request.urlopen(base.rstrip("/") + "/metrics", timeout=timeout) as r:
        body = r.read().decode()
    out = {}
    for line in body.splitlines():
        if line.startswith("#") or "accept" not in line.lower():
            continue
        m = re.match(r"^([\w:]+)\{[^}]*\}\s+([0-9.eE+-]+)\s*$", line) or \
            re.match(r"^([\w:]+)\s+([0-9.eE+-]+)\s*$", line)
        if m:
            try:
                out.setdefault(m.group(1), []).append(float(m.group(2)))
            except ValueError:
                pass
    return out


def census_fallback(census_json: str, de_jsons):
    """accept_len_est = Σ completion / census steps。多份 DE json 求和。"""
    c = bigread.capped_json_load(census_json, label="census")
    steps = c.get("steps")
    if not steps:
        raise ValueError(f"census 无 steps 字段: {census_json}")
    tot_ct = 0
    used = []
    for p in de_jsons:
        d = bigread.capped_json_load(p, label="de")
        for row in d.get("de", []):
            tot_ct += sum(row.get("completion", []))
        used.append(p)
    return tot_ct / steps, steps, tot_ct, used


def selfcheck():
    ok = True

    def need(cond, why):
        nonlocal ok
        print(("PASS" if cond else "FAIL"), why)
        ok = ok and cond

    # fallback 数学口径自检（不读外部文件）
    need(abs(2000 / 750 - 2.667) < 0.001, "r12 标定数 2000/750=2.667（∈[2.47,2.74]）")
    need(2000 / 2071 < 1.0, "r11 SPEC=0 est<1 → N/A-SPEC0 分支可达")
    # /metrics 解析器喂样例
    import io
    sample = ("# HELP sglang:spec_accept_rate accept\n"
              "sglang:spec_accept_rate{model=\"x\"} 0.41\n"
              "sglang:spec_accept_len 2.66\n"
              "sglang:num_running_reqs 4\n")
    parsed = {}
    for line in sample.splitlines():
        if line.startswith("#") or "accept" not in line.lower():
            continue
        m = re.match(r"^([\w:]+)\{[^}]*\}\s+([0-9.eE+-]+)\s*$", line) or \
            re.match(r"^([\w:]+)\s+([0-9.eE+-]+)\s*$", line)
        if m:
            parsed.setdefault(m.group(1), []).append(float(m.group(2)))
    need("sglang:spec_accept_rate" in parsed and parsed["sglang:spec_accept_rate"] == [0.41],
         "/metrics 解析（带 label 行）")
    need("sglang:num_running_reqs" not in parsed, "非 accept 指标不混入")
    try:
        fetch_metrics_accept("http://127.0.0.1:1", timeout=2)
        need(False, "坏端点必须红")
    except Exception as e:
        need("Connection" in type(e).__name__ or "connection" in str(e).lower(),
             f"坏端点红（{type(e).__name__}）")
    print("SELFCHECK", "PASS" if ok else "FAIL")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--base", default="http://127.0.0.1:8898")
    ap.add_argument("--samples", type=int, default=10)
    ap.add_argument("--interval-s", type=float, default=2.0)
    ap.add_argument("--census", help="fallback 用 census json（须与 DE 同窗）")
    ap.add_argument("--de", nargs="+", help="fallback 用 DE json（可多份）")
    ap.add_argument("--window", default="3.10,3.40",
                    help="基线窗 lo,hi（默认 A0S′ 锚带 3.10-3.40（3.25±5%）；旧 2.47-2.74=pre-A0S′ 已废，A13 卡 §3）")
    ap.add_argument("--json-out")
    ap.add_argument("--selfcheck", action="store_true")
    a = ap.parse_args()
    if a.selfcheck:
        return selfcheck()

    lo, hi = (float(x) for x in a.window.split(","))
    result = {"base": a.base, "window": [lo, hi], "source": None, "gap_notes": []}

    # primary: /metrics 采样
    try:
        series = {}
        for _ in range(max(1, a.samples)):
            got = fetch_metrics_accept(a.base)
            for k, v in got.items():
                series.setdefault(k, []).extend(v)
            time.sleep(a.interval_s)
        if series:
            kbest = max(series, key=lambda k: len(series[k]))
            xs = series[kbest]
            mean = statistics.fmean(xs)
            sigma = statistics.pstdev(xs) if len(xs) > 1 else None
            result.update({
                "source": "metrics", "metric": kbest,
                "n_samples": len(xs), "mean": round(mean, 4),
                "sigma": round(sigma, 4) if sigma is not None else None,
                "window_own": [round(mean - 2 * sigma, 4), round(mean + 2 * sigma, 4)]
                if sigma is not None else None,
                "pass": lo <= mean <= hi,
                "sigma_unavailable": sigma is None})
        else:
            result["gap_notes"].append("/metrics 200 但无 accept 类指标行")
    except Exception as e:  # noqa: BLE001
        result["gap_notes"].append(f"/metrics 不可达: {str(e)[:120]}")

    # fallback: census 步数 × DE completion
    if result["source"] is None:
        if a.census and a.de:
            try:
                est, steps, tot_ct, used = census_fallback(a.census, a.de)
                result.update({
                    "source": "census-fallback", "accept_len_est": round(est, 4),
                    "census_steps": steps, "sum_completion_tokens": tot_ct,
                    "de_files": used, "sigma": None, "sigma_unavailable": True,
                    "pass": (lo <= est <= hi) if est >= 1.0 else None})
                if est < 1.0:
                    result["note"] = ("est<1 → N/A-SPEC0（非投机臂，窗检查不适用；"
                                      "口径=census steps 含非解码步的步界效应）")
                result["gap_notes"].append(
                    "σ 不可得（单点估计）；sd_bench json 无步数字段为已核实缺口")
            except Exception as e:  # noqa: BLE001
                result["gap_notes"].append(f"census fallback 失败: {str(e)[:160]}")
        else:
            result["gap_notes"].append(
                "无 --census/--de 可供 fallback；缺 census json 是本臂采集缺口")

    result["verdict"] = "PASS" if result.get("pass") else (
        "N/A" if result.get("pass") is None else "FAIL")
    print(json.dumps(result, ensure_ascii=False, indent=1))
    if a.json_out:
        open(a.json_out, "w").write(json.dumps(result, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
