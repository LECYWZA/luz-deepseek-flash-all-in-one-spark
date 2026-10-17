#!/usr/bin/env bash
# 阶段2：点火 LuZ-0.3.1 栈（OPS-MANUAL 合规：slotlock wrapper + 九参 + overlay + 调优）
set -euo pipefail
L=/root/luz-logs
stop_ts=$(cat "$L/.stop_ts" 2>/dev/null || echo 0)
now=$(date +%s); el=$(( now - stop_ts ))
echo "=== 阶段2 点火 $(date +%F' '%T) ==="
echo "[沉降] 距停栈已 ${el}s"
if [ "$el" -lt 600 ]; then
  echo "!! 沉降不足 600s（OPS-MANUAL 第四章规避律：快速重启=首请求 940 级慢窗）——拒绝点火"
  exit 1
fi
mkdir -p /root/luz030-opt-campaign
cd /models/luz-deepseek-flash-all-in-one

export ARM_TAG=luz031-SPARK
export SPEC=1
export API_PORT=8888
export CTN_PREFIX=r3boot
export ARM_ENV_FILE=/root/migrate-assets/dsv41/env/PROD-R51W5-1017.env
export SGLANG_OVERLAY_DIR=/root/migrate-assets/v4vl/sglang-overlay.o12c1-prod
# 九参（SPEC6 六参 + A8/A9 + W-G 第9参）；交付脚本 SERVER_ARGS 缺第6-9参，走官方 SPEC_EXTRA_ARGS 注入面
export SPEC_EXTRA_ARGS="--prefill-decode-interval 16 --max-queued-requests 32 --min-free-slots-delay 1 --enable-decoder-swa-bounded-replay --reasoning-parser deepseek-v41 --swa-prefix-tails 256 --tool-call-parser deepseekv41 --enable-cache-report --sleep-on-idle"

LOG=$L/boot-$(date +%Y%m%d-%H%M%S).log
echo "[点火] 日志 → $LOG"
echo "[点火] 参数面: env=PROD-R51W5-1017.env(51键) spec=1 port=8888 ctner=r3boot"
bash tools/boot-with-slotlock.sh bash /root/migrate-assets/bin/r3-boot-arm.spark.sh 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
echo "[点火结束 rc=$rc $(date +%T)]"
exit "$rc"
