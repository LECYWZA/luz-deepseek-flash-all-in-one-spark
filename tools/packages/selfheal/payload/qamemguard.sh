#!/bin/bash
# qamemguard.sh — QA 测试窗内存硬门看护（产品化单件，QA-TOOLS 20261006 任务 3）
#
# 定位（红线）：测试窗看护工具——**由窗驱动显式启动**（窗内后台进程，窗毕 stop 文件收束）；
#   绝不进生产 boot 链、不建 systemd 单元、不做守护常驻（守护常驻=用户裁定面，
#   注记见 docs/taskcards/QA-TOOLS-20261006.md §四）。本件零 HTTP：8898/8899 双口零流量。
#
# 世系：logs/VLW3B-20261005/memguard_vlw3b.sh + logs/VLW2W3-20261005/memguard_vlw2w3.sh
#   两窗实战形产品化（VLW2W3 全程零触发=防线有效；VLW3B 10:30:44 首版 GPU 占用字段探针
#   空载误触发=零实害教训件，本件探针面硬禁该字段——自检含代码断言）。
#
# 触发条件（任一即拆线，不再等用户重启——INCIDENT-VLW3-WEDGE §六.2 教训）：
#   ①任一机 MemAvailable < QMG_MEM_FLOOR_MB（缺省 6000）；
#   ②任一机 nvidia-smi driver_version 查询连续 QMG_SMI_FAILS（缺省 3）次失败/N/A。
#   探针禁项：GPU 占用（mem+used 点形字段族）禁作探针——GB10 UMA 平台该查询恒 [N/A]
#   =平台基线（PROD-RS-20261003 §七.7 + VLW3B/VLW2W3 seg0 实测），误用必空载误报。
#   健态判据=driver_version 实值（实测基线 580.173.02）；fail=N/A/空/无数字/Failed/Errno/超时。
#   MemAvailable 读不到（ssh 不可达）=记 0 不触发水位线，由 smi 三振面兜底（同窗实战形语义）。
#
# 拆线序（先存后删）：触发时刻水位四机留痕 → 四机 docker logs 先存（30s/机超时防驱动
#   楔死拖死看护）→ docker stop head → workers（head 先、workers 后）→ docker rm -f
#   → 冷却标记（缺省 10min，UMA 回收时滞；冷却期内再启动=拒绝 rc 4，窗驱动遵守）。
# 退出：$QMG_DIR/state/memguard.stop 在位=优雅退；或拆线完成后退。
# 状态行：每周期（缺省 10s）追加 $QMG_DIR/watermark-10s.log 一行
#   （TS host=MemAvail M/smi:ok|fail[/fN] ×4，与 VLW3B seg3/watermark-full.log 同格式）。
#
# 用法（窗驱动内）：
#   QMG_DIR=logs/<窗>/ QMG_HEAD_CTN=<head 容器> QMG_WORKER_CTN=<worker 容器> \
#     bash qamemguard.sh &      # 启动；echo $! > state/memguard.pid
#   touch $QMG_DIR/state/memguard.stop    # 优雅收束
#   bash qamemguard.sh --selftest         # 离线三件自检（零引擎零网络零 docker）
set -u

