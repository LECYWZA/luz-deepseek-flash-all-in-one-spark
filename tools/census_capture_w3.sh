#!/usr/bin/env bash
# census_capture_w3.sh — census v3 分窗自动停流式采集（INC-20261004-UMA 重构）
#
# 守卫世系（logs/R1CERT3-20261004/census_capture_w1.sh ← r1recert ← r12）全保留：
#   G1 水位门 / 干跑探针谷地板(A0H 律) / watchdog hold ≤25min / trace cap /
#   flush 账 memlog / safe_run+--mem-limit-mb 兜底 / 禁 kernel_census_v2.py。
# v3 增量（全针对 OOM 根因=census 采集侧 kineto 整窗缓冲净吃 13GB+）：
#   1. 分窗：每窗 /start_profile {num_steps:N, profile_by_stage:true,
#      profile_stages:[phase]}——引擎到步自动停+自动 flush 落盘（v1 路径
#      profiler_manager._profile_batch_predicate → _stop_profile →
#      export_chrome_trace），调用方零 stop_profile；相切换（prefill↔decode）
#      也即时 flush，窗=纯相位连续步。
#   2. 显式 with_stack:false + record_shapes:false：SGLANG_PROFILE_WITH_STACK/
#      RECORD_SHAPES 默认 true（tokenizer_control_mixin.py:405-413），不显式关
#      则每事件带栈/形状 args（r12 trace with_stack=1 record_shapes=1 实证），
#      kineto 缓冲与 trace 体积成倍膨胀——族分类只用 kernel name，全可关。
#   3. 预算硬门（教义 #31 操作化，预登记；深挖 4cdf22e 终裁后修订——引爆相=
#      stop_profile 的 **flush 峰**（599k「flush 24-28GiB」教训复发），非稳态
#      缓冲单独作案）：
#      a) 开窗门（fail-loud）：只在 MemAvailable > max(已测单窗净吃)×3 + 4096MB
#         时才准开窗——即「开窗余量 − 净吃预算 − 单窗 flush 峰 ≥ 4GiB」；
#         首窗以登记先验 W3_FIRST_WINDOW_BUDGET_MB(2048) 代入实测值。
#      b) 窗中水位看护（flush 前最后一道）：轮询等窗落盘期间盯 MemAvailable，
#         跌破干跑谷地板（PROBE_FLOOR_MB，A0H 律同值）即刻 POST /stop_profile
#         提前收窗——提前 flush = 更少缓冲事件 = 更小 flush 峰；截断窗照常
#         解析聚合，truncated 标记入窗账 meta 与 memlog（落档不静默）。
#      c) 净吃账（flush 峰含在内）：净吃=开窗前 vs flush 落盘后 MemAvailable
#         差，逐窗入 memlog，首窗实测值即后续火卡的登记先验。
#      分窗本身天然压 flush 峰：峰∝单窗事件量（整窗 13GB+ 的事故形态被
#      结构性消灭），预算门是叠加护栏而非替代。
#   4. 即采即析即删：窗 trace docker cp 出 → census_window.py（流式，
#      census_stream 内核零改动薄包装）→ 窗账 JSON → 删容器侧窗 trace；
#      本地留档 ≤W3_KEEP_MB(100)MB，超则删（聚合不依赖原始窗 trace）。
#   5. 收尾 census_aggregate.py 跨窗聚合 → ${TAG}_census_w3.json（字段兼容
#      现行 census 三件套判据读数）+ ${TAG}_census_w3_arpeaks.json。
#
# 用法:
#   bash census_capture_w3.sh <TAG> [sizes...]        # 默认 decode 相窗
#   PHASE=prefill bash census_capture_w3.sh <TAG> 65536   # prefill 相窗
# 环境旋钮: PHASE=decode|prefill W3_WINDOWS=1 W3_STEPS=128 W3_PREFILL_STEPS=20
#   W3_RUNS=2（深挖 4cdf22e 降载推荐：64k×2runs 单窗；32k 档对 G2 判据可达性
#   =冗余，W1 只采 64k 相）W3_FIRST_WINDOW_BUDGET_MB=2048 W3_KEEP_MB=100
#   W3_WINDOW_WAIT_S=300 W3_GAP_S=5 MEM_GATE_GB=8 PROBE_FLOOR_MB=12288
#   BENCH_TIMEOUT_S=1800 TRACE_CAP_MB=1024 CENSUS_MEM_LIMIT_MB=512
#   IMAGE_CTN=r3boot-head API=... PROF=...
set -euo pipefail

