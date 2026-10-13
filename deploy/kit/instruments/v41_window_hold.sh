#!/bin/bash
# ==============================================================
# v41_window_hold.sh <suffix>   --  run ON EACH NODE, as liux***ya, no root.
#
# Parks every automatic-restart / rebuild guard on this node so a V4.1 test
# boot can own the shared memory pool without production's self-heal chain
# fighting it for the GPU and the ports.
#
# What is held (and why each one matters):
#   /opt/aicad-prod/scripts/healthcheck-rebuild.sh
#       invoked by vllm-healthcheck.timer (every 60s, oneshot service). On a
#       failed probe it runs `docker ps -aq --filter name=tp4-rank` and
#       `docker rm -f` -- with `-a` that includes STOPPED containers, so it
#       would delete the very production containers we intend to `docker start`
#       during rollback.  MUST be held before production is stopped.
#   /home/liux***ya/w6-kit/monitor_tp4_head_v043.sh     (ExecStart of vllm-tp4-head.service)
#   /home/liux***ya/w6-kit/monitor_tp4_worker_v043.sh   (ExecStart of vllm-tp4-worker.service)
#       these recreate the production stack; the head one also ssh-removes the
#       worker containers on the other three nodes.
#
# How the hold works (REX-HOLD, proven in the 2026-09-11 window):
#   the unit is Type=simple, Restart=always, User=liux***ya. Replacing the
#   ExecStart target's content and then killing the main PID makes systemd
#   re-exec the same path -- now the parked version. No root, no unit edits.
#   The swap uses write-to-temp + mv, which is atomic: the still-running old
#   bash keeps its open inode and is never corrupted mid-read.
#
# Reversal: v41_window_rollback.sh <suffix>
# ==============================================================
set -uo pipefail
export HOME=/home/liux***ya

SUFFIX="${1:?usage: bash v41_window_hold.sh <suffix>   e.g. 20260911T0140Z-v41window2}"
ROLE="${ROLE:-auto}"

HOST=$(hostname)
case "$HOST" in
  dgxspark01) ROLE=head ;;
  dgxspark02|dgxspark03|dgxspark04) ROLE=worker ;;
  *) echo "unknown host $HOST" >&2; exit 2 ;;
esac

HOLD_SLEEP='#!/bin/bash
# v41 WINDOW HOLD -- intentionally parks this unit. Auto-restart guards on this
# node are suspended so a V4.1 test boot can own the shared memory pool.
# Nothing here touches docker. Restore with v41_window_rollback.sh.
export HOME=/home/liux***ya
echo "[v41-hold] hold active on '"$HOST"' since $(date -Is); unit parked, no container action will be taken"
while :; do sleep 3600; done
'

hmm() { echo "  $*"; }

# ---- helper: hold one file atomically -------------------------------------
hold_file() {
  local f="$1" desc="$2"
  if [ ! -f "$f" ]; then
    hmm "SKIP  $f (absent)"
    return 0
  fi
  if [ -f "$f.$SUFFIX" ]; then
    hmm "SKIP  $f.$SUFFIX already exists -- refusing to overwrite an existing backup"
    return 0
  fi
  if [ "${DRYRUN:-0}" = "1" ]; then
    hmm "WOULD HOLD  $f  ($desc)"
    hmm "            backup -> $f.$SUFFIX (md5=$(md5sum "$f" | cut -d' ' -f1))"
    return 0
  fi
  cp -p "$f" "$f.$SUFFIX" || { echo "ABORT: backup of $f failed" >&2; return 1; }
  local tmp; tmp=$(mktemp "$f.hold.XXXXXX") || return 1
  printf '%s' "$HOLD_SLEEP" > "$tmp"
  chmod --reference="$f" "$tmp" 2>/dev/null || chmod 755 "$tmp"
  mv -f "$tmp" "$f" || { echo "ABORT: swap of $f failed" >&2; return 1; }
  hmm "HELD  $f  ($desc)"
  hmm "      backup -> $f.$SUFFIX  md5=$(md5sum "$f.$SUFFIX" | cut -d' ' -f1)"
  return 0
}

echo "=============================================================="
echo " v41 window hold on $HOST  (role=$ROLE, suffix=$SUFFIX)"
echo "=============================================================="

FAIL=0
hold_file /opt/aicad-prod/scripts/healthcheck-rebuild.sh "healthcheck rebuild (would rm -f stopped containers)" || FAIL=1

if [ "$ROLE" = "head" ]; then
  hold_file /home/liux***ya/w6-kit/monitor_tp4_head_v043.sh "head self-heal monitor" || FAIL=1
  UNIT=vllm-tp4-head.service
else
  hold_file /home/liux***ya/w6-kit/monitor_tp4_worker_v043.sh "worker self-heal monitor" || FAIL=1
  UNIT=vllm-tp4-worker.service
fi
[ "$FAIL" = 0 ] || { echo "ABORT: a hold step failed; nothing was killed. Fix and re-run." >&2; exit 1; }

# ---- now park the running monitor (systemd re-execs the held script) -------
if [ "${DRYRUN:-0}" = "1" ]; then
  echo "  DRYRUN: would send SIGTERM to MainPID of $UNIT and let systemd re-exec the held script"
  echo "DRYRUN complete on $HOST -- nothing was modified"
  exit 0
fi
PID=$(systemctl show -p MainPID --value "$UNIT" 2>/dev/null)
echo "  unit  $UNIT MainPID=${PID:-0}"
if [ -n "${PID:-}" ] && [ "$PID" != "0" ]; then
  kill "$PID" 2>/dev/null || { echo "ABORT: cannot signal $PID" >&2; exit 1; }
  echo "  sent SIGTERM to $PID; systemd Restart=always will re-exec the held script"
  for i in $(seq 1 20); do
    sleep 2
    NP=$(systemctl show -p MainPID --value "$UNIT" 2>/dev/null)
    if [ -n "${NP:-}" ] && [ "$NP" != "0" ] && [ "$NP" != "$PID" ]; then
      echo "  new MainPID=$NP after $((i*2))s"
      PID="$NP"
      break
    fi
  done
else
  echo "  NOTE: unit not running (MainPID=0); the held script will be picked up on next start"
fi

echo "--- verification ---"
sleep 3
if [ -n "${PID:-}" ] && [ "$PID" != "0" ]; then
  CMDLINE=$(tr '\0' ' ' < /proc/$PID/cmdline 2>/dev/null)
  echo "  running: $CMDLINE"
  case "$CMDLINE" in
    *monitor_tp4_head*|*monitor_tp4_worker*)
      if grep -q 'WINDOW HOLD' "$(echo "$CMDLINE" | awk '{print $NF}')" 2>/dev/null; then
        echo "  OK: the unit is now running the parked hold script"
      else
        echo "  *** WARNING: the unit's script does NOT contain the hold marker -- inspect before proceeding ***"
      fi ;;
    *) echo "  *** WARNING: unexpected cmdline for the unit -- inspect before proceeding ***" ;;
  esac
  ps -o pid,etimes,stat,args -p "$PID" 2>/dev/null | tail -1 | sed 's/^/  /'
fi
echo "  healthcheck-rebuild.sh now: $(md5sum /opt/aicad-prod/scripts/healthcheck-rebuild.sh | cut -d' ' -f1) (held no-op)"
echo "  held files in place:"
ls -la /opt/aicad-prod/scripts/healthcheck-rebuild.sh* /home/liux***ya/w6-kit/monitor_tp4_*_v043.sh* 2>/dev/null | sed 's/^/    /'
echo "=============================================================="
echo " HOLD INSTALLED on $HOST"
echo "=============================================================="
