#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""c16_600k_driver — C16×600K 压测驱动器（设计卡 §六实现，2026-10-01）。

与 needle_probe 的差异（勿复用其发包）：客户端 T×L 门参数化（--tl-budget，镜像
admission_gate 律 limit=budget//4096）；流式采 TTFT（16 发齐射⇒调度器天然串行 prefill，
断言 TTFT 阶梯单调）；1s 水位哨兵 <阈值 即 POST /abort_request 全中止；HTTP timeout ≥5400s
（MIA P4 律：600k 档 TTFT ~数分钟-小时级，600s 必超）。

三臂：probe=单条先遣；a=16×596k+2k 生成位（主案，池 9.6M 余 32k）；b=15×600k（备案）。
自测：python3 tools/c16_600k_driver.py --selfcheck（离线，不发包）

D-1 修复（2026-10-09 案头批；RATIFY §八 异常②+READINGS :90/:187；FIXCAMPAIGN-
OPENITEMS-CONSOLIDATION D-1）：被拒行（400 拒绝/超时/异常）容错——汇总面全键 .get
（行键集完备律：拒绝行无 prompt_tokens 键⇒计 est_tokens，不炸不猜）；异常行错误记
{status:SKIP, error:rc=X|timeout|原文}（对齐劣化探针 v2 的 400 行处理面
pr_degrade_probe_draft.py 3796b9f）+汇总加 n_rejected 计数；selfcheck 增构造 400
响应样本自验（喂 HTTPError(400) 证拒绝行不再炸；零实跑）。
"""
import argparse
import json
import os
import random
import re
import sys
import threading
import time
import urllib.error
import urllib.request

WORDS = ("time year people way day man thing woman life child world school state "
         "family student group country problem hand part place case week company "
         "system program question work government number night point home water "
         "room mother area money story fact month lot right study book eye job "
         "word business issue side kind head house service friend father power "
         "hour game line end member law car city community name president team "
         "minute idea kid body information back parent face others level office "
         "door health person art war history girl guy moment air teacher force "
         "education foot boy age policy").split()


def estimate_tokens(s: str) -> int:
    return max(1, (len(s) + 3) // 4)


def make_filler(seed: str, target_tokens: int) -> str:
    rng = random.Random(f"c16:{seed}")
    out, n = [], 0
    target_chars = target_tokens * 4
    while n < target_chars:
        w = WORDS[rng.randrange(len(WORDS))]
        out.append(w)
        n += len(w) + 1
    return " ".join(out)


def build_prompt(target_tokens: int, seed: str, depth: float):
    """needle 式 prompt，魔码句埋 depth。返回 (prompt, magic)。"""
    rng = random.Random(f"magic:{seed}")
    magic = "%08x" % rng.getrandbits(32)
    header = (f"[c16-600k {seed}]\nBelow is a long document. "
              "After reading it, answer the final question briefly.\n\n")
    footer = ("\n\nQuestion: What is the magic code hidden in the document above? "
              "Answer with the code only.")
    needle = f"\nThe magic code for this session is {magic}. Remember it.\n"
    fill_tokens = max(1, target_tokens - estimate_tokens(header + footer + needle) - 8)
    body = make_filler(seed, fill_tokens)
    cut = int(len(body) * depth)
    prompt = header + body[:cut] + needle + body[cut:] + footer
    return prompt, magic


def calibrate(target_tokens, seed, depth, tol=0.003):
    """把 est 收进 target±0.3%：过量则按词尾裁剪，欠则补。"""
    prompt, magic = build_prompt(target_tokens, seed, depth)
    est = estimate_tokens(prompt)
    lo, hi = int(target_tokens * (1 - tol)), int(target_tokens * (1 + tol))
    if lo <= est <= hi:
        return prompt, magic, est
    delta_chars = (target_tokens - est) * 4
    if delta_chars < 0:  # 裁剪：从尾部按词界剪，保持 footer
        idx = prompt.rfind(footer)
        body_head = prompt[:idx]
        keep = len(body_head) + delta_chars
        cut_at = prompt.rfind(" ", 0, max(keep, 1))
        prompt = prompt[:cut_at] + footer
    else:
        idx = prompt.rfind(footer)
        extra = make_filler(seed + "-pad", delta_chars // 4 + 1)
        prompt = prompt[:idx] + " " + extra + prompt[idx:]
    return prompt, magic, estimate_tokens(prompt)


class WaterSentry(threading.Thread):
    """1s 采样 MemAvailable；<阈值 → abort_all（幂等）。"""

    def __init__(self, base, abort_m, sample_s=1.0):
        super().__init__(daemon=True)
        self.base, self.abort_m, self.sample_s = base, abort_m, sample_s
        self.lowest = None
        self.before = None
        self.aborted = False
        self.stop = threading.Event()
        self.samples = 0

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
            req = urllib.request.Request(
                self.base.rstrip("/") + "/abort_request",
                data=json.dumps({"abort_all_requests": True}).encode(),
                headers={"Content-Type": "application/json"}, method="POST")
            urllib.request.urlopen(req, timeout=30).read()
        except Exception:
            pass

    def run(self):
        self.before = self.read_m()
        self.lowest = self.before
        while not self.stop.is_set():
            m = self.read_m()
            if m is not None:
                self.samples += 1
                if self.lowest is None or m < self.lowest:
                    self.lowest = m
                if m < self.abort_m:
                    self.abort_all()
                    return
            self.stop.wait(self.sample_s)


def ask_stream(base, prompt, model, max_tokens, timeout):
    """流式请求；返回 (text, prompt_tokens, completion_tokens, ttft_s, total_s)。"""
    payload = {"model": model, "messages": [{"role": "user", "content": prompt}],
               "max_tokens": max_tokens, "temperature": 0.0, "stream": True}
    req = urllib.request.Request(base.rstrip("/") + "/v1/chat/completions",
                                 data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    ttft = None
    chunks = []
    pt = ct = 0
    with urllib.request.urlopen(req, timeout=timeout) as r:
        for raw in r:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data: "):
                continue
            data = line[6:]
            if data == "[DONE]":
                break
            try:
                obj = json.loads(data)
            except ValueError:
                continue
            u = obj.get("usage") or {}
            pt = u.get("prompt_tokens", pt)
            ct = u.get("completion_tokens", ct)
            for ch in obj.get("choices", []):
                delta = (ch.get("delta") or {}).get("content") or ""
                if delta:
                    if ttft is None:
                        ttft = time.time() - t0
                    chunks.append(delta)
    return "".join(chunks), pt, ct, ttft, time.time() - t0


def err_tag(e) -> str:
    """D-1：异常→拒绝行错误结构 rc=X|timeout|原文截断（对齐探针 v2 的 {shot,error} 处理面）。"""
    if isinstance(e, urllib.error.HTTPError):
        return f"rc={e.code}"
    if isinstance(e, TimeoutError):
        return "timeout"
    return str(e)[:200]


def agg_prompt_tokens(rows) -> int:
    """D-1：行键集完备律——全键 .get；拒绝行无 prompt_tokens 键⇒计 est_tokens（不炸不猜）。"""
    return sum(r.get("prompt_tokens") or r.get("est_tokens") for r in rows if r)


def run_arm(base, model, arm, prompt_tokens, gen_tokens, concurrency, depths,
            seed0, tl_budget, http_timeout, sentry):
    limit = tl_budget // 4096
    n = 1 if arm == "probe" else concurrency
    reqs = []
    for i in range(n):
        depth = depths[i % len(depths)]
        seed = f"{seed0}-{i}"
        prompt, magic, est = calibrate(prompt_tokens, seed, depth)
        if est > limit:
            return {"status": "SKIP",
                    "reason": f"客户端 T×L 门：est {est} > limit {limit}（tl_budget={tl_budget}）"}
        reqs.append({"i": i, "seed": seed, "depth": depth, "prompt": prompt,
                     "magic": magic, "est": est})
    results = [None] * n
    lock = threading.Lock()

    def worker(r):
        try:
            txt, pt, ct, ttft, tot = ask_stream(base, r["prompt"], model,
                                                gen_tokens, http_timeout)
            hit = r["magic"].lower() in (txt or "").lower()
            with lock:
                results[r["i"]] = {
                    "i": r["i"], "seed": r["seed"], "depth": r["depth"],
                    "est_tokens": r["est"], "magic": r["magic"],
                    "prompt_tokens": pt, "completion_tokens": ct,
                    "ttft_s": round(ttft, 1) if ttft else None,
                    "total_s": round(tot, 1),
                    "decode_tps": round(ct / (tot - ttft), 2) if ttft and tot > ttft and ct else None,
                    "answer_head": re.sub(r"\s+", " ", txt or "")[:80],
                    "status": "PASS" if hit else "FAIL", "pass": hit}
        except Exception as e:  # noqa: BLE001
            with lock:
                results[r["i"]] = {"i": r["i"], "seed": r["seed"], "est_tokens": r["est"],
                                   "magic": r["magic"], "status": "SKIP", "pass": False,
                                   "error": err_tag(e)}

    threads = [threading.Thread(target=worker, args=(r,)) for r in reqs]
    sentry.start()
    t0 = time.time()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    sentry.stop.set()
    wall = round(time.time() - t0, 1)

    ladder_ok, ladder_note = True, ""
    if arm != "probe":
        ttfts = [r.get("ttft_s") for r in results if r]
        ttfts = [t for t in ttfts if t]
        srt = sorted(ttfts)
        if srt and any(b < a * 0.5 for a, b in zip(srt, srt[1:])):
            ladder_ok = False
            ladder_note = "阶梯乱序>2x"
    n_pass = sum(1 for r in results if r and r.get("pass"))
    n_fail = sum(1 for r in results if r and r.get("status") == "FAIL")
    n_skip = sum(1 for r in results if r and r.get("status") == "SKIP")
    n_rejected = sum(1 for r in results if r and r.get("error"))  # D-1：拒行入 rejected 计数
    total_prompt_tok = agg_prompt_tokens(results)
    return {"status": "DONE", "arm": arm, "n": n, "wall_s": wall,
            "water": {"before_m": sentry.before, "lowest_m": sentry.lowest,
                      "after_m": sentry.read_m(), "samples": sentry.samples,
                      "aborted": sentry.aborted, "abort_line_m": sentry.abort_m},
            "agg_prefill_tok_s": round(total_prompt_tok / wall) if wall else None,
            "ladder_monotonic_ok": ladder_ok, "ladder_note": ladder_note,
            "n_pass": n_pass, "n_fail": n_fail, "n_skip": n_skip, "n_rejected": n_rejected,
            "gate_pass": n_pass == n and not sentry.aborted,
            "rows": results}


def selfcheck(args):
    ok = True

    def need(cond, why):
        nonlocal ok
        print(("PASS" if cond else "FAIL"), why)
        ok = ok and cond
    p1, m1, e1 = calibrate(596000, "sc1", 0.5)
    p2, m2, e2 = calibrate(596000, "sc1", 0.5)
    need(p1 == p2, "同 seed 可复现")
    p3, _, e3 = calibrate(596000, "sc2", 0.5)
    need(p1 != p3, "跨 seed 不同文本（零 radix 共享）")
    need(596000 * 0.997 <= e1 <= 596000 * 1.003, f"596k 校准 ±0.3%（{e1}）")
    need(596000 * 0.997 <= e3 <= 596000 * 1.003, f"596k 校准跨 seed（{e3}）")
    need(p1.count(m1) == 1, "魔码唯一出现")
    idx = p1.find(m1)
    need(0.4 * len(p1) <= idx <= 0.6 * len(p1), f"埋深 0.5（{idx / len(p1):.2f}）")
    p4, m4, e4 = calibrate(596000, "sc4", 0.25)
    need(p4.find(m4) < 0.35 * len(p4), "埋深 0.25 交错")
    need(596000 * 0.997 <= e4 <= 596000 * 1.003, f"0.25 档也校准（{e4}）")
    # D-1 拒绝行容错自验（构造 400 响应样本；离线零实跑）：
    # 旧码汇总面 r["prompt_tokens"] 裸下标在拒绝行（无该键）必 KeyError——本块喂同构
    # 拒绝行（=worker 异常分支产物形）证汇总不炸+错误结构+计数三面。
    row_ok = {"i": 0, "seed": "s", "est_tokens": 596000, "magic": "m",
              "prompt_tokens": 595000, "completion_tokens": 8, "ttft_s": 1.0,
              "total_s": 2.0, "decode_tps": None, "answer_head": "ok",
              "status": "PASS", "pass": True}
    row_400 = {"i": 1, "seed": "s", "est_tokens": 596000, "magic": "m",
               "status": "SKIP", "pass": False,
               "error": err_tag(urllib.error.HTTPError(
                   "http://127.0.0.1:8898/v1/chat/completions", 400,
                   "Bad Request", None, None))}
    row_tmo = {"i": 2, "seed": "s", "est_tokens": 596000, "magic": "m",
               "status": "SKIP", "pass": False, "error": err_tag(TimeoutError("t"))}
    rows_d1 = [row_ok, row_400, row_tmo]
    try:
        tot_d1 = agg_prompt_tokens(rows_d1)
        nrej_d1 = sum(1 for r in rows_d1 if r and r.get("error"))
        need(tot_d1 == 595000 + 2 * 596000, f"D-1 拒绝行容错：汇总不炸（tot={tot_d1}）")
        need(row_400["error"] == "rc=400", f"D-1 400 行错误结构 rc=X（{row_400['error']}）")
        need(row_tmo["error"] == "timeout", "D-1 timeout 行错误结构")
        need(nrej_d1 == 2, f"D-1 拒绝行计数 n_rejected（{nrej_d1}）")
    except KeyError:
        need(False, "D-1 拒绝行容错：仍 KeyError（修复失效）")
    lim = args.tl_budget // 4096
    need(e1 <= lim, f"客户端 T×L 门镜像（est {e1} ≤ limit {lim}）")
    need(596000 < lim < 605000, f"门限覆盖 600k 级（limit={lim}）")
    print("selfcheck:", "OK" if ok else "NG")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8898")
    ap.add_argument("--model", default="deepseek-v4.1-flash")
    ap.add_argument("--arm", choices=["probe", "a", "b"], default="a")
    ap.add_argument("--prompt-tokens", type=int, default=None)
    ap.add_argument("--gen-tokens", type=int, default=2000)
    ap.add_argument("--concurrency", type=int, default=16)
    ap.add_argument("--depths", type=float, nargs="+", default=[0.5])
    ap.add_argument("--seeds", default="c16-20261001")
    ap.add_argument("--water-abort-m", type=int, default=9000)
    ap.add_argument("--water-sample-s", type=float, default=1.0)
    ap.add_argument("--http-timeout", type=int, default=5400)
    ap.add_argument("--tl-budget", type=int, default=2478000000)
    ap.add_argument("--json-out", default=None)
    ap.add_argument("--selfcheck", action="store_true")
    args = ap.parse_args()
    if args.selfcheck:
        sys.exit(selfcheck(args))
    pt = args.prompt_tokens
    if pt is None:
        pt = 596000 if args.arm in ("probe", "a") else 600000
    conc = 1 if args.arm == "probe" else (16 if args.arm == "a" else 15)
    sentry = WaterSentry(args.base, args.water_abort_m, args.water_sample_s)
    out = run_arm(args.base, args.model, args.arm, pt, args.gen_tokens, conc,
                  args.depths, args.seeds, args.tl_budget, args.http_timeout, sentry)
    if args.json_out:
        os.makedirs(os.path.dirname(args.json_out), exist_ok=True)
        with open(args.json_out, "w") as f:
            json.dump(out, f, ensure_ascii=False, indent=1)
    print(json.dumps({k: v for k, v in out.items() if k != "rows"},
                     ensure_ascii=False, indent=1))
    if out.get("rows"):
        for r in out["rows"]:
            print(" ", r.get("i"), r.get("status"), r.get("magic"),
                  "ttft=", r.get("ttft_s"), r.get("answer_head", "")[:40])
    sys.exit(0 if out.get("gate_pass") else 2)


if __name__ == "__main__":
    main()