TAG="${1:?usage: census_capture_w3.sh <tag> [sizes...]}"
shift || true
SIZES="${*:-65536}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${W3_OUT:-$HOME/luz030-opt-campaign/logs/R1CERT3-20261004}"
API="${API:-http://127.0.0.1:8898}"
PROF="${PROF:-/tmp/prof-censusv3}"
IMAGE_CTN="${IMAGE_CTN:-r3boot-head}"
BENCH="$OUT/w1_longctx_bench.py"

CENSUS_STREAM="$HOME/v41-opt/tools/census_stream.py"
WINDOW_PY="$HERE/census_window.py"
AGG_PY="$HERE/census_aggregate.py"

PHASE="${PHASE:-decode}"
WINDOWS="${W3_WINDOWS:-1}"
STEPS="${W3_STEPS:-128}"
PREFILL_STEPS="${W3_PREFILL_STEPS:-20}"
FIRST_BUDGET_MB="${W3_FIRST_WINDOW_BUDGET_MB:-2048}"
KEEP_MB="${W3_KEEP_MB:-100}"
WINDOW_WAIT_S="${W3_WINDOW_WAIT_S:-300}"
GAP_S="${W3_GAP_S:-5}"
RUNS="${W3_RUNS:-2}"
MAXTOK="${W3_MAXTOK:-64}"

MEM_GATE_GB="${MEM_GATE_GB:-8}"
PROBE_FLOOR_MB="${PROBE_FLOOR_MB:-12288}"
BENCH_TIMEOUT_S="${BENCH_TIMEOUT_S:-1800}"
TRACE_CAP_MB="${TRACE_CAP_MB:-1024}"
CENSUS_MEM_LIMIT_MB="${CENSUS_MEM_LIMIT_MB:-512}"
HOLD_F=/tmp/r3-watchdog-hold
MEMLOG="$OUT/census_w3_memlog.txt"

mem_avail_mb() { awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo; }

# ── G1 水位门（w1 世系原样）──────────────────────────────────────────
AVAIL=$(mem_avail_mb)
echo "[G1] MemAvailable=${AVAIL}MB (gate=$((MEM_GATE_GB*1024))MB)"
[ "$AVAIL" -lt $((MEM_GATE_GB*1024)) ] && { echo "[G1] REFUSE"; exit 41; }

# ── 干跑探针（无 kineto；谷地板=A0H 律，w1 世系原样）────────────────
echo "[probe] dry-run 1 round（无 kineto）BEGIN $(date -u +%T)"
( while :; do awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo; sleep 2; done ) \
  > /tmp/censusv3_probe.mem &
PROBE_PID=$!
sleep 1
timeout "$BENCH_TIMEOUT_S" python3 "$BENCH" --base-url "$API/v1" \
  --sizes $SIZES --runs 1 --max-tokens "$MAXTOK" >/dev/null 2>&1 \
  || { kill $PROBE_PID 2>/dev/null || true; echo "[probe] dry-run 失败"; exit 42; }
kill $PROBE_PID 2>/dev/null || true; sleep 2
VALLEY=$(sort -n /tmp/censusv3_probe.mem | head -1)
echo "[probe] dry-run 谷 MemAvailable=${VALLEY}MB（地板=${PROBE_FLOOR_MB}MB）"
[ "$VALLEY" -lt "$PROBE_FLOOR_MB" ] && { echo "[probe] REFUSE: 谷 ${VALLEY}MB < 地板（A0H 律）"; exit 44; }
cp /tmp/censusv3_probe.mem "$OUT/census_probe_valley_${TAG}.mem"

docker exec "$IMAGE_CTN" rm -rf "$PROF" 2>/dev/null || true
docker exec "$IMAGE_CTN" mkdir -p "$PROF"

# safe_run 世系（r1recert 同法：有则用，无则退回解析器自检）
if [[ -x "$HOME/v41-opt/tools/safe_run.sh" ]]; then
  RUNNER=("$HOME/v41-opt/tools/safe_run.sh")
else
  echo "[guard] safe_run.sh 不存在，退回 census_window.py 自身 --mem-limit-mb 自检"
  RUNNER=()