QMG_HEAD_HOST="${QMG_HEAD_HOST:-dgxspark01}"
QMG_WORKERS="${QMG_WORKERS:-dgxspark02 dgxspark03 dgxspark04}"
QMG_DIR="${QMG_DIR:-$HOME/luz030-opt-campaign/logs/qamemguard-$(date -u +%Y%m%d)}"
QMG_HEAD_CTN="${QMG_HEAD_CTN:-r3boot-head}"
QMG_WORKER_CTN="${QMG_WORKER_CTN:-r3boot-worker}"
QMG_MEM_FLOOR_MB="${QMG_MEM_FLOOR_MB:-6000}"
QMG_SMI_FAILS="${QMG_SMI_FAILS:-3}"
QMG_INTERVAL_S="${QMG_INTERVAL_S:-10}"
QMG_COOLDOWN_MIN="${QMG_COOLDOWN_MIN:-10}"
QMG_SSH_TO="${QMG_SSH_TO:-5}"
QMG_PROBE_TO="${QMG_PROBE_TO:-15}"
QMG_SAVE_TO="${QMG_SAVE_TO:-30}"
QMG_STOP_TO="${QMG_STOP_TO:-90}"
QMG_STOP_T="${QMG_STOP_T:-60}"
QMG_RM_TO="${QMG_RM_TO:-30}"
QMG_MAX_CYCLES="${QMG_MAX_CYCLES:-0}"   # 0=不限；自检/巡检设正数
SSHC="ssh -o BatchMode=yes -o ConnectTimeout=$QMG_SSH_TO"
WATERMARK=""; STATED=""; STOPF=""; TRIGF=""

log(){ echo "[$(date -u +%FT%TZ)] $*" | tee -a "$WATERMARK"; }

init_paths(){
  WATERMARK="$QMG_DIR/watermark-10s.log"; STATED="$QMG_DIR/state"
  mkdir -p "$STATED" "$QMG_DIR/forensics"; touch "$WATERMARK"
  STOPF="$STATED/memguard.stop"; TRIGF="$STATED/memguard-triggered"
}

# ── 探针接缝（自检以同名函数覆盖实现 mock）──────────────────────────
raw_mem(){ # $1=host → MemAvailable MB（读不到=0）
  if [ "$1" = "$QMG_HEAD_HOST" ]; then
    awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0
  else
    $SSHC "$1" "awk '/MemAvailable/{printf \"%d\", \$2/1024}' /proc/meminfo" 2>/dev/null || echo 0
  fi
}
raw_smi(){ # $1=host → driver_version 查询原样输出（含 stderr；超时/失败走 rc）
  if [ "$1" = "$QMG_HEAD_HOST" ]; then
    timeout "$QMG_PROBE_TO" nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>&1
  else
    $SSHC "$1" "timeout $QMG_PROBE_TO nvidia-smi --query-gpu=driver_version --format=csv,noheader" 2>&1
  fi
}
mem_probe(){ raw_mem "$1"; }
smi_probe(){ # → ok|fail（N/A/空/无数字/Failed/Errno/超时=fail；健态=实值驱动版本）
  local out; out=$(raw_smi "$1") || { echo fail; return; }
  case "$out" in
    *N/A*|*Failed*|*Errno*) echo fail;;
    *[0-9]*[.]*[0-9]*|*[0-9][0-9]*) echo ok;;
    *) echo fail;;
  esac
}

# ── 动作接缝（自检以记录器覆盖）──────────────────────────────────
act_save(){ # $1=host $2=ctn $3=outfile → docker logs 先存（超时防楔死拖死）
  if [ "$1" = "$QMG_HEAD_HOST" ]; then
    timeout "$QMG_SAVE_TO" docker logs "$2" > "$3" 2>&1
  else
    timeout "$QMG_SAVE_TO" $SSHC "$1" "docker logs $2" > "$3" 2>&1
  fi
}
act_stop(){ # $1=host $2=ctn → docker stop（head 先 workers 后由调用序保证）
  if [ "$1" = "$QMG_HEAD_HOST" ]; then timeout "$QMG_STOP_TO" docker stop -t "$QMG_STOP_T" "$2" >/dev/null 2>&1
  else timeout "$QMG_STOP_TO" $SSHC "$1" "docker stop -t $QMG_STOP_T $2" >/dev/null 2>&1; fi
}
act_rm(){ # $1=host $2=ctn
  if [ "$1" = "$QMG_HEAD_HOST" ]; then timeout "$QMG_RM_TO" docker rm -f "$2" >/dev/null 2>&1
  else timeout "$QMG_RM_TO" $SSHC "$1" "docker rm -f $2" >/dev/null 2>&1; fi
}

