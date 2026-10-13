#!/bin/bash
# oom_gate.sh — GB10 四机内存门（2026-09-14 集群 OOM 事故 A1 落地；判据=事故报告 §6.4 F1/G1-G4）
#
# 事故教训（勿删）：
#  - GB10 UMA：设备分配不进 cgroup ⇒ docker --memory 拦不住；宿主 global OOM 不分生产/测试。
#  - MemAvailable 在高压下不稳定且口径不可靠（F-26/O-3）⇒ 一律用
#    有效空闲 = MemFree + Cached + SReclaimable − Shmem。
#  - "healthy" 是结论不是证据：任何窗口必须附 NVRM/host-oom 增量与有效空闲最低点（F11）。
#
# 用法：
#   oom_gate.sh pre [-t GIB] [--strict-containers]   # 冷启动准入（拒启=rc=1，非告警）
#       -t                 有效空闲阈值，默认 110 GiB（G1）
#       --strict-containers 附加断言四机无 vllm-v41-* 容器残留（仅首个 rank 用；
#                           串行准入的后续 rank 会看到先起者，不应启用）
#   oom_gate.sh baseline > file                       # 采窗口基线（NVRM/host-oom 计数）
#   oom_gate.sh post file                             # 窗口收口：任一增量>0 ⇒ rc=1（判假绿，结论作废）
#   oom_gate.sh monitor [-f GIB] [-n N] [-a] [--iv S] # boot 期常驻守护（本机）：
#       -f                有效空闲地板，默认 8 GiB（F6）
#       -w                警戒线（**只记日志，不动作**），默认 0=关。-w 与 -f 是两个不同的东西：
#                         -f 是"止损线"，它的动作是 docker stop（不可逆）；-w 是"开始留意的线"。
#                         2026-09-16 加：此前 "正常" 与 "逼近止损线" 之间**没有任何信号**，
#                         重载把余量吃到多少只能靠人工看。有了 -w 就能在重载期读出趋势。
#                         建议配法：`-w 6 -f 1.5 -n 3 --iv 10 -a`
#                         （6 = 期望的运营余量线；1.5 = 现行安全地板，也是唯一会动手的值。
#                          ★2026-09-23 由 3 下调——用户收尾令第 4 条；理由与两条余量事实见
#                          `../adr/ADR-004-three-gib-floor-guard.md` §0.1）
#       -n                连续破地板次数才动作，默认 3
#       -a                动作=docker stop 本机 vllm-v41-*（默认仅告警）
#       --iv              采样间隔秒，默认 30
#       -e                ★应急线（2026-09-18 加）：有效空闲 < 该值 ⇒ **单采样立即止损**，
#                         不等 -n 连续计数（-f 的 3×10s 在滑向 host-OOM 的最后 1 GiB 里太慢）。
#                         与 -f 的分工：-f 1.5 = 运营包络外的提前止损（可容忍确认延迟）；
#                         -e 1 = 最后一道断路器（用户令：剩余内存 ≤1G 时及时 kill 推理）。
#                         建议配法更新：`-w 6 -f 1.5 -n 3 --iv 10 -a -e 1`（0=关，默认关）
#   oom_gate.sh snapshot [why]                        # 手动落一份站点现场（不起守护）
#   oom_gate.sh monitor ... --once                    # 单采样后退出（自检/演练；默认常驻）
#
# 环境旋钮：
#   V41_GATE_SNAP=0          关掉止损前现场快照（默认 1=开）
#   V41_GATE_SNAP_DIR=DIR    快照根目录（默认 ~/w6-kit/oom-gate/logs/site）
#   V41_GATE_ALERTS=FILE     告警落盘位置（默认 ~/w6-kit/guard/guard-alerts.log）
#   V41_GATE_NO_LOGGER=1     自检用：不写 syslog（防演练制造假事故痕迹）
set -uo pipefail

