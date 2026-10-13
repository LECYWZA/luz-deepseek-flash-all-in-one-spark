#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""w2_a2a6_crash_adjudicate — W2 修复窗 A2/A6 崩死终裁断言件（案头 DRY 形+靴搭载双用）。

法源：
  - docs/research/INDEXER-ROWCHUNK-PORTPLAN-20261009.md §五 A2/A6 行（判别力表）；
  - docs/research/ENGRAM-PREFILL-DEGRADATION-FORENSICS-20261009.md §3.2/§3.3
    （崩死候选 A-V1 buddy 碎片 / A-V2 row_store fail→abort / V3 cgroup OOM；
    重放取证三探针+读判四支）；
  - docs/taskcards/PREFILL-FIX-CAMPAIGN-CARD-20261009.md §三 F-1 验收面/§七。

子命令：
  sample     头宿主采样器（V1/V3/水位/可选 GPU 面）：/proc/buddyinfo 高阶空闲块
             +cgroup memory.events(oom_kill)/memory.current +/proc/meminfo
             +可选 nvidia-smi memory.used → JSONL。W2 重放窗全程跑，30s 缺省。
  derive     samples+rows.jsonl → A2 记录（每发窗口 [ts-total_s, ts] 内 GPU/水位
             峰-谷差；无 GPU 样本时用水位 MemAvailable 谷-峰差，记录 channel 字段）。
  a2         A2 断言（563k C 流除名/复活裁决器）：同预算组内 600k vs 300k vs
             128k 峰值增量不随总长线性涨（ratio 带）+绝对帽（budget×mult 与
             abs_floor 取大）。红=「#39187 前病（随 prompt 总长无界）复现」。
  adjudicate A6 终裁：rows 判死活 + 探针读出（V1 buddy 高阶塌陷先于死 / V2
             row_store fail 签名 grep / V3 oom_kill 计数）+ A2 联合 → C 流
             除名/复活 + A-V1/A-V2 升权 + 无探针时 core/UMA dump 升级支。
  selfcheck  合成夹具全链：绿/红/牙三向（负控=planted red 必须因正确理由红）。

判读门缺省值（设计稿未给数，自主定缺省、全部 flag 可调、如实呈报）：
  --ratio-band 3.0（线性涨=600k/128k≈4.7x，有界≈1x，带取中）;--headroom-mult 2.0
  +--abs-floor-gib 8.0（有界瞬态包络余帽；#39187 前病 488k 单 chunk 29.8GiB/rank
  远超此帽）;--buddy-order 10（4KiB 基页×2^10=4MiB 以上高阶）+--collapse-frac 0.1
  （高阶空闲 < 基线 10% = 塌陷）+--baseline-n 5。

已知缺口（如实标注，不臆造）：V2 的 fail 行在【未打 row_store fail() 落盘补丁
（A §6.2 F5）且容器 --rm】时物理不可得——本件 V2 判定输出「未见（探针完整性
依赖 F5 补丁+F8 日志保留）」而非「排除」；补丁+rebuild=W2 呈裁项，本役零碰
row_store.cpp/.so。
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time

FAILS = []


def check(tag, cond, detail=""):
    print("%s %s %s" % ("PASS" if cond else "FAIL", tag, detail))
    if not cond:
        FAILS.append(tag)
    return bool(cond)


# ───────────────────────────── sample ─────────────────────────────

def read_buddy(path="/proc/buddyinfo", min_order=0):
    """→ {order: Σfree_blocks}（全 node/zone 求和）；读不到返回 None。"""
    try:
        per = {}
        with open(path) as f:
            for line in f:
                parts = line.split()
                # "Node 0, zone Normal 4 12 8 ..." → 尾部数字串=各阶空闲块
                nums = [p for p in parts[3:] if p.isdigit()] if len(parts) > 3 else []
                # 容错：某些内核串形为 "Node 0, zone DMA32 1 2 ..."（parts[3:] 全数字）
                for i, v in enumerate(nums):
                    per[i] = per.get(i, 0) + int(v)
        return per or None
    except OSError:
        return None


