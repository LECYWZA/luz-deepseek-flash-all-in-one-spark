#!/bin/bash
# ==============================================================================
# guard-onstart.sh — 启动脚本前置的「守卫体检」钩子
#
# 定位：由 ~/dsv41-flash-dgxsparks/start.sh 的 cmd_serve() 在**创建容器之前**调用一次
#       （在役接线实测：start.sh:1211 定义 cmd_serve、:1220-1221 调用本脚本，`GUARD_ONSTART=0` 跳过、`|| true` 永不阻塞）。
#       另有三个**历史调用点**（vLLM 时代启动器，非生产路径）：start_tp4_head_v043.sh:43-44、
#       start_tp4_worker_v043.sh:17-18、~/v41_launch.sh:4-5 —— 同一形态的 GUARD_ONSTART 门控。
# ⚠️ 2026-09-23 更正：旧注释作「定位：由 start_tp4_*.sh / v41_launch.sh 在**拉起容器之前**调用一次」。
#    那两个调用点**确实存在**（见上三处行号），所以不假；但它**漏了生产路径上的真正接线**
#    （start.sh 的 cmd_serve）——照旧注释读会以为本脚本只挂在已退役的 vLLM 链上。
#
# 铁律（改这个脚本必须保持）：
#   1) **永远 exit 0**。守卫体检绝不阻塞启动——启动失败比守卫缺失更严重。
#   2) **只读**。不写文件、不动容器、不改 systemd。
#   3) **快**。启动路径上最多一次 check，超时 60s。
#   4) 有异常时**大声说出来**并写告警日志，让人在任何日志里都能看见。
#
# 为什么需要它：守卫失效是**静默**的（2026-09-11 实测 head 的 P1 重建守卫
# 已被冻结 40 分钟而生产完全健康，无任何信号）。把它挂在启动路径上，等于每次
# 起栈都强制体检一次，避免"起了一个没人守的栈"。
#
# 用法：bash guard-onstart.sh [head|worker]     （角色可省，自动判定）
# ==============================================================================
set -uo pipefail
export HOME=/home/liux***ya

GUARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTL="$GUARD_DIR/guardctl.sh"
LOG="$GUARD_DIR/guard-alerts.log"
TAG="${GUARD_TAG:-onstart}"

echo "[guard-onstart] 守卫体检 ($(hostname), tag=$TAG) ..."
if [ ! -f "$CTL" ]; then
  echo "[guard-onstart] WARN: 找不到 $CTL，跳过体检（不阻塞启动）" >&2
  exit 0
fi

# 启动路径上网关本来就还没起来，检查业务面会变成"每次开机都喊狼来了"，
# 反而训练人忽略告警。这里只关心"容错链是否还活着"。
export GUARD_CHECK_GATEWAY=0

OUT=$(timeout 60 bash "$CTL" check 2>&1); RC=$?
echo "$OUT" | sed 's/^/  | /'

if [ "${RC:-1}" -eq 0 ]; then
  echo "[guard-onstart] 守卫全部正常，继续启动。"
  exit 0
fi

# ---- 有异常：不阻塞，但把所有能给的线索一次给全 ------------------------------
{
  echo "================================================================"
  echo "[guard-onstart] ⚠ 守卫体检未通过（这不阻塞启动，但请立刻处理）"
  echo "================================================================"
  echo "$OUT" | grep -E '^(FAIL|WARN)' | sed 's/^/  /'
  echo
  echo "  体检不过 ≠ 启动不了；体检不过 = **拉起后可能没有人守它**。"
  echo "  逐项自解释：  bash $CTL explain <单元名>"
  echo "  深诊断    ：  bash $CTL doctor"
  echo "  维护窗口开关：  bash $CTL hold <tag>   /   bash $CTL release <tag>"
  echo "================================================================"
} | tee -a "$LOG" >&2

command -v logger >/dev/null 2>&1 && \
  logger -t guard-onstart -p daemon.err "[CRIT] $(hostname) 守卫体检未通过（tag=$TAG）——见 $LOG" 2>/dev/null || true
exit 0