HOSTS=(localhost dgxspark02 dgxspark03 dgxspark04)
V41_PAT="${V41_PAT:-vllm-v41-\\|dsv41-}"  # BRE：\| = 或
LOG_PREFIX="[oom-gate]"
ALERTS_F="${V41_GATE_ALERTS:-$HOME/w6-kit/guard/guard-alerts.log}"

run_on() {  # $1=host $2=cmd（stdin 一律隔离：防 ssh/子壳吃掉外层 while read 的输入）
  local h=$1 c=$2
  if [ "$h" = "localhost" ]; then bash -c "$c" </dev/null; else ssh -n -o ConnectTimeout=8 "$h" "$c" </dev/null 2>/dev/null; fi
}

eff_idle_kb() {  # 输出 KiB
  awk '/^MemFree:/{f=$2}/^Cached:/{c=$2}/^SReclaimable:/{s=$2}/^Shmem:/{m=$2}END{print f+c+s-m}' /proc/meminfo
}

mode="${1:-}"; shift || true
FILE_ARG=""
TH=110; FLOOR=8; NCNT=3; ACT=0; IV=30; STRICT=0; LOCAL=0; WARN=0; EMER=0; ONCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    -t) TH="${2:?}"; shift 2 ;;
    -f) FLOOR="${2:?}"; shift 2 ;;
    -w) WARN="${2:?}"; shift 2 ;;
    -e) EMER="${2:?}"; shift 2 ;;
    -n) NCNT="${2:?}"; shift 2 ;;
    --iv) IV="${2:?}"; shift 2 ;;
    --once) ONCE=1; shift ;;
    -a) ACT=1; shift ;;
    --strict-containers) STRICT=1; shift ;;
    --local) LOCAL=1; shift ;;
    -*) echo "$LOG_PREFIX 未知参数 $1" >&2; exit 2 ;;
    *) FILE_ARG="$1"; shift ;;
  esac
done

# 内核日志读取链：dmesg 受限(假 0)时必须回退 journalctl -k，否则 post 判据被静默废掉
kern_log() {
  local out
  out=$(dmesg 2>/dev/null)
  if [ -n "$out" ]; then printf '%s' "$out"; else journalctl -k --no-pager 2>/dev/null; fi
}

