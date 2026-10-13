#!/usr/bin/env bash
# r3-watchdog.sh — 运行期联动看门狗（INCIDENT-2026-09-30-13:26 F-2）
# 背景：head UMA 楔死（进程活着但不响应）时 workers 无联动停机 → 连锁 OOM。
# 双哨部署：01=head 哨（全栈守卫+水位门）；02=worker 哨（head 亡故检测+workers 联动，
#           防 head 楔死时哨兵同亡）。两哨拆除动作幂等（docker rm -f），双触发无害。
# 触发条件（任一）：
#   head 哨：①容器 running 且 龄>BOOT_GRACE 后 health 连续 FAIL_N 次失败
#            ②容器 running 且 MemAvailable < WATER_M（UMA 超卖先兆，立即拆）
#   worker 哨：①head health 连续 FAIL_N 次失败 且（head ssh 不通 或 head 容器非 running）
#              ②本机 MemAvailable < WATER_M（worker 在跑时）
# 用法： r3-watchdog.sh head | worker   （systemd 常驻，30s 一轮）
set -u

ROLE="${1:?usage: r3-watchdog.sh head|worker}"
INTERVAL=15
FAIL_N=4            # 4×15s=60s health 失败即拆（事故实测跌穿快于 30s 粒度）
BOOT_GRACE=$((15 * 60))     # 靴窗宽限：容器启动后 15 分钟内不要求 health
# 点3（2026-09-30）水位线对齐 0.2.8/0.2.9 实战口径（w6-kit oom_gate：
# `-w 6 -f 1.5 -n 3 --iv 2 -a -e 1`）。主守卫=系统级 oom-gate-monitor（2s
# 采样、止损前带现场快照、PAT 已扩 r3boot-*）；本哨水位=纯兜底位：红线取
# 同值 1.5G 但 3 连确认 @15s（45s ≫ oom_gate 的 6s）——保证实战件先出手、
# 现场取证不丢；本哨只在 oom_gate 失效（服务死/被卸）时兜底拆除。
WATER_M=1500                # 水位红线（MemAvailable MB；= oom_gate -f 1.5）
WATER_WARN_M=6000           # 预警线（= oom_gate -w 6）
WATER_N=3                   # 红线连续确认次数（= oom_gate -n 3；兜底慢环）
HEAD_IP="192.168.5.186"
API_PORT=8898
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8)
WORKERS=(dgxspark02 dgxspark04 dgxspark03)
INCIDENT_DIR="$HOME/l10-incident"

log()  { printf '[%s] [r3wd-%s] %s\n' "$(date -Is)" "$ROLE" "$*"; }

teardown() {  # teardown <原因>
  local why="$1" ts; ts=$(date +%Y%m%d-%H%M%S)
  local out="$INCIDENT_DIR/watchdog-${ROLE}-${ts}.log"
  mkdir -p "$INCIDENT_DIR"
  { log "TEARDOWN 触发：$why"
    echo "--- 证据 ---"
    awk '/MemAvailable/{printf "MemAvailable=%dM\n", $2/1024}' /proc/meminfo
    docker ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null | grep r3boot || echo "(local no r3boot)"
    docker inspect -f '{{.Name}} state={{.State.Status}} started={{.State.StartedAt}}' r3boot-head 2>/dev/null
  } > "$out" 2>&1
  log "TEARDOWN 执行（证据落 $out）"
  docker rm -f r3boot-head >/dev/null 2>&1
  for h in "${WORKERS[@]}"; do ssh "${SSH_OPTS[@]}" "$h" "docker rm -f r3boot-worker" >/dev/null 2>&1; done
  log "TEARDOWN 完成（四机）"
}

memavail() { awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo; }
ctn_state() { docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null | tr -d '\r'; }
ctn_age_s() {
  local st; st=$(docker inspect -f '{{.State.StartedAt}}' "$1" 2>/dev/null | tr -d '\r')
  [[ -n "$st" ]] && echo $(( $(date +%s) - $(date -d "$st" +%s) )) || echo 0
}

log "启动（interval=${INTERVAL}s fail_n=${FAIL_N} grace=${BOOT_GRACE}s water=${WATER_M}M）"

