#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pr_degrade_probe_draft.py — 「靴内劣化曲线」探针【草案 v2，未实跑】.

归属：docs/research/PR-ANCHOR-CONTAMINATION-AUDIT-20261009.md §四.4（2026-10-09 审计
交付三的量具草案）。设计动机=KV-V41 靴实证「真文本 prefill 靴内渐进劣化（累积 ~500k
后崩至 ~600-880 tok/s，跨 /flush_cache 不可逆）」vs KV-V41B 复靴 0→1.6M 全程平坦——
劣化是真文本载荷下的靴级事件，需要一把能在修复窗内量化「速率~靴内累积」曲线的量具。

口径纪律（与审计档 §〇/§四.2 一致）：
  - filler=sd_bench `real` 档（sd_bench_real_text.patch 已应用 01b0356；行级唯一、
    无相邻重复、真实分布——MiaAI-Lab#21 行缓存膨胀面免疫）；
  - 速率=usage.prompt_tokens/TTFT（服务端 usage 基，链 A；禁用 calib 5.442 换算——
    该密度先验被 ×24 重复句自污染，审计档 §〇.2）；
  - fresh salt 逐发（sd_bench PR 内建 uuid/发）；**全程不 flush**——测的就是靴内累积
    效应，flush 反而抹掉被测量（KV-V41 实证 flush 也不可逆，更无理由 flush）；
  - 单发串行（禁并发：KV-V41 prep1 突发相教训——并发批表观速率不可作单流锚）。

探针形态：固定 32k 档（平台区、成本中位），每靴内累积 +250k tokens 复发一轮（3 发
取中位），至 ~3M（12 轮）。每轮记 {round, cum_tokens_before, tok_s_med, ttft_med,
cpt_med, kv_available, water_m, boot_age_s}。判读门（审计档 §四.3）：任意相邻两轮
−15% 或首轮→末轮 −25% =RED（劣化复现）；V4.1B 型健康靴预期全程 3.8-4.2k 平坦。
兼任「快相裁决器」：任何 fresh 靴首轮真文本 32k >4.4k ⇒ KV-V41 快相升级为可复现
现象（6000t 条件线激活面）。

安全阀：DRY_RUN 缺省真（只打计划不发包，--exec 显式解）；8899 产线硬拒（prl6 同律）；
逐发 subprocess timeout 护栏；水位哨兵对齐 agg600k_p2_probe 程序（MemAvailable <
abort_line 即 POST /abort_request 收束）。运行前置=专用读数靴（一靴一锚新鲜律：
--boot-end 锚 BOOT-END 时刻，逐轮记 boot_age_s），BASE 指 8898 测试口。

v2 修订（F-6a.3 案头审校，2026-10-09；DRY 缺省真不变、零实跑）：
  1. 8899 硬拒门落码（v1 头注声称无实现）；
  2. base 双消费面拆分：sd_bench 需 /v1 路由（缺省 :8898/v1），哨兵 abort 用 root
     （agg600k_p2_probe/c16 WaterSentry 同程序用 root /abort_request）；
  3. 行级 cpt 记录位修复：v1 读 `chars_per_token` 键在 sd_bench PR 行不存在（恒
     None 静默）——sd_bench 侧已补 prompt_chars/chars_per_token 两键（引擎仓
     901d9f7，selfcheck 复证 21/21），探针侧全键 .get 容忍（行键集完备律：缺键=
     None 如实记，不炸不猜）；
  4. 失败发/400 拒绝行处理：失败发记 {"shot":n,"error":"rc=X|timeout|no-json"}
     非 bare None；轮记录加 failed 计数（D-1 c16 被拒行 KeyError 教训——本探针
     零 KeyError 面）；
  5. 逐发 timeout（缺省 900s，--step-timeout）防失控长跑（prl6 同护栏）；
  6. 一靴一锚新鲜律参数面：--boot-end（epoch 或 ISO-8601 UTC）→ 逐轮 boot_age_s；
     轮记录补 ttft_med/cpt_med/kv_available（metrics best-effort）/water_m
     （v1 头注承诺未落码的记录位）；
  7. 斜率门改 in-run 中位序列（v1 重读整个 ledger 会跨 run 混账）；补首末 −25% 门；
  8. cum 推进估算标记 cum_est（全发失败按步长推进时如实记）；
  9. run_start 账首行（参数+argv+ts，多 run 追加可分账）；--dry-run 死旗修为可显式
     置 dry（v1 store_true default=True 为不可操作的装饰旗）。