# ── 站点快照（2026-09-22 加；用户令②"应急分支加保护"）
# 动机：9/21 与 9/22 两次事故里，docker stop 一执行**现场就被销毁**——进程树、PSI、
# cgroup 峰值、页缓存/脏页态势全没了，事后只剩 10s 粒度主机线与容器日志，归因只能拼图。
# 止损前先落一份现场：成本几百毫秒，换来事后可复核。
# 纪律（防"保护动作本身变成事故"）：
#   ① 永不改变止损决定——快照/同步全失败也照旧 docker stop，退出码不变；
#   ② 每个采集器独立 `timeout`，fork/exec 在 <1 GiB 下可能失败，失败只是少几行；
#   ③ 绝不 fsync 整机：sync 也带时间盒（有界放弃）。
SNAPBASE="${V41_GATE_SNAP_DIR:-$HOME/w6-kit/oom-gate/logs/site}"
# 输出协议：**stdout 只出一行=目录路径**（调用方 `dir=$(snapshot ...)` 直接可用），
# 进度/告警一律走 stderr（否则会被命令替换吞掉，日志里什么都看不见）。
snapshot() {  # $1=触发原因   stdout=目录路径；失败也 return 0，绝不阻断止损
  [ "${V41_GATE_SNAP:-1}" = 1 ] || { echo "  （现场快照已关 V41_GATE_SNAP=0）" >&2; return 0; }
  local why="${1:-manual}" d dir
  d=$(date +%Y%m%dT%H%M%S)
  dir="$SNAPBASE/$(hostname).$d.$why"
  mkdir -p "$dir" 2>/dev/null || { echo "  ⚠ 快照目录不可建（$dir）⇒ 跳过，不影响止损" >&2; return 0; }
  _t() { timeout 3 "$@" 2>/dev/null; }        # 单采集器时间盒
  if ! command -v timeout >/dev/null 2>&1; then _t() { "$@" 2>/dev/null; }; fi
  {
    echo "why=$why ts=$(date -Is) host=$(hostname)"
    echo "gate参数 floor=${FLOOR:-?} warn=${WARN:-?} n=${NCNT:-?} act=${ACT:-?} iv=${IV:-?} emer=${EMER:-?}"
    echo "有效空闲=$(_eff_gib)GiB   判定=MemFree+Cached+SReclaimable-Shmem"
    uptime
  } > "$dir/00-trigger.txt"
  _t awk '/^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SReclaimable|Shmem|AnonPages|Mapped|Dirty|Writeback|Slab|SUnreclaim|KernelStack|PageTables|Committed_AS|SwapTotal|SwapFree):/' /proc/meminfo > "$dir/10-meminfo.txt"
  _t cat /proc/pressure/memory  > "$dir/11-psi-memory.txt"    # ★PSI=唯一给出"卡了多久"的官方口径
  _t cat /proc/pressure/io      > "$dir/11-psi-io.txt"
  _t cat /proc/pressure/cpu     > "$dir/11-psi-cpu.txt"
  _t cat /proc/vmstat           > "$dir/12-vmstat.txt"
  _t cat /proc/loadavg          > "$dir/13-loadavg.txt"
  _t ps -eo pid,ppid,rss,vsz,stat,etimes,comm --sort=-rss > "$dir/20-ps-rss.txt"
  { echo "== 本机(host) cgroup 树"; _t cat /sys/fs/cgroup/memory.stat; _t cat /sys/fs/cgroup/memory.current; } > "$dir/32-cg-host.txt"
  {
    echo "== docker ps"; _t docker ps --format '{{.Names}}\t{{.Status}}\t{{.Image}}'
    echo "== docker stats --no-stream"; _t docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}'
    echo "== 逐容器 cgroup（memory.peak=本容器历史峰值，事后归因关键）"
    # ★必须用 `docker inspect` 拿**全 64 位** id：`docker ps -q` 只给 12 位短 id，
    #   而 cgroup 目录名用全长 id（2026-09-22 实测：短 id 拼路径**全部落空**，且是静默落空——
    #   段落照打、路径一条没有，读者会误以为"这台机器没有 cgroup"）。
    #   双路兜底：① PID 反查 /proc/$pid/cgroup（与 cgroup 驱动无关）② 两种已知布局。
    #   两条都拿不到时**显式打 ⚠**，绝不静默。
    for line in $(_t docker inspect -f '{{.Id}}|{{.State.Pid}}|{{.Name}}' $(docker ps -q 2>/dev/null) 2>/dev/null); do
      cid="${line%%|*}"; rest="${line#*|}"; cpid="${rest%%|*}"; cname="${rest#*|}"
      echo "-- container $cname (id=$cid pid=$cpid)"
      cgp=""
      [ -n "$cpid" ] && [ -r "/proc/$cpid/cgroup" ] && cgp=$(awk -F: '{print $3; exit}' "/proc/$cpid/cgroup" 2>/dev/null)
      cands=""
      [ -n "$cgp" ] && cands="/sys/fs/cgroup$cgp"
      cands="$cands /sys/fs/cgroup/system.slice/docker-$cid.scope /sys/fs/cgroup/docker/$cid"
      hit=0
      for p in $cands; do
        if [ -d "$p" ]; then
          for f in memory.peak memory.current memory.events memory.stat; do
            [ -f "$p/$f" ] && { echo "  ## $p/$f"; _t cat "$p/$f"; }
          done
          hit=1; break
        fi
      done
      [ "$hit" = 1 ] || echo "  ⚠ 该容器 cgroup 路径未命中（试过：$cands）——不是没有，是没找到"
    done
  } > "$dir/30-docker.txt"
  { echo "== dmesg/journal 内核尾"; _t bash -c 'dmesg 2>/dev/null | tail -n 60'; _t journalctl -k -n 60 --no-pager; } > "$dir/40-kernel.txt"
  { echo "== NV_ERR / OOM-killer / NVRM 计数"; printf 'NV_ERR_NO_MEMORY='; _t bash -c 'dmesg 2>/dev/null | grep -c NV_ERR_NO_MEMORY'; printf 'Out_of_memory_Killed='; _t bash -c 'dmesg 2>/dev/null | grep -c "Out of memory: Killed"'; } > "$dir/41-counters.txt"
  { echo "== 运行中的 v41/推理相关进程"; _t bash -c "ps -eo pid,ppid,rss,comm,args --sort=-rss | grep -E '[v]llm-v41|[d]sv41|[s]glang|[p]ython3' | head -n 40"; } > "$dir/50-v41-procs.txt"
  local n f
  n=$(ls -1 "$dir" 2>/dev/null | wc -l)
  echo "  ✓ 现场快照 $n 个文件 → $dir" >&2
  printf '%s\n' "$dir"
}

