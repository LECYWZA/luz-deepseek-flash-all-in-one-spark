#!/bin/bash
# oom_gate.hardened.workcopy.sh — oom-gate 五件加固工作副本（D1-D5；H-TTL 在 watchdog 侧）
# ⚠ WORKCOPY（零部署）：基线=~/w6-kit/oom-gate/oom_gate.sh（2026-10-04 00:01 r3prod-PAT 版，
#   在役件只读未动）；四机分发=INC-20261004-DRIFT 收口后由主会话另派（guardctl+md5 单）。
# 裁定：docs/governance/OOMGATE-HARDENING-PROPOSAL-20261004.md §裁定（2026-10-04 六件全准）。
# 根因：docs/verdicts/OOM-INCIDENT-DEEPDIVE-20261004.md §1.4/§1.5（D1-D5 证据原文）。
#
# 五件改动（**判据/阈值/红线零改**：水位四线/G1 门/中止线/admission 面全部原样；
# 有效空闲公式=MemFree+Cached+SReclaimable−Shmem 原样；exit 0/1/2/3/4 语义原样）：
#  D1 命运共担豁免（采样免 fork 化半件；单元三键=drop-in/ 下 conf，不改原 unit）：
#    monitor 采样点改单进程常驻读：/proc/meminfo 用 read 内建读、算术/时间戳/日志全内建
#    （EPOCHREALTIME、printf %()T、printf >>），节拍定时=FIFO+read -t（免 sleep fork）。
#    饥荒期 fork/exec 停滞不再拖采样（本案 01：2s 拍距被拖成 11min55s）。
#  D2 止损优先：动作块重排——极简快照（meminfo/ps/docker ps 三件，实测 5 execve）→
#    sync（时间盒，原样）→ docker stop → 重取证（重收集器全量）移到 stop 完成后
#    （systemd-run 瞬态单元异步；不可用退同步整段时间盒）。
#  D3 PID 直杀后备：启动预取+周期刷新本机容器 PID 清单（name→cid pid；时间盒，失败保旧）；
#    止损序（预登记）=①docker stop（主路径，调用形原样）→②超时/失败→③对缓存 PID 发
#    SIGKILL（kill=内建，内核信号不经 dockerd）；直杀前必须过 PID 身份核验
#    （/proc/<pid>/cgroup 含容器全 id；不过=跳过+CRIT——宁少杀不错杀，教义 #12）。
#  D4 双时间戳：决策/完成各打真实时间戳（µs=EPOCHREALTIME）；实耗分段
#    （min 快照/止损管道）上报；steady 循环每拍取新 TS，禁复用 stale $TS。
#  D5 零匹配兜底：破线 ∧（docker 清单空 ∧ PID 缓存空）⇒ pkill -9 -f sglang（rc 如实上报）。
#
# 新增环境旋钮（默认值=裁定形；全部为管道/测试面，非判据）：
#   V41_GATE_MEMINFO_SRC    采样源（默认 /proc/meminfo；电池 fixture 注入口）
#   V41_GATE_PID_CACHE      PID 清单缓存落盘（默认 ~/w6-kit/oom-gate/logs/pidcache-<host>.txt）
#   V41_GATE_PIDCACHE_IV    PID 清单刷新间隔秒（默认 60；时间盒 10s，失败保留旧清单）
#   V41_GATE_PID_CMDLINE_MATCH =1 身份核验加受「/proc/<pid>/cmdline 含容器名」
#                           （默认 0=关；仅电池/离线演练用——生产=cgroup-only 严格形）
#   V41_GATE_STOP_T         覆盖 docker stop -t（默认空=emer 15/floor 60 原值；演练/电池用）
#   V41_GATE_PKILL_FB       零匹配 pkill 兜底开关（默认 1=开=裁定形）
#   V41_GATE_HEAVY_ASYNC    重取证异步（默认 1=systemd-run 瞬态单元；0=同步时间盒）
#   V41_GATE_HEAVY_BOX_S    同步后备时间盒秒（默认 120）
#   V41_GATE_TIMER_FD       =0 禁用 FIFO 定时器退 sleep（默认自动）
# 既有旋钮（V41_GATE_SNAP/SNAP_DIR/ALERTS/NO_LOGGER/LOG）语义不变。
#
# 用法：与本件基线完全一致（pre/baseline/post/monitor/snapshot/--once）+ 内部模式
#   evidence <why>（D2 重取证体，由 systemd-run/同步后备调起；只收集不判据不动作）。
#
# 事故教训（勿删——与基线同源）：
#  - GB10 UMA：设备分配不进 cgroup ⇒ docker --memory 拦不住；宿主 global OOM 不分生产/测试。
#  - MemAvailable 在高压下不稳定且口径不可靠（F-26/O-3）⇒ 一律用
#    有效空闲 = MemFree + Cached + SReclaimable − Shmem。
#  - "healthy" 是结论不是证据：任何窗口必须附 NVRM/host-oom 增量与有效空闲最低点（F11）。
#  - 2026-10-04 INC 追加：决策已对、执行迟到也是事故——止损管道的每一 fork 都是饥荒里的
#    债务（D1）；取证永远排在 stop 之后（D2）。
set -uo pipefail