cooldown_active(){ # 冷却期内=rc0（拒启）；判据=TRIGF 最新 cooldown-until 时间戳
  [ -f "$TRIGF" ] || return 1
  local until now
  until=$(sed -n 's/^cooldown-until=\([0-9][0-9:T-]*Z\).*/\1/p' "$TRIGF" | tail -1)
  [ -n "$until" ] || return 1
  now=$(date -u +%s); [ "$(date -u -d "$until" +%s 2>/dev/null || echo 0)" -gt "$now" ]
}

teardown(){ # $1=reason —— 先存后删+按序拆线+触发时刻水位留痕+冷却标记
  local reason="$1" ts ftd rc h
  ts=$(date -u +%FT%TZ); ftd=$(date -u +%Y%m%dT%H%M%SZ)
  local FD="$QMG_DIR/forensics/memguard-teardown-$ftd"; mkdir -p "$FD"
  {
    echo "triggered=$ts reason=$reason"
    echo "watermark-at-trigger:"
    for m in "$QMG_HEAD_HOST" $QMG_WORKERS; do
      echo "  $m mem=$(mem_probe "$m")MB smi=$(smi_probe "$m")"
    done
  } | tee "$TRIGF" | tee -a "$WATERMARK" >/dev/null
  log "!! 内存硬门触发：$reason → 先存后删+按序拆线"
  # ① 先存（head → workers，各机超时）
  act_save "$QMG_HEAD_HOST" "$QMG_HEAD_CTN" "$FD/engine-head.docker.log" \
    || echo "[$(date -u +%FT%TZ)] [qamemguard] head logs 保存超时/失败" >> "$WATERMARK"
  for h in $QMG_WORKERS; do
    act_save "$h" "$QMG_WORKER_CTN" "$FD/engine-worker-$h.docker.log" \
      || echo "[$(date -u +%FT%TZ)] [qamemguard] $h logs 保存超时/失败" >> "$WATERMARK"
  done
  log "先存完成（$(du -sh "$FD" 2>/dev/null | cut -f1)）→ docker stop head→workers"
  # ② 按序拆线：head 先，workers 后
  act_stop "$QMG_HEAD_HOST" "$QMG_HEAD_CTN"; rc=$?
  echo "[$(date -u +%FT%TZ)] head stop rc=$rc" >> "$WATERMARK"
  for h in $QMG_WORKERS; do
    act_stop "$h" "$QMG_WORKER_CTN"; rc=$?
    echo "[$(date -u +%FT%TZ)] $h stop rc=$rc" >> "$WATERMARK"
  done
  act_rm "$QMG_HEAD_HOST" "$QMG_HEAD_CTN"
  for h in $QMG_WORKERS; do act_rm "$h" "$QMG_WORKER_CTN"; done
  # ③ 冷却标记（窗驱动遵守；期内再启动=rc4 拒绝）
  echo "cooldown-until=$(date -u -d "+$QMG_COOLDOWN_MIN min" +%FT%TZ)（+${QMG_COOLDOWN_MIN}min，UMA 回收时滞）" >> "$TRIGF"
  log "拆线完成；${QMG_COOLDOWN_MIN}min 冷却至 $(date -u -d "+$QMG_COOLDOWN_MIN min" +%FT%TZ)"
  touch "$STATED/memguard-toredown"
}