_eff_gib() { awk -v k="$(eff_idle_kb)" 'BEGIN{printf "%.1f", k/1048576}'; }

case "$mode" in
pre)
  # --local: 只查本机（worker rank 用——机间无免密 ssh，嵌套查询会假 0.0；
  # 四机全检由 rank0/操作者在 01 侧承担）
  if [ $LOCAL = 1 ]; then HOSTS=(localhost); fi
  FAIL=0
  for h in "${HOSTS[@]}"; do
    KB=$(run_on "$h" "$(declare -f eff_idle_kb); eff_idle_kb")
    GIB=$(awk -v k="$KB" 'BEGIN{printf "%.1f", k/1048576}')
    OK=$(awk -v g="$GIB" -v t="$TH" 'BEGIN{print (g>=t)?1:0}')
    echo "$LOG_PREFIX pre $h 有效空闲=${GIB}GiB 门限=${TH}GiB => $([ $OK = 1 ] && echo PASS || echo FAIL)"
    [ "$OK" = 1 ] || FAIL=1
    if [ $STRICT = 1 ]; then
      N=$(run_on "$h" "docker ps -a --format '{{.Names}}' | grep -c '$V41_PAT' || true")
      [ "${N:-0}" = "0" ] && echo "$LOG_PREFIX pre $h 无 v41 容器残留 PASS" \
                        || { echo "$LOG_PREFIX pre $h 有 $N 个 v41 容器残留 FAIL（先清理/确认 Exited）"; FAIL=1; }
    fi
  done
  [ $FAIL = 0 ] && echo "$LOG_PREFIX pre 四机全过，放行" || echo "$LOG_PREFIX pre 拒启（A1 硬门）" >&2
  exit $FAIL
  ;;
baseline)
  # 行格式："<host> <nvrm_count> <hostoom_count>"（裸数字——post 用 read 三段解析）
  for h in "${HOSTS[@]}"; do
    NV=$(run_on "$h" "$(declare -f kern_log); kern_log | grep -c 'NV_ERR_NO_MEMORY' || true")
    OM=$(run_on "$h" "$(declare -f kern_log); kern_log | grep -c 'Out of memory: Killed' || true")
    echo "$h ${NV:-0} ${OM:-0}"
  done
  ;;
post)
  F="$FILE_ARG"
  [ -n "$F" ] && [ -f "$F" ] || { echo "$LOG_PREFIX 基线文件不存在：$F" >&2; exit 2; }
  FAIL=0
  while read -r h b_nv b_om; do
    NV=$(run_on "$h" "$(declare -f kern_log); kern_log | grep -c 'NV_ERR_NO_MEMORY' || true")
    OM=$(run_on "$h" "$(declare -f kern_log); kern_log | grep -c 'Out of memory: Killed' || true")
    echo "$LOG_PREFIX post $h ΔNVRM=$((NV-b_nv)) ΔhostOOM=$((OM-b_om))"
    [ "$NV" = "$b_nv" ] && [ "$OM" = "$b_om" ] || FAIL=1
  done < "$F"
  [ $FAIL = 0 ] && echo "$LOG_PREFIX post 窗口干净" || echo "$LOG_PREFIX post 窗口被污染 ⇒ 本轮结论作废（F2/F3）" >&2
  exit $FAIL
  ;;