HOSTS=(localhost dgxspark02 dgxspark03 dgxspark04)
V41_PAT="${V41_PAT:-vllm-v41-\\|dsv41-\\|r3boot-\|r3prod-}"  # BRE：\| = 或；v2(2026-09-30)：r3boot- 入默认（LuZ-0.3.0 新栈一等公民，原靠 drop-in 补丁）；2026-10-04：r3prod- 入默认
LOG_PREFIX="[oom-gate]"
ALERTS_F="${V41_GATE_ALERTS:-$HOME/w6-kit/guard/guard-alerts.log}"

run_on() {  # $1=host $2=cmd（stdin 一律隔离：防 ssh/子壳吃掉外层 while read 的输入）
  local h=$1 c=$2
  if [ "$h" = "localhost" ]; then bash -c "$c" </dev/null; else ssh -n -o ConnectTimeout=8 "$h" "$c" </dev/null 2>/dev/null; fi
}

# （D1 注：monitor 面改用免 fork 内建版 _gt_read_meminfo——判据同式；本函数供
#  pre/baseline/post/snapshot 面原样沿用，函数体与在役逐字节同文。）
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

# ── 站点快照（2026-09-22 加；用户令②"应急分支加保护"）────────────────────────────
# 动机：9/21 与 9/22 两次事故里，docker stop 一执行**现场就被销毁**——进程树、PSI、
# cgroup 峰值、页缓存/脏页态势全没了，事后只剩 10s 粒度主机线与容器日志，归因只能拼图。
# 纪律（防"保护动作本身变成事故"）：
#   ① 永不改变止损决定——快照/同步全失败也照旧 docker stop，退出码不变；
#   ② 每个采集器独立 `timeout`，fork/exec 在 <1 GiB 下可能失败，失败只是少几行；
#   ③ 绝不 fsync 整机：sync 也带时间盒（有界放弃）。
# ★D2（2026-10-04）重排：全量收集器=重取证，移到 stop 完成后（snapshot_heavy）；
#   止损前只留极简三件（snapshot_min，实测 5 execve：mkdir+timeout×2+ps+docker ps）。
SNAPBASE="${V41_GATE_SNAP_DIR:-$HOME/w6-kit/oom-gate/logs/site}"
# 输出协议：**stdout 只出一行=目录路径**（调用方 `dir=$(snapshot ...)` 直接可用），
# 进度/告警一律走 stderr（否则会被命令替换吞掉，日志里什么都看不见）。