watch_loop(){ # 主循环：10s 状态行 → watermark；触发即拆线；stop 文件优雅退
  local -A SMIFAIL
  local n=0 ts line ma sp h fired
  while [ ! -f "$STOPF" ]; do
    [ "$QMG_MAX_CYCLES" -gt 0 ] && [ "$n" -ge "$QMG_MAX_CYCLES" ] && return 0
    n=$((n + 1))
    ts=$(date -u +%FT%TZ); line="$ts"; fired=""
    for h in "$QMG_HEAD_HOST" $QMG_WORKERS; do
      ma=$(mem_probe "$h"); sp=$(smi_probe "$h")
      if [ "$sp" = fail ]; then SMIFAIL[$h]=$(( ${SMIFAIL[$h]:-0} + 1 )); else SMIFAIL[$h]=0; fi
      line="$line $h=${ma:-0}M/smi:${sp}${SMIFAIL[$h]:+/f${SMIFAIL[$h]}}"
      # 水位线：0<ma<floor 触发（ma=0=读不到，由 smi 三振面兜底）；先触先记（任一即拆线）
      [ -z "$fired" ] && [ "${ma:-0}" -lt "$QMG_MEM_FLOOR_MB" ] && [ "${ma:-0}" -gt 0 ] \
        && fired="MemAvailable $h=${ma}M<${QMG_MEM_FLOOR_MB}M"
      [ -z "$fired" ] && [ "${SMIFAIL[$h]:-0}" -ge "$QMG_SMI_FAILS" ] \
        && fired="nvidia-smi $h 连续${SMIFAIL[$h]}次失败/N/A"
    done
    echo "$line" >> "$WATERMARK"
    if [ -n "$fired" ]; then teardown "$fired"; return 0; fi
    sleep "$QMG_INTERVAL_S"
  done
  log "qamemguard 退出（stop 文件在位）"
  return 0
}

start(){ # 启动面：冷却判拒 → 横幅 → 主循环
  init_paths
  if cooldown_active; then
    echo "[qamemguard] 拒绝启动：冷却期内（$(sed -n 's/^cooldown-until=//p' "$TRIGF" | tail -1)）" >&2
    echo "[$(date -u +%FT%TZ)] qamemguard 拒绝启动（冷却未满）" >> "$WATERMARK"
    return 4
  fi
  log "qamemguard 启动 head=$QMG_HEAD_HOST workers=[$(echo $QMG_WORKERS)] ctn=$QMG_HEAD_CTN/$QMG_WORKER_CTN floor=${QMG_MEM_FLOOR_MB}M smi_fails=$QMG_SMI_FAILS interval=${QMG_INTERVAL_S}s cooldown=${QMG_COOLDOWN_MIN}min"
  watch_loop
}