monitor)
  # 2026-09-20 H5：①止损日志迁出 /tmp（重启即丢 ⇒ "止损已发生"的证据链曾不可追溯）；
  # ②止损/击穿进 syslog + guard 告警面 + 可选 webhook——docker stop 之后单元会拉起
  # 新 monitor，此前唯一痕迹在 /tmp，等于无声止损。
  LOGF="${V41_GATE_LOG:-$HOME/w6-kit/oom-gate/logs/oom-gate-monitor-$(hostname).log}"
  mkdir -p "$(dirname "$LOGF")" 2>/dev/null || true
  shout() {  # 对外出声：guard-alerts.log（与 guardctl alert() 同格式，同一采集面可抓）+ syslog + 可选 hook
    local sev="${1:-CRIT}"; shift
    printf '%s [%s] %s oom-gate %s\n' "$(date -Is)" "$sev" "$(hostname)" "$*" \
      >> "$ALERTS_F" 2>/dev/null || true
    if [ "${V41_GATE_NO_LOGGER:-0}" != 1 ] && command -v logger >/dev/null 2>&1; then
      logger -t oom-gate -p daemon.err "$*" 2>/dev/null || true
    fi
    if [ -n "${GUARD_ALERT_HOOK:-}" ]; then
      curl -sS --max-time 10 -H 'Content-Type: application/json' \
        -d "{\"severity\":\"$sev\",\"host\":\"$(hostname)\",\"src\":\"oom-gate\",\"text\":\"$*\",\"ts\":\"$(date -Is)\"}" \
        "$GUARD_ALERT_HOOK" >/dev/null 2>&1 || true
    fi
  }
  echo "$LOG_PREFIX monitor 启动 floor=${FLOOR}GiB warn=${WARN}GiB n=${NCNT} act=$ACT iv=${IV}s emer=${EMER}GiB log=$LOGF" | tee -a "$LOGF"
  HIT=0
  WHIT=0
  while :; do
    GIB=$(awk -v k="$(eff_idle_kb)" 'BEGIN{printf "%.1f", k/1048576}')
    TS=$(date -Is)
    # ★应急线（-e）：单采样、零等待。放在一切之前——这 1 GiB 里没有时间做确认。
    if [ "$EMER" != 0 ] && awk -v g="$GIB" -v e="$EMER" 'BEGIN{exit !(g<e)}'; then
      echo "$TS ★★应急线击穿 ${GIB}GiB<${EMER}GiB ⇒ 立即止损（不等 -n 确认）" | tee -a "$LOGF" >&2
      if [ $ACT = 1 ]; then
        # ② 止损前保护（2026-09-22 用户令②）。顺序不可换：
        #   snapshot 先于 sync —— sync 在极端压力下可能长尾（写回 GB 级脏页），现场不能赌它；
        #   两者都失败也要走到 docker stop（保护动作绝不改判决）。
        snapdir=$(snapshot "emer-${GIB}GiB" 2>>"$LOGF")
        if command -v timeout >/dev/null 2>&1; then timeout 3 sync 2>/dev/null || true; else sync 2>/dev/null || true; fi
        echo "$TS 止损前保护：现场=${snapdir:-无} + sync 已发（任一失败不阻断止损）" | tee -a "$LOGF"
        t_start=$(date +%s)
        for c in $(docker ps --format '{{.Names}}' | grep "$V41_PAT" || true); do
          docker stop -t 15 "$c" >> "$LOGF" 2>&1
        done
        t_stop=$(( $(date +%s) - t_start ))
        echo "$TS ★★应急止损完成（-t 15 短超时；实耗 ${t_stop}s）" | tee -a "$LOGF"
        shout CRIT "应急线击穿 ${GIB}GiB<${EMER}GiB ⇒ 已 docker stop（exit 4，耗 ${t_stop}s）；现场=${snapdir:-未落}；日志 $LOGF"
        exit 4
      else
        echo "$TS ★★应急线击穿（仅告警模式；-a 可启用自动止损）" | tee -a "$LOGF" >&2
      fi
    fi
    # 警戒线：只记日志（放在地板判定之前，两条线互不干扰；WARN=0 表示关闭）
    if [ "$WARN" != 0 ]; then
      if awk -v g="$GIB" -v w="$WARN" 'BEGIN{exit !(g<w)}'; then
        WHIT=$((WHIT+1))
        echo "$TS 低于警戒线 ${GIB}GiB<${WARN}GiB（第 $WHIT 次；仅告警，动作地板=${FLOOR}GiB 未触发）" | tee -a "$LOGF" >&2
      elif [ "$WHIT" -gt 0 ]; then
        echo "$TS 回到警戒线上方 ${GIB}GiB（复位）" | tee -a "$LOGF"
        WHIT=0
      fi
    fi
    if awk -v g="$GIB" -v f="$FLOOR" 'BEGIN{exit !(g<f)}'; then
      HIT=$((HIT+1))
      echo "$TS 破地板 ${GIB}GiB<${FLOOR}GiB ($HIT/$NCNT)" | tee -a "$LOGF" >&2
      if [ $HIT -ge $NCNT ]; then
        if [ $ACT = 1 ]; then
          # ADR-004 = 本行止损线（`-f`，在役 1.5 GiB；脚本内默认是 FLOOR=8，勿混）的决策记录，定义见 ~/w6-kit/adr/ADR-004-three-gib-floor-guard.md
          # （正文里的 "ADR-004" 就是它；此处只加注释，未动任何判据/阈值）。
          echo "$TS ★地板击穿 ⇒ 自动 docker stop 本机 v41 容器（ADR-004 止损）" | tee -a "$LOGF" >&2
          # ② 同一套保护（与应急线一致，避免两条路证据规格不同）
          snapdir=$(snapshot "floor-${GIB}GiB" 2>>"$LOGF")
          if command -v timeout >/dev/null 2>&1; then timeout 3 sync 2>/dev/null || true; else sync 2>/dev/null || true; fi
          echo "$TS 止损前保护：现场=${snapdir:-无} + sync 已发（任一失败不阻断止损）" | tee -a "$LOGF"
          t_start=$(date +%s)
          for c in $(docker ps --format '{{.Names}}' | grep "$V41_PAT" || true); do
            docker stop -t 60 "$c" >> "$LOGF" 2>&1
          done
          t_stop=$(( $(date +%s) - t_start ))
          echo "$TS 止损完成（实耗 ${t_stop}s）" | tee -a "$LOGF"
          shout CRIT "地板击穿 ${GIB}GiB<${FLOOR}GiB ×${NCNT} ⇒ 已 docker stop（exit 3，耗 ${t_stop}s）；现场=${snapdir:-未落}；日志 $LOGF"
          exit 3
        else
          echo "$TS ★地板击穿（仅告警模式；-a 可启用自动止损）" | tee -a "$LOGF" >&2
          shout WARN "地板击穿 ${GIB}GiB<${FLOOR}GiB ×${NCNT}（-a 未启=不动作，仅出声）"
        fi
      fi
    else
      [ $HIT -gt 0 ] && echo "$TS 回到地板上方 ${GIB}GiB（复位）" | tee -a "$LOGF"
      HIT=0
    fi
    if [ "$ONCE" = 1 ]; then
      echo "$TS --once：单采样完成（有效空闲 ${GIB}GiB，未触发任何动作）⇒ 退出 0" | tee -a "$LOGF"
      exit 0
    fi
    sleep "$IV"
  done
  ;;
snapshot)
  # 手动落现场（不起守护）：运维随时可抓一份"现在长什么样"，与止损路径同一套采集规格
  snapdir=$(snapshot "${FILE_ARG:-manual}")
  echo "$LOG_PREFIX 现场=$snapdir"
  ;;
*)
  grep -E '^# (用法|事故)' "$0" | sed 's/^# //'; exit 2 ;;
esac