fail=0
wfail=0
HOLD_F="/tmp/r3-watchdog-hold"       # 量具 hold：census/kineto 采样窗内暂停 health 计数
HOLD_MAX_S=$((25 * 60))              # hold 自动过期（防脚本暴毙后永久静默）
while true; do
  if [[ "$ROLE" == "head" ]]; then
    if [[ "$(ctn_state r3boot-head)" == "running" ]]; then
      m=$(memavail)
      if (( m < WATER_M )); then
        (( wfail += 1 ))
        log "红线 MemAvailable=${m}M < ${WATER_M}M（${wfail}/${WATER_N} 连；主守卫=oom_gate@2s）"
        if (( wfail >= WATER_N )); then
          teardown "head 水位红线 ${WATER_N}×${INTERVAL}s 确认 MemAvailable=${m}M（oom_gate 兜底位）"
        fi
      else
        wfail=0
      fi
      if (( m < WATER_WARN_M )); then
        log "WARN head 水位 ${m}M < ${WATER_WARN_M}M（盯跌速；红线 ${WATER_M}M）"
      fi
      hold_active=0
      if [[ -f "$HOLD_F" ]]; then
        hage=$(( $(date +%s) - $(stat -c %Y "$HOLD_F" 2>/dev/null || date +%s) ))
        if (( hage > HOLD_MAX_S )); then
          log "hold 文件过期（${hage}s > ${HOLD_MAX_S}s）——撤销并恢复 health 计数"
          rm -f "$HOLD_F"
        else
          hold_active=1
        fi
      fi
      if (( $(ctn_age_s r3boot-head) > BOOT_GRACE )); then
        if curl -fsS --max-time 5 "http://127.0.0.1:${API_PORT}/health" >/dev/null 2>&1; then
          fail=0
        elif (( hold_active )); then
          (( fail += 1 ))
          log "health 失败 ${fail}/${FAIL_N} 但 hold 活跃（量具采样窗）——不计入楔死判据"
          fail=0
        else
          (( fail += 1 ))
          log "health 失败 ${fail}/${FAIL_N}（MemAvail=${m}M）"
          if (( fail >= FAIL_N )); then
            teardown "head health 连续 ${FAIL_N}×${INTERVAL}s 失败（UMA 楔死形态）"
            fail=0
          fi
        fi
      fi
    else
      fail=0; wfail=0   # 无栈/靴窗：静默
    fi

  elif [[ "$ROLE" == "worker" ]]; then
    if [[ "$(ctn_state r3boot-worker)" == "running" ]]; then
      m=$(memavail)
      if (( m < WATER_M )); then
        (( wfail += 1 ))
        log "红线 MemAvailable=${m}M < ${WATER_M}M（${wfail}/${WATER_N} 连；主守卫=oom_gate@2s）"
        if (( wfail >= WATER_N )); then
          teardown "worker(02) 水位红线 ${WATER_N}×${INTERVAL}s 确认 MemAvailable=${m}M（oom_gate 兜底位）"
        fi
      else
        wfail=0
      fi
      if (( m < WATER_WARN_M )); then
        log "WARN worker 水位 ${m}M < ${WATER_WARN_M}M（盯跌速；红线 ${WATER_M}M）"
      fi
      if curl -fsS --max-time 5 "http://${HEAD_IP}:${API_PORT}/health" >/dev/null 2>&1; then
        fail=0
      else
        (( fail += 1 ))
        log "head health 探测失败 ${fail}/${FAIL_N}（MemAvail=${m}M）"
        if (( fail >= FAIL_N )); then
          # 确认 head 真亡：ssh 不通 或 head 容器非 running；若 head 仍活则留给 head 哨
          if ! ssh "${SSH_OPTS[@]}" dgxspark01 "true" 2>/dev/null \
             || [[ "$(ssh "${SSH_OPTS[@]}" dgxspark01 "docker inspect -f '{{.State.Status}}' r3boot-head 2>/dev/null" | tr -d '\r')" != "running" ]]; then
            teardown "head 亡故确认（health×${FAIL_N} 失败且 ssh/容器死）——workers 联动拆除"
          else
            log "head health 失败但 head 容器+ssh 存活——交给 head 哨处理，本哨复位"
          fi
          fail=0
        fi
      fi
    else
      fail=0; wfail=0
    fi
  fi
  sleep $INTERVAL
done