# ── 离线三件自检（零引擎零网络零 docker；接缝 mock，临时目录隔离）────────
selftest(){
  local ok=1 TD rc
  asrt(){ [ "$2" = "$3" ] && echo "PASS $1" || { echo "FAIL $1（got=[$2] want=[$3]）"; ok=0; }; }
  want(){ if [ "$1" = 0 ]; then echo "PASS $2"; else echo "FAIL $2"; ok=0; fi; }

  # 代码断言：探针面禁 GPU 占用字段（字面量拼接防自匹配；grep -c 零计数走数值判定=L1 教训）
  local BAN="memor"; BAN="${BAN}y.used"
  local nban; nban=$(grep -c "$BAN" "$0" || true)
  asrt "代码断言：禁占用字段零引用" "$nban" "0"

  fresh(){ TD=$(mktemp -d /tmp/qamemguard-selftest-XXXXXX); QMG_DIR="$TD"; init_paths; }
  cleanup(){ rm -rf "$TD"; }

  # ① 假低水位触发：dgxspark03 MemAvailable=5000 → 拆线序正确（先存后删、head 先 workers 后）
  fresh
  raw_mem(){ case "$1" in dgxspark03) echo 5000;; *) echo 60000;; esac; }
  raw_smi(){ echo "580.173.02"; }
  ACTS=()
  act_save(){ ACTS+=("save:$2"); : > "$3"; return 0; }
  act_stop(){ ACTS+=("stop:$2"); return 0; }
  act_rm(){ ACTS+=("rm:$2"); return 0; }
  QMG_MAX_CYCLES=1
  watch_loop
  asrt "①触发原因=低水位" "$(sed -n 's/^triggered=[^ ]* reason=//p' "$TRIGF")" "MemAvailable dgxspark03=5000M<6000M"
  asrt "①拆线动作数（存4+停4+删4）" "${#ACTS[@]}" "12"
  asrt "①拆线序" "$(printf '%s\n' "${ACTS[@]}")" "$(printf '%s\n' \
    save:$QMG_HEAD_CTN save:$QMG_WORKER_CTN save:$QMG_WORKER_CTN save:$QMG_WORKER_CTN \
    stop:$QMG_HEAD_CTN stop:$QMG_WORKER_CTN stop:$QMG_WORKER_CTN stop:$QMG_WORKER_CTN \
    rm:$QMG_HEAD_CTN rm:$QMG_WORKER_CTN rm:$QMG_WORKER_CTN rm:$QMG_WORKER_CTN)"
  [ -f "$STATED/memguard-toredown" ]; want $? "①toredown 标记在位"
  grep -q "watermark-at-trigger" "$TRIGF"; want $? "①触发时刻水位四机留痕"
  grep -q "^cooldown-until=" "$TRIGF"; want $? "①冷却标记在位"
  cleanup

  # ② N/A 平台回归：占用字段恒 N/A 的 GB10 平台态（健态 driver_version）→ 零误报；
  #    driver_version 恒 [N/A] → 恰第 3 周期触发（三振回归）
  fresh
  raw_mem(){ echo 60000; }
  raw_smi(){ echo "580.173.02, 580.173.02"; }   # 健态（平台占用字段 N/A 与本件无关——不读该字段）
  ACTS=(); act_save(){ return 0; }; act_stop(){ return 0; }; act_rm(){ return 0; }
  QMG_MAX_CYCLES=2
  watch_loop
  [ ! -f "$TRIGF" ]; want $? "②N/A 平台健态零触发（2 周期）"
  [ "$(grep -o 'smi:ok' "$WATERMARK" | wc -l)" -ge 8 ]; want $? "②状态行 smi:ok ×4 机 ×2 周期"
  raw_smi(){ echo "[N/A]"; }                    # driver_version 退变=恒 N/A
  QMG_MAX_CYCLES=3
  watch_loop
  asrt "②driver_version 三振恰第 3 周期触发" \
    "$(sed -n 's/^triggered=[^ ]* reason=//p' "$TRIGF")" "nvidia-smi dgxspark01 连续3次失败/N/A"
  cleanup

  # ③ 冷却与 stop 文件：冷却未满=rc4 拒启；冷却已过=放行；stop 文件=优雅退
  fresh
  echo "cooldown-until=$(date -u -d '+5 min' +%FT%TZ)" > "$TRIGF"
  rc=0; start || rc=$?
  asrt "③冷却未满拒启 rc" "$rc" "4"
  echo "cooldown-until=$(date -u -d '-5 min' +%FT%TZ)" > "$TRIGF"
  raw_mem(){ echo 60000; }; raw_smi(){ echo "580.173.02"; }
  ACTS=(); act_save(){ return 0; }; act_stop(){ return 0; }; act_rm(){ return 0; }
  QMG_MAX_CYCLES=1
  start; [ $? -eq 0 ]; want $? "③冷却已过放行"
  cleanup
  fresh
  touch "$STOPF"
  watch_loop
  grep -q "退出（stop 文件在位）" "$WATERMARK"; want $? "③stop 文件优雅退"
  cleanup

  echo "SELFTEST" "$([ $ok = 1 ] && echo PASS || echo FAIL)"
  [ $ok = 1 ] || return 1
  return 0
}

# ── 入口 ────────────────────────────────────────────────────────
main(){
  local arg
  while [ $# -gt 0 ]; do
    case "$1" in
      --selftest) selftest; return $?;;
      --dir) QMG_DIR="$2"; shift;;
      --head-ctn) QMG_HEAD_CTN="$2"; shift;;
      --worker-ctn) QMG_WORKER_CTN="$2"; shift;;
      --once) QMG_MAX_CYCLES=1;;   # 单周期采样即退（异常仍按拆线序处置）
      *) echo "[qamemguard] 未知参数：$1（支持 --selftest/--dir/--head-ctn/--worker-ctn/--once）" >&2; return 2;;
    esac
    shift
  done
  start
}

main "$@"
