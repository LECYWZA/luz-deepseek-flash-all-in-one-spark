#!/usr/bin/env bash
# prefix_hit_probe.sh — R40(b)：前缀命中专项量具（encoder replay 收益验收专用）
#
# 【为什么存在】--enable-encoder-swa-bounded-replay（T51/A23-α 一行债）的收益面
#   = 前缀命中（同 prompt 重复 PR 第二次命中缓存 vs 加盐未命中）。sd_bench 的 PR
#   段每档 fresh uuid 盐、**设计上永不命中前缀**（防跨尺寸污染）——故命中收益在
#   现行量具中不可见，须本专项探针。
#
# 【协议】每档（默认 8192/32768/131072）× PAIRS 对（默认 3）：
#     warmup 512t（复用 sd_bench run_pr 同款内建预热形态）
#     每对 p：
#       MISS_A = fresh 盐构造 P_A，首发（必 miss）           → ttft_miss_a
#       HIT    = 同一 P_A **字节相同**重发（第二次=前缀命中）→ ttft_hit
#       MISS_B = fresh 盐构造 P_B 同长（时序对照 miss，防「引擎变快」漂移）→ ttft_miss_b
#     对速比 = mean(ttft_miss_a, ttft_miss_b) / ttft_hit
#   档结果 = 各对 med（ttft_miss / ttft_hit / 速比 / wall 速比 / cached_tokens）。
#   命中比（speedup）与 cached_tokens（引擎 usage 若报 prompt_tokens_details.
#   cached_tokens 则实证命中层数）双口径输出；verdict：HIT-CONFIRMED / FLAT。
#
# 【口径】prompt 构造复用 sd_bench.build_pr_prompt（import 复用，逐字节同源）；
#   filler 默认 random（真实文本口径——repeated 会使 Engram 行缓存命中混入，
#   与前缀命中混淆；PR_FILLER=repeated 可切 sparkDash 口径对照）。计时形态与
#   sd_bench.Client.stream 相同：SSE 流式、ttft=t_first−t_req、GEN 8、
#   wall=t_last−t_req、stream+include_usage。
#
# 【用法（本工具只写不跑；真跑须引擎已在 :8898）】
#   ARM_TAG=A21G bash tools/prefix_hit_probe.sh                # γ1 基线（命中比~1 的地板）
#   ARM_TAG=A23A bash tools/prefix_hit_probe.sh                # A23-α 验收（replay 收益）
#   ARM_TAG=selftest DRY_RUN=1 bash tools/prefix_hit_probe.sh  # 干跑：构造+复现性自检，不发包
#   ARM_TAG=x bash tools/prefix_hit_probe.sh 8192 131072       # 位置参数覆盖档表
# 环境变量：
#   ARM_TAG(默认 unknown)      臂标签 → logs/<ARM_TAG>/prefix_hit/<ts>/
#   BASE_URL(默认 http://127.0.0.1:8898/v1)  引擎口（含 8899 即拒跑，G5 生产口隔离）
#   SIZES(默认 "8192 32768 131072")  探针档（位置参数可覆盖）
#   PAIRS(默认 3)              每档配对数（仲裁取中位）
#   PR_FILLER(默认 random)     random=真实文本口径；repeated=sparkDash 对照口径
#   GEN_TOKENS(默认 8) / WARM_TOKENS(默认 512)   对齐 sd_bench PR 口径
#   HIT_GATE(默认 1.05)        速比判线（≥ 即 HIT-CONFIRMED；仅探针输出，非 G 门）
#   STEP_TIMEOUT_S(默认 1800)  整个探针 python 外层超时
#   BENCH_REPO(默认 ~/dsv41-flash-dgxsparks) / CAMPAIGN(默认 ~/luz030-opt-campaign)
#
# 【输出】$OUTDIR/：prefix_hit.json（全档明细+中位+verdict）、prefix_hit.log、
#   控制台表（size/filler/pairs/ttft_miss/ttft_hit/速比/wall速比/cached_tok/verdict）、
#   PREFIX-HIT-DONE 标记行。
# 【护栏】8899 硬拒；HIT 请求绝不请求 logprobs/hidden_states（replay_guard 拦截面
#   规避——return_logprob+start_len 或 FULL hidden 会 400/毁靴）；重定向前先 mkdir；
#   结果提取走 python JSON（本机 grep=ugrep 大小写陷阱，不 grep 文本锚定）；
#   DRY_RUN 干跑不发任何包。
set -uo pipefail

ARM_TAG="${ARM_TAG:-unknown}"
DRY_RUN="${DRY_RUN:-0}"
BASE_URL="${BASE_URL:-http://127.0.0.1:8898/v1}"
BENCH_REPO="${BENCH_REPO:-$HOME/dsv41-flash-dgxsparks}"
CAMPAIGN="${CAMPAIGN:-$HOME/luz030-opt-campaign}"
SIZES="${SIZES:-8192 32768 131072}"
PAIRS="${PAIRS:-3}"
PR_FILLER="${PR_FILLER:-random}"
GEN_TOKENS="${GEN_TOKENS:-8}"
WARM_TOKENS="${WARM_TOKENS:-512}"
HIT_GATE="${HIT_GATE:-1.05}"
STEP_TIMEOUT_S="${STEP_TIMEOUT_S:-1800}"

