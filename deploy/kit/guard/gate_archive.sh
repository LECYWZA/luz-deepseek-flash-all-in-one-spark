#!/bin/bash
# gate_archive.sh — 2026-09-20 H2：gate 快档节拍化+存档（timer 每 6h，head 专用）。
# 背景：gate 结果此前只进 stdout——没人跑就没人知，PASSED 不留档、FAILED 无人收。
# 本脚本跑 gate.sh（快档 ~2min、8 个小请求）取 --json 末行，追加进
# logs/gate-history.jsonl（趋势可回溯），FAIL 时走 guard 告警链（本地+syslog+可选
# hook）。采分窗口期间请 systemctl --user stop gate-archive.timer（测量纪律）。
#
# 分工（2026-09-23 补）：与 `guard-check` **不是一回事**，勿混：
#   · 本件（gate-archive.timer，user 域，6h）= 只跑 **gate 快档**（gate.sh --json）并**落历史 + 告警**；
#     **不做任何单元判定**（不碰 systemd、不判守卫在不在），且自身**恒 exit 0**。
#   · `guard-check.timer`（user 域，OnBootSec=3min + OnUnitActiveSec=15min）跑的是 `guardctl.sh check`
#     = 判定**守卫单元/前置/定时器**的治理面（"守卫还在不在"）。
#   一句话：一个管「守卫在不在」，一个管「服务本身还对不对」（gate = 端到端判据，见 gate.sh 头注
#   「容器 Up ≠ 服务可信」）。
# ⚠️ gate.sh 缺失/异常时的语义（2026-09-23 补，**当前实现 = 直接取 rc，未特判**）：
#   下面是 `out=$(…); rc=$?` 的裸取码 —— 脚本不存在/不可执行时 bash 给 126/127，
#   **同样落进 rc≠0 分支** ⇒ 存档一行 rc=126/127、并照常发 CRIT。取不到 JSON 行时
#   `"gate"` 写 `null`（`${jline:-null}`）。即"gate 跑不起来"**不会**被静默吞掉，但也不会
#   被区分成"判据挂了"与"网络/端口不通"（两者都只是 rc≠0）。要区分需另加判据，当前没有。
set -u
REPO="$HOME/dsv41-flash-dgxsparks"
HIST="$REPO/logs/gate-history.jsonl"
ALERT_LOG="$HOME/w6-kit/guard/guard-alerts.log"
mkdir -p "$REPO/logs"

out=$("$REPO/scripts/gate.sh" --json 2>&1); rc=$?
jline=$(printf '%s' "$out" | grep '^{' | tail -1)
printf '{"ts":"%s","host":"%s","rc":%d,"gate":%s}\n' \
  "$(date -Is)" "$(hostname)" "$rc" "${jline:-null}" >> "$HIST"

if [ "$rc" -ne 0 ]; then
  printf '%s [CRIT] %s periodic-gate FAILED rc=%d\n' "$(date -Is)" "$(hostname)" "$rc" >> "$ALERT_LOG" 2>/dev/null || true
  command -v logger >/dev/null 2>&1 && logger -t guard-gate -p daemon.err "periodic-gate FAILED rc=$rc（详情 $HIST）" 2>/dev/null || true
  if [ -n "${GUARD_ALERT_HOOK:-}" ]; then
    curl -sS --max-time 10 -H 'Content-Type: application/json' \
      -d "{\"severity\":\"CRIT\",\"host\":\"$(hostname)\",\"src\":\"periodic-gate\",\"text\":\"gate fast FAILED rc=$rc\",\"ts\":\"$(date -Is)\"}" \
      "$GUARD_ALERT_HOOK" >/dev/null 2>&1 || true
  fi
fi
# 存档滚动（留 2000 轮 ≈ 16 个月）
tail -2000 "$HIST" > "$HIST.tmp" 2>/dev/null && mv "$HIST.tmp" "$HIST"
exit 0
