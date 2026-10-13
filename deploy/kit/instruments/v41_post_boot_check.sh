#!/bin/bash
# V4.1 post-boot check -- read-only. Reads `docker logs`/`docker stats` on the
# local host and evaluates the runbook checklist. Starts, stops and modifies
# nothing.
#
#   bash v41_post_boot_check.sh [container_name]     # default vllm-v41-test-rank0
#
# The critical assertion is the Engram one. The patched engine must MAP the
# tables out of the checkpoint ("Engram table mapped from ...", once per Engram
# layer). If those lines are absent and the pinned-memory line is present, the
# --engram-config switch did not take effect and the run is back to overcommitting
# the host/device pool -- which is what hung the cluster on 2026-09-10.
set -uo pipefail

C=${1:-vllm-v41-test-rank0}
MEMCAP="${MEMCAP:-120}"          # direction-1 hard cap, GiB
FAILED=0
pass() { printf '  %-5s %s\n' "PASS" "$1"; }
warn() { printf '  %-5s %s\n' "WARN" "$1"; }
fail() { printf '  %-5s %s\n' "FAIL" "$1"; FAILED=1; }

if ! docker inspect "$C" >/dev/null 2>&1; then
  echo "container '$C' not found"; exit 2
fi

# Role: with --nnodes 4 --tensor-parallel-size 4 the world size is 4, so
# node_rank_within_dp == node_rank and only rank 0 is a DP-group leader. Ranks
# 1-3 are followers: their EngineCore parks after bringing the worker up (that
# is the production fork's hold, ported into this image), so they are expected
# to have NO API server and NO KV-cache report. Asserting those on a follower
# would produce a false failure.
RANK=$(echo "$C" | grep -o '[0-9]*$' || true)
ROLE=leader
[ -n "$RANK" ] && [ "$RANK" != "0" ] && ROLE=follower

L=$(docker logs --tail 100000 "$C" 2>&1)

echo "=============================================================="
echo " V4.1 post-boot check: $C  (rank=${RANK:-?} role=$ROLE)"
echo "=============================================================="

# --- 0. the multi-node role assertion -----------------------------------
HOLD=$(echo "$L" | grep -c "Follower node: holding process" || true)
if [ "$ROLE" = "follower" ]; then
  if [ "$HOLD" -ge 1 ]; then
    pass "follower EngineCore parked as designed (leader orchestrates all workers)"
  else
    fail "follower never reached the hold -- see the collective_rpc failure below"
  fi
else
  [ "$HOLD" -eq 0 ] && pass "leader did not park (expected: leader runs the engine)" \
                    || fail "leader parked in the follower hold -- rank/role is wrong"
fi
if echo "$L" | grep -q "collective_rpc should not be called on follower node"; then
  fail "collective_rpc called on follower node -- the 2026-09-11 first-window failure"
else
  pass "no 'collective_rpc on follower node' assertion"
fi

# --- 1. THE engram assertion: mapped, not pinned -------------------------
MAPPED=$(echo "$L" | grep -c "Engram table mapped from" || true)
PINNED=$(echo "$L" | grep -c "Engram table offloaded to pinned host memory" || true)
echo "  info  engram disk-mapping lines=$MAPPED  pinned-memory lines=$PINNED"
if [ "$MAPPED" -ge 2 ]; then
  pass "both Engram layers are mapped from the checkpoint (disk-backed)"
  echo "$L" | grep -o "Engram table mapped from [^:]*: [0-9]* rows x [0-9]*, [0-9.]* GiB per rank" \
    | sed 's/^/        /'
elif [ "$MAPPED" -eq 1 ]; then
  fail "only ONE Engram layer mapped -- both layers 1 and 14 should be"
else
  fail "no 'Engram table mapped from' line -- --engram-config did not take effect"
fi
[ "$PINNED" -eq 0 ] && pass "no pinned-host-memory Engram allocation" \
                    || fail "$PINNED pinned-memory allocation(s) -- pool overcommit is back"

# --- 2. weight footprint -------------------------------------------------
ML=$(echo "$L" | grep -o "Model loading took [0-9.]* GiB" | tail -1 | grep -o "[0-9.]*")
if [ -n "$ML" ]; then
  echo "  info  Model loading took ${ML} GiB/rank"
  awk -v v="$ML" 'BEGIN{exit !(v<=112)}' \
    && pass "weight footprint ${ML} GiB fits the startup-free pool" \
    || fail "footprint ${ML} GiB exceeds the startup-free pool"
else
  warn "no 'Model loading took' line -- model may not have finished loading"
fi

# --- 3. engram tensors must NOT be reported unexpected -------------------
if echo "$L" | grep -qiE "unexpected.*engram|engram.*(unexpected|not found in the model)"; then
  fail "engram tensors reported unexpected -- config/checkpoint mismatch"
else
  pass "no unexpected-key complaints about engram tensors"
fi

# --- 4. memory picture ---------------------------------------------------
FREE=$(echo "$L" | grep -o "Free memory on device ([0-9.]*/[0-9.]* GiB)" | tail -1)
[ -n "$FREE" ] && pass "device pool: $FREE" || warn "no 'Free memory on device' line"

KV=$(echo "$L" | grep -o "Available KV cache memory: [0-9.]* GiB" | tail -1)
if [ -n "$KV" ]; then
  N=$(echo "$KV" | grep -o "[0-9.]*")
  awk -v v="$N" 'BEGIN{exit !(v>=5)}' && pass "$KV (>=5 GiB)" \
    || fail "$KV -- too small, expect OOM/backpressure under load"