"""
import argparse
import datetime as _dt
import json
import os
import statistics
import subprocess
import sys
import threading
import time
import urllib.request

SIZES = ["32768"]                 # 固定档（平台区）
SHOTS_PER_ROUND = 3               # 每轮 3 发取中位
STEP_TOKENS = 250_000             # 每累积 +250k 复发一轮
MAX_ROUNDS = 12                   # ~3M 封顶
WARMUP = 512                      # sd_bench 每档 512-token warmup（口径内建）
ABORT_LINE_M = 6000               # 水位哨兵线（对齐 KV-LIFE qamemguard floor）
DEFAULT_STEP_TIMEOUT_S = 900      # 逐发 subprocess timeout（prl6 同护栏）
SDBENCH = os.path.expanduser("~/dsv41-flash-dgxsparks/bench/sd_bench.py")


def root_of(base: str) -> str:
    """sd_bench 面 base（…/v1）→ 引擎原生 root（/abort_request、/metrics 所在）。"""
    b = base.rstrip("/")
    return b[: -len("/v1")] if b.endswith("/v1") else b


class Sentry(threading.Thread):
    """agg600k_p2_probe.py:29-68 同程序（水位哨兵；跌破即 abort_all 收束）。"""

    def __init__(self, base, abort_m, sample_s=1.0):
        super().__init__(daemon=True)
        self.base, self.abort_m, self.sample_s = base, abort_m, sample_s
        self.before = self.lowest = self.read_m()
        self.aborted = False
        self.stop = threading.Event()

    def read_m(self):
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemAvailable:"):
                        return int(line.split()[1]) // 1024
        except OSError:
            return None
        return None

    def abort_all(self):
        if self.aborted:
            return
        self.aborted = True
        try:
            req = urllib.request.Request(self.base + "/abort_request",
                                         data=json.dumps({"abort_all_requests": True}).encode(),
                                         headers={"Content-Type": "application/json"}, method="POST")
            urllib.request.urlopen(req, timeout=30).read()
        except Exception:
            pass

    def run(self):
        while not self.stop.is_set():
            m = self.read_m()
            if m is not None:
                if self.lowest is None or m < self.lowest:
                    self.lowest = m
                if m < self.abort_m:
                    self.abort_all()
                    return
            self.stop.wait(self.sample_s)


def sample_kv(root: str):
    """kv_available 记录位（best-effort）：GET /metrics 抓 kv 族指标；未命中=None 如实记。"""
    try:
        with urllib.request.urlopen(root + "/metrics", timeout=5) as r:
            txt = r.read().decode(errors="replace")
    except Exception:
        return None
    out = {}
    for ln in txt.splitlines():
        if ln.startswith("#") or "kv" not in ln.lower():
            continue
        key, _, val = ln.partition(" ")
        try:
            out[key.strip()] = float(val.strip())
        except ValueError:
            continue
    return out or None


def parse_boot_end(s):
    """--boot-end：epoch 秒或 ISO-8601（UTC 语义，与 boot 日志 Z 戳同锚）。"""
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        pass
    try:
        t = s.replace("Z", "+00:00")
        return _dt.datetime.fromisoformat(t).timestamp()
    except ValueError:
        raise SystemExit(f"ABORT: --boot-end 无法解析（epoch 或 ISO-8601）: {s!r}")


def run_round(base, outdir, rnd_i, cum_before, dry, step_timeout_s):
    """一轮=3 发 sd_bench real 档调用（--runs 在 pr 模式被忽略→每调用=1 暖+1 测）。"""
    shots, failed = [], 0
    for s in range(SHOTS_PER_ROUND):
        shot_no = s + 1
        json_out = os.path.join(outdir, f"r{rnd_i:02d}_shot{shot_no}.json")
        cmd = [sys.executable, SDBENCH, "--base-url", base, "--key-file", "/dev/null",
               "--mode", "pr", "--pr-filler", "real", "--sizes", *SIZES,
               "--label", f"degrade-r{rnd_i:02d}-s{shot_no}", "--json-out", json_out]
        print(f"[round {rnd_i}] cum_before={cum_before:,} shot {shot_no}/{SHOTS_PER_ROUND}: "
              f"{'DRY ' if dry else ''}{' '.join(cmd)}", flush=True)
        if dry:
            shots.append(None)          # dry=计划位（区别于失败发）
            continue
        try:
            rc = subprocess.call(cmd, timeout=step_timeout_s)
        except subprocess.TimeoutExpired:
            shots.append({"shot": shot_no, "error": f"timeout>{step_timeout_s}s"})
            failed += 1
            continue
        if rc != 0:
            shots.append({"shot": shot_no, "error": f"rc={rc}"})   # 400 拒绝/连接败→rc≠0
            failed += 1
            continue
        if not os.path.exists(json_out):
            shots.append({"shot": shot_no, "error": "no-json"})
            failed += 1
            continue
        try:
            d = json.load(open(json_out))
        except (OSError, json.JSONDecodeError) as e:
            shots.append({"shot": shot_no, "error": f"bad-json:{type(e).__name__}"})
            failed += 1
            continue
        row = (d.get("pr") or [None])[0] if isinstance(d, dict) else None
        if not row:
            shots.append({"shot": shot_no, "error": "no-pr-row"})
            failed += 1
            continue
        # 行键集完备律：全键 .get，缺键=None 如实记（chars_per_token 需 sd_bench≥901d9f7）
        shots.append({"shot": shot_no,
                      "prompt_tokens": row.get("prompt_tokens"),
                      "ttft_s": row.get("ttft_s"),
                      "tok_s": row.get("tok_s"),
                      "chars_per_token": row.get("chars_per_token"),
                      "filler": row.get("filler")})
    return shots, failed


def main():
    ap = argparse.ArgumentParser(description="靴内劣化曲线探针（草案 v2；DRY 缺省真）")
    ap.add_argument("--base", default="http://127.0.0.1:8898/v1",
                    help="sd_bench 面 base（OpenAI /v1 路由；哨兵自动剥 /v1 用 root）")
    ap.add_argument("--outdir", required=True, help="窗档 bench 目录（勿写 KV-LIFE 在飞窗）")
    ap.add_argument("--dry-run", dest="go", action="store_false",
                    help="显式置 dry（缺省即 dry；与 --exec 互斥以后者为准）")
    ap.add_argument("--exec", dest="go", action="store_true",
                    help="显式解 dry 真跑（本草案不启动）")
    ap.add_argument("--step-timeout", type=int, default=DEFAULT_STEP_TIMEOUT_S,
                    help="逐发 subprocess timeout 秒（缺省 900）")
    ap.add_argument("--boot-end", default=None,
                    help="BOOT-END 锚（epoch 秒或 ISO-8601 UTC）——一靴一锚新鲜律靴龄记录位")
    ap.set_defaults(go=False)               # DRY_RUN 缺省真
    args = ap.parse_args()
    dry = not args.go

    if "8899" in args.base:
        print(f"ABORT: --base 含 8899（生产口，G5 绝对隔离）: {args.base}", file=sys.stderr)
        sys.exit(5)
    if not os.path.isfile(SDBENCH):
        print(f"ABORT: 缺 {SDBENCH}", file=sys.stderr)
        sys.exit(5)

    boot_end = parse_boot_end(args.boot_end)
    os.makedirs(args.outdir, exist_ok=True)
    ledger_path = os.path.join(args.outdir, "degrade_probe.jsonl")
    root = root_of(args.base)

    sentry = Sentry(root, ABORT_LINE_M)
    if not dry:
        sentry.start()

    # run_start 账首行（多 run 追加 ledger 可分账）
    rec0 = {"run_start": True, "ts": round(time.time(), 1), "dry": dry,
            "base": args.base, "boot_end": boot_end, "sdbench": SDBENCH,
            "plan": {"size": SIZES[0], "shots_per_round": SHOTS_PER_ROUND,
                     "step_tokens": STEP_TOKENS, "max_rounds": MAX_ROUNDS,
                     "abort_line_m": ABORT_LINE_M, "step_timeout_s": args.step_timeout},
            "argv": sys.argv[1:]}
    with open(ledger_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec0, ensure_ascii=False) + "\n")

    cum = 0
    rnd_i = 0
    meds = []                                # 本 run 内中位序列（斜率门用；禁跨 run 混账）
    print(f"[plan] size={SIZES[0]} shots/round={SHOTS_PER_ROUND} step=+{STEP_TOKENS:,} "
          f"max_rounds={MAX_ROUNDS} dry={dry} boot_end={boot_end}", flush=True)
    while rnd_i < MAX_ROUNDS:
        shots, failed = run_round(args.base, args.outdir, rnd_i + 1, cum, dry, args.step_timeout)
        tok = [s["tok_s"] for s in shots if s and s.get("tok_s")]
        ttfts = [s["ttft_s"] for s in shots if s and s.get("ttft_s") is not None]
        cpts = [s["chars_per_token"] for s in shots if s and s.get("chars_per_token")]
        med = round(statistics.median(tok), 1) if tok else None
        ttft_med = round(statistics.median(ttfts), 3) if ttfts else None
        cpt_med = round(statistics.median(cpts), 3) if cpts else None
        added = sum((s or {}).get("prompt_tokens") or 0 for s in shots)
        cum_est = not added
        rec = {"round": rnd_i + 1, "cum_tokens_before": cum, "tok_s_med": med,
               "ttft_med": ttft_med, "cpt_med": cpt_med, "failed_shots": failed,
               "shots": shots, "ts": round(time.time(), 1), "dry": dry,
               "water_m": sentry.read_m(),
               "kv_available": (sample_kv(root) if not dry else None)}
        rec["boot_age_s"] = (round(rec["ts"] - boot_end, 1) if boot_end else None)
        with open(ledger_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        print(f"[round {rnd_i+1}] cum_before={cum:,} tok_s_med={med} ttft_med={ttft_med} "
              f"cpt_med={cpt_med} added={added:,}{'+est' if cum_est else ''} failed={failed} "
              f"water={rec['water_m']}M", flush=True)
        cum += added or STEP_TOKENS          # dry 态/全败按步长推进（cum_est 如实记）
        rnd_i += 1
        if med is not None:
            meds.append(med)
        if sentry.aborted:
            print("[sentry] 水位 abort——收束", flush=True)
            break
        if len(meds) >= 2:
            # 就地早停门（正式判读以审计档 §四.3 斜率门离线拟合为准）：
            # 相邻轮 −15% 或 首轮→本轮 −25% = RED
            if meds[-1] / meds[-2] < 0.85:
                print(f"[GATE-RED] 相邻轮 −{(1 - meds[-1] / meds[-2]) * 100:.1f}% ≥15% ⇒ 劣化复现", flush=True)
                break
            if meds[0] and meds[-1] / meds[0] < 0.75:
                print(f"[GATE-RED] 首末 −{(1 - meds[-1] / meds[0]) * 100:.1f}% ≥25% ⇒ 劣化复现", flush=True)
                break
    sentry.stop.set()
    print(json.dumps({"done": True, "rounds": rnd_i, "cum": cum, "ledger": ledger_path,
                      "water": {"before_m": sentry.before, "lowest_m": sentry.lowest,
                                "aborted": sentry.aborted}}))


if __name__ == "__main__":
    main()
