#!/usr/bin/env bash
# run_battery_v2.sh — L10 质量面 sd 电池 v2（M0 量具修正版）
#
# 相对 v1（~/l10-quality/run_battery.sh）的修正（对齐任务书 doc102 M0(b)(c)(d)）：
#   [W1] PR 段前插 1 次 8k warmup（v1 实证首探针 4k 冷罚 655.7 t/s vs 8k 2364——
#        sd_bench 内建 512-token warmup 不足以预热 prefill 长档路径）。
#        warmup 结果落 pr_warmup_8k.json 并写 WARMUP-NOT-ANCHORED 标记，禁止入锚。
#   [W2] 输出全部进带时间戳目录：~/luz030-opt-campaign/logs/<ARM_TAG>/<ts>/，
#        ARM_TAG 由环境变量传入（默认 unknown），附 latest 软链。
#   [W3] 电池前后各采一次 MemAvailable + nvidia-smi 显存 → mem_snapshot.txt
#        （对齐 census 护栏 G4 flush 观测协议）。
#   [W4] 结尾打印 BATTERY-DONE + 目录路径（供 verdict 卡与闭合校验自动定位）。
#   DE 段口径不变：prose/code c1 + prose c8/c12/c16 + pr 4sizes（与 r11/r12 锚可比）。
#
# 用法:
#   ARM_TAG=<臂名> bash tools/run_battery_v2.sh          # 真跑（引擎须已在 :8898）
#   ARM_TAG=selftest DRY_RUN=1 bash tools/run_battery_v2.sh   # 干跑：只打印命令，不发包
# 环境变量:
#   ARM_TAG (默认 unknown)   臂标签，构成 logs/<ARM_TAG>/<ts>/
#   DRY_RUN=1                干跑分支（离线自测用，绝不发包）
#   BASE_URL  (默认 http://127.0.0.1:8898/v1)
#   BENCH_REPO(默认 ~/dsv41-flash-dgxsparks)   sd_bench.py 所在仓
#   CAMPAIGN  (默认 ~/luz030-opt-campaign)
#   STEP_TIMEOUT_S(默认 900) 单段 bench 超时上限（继承 census 护栏 G2）
set -uo pipefail

ARM_TAG="${ARM_TAG:-unknown}"
DRY_RUN="${DRY_RUN:-0}"
BASE_URL="${BASE_URL:-http://127.0.0.1:8898/v1}"
BENCH_REPO="${BENCH_REPO:-$HOME/dsv41-flash-dgxsparks}"
CAMPAIGN="${CAMPAIGN:-$HOME/luz030-opt-campaign}"
STEP_TIMEOUT_S="${STEP_TIMEOUT_S:-900}"
B="python3 $BENCH_REPO/bench/sd_bench.py --base-url $BASE_URL --key-file /dev/null"

TS="$(date +%Y%m%d-%H%M%S)"
OUTDIR="$CAMPAIGN/logs/$ARM_TAG/$TS"
mkdir -p "$OUTDIR"
ln -sfn "$OUTDIR" "$CAMPAIGN/logs/$ARM_TAG/latest"

# ── [W3] 前置内存快照 ────────────────────────────────────────────────────
mem_snapshot() {
  local phase="$1"
  {
    echo "=== $phase @ $(date -Is) ==="
    awk '/^MemAvailable:/{printf "MemAvailable_mb=%d\n", $2/1024}' /proc/meminfo
    if command -v nvidia-smi >/dev/null 2>&1; then
      nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader \
        || echo "nvidia-smi query failed"
    else
      echo "nvidia-smi: not found on this host"
    fi
  } | tee -a "$OUTDIR/mem_snapshot.txt"
}

run() {  # run <说明> <cmd...>：DRY_RUN 只打印；真跑带超时与退出码记录
  local desc="$1"; shift
  echo "[$(date -Is)] $desc"
  echo "  CMD: $*"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  (DRY_RUN: skip)"
    return 0
  fi
  if timeout "$STEP_TIMEOUT_S" "$@" | tee -a "$OUTDIR/battery_$ARM_TAG.log"; then
    echo "  rc=0"
  else
    local rc=$?
    echo "  rc=$rc  ⚠ 段失败/超时(${STEP_TIMEOUT_S}s)，继续下一段但判据卡须记录" | tee -a "$OUTDIR/battery_$ARM_TAG.log"
  fi
}

echo "ARM_TAG=$ARM_TAG  OUTDIR=$OUTDIR  DRY_RUN=$DRY_RUN"
mem_snapshot "pre-battery"

# ── DE 段（口径与 v1/r11/r12 完全一致，勿改参数）────────────────────────
run "DE prose c1"  $B --mode de --type prose  --concurrency 1  --json-out "$OUTDIR/de_prose_c1.json"
run "DE code  c1"  $B --mode de --type code   --concurrency 1  --json-out "$OUTDIR/de_code_c1.json"
run "DE prose c8"  $B --mode de --type prose  --concurrency 8  --json-out "$OUTDIR/de_prose_c8.json"
run "DE prose c12" $B --mode de --type prose  --concurrency 12 --json-out "$OUTDIR/de_prose_c12.json"
run "DE prose c16" $B --mode de --type prose  --concurrency 16 --json-out "$OUTDIR/de_prose_c16.json"

# ── [W1] PR 段前 8k warmup（不落锚）─────────────────────────────────────
# 单独成段：8192 档全量 prefill 一次，预热 chunk/indexer/图路径；结果文件名带
# warmup、目录内写 WARMUP-NOT-ANCHORED 标记，锚表与闭合校验一律排除此文件。
run "PR warmup 8k (NOT ANCHORED)" \
  $B --mode pr --sizes 8192 --label pr-warmup-8k --json-out "$OUTDIR/pr_warmup_8k.json"
{ echo "pr_warmup_8k.json = warmup-only, M0-W1 冷罚修正，禁止入锚/入闭合校验 ($(date -Is))"; } \
  > "$OUTDIR/WARMUP-NOT-ANCHORED"

# ── PR 段（4 sizes，口径不变）───────────────────────────────────────────
run "PR 4sizes" $B --mode pr --sizes 4096 8192 16384 32768 --json-out "$OUTDIR/pr_4sizes.json"

# ── [W3] 后置内存快照 + [W4] 完成标记 ───────────────────────────────────
mem_snapshot "post-battery"
if [[ "$DRY_RUN" != "1" ]]; then
  ls -la "$OUTDIR"
fi
echo "BATTERY-DONE $OUTDIR"
