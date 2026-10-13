#!/usr/bin/env bash
# pr_ladder6.sh — R40(a)：六档 PR 阶梯量具（4k/8k/16k/32k/64k/128k，三步法）
#
# 【为什么存在】TP split 收益面在 ≥64k（任务书 104 §R40），现行四档阶梯
#   （run_battery_v2 PR 段 4096-32768）测不到 64k/128k；本工具把 PR 段扩为六档
#   并把「三步法」在壳层做对（见下方量具坑①）。
#
# 【口径】sparkDash PR（sd_bench --mode pr）：串行、每档单请求、每档 fresh salt、
#   512-token 内建 warmup、GEN 8、tok/s = prompt_tokens/TTFT、filler 默认 repeated
#   （" the"×N——Engram 行缓存命中膨胀属性，只与同口径比；γ1 锚即此口径）。
#   三档口径（F-6a.2 修复 2026-10-09：口径名=filler 值名，废除旧「realtext→random」
#   值名错配——PR-ANCHOR-CONTAMINATION-AUDIT §四.1-4 接线缺口）：
#     repeated = sparkDash 锚口径（本工具必跑；γ1 列锚）；
#     random   = RANDOM_PASS=1 追加（均匀词汤，行缓存无可命中，无锚参考）；
#     real     = REAL_PASS=1 追加（sd_bench --pr-filler real=PORT(3) 语法模板散文，
#                真文本锚口径；无列锚=NEW-TIER 首跑建锚；三档数字互不可比）。
#
# 【三步法（每档 5 样本）】
#   A 首发   = 1 次 sd_bench 调用带全六档（与 run_battery_v2 pr_4sizes 首发段同形态；
#              内建 512t warmup 不足以预热长档路径——A19 实证首探针 4k 冷罚 655.7）
#   B 暖重   = 每档单独 1 次调用（与 a22/a23 链 pr_warm 段同形态）
#   C 仲裁×3 = 3 轮、每轮每档 1 次调用、**轮间档序左旋换位**（位置敏感纪律：
#              档结果受序列位置影响，轮换使位置偏差在仲裁中位处对消；
#              档间加盐由 sd_bench 每调用 uuid 自动保证）
#   锚值 = C 三样本中位（对齐 A20B/A22 判定卡的「仲裁」语义）。
#
# 【γ1 锚（A21-γ1 暖测，sparkDash）】4096:3322 8192:3772 16384:3940 32768:4069；
#   65536/131072 = NEW（无锚，本工具首跑即建锚）。带内判据默认 ±5%（A20B 判卡先例）。
#   参考列：γ1 数学模型 T(L)=242ms+238.4µs/tok（残差<1%）外推 tok_s（仅 sparkDash 行）。
#
# 【量具坑（本工具规避，勿回退）】
#   ① sd_bench 的 --runs 在 pr 模式**被忽略**（run_pr 只迭代 sizes，每档 1 样本）——
#     a21g2p/a22alpha/a23delta/a22_audit 链里 `--runs 3` 是 no-op，仲裁×3 必须是
#     3 次独立调用（本工具如此实现）。
#   ② sd_bench --base-url 默认 = http://127.0.0.1:8899 = **生产口**（G5 绝对隔离），
#     必须显式 --base-url ...:8898（本工具硬拒 8899）。
#   ③ 本机 grep 实为 ugrep（RING-FACE 审计曾出大小写意外命中）——结果提取一律走
#     python3 解析 JSON，禁止 grep 日志文本锚定；必须文本匹配时用 grep -F 定串。
#   ④ 重定向前先 mkdir（OUTDIR/latest 软链与逐档 JSON 全部先建目录再落盘）。
#
# 【用法】
#   ARM_TAG=A21G bash tools/pr_ladder6.sh               # 真跑（引擎须已在 :8898）
#   ARM_TAG=selftest DRY_RUN=1 bash tools/pr_ladder6.sh # 干跑：只打印命令，不发包
# 环境变量：
#   ARM_TAG(默认 unknown)      臂标签 → logs/<ARM_TAG>/prl6/<ts>/
#   BASE_URL(默认 http://127.0.0.1:8898/v1)  引擎口（含 8899 即拒跑）
#   BENCH_REPO(默认 ~/dsv41-flash-dgxsparks)  sd_bench.py 所在仓
#   CAMPAIGN(默认 ~/luz030-opt-campaign)
#   SIZES(默认 "4096 8192 16384 32768 65536 131072")
#   STEP_TIMEOUT_S(默认 900)   单次 sd_bench 调用超时（护栏，防失控长跑）
#   RANDOM_PASS(默认 0)        =1 追加 random 口径整轮（无锚参考）
#   REAL_PASS(默认 0)          =1 追加 real 口径整轮（真文本锚，NEW-TIER 首跑建锚）
#   PR_BAND_PCT(默认 5)        带内判据 ±%（超带需 census 族帐背书，G2）
#   ANCHORS(默认 "4096:3322 8192:3772 16384:3940 32768:4069")  γ1 锚，可覆盖
#
# 【输出】$OUTDIR/：prl_{cal}_first.json（首发六行）、prl_{cal}_warm_{sz}.json、
#   prl_{cal}_arb{1,2,3}_{sz}.json、pr_ladder6.log、water.txt（分相 MemAvailable）、
#   prl6_summary.json + prl6_summary.tsv（判定表）、PR-LADDER6-DONE 标记行。
# 【护栏】8899 硬拒；逐调用 timeout；DRY_RUN 干跑；本工具不读写 8899、不起靴、
#   不碰集群——只对 :8898 发 PR 请求。
set -uo pipefail

