#!/bin/bash
# ==============================================================
# v41_window_rollback.sh <suffix>   --  run ON EACH NODE, as liux***ya, no root.
#
# Reverses v41_window_hold.sh: restores the real guard scripts from their
# backups, verifies their md5 against the values recorded when the window was
# opened, and re-execs the units so self-heal resumes.
#
# ORDER MATTERS and is the one proven in the 2026-09-11 window:
#   1. (driver, not here) remove the V4.1 test containers
#   2. (driver, not here) `docker start` the production containers
#   3. restore the monitor + healthcheck scripts  <-- this script
#   4. kill the held MainPID so systemd re-execs the real monitor
#   5. healthcheck rebuilt LAST (the driver does this after step 4)
#   -> the monitor's own guard sees the already-running production container
#      and simply follows it with `docker wait`, which is the desired steady
#      state. It will NOT start a second stack.
#
# `docker start` (not re-running start_tp4_*.sh) is deliberate: it restores the
# exact previous container spec in seconds and keeps the rollback anchor intact.
# ==============================================================
set -uo pipefail
export HOME=/home/liux***ya

SUFFIX="${1:?usage: bash v41_window_rollback.sh <suffix>}"
HOST=$(hostname)
case "$HOST" in
  dgxspark01) ROLE=head ;;
  dgxspark02|dgxspark03|dgxspark04) ROLE=worker ;;
  *) echo "unknown host $HOST" >&2; exit 2 ;;
esac

HC=/opt/aicad-prod/scripts/healthcheck-rebuild.sh
if [ "$ROLE" = "head" ]; then
  UNIT=vllm-tp4-head.service
  MON=/home/liux***ya/w6-kit/monitor_tp4_head_v043.sh
else
  UNIT=vllm-tp4-worker.service
  MON=/home/liux***ya/w6-kit/monitor_tp4_worker_v043.sh
fi

echo "=============================================================="
echo " v41 window rollback on $HOST (role=$ROLE, suffix=$SUFFIX)"
echo "=============================================================="

# ---- step 3: restore the real scripts ------------------------------------
for f in "$HC" "$MON"; do
  if [ -f "$f.$SUFFIX" ]; then
    mv -f "$f.$SUFFIX" "$f" && echo "  restored $f   md5=$(md5sum "$f" | cut -d' ' -f1)"
  else
    echo "  NOTE   $f.$SUFFIX not present -- nothing to restore for $f"
  fi
done

# ---- step 4: re-exec so the unit picks the real monitor back up ----------
PID=$(systemctl show -p MainPID --value "$UNIT" 2>/dev/null || echo 0)
echo "  unit $UNIT MainPID=${PID:-0}"
if [ -n "${PID:-}" ] && [ "$PID" != "0" ]; then
  kill "$PID" 2>/dev/null || true
  for i in $(seq 1 20); do
    sleep 2
    NP=$(systemctl show -p MainPID --value "$UNIT" 2>/dev/null || echo 0)
    if [ -n "${NP:-}" ] && [ "$NP" != "0" ] && [ "$NP" != "$PID" ]; then
      echo "  new MainPID=$NP after $((i*2))s"
      echo "  running: $(tr '\0' ' ' < /proc/$NP/cmdline 2>/dev/null)"
      break
    fi
  done
fi

# ---- step 4b: reclaim the wedged healthcheck oneshot (head only) ----------
# WHY THIS EXISTS (found the hard way in the 2026-09-11 window):
#   The hold swaps healthcheck-rebuild.sh for a stub that loops `sleep 3600`.
#   An oneshot that was ALREADY RUNNING when the swap happened keeps the old
#   inode, so it never exits. Restoring the real script on disk does not help:
#   the unit stays `activating`, its timer reads NextElapse=infinity, and
#   self-heal is silently dead from then on -- the exact 2026-09-11 root cause.
#   Step 4 only re-execs the monitor unit, so without this step the head comes
#   back with a live service and a dead rebuild chain, and nothing says so.
HC_UNIT=vllm-healthcheck.service
HC_TIMER=vllm-healthcheck.timer
if [ "$ROLE" = "head" ]; then
  HP=$(systemctl show -p MainPID --value "$HC_UNIT" 2>/dev/null || echo 0)
  HS=$(systemctl show -p ActiveState -p SubState --value "$HC_UNIT" 2>/dev/null | tr '\n' '/')
  echo "  oneshot $HC_UNIT MainPID=${HP:-0} state=${HS:-?}"
  if [ -n "${HP:-}" ] && [ "$HP" != "0" ]; then
    # Only reclaim if it is actually wedged on the stub -- a healthy run finishes
    # in well under a minute, so anything older than GUARD_ONESHOT_RUN_MAX is stuck.
    RUN_MAX="${GUARD_ONESHOT_RUN_MAX:-120}"
    EL=$(( $(date +%s) - $(stat -c %Y /proc/$HP 2>/dev/null || date +%s) ))
    STUBBED=0
    pgrep -P "$HP" -a 2>/dev/null | grep -q 'sleep 3600' && STUBBED=1
    if [ "$STUBBED" = "1" ] || [ "$EL" -gt "$RUN_MAX" ]; then
      echo "  reclaiming wedged oneshot (age=${EL}s, stubbed=${STUBBED})"
      pgrep -P "$HP" 2>/dev/null | while read -r c; do kill -TERM "$c" 2>/dev/null || true; done
      kill -TERM "$HP" 2>/dev/null || true
      for i in $(seq 1 15); do
        sleep 2
        NOWP=$(systemctl show -p MainPID --value "$HC_UNIT" 2>/dev/null || echo 0)
        [ "${NOWP:-0}" = "0" ] && { echo "  oneshot reclaimed after $((i*2))s"; break; }
      done
    else
      echo "  oneshot is executing normally (age=${EL}s) -- leaving it alone"
    fi
  fi

  # ---- step 4c: assert the trigger chain is actually re-armed --------------
  # `release` without this assertion is a lie: the script being restored does NOT
  # prove the timer will fire. NextElapse=infinity is the only trustworthy signal.
  NX=""
  for i in $(seq 1 20); do
    NX=$(systemctl show -p NextElapseUSecMonotonic --value "$HC_TIMER" 2>/dev/null || echo "")
    case "$NX" in *infinity*|*Infinity*|"") sleep 3 ;; *) break ;; esac
  done
  case "$NX" in
    *infinity*|*Infinity*|"")
      echo "  !! ASSERTION FAILED: $HC_TIMER NextElapse=$NX -- 触发链仍未恢复，自愈是死的"
      echo "  !! 收窗**未完成**。排查：systemctl status $HC_UNIT / guardctl.sh explain $HC_UNIT"
      RC=1 ;;
    *)
      echo "  ASSERT OK: $HC_TIMER NextElapse=$NX（已重新武装）"
      RC=0 ;;
  esac
fi

# ---- evidence ------------------------------------------------------------
echo "--- restored guard digests ---"
md5sum "$HC" "$MON" 2>/dev/null | sed 's/^/  /'
echo "--- leftover held backups (should be none) ---"
ls -la "$HC".*"$SUFFIX"* "$MON".*"$SUFFIX"* 2>/dev/null | sed 's/^/  /' || echo "  none"
echo "=============================================================="
if [ "${RC:-0}" = "0" ]; then
  echo " ROLLBACK DONE on $HOST -- self-heal will resume; verify containers next"
else
  echo " ROLLBACK INCOMPLETE on $HOST -- 触发链未恢复，见上面的 ASSERTION FAILED"
fi
echo "=============================================================="
exit "${RC:-0}"