fi

NET_MAX=0           # 已测单窗净吃峰值（预算门用；首窗以 FIRST_BUDGET_MB 先验代入）
WINS_PARSED=0

# ── 窗循环 ──────────────────────────────────────────────────────────
start_window() {  # $1=wid $2=num_steps $3=stages_json
  local PRE=$(mem_avail_mb)
  local BUDGET=$(( NET_MAX > FIRST_BUDGET_MB ? NET_MAX : FIRST_BUDGET_MB ))
  local NEED=$(( BUDGET * 3 + 4096 ))
  echo "[BUDGET] win#$1 开窗前 MemAvailable=${PRE}MB（单窗净吃先验=${BUDGET}MB, 需>${NEED}MB）"
  if [ "$PRE" -le "$NEED" ]; then
    echo "[BUDGET] win#$1 REFUSE: ${PRE}MB ≤ 3×${BUDGET}MB+4096MB（#31: 余量−净吃−flush峰≥4GiB）"
    return 45
  fi

  touch "$HOLD_F"; trap 'rm -f "$HOLD_F"' EXIT
  echo "[hold] watchdog health 计数暂停（本窗 ≤25min）"

  # 快照先于 start_profile（防引擎 flush 快于轮询起拍，新文件误入 BEFORE 集）
  docker exec "$IMAGE_CTN" sh -c "ls '$PROF'/*.trace.json.gz 2>/dev/null" \
    > /tmp/censusv3_win_before.ls || true

  curl -sf -X POST "$API/start_profile" -H 'Content-Type: application/json' \
    -d "{\"output_dir\":\"$PROF\",\"num_steps\":$2,\"profile_by_stage\":true,\
\"profile_stages\":$3,\"activities\":[\"CPU\",\"GPU\"],\
\"with_stack\":false,\"record_shapes\":false,\
\"profile_prefix\":\"w3w$1\"}" >/dev/null \
    || { rm -f "$HOLD_F"; echo "[G2] win#$1 start_profile 失败"; return 46; }

  echo "$PRE" > /tmp/censusv3_win_pre.mem
  return 0
}

wait_window_trace() {  # $1=wid → 回显容器内新 trace 路径（超时空）
  # 窗中水位看护（flush 前最后一道护栏）：等落盘期间盯 MemAvailable，
  # 跌破干跑谷地板即提前收窗——更少缓冲事件=更小 flush 峰（fail-loud 落档）。
  local WID="$1" T0=$(date +%s) NEW="" TRUNC=0 MID
  local BEFORE; BEFORE=$(cat /tmp/censusv3_win_before.ls)
  echo 0 > /tmp/censusv3_win_trunc
  while :; do
    MID=$(mem_avail_mb)
    if [ "$MID" -lt "$PROBE_FLOOR_MB" ] && [ "$TRUNC" -eq 0 ]; then
      TRUNC=1
      echo "[BUDGET] win#$WID 窗中水位塌陷 ${MID}MB<地板${PROBE_FLOOR_MB}MB → \
提前收窗截断 flush 峰（fail-loud）" >&2
      curl -s -X POST "$API/stop_profile" >/dev/null 2>&1 || true
      echo 1 > /tmp/censusv3_win_trunc
      echo "$(date -Is) tag=${TAG} win=$WID TRUNCATED mid_window_avail=${MID}MB" >> "$MEMLOG"
    fi
    local NOW; NOW=$(docker exec "$IMAGE_CTN" sh -c "ls '$PROF'/*.trace.json.gz 2>/dev/null" || true)
    NEW=$(comm -13 <(printf '%s\n' "$BEFORE" | sort) <(printf '%s\n' "$NOW" | sort) | head -1)
    if [[ -n "$NEW" ]]; then
      # 落盘稳定门：两次采样字节数不变才宣告（防 cp 到半写 gz）
      local S1 S2
      S1=$(docker exec "$IMAGE_CTN" stat -c%s "$NEW" 2>/dev/null || echo 0)
      sleep 4
      S2=$(docker exec "$IMAGE_CTN" stat -c%s "$NEW" 2>/dev/null || echo 0)
      if [ "$S1" = "$S2" ] && [ "$S1" != "0" ]; then echo "$NEW"; return 0; fi
    fi
    if [ $(( $(date +%s) - T0 )) -ge "$WINDOW_WAIT_S" ]; then
      curl -s -X POST "$API/stop_profile" >/dev/null 2>&1 || true  # 防御性收口
      echo ""; return 0
    fi
    sleep 2
  done
}