def read_cgroup_events(cgroup_dir):
    """memory.events → dict；不存在返回 None。"""
    p = os.path.join(cgroup_dir, "memory.events")
    try:
        ev = {}
        with open(p) as f:
            for line in f:
                kv = line.split()
                if len(kv) == 2:
                    ev[kv[0]] = int(kv[1])
        return ev or None
    except OSError:
        return None


def read_flat(path, key=None):
    try:
        with open(path) as f:
            for line in f:
                kv = line.split(":", 1)
                if len(kv) == 2 and kv[0].strip() == key:
                    m = re.match(r"\s*(\d+)", kv[1])
                    return int(m.group(1)) if m else None
    except OSError:
        pass
    return None


def read_nvidia_smi():
    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=index,memory.used",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=10)
        if r.returncode != 0:
            return None
        used = [int(m[1]) for m in re.findall(r"(\d+)\s*,\s*(\d+)", r.stdout)]
        return used or None
    except Exception:
        return None


def cmd_sample(args):
    sink = open(args.out, "a") if args.out else None

    def emit(rec):
        line = json.dumps(rec, ensure_ascii=False)
        if sink:
            sink.write(line + "\n")
            sink.flush()
        else:
            print(line, flush=True)

    n = 0
    while args.iterations <= 0 or n < args.iterations:
        rec = {"ts": time.time(), "type": "tick"}
        per = read_buddy(args.buddy)
        if per is not None:
            high = sum(v for k, v in per.items() if k >= args.buddy_order)
            rec["buddy_high_order_free"] = high
            rec["buddy_per_order"] = [per.get(i, 0)
                                      for i in range(max(per) + 1)]
        ev = read_cgroup_events(args.cgroup_dir) if args.cgroup_dir else None
        if ev is not None:
            rec["cgroup_memory_events"] = ev
            cur = read_flat(os.path.join(args.cgroup_dir, "memory.current"))
            if cur is not None:
                rec["cgroup_memory_current"] = cur
        ma = read_flat(args.meminfo, "MemAvailable")
        if ma is not None:
            rec["mem_available_kb"] = ma
        if args.nvidia_smi:
            g = read_nvidia_smi()
            if g is not None:
                rec["gpu_mem_used_mb"] = g
        emit(rec)
        n += 1
        if args.once or (args.iterations > 0 and n >= args.iterations):
            break
        time.sleep(args.interval)
    if sink:
        sink.close()
        sys.stderr.write("[sample] %d 窗落 %s\n" % (n, args.out))
    return 0


# ───────────────────────────── rows / derive ─────────────────────────────

def load_rows(path):
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def is_dead_signature(row):
    err = (row.get("error") or "")
    return (row.get("status") == "FAIL"
            and ("Remote end closed" in err or "Connection refused" in err))