ARM_TAG="${ARM_TAG:-unknown}"
DRY_RUN="${DRY_RUN:-0}"
BASE_URL="${BASE_URL:-http://127.0.0.1:8898/v1}"
BENCH_REPO="${BENCH_REPO:-$HOME/dsv41-flash-dgxsparks}"
CAMPAIGN="${CAMPAIGN:-$HOME/luz030-opt-campaign}"
SIZES="${SIZES:-4096 8192 16384 32768 65536 131072}"
STEP_TIMEOUT_S="${STEP_TIMEOUT_S:-900}"
RANDOM_PASS="${RANDOM_PASS:-0}"
REAL_PASS="${REAL_PASS:-0}"
PR_BAND_PCT="${PR_BAND_PCT:-5}"
ANCHORS="${ANCHORS:-4096:3322 8192:3772 16384:3940 32768:4069}"

# ── 护栏：生产口绝对隔离（G5）+ 依赖自检 ─────────────────────────────────
case "$BASE_URL" in
  *8899*) echo "ABORT: BASE_URL 含 8899（生产口，G5 绝对隔离）: $BASE_URL" >&2; exit 5 ;;
esac
SD="$BENCH_REPO/bench/sd_bench.py"
[ -f "$SD" ] || { echo "ABORT: 缺 $SD" >&2; exit 5; }
command -v python3 >/dev/null || { echo "ABORT: 无 python3" >&2; exit 5; }

# ── 输出目录：先 mkdir 再重定向（坑④）────────────────────────────────────
TS="$(date +%Y%m%d-%H%M%S)"
OUTDIR="$CAMPAIGN/logs/$ARM_TAG/prl6/$TS"
mkdir -p "$OUTDIR"
ln -sfn "$OUTDIR" "$CAMPAIGN/logs/$ARM_TAG/prl6/latest" 2>/dev/null || true
LOG="$OUTDIR/pr_ladder6.log"
: > "$LOG"

log() { echo "[$(date -u +%FT%TZ)] $*" | tee -a "$LOG"; }
water() {  # head 机 MemAvailable（battery_v2 [W3] 同源；四机水线=R41 挂载说明）
  awk '/^MemAvailable:/{printf "%dMB", int($2/1024)}' /proc/meminfo 2>/dev/null || echo "?"
}

run_step() {  # run_step <说明> <cmd...>：DRY_RUN 只打印；真跑带 timeout 与 rc 记录
  local desc="$1"; shift
  log "$desc"
  log "  CMD: $*"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "  (DRY_RUN: skip)"
    return 0
  fi
  if timeout "$STEP_TIMEOUT_S" "$@" >> "$LOG" 2>&1; then
    log "  rc=0 (water=$(water))"
  else
    local rc=$?
    log "  rc=$rc  WARN: 段失败/超时(${STEP_TIMEOUT_S}s)，续跑但判定卡须记缺口"
    return "$rc"
  fi
}

B=(python3 "$SD" --base-url "$BASE_URL" --key-file /dev/null --mode pr)

