#!/usr/bin/env bash
# census_capture_r12.sh TAG CONC — r12 活栈(:8898, SPEC=1 DSPARK) census 采集【护栏版 r12.1】
# 用法: bash census_capture_r12.sh r12 1   → 产出 r12_census_c1.{json,trace.json.gz,arpeaks.json}
# 模式继承 census_capture.sh: 预热→start_profile→bench→stop→docker cp→census_stream 解析
#
# ── 防护栏（2026-09-30 四节点冻结事故后新增，见 reports/23-census护栏设计-V41新基座.md）──
#   G1 内存门禁   : 启动前查 MemAvailable，低于 $MEM_GATE_GB(默认8G) 拒绝启动
#   G2 轮数上限   : 每次 bench 调用加 timeout $BENCH_TIMEOUT_S(默认900s)，防止失控长跑
#   G3 体积上限   : docker cp 后检查 trace 体积，超过 $TRACE_CAP_GB(默认4G) 告警并拒解析
#   G4 flush 观测 : start_profile 前后快照 MemAvailable，输出 delta（喂给 flush 观测协议）
#
# 环境变量（均可覆盖默认值）:
#   MEM_GATE_GB=8    BENCH_TIMEOUT_S=900    TRACE_CAP_GB=4
set -euo pipefail
TAG="${1:?usage: census_capture_r12.sh <tag> <conc>}"
CONC="${2:-pr}"
OUT="$HOME/l10-quality/r12"
REPO="$HOME/dsv41-flash-dgxsparks"
B="python3 $REPO/bench/sd_bench.py --base-url http://127.0.0.1:8898/v1 --key-file /dev/null"
API=http://127.0.0.1:8898
PROF=/tmp/prof-r12

MEM_GATE_GB="${MEM_GATE_GB:-8}"        # G1: 引擎常驻~107G/121G，剩余<8G 时任何采集都可能压垮 UMA
BENCH_TIMEOUT_S="${BENCH_TIMEOUT_S:-900}"  # G2: 单次 bench 上限 15min
TRACE_CAP_GB="${TRACE_CAP_GB:-4}"      # G3: 单 trace 体积上限（历史 r11 ~数百MB/份，4G 是宽松上限）

mem_avail_mb() { awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo; }

# ── G1 内存门禁：任何动作之前 ─────────────────────────────────────────────
AVAIL=$(mem_avail_mb)
GATE_MB=$((MEM_GATE_GB * 1024))
echo "[G1] MemAvailable=${AVAIL}MB (gate=${GATE_MB}MB)"
if [[ "$AVAIL" -lt "$GATE_MB" ]]; then
  echo "[G1] REFUSE: MemAvailable ${AVAIL}MB < gate ${GATE_MB}MB — 引擎常驻内存已逼近上限，" >&2
  echo "     kineto 全 rank flush 峰值可能触发四节点用户态冻结（2026-09-30 事故）。" >&2
  echo "     处置：确认无泄漏/重启引擎后再采集。强制绕过：MEM_GATE_GB=<更低值> bash $0 ..." >&2
  exit 41
fi

mkdir -p "$OUT"
docker exec r3boot-head rm -rf "$PROF" 2>/dev/null || true

# ── G2 预热一轮（排除首用编译噪声），带超时上限 ─────────────────────────
timeout "$BENCH_TIMEOUT_S" $B --mode pr --sizes ${PR_SIZES:-16384} --runs ${PR_RUNS:-2} >/dev/null 2>&1 \
  || { echo "[G2] warmup bench 超时(${BENCH_TIMEOUT_S}s)或失败，中止"; exit 42; }

# ── G4 flush 前快照 ──────────────────────────────────────────────────────
PRE_MB=$(mem_avail_mb)
echo "[G4] flush-window BEGIN: MemAvailable=${PRE_MB}MB — 此窗口内禁止并发 SSH 大操作（rsync/大文件 cp/第二个采集）"

# 量具 hold：kineto 采样窗内引擎 health 瞬态失速（A0S 晨靴同款、当时无看门狗静默
# 自愈；A5b 16:46 被看门狗 4×15s 判死=量具×守卫交互事故）。hold 只豁免 health
# 计数；水位红线/oom_gate 全时在位。25min 自动过期由看门狗侧执行。
HOLD_F=/tmp/r3-watchdog-hold
touch "$HOLD_F"; trap 'rm -f "$HOLD_F"' EXIT
echo "[hold] 看门狗 health 计数暂停（水位/oom_gate 不受影响）"

