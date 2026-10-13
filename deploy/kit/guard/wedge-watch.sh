#!/usr/bin/env bash
# wedge-watch.sh —— 宿主"用户态冻结"楔死探测器（2026-09-22 事故教训）
#
# 为什么需要它：2026-09-22 r3 窗口，dgxspark02 在 256K 档期间楔死（14:49:34 起无任何日志），
# 而 guard-alerts.log 里**一条 02 的记录都没有**——现有判据覆盖 NVRM、内核 OOM、时钟楔死，
# 但没有任何判据覆盖"ping 通、TCP 22 能 accept、却不再发 banner"这一形态（用户态冻结），
# 也没有跨机探测（用户级 timer 只在本机跑）。结果：机器悄悄楔死，靠人 ssh 失败才发现。
#
# 判定（四态，全部可复核）：
#   OK        ssh 握手成功
#   NET-DOWN  ping 不通（网络/断电/机器关机）
#   WEDGE     ping 通 + TCP 端口可连 + ssh 无 banner  ⇒ **宿主用户态冻结**（已知修复=控制台冷重启）
#   SSHD-DOWN ping 通 + TCP 端口拒绝连接            ⇒ sshd 未运行（另一类故障，别误判成楔死）
#
# 用法：
#   wedge-watch.sh probe <host> [port]      # 单机判定，输出 "<VERDICT> <host> <细节>"
#   wedge-watch.sh sweep <host...>          # 逐机判定并汇总；CRIT 走 alert 落 guard-alerts.log
#   wedge-watch.sh selftest                 # 判别力自检（用本机假端点造四种形态）
set -uo pipefail
PORT_DEFAULT=22
CT=${CT:-6}          # TCP/ssh 连接超时
PINGW=${PINGW:-2}

_verdict() { echo "$1 $2 ${3:-}"; }

probe() {
  local host="$1" port="${2:-$PORT_DEFAULT}" tcp="refused" sshmsg rc
  local SSH="${WEDGE_SSH_BIN:-ssh}"      # 可注入：自检用它喂四种 ssh 输出，确定性判判定器
  if ! ping -c 1 -W "$PINGW" "$host" >/dev/null 2>&1; then
    _verdict NET-DOWN "$host" "ping 不通"; return 0
  fi
  timeout "$CT" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null && tcp="open"
  sshmsg=$(timeout $((CT + 4)) "$SSH" -o BatchMode=yes -o ConnectTimeout="$CT" \
             -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
             -o ServerAliveInterval=3 -o ServerAliveCountMax=2 -p "$port" "$host" true 2>&1)
  rc=$?
  if [ $rc -eq 0 ]; then _verdict OK "$host" "握手成功"; return 0; fi
  case "$sshmsg" in
    *"banner exchange"*) _verdict WEDGE "$host" "TCP 可连但无 banner ⇒ 用户态冻结（修复=控制台冷重启）";;
    *"Connection refused"*) [ "$tcp" = open ] && _verdict WEDGE "$host" "TCP 可连、ssh 拒答" || _verdict SSHD-DOWN "$host" "端口 $port 拒绝连接";;
    *"timed out"*|*"Timeout"*) [ "$tcp" = open ] && _verdict WEDGE "$host" "TCP 可连但 ssh 超时" || _verdict NET-DOWN "$host" "TCP 与 ssh 均超时";;
    *) _verdict WEDGE "$host" "ssh 异常（rc=$rc）: $(echo "$sshmsg" | head -1 | cut -c1-60)";;
  esac
}

sweep() {
  local log="${GUARD_ALERTS:-$HOME/w6-kit/guard/guard-alerts.log}" v h worst=0
  for h in "$@"; do
    v=$(probe "$h")
    echo "  $v"
    case "$v" in
      WEDGE*)    printf '%s [CRIT] %s 楔死：宿主用户态冻结（%s）——修复=控制台冷重启，remote 已无用户态可操作\n' "$(date -Is)" "$h" "${v#* }" >>"$log"; worst=2;;
      NET-DOWN*) printf '%s [CRIT] %s 网络不可达（ping 不通）\n' "$(date -Is)" "$h" >>"$log"; worst=$((worst>1?worst:1));;
      SSHD-DOWN*)printf '%s [WARN] %s sshd 未运行（端口拒绝）\n' "$(date -Is)" "$h" >>"$log";;
    esac
  done
  return $worst
}

selftest() {
  # ★判别力自检：判**判定器**而不是判网络——用注入的假 ssh 喂四种真实输出形态。
  # （第一版自检曾试图用假 banner 服务造 OK 例，结果 ssh 客户端不认 ⇒ 那条断言测的是网络不是判定器，
  #   已改为：OK 用真实端点 localhost，其余三态用桩。）
  local ok=0 bad=0
  # ★T 必须是全局：EXIT trap 在脚本体退出时才展开变量，local 那时已出栈（实测 "T: 未绑定的变量"）
  WEDGE_ST_TMP=$(mktemp -d); T="$WEDGE_ST_TMP"; trap 'rm -rf "${WEDGE_ST_TMP:-}"' EXIT
  printf '#!/bin/sh\necho "Connection timed out during banner exchange" >&2\nexit 255\n' >"$T/ssh-wedge"; chmod +x "$T/ssh-wedge"
  printf '#!/bin/sh\necho "ssh: connect to host x port 22: Connection refused" >&2\nexit 255\n' >"$T/ssh-refused"; chmod +x "$T/ssh-refused"
  # 让 WEDGE 例具备"TCP 可连"前提：本地起一个只听不说的监听
  ( timeout 20 nc -l 127.0.0.1 22312 >/dev/null 2>&1 ) & sleep 1

  _one() {  # 期望 主机 端口 [ssh桩]
    local exp="$1" host="$2" port="$3" got
    got=$(WEDGE_SSH_BIN="${4:-ssh}" probe "$host" "$port"); got="${got%% *}"
    if [ "$got" = "$exp" ]; then echo "  ✓ $exp（$host:$port）"; ok=$((ok+1));
    else echo "  ⛔ 期望 $exp 实得 $got（$host:$port）"; bad=$((bad+1)); fi
  }
  _one OK        localhost 22                                  # 真实端点
  _one WEDGE     127.0.0.1 22312 "$T/ssh-wedge"                # 桩：banner 超时 + TCP 可连
  _one SSHD-DOWN 127.0.0.1 22399 "$T/ssh-refused"              # 桩：拒绝 + 无人监听
  _one NET-DOWN  192.0.2.1 22                                  # 真实不可达（ping 先行）
  wait 2>/dev/null
  echo "  自检 $ok/$((ok+bad)) 通过"
  [ "$bad" -eq 0 ]
}

case "${1:-}" in
  probe) shift; probe "$@";;
  sweep) shift; [ $# -gt 0 ] || { echo "用法: wedge-watch.sh sweep <host...>"; exit 2; }; sweep "$@";;
  selftest) selftest;;
  *) sed -n '2,20p' "$0"; exit 2;;
esac