finish_window() {  # $1=wid $2=phase $3=num_steps $4=容器trace路径
  local WID="$1" PH="$2" NS="$3" CTR="$4"
  curl -s -X POST "$API/stop_profile" >/dev/null 2>&1 || true  # 幂等防御（自动停后无害）
  rm -f "$HOLD_F"
  sleep 5   # flush 落盘 + kineto 缓冲释放结算窗

  local POST=$(mem_avail_mb)
  local PRE=$(cat /tmp/censusv3_win_pre.mem)
  local NET=$(( PRE - POST ))
  local TRUNC; TRUNC=$(cat /tmp/censusv3_win_trunc 2>/dev/null || echo 0)
  if [ "$NET" -gt "$NET_MAX" ]; then NET_MAX=$NET; fi
  echo "[BUDGET] win#$WID 净吃=${NET}MB（pre=${PRE} post=${POST} truncated=${TRUNC}）→ 已测单窗峰值=${NET_MAX}MB"
  echo "$(date -Is) tag=${TAG} win=$WID phase=$PH pre=${PRE}MB post=${POST}MB net=${NET}MB truncated=${TRUNC}" >> "$MEMLOG"

  if [[ -z "$CTR" ]]; then
    echo "[G2] win#$WID ${WINDOW_WAIT_S}s 内未见窗 trace（负载断流或到步未触发）→ 弃窗"
    return 47
  fi
  local LOCAL_GZ="$OUT/${TAG}_w3w${WID}.trace.json.gz"
  docker cp "$IMAGE_CTN:$CTR" "$LOCAL_GZ"

  local BYTES; BYTES=$(stat -c%s "$LOCAL_GZ")
  echo "[G3] win#$WID trace size=$((BYTES/1024/1024))MB (cap=${TRACE_CAP_MB}MB)"
  if [ "$BYTES" -gt $((TRACE_CAP_MB * 1024 * 1024)) ]; then
    echo "[G3] win#$WID REFUSE: 窗 trace 超过 ${TRACE_CAP_MB}MB"; rm -f "$LOCAL_GZ"; return 43
  fi

  # [v3.1 回移 R1CERT3B fix@0c0bdc3 勘误⑥] WINS_PARSED 增量 rc 门控：census_window 拒出（零窗账）不计入，fail-loud rc40
  if "${RUNNER[@]}" python3 "$WINDOW_PY" "$LOCAL_GZ" \
      --json "$OUT/${TAG}_w3w${WID}.census.json" \
      --window-id "$WID" --label "${TAG}" --phase "$PH" --req-num-steps "$NS" \
      --profile-stages "[\"$PH\"]" \
      --mem-limit-mb "$CENSUS_MEM_LIMIT_MB" --census-stream "$CENSUS_STREAM" \
      --meta mem_pre_mb="$PRE" --meta mem_post_mb="$POST" --meta net_mb="$NET" \
      --meta truncated="$TRUNC" --meta trace_mb=$((BYTES/1024/1024)); then
    WINS_PARSED=$((WINS_PARSED + 1))
  else
    echo "[G2] win#$WID census_window 拒出（零窗账不计入，fail-loud）"; return 40
  fi

  docker exec "$IMAGE_CTN" rm -f "$CTR"     # 容器侧即删（下窗 ls 快照干净）
  if [ "$BYTES" -gt $((KEEP_MB * 1024 * 1024)) ]; then
    echo "[keep] win#$WID 本地窗 trace ${KEEP_MB}MB 以上，聚合后删除（窗账 JSON 已存）"
    rm -f "$LOCAL_GZ"
  fi
  return 0
}