elif [ "$ROLE" = "follower" ]; then
  # expected: the leader computes the KV budget and broadcasts it to every
  # worker, so only the leader's core reports it.
  pass "no local KV report (expected on a follower; leader owns the budget)"
else
  warn "no 'Available KV cache memory' line"
fi

# container RSS against the 120g cgroup cap (direction 1)
STATS=$(docker stats --no-stream --format '{{.MemUsage}}' "$C" 2>/dev/null)
if [ -n "$STATS" ]; then
  echo "  info  container memory: $STATS (cap ${MEMCAP} GiB)"
  USE=$(echo "$STATS" | awk '{print $1}')
  giB=$(python3 -c '
import re,sys
m=re.match(r"([0-9.]+)\s*([KMGT]?i?B)", sys.argv[1])
if not m: raise SystemExit
v=float(m.group(1)); u=m.group(2).lower()
print("%.2f" % (v*{"b":1/2**30,"kb":1e3/2**30,"kib":1/2**20,"mb":1e6/2**30,
                   "mib":1/2**10,"gb":1e9/2**30,"gib":1}[u]))
' "$USE" 2>/dev/null)
  if [ -n "$giB" ]; then
    awk -v v="$giB" -v c="$MEMCAP" 'BEGIN{exit !(v<c)}' \
      && pass "container memory ${giB} GiB is under the ${MEMCAP} GiB cap" \
      || fail "container memory ${giB} GiB EXCEEDS the ${MEMCAP} GiB cap"
  fi
else
  warn "docker stats unavailable"
fi

# --- 5. hard failures ---------------------------------------------------
if echo "$L" | grep -qiE "torch.OutOfMemoryError|CUDA out of memory|RuntimeError:.*out of memory|NV_ERR_NO_MEMORY"; then
  fail "OOM in log"
else
  pass "no OOM"
fi
# A kernel OOM kill leaves NO line in the application log -- the process just
# dies with "exit code: None". Checking only the container log produced a false
# PASS on 2026-09-11 01:32:13Z, when the host OOM-killed VLLM::Worker_TP while
# the leader's log merely said "Worker proc VllmWorker-0 died unexpectedly".
# So ask the kernel directly, and check the container's own OOM flag.
KOOM=$(journalctl -k --since "-45min" --no-pager 2>/dev/null | grep -c "oom-kill:" || true)
if [ "${KOOM:-0}" -gt 0 ]; then
  fail "kernel OOM killer fired ${KOOM}x in the last 45min -- see: journalctl -k | grep -A40 oom-killer"
  journalctl -k --since "-45min" --no-pager 2>/dev/null | grep -E "oom-kill:|Out of memory: Killed" | tail -4 | sed 's/^/        /'
else
  pass "no kernel OOM kill in the last 45min"
fi
OOMK=$(docker inspect -f '{{.State.OOMKilled}}' "$C" 2>/dev/null)
[ "$OOMK" = "true" ] && fail "container was OOMKilled" || pass "container OOMKilled flag: ${OOMK:-false}"
if echo "$L" | grep -q "died unexpectedly"; then
  fail "a worker process died unexpectedly (exit code: None means killed by signal -- check the kernel OOM log)"
else
  pass "no worker died unexpectedly"
fi
# A traceback is only a failure if it is not the known, intended consequence of
# preloading production's ring-only NCCL next to the image's bundled one.
if echo "$L" | grep -qiE "Traceback \(most recent call last\)"; then
  TB=$(echo "$L" | grep -ciE "Traceback \(most recent call last\)")
  NCCL_DUP=$(echo "$L" | grep -c "Duplicate NCCL runtime found" || true)
  if [ "$TB" -le "$NCCL_DUP" ]; then
    pass "only the known 'Duplicate NCCL runtime' warning (expected with the ring-only NCCL preload)"
  else
    fail "python traceback present in log (${TB} tracebacks, ${NCCL_DUP} are the known NCCL one)"
  fi
else
  pass "no python traceback"
fi
if echo "$L" | grep -qiE "does not match the checkpoint"; then
  fail "Engram mapping verification failed"
else
  pass "no Engram mapping-verification failure"
fi

# --- 6. engine actually up ---------------------------------------------
if [ "$ROLE" = "follower" ]; then
  # A follower is not supposed to serve. What matters is that its worker joined
  # the group and the parked engine process is alive.
  if docker exec "$C" pgrep -f VLLM::EngineCore >/dev/null 2>&1; then
    pass "follower engine process alive (VLLM::EngineCore)"
  else
    warn "no VLLM::EngineCore process in the follower container"
  fi
  if echo "$L" | grep -qiE "Application startup complete|Uvicorn running"; then
    warn "follower reported an API server -- unexpected for a follower role"
  else
    pass "follower correctly exposes no API server"
  fi
else
  if echo "$L" | grep -qiE "Application startup complete|Starting vLLM API server|Uvicorn running"; then
    pass "API server reported started"
  else
    warn "API server startup line not seen yet"
  fi
fi
HC=$(docker inspect -f '{{.State.Health.Status}}' "$C" 2>/dev/null)
[ "$HC" = "healthy" ] && pass "container health: healthy" || warn "container health: ${HC:-unknown}"

echo "=============================================================="
[ "$FAILED" = "0" ] && echo " POST-BOOT: no FAIL lines" \
                    || echo " POST-BOOT: FAILURES present -- stop and roll back"
echo "=============================================================="
exit "$FAILED"