log "== pr_ladder6 启动 ARM_TAG=$ARM_TAG OUTDIR=$OUTDIR DRY_RUN=$DRY_RUN =="
log "sizes=[$SIZES] anchors=[$ANCHORS] band=±${PR_BAND_PCT}% random_pass=$RANDOM_PASS real_pass=$REAL_PASS"
log "口径注: sparkDash=repeated filler(γ1锚可比); random=均匀词汤(无锚参考); real=真文本(NEW-TIER首跑建锚); 三档互不可比"
echo "phase=pre water=$(water)" >> "$OUTDIR/water.txt"

# 口径轮：sparkDash 必跑（锚口径）；random/real 由 RANDOM_PASS/REAL_PASS 追加
# F-6a.2：口径名=filler 值名（旧「realtext→random」错配废除）
CALS=(sparkdash)
FILLERS=(repeated)
if [[ "$RANDOM_PASS" == "1" ]]; then CALS+=(random); FILLERS+=(random); fi
if [[ "$REAL_PASS" == "1" ]];   then CALS+=(real);   FILLERS+=(real);   fi

read -r -a SIZE_ARR <<< "$SIZES"
N=${#SIZE_ARR[@]}

for ci in "${!CALS[@]}"; do
  cal="${CALS[$ci]}"; fil="${FILLERS[$ci]}"
  log "-- 口径轮 cal=$cal filler=$fil --"

  # ── A 首发：一次调用带全六档（battery_v2 pr_4sizes 同形态）──────────────
  run_step "[$cal] A 首发（六档串行,每档 fresh salt）" \
    "${B[@]}" --pr-filler "$fil" --label "prl6-$cal-first" \
    --json-out "$OUTDIR/prl_${cal}_first.json"

  # ── B 暖重：每档单独一次（链 pr_warm 同形态）───────────────────────────
  for sz in "${SIZE_ARR[@]}"; do
    run_step "[$cal] B 暖重 $sz" \
      "${B[@]}" --pr-filler "$fil" --sizes "$sz" --label "prl6-$cal-warm-$sz" \
      --json-out "$OUTDIR/prl_${cal}_warm_${sz}.json"
  done

  # ── C 仲裁×3：轮间档序左旋换位（位置敏感纪律）──────────────────────────
  for r in 1 2 3; do
    rot=$(( (r - 1) % N ))
    order=("${SIZE_ARR[@]:rot}" "${SIZE_ARR[@]:0:rot}")
    log "[$cal] C 仲裁轮 $r 档序(换位)= ${order[*]}"
    for sz in "${order[@]}"; do
      run_step "[$cal] C 仲裁 $r 档 $sz" \
        "${B[@]}" --pr-filler "$fil" --sizes "$sz" --label "prl6-$cal-arb$r-$sz" \
        --json-out "$OUTDIR/prl_${cal}_arb${r}_${sz}.json"
      # 64k/128k 新档水线盯梢（128k prefill 池压力新 territory）
      case "$sz" in 65536|131072) echo "post-arb$r-$sz water=$(water)" >> "$OUTDIR/water.txt" ;; esac
    done
  done
  echo "phase=post-$cal water=$(water)" >> "$OUTDIR/water.txt"
done

# ── 汇总判定：python 解析 JSON（坑③：不 grep 文本）────────────────────────
python3 - "$OUTDIR" "$SIZES" "$ANCHORS" "$PR_BAND_PCT" "$RANDOM_PASS" "$REAL_PASS" "$DRY_RUN" "$ARM_TAG" "${CALS[@]}" <<'PY' | tee -a "$LOG"
import json, os, statistics, sys

outdir, sizes_s, anchors_s, band, random_pass, real_pass, dry, arm = sys.argv[1:9]
cals = sys.argv[9:]
sizes = [int(x) for x in sizes_s.split()]
anchors = {}
for kv in anchors_s.split():
    k, _, v = kv.partition(":")
    anchors[int(k)] = float(v)
band = float(band)

def row_of(path, target):
    try:
        for r in json.load(open(path))["pr"]:
            if r["target"] == target:
                return r
    except Exception:
        pass
    return None

rows, tsv = [], []
hdr = ("caliber\ttier\tfirst\twarm\tarb1\tarb2\tarb3\tarb_med\tspread%\tanchor\t"
       "delta%\tmodel_pred\tttft_med_s\tckpt:prompt_tokens\tverdict")
tsv.append(hdr)
MODEL = lambda L: L / (0.242 + 0.0002384 * L)  # γ1 数学模型外推（仅 sparkDash 参考）