snapshot_heavy() {  # $1=触发原因   stdout=目录路径；失败也 return 0，绝不阻断止损
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
    # ★D3(2026-10-04)：docker ps -q 加时间盒（本案 01 的 30-docker 块无盒卡 1h56m 的教训）。
    for line in $(_t docker inspect -f '{{.Id}}|{{.State.Pid}}|{{.Name}}' $(timeout 8 docker ps -q 2>/dev/null) 2>/dev/null); do
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
  # ★D2(2026-10-04)：逐容器日志尾随取证从「stop 前」移到「stop 后」——容器未被本脚本 rm，
  #   docker logs 对已停容器仍可读；若被 watchdog 抢先 rm 则如实记失败（本案 head 终言丢失的
  #   竞态教训：拿不到就大声写拿不到，不静默）。
  if [ -n "${V41_GATE_STOPPED_NAMES:-}" ]; then
    {
      echo "== poststop docker logs 尾 120（D2：移至 stop 完成后取证）"
      for pc in $V41_GATE_STOPPED_NAMES; do
        echo "-- container $pc"
        timeout 5 docker logs --tail 120 "$pc" 2>&1 || echo "  (docker logs $pc 失败——容器可能已被移除/清理)"
      done
    } > "$dir/31-poststop-logs.txt"
  fi
  { echo "== dmesg/journal 内核尾"; _t bash -c 'dmesg 2>/dev/null | tail -n 60'; _t journalctl -k -n 60 --no-pager; } > "$dir/40-kernel.txt"
  { echo "== NV_ERR / OOM-killer / NVRM 计数"; printf 'NV_ERR_NO_MEMORY='; _t bash -c 'dmesg 2>/dev/null | grep -c NV_ERR_NO_MEMORY'; printf 'Out_of_memory_Killed='; _t bash -c 'dmesg 2>/dev/null | grep -c "Out of memory: Killed"'; } > "$dir/41-counters.txt"
  { echo "== 运行中的 v41/推理相关进程"; _t bash -c "ps -eo pid,ppid,rss,comm,args --sort=-rss | grep -E '[v]llm-v41|[d]sv41|[s]glang|[p]ython3' | head -n 40"; } > "$dir/50-v41-procs.txt"
  local n f
  n=$(ls -1 "$dir" 2>/dev/null | wc -l)
  echo "  ✓ 重取证 $n 个文件 → $dir" >&2
  printf '%s\n' "$dir"
}
snapshot() { snapshot_heavy "${1:-manual}"; }   # 手动/兼容入口：全量规格不变

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

  # ══ D1：免 fork 采样原语（单进程常驻读；判据口径与 awk 基线逐值等同）═════════════
  # 依据 DEEPDIVE §1.3：01 的采样拍距 2s→11min55s，元凶=每拍 5-8 次 fork/exec 在饥荒里
  # 爬行。本节全部用 bash 内建：read（/proc/meminfo）、算术、EPOCHREALTIME、printf %()T、
  # printf >> 日志、FIFO read -t 定时——steady 态零 fork（电池以 strace execve 计数证明）。
  [ -n "${EPOCHREALTIME:-}" ] || { echo "$LOG_PREFIX 本件需 bash≥5（EPOCHREALTIME）——环境不符，拒绝降级运行（防静默失去 D1 保证）" >&2; exit 2; }
  MEMINFO_SRC="${V41_GATE_MEMINFO_SRC:-/proc/meminfo}"
  GT_HOST=$(hostname)   # 启动期一次（steady 不再 fork hostname）

  GT_EFF_KB=0; GT_TENTHS=0; GT_GIB="0.0"; GT_ISO=""
  _gt_read_meminfo() {  # 读一次采样源 → GT_EFF_KB（KiB）；纯内建零 fork
    local key val rest mf=0 ca=0 sr=0 sh=0
    while read -r key val rest; do
      case $key in
        MemFree:)      mf=$val ;;
        Cached:)       ca=$val ;;
        SReclaimable:) sr=$val ;;
        Shmem:)        sh=$val ;;
      esac
    done < "$MEMINFO_SRC"
    GT_EFF_KB=$(( mf + ca + sr - sh ))
  }
  _gt_gib_tenths() {    # KiB→GiB 十分位。与基线 awk printf %.1f 同域同值：基线先四舍五入到
    GT_TENTHS=$(( (GT_EFF_KB * 10 + 524288) / 1048576 ))   # 1 位小数再比较，本处亦然；仅当
  }                     # k*10/1048576 恰落 .5 平点时半进 vs IEEE 平偶可能差 1 个十分位——
  _gt_fmt_gib() {       # 判据线均为 .0/.5 整值，不受影响（报告已登记此边界）。
    GT_GIB="$(( GT_TENTHS / 10 )).$(( GT_TENTHS % 10 ))"
  }
  _gt_iso() {  # 内建时间戳（等价 date -Is 语义；格式差=时区无冒号，同为 ISO8601）
    printf -v GT_ISO '%(%Y-%m-%dT%H:%M:%S%z)T' -1
  }
  _logm() {    # 内建日志（等价 `echo|x tee -a $LOGF >&2`；steady 态零 fork）
    printf '%s\n' "$*" >> "$LOGF" 2>/dev/null
    printf '%s\n' "$*" >&2
  }
  _us2int() {  # "1791126116.482292"→µs 整数（D4 遥测精度）
    local s=${1%%.*} f=${1#*.}
    [ "$s" = "$1" ] && f=0
    while [ ${#f} -lt 6 ]; do f="${f}0"; done
    f=${f:0:6}
    US_INT=$(( s * 1000000 + 10#$f ))
  }
  GT_TIMER_FD=""   # FIFO 定时器：read -t 纯内建等待（免 sleep fork）
  _gt_timer_init() {
    [ "${V41_GATE_TIMER_FD:-1}" = 0 ] && return 0
    local f="${TMPDIR:-/tmp}/oomgate-timer.$$.$RANDOM.fifo"
    if mkfifo -- "$f" 2>/dev/null; then
      if exec {GT_TIMER_FD}<> "$f"; then return 0; fi
    fi
    GT_TIMER_FD=""   # 建不成→退 sleep（每拍 1 fork；D1 降级，启动行如实标注）
  }
  _gt_sleep() {  # $1=秒（可小数）
    if [ -n "$GT_TIMER_FD" ]; then
      IFS= read -t "$1" -u "$GT_TIMER_FD" _ || true   # 超时 rc>128=正常节拍
    else
      sleep "$1"
    fi
  }

  # 阈值→十分位整数（与基线「awk 按 1 位小数浮点比较」同判定域；非法值拒绝启动=原 set -u 精神）
  _dec_to_tenths() {  # $1=值 → $2=变量名；rc1=非法
    local s=${!1:-} int frac
    case $s in
      ''|*[!0-9.]*) return 1 ;;
      *.*) int=${s%%.*}; frac=${s#*.} ;;
      *)   int=$s;  frac=0 ;;
    esac
    case $int  in ''|*[!0-9]*) return 1 ;; esac
    case $frac in ''|*[!0-9]*) return 1 ;; esac
    [ ${#frac} -gt 1 ] && frac=${frac:0:1}   # >1 位小数截断（在役形只给 1 位；防御）
    [ ${#frac} -eq 0 ] && frac=0
    printf -v "$2" '%s' $(( int * 10 + 10#$frac ))
    return 0
  }
  _dec_to_tenths FLOOR FLOOR_T || { echo "$LOG_PREFIX 非法 -f '$FLOOR'" >&2; exit 2; }
  _dec_to_tenths WARN  WARN_T  || { echo "$LOG_PREFIX 非法 -w '$WARN'"  >&2; exit 2; }
  _dec_to_tenths EMER  EMER_T  || { echo "$LOG_PREFIX 非法 -e '$EMER'"  >&2; exit 2; }

  # ══ D3：本机容器 PID 清单（预取+周期刷新；时间盒，失败保旧——dockerd 假死不废兜底）══
  declare -A GT_PIDCACHE=()
  GT_PIDCACHE_IV="${V41_GATE_PIDCACHE_IV:-60}"
  case $GT_PIDCACHE_IV in ''|*[!0-9]*) GT_PIDCACHE_IV=60 ;; esac
  GT_PID_CACHE_F="${V41_GATE_PID_CACHE:-$HOME/w6-kit/oom-gate/logs/pidcache-${GT_HOST}.txt}"
  GT_PIDCACHE_ERE="${V41_PAT//\\|/|}"   # BRE 或语法→ERE（内建 =~ 匹配，免 grep fork）
  _gt_pidcache_store() {  # 落盘（printf 内建，零 fork）；行式 name|cid|pid（与 loadf 同式）
    local n out="" v
    for n in "${!GT_PIDCACHE[@]}"; do
      v="${GT_PIDCACHE[$n]}"
      out+="$n|${v% *}|${v#* }"$'\n'
    done
    printf '%s' "$out" > "$GT_PID_CACHE_F" 2>/dev/null || true
  }
  _gt_pidcache_loadf() {  # 从落盘缓存恢复（内建 read）
    [ -f "$GT_PID_CACHE_F" ] || return 0
    local n c p
    while IFS='|' read -r n c p; do
      [ -n "$n" ] || continue
      case $p in ''|*[!0-9]*) continue ;; esac
      GT_PIDCACHE[$n]="$c $p"
    done < "$GT_PID_CACHE_F"
  }
  _gt_pidcache_refresh() {  # docker 面可用时刷新；ps -q rc!=0=面不可用→保旧清单+WARN（不 nuke）
    local q="" drc=0 out cname cid pidn run ts
    q=$(timeout 8 docker ps -q 2>/dev/null) || drc=$?
    if [ "$drc" != 0 ]; then
      printf -v ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1
      _logm "$ts [pidcache] WARN docker 面刷新失败（ps -q rc=$drc）——保留旧清单 ${#GT_PIDCACHE[@]} 项"
      return 0
    fi
    GT_PIDCACHE=()   # rc=0（含"无容器"=合法空清单）
    if [ -n "$q" ]; then
      out=$(timeout 10 docker inspect -f '{{.Name}}|{{.Id}}|{{.State.Pid}}|{{.State.Running}}' $q 2>/dev/null) || out=""
      while IFS='|' read -r cname cid pidn run; do
        [ -n "$cname" ] || continue
        cname=${cname#/}
        [ "$run" = "true" ] || continue          # 只缓存 running（Exited 不是止损对象）
        case $pidn in ''|*[!0-9]*|0) continue ;; esac
        [[ $cname =~ $GT_PIDCACHE_ERE ]] || continue
        GT_PIDCACHE[$cname]="$cid $pidn"
      done <<< "$out"
    fi
    _gt_pidcache_store
    printf -v ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1
    _logm "$ts [pidcache] 刷新：${#GT_PIDCACHE[@]} 个受管容器 → $GT_PID_CACHE_F"
  }
  _gt_pid_identity_ok() {  # $1=pid $2=cid $3=cname → rc0=身份确认；纯内建
    local pid=$1 cid=$2 cg
    [ -r "/proc/$pid/cgroup" ] || return 1
    cg=$(<"/proc/$pid/cgroup")            # $(<file)=内建，零 fork
    case $cg in *"$cid"*) return 0 ;; esac
    if [ "${V41_GATE_PID_CMDLINE_MATCH:-0}" = 1 ]; then
      # 测试/离线演练 hatch（默认关）：cmdline 含容器名亦认。生产=cgroup-only 严格形。
      local cl="" seg
      if [ -r "/proc/$pid/cmdline" ]; then
        while read -r -d '' seg; do cl+="$seg"; done < "/proc/$pid/cmdline"
        case $cl in *"$3"*) return 0 ;; esac
      fi
    fi
    return 1
  }

  # ══ D2：极简快照（止损前唯一取证；实测 5 execve：mkdir+timeout×2+ps+docker ps）════
  GT_STOPPED_NAMES=""
  snapshot_min() {  # $1=why  stdout=目录路径；失败 return 0，绝不阻断止损
    [ "${V41_GATE_SNAP:-1}" = 1 ] || { echo "  （现场快照已关 V41_GATE_SNAP=0）" >&2; return 0; }
    local why="${1:-min}" dir
    printf -v dir '%s/%s.min.%(%Y%m%dT%H%M%S%z)T.%s' "$SNAPBASE" "$GT_HOST" -1 "$why"
    mkdir -p "$dir" 2>/dev/null || { echo "  ⚠ 极简快照目录不可建（$dir）⇒ 跳过，不影响止损" >&2; printf '未落\n'; return 0; }
    {
      local la="" its=""
      IFS= read -r la _ < /proc/loadavg 2>/dev/null || true   # read 内建（免 cat fork）
      printf -v its '%(%Y-%m-%dT%H:%M:%S%z)T' -1
      printf 'why=%s ts=%s host=%s\n' "$why" "$its" "$GT_HOST"
      printf 'gate参数 floor=%s warn=%s n=%s act=%s iv=%s emer=%s\n' "${FLOOR}" "${WARN}" "${NCNT}" "${ACT}" "${IV}" "${EMER}"
      printf '有效空闲=%sGiB   判定=MemFree+Cached+SReclaimable-Shmem（D2 极简面）\n' "$GT_GIB"
      printf 'loadavg=%s\n' "${la:-不可读}"
    } > "$dir/00-trigger.txt"
    { while read -r l; do
        case $l in
          MemTotal:|MemFree:|MemAvailable:|Buffers:|Cached:|SReclaimable:|Shmem:|AnonPages:|Mapped:|Dirty:|Writeback:|Slab:|SUnreclaim:|KernelStack:|PageTables:|Committed_AS:|SwapTotal:|SwapFree:)
          printf '%s\n' "$l" ;;
        esac
      done < "$MEMINFO_SRC"; } > "$dir/10-meminfo.txt" 2>/dev/null
    timeout 3 ps -eo pid,ppid,rss,vsz,stat,etimes,comm --sort=-rss > "$dir/20-ps-rss.txt" 2>/dev/null || true
    { printf '== docker ps（D2 极简面）\n'
      timeout 5 docker ps --format '{{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null || printf '(docker ps 不可用)\n'
    } > "$dir/30-docker-lite.txt"
    printf '%s\n' "$dir"
  }

  # ══ D3+D5：止损序（预登记）①docker stop 主路径→②超时/失败→③PID SIGKILL；零匹配兜底 ══
  stop_matched() {  # $1=why $2=docker stop -t 秒
    local why="$1" tst="$2" c matched=0 escalated=0 stop_rc names src=docker
    names=$(timeout 15 docker ps --format '{{.Names}}' 2>/dev/null | grep "$V41_PAT" || true)
    if [ -z "$names" ] && [ "${#GT_PIDCACHE[@]}" -gt 0 ]; then
      names=""
      for c in "${!GT_PIDCACHE[@]}"; do names+="$c "; done
      src=pidcache
      _logm "[$why] docker 清单空——改用 PID 缓存清单（${#GT_PIDCACHE[@]} 项；D3 兜底枚举）"
    fi
    for c in $names; do
      matched=$((matched+1))
      GT_STOPPED_NAMES+="$c "
      _logm "[$why] 止损目标：$c（清单源=$src；docker stop -t $tst 主路径→超时/失败才走 PID 直杀）"
      stop_rc=0
      timeout $(( tst + 15 )) docker stop -t "$tst" "$c" >> "$LOGF" 2>&1 || stop_rc=$?
      if [ "$stop_rc" != 0 ]; then
        local entry cid pidn
        entry="${GT_PIDCACHE[$c]:-}"
        if [ -n "$entry" ]; then
          cid=${entry% *}; pidn=${entry#* }
          if _gt_pid_identity_ok "$pidn" "$cid" "$c"; then
            kill -9 "$pidn" 2>/dev/null || true     # kill=bash 内建：内核信号，不经 dockerd
            escalated=$((escalated+1))
            _logm "[$why] ★D3-ESCALATION：docker stop 失败（rc=$stop_rc）⇒ SIGKILL pid=$pidn（容器 $c cid=${cid:0:12}）"
          else
            _logm "[$why] ★CRIT PID 身份核验不过（pid=$pidn 与 cid=${cid:0:12} 不符）——放弃直杀防误杀"
            shout CRIT "oom-gate [$why] D3 直杀身份核验失败 pid=$pidn cid=${cid:0:12}——已跳过（防误杀）；docker stop rc=$stop_rc"
          fi
        else
          _logm "[$why] ★CRIT docker stop 失败（rc=$stop_rc）且 PID 缓存无 $c——该容器止损悬空"
          shout CRIT "oom-gate [$why] docker stop 失败(rc=$stop_rc)且无 PID 缓存可兜底（容器 $c）"
        fi
      fi
    done
    if [ "$matched" -eq 0 ]; then
      _logm "[$why] ★零容器匹配 PAT='$V41_PAT'（docker 面与 PID 缓存面皆空）——CRIT"
      shout CRIT "oom-gate [$why] 破线但零容器匹配 PAT（r3boot 栈未被管辖？）；日志 $LOGF"
      if [ "${V41_GATE_PKILL_FB:-1}" = 1 ]; then    # D5 兜底（默认开=裁定形）
        local pk_rc=0
        pkill -9 -f sglang || pk_rc=$?
        _logm "[$why] D5-兜底：pkill -9 -f sglang 执行（rc=$pk_rc；rc=1=本机无 sglang 进程，如实记录）"
        shout CRIT "oom-gate [$why] 零匹配 ⇒ D5 兜底 pkill -9 -f sglang（rc=$pk_rc）"
      fi
    else
      _logm "[$why] 共止损 ${matched} 个容器（D3 直杀后备触发 ${escalated} 次）"
    fi
  }

  # ══ D2+D4：止损管道（动作块重排=极简快照→sync→stop→重取证；双时间戳+分段实耗）══
  _launch_heavy_evidence() {  # $1=why ——重取证在 stop 完成后（D2）
    local why="$1" hus
    export V41_GATE_STOPPED_NAMES="${GT_STOPPED_NAMES% }"
    _us2int "$EPOCHREALTIME"; hus=$US_INT
    if [ "${V41_GATE_HEAVY_ASYNC:-1}" = 1 ] && command -v systemd-run >/dev/null 2>&1 \
       && systemd-run --collect --quiet --unit="oomgate-evid-${why}-$$" \
            /bin/bash "$0" evidence "$why" >> "$LOGF" 2>&1; then
      _logm "[$why] D4-MARK heavy_launch_us=$hus heavy=async(systemd-run)"
    else
      local hb="${V41_GATE_HEAVY_BOX_S:-120}"
      _logm "[$why] D4-MARK heavy_launch_us=$hus heavy=sync（box=${hb}s；systemd-run 不可用/失败）"
      timeout "$hb" /bin/bash "$0" evidence "$why" >> "$LOGF" 2>&1 || \
        _logm "[$why] ⚠ 同步重取证超时/失败（box=${hb}s）——证据缺失不回滚已完成的止损"
    fi
  }
  _breach_action() {  # $1=why标签 $2=stop -t 秒 $3=exit 码
    local why="$1" tst="${V41_GATE_STOP_T:-$2}" xcode="$3"
    local dec_us dec_iso
    dec_us=$EPOCHREALTIME
    printf -v dec_iso '%(%Y-%m-%dT%H:%M:%S%z)T' -1
    _us2int "$dec_us"; local d0=$US_INT
    _logm "$dec_iso ★[$why] 止损管道启动（D4-MARK dec_us=$d0；决策时刻=$dec_us）"
    local t0=$EPOCHREALTIME snapdir=""
    snapdir=$(snapshot_min "$why" 2>>"$LOGF")
    local t1=$EPOCHREALTIME
    _us2int "$t1"; local d1=$US_INT
    _logm "[$why] D4-MARK minsnap_done_us=$d1 现场极简=$snapdir"
    if command -v timeout >/dev/null 2>&1; then timeout 3 sync 2>/dev/null || true; else sync 2>/dev/null || true; fi
    stop_matched "$why" "$tst"
    local t3=$EPOCHREALTIME
    _us2int "$t3"; local d3=$US_INT
    _logm "[$why] D4-MARK stop_done_us=$d3"
    _launch_heavy_evidence "$why"
    local done_us=$EPOCHREALTIME done_iso
    printf -v done_iso '%(%Y-%m-%dT%H:%M:%S%z)T' -1
    _us2int "$done_us"; local d9=$US_INT
    local seg_min=$(( d1 - d0 )) seg_stop=$(( d3 - d1 )) total=$(( d9 - d0 ))
    _logm "$done_iso ★[$why] 止损管道完成（D4-MARK done_us=$d9；完成时刻=$done_us）"
    _logm "[$why] D4-SEGS min_snap_ms=$(( seg_min / 1000 )) stop_pipe_ms=$(( seg_stop / 1000 )) total_ms=$(( total / 1000 ))"
    shout CRIT "[$why] 决策=$dec_iso 完成=$done_iso 决策→完成=$(( total / 1000 ))ms 分段[min-snap=$(( seg_min / 1000 ))ms 止损管道=$(( seg_stop / 1000 ))ms]；现场极简=$snapdir；重取证=stop 后；日志 $LOGF"
    exit "$xcode"
  }

  _gt_timer_init
  TIMER_FORM=sleep
  [ -n "$GT_TIMER_FD" ] && TIMER_FORM=fifo
  echo "$LOG_PREFIX monitor 启动 floor=${FLOOR}GiB warn=${WARN}GiB n=${NCNT} act=$ACT iv=${IV}s emer=${EMER}GiB log=$LOGF hardening=D1-D5(2026-10-04) timer=$TIMER_FORM" >> "$LOGF"
  _gt_pidcache_refresh          # D3 启动预取
  [ "${#GT_PIDCACHE[@]}" -gt 0 ] || _gt_pidcache_loadf   # 预取失败→吃落盘旧账
  HIT=0
  WHIT=0
  LAST_REFRESH=$EPOCHSECONDS
  while :; do
    _gt_read_meminfo
    _gt_gib_tenths
    _gt_fmt_gib
    _gt_iso; TS=$GT_ISO          # 每拍新 TS（D4：禁 stale 复用）
    # ★应急线（-e）：单采样、零等待。放在一切之前——这 1 GiB 里没有时间做确认。
    if [ "$EMER" != 0 ] && [ "$GT_TENTHS" -lt "$EMER_T" ]; then
      _logm "$TS ★★应急线击穿 ${GT_GIB}GiB<${EMER}GiB ⇒ 立即止损（不等 -n 确认）"
      if [ $ACT = 1 ]; then
        _breach_action "emer" 15 4
      else
        _logm "$TS ★★应急线击穿（仅告警模式；-a 可启用自动止损）"
      fi
    fi
    # 警戒线：只记日志（放在地板判定之前，两条线互不干扰；WARN=0 表示关闭）
    if [ "$WARN" != 0 ]; then
      if [ "$GT_TENTHS" -lt "$WARN_T" ]; then
        WHIT=$((WHIT+1))
        _logm "$TS 低于警戒线 ${GT_GIB}GiB<${WARN}GiB（第 $WHIT 次；仅告警，动作地板=${FLOOR}GiB 未触发）"
      elif [ "$WHIT" -gt 0 ]; then
        _logm "$TS 回到警戒线上方 ${GT_GIB}GiB（复位）"
        WHIT=0
      fi
    fi
    if [ "$GT_TENTHS" -lt "$FLOOR_T" ]; then
      HIT=$((HIT+1))
      _logm "$TS 破地板 ${GT_GIB}GiB<${FLOOR}GiB ($HIT/$NCNT)"
      if [ $HIT -ge $NCNT ]; then
        if [ $ACT = 1 ]; then
          # ADR-004 = 本行止损线（`-f`，在役 1.5 GiB；脚本内默认是 FLOOR=8，勿混）的决策记录，
          # 定义见 ~/w6-kit/adr/ADR-004-three-gib-floor-guard.md
          _logm "$TS ★地板击穿 ⇒ 自动 docker stop 本机 v41 容器（ADR-004 止损）"
          _breach_action "floor" 60 3
        else
          _logm "$TS ★地板击穿（仅告警模式；-a 可启用自动止损）"
          shout WARN "地板击穿 ${GT_GIB}GiB<${FLOOR}GiB ×${NCNT}（-a 未启=不动作，仅出声）"
        fi
      fi
    else
      [ $HIT -gt 0 ] && _logm "$TS 回到地板上方 ${GT_GIB}GiB（复位）"
      HIT=0
    fi
    # D3 周期刷新（时间盒；失败保旧）
    if [ $(( EPOCHSECONDS - LAST_REFRESH )) -ge "$GT_PIDCACHE_IV" ]; then
      _gt_pidcache_refresh
      LAST_REFRESH=$EPOCHSECONDS
    fi
    if [ "$ONCE" = 1 ]; then
      _logm "$TS --once：单采样完成（有效空闲 ${GT_GIB}GiB，未触发任何动作）⇒ 退出 0"
      exit 0
    fi
    _gt_sleep "$IV"
  done
  ;;
snapshot)
  # 手动落现场（不起守护）：运维随时可抓一份"现在长什么样"，与止损路径同一套采集规格
  snapdir=$(snapshot_heavy "${FILE_ARG:-manual}")
  echo "$LOG_PREFIX 现场=$snapdir"
  ;;
evidence)
  # D2 重取证体：stop 完成后由 systemd-run 瞬态单元/同步后备调起；只收集，不判据不动作
  LOGF="${V41_GATE_LOG:-$HOME/w6-kit/oom-gate/logs/oom-gate-monitor-$(hostname).log}"
  mkdir -p "$(dirname "$LOGF")" 2>/dev/null || true
  snapdir=$(snapshot_heavy "${FILE_ARG:-evidence}")
  echo "$LOG_PREFIX evidence 现场=$snapdir"
  ;;
*)
  grep -E '^# (用法|事故)' "$0" | sed 's/^# //'; exit 2 ;;
esac
