#!/bin/bash
# A18：cap-accept 武装链。boot(A17键+cap-accept+SPS表) → 靴门(调度器横幅) → battery v2 → accept(突发后读) → GSM8K
# 前置：A18P 已出表并四机对齐（/opt/dsv41/adapter/dspark_sps_a18.json）
# 锚：A17-DEBT1（脚本头 ANCHOR_* 处填，A17 链收后落值）
set -uo pipefail
cd ~/luz030-opt-campaign
D=logs/A18B-COMPACT; L=$D/chain.log; mkdir -p "$D"
log(){ echo "[$(date -u +%FT%TZ)] $*" | tee -a "$L"; }
water(){ ssh dgxspark01 "free -m | awk '/Mem:/ {print \$7}'" 2>/dev/null; }

# ── A17 锚（2026-10-02 06:26 链收定稿；判据 DE ±2% / PR ±5%）──
ANCHOR="A17-DEBT1: c1=62.60 code=102.61 c8=20.86 c12=16.92 c16=14.74 PR=3347/3886/4011/4092 accept[3.1,3.4]"
log "锚：$ANCHOR"

log "== A18 boot =="
ARM_TAG=A18B SPEC=1 SPEC_EXTRA_ARGS="--prefill-decode-interval 16 --max-queued-requests 32 --min-free-slots-delay 1 --enable-decoder-swa-bounded-replay --speculative-dspark-sps-table-path /opt/dsv41/adapter/dspark_sps_a18.json" ARM_ENV_FILE=~/luz030-opt-campaign/arms/A18B-COMPACT-spec1.env bash ~/migrate-assets/bin/r3-boot-arm.sh >> "$L" 2>&1
log "boot rc=$?"

for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8898/health 2>/dev/null)
  [ "$code" = "200" ] && break; sleep 20
done
[ "$code" = "200" ] || { log "ABORT health 未达"; exit 2; }
log "health 200 → steady 5min（water=$(water)M）"; sleep 300

mode=$(docker exec r3boot-head printenv SGLANG_RAGGED_VERIFY_MODE 2>/dev/null)
sched=$(docker logs r3boot-head 2>&1 | grep -c 'DSpark ragged-verify scheduler enabled (mode=compact')
flat=$(docker logs r3boot-head 2>&1 | grep -c 'SPS table is uninitialized')
tbl=$(docker logs r3boot-head 2>&1 | grep 'ragged-verify scheduler enabled' | tail -1 | grep -o 'sps_table=[^,]*')
cps=$(docker logs r3boot-head 2>&1 | grep -c '\[DSPARK-CPS\]')
log "env: MODE=$mode; 调度横幅=$sched sps_table=[$tbl] flat警告=$flat（须0）"
[ "$mode" = "compact" ] && [ "$sched" -ge 1 ] && [ "$flat" -eq 0 ] || { log "ABORT cap-accept 未武装或表未装载"; exit 3; }

log "== battery v2 =="
ARM_TAG=A18B bash tools/run_battery_v2.sh >> "$L" 2>&1; log "battery rc=$? water=$(water)M"

log "== accept（3×256 预热，纯 decode 突发后读——口径纪律）=="
for i in 1 2 3; do python3 ~/dsv41-flash-dgxsparks/bench/sd_bench.py --base-url http://127.0.0.1:8898/v1 --key-file /dev/null --mode de --type prose --concurrency 1 --max-tokens 256 --runs 1 >/dev/null 2>&1; done
python3 tools/accept_window.py --base http://127.0.0.1:8898 > $D/accept.json 2>&1; cat $D/accept.json | tee -a "$L"

log "== GSM8K 200 =="
timeout 1800 python3 ~/dsv41-flash-dgxsparks/bench/gsm8k_dsv41.py --base http://127.0.0.1:8898 --model deepseek-v4.1-flash --nq 200 --out-raw $D/gsm8k_raw.json --out-summary $D/gsm8k_summary.json >> "$L" 2>&1
log "gsm8k rc=$?"; cat $D/gsm8k_summary.json 2>/dev/null | tee -a "$L"

log "== 运行中 CPS 行抽样（预算生效证据）=="
docker logs r3boot-head 2>&1 | grep '\[DSPARK-CPS\]' | tail -3 | tee -a "$L"
log "== A18 链完 =="