def cmd_derive(args):
    rows = load_rows(args.rows)
    samples = load_samples(args.samples)
    gpu = [s for s in samples if "gpu_mem_used_mb" in s]
    water = [s for s in samples if "mem_available_kb" in s]
    channel = "gpu" if gpu else ("water-inverted" if water else "none")
    sink = open(args.out, "a") if args.out else None

    def emit(rec):
        line = json.dumps(rec, ensure_ascii=False)
        if sink:
            sink.write(line + "\n")
        else:
            print(line, flush=True)

    for r in rows:
        pt, tot = r.get("prompt_tokens") or 0, r.get("total_s") or 0
        ts = r.get("ts") or 0
        if not pt or not tot or r.get("status") != "PASS":
            continue  # 只对完整 PASS 发做窗口峰值（FAIL 发窗口被死机截断无义）
        lo, hi = ts - tot, ts
        m = min(args.baseline_margin, tot)
        if channel == "gpu":
            base_win = [max(s["gpu_mem_used_mb"]) for s in gpu
                        if lo - m <= s["ts"] < lo]
            win = [max(s["gpu_mem_used_mb"]) for s in gpu
                   if lo <= s["ts"] <= hi]
            if not win:
                continue
            base = sorted(base_win)[len(base_win) // 2] if base_win \
                else min(win)
            delta = (max(win) - base) << 20
        elif channel == "water-inverted":
            base_win = [s["mem_available_kb"] for s in water
                        if lo - m <= s["ts"] < lo]
            win = [s["mem_available_kb"] for s in water
                   if lo <= s["ts"] <= hi]
            if not win:
                continue
            base = sorted(base_win)[len(base_win) // 2] if base_win \
                else max(win)
            delta = (base - min(win)) << 10
        else:
            continue
        emit({"doc_id": r.get("doc_id"), "tier": r.get("phase"),
              "prompt_tokens": pt, "prefill_peak_delta_bytes": delta,
              "budget_bytes": args.budget_bytes, "channel": channel,
              "est_tokens": r.get("est_tokens")})
    if sink:
        sink.close()
    return 0


# ───────────────────────────── a2 ─────────────────────────────

def a2_verdict(records, ratio_band=3.0, headroom_mult=2.0, abs_floor_gib=8.0):
    """→ (green:bool, report:str)。组=同 budget_bytes；红=任一规则破。"""
    if not records:
        return None, "A2 INSUFFICIENT：无记录"
    reasons, greens = [], []
    abs_cap_dyn = max(headroom_mult * max(r["budget_bytes"] for r in records),
                      abs_floor_gib * (1 << 30))
    worst = max(r["prefill_peak_delta_bytes"] for r in records)
    if worst > abs_cap_dyn:
        reasons.append("绝对帽破：最大峰值增量 %.2fGiB > 帽 %.2fGiB（budget×%.1f "
                       "与 %.0fGiB 地板取大）——#39187 前病（无界瞬态）形态"
                       % (worst / (1 << 30), abs_cap_dyn / (1 << 30),
                          headroom_mult, abs_floor_gib))
    else:
        greens.append("绝对帽内：最大峰值增量 %.2fGiB ≤ %.2fGiB"
                      % (worst / (1 << 30), abs_cap_dyn / (1 << 30)))
    by_budget = {}
    for r in records:
        by_budget.setdefault(r["budget_bytes"], []).append(r)
    for b, rs in sorted(by_budget.items()):
        if len(rs) < 2:
            greens.append("预算 %dB 组仅 %d 发——ratio 律样本不足（如实记）"
                          % (b, len(rs)))
            continue
        toks = [r["prompt_tokens"] for r in rs]
        dels = [r["prefill_peak_delta_bytes"] for r in rs]
        span = max(toks) / max(min(toks), 1)
        ratio = max(dels) / max(min(dels), 1)
        if span < 3.0:
            greens.append("预算 %dB 组长度跨 %.1fx<3x——ratio 律跨不足（如实记）"
                          % (b, span))
            continue
        if ratio > ratio_band:
            reasons.append("线性涨破：预算 %dB 组内峰值比 %.1fx > 带 %.1fx"
                           "（长度跨 %.1fx）——随 prompt 总长无界复现"
                           % (b, ratio, ratio_band, span))
        else:
            greens.append("有界：预算 %dB 组峰值比 %.2fx ≤ 带 %.1fx（长度跨 %.1fx）"
                          % (b, ratio, ratio_band, span))
    report = "；".join(greens + reasons)
    return (not reasons), report


def cmd_a2(args):
    records = [json.loads(l) for l in open(args.records) if l.strip()]
    green, report = a2_verdict(records, args.ratio_band, args.headroom_mult,
                               args.abs_floor_gib)
    verdict = "A2 GREEN" if green else ("A2 INSUFFICIENT" if green is None
                                        else "A2 RED")
    print("%s：%s" % (verdict, report))
    return 0 if green else 1


# ───────────────────────────── adjudicate ─────────────────────────────

V2_SIGNATURES = [
    "short or failed direct read",     # row_store.cpp:119 read_from fail()
    "row ID out of bounds",            # row_store.cpp:217
    "invalid table extent",            # row_store.cpp:393
    "packed Engram shard",             # row_store.cpp:463/473
]
V1_SUPPORT = [
    "NV_ERR_NO_MEMORY",
    "CUDA error out of memory",
    "cudaErrorMemoryAllocation",
]


def load_samples(path):
    if not path:
        return []
    with open(path) as f:
        return [json.loads(l) for l in f if l.strip()]


def v1_buddy_collapse(samples, death_ts, baseline_n=5, buddy_order=10,
                      collapse_frac=0.1):
    buddy = [(s["ts"], s["buddy_high_order_free"]) for s in samples
             if "buddy_high_order_free" in s]
    if not buddy:
        return None, "buddy 样本缺失"
    base_win = [v for _, v in buddy[:baseline_n]]
    if len(base_win) < 2 or sum(base_win) < 10:
        return None, "buddy 基线不足（首 %d 窗高阶和<10 或窗数<2）" % baseline_n
    base = sorted(base_win)[len(base_win) // 2]
    pre = [(t, v) for t, v in buddy if death_ts is None or t <= death_ts]
    collapsed = [(t, v) for t, v in pre if v < collapse_frac * base]
    if collapsed:
        return True, ("buddy 高阶(≥order %d)塌陷先于死：基线 %d → %d（%.0f%%），"
                      "首塌点 ts=%.0f" % (buddy_order, base, collapsed[-1][1],
                                          100 * collapsed[-1][1] / max(base, 1),
                                          collapsed[0][0]))
    return False, "buddy 高阶无塌陷（基线 %d，死前最小 %d）" % (
        base, min((v for _, v in pre), default=-1))


def v2_fail_line(log_paths):
    if not log_paths:
        return None, "未供日志——V2=未见（不排除）"
    hits = []
    for p in log_paths:
        try:
            txt = open(p, errors="replace").read()
        except OSError:
            continue
        for sig in V2_SIGNATURES:
            if sig in txt:
                hits.append("%s: %s" % (os.path.basename(p), sig))
    if hits:
        return True, "row_store fail 签中：%s" % "; ".join(hits)
    return False, ("日志无 fail 签（注：V2 探针完整性依赖 row_store fail() 落盘"
                   "补丁（A §6.2 F5）+容器日志保留（F8）——未装则「未见」≠「排除」）")


def v3_oom_kill(samples):
    evs = [(s["ts"], s.get("cgroup_memory_events", {}).get("oom_kill", 0))
           for s in samples if "cgroup_memory_events" in s]
    if not evs:
        return None, "cgroup memory.events 样本缺失（V3=未见）"
    base, peak = evs[0][1], max(v for _, v in evs)
    if peak > base:
        return True, "oom_kill %d→%d（+Δ）" % (base, peak)
    return False, "oom_kill 恒 %d" % base


def c_flow_verdict(alive_pass, a2_green, v1, v2, v3, details):
    lines = []
    if alive_pass:
        lines.append("【C 流除名】563k/573k est 单发存活 PASS——C-#36941/#39187 "
                     "无界索引瞬态流正式除名（对 KV-V41B rows.jsonl:8 X5121 "
                     "PASS 复验同形闭合，设计稿 §五 A6 首支）")
    else:
        if a2_green is True:
            lines.append("【A-V1/A-V2 升权】死且 A2 绿 ⇒ 死因确在索引器外"
                         "（设计稿 §五 A6 末支）")
        elif a2_green is False:
            lines.append("【C 流复活】死且 A2 红 ⇒ 索引器瞬态载体成立——W2 呈裁")
        else:
            lines.append("【A2 缺】无 A2 记录——升权/复活均不定，补 A2 记录再裁")
    for name, v in (("V1", v1), ("V2", v2), ("V3", v3)):
        if v is True:
            lines.append("【%s 坐实】%s" % (name, details[name]))
        elif v is False:
            lines.append("【%s 未见】%s" % (name, details[name]))
        else:
            lines.append("【%s 探针缺】%s" % (name, details[name]))
    if (not alive_pass) and v1 is not True and v2 is not True and v3 is not True:
        lines.append("【升级支】三探针皆无信号而头死——按 A §3.3 读判第 4 支升级采 "
                     "core/UMA dump（V2 完整性先补 F5 fail 行补丁再重放）")
    return "\n".join(lines)


def cmd_adjudicate(args):
    rows = load_rows(args.rows)
    target = [r for r in rows if not args.death_doc
              or r.get("doc_id") == args.death_doc]
    dead_rows = [r for r in target if is_dead_signature(r)]
    alive = [r for r in target if r.get("status") == "PASS"]
    if not target:
        print("RED：rows 中无目标文档（--death-doc=%s）" % args.death_doc)
        return 2
    alive_pass = bool(alive) and not dead_rows
    death_ts = None
    if dead_rows and alive_pass is False:
        death_ts = max(r.get("ts") or 0 for r in dead_rows)
    samples = load_samples(args.samples)
    v1, d1 = v1_buddy_collapse(samples, death_ts, args.baseline_n,
                               args.buddy_order, args.collapse_frac)
    v2, d2 = v2_fail_line(args.logs)
    v3, d3 = v3_oom_kill(samples)
    a2_green = None
    if args.a2_records:
        recs = [json.loads(l) for l in open(args.a2_records) if l.strip()]
        a2_green, rep = a2_verdict(recs, args.ratio_band, args.headroom_mult,
                                   args.abs_floor_gib)
        print("A2：%s" % rep)
    print("死活：%s（alive_pass=%s death_ts=%s）"
          % ("死" if dead_rows else "活", alive_pass, death_ts))
    print(c_flow_verdict(alive_pass, a2_green, v1, v2, v3,
                         {"V1": d1, "V2": d2, "V3": d3}))
    return 0


# ───────────────────────────── selfcheck ─────────────────────────────

def _write(path, lines):
    with open(path, "w") as f:
        for l in lines:
            f.write((l if isinstance(l, str) else json.dumps(l)) + "\n")


def cmd_selfcheck(_args):
    tmp = tempfile.mkdtemp(prefix="w2a2a6_")
    now = time.time()

    # ── A2 三向 ──
    recs_green = [
        {"doc_id": "A", "tier": "ladder", "prompt_tokens": 128000,
         "prefill_peak_delta_bytes": 1 << 30, "budget_bytes": 134217728},
        {"doc_id": "B", "tier": "ladder", "prompt_tokens": 300000,
         "prefill_peak_delta_bytes": 1100000000, "budget_bytes": 134217728},
        {"doc_id": "C", "tier": "ladder", "prompt_tokens": 596000,
         "prefill_peak_delta_bytes": 1200000000, "budget_bytes": 134217728},
    ]
    g, rep = a2_verdict(recs_green)
    check("sc-a2-green", g is True, rep)
    recs_linear = [dict(recs_green[0]),
                   {"doc_id": "B", "tier": "ladder", "prompt_tokens": 300000,
                    "prefill_peak_delta_bytes": 2200000000,
                    "budget_bytes": 134217728},
                   {"doc_id": "C", "tier": "ladder", "prompt_tokens": 596000,
                    "prefill_peak_delta_bytes": 48 << 29,
                    "budget_bytes": 134217728}]
    g, rep = a2_verdict(recs_linear)
    check("sc-a2-red-linear", g is False and "线性涨破" in rep, rep)
    recs_abs = [dict(recs_green[0]),
                {"doc_id": "C", "tier": "ladder", "prompt_tokens": 596000,
                 "prefill_peak_delta_bytes": 30 << 30,
                 "budget_bytes": 134217728}]
    g, rep = a2_verdict(recs_abs)
    check("sc-a2-red-abs", g is False and "绝对帽破" in rep, rep)
    g, rep = a2_verdict([recs_green[0]])
    check("sc-a2-insufficient-single", g is True and "样本不足" in rep,
          "单发=带内但不裁 ratio 律（如实记）：%s" % rep)
    g, rep = a2_verdict([])
    check("sc-a2-insufficient-empty", g is None)

    # ── V1 有牙/无假阳 ──
    stable = [{"ts": now - 600 + i * 30, "buddy_high_order_free": 100 + i}
              for i in range(8)]
    collapse = ([{"ts": now - 600 + i * 30, "buddy_high_order_free": 100}
                 for i in range(5)]
                + [{"ts": now - 450 + i * 30, "buddy_high_order_free": 3}
                   for i in range(5)])
    v1, d = v1_buddy_collapse(collapse, death_ts=now)
    check("sc-v1-fires", v1 is True, d)
    v1, d = v1_buddy_collapse(stable, death_ts=now)
    check("sc-v1-teeth-no-false-positive", v1 is False, d)
    v1, d = v1_buddy_collapse([], death_ts=now)
    check("sc-v1-missing-samples", v1 is None)

    # ── V2 签名 grep ──
    log_bad = os.path.join(tmp, "worker.docker.log")
    _write(log_bad, ["[rank0] row_store: short or failed direct read",
                     "terminate called after throwing"])
    log_clean = os.path.join(tmp, "head.docker.log")
    _write(log_clean, ["[2026-10-10 00:31:02] healthy tick"])
    v2, d = v2_fail_line([log_bad, log_clean])
    check("sc-v2-fires", v2 is True, d)
    v2, d = v2_fail_line([log_clean])
    check("sc-v2-clean-log", v2 is False)
    v2, d = v2_fail_line(None)
    check("sc-v2-no-logs-honest", v2 is None and "未见" in d)

    # ── V3 ──
    ev = [{"ts": now - 60, "cgroup_memory_events": {"oom_kill": 0}},
          {"ts": now - 30, "cgroup_memory_events": {"oom_kill": 1}}]
    v3, d = v3_oom_kill(ev)
    check("sc-v3-fires", v3 is True, d)
    v3, d = v3_oom_kill([])
    check("sc-v3-missing", v3 is None)

    # ── A6 终裁四支（合成 rows）──
    rows_alive = [{"doc_id": "L0021", "status": "PASS", "error": None,
                   "ts": now, "total_s": 300.0, "prompt_tokens": 380000}]
    rows_dead = [{"doc_id": "L0021", "status": "FAIL",
                  "error": "Remote end closed connection without response",
                  "ts": now, "total_s": None, "prompt_tokens": 0}]
    rpath = lambda n: os.path.join(tmp, n)
    _write(rpath("rows_alive.jsonl"), rows_alive)
    _write(rpath("rows_dead.jsonl"), rows_dead)
    spath = os.path.join(tmp, "s.jsonl")
    _write(spath, [])
    a2r = os.path.join(tmp, "a2.jsonl")
    _write(a2r, recs_green)

    v = c_flow_verdict(True, True, False, False, False,
                       {"V1": "-", "V2": "-", "V3": "-"})
    check("sc-a6-alive-names-C", "C 流除名" in v and "X5121" in v)
    v = c_flow_verdict(False, True, False, False, False,
                       {"V1": "-", "V2": "-", "V3": "-"})
    check("sc-a6-dead-green-escalates", "A-V1/A-V2 升权" in v and "升级支" in v)
    v = c_flow_verdict(False, False, None, None, None,
                       {"V1": "-", "V2": "-", "V3": "-"})
    check("sc-a6-dead-red-revives-C", "C 流复活" in v)
    v = c_flow_verdict(False, True, True, False, False,
                       {"V1": "buddy 塌陷在档", "V2": "-", "V3": "-"})
    check("sc-a6-dead-v1-pinned", "V1 坐实" in v and "升级支" not in v)

    # ── sample --once 实跑（真 /proc 只读；cgroup 用合成目录）──
    cg = os.path.join(tmp, "cg")
    os.makedirs(cg, exist_ok=True)
    _write(os.path.join(cg, "memory.events"), ["oom_kill 0", "pgmajfault 12"])
    _write(os.path.join(cg, "memory.current"), ["123456789"])
    sm = os.path.join(tmp, "once.jsonl")
    rc = subprocess.run(
        [sys.executable, os.path.abspath(__file__), "sample", "--out", sm,
         "--once", "--cgroup-dir", cg],
        capture_output=True, text=True, env=dict(os.environ))
    ok = rc.returncode == 0 and os.path.exists(sm)
    if ok:
        first = json.loads(open(sm).read().splitlines()[0])
        ok = "ts" in first and "buddy_high_order_free" in first \
            and first.get("cgroup_memory_events", {}).get("oom_kill") == 0
    check("sc-sample-once-live-proc", ok,
          "真 /proc/buddyinfo 只读采样+合成 cgroup 联通（rc=%s）" % rc.returncode)

    # ── derive 链（合成 gpu 样本+PASS rows → 记录文件）──
    gpu_s = os.path.join(tmp, "g.jsonl")
    _write(gpu_s, [
        {"ts": now - 400, "gpu_mem_used_mb": [20000]},
        {"ts": now - 200, "gpu_mem_used_mb": [24000]},   # 窗内峰
        {"ts": now - 10, "gpu_mem_used_mb": [20500]},
    ])
    drv = os.path.join(tmp, "drv.jsonl")
    rc = subprocess.run(
        [sys.executable, os.path.abspath(__file__), "derive",
         "--samples", gpu_s, "--rows", rpath("rows_alive.jsonl"),
         "--budget-bytes", "134217728", "--out", drv],
        capture_output=True, text=True, env=dict(os.environ))
    lines = [l for l in open(drv).read().splitlines() if l.strip()] \
        if os.path.exists(drv) else []
    ok = rc.returncode == 0 and len(lines) == 1
    if ok:
        rec = json.loads(lines[0])
        ok = (rec["prompt_tokens"] == 380000
              and rec["prefill_peak_delta_bytes"] == (4000 << 20)
              and rec["channel"] == "gpu")
    check("sc-derive-window-peak", ok,
          "窗口峰-谷差=(24000-20000)MiB=%sB" %
          ((4000 << 20) if ok else "?"))

    print("=" * 64)
    if FAILS:
        print("SELFCHECK RED：%d 项失败：%s" % (len(FAILS), FAILS))
        return 1
    print("SELFCHECK GREEN：18 检全过（A2 三向/V1-V3 牙向/A6 四支/sample/derive）")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("sample")
    p.add_argument("--out", required=True)
    p.add_argument("--interval", type=float, default=30.0)
    p.add_argument("--iterations", type=int, default=0, help="0=不限（Ctrl-C 止）")
    p.add_argument("--once", action="store_true")
    p.add_argument("--buddy", default="/proc/buddyinfo")
    p.add_argument("--buddy-order", type=int, default=10)
    p.add_argument("--cgroup-dir", default=None)
    p.add_argument("--meminfo", default="/proc/meminfo")
    p.add_argument("--nvidia-smi", action="store_true")
    p.set_defaults(func=cmd_sample)

    p = sub.add_parser("derive")
    p.add_argument("--samples", required=True)
    p.add_argument("--rows", required=True)
    p.add_argument("--budget-bytes", type=int, default=134217728)
    p.add_argument("--baseline-margin", type=float, default=120.0,
                   help="发前基线窗秒数（缺省 120；取窗内中位）")
    p.add_argument("--out", default=None, help="缺省打 stdout")
    p.set_defaults(func=cmd_derive)

    p = sub.add_parser("a2")
    p.add_argument("--records", required=True)
    p.add_argument("--ratio-band", type=float, default=3.0)
    p.add_argument("--headroom-mult", type=float, default=2.0)
    p.add_argument("--abs-floor-gib", type=float, default=8.0)
    p.set_defaults(func=cmd_a2)

    p = sub.add_parser("adjudicate")
    p.add_argument("--rows", required=True)
    p.add_argument("--samples", default=None)
    p.add_argument("--logs", nargs="*", default=None)
    p.add_argument("--a2-records", default=None)
    p.add_argument("--death-doc", default=None)
    p.add_argument("--ratio-band", type=float, default=3.0)
    p.add_argument("--headroom-mult", type=float, default=2.0)
    p.add_argument("--abs-floor-gib", type=float, default=8.0)
    p.add_argument("--baseline-n", type=int, default=5)
    p.add_argument("--buddy-order", type=int, default=10)
    p.add_argument("--collapse-frac", type=float, default=0.1)
    p.set_defaults(func=cmd_adjudicate)

    p = sub.add_parser("selfcheck")
    p.set_defaults(func=cmd_selfcheck)

    args = ap.parse_args()
    rc = 0
    try:
        rc = args.func(args)
    except KeyboardInterrupt:
        rc = 130
    sys.exit(rc or 0)


if __name__ == "__main__":
    main()
