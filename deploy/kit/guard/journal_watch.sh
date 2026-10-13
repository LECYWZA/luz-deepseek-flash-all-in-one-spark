#!/bin/bash
# journal_watch.sh — 2026-09-20 H2：journal/kernel 事件增量守望（timer 每 10min）。
# 背景：NV_ERR 396 条/oom-kill/watchdog/保活连环重启此前只在人工跑 doctor/gate 时
# 才被看见——「journal 无人持续盯」是静默错误的根缺口之一。本脚本用秒级游标增量
# 扫描，命中即写 guard-alerts.log + syslog（格式与 guardctl alert() 一致，供同一
# 外部采集面抓取）；GUARD_ALERT_HOOK 设了 URL 则 CRIT 级 POST（同 H1）。
# 只读 journal、只写自己的游标与告警文件，零副作用。
set -u
GUARD_DIR="${GUARD_DIR:-$HOME/w6-kit/guard}"
ALERT_LOG="$GUARD_DIR/guard-alerts.log"
CURSOR="$GUARD_DIR/state/journal-watch.cursor"
SCAN_LOG="$GUARD_DIR/state/journal-watch.log"   # 每轮摘要（自审计：timer 有没有真跑）

now=$(date +%s)
# 首跑：游标=now-10min（只看将来，不翻旧账——历史簇已由 doctor 归档）
[ -f "$CURSOR" ] || echo $((now - 600)) > "$CURSOR"
since=$(cat "$CURSOR" 2>/dev/null || echo $((now - 600)))
case "$since" in ''|*[!0-9]*) since=$((now - 600)) ;; esac

emit() {  # emit <CRIT|WARN> <text>
  local sev="$1"; shift
  printf '%s [%s] %s %s\n' "$(date -Is)" "$sev" "$(hostname)" "journal-watch $*" >> "$ALERT_LOG" 2>/dev/null || true
  command -v logger >/dev/null 2>&1 && logger -t guard-jwatch -p "daemon.$([ "$sev" = CRIT ] && echo err || echo warning)" "$*" 2>/dev/null || true
  if [ "$sev" = CRIT ] && [ -n "${GUARD_ALERT_HOOK:-}" ]; then
    curl -sS --max-time 10 -H 'Content-Type: application/json' \
      -d "{\"severity\":\"$sev\",\"host\":\"$(hostname)\",\"src\":\"journal-watch\",\"text\":\"$*\",\"ts\":\"$(date -Is)\"}" \
      "$GUARD_ALERT_HOOK" >/dev/null 2>&1 || true
  fi
}

kern_hits=0
# kernel 面：驱动内存失败 / OOM 击杀 / watchdog。journalctl 不可读时必须出声而非假 0
# （H9 同源教训：读不到 ≠ 零事件）。
if journalctl -k --since "@$since" --no-pager >/dev/null 2>&1; then
  _n=$(journalctl -k --since "@$since" --no-pager 2>/dev/null | grep -c 'NV_ERR_NO_MEMORY')
  [ "${_n:-0}" -gt 0 ] && { emit WARN "kernel NV_ERR_NO_MEMORY ×$_n（驱动侧内存分配失败，tail：$(journalctl -k --since "@$since" --no-pager 2>/dev/null | grep -m1 'NV_ERR_NO_MEMORY' | tail -c 120)）"; kern_hits=$((kern_hits+_n)); }
  # 2026-09-21 误报修复（子代理交叉审计实锤）：旧正则 'Out of memory|oom-kill' 会命中
  # NVRM 驱动行 "Check failed: Out of memory [NV_ERR_NO_MEMORY]"（=上面那条 WARN 的
  # 同一行）⇒ 每次图捕获瞬态都被报成「内核击杀进程」CRIT。内核真击杀的签名是
  # "invoked oom-killer" / "Killed process"；NVRM 面由上面 NV_ERR 分支单独报 WARN。
  _n=$(journalctl -k --since "@$since" --no-pager 2>/dev/null | grep -cE 'invoked oom-killer|Killed process')
  [ "${_n:-0}" -gt 0 ] && { emit CRIT "kernel OOM kill ×$_n（有进程被内核击杀——查 journalctl -k | grep -i oom 定位牺牲者）"; kern_hits=$((kern_hits+_n)); }
  _n=$(journalctl -k --since "@$since" --no-pager 2>/dev/null | grep -ciE 'watchdog.*(timeout|panic)|BUG: soft lockup')
  [ "${_n:-0}" -gt 0 ] && { emit CRIT "kernel watchdog/lockup ×$_n"; kern_hits=$((kern_hits+_n)); }
else
  emit WARN "journalctl -k 不可读（权限/环境变化）——本窗口未扫描，勿当作零事件"
fi

# 用户域：保活单元连环重启/失败（NRestarts 早期信号由 guardctl check 断言，这里
# 抓单元日志里的显式失败行作证据链）。
_u=$(journalctl --user -u dsv41-serve.service --since "@$since" --no-pager 2>/dev/null | grep -cE 'Failed with result|Start request repeated too quickly')
[ "${_u:-0}" -gt 0 ] && emit CRIT "dsv41-serve.service 失败/重启触顶 ×$_u（崩溃循环证据：journalctl --user -u dsv41-serve.service --since @$since）"

# 游标前移（留 2s 重叠防边界丢行）
# 2026-09-21：旧值 now-2 的 2s 重叠使窗口边界事件被相邻两轮各计一次（journal-watch.log
# 自审计实锤：窗起=前窗止-2s ⇒ 同一条 NVRM 行 kern_hits 翻倍）。now 在脚本开头取样，
# 扫描期间新到的日志时间戳 > now，自然落入下一窗，无丢失。
echo "$now" > "$CURSOR"
printf '%s scan[%d,%d] kern_hits=%d\n' "$(date -Is)" "$since" "$now" "$kern_hits" >> "$SCAN_LOG"
tail -200 "$SCAN_LOG" > "$SCAN_LOG.tmp" 2>/dev/null && mv "$SCAN_LOG.tmp" "$SCAN_LOG"   # 自审计日志滚动
exit 0