send_one_request() {  # 单请求驱动（prefill 相窗用：窗臂后再发 64k 请求）
  python3 - "$API/v1" $SIZES <<'PYEOF'
import sys, uuid
sys.path.insert(0, "/home/liux***ya/dsv41-flash-dgxsparks/bench")
from sd_bench import Client, DE_PROSE_PROMPT, FILLER_UNIT, estimate_tokens
base, sizes = sys.argv[1], [int(x) for x in sys.argv[2:]]
c = Client(base, None, 1800)
for n in sizes:
    salt = uuid.uuid4().hex[:8]
    header = f"[censusv3 {salt}]\nIgnore the filler below. {DE_PROSE_PROMPT}\n"
    fill = max(1, n - estimate_tokens(header))
    o = c.stream(header + FILLER_UNIT * fill, 64)
    print(f"[w3-req] size={n} pt={o['prompt_tokens']} gen={o['completion']}")
PYEOF
}

BENCH_PID=""
cleanup() {
  rm -f "$HOLD_F"
  [[ -n "$BENCH_PID" ]] && kill "$BENCH_PID" 2>/dev/null || true
}
trap cleanup EXIT

WID=0
while [ "$WID" -lt "$WINDOWS" ]; do
  if [ "$PHASE" = "decode" ]; then
    # decode 相：后台连续负载，窗在 decode 稳态相依次开
    if ! kill -0 "$BENCH_PID" 2>/dev/null; then
      if [[ -n "$BENCH_PID" ]]; then echo "[load] bench 已结束，停止开新窗"; break; fi
      echo "[load] 后台负载 BEGIN $(date -u +%T)（runs=$RUNS sizes=$SIZES maxtok=$MAXTOK）"
      timeout "$BENCH_TIMEOUT_S" python3 "$BENCH" --base-url "$API/v1" \
        --sizes $SIZES --runs "$RUNS" --max-tokens "$MAXTOK" \
        --json-out "$OUT/${TAG}_w3_bench.json" > "$OUT/${TAG}_w3_bench.log" 2>&1 &
      BENCH_PID=$!
      # by-stage 窗由引擎等 decode 相（prefill 不消耗窗），无需人等稳态；
      # 3s 仅让 bench 起步（64k×2runs 总负载 ~1min 级，等久了反而错过相位）
      sleep 3
    fi
    start_window "$WID" "$STEPS" '["decode"]' || { RC=$?; [ "$RC" -eq 45 ] && break || exit "$RC"; }
    TRACE=$(wait_window_trace "$WID")
    finish_window "$WID" decode "$STEPS" "$TRACE" || true
  else
    # prefill 相：窗臂 → 单 fresh 64k 请求（16 chunk 步），相切换自动 flush
    start_window "$WID" "$PREFILL_STEPS" '["prefill"]' || { RC=$?; [ "$RC" -eq 45 ] && break || exit "$RC"; }
    send_one_request >/dev/null 2>&1 || echo "[G2] win#$WID 驱动请求非零（仍收窗）"   # [v3.1 回移 R1CERT3B fix@0c0bdc3 勘误③] timeout 不可 exec bash 函数（原样=恒 rc127 驱动零发包；时限由 Client(base,None,1800) 内持）
    TRACE=$(wait_window_trace "$WID")
    finish_window "$WID" prefill "$PREFILL_STEPS" "$TRACE" || true
  fi
  WID=$((WID + 1))
  sleep "$GAP_S"
done

[[ -n "$BENCH_PID" ]] && { kill "$BENCH_PID" 2>/dev/null || true; wait "$BENCH_PID" 2>/dev/null || true; }
BENCH_PID=""

echo "[G4] 窗循环结束: parsed=$WINS_PARSED/$WID"
if [ "$WINS_PARSED" -lt 1 ]; then
  echo "CENSUS-W3-FAIL($TAG): 零窗账，拒聚合"; exit 1
fi

"${RUNNER[@]}" python3 "$AGG_PY" "$OUT/${TAG}_w3w*.census.json" \
  --json "$OUT/${TAG}_census_w3.json" \
  --arpeaks "$OUT/${TAG}_census_w3_arpeaks.json" \
  --expect-windows "$WINS_PARSED"

POST_ALL=$(mem_avail_mb)
echo "[G4] 全程 END: MemAvailable=${POST_ALL}MB（起点=${AVAIL}MB）"
echo "$(date -Is) tag=${TAG} phase=$PHASE windows_parsed=${WINS_PARSED} net_max=${NET_MAX}MB avail_end=${POST_ALL}MB" >> "$MEMLOG"
echo "CENSUS-W3-DONE($TAG phase=$PHASE windows=$WINS_PARSED net_max=${NET_MAX}MB)"
