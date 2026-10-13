#!/bin/bash
# A18B 续链：靴已在+门已人工验绿（08:08:31 假ABORT=脚本判据漏改），从 battery 起
set -uo pipefail
cd ~/luz030-opt-campaign
D=logs/A18B-COMPACT; L=$D/chain.log
log(){ echo "[$(date -u +%FT%TZ)] $*" | tee -a "$L"; }
log "== 续链：battery v2（门已于 08:08:31 验绿：MODE=compact 横幅=1 表装载 flat=0）=="
ARM_TAG=A18B bash tools/run_battery_v2.sh >> "$L" 2>&1; log "battery rc=$?"
log "== accept（3×256 预热，纯 decode 突发后读）=="
for i in 1 2 3; do python3 ~/dsv41-flash-dgxsparks/bench/sd_bench.py --base-url http://127.0.0.1:8898/v1 --key-file /dev/null --mode de --type prose --concurrency 1 --max-tokens 256 --runs 1 >/dev/null 2>&1; done
python3 tools/accept_window.py --base http://127.0.0.1:8898 > $D/accept.json 2>&1; cat $D/accept.json | tee -a "$L"
log "== GSM8K 200 =="
timeout 1800 python3 ~/dsv41-flash-dgxsparks/bench/gsm8k_dsv41.py --base http://127.0.0.1:8898 --model deepseek-v4.1-flash --nq 200 --out-raw $D/gsm8k_raw.json --out-summary $D/gsm8k_summary.json >> "$L" 2>&1
log "gsm8k rc=$?"; cat $D/gsm8k_summary.json 2>/dev/null | tee -a "$L"
log "== A18B 链完 =="