curl -s -X POST "$API/start_profile" -H 'Content-Type: application/json' \
  -d "{\"output_dir\":\"$PROF\"}" >/dev/null
timeout "$BENCH_TIMEOUT_S" $B --mode pr --sizes ${PR_SIZES:-16384} --runs ${PR_RUNS:-2} >/dev/null 2>&1 \
  || { echo "[G2] profiled bench 超时(${BENCH_TIMEOUT_S}s)或失败，仍尝试 stop_profile 收尾"; }
# stop_profile 响应可能 500（flush 已完成），良性
curl -s -X POST "$API/stop_profile" >/dev/null 2>&1 || true
rm -f "$HOLD_F"
sleep 3

# ── G4 flush 后对比：delta 落盘供观测协议归档 ────────────────────────────
POST_MB=$(mem_avail_mb)
DELTA_MB=$((PRE_MB - POST_MB))
echo "[G4] flush-window END: MemAvailable=${POST_MB}MB (delta=${DELTA_MB}MB)"
echo "$(date -Is) tag=${TAG} c=${CONC} pre=${PRE_MB}MB post=${POST_MB}MB delta=${DELTA_MB}MB" \
  >> "$OUT/flush_memlog.txt"
if [[ "$DELTA_MB" -gt $((MEM_GATE_GB * 1024)) ]]; then
  echo "[G4] WARN: flush 期间 MemAvailable 掉了 ${DELTA_MB}MB（>gate），下次采集前先核对是否泄漏" >&2
fi

TRACES=$(docker exec r3boot-head sh -c "ls -t $PROF/*.trace.json.gz 2>/dev/null | head -1")
if [[ -z "$TRACES" ]]; then
  docker exec r3boot-head sh -c "find /tmp -name '*.trace.json.gz' -mmin -5 2>/dev/null | head -3"
  echo "no trace found"; exit 1
fi
docker cp "r3boot-head:$TRACES" "$OUT/${TAG}_census_c${CONC}.trace.json.gz"

# ── G3 profiler 输出体积上限 ─────────────────────────────────────────────
TRACE_BYTES=$(stat -c%s "$OUT/${TAG}_census_c${CONC}.trace.json.gz")
CAP_BYTES=$((TRACE_CAP_GB * 1024 * 1024 * 1024))
echo "[G3] trace size=$((TRACE_BYTES/1024/1024))MB (cap=${TRACE_CAP_GB}GB)"
if [[ "$TRACE_BYTES" -gt "$CAP_BYTES" ]]; then
  echo "[G3] REFUSE: trace 超过 ${TRACE_CAP_GB}GB，拒绝进入解析（防解析器内存放大）。" >&2
  echo "     处置：缩短 profile 时长或降低 conc 后重采。" >&2
  exit 43
fi

# 解析器层护栏: 优先用 safe_run.sh 硬限（systemd-run 可用性待窗口后核验），否则退回解析器自检
# 2026-10-07 断链修复（OPEN-28 §十六）：原硬编码 ~/v41-opt/ 旧版解析器（a5ca6eae，无 CUDA-port 规则）
# 产生 const_int 兜底标签伪影（族名换版被误读为后端翻转）；该树 15:26 归档后此步必断。
# 现钉仓内 canonical 副本 tools/census_stream.py（eeb498b7，含 CUDA-port 规则），锚点同日重登记。
CENSUS="$HOME/luz030-opt-campaign/tools/census_stream.py"
if [[ -x "$HOME/luz030-opt-campaign/tools/safe_run.sh" ]]; then
  RUNNER=("$HOME/luz030-opt-campaign/tools/safe_run.sh")
else
  echo "[guard] safe_run.sh 不存在，退回 census_stream.py 自身 --mem-limit-mb 自检"
  RUNNER=()
fi
"${RUNNER[@]}" python3 "$CENSUS" "$OUT/${TAG}_census_c${CONC}.trace.json.gz" \
  --top 45 --json "$OUT/${TAG}_census_c${CONC}.json" \
  --arpeaks "$OUT/${TAG}_census_c${CONC}_arpeaks.json" \
  --mem-limit-mb "${CENSUS_MEM_LIMIT_MB:-512}"
echo "CENSUS-DONE($TAG c$CONC)"