# ── 护栏：生产口绝对隔离（G5）+ 依赖自检 ─────────────────────────────────
case "$BASE_URL" in
  *8899*) echo "ABORT: BASE_URL 含 8899（生产口，G5 绝对隔离）: $BASE_URL" >&2; exit 5 ;;
esac
[ -f "$BENCH_REPO/bench/sd_bench.py" ] || { echo "ABORT: 缺 $BENCH_REPO/bench/sd_bench.py" >&2; exit 5; }
command -v python3 >/dev/null || { echo "ABORT: 无 python3" >&2; exit 5; }

# 位置参数覆盖档表
[ $# -gt 0 ] && SIZES="$*"

# ── 输出目录：先 mkdir 再重定向 ──────────────────────────────────────────
TS="$(date +%Y%m%d-%H%M%S)"
OUTDIR="$CAMPAIGN/logs/$ARM_TAG/prefix_hit/$TS"
mkdir -p "$OUTDIR"
ln -sfn "$OUTDIR" "$CAMPAIGN/logs/$ARM_TAG/prefix_hit/latest" 2>/dev/null || true
LOG="$OUTDIR/prefix_hit.log"
: > "$LOG"

echo "[$(date -u +%FT%TZ)] prefix_hit_probe 启动 ARM_TAG=$ARM_TAG sizes=[$SIZES] pairs=$PAIRS filler=$PR_FILLER gate=$HIT_GATE DRY_RUN=$DRY_RUN" | tee -a "$LOG"

# ── 探针本体（python：复用 sd_bench 构造；SSE 计时同 Client.stream + cached_tokens）──
run_probe() {
  timeout "$STEP_TIMEOUT_S" python3 - "$BASE_URL" "$SIZES" "$PAIRS" "$PR_FILLER" \
    "$GEN_TOKENS" "$WARM_TOKENS" "$HIT_GATE" "$DRY_RUN" "$OUTDIR" "$BENCH_REPO" \
    <<'PY' 2>&1 | tee -a "$LOG"
import json, os, statistics, sys, time, uuid

(base, sizes_s, pairs, filler, gen_t, warm_t, gate_s, dry,
 outdir, bench_repo) = sys.argv[1:11]
pairs, gen_t, warm_t = int(pairs), int(gen_t), int(warm_t)
gate = float(gate_s)
sizes = [int(x) for x in sizes_s.split()]

sys.path.insert(0, os.path.join(bench_repo, "bench"))
import sd_bench  # 复用：build_pr_prompt / estimate_tokens（逐字节同源）

import requests

def stream_capture(base, prompt, gen_tokens, timeout_s=3200.0):
    """与 sd_bench.Client.stream 同计时形态；额外捕获 usage.prompt_tokens_details."""
    body = {"messages": [{"role": "user", "content": prompt}],
            "max_tokens": gen_tokens, "temperature": 0.0, "top_p": 1.0,
            "stream": True, "stream_options": {"include_usage": True}}
    t_first = t_last = completion = prompt_tokens = cached = None
    t0 = time.perf_counter()
    r = requests.post(f"{base.rstrip('/')}/chat/completions", json=body,
                      stream=True, timeout=timeout_s)
    r.raise_for_status()
    for line in r.iter_lines(decode_unicode=False):
        if not line or not line.startswith(b"data:"):
            continue
        payload = line[5:].strip()
        if payload == b"[DONE]":
            break
        try:
            j = json.loads(payload)
        except json.JSONDecodeError:
            continue
        now = time.perf_counter()
        for ch in j.get("choices", []):
            if ch.get("delta", {}).get("content"):
                if t_first is None:
                    t_first = now
                t_last = now
        u = j.get("usage")
        if u:
            completion = u.get("completion_tokens")
            prompt_tokens = u.get("prompt_tokens")
            det = u.get("prompt_tokens_details") or {}
            if det.get("cached_tokens") is not None:
                cached = det["cached_tokens"]
            t_last = t_last or now
    if t_first is None or completion is None:
        raise RuntimeError("no visible delta or usage")
    ms = lambda t: round((t - t0) * 1000.0, 1)
    return {"ttft_ms": ms(t_first), "wall_ms": ms(t_last),
            "prompt_tokens": prompt_tokens, "completion": completion,
            "cached_tokens": cached}

# 干跑：构造 + 复现性/互异自检（不发任何包）
if dry == "1":
    ok = True
    for sz in sizes:
        p1 = sd_bench.build_pr_prompt(sz, "deadbeef", filler)
        p2 = sd_bench.build_pr_prompt(sz, "deadbeef", filler)
        p3 = sd_bench.build_pr_prompt(sz, uuid.uuid4().hex[:8], filler)
        same = p1 == p2
        diff = p1 != p3  # 盐在 header ⇒ 全提示自首字符即不同（repeated/random 皆然）
        cov = sd_bench.estimate_tokens(p1) >= sz - 64
        print(f"DRY size={sz} reproducible={same} cross_salt_differs={diff} cover={cov}")
        ok = ok and same and diff and cov
        print(f"  plan: {pairs}x [MISS_A(salt@t) -> HIT(同字节重发) -> MISS_B(fresh盐)]")
    print("DRY-RUN", "PASS" if ok else "FAIL", "(未发包)")
    sys.exit(0 if ok else 1)

# 真跑
client_warm = sd_bench.build_pr_prompt(warm_t, uuid.uuid4().hex[:8], filler)
stream_capture(base, client_warm, gen_t)  # warmup（sd_bench run_pr 同款 512t）

results = []
for sz in sizes:
    pair_rows = []
    for p in range(1, pairs + 1):
        sa = uuid.uuid4().hex[:8]
        pa = sd_bench.build_pr_prompt(sz, sa, filler)
        miss_a = stream_capture(base, pa, gen_t)   # 必 miss（全新盐）
        hit = stream_capture(base, pa, gen_t)      # 字节相同 → 前缀命中
        pb = sd_bench.build_pr_prompt(sz, uuid.uuid4().hex[:8], filler)
        miss_b = stream_capture(base, pb, gen_t)   # 时序对照 miss
        miss_ref = (miss_a["ttft_ms"] + miss_b["ttft_ms"]) / 2.0
        pair_rows.append({
            "pair": p, "salt_a": sa,
            "ttft_miss_a_ms": miss_a["ttft_ms"], "ttft_hit_ms": hit["ttft_ms"],
            "ttft_miss_b_ms": miss_b["ttft_ms"],
            "ttft_speedup": round(miss_ref / hit["ttft_ms"], 3),
            "wall_miss_a_ms": miss_a["wall_ms"], "wall_hit_ms": hit["wall_ms"],
            "wall_speedup": round(((miss_a["wall_ms"] + miss_b["wall_ms"]) / 2.0)
                                  / hit["wall_ms"], 3),
            "prompt_tokens": hit["prompt_tokens"], "cached_tokens": hit["cached_tokens"]})
        print(f"size={sz} pair={p} miss_a={miss_a['ttft_ms']}ms hit={hit['ttft_ms']}ms "
              f"miss_b={miss_b['ttft_ms']}ms speedup={pair_rows[-1]['ttft_speedup']}x "
              f"cached={hit['cached_tokens']}")

    med = lambda k: round(statistics.median(r[k] for r in pair_rows), 1)
    cached_vals = [r["cached_tokens"] for r in pair_rows if r["cached_tokens"] is not None]
    cached_med = int(statistics.median(cached_vals)) if cached_vals else None
    sp_med = round(statistics.median(r["ttft_speedup"] for r in pair_rows), 3)
    verdict = ("HIT-CONFIRMED" if ((cached_med or 0) > 0 or sp_med >= gate) else "FLAT")
    results.append({
        "size": sz, "filler": filler, "pairs": pair_rows,
        "ttft_miss_med_ms": med("ttft_miss_a_ms"), "ttft_hit_med_ms": med("ttft_hit_ms"),
        "ttft_speedup_med": sp_med, "wall_speedup_med": round(
            statistics.median(r["wall_speedup"] for r in pair_rows), 3),
        "cached_tokens_med": cached_med,
        "cached_tokens_reported": bool(cached_vals),
        "hit_gate": gate, "verdict": verdict,
        "note": ("cached_tokens 引擎未报——命中判据退化为纯计时速比" if not cached_vals
                 else "cached_tokens 实证命中层数")})

out = {"base": base, "filler": filler, "sizes": sizes, "pairs": pairs,
       "protocol": "MISS_A(fresh盐)->HIT(字节相同重发)->MISS_B(fresh盐对照), 每对取 mean(missA,missB)/hit",
       "purpose": "encoder replay (--enable-encoder-swa-bounded-replay) 前缀命中收益验收",
       "results": results}
with open(os.path.join(outdir, "prefix_hit.json"), "w") as fp:
    json.dump(out, fp, ensure_ascii=False, indent=1)

print("\nsize\tfiller\tpairs\tttft_miss\tttft_hit\tspeedup\twall_speedup\tcached\tverdict")
for r in results:
    print("\t".join(str(x) for x in (
        r["size"], r["filler"], len(r["pairs"]), r["ttft_miss_med_ms"],
        r["ttft_hit_med_ms"], r["ttft_speedup_med"], r["wall_speedup_med"],
        r["cached_tokens_med"] if r["cached_tokens_reported"] else "n/a", r["verdict"])))
print(f"detail -> {outdir}/prefix_hit.json")
PY
}

run_probe
rc=$?
echo "[$(date -u +%FT%TZ)] prefix_hit_probe 完 rc=$rc" | tee -a "$LOG"
if [ "$rc" -ne 0 ]; then
  echo "WARN: 探针非零退出（超时/HTTP/解析），判定卡须记缺口" | tee -a "$LOG"
fi
echo "PREFIX-HIT-DONE $OUTDIR"
exit "$rc"