for cal in cals:
    for sz in sizes:
        f = row_of(os.path.join(outdir, f"prl_{cal}_first.json"), sz)
        w = row_of(os.path.join(outdir, f"prl_{cal}_warm_{sz}.json"), sz)
        arbs = [row_of(os.path.join(outdir, f"prl_{cal}_arb{r}_{sz}.json"), sz) for r in (1, 2, 3)]
        g = lambda r, k: (r or {}).get(k)
        arb_vals = [r["tok_s"] for r in arbs if r and r.get("tok_s")]
        arb_med = round(statistics.median(arb_vals), 1) if arb_vals else None
        spread = (round(100.0 * (max(arb_vals) - min(arb_vals)) / arb_med, 1)
                  if len(arb_vals) == 3 and arb_med else None)
        anch = anchors.get(sz)
        if cal != "sparkdash":
            anch = None  # random/real 口径无 γ1 列锚（real=NEW-TIER 首跑建锚）
        delta = (round(100.0 * (arb_med - anch) / anch, 1)
                 if (arb_med is not None and anch is not None) else None)
        ttfts = [r["ttft_s"] for r in arbs if r and r.get("ttft_s") is not None]
        ttft_med = round(statistics.median(ttfts), 3) if ttfts else None
        pts = [r["prompt_tokens"] for r in arbs if r and r.get("prompt_tokens")]
        pt = int(statistics.median(pts)) if pts else None
        if dry == "1":
            verdict = "DRY-RUN"
        elif arb_med is None:
            verdict = "MISSING(判卡记缺口)"
        elif anch is None:
            verdict = ("NEW-TIER(首跑建锚)" if sz not in anchors else "NO-ANCHOR(该口径)")
        elif abs(delta) <= band:
            verdict = "IN-BAND"
        else:
            verdict = "OUT-OF-BAND(小增益须census族帐背书,G2)"
        model_pred = round(MODEL(sz), 1) if cal == "sparkdash" else None
        fmt = lambda v: "-" if v is None else v
        tsv.append("\t".join(str(x) for x in (
            cal, sz, fmt(g(f, "tok_s")), fmt(g(w, "tok_s")),
            fmt(g(arbs[0], "tok_s")), fmt(g(arbs[1], "tok_s")), fmt(g(arbs[2], "tok_s")),
            fmt(arb_med), fmt(spread), fmt(anch), fmt(delta), fmt(model_pred),
            fmt(ttft_med), fmt(pt), verdict)))
        rows.append({"caliber": cal, "tier": sz,
                     "first_tok_s": g(f, "tok_s"), "warm_tok_s": g(w, "tok_s"),
                     "arb_tok_s": arb_vals, "arb_median_tok_s": arb_med,
                     "arb_spread_pct": spread, "anchor": anch, "delta_pct": delta,
                     "model_pred_tok_s": model_pred, "arb_median_ttft_s": ttft_med,
                     "arb_median_prompt_tokens": pt, "verdict": verdict})

table = "\n".join(tsv)
print(table)
summary = {"arm_tag": arm, "dry_run": dry == "1", "calibers": cals,
           "sizes": sizes, "anchors": {str(k): v for k, v in anchors.items()},
           "band_pct": band, "random_pass": random_pass == "1", "real_pass": real_pass == "1",
           "caliber_note": ("sparkDash=repeated filler(γ1锚口径,行缓存膨胀属性); "
                            "random=均匀词汤(无锚参考); real=真文本(PORT(3)散文,NEW-TIER首跑建锚); "
                            "三档数字互不可比(F-6a.2 口径名=值名)"),
           "discipline": ("三步法=首发+暖重+仲裁×3(独立调用,--runs在pr模式被忽略); "
                          "仲裁轮间档序左旋换位;档间加盐=sd_bench每调用uuid"),
           "rows": rows}
with open(os.path.join(outdir, "prl6_summary.json"), "w") as fp:
    json.dump(summary, fp, ensure_ascii=False, indent=1)
with open(os.path.join(outdir, "prl6_summary.tsv"), "w") as fp:
    fp.write(table + "\n")
print(f"summary json/tsv -> {outdir}/prl6_summary.{{json,tsv}}")
PY
py_rc=$?
echo "phase=post-summary water=$(water)" >> "$OUTDIR/water.txt"
log "== pr_ladder6 完（summary rc=$py_rc）=="
echo "PR-LADDER6-DONE $OUTDIR"
exit "$py_rc"
