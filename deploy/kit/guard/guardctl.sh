#!/bin/bash
# ==============================================================================
# guardctl.sh — DGX Spark TP4 集群「守卫 / 自恢复 / 健康检查」统一管理器
#
# 为什么存在
# ----------
# 这套栈有 4~6 个互不相同的容错部件（systemd 单元、60s 主动重建探针、自愈
# 监视器、取证转储、业务网关）。它们平时各自默默工作，**失效时不会报警**：
# 2026-09-11 实测到 head 的 P1 主动重建守卫被上一次性维护窗口的残留停泊进程
# 冻结（单元永卡 activating、定时器 NextElapse=infinity），而生产完全健康，
# 于是没有任何信号暴露它——它已经"没人守"了 40 分钟。
# 本工具把"逐个检查守卫"变成一条命令，并把开关、失效识别、告警、自解释统一。
#
# 用法（全部无需 root，本账号即可）
#   bash guardctl.sh status            # 人读的守卫总览表
#   bash guardctl.sh check             # 机器判据：退出码 0=全好 1=有异常（含修复命令）
#   bash guardctl.sh explain [守卫名]  # 自解释：它做什么/为什么重要/怎么验证/停了会怎样
#   bash guardctl.sh doctor            # 深诊断：内核 OOM/看门狗/定时器楔死/注册漂移
#   bash guardctl.sh hold  <tag>       # 【总开关 关】停泊全部守卫（开维护窗口用）
#   bash guardctl.sh release <tag>     # 【总开关 开】恢复全部守卫并断言已重新武装
#   bash guardctl.sh watch [秒]        # 持续监视，状态翻转才告警（默认 60s 一轮）
#   bash guardctl.sh preflight         # 【开窗前】断言启动前置 + 自恢复链；0=可启动 1=不许启动
#   bash guardctl.sh snapshot          # 把当前摘要记为基线（BASELINE.md）
#
# 前置条件（PRECOND）与自恢复链（RECOVERY）也在 guards.conf 里注册：
#   * RECOVERY 在 check/status/preflight 里**始终判定**——它的失效与生产在不在跑无关，
#     且是**无声的**（冷却状态被写入未来时间戳 ⇒ 自愈链永久锁死，无任何日志）。
#   * PRECOND 只在 preflight 里**真正判定**。原因是"池子空出来"这类条件在生产
#     正常运行时本就不成立，若放进例行 check 就会每次都 FAIL（新一轮"狼来了"）。
#
# 退出码
#   0 一切正常 / 操作成功      1 发现异常或复位未完成 / preflight 被拦      2 用法错误
#   环境变量（与既有的 GUARD_CHECK_GATEWAY 同源设计）
#   GUARD_CHECK_GATEWAY=0   例行 start 路径不探业务面（guard-onstart.sh 默认置 0）
#   GUARD_CHECK_PRECOND=1   在 check/status 里也判定 PRECOND（等价于跑 preflight 的前半）
#   GUARD_ONESHOT_RUN_MAX   判定 oneshot"卡死"的持续时长上限，默认 120s
#   GUARD_ONESHOT_MAX_AGE   判定 oneshot"停摆"的静息时长上限，默认 900s
#
# 设计约束（务必遵守）
#   * status/check/doctor/explain 是**只读**的，不碰任何文件、不碰容器。
#   * hold/release 只改守卫脚本自身（写前留 .<tag> 备份），**从不碰生产容器**。
#   * guard-onstart.sh 由启动脚本调用，永远 exit 0，绝不阻塞启动。
# ==============================================================================
set -uo pipefail
export HOME=/home/liux***ya

GUARD_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF="${GUARD_CONF:-$GUARD_DIR/guards.conf}"   # 可用 GUARD_CONF 覆盖：便于用临时清单做故障注入测试，绝不碰生产清单
STATE_DIR="$GUARD_DIR/state"
ALERT_LOG="$GUARD_DIR/guard-alerts.log"
mkdir -p "$STATE_DIR" 2>/dev/null || true

# ---- 颜色（非 tty 自动关闭）--------------------------------------------------
if [ -t 1 ]; then R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1m'; N=$'\e[0m'
else R=; G=; Y=; B=; N=; fi

ok()   { echo "  ${G}OK${N}     $*"; }
warn() { echo "  ${Y}WARN${N}   $*"; }
bad()  { echo "  ${R}FAIL${N}   $*"; }
info() { echo "  ${B}info${N}   $*"; }
# SKIP = 一等结论（"这一项在本机不适用/结构性不存在"），**不是** WARN。
# 把 SKIP 渲染成 WARN 的后果是每次巡检都叫一声 —— 那正是要消掉的噪音。
skip() { echo "  SKIP   $*"; }
hdr()  { echo; echo "${B}=== $* ===${N}"; }

# 告警：既写日志，也尽量写 syslog（无 root 也可），供外部监控抓取
# 2026-09-20 H1：可选 webhook 出口——GUARD_ALERT_HOOK 设为 URL 时，CRIT 级追加
# 一次 curl POST（JSON: {severity,host,text,ts}）。默认未设=零行为变化；hook 失败
# 绝不影响本地留痕（此前「告警只写本地无人收」是静默错误的根缺口）。
alert() {  # alert <severity> <text>
  local sev="$1"; shift
  printf '%s [%s] %s %s\n' "$(date -Is)" "$sev" "$(hostname)" "$*" >> "$ALERT_LOG" 2>/dev/null || true
  command -v logger >/dev/null 2>&1 && logger -t guardctl -p "daemon.$([ "$sev" = CRIT ] && echo err || echo warning)" \
      "[$sev] $(hostname) $*" 2>/dev/null || true
  if [ "$sev" = CRIT ] && [ -n "${GUARD_ALERT_HOOK:-}" ]; then
    curl -sS --max-time 10 -H 'Content-Type: application/json' \
      -d "{\"severity\":\"$sev\",\"host\":\"$(hostname)\",\"text\":\"$*\",\"ts\":\"$(date -Is)\"}" \
      "$GUARD_ALERT_HOOK" >/dev/null 2>&1 || true
  fi
  [ "$sev" = CRIT ] && bad "$*" || warn "$*"
}
QUIET=0

role_of_host() {
  case "$(hostname)" in
    dgxspark01) echo head ;;
    dgxspark02|dgxspark03|dgxspark04) echo worker ;;
    *) echo unknown ;;
  esac
}
ROLE=$(role_of_host)

# ---- systemd 读取封装（全部只读）---------------------------------------------
u_prop()  { systemctl show -p "$2" --value "$1" 2>/dev/null; }          # 属性值
u_state() { systemctl is-active "$1" 2>/dev/null || echo unknown; }     # active/inactive/failed/activating
u_script(){ u_prop "$1" ExecStart | tr ';' '\n' | grep -oE '/[^ ]*\.(sh|py)' | tail -1; }  # ExecStart 里的 .sh/.py
u_md5()   { local f="$1"; [ -f "$f" ] && md5sum "$f" 2>/dev/null | cut -c1-12 || echo "-"; }
# role=all 的行 = "任何主机都要满足"。read_* 已把 all 放进来，但各显示循环**又**用
# `[ "$r" = "$ROLE" ]` 过滤了一遍，于是 `GUARD|all|…` 仍然在任何主机上都不被判定
# （2026-09-17 交叉审核 B2 的完整根因：不是一处，是 18 处）。统一走这个判据。
role_match() { [ "$1" = "$ROLE" ] || [ "$1" = all ]; }

is_parked(){  # 脚本内容是否为"停泊桩"
  local f="$1"; [ -f "$f" ] || return 1
  # ★只看头 5 行：停泊桩由 cmd_hold 生成、标记就在开头（见本文件 738/746 行的桩文本）。
  #   全文 grep 的代价是：真脚本正文里只要写过"停泊"二字，就会把 CRIT 静默降级成 WARN。
  head -5 "$f" 2>/dev/null | grep -qE 'WINDOW HOLD|REX-HOLD|guardctl HOLD|停泊|parked' 2>/dev/null
}

# ---- 单调钟时间戳解析 --------------------------------------------------------
# ⚠️ 坑：同一个 systemd 对**不同单元/属性**会给出两种格式——
#   * 服务属性（如 ExecMainExitTimestampMonotonic）多为**原始微秒**；
#   * 定时器属性（如 NextElapseUSecMonotonic）可能是 "3h 37min 28.166119s"
#     这样的**人类可读时长**（本机实测，systemd 版本相关）。
# 用 `date -d` 解析会在中文 locale 下失败，所以这里手工换算，两种格式都吃。
mono_secs() {  # 单调钟时间戳 → 自开机起秒数；无法解析则不输出
  local v="$1"
  case "$v" in ''|0|*infinity*|*Infinity*) return ;; esac
  if printf '%s' "$v" | grep -qE '^[0-9]+$'; then printf '%d' "$(( v / 1000000 ))"; return; fi
  local secs=0 n
  n=$(printf '%s' "$v" | grep -oE '[0-9]+(\.[0-9]+)?h' | tr -d 'h')
  [ -n "$n" ] && secs=$(awk -v a="$secs" -v b="$n" 'BEGIN{printf "%d", a+b*3600}')
  n=$(printf '%s' "$v" | grep -oE '[0-9]+(\.[0-9]+)?min' | sed 's/min//')
  [ -n "$n" ] && secs=$(awk -v a="$secs" -v b="$n" 'BEGIN{printf "%d", a+b*60}')
  n=$(printf '%s' "$v" | grep -oE '[0-9]+(\.[0-9]+)?s$' | tr -d 's')
  [ -n "$n" ] && secs=$(awk -v a="$secs" -v b="$n" 'BEGIN{printf "%d", a+b}')
  [ "$secs" -gt 0 ] && printf '%d' "$secs"
}
mono_age() {  # 单调钟时间戳 → 距今秒数（负值=在未来）
  local s up; s=$(mono_secs "$1"); [ -n "$s" ] || return
  up=$(cut -d. -f1 /proc/uptime); printf '%d' "$(( up - s ))"
}

# ---- 单守卫状态判定 ----------------------------------------------------------
# 输出: <verdict>|<detail>
# verdict: OK HELD DRIFT DEAD MISSING DEGRADED
guard_verdict() {
  local unit="$1" want_type="$2" want_restart="$3" want_path="$4" want_md5="$5" required="$6"
  local st ty path md5 rp
  st=$(u_state "$unit")
  [ "$st" = "unknown" ] && { echo "MISSING|单元不存在"; return; }
  ty=$(u_prop "$unit" Type); rp=$(u_prop "$unit" Restart)
  path=$(u_script "$unit"); md5=$(u_md5 "$path")

  if is_parked "$path"; then echo "HELD|脚本是停泊桩($path)"; return; fi
  if [ "$want_md5" != "-" ] && [ "$md5" != "-" ] && [ "$md5" != "$want_md5" ]; then
    echo "DRIFT|md5=$md5 期望=$want_md5 ($path)"; return; fi

  # ---- 类型相关的静息态判定 -------------------------------------------------
  # oneshot 的**正常静息态就是 inactive**（跑完即退，等下一次定时器触发）。
  # 只看 is-active 会把健康的 oneshot 误判为 DEAD；真正的失效形态是
  # "卡在 activating"（永不退出 ⇒ 定时器 NextElapse=infinity）与"上次执行非 success"。
  #
  # ⚠️ 2026-09-11 二次修正：**短暂的 activating/active 是正常态，不是卡死**。
  #    OnUnitActiveSec=60s 的探针每次只跑数秒；任何恰好落在这几秒内的检查，
  #    都会看到 activating + 空的 ExecMainExitTimestampMonotonic。旧逻辑把这两个
  #    瞬时态直接判成 DEAD/"从未执行过"，实测约每 10 次检查误报 1 次（四机同源）。
  #    判据改为**按持续时间**：超过 GUARD_ONESHOT_RUN_MAX（默认 120s）才算真卡死，
  #    这既保留了 2026-09-11 那次"卡 40 分钟"的检出能力，又消除了瞬时误报。
  if [ "$ty" = "oneshot" ]; then
    # ★RemainAfterExit=yes 的 oneshot（如 gb10-clock-cap.service）跑完会**一直** active：
    #   下面那条"active 且 ActiveEnter 已过 run_max=120s ⇒ 卡死"的判据对它恒真 ⇒ 永久假 DEAD。
    #   这类单元的失效形态是 Result≠success（或单元消失），静息态就是 active。
    if [ "$(u_prop "$unit" RemainAfterExit)" = "yes" ]; then
      if [ "$(u_prop "$unit" Result)" = "success" ]; then echo "OK|oneshot(RemainAfterExit) 已成功并常驻 active"; return; fi
      echo "DEGRADED|oneshot(RemainAfterExit) Result=$(u_prop "$unit" Result)"; return
    fi
    local run_max="${GUARD_ONESHOT_RUN_MAX:-120}"
    case "$st" in
      activating|active)
        local el; el=$(mono_age "$(u_prop "$unit" ActiveEnterTimestampMonotonic)")
        if [ -n "$el" ] && [ "$el" -gt "$run_max" ]; then
          local pid; pid=$(u_prop "$unit" MainPID)
          echo "DEAD|oneshot 已执行 ${el}s 未退出（>${run_max}s，MainPID=$pid）—— 卡死，触发链已死"; return
        fi
        echo "OK|type=oneshot 正在执行中（${el:-?}s）—— 触发链活着，无需干预"; return ;;
      failed)
        echo "DEGRADED|上次执行失败（Result=$(u_prop "$unit" Result)）"; return ;;
    esac
    # inactive/dead：核对结果与新鲜度（用**单调钟**，避免中文 locale 下 date -d 解析失败）
    local res em age max_age
    res=$(u_prop "$unit" Result)
    em=$(u_prop "$unit" ExecMainExitTimestampMonotonic)
    max_age="${GUARD_ONESHOT_MAX_AGE:-900}"
    if [ "$res" != "success" ]; then echo "DEGRADED|上次执行 Result=$res"; return; fi
    age=$(mono_age "$em")
    if [ -z "$age" ]; then echo "DEGRADED|从未执行过（定时器未触发或从未成功）"; return; fi
    if [ "$age" -gt "$max_age" ]; then
      echo "DEGRADED|最近一次成功执行在 ${age}s 前（>${max_age}s）—— 触发链疑似已停"; return
    fi
    echo "OK|type=oneshot 静息正常，上次成功于 ${age}s 前"; return
  fi
  case "$st" in
    active) ;;
    failed) echo "DEGRADED|单元 failed（Result=$(u_prop "$unit" Result)）"; return ;;
    activating) echo "DEGRADED|activating（启动中，若长期不变即为卡死）"; return ;;
    *) echo "DEAD|单元 $st，守卫不在运行"; return ;;
  esac

  # Type=simple 的监视器：MainPID 必须真的在跑它的脚本
  if [ "$ty" = "simple" ]; then
    local pid; pid=$(u_prop "$unit" MainPID)
    if [ -z "$pid" ] || [ "$pid" = "0" ]; then echo "DEAD|MainPID 为空"; return; fi
    local a; a=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    case "$a" in
      *"$path"*) ;;
      *) echo "DEGRADED|MainPID $pid 跑的不是 $path（cmdline=$a）"; return ;;
    esac
  fi
  if [ "$want_restart" != "-" ] && [ "$rp" != "$want_restart" ]; then
    echo "DEGRADED|Restart=$rp 期望=$want_restart（崩溃后不会自动回来）"; return; fi
  echo "OK|type=$ty restart=$rp md5=$md5"
}

timer_verdict() {
  local t="$1" dep="$2"
  local nx; nx=$(u_prop "$t" NextElapseUSecMonotonic)
  [ -z "$nx" ] && { echo "MISSING|定时器不存在"; return; }
  # ★OnCalendar 型定时器（本例 daily-smoke.timer）的 NextElapseUSecMonotonic 恒为 0，
  #   "下一次触发"只出现在 NextElapseUSecRealtime（实测：Monotonic=0 / Realtime="Thu … UTC"）。
  #   旧逻辑把 0 当成"开机第 0 秒" ⇒ 打出 `开机第 ?s（原始值 0）`，看着像通过其实什么都没判。
  case "$nx" in
    0|0s|n/a)
      local rt; rt=$(u_prop "$t" NextElapseUSecRealtime)
      if [ -z "$rt" ] || [ "$rt" = "n/a" ]; then
        echo "OK|OnCalendar 型：下一次触发不可读（单调/实时皆空）定时器状态=$(u_state "$t")/$(u_prop "$t" UnitFileState)"; return
      fi
      case "$rt" in
        *[!0-9]*) echo "OK|OnCalendar 型，下次触发 $rt（实时钟）" ;;
        *) echo "OK|OnCalendar 型，下次触发 $(date -d "@$(( rt / 1000000 ))" '+%F %T' 2>/dev/null || echo "epoch=${rt}us")（实时钟）" ;;
      esac
      return ;;
  esac
  # ⚠️ 2026-09-11 二次修正：`infinity` 有**两种**含义，必须分开——
  #   a) 依赖单元**正在执行**：systemd 在运行期间无法给出下次 elapse，报 infinity
  #      **属正常**。OnUnitActiveSec=60s 的探针每次跑数秒，任何落在这几秒内的检查
  #      都会撞上它。旧逻辑一律判 DEAD，实测约每 10 次误报 1 次（四机同源）。
  #   b) 依赖单元卡死/不存在：这才是真失效（2026-09-11 那次卡了 40 分钟）。
  # 判据：infinity 时先看依赖单元状态；若在执行中，再按**持续时间**决定——
  #      超过 GUARD_ONESHOT_RUN_MAX 才算卡死。
  case "$nx" in
    *infinity*|*Infinity*)
      local dst; dst=$(u_state "$dep")
      case "$dst" in
        activating|active)
          local el run_max="${GUARD_ONESHOT_RUN_MAX:-120}"
          el=$(mono_age "$(u_prop "$dep" ActiveEnterTimestampMonotonic)")
          if [ -n "$el" ] && [ "$el" -gt "$run_max" ]; then
            echo "DEAD|依赖单元 $dep 已 ${el}s 未结束（>${run_max}s）且 NextElapse=infinity ⇒ 卡死，触发链已死"; return
          fi
          echo "OK|依赖单元正在执行（${el:-?}s）—— 此时 NextElapse=infinity 属正常"; return ;;
      esac
      echo "DEAD|NextElapse=infinity 且依赖单元 $dep 状态=$dst ⇒ 触发链已死（典型原因：卡在 activating）"; return ;;
  esac
  local s; s=$(mono_secs "$nx")
  echo "OK|下次触发在开机第 ${s:-?}s（原始值 $nx）"
}

# ---- 采集清单 ---------------------------------------------------------------
read_guards() {  # 输出 "<GUARD>|<role>|<unit>|<type>|<restart>|<path>|<md5>|<required>|<desc>"
  [ -f "$CONF" ] || { echo "guards.conf 缺失: $CONF" >&2; return 1; }
  # ★`all` 必须与 PRECOND/RECOVERY 同口径。旧版只认 $2==$ROLE ⇒ `GUARD|all|…` 的行
  #   **在任何主机上都不会被判定**（2026-09-17 交叉审核 B2：gb10-clock-cap.service 就此
  #   长期"在册但从不判定"，连带 guard_verdict 里专为 oneshot 写的分支成了不可达代码）。
  awk -F'|' -v r="$ROLE" '$1=="GUARD" && ($2==r || $2=="all") {print $0}' "$CONF"
}
read_timers() { awk -F'|' -v r="$ROLE" '$1=="TIMER" && ($2==r || $2=="all") {print $0}' "$CONF" 2>/dev/null; }
# PRECOND 允许 role=all（任何角色都要满足的前置条件）。
read_preconds() { awk -F'|' -v r="$ROLE" '$1=="PRECOND" && ($2==r || $2=="all") {print $0}' "$CONF" 2>/dev/null; }
read_recoveries() { awk -F'|' -v r="$ROLE" '$1=="RECOVERY" && ($2==r || $2=="all") {print $0}' "$CONF" 2>/dev/null; }

# ==============================================================================
# 前置条件判定（只读，不需要 root）
#
# 设计原则：**宁可 SKIP 也不要误报**。任何读不出来的量都返回 SKIP 并说明原因，
# 而不是猜一个 0 再判 FAIL——上一版 guardctl 的三个"狼来了"都是这么来的。
# ==============================================================================
precond_verdict() {  # <name> <kind> <arg> <want>
  local name="$1" kind="$2" arg="$3" want="$4"
  case "$kind" in
    file)
      if [ -e "$arg" ]; then echo "OK|$arg 存在"; else echo "FAIL|$arg 不存在（$name 不满足）"; fi ;;
    md5)
      if [ ! -f "$arg" ]; then echo "FAIL|$arg 不存在，无法校验版本"; return; fi
      local got; got=$(md5sum "$arg" 2>/dev/null | cut -c1-12)
      if [ "$got" = "$want" ]; then echo "OK|md5=$got 已钉版"
      else echo "DEGRADED|md5=$got 期望=$want —— 版本漂移，须确认是否漏了修复"; fi ;;
    memfree)
      # 有效空闲 = MemFree + 可回收文件页（2026-09-11e 第三次修订，前两版都量错了对象）
      #
      # 这一项要回答的是"驱动做 gmu 一次性预留（~84 GiB）时，内核能给出多少页"。
      # 候选量的实测（node01，2026-09-11e）：
      #   MemFree 102.9 GiB / MemAvailable 102.6 GiB / 可回收文件页 10.4 GiB ⇒ 真实可取用 113.3 GiB
      # 为什么两个都不能直接用：
      #   · MemAvailable 的定义是 `MemFree + 可回收 − totalreserve_pages`，而
      #     v41_window_prep.sh 曾把 vm.min_free_kbytes=1572864 / watermark_scale_factor=200
      #     之后 node0 的 low 水位实测 3.91 GiB、high 6.33 GiB —— **我们自己的保护动作**
      #     把被检查的量扣掉了 4–6 GiB（这笔膨胀保留是为 swap 回收风暴买的缓冲，swap 按设计
      #     关闭后收益归零，2026-09-11f 已回落到 524288/50 ⇒ node0 low≈1.0 GiB）；
      #   · MemFree 不扣水位，但**也不含干净页缓存**，而宿主读过的镜像层/权重分片恰恰会
      #     留下十几 GiB 干净缓存（正是这台 node01：10.4 GiB）——这些页内核随时可回收给
      #     驱动，却被 MemFree 当成"已占用"。
      # 两版都踩了同一个坑：拿一个被无关因素压低的代理量当门 ⇒ 池子很空的机器会被
      # 永久钉在 BLOCKED（同 v0.4.1 磁盘阈值 100 GiB 的教训）。故取
      #   MemFree + Cached + SReclaimable − Shmem
      # 作为"有效空闲"，阈值不变；三项原始值一并打印以便复核。
      local line
      line=$(awk -F: '
        /^(MemFree|Cached|SReclaimable|Shmem|MemAvailable):/{gsub(/ /,"",$2); v[$1]=$2}
        END{ if (v["MemFree"]=="") exit 1
             printf "%d %d %d %d",
               (v["MemFree"]+v["Cached"]+v["SReclaimable"]-v["Shmem"])/1024,
               v["MemFree"]/1024, v["MemAvailable"]/1024,
               (v["Cached"]+v["SReclaimable"]-v["Shmem"])/1024 }' /proc/meminfo 2>/dev/null)
      if [ -z "$line" ]; then echo "SKIP|/proc/meminfo 读不到 MemFree"; return; fi
      local emib fmib amib cmib; read -r emib fmib amib cmib <<<"$line"
      if [ "$emib" -ge "$want" ]; then
        echo "OK|有效空闲 ${emib} MiB ≥ ${want} MiB（= MemFree ${fmib} + 可回收文件页 ${cmib}；MemAvailable ${amib} 被水位保留压低，仅参考）"
      else
        echo "FAIL|有效空闲 ${emib} MiB < ${want} MiB（= MemFree ${fmib} + 可回收文件页 ${cmib}）—— 池子没空出来，**不要启动**"
      fi ;;
    memavail)
      local kb; kb=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)
      if [ -z "$kb" ]; then echo "SKIP|/proc/meminfo 读不到 MemAvailable"; return; fi
      local mib=$(( kb / 1024 ))
      if [ "$mib" -ge "$want" ]; then echo "OK|MemAvailable ${mib} MiB ≥ ${want} MiB"
      else echo "FAIL|MemAvailable ${mib} MiB < ${want} MiB —— 池子没空出来，**不要启动**"; fi ;;
    memfreeraw)
      # V 轨门（2026-09-13）：防的是**池缩水**，与上面 memfree 防 OOM 是两个口径。
      # vLLM 的启动可用内存/KV 池定尺寸读的是**裸 MemFree**——干净页缓存被它当
      # "已用"（本文件 doctor 节统一内存结论的实测）。同 GMU=0.82 下池实测漂移
      # 1.56-4.28 GiB（并发 3.43×-8.89×），与起栈时刻的页缓存存量直接相关；
      # "有效空闲"把可回收页算进来，恰好掩盖了这个缩水。故本门要求页缓存
      # **真的被 drop 过**（可回收 ≠ 已回收）。
      local kb2; kb2=$(awk '/^MemFree:/{print $2}' /proc/meminfo 2>/dev/null)
      if [ -z "$kb2" ]; then echo "SKIP|/proc/meminfo 读不到 MemFree"; return; fi
      local mib2=$(( kb2 / 1024 ))
      if [ "$mib2" -ge "$want" ]; then
        echo "OK|裸 MemFree ${mib2} MiB ≥ ${want} MiB（vLLM 池定尺寸口径：页缓存已清，可全额进 KV 池）"
      else
        echo "FAIL|裸 MemFree ${mib2} MiB < ${want} MiB —— 页缓存没 drop（可回收≠已回收），vLLM 会把缓存当已用、KV 池缩水（2026-09-13 实测 1.56GiB/3.43× vs 族高 4.28GiB/8.89×）；先跑 v41_kv_hygiene.sh 或 v41_window_prep.sh 再启动"
      fi ;;
    diskfree)
      local av; av=$(df -Pk "$arg" 2>/dev/null | awk 'NR==2{print $4}')
      if [ -z "$av" ]; then echo "SKIP|df $arg 无输出"; return; fi
      local amib=$(( av / 1024 ))
      if [ "$amib" -ge "$want" ]; then echo "OK|$arg 可用 ${amib} MiB ≥ ${want} MiB"
      else echo "FAIL|$arg 可用 ${amib} MiB < ${want} MiB"; fi ;;
    proc)
      # 参数 = pgrep -f 的模式（正则，用 [x] 形式自避），期望 = 最少实例数。
      # 只读：检查一个守护**在不在**。2026-09-15 W4 事故根因就是"止损守护未运行"
      # （四机无 oom_gate monitor ⇒ 8M pin 的瞬态无人拦，直接全局 OOM 连杀）。
      if ! command -v pgrep >/dev/null 2>&1; then echo "SKIP|pgrep 不可用"; return; fi
      # 期望值不是整数 = 注册表写错了行。旧行为是把它丢给 `[ "$n" -ge "$want" ]`，
      # 于是每次巡检都打一行 `[: -: 需要整数表达式` 并报 FAIL —— 一条永假的告警，
      # 把"注册表写错"伪装成"守护挂了"。fail-closed 仍要出声，但要说清是什么错。
      case "$want" in ''|*[!0-9]*) echo "SKIP|期望值 '$want' 不是整数（guards.conf 该行写错）⇒ 本项不判定"; return ;; esac
      # ★只数**真身**，不数包装壳。`bash -c '… setsid oom_gate.sh monitor …'` 这类一次性
      # 包装进程的 cmdline 里带着同样的模式串，于是"真身死了"也能凑够期望数（cmd_hold 早就
      # 排除 *" -c "* 了，这里一直漏着）。判据 = /proc/<pid>/cmdline 里没有 " -c " 段。
      local n=0 pid cl hits=""
      for pid in $(pgrep -f "$arg" 2>/dev/null); do
        cl=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || continue
        case "$cl" in *" -c "*) continue ;; esac
        n=$((n+1)); hits="$hits $pid"
      done
      if [ "$n" -ge "$want" ]; then
        echo "OK|匹配 '$arg' 的真身 $n 个 ≥ $want 个（pid:${hits:- 无}；包装壳已排除）"
      else
        echo "FAIL|匹配 '$arg' 的进程 $n 个 < $want 个 —— 期望的守护形态不在役：**进程没了，或参数漂移**（进程没了的典型场景=2026-09-15 W4：无兜底 ⇒ 全局 OOM 连杀）"
      fi ;;
    envpin)
      # 参数 = <文件>::<必须出现的子串>，期望 = -（子串出现即 OK）。
      # 用途：把"已批准的生产旋钮"钉进巡检——例 .env.tp4 里的
      # MAX_TOTAL_TOKENS=<批准值> / SGLANG_DSV4_KV_LAYOUT=fork-v4-fp4。
      # 与 md5 kind 的分工：md5 钉"脚本整版"，本 kind 钉"配置里的单个事实"，
      # 因此改 pin 只需改这里的一行，而不必重算整个文件 md5。
      local f="${arg%%::*}" s="${arg#*::}"
      if [ "$arg" = "$s" ] || [ -z "$s" ]; then echo "SKIP|envpin 参数须为 <file>::<substring>"; return; fi
      if [ ! -f "$f" ]; then echo "FAIL|$f 不存在，无法核对"; return; fi
      if grep -qF -- "$s" "$f"; then echo "OK|$f 含 '$s'"
      else echo "FAIL|$f 不含 '$s' —— 生产旋钮与台账不符（若有意的变更，先更新 guards.conf 再开窗）"; fi ;;
    archscr)
      # 参数 = 一个体检脚本（可带参数，按空格切）。期望 = -。
      # 退出码约定：0=OK / 1=FAIL / 2=SKIP（当前无从判定，例：引擎没跑就没有"在役路径"可体检）
      # 用途：把外部体检脚本接进巡检，脚本自己负责输出人话与退出码，本 kind 只负责在
      # preflight 里判定它。**只读**，不得有副作用。
      # 首个用户 = flashinfer-arch-guard.sh：SM121 上 flashinfer AOT 取件的 arch 体检。
      # 为什么需要它：flashinfer 的 JitSpec.try_load() 在 is_aot 时**直接返回预编译包**，
      # **不做任何 arch 校验**；若取到的 .so 里只有 sm_100a/sm_103a 的 cubin（arch-accelerated
      # 对 SM121 不向前兼容）且无 PTX 兜底，故障要拖到**首次核启动**才暴露，且报错点离病因很远。
      # ⚠ 本体检看的是"进程真正 mmap 进来的模块"（/proc/<pid>/maps），不是在役路径的静态
      #   超集——包内没被取件的旧模块无害（moe_utils 就是这样：只有 100a/103a，而我方
      #   MoE 走 b12x，根本不取它）。
      local sc="${arg%% *}"
      if [ ! -x "$sc" ] && ! command -v "$sc" >/dev/null 2>&1; then
        echo "FAIL|体检脚本不可用：$sc"; return
      fi
      local out rc
      out=$($arg 2>&1); rc=$?
      case "$rc" in
        0) echo "OK|$(printf '%s' "$out" | tail -1)" ;;
        2) echo "SKIP|$(printf '%s' "$out" | tail -1)" ;;
        *) echo "FAIL|$(printf '%s' "$out" | grep -E 'FAIL|不可用' | head -3 | tr '\n' ' ')" ;;
      esac ;;
    unitprop)
      # 2026-09-20 H3：断言 systemd 单元属性。参数 = <unit>::<prop>，期望 = 数值上限。
      # 先试 --user 再试系统域（dsv41-serve 是用户级单元）。首个用户 = 保活单元崩溃循环：
      # Restart=always 会把 38 连败掩盖成"一直 active"，NRestarts/Result 不在任何判定面
      # （2026-09-19 事故是事后翻 journal 才发现）。
      local un="${arg%%::*}" pr="${arg#*::}"
      if [ "$arg" = "$pr" ] || [ -z "$pr" ]; then echo "SKIP|unitprop 参数须为 <unit>::<prop>"; return; fi
      case "$want" in ''|*[!0-9]*) echo "SKIP|期望值 '$want' 须为数值上限（guards.conf 该行写错）"; return ;; esac
      local pv
      pv=$(systemctl --user show -p "$pr" --value "$un" 2>/dev/null)
      [ -z "$pv" ] && pv=$(systemctl show -p "$pr" --value "$un" 2>/dev/null)
      case "$pv" in
        ''|*[!0-9]*) echo "SKIP|$un 的 $pr 读不到或非数值（'$pv'）—— 单元可能未加载"; return ;;
      esac
      if [ "$pv" -le "$want" ]; then
        echo "OK|$un $pr=$pv ≤ $want"
      else
        echo "FAIL|$un $pr=$pv > $want —— 保活在连环重启/反复失败（Restart=always 会把崩溃循环掩盖成 active；翻 journalctl --user -u $un 找首因）"
      fi ;;
    *) echo "SKIP|未知 kind=$kind" ;;
  esac
}

# ==============================================================================
# 自恢复链判定
#
# 核心是那个**不对称失效**：state 被写成未来时间戳后，判据 `NOW-LAST < COOLDOWN`
# 恒真，自愈链永久锁死且**不产生任何日志**。所以负值必须单独判成 DEAD，而不是
# 被算成"还在冷却中"（那正是旧代码的 bug）。
# 另附静态检查：链脚本缺负值护栏 ⇒ 根因仍在，报 DEGRADED。
# ==============================================================================
chain_is_wired() {  # $1 = 链脚本路径；真 = 有单元引用它
  local base; base=$(basename "$1")
  grep -rlF -- "$base" /etc/systemd/system /usr/lib/systemd/system /lib/systemd/system 2>/dev/null \
    | grep -qE '\.(service|timer)$'
}

recovery_verdict() {  # <name> <statefile> <chain> <cooldown>
  local name="$1" state="$2" chain="$3" cool="$4"
  local chain_ref="$3"   # 单元实际调用的路径（停泊替换后仍用它判断"接线"）
  local now; now=$(date +%s)

  # ---- 停泊感知（2026-09-11 修正）----------------------------------------
  # 开窗期间 v41_window_hold.sh 会把链脚本**替换成停泊桩**，真身留在 <chain>.<suffix>。
  # 若不感知这一点，静态检查就会对着 400 字节的桩报"缺负值护栏 ⇒ DEGRADED"，
  # 于是 preflight 在**它自己刚停泊之后**必然 BLOCKED —— 一个纯自伤的假阳性。
  # 正确做法：静态检查评估**停泊前的真身**，并在结论里注明当前处于停泊态。
  local hnote="" newest=""
  newest=$(ls -1t "$chain".* 2>/dev/null | head -1)
  if grep -qE 'WINDOW HOLD|REX-HOLD|guardctl HOLD|unit parked|guardctl\.sh (hold|release)' "$chain" 2>/dev/null \
     || { [ -n "$newest" ] && [ "$newest" -nt "$chain" ]; }; then
    # ★停泊 = 自愈链**当前不工作**（桩脚本立即成功退出、什么都不做）。这必须是一等结论。
    #   旧版把停泊态"翻译"成"改去评估停泊前的真身"，于是输出 OK/PASS —— 与 GUARD 的
    #   HELD→WARN 口径正好相反，结果是"链被关掉"成了唯一**不会被渲染出来**的失效形态
    #   （README 反复强调 RECOVERY 的失效是无声的，这条却把它渲染成绿的）。
    #   实测代价：2026-09-17 交叉审核查到 01 上这枚停泊桩**挂了 6 天**（2026-09-11 窗口留下的），
    #   而 status/check 一路报 PASS/rc=0。
    [ -n "$newest" ] && hnote="  ［真身备份：$(basename "$newest")］"
    echo "HELD|链脚本是**停泊桩**（$(basename "$chain_ref")）⇒ 自愈链当前不工作；不在维护窗口内就用 'guardctl.sh release <tag>' 还原$hnote"; return
  fi

  # ---- 接线检查：链脚本有没有单元在调用它 -----------------------------------
  # worker 上 healthcheck-rebuild.sh 在盘上（P3），但**没有任何单元调用它**（未挂载该单元），
  # 于是冷却状态文件永远不存在 ⇒ 旧逻辑每次都报一条永久 WARN，并建议创建一个没人读的文件。
  # 结构性不存在 ≠ 异常：判据 = 有没有单元的 ExecStart 引用这个脚本。
  if ! chain_is_wired "$chain_ref"; then
    echo "SKIP|链脚本 $(basename "$chain_ref") 在盘上，但没有任何单元引用它（本机未挂载该自恢复单元）⇒ 冷却状态本就不存在，不作为异常$hnote"; return
  fi

  # ---- 静态检查优先：链脚本本身不可用/有根因缺陷时，动态判定没有意义 ----
  # 这两条都是**会让自恢复彻底失效**的状态，必须直接报 DEGRADED，而不是"PASS 附带一句提醒"。
  if [ ! -f "$chain" ]; then
    echo "DEGRADED|链脚本 $chain 不存在 ⇒ 自恢复链不可能工作"; return
  fi
  if ! grep -q 'NOW - LAST)) -ge 0' "$chain" 2>/dev/null; then
    echo "DEGRADED|链脚本缺负值护栏（md5=$(md5sum "$chain" 2>/dev/null | cut -c1-12)）⇒ 一旦 state 被写成未来时间戳就会再次永久自锁（2026-09-11 根因）$hnote"; return
  fi

  # ---- 动态检查：冷却窗状态 ----
  if [ ! -f "$state" ]; then
    echo "WARN|冷却状态文件不存在（链条从未触发过，或状态目录被清理）$hnote"; return
  fi
  local last; last=$(cat "$state" 2>/dev/null || echo "")
  case "$last" in
    ''|*[!0-9]*)
      echo "DEGRADED|冷却状态非法（内容='$last'）—— 判定会退化，须清零$hnote"; return ;;
  esac
  if [ "$last" -eq 0 ]; then
    echo "OK|无冷却记录（state=0，视为可触发）$hnote"; return
  fi
  local d=$(( now - last ))
  if [ "$d" -lt 0 ]; then
    echo "DEAD|冷却状态被写入未来时间戳（NOW−LAST=${d}s）⇒ 旧判据恒真、自愈链被永久锁死；到 $(( last + cool )) 才会自然解锁$hnote"; return
  fi
  if [ "$d" -lt "$cool" ]; then
    echo "OK|冷却窗内 ${d}s < ${cool}s（正常静息，还差 $(( cool - d ))s 解锁）$hnote"; return
  fi
  echo "OK|冷却窗已过（${d}s ≥ ${cool}s），下次探针失败即可重建$hnote"
}

# ==============================================================================
cmd_status() {
  [ "${1:-}" = silent ] && QUIET=1
  hdr "守卫总览  $(hostname)  role=$ROLE  $(date '+%F %T%z')"
  local bad_n=0 total=0
  while IFS='|' read -r _ r u ty rp p m req desc; do
    role_match "$r" || continue
    total=$((total+1))
    local v d; IFS='|' read -r v d <<<"$(guard_verdict "$u" "$ty" "$rp" "$p" "$m" "$req")"
    case "$v" in OK) ok   "$(printf '%-26s %s' "$u" "$d")" ;;
                   HELD)  warn "$(printf '%-26s %s' "$u" "$d")" ;;
                   DRIFT|DEGRADED) warn "$(printf '%-26s %s' "$u" "$d")"; bad_n=$((bad_n+1)) ;;
                   *)     if [ "$req" = yes ]; then bad "$(printf '%-26s %s' "$u" "$d")"
                          else warn "$(printf '%-26s %s' "$u" "$d")"; fi
                          bad_n=$((bad_n+1)) ;;
    esac
    echo "         └ $desc"
  done < <(read_guards)
  while IFS='|' read -r _ r t dep req desc; do
    role_match "$r" || continue
    total=$((total+1))
    local v d; IFS='|' read -r v d <<<"$(timer_verdict "$t" "$dep")"
    case "$v" in OK) ok "$(printf '%-26s %s' "$t" "$d")" ;;
                   *) if [ "$req" = yes ]; then bad "$(printf '%-26s %s' "$t" "$d")"
                      else warn "$(printf '%-26s %s' "$t" "$d")"; fi
                      bad_n=$((bad_n+1)) ;;
    esac
    echo "         └ $desc"
  done < <(read_timers)
  # ---- 前置条件 + 自恢复链（2026-09-11 扩展：启动检查与自恢复纳入同一套件）----
  # 前置条件默认只展示不判定（见 cmd_check 的说明）；自恢复链**始终判定**，
  # 因为它的失效与生产是否在跑无关，且是无声的。
  local do_pre="${GUARD_CHECK_PRECOND:-0}"
  while IFS='|' read -r _ r n kind arg want req desc; do
    total=$((total+1))
    if [ "$do_pre" != "1" ]; then
      printf '         %s\n' "$(printf '%-26s %s' "前置:$n" "开窗前置（用 preflight 断言）")"
      echo "         └ $desc"; continue
    fi
    local v d; IFS='|' read -r v d <<<"$(precond_verdict "$n" "$kind" "$arg" "$want")"
    case "$v" in OK) ok "$(printf '%-26s %s' "前置:$n" "$d")" ;;
                   SKIP) skip "$(printf '%-26s %s' "前置:$n" "$d")" ;;
                   *) warn "$(printf '%-26s %s' "前置:$n" "$d")"; [ "$req" = yes ] && bad_n=$((bad_n+1)) ;;
    esac
    echo "         └ $desc"
  done < <(read_preconds)
  while IFS='|' read -r _ r n state chain cool req desc; do
    total=$((total+1))
    local v d; IFS='|' read -r v d <<<"$(recovery_verdict "$n" "$state" "$chain" "$cool")"
    case "$v" in OK) ok "$(printf '%-26s %s' "自恢复:$n" "$d")" ;;
                   SKIP) skip "$(printf '%-26s %s' "自恢复:$n" "$d")" ;;
                   HELD) warn "$(printf '%-26s %s' "自恢复:$n" "$d")" ;;
                   *) warn "$(printf '%-26s %s' "自恢复:$n" "$d")"; [ "$req" = yes ] && bad_n=$((bad_n+1)) ;;
    esac
    echo "         └ $desc"
  done < <(read_recoveries)
  # 容器伴随性：守卫在跑，就该有容器被跟随
  if [ "$QUIET" = 0 ]; then
    hdr "被守卫的容器"
    # 模式要覆盖**实际在役**的名字：生产是 dsv41-head/dsv41-worker（旧栈才是 vllm-tp4-rank*）。
    # 只认旧名字 = 每次 status 都报一句恒假的 WARN，把"守卫在跟随什么"变成噪音。
    local c; c=$(docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -E '^(vllm-tp4-rank|dsv41-)' || true)
    [ -n "$c" ] && echo "$c" | sed 's/^/  /' || warn "本机没有被守卫的容器在运行（模式 ^(vllm-tp4-rank|dsv41-)）"
  fi
  echo
  if [ "$bad_n" = 0 ]; then echo "  ${G}${B}结论：$total 项守卫全部正常${N}"
  else echo "  ${R}${B}结论：$total 项中有 $bad_n 项异常 —— 跑 'bash guardctl.sh check' 拿修复命令${N}"; fi
  [ "$bad_n" = 0 ]
}

# ==============================================================================
cmd_check() {
  echo "guardctl check on $(hostname) role=$ROLE —— $(date -Is)"
  local bad_n=0
  while IFS='|' read -r _ r u ty rp p m req desc; do
    role_match "$r" || continue
    local v d; IFS='|' read -r v d <<<"$(guard_verdict "$u" "$ty" "$rp" "$p" "$m" "$req")"
    case "$v" in
      OK) printf 'PASS %-26s %s\n' "$u" "$d" ;;
      HELD) printf 'WARN %-26s %s\n' "$u" "$d ($desc)"
            echo "     -> 若不在维护窗口：bash $GUARD_DIR/guardctl.sh release <tag>" ;;
      DRIFT) printf 'WARN %-26s %s\n' "$u" "$d"; bad_n=$((bad_n+1))
            echo "     -> 合法改动请跑 'guardctl.sh snapshot' 更新基线；否则跑 release 复位" ;;
      # ★渲染成 FAIL 就必须计入 bad_n。required=no 只说明"它坏了不挡启动"，**不**说明
      #   可以一边打印 FAIL 一边宣布 ALL-OK / 退出 0（2026-09-17 交叉审核 B1：那是个可达态，
      #   且四机在册的 vllm-logdump.service 正是 required=no ⇒ 它再坏也没人被告知）。
      MISSING) printf '%s %-26s %s\n' "$([ "$req" = yes ] && echo FAIL || echo WARN)" "$u" "$d"; bad_n=$((bad_n+1)) ;;
      DEAD) printf '%s %-26s %s\n' "$([ "$req" = yes ] && echo FAIL || echo WARN)" "$u" "$d"; bad_n=$((bad_n+1))
            [ "$ty" = oneshot ] && echo "     -> 修复：kill -TERM \$(systemctl show -p MainPID --value $u) 及其子进程（见 explain $u）" ;;
      *) printf '%s %-26s %s\n' "$([ "$req" = yes ] && echo FAIL || echo WARN)" "$u" "$d"; bad_n=$((bad_n+1))
            echo "     -> 修复：systemctl status $u；必要时 release <tag> 复位守卫脚本" ;;
    esac
  done < <(read_guards)
  while IFS='|' read -r _ r t dep req desc; do
    role_match "$r" || continue
    local v d; IFS='|' read -r v d <<<"$(timer_verdict "$t" "$dep")"
    case "$v" in
      OK) printf 'PASS %-26s %s\n' "$t" "$d" ;;
      *)  printf '%s %-26s %s\n' "$([ "$req" = yes ] && echo FAIL || echo WARN)" "$t" "$d"; bad_n=$((bad_n+1))
          echo "     -> 修复：回收 $dep 的停泊/卡死进程后定时器会自动重算；见 explain $dep" ;;
    esac
  done < <(read_timers)
  # ---- 前置条件：启动/开窗前必须满足（只读）----
  # ⚠️ 默认**不判定**，只 SKIP。理由：其中"池子空出来"这类条件在**生产正常运行时
  #    本来就不成立**（生产在跑，池子当然不空）。若在例行巡检里断言它，就会变成
  #    "每次 check 都 FAIL"的新一轮狼来了。它们是**开窗/首启前置**，只在
  #    `guardctl.sh preflight`（或 GUARD_CHECK_PRECOND=1）里才真正判定。
  local do_pre="${GUARD_CHECK_PRECOND:-0}"
  while IFS='|' read -r _ r n kind arg want req desc; do
    if [ "$do_pre" != "1" ]; then
      printf 'SKIP %-26s 开窗前置（例行巡检不判定；用 preflight 断言）\n' "前置:$n"; continue
    fi
    local v d; IFS='|' read -r v d <<<"$(precond_verdict "$n" "$kind" "$arg" "$want")"
    case "$v" in
      OK)   printf 'PASS %-26s %s\n' "前置:$n" "$d" ;;
      SKIP) printf 'SKIP %-26s %s\n' "前置:$n" "$d" ;;
      *)    printf '%s %-26s %s\n' "$([ "$req" = yes ] && echo FAIL || echo WARN)" "前置:$n" "$d"
            [ "$req" = yes ] && bad_n=$((bad_n+1))
            echo "     -> 用途：$desc" ;;
    esac
  done < <(read_preconds)
  # ---- 自恢复链：负值冷却=永久锁死（无声失效，必须在开窗前查）----
  while IFS='|' read -r _ r n state chain cool req desc; do
    local v d; IFS='|' read -r v d <<<"$(recovery_verdict "$n" "$state" "$chain" "$cool")"
    case "$v" in
      OK)   printf 'PASS %-26s %s\n' "自恢复:$n" "$d" ;;
      SKIP) printf 'SKIP %-26s %s\n' "自恢复:$n" "$d" ;;
      HELD) printf 'WARN %-26s %s\n' "自恢复:$n" "$d"
            echo "     -> 若不在维护窗口：bash $GUARD_DIR/guardctl.sh release <tag>" ;;
      *)    printf '%s %-26s %s\n' "$([ "$req" = yes ] && echo FAIL || echo WARN)" "自恢复:$n" "$d"
            [ "$req" = yes ] && bad_n=$((bad_n+1))
            echo "     -> 修复：清零冷却状态 echo 0 > $state（只读检查不会替你改，需人工/窗口内执行）" ;;
    esac
  done < <(read_recoveries)
  # 网关可用性（业务面）。⚠️ 两个"喊狼来了"的来源必须排除：
  #   a) 启动路径上网关本来就没起来 → guard-onstart.sh 置 GUARD_CHECK_GATEWAY=0；
  #   b) 网关**只在 head 上跑**（concurrency-proxy-v2.service 是 01 的单元），
  #      在 worker 上探 8001 必然失败 —— 那是**角色差异不是故障**，必须按角色收窄。
  if [ "${GUARD_CHECK_GATEWAY:-1}" = "1" ] && [ "$ROLE" = "head" ]; then
    local hc; hc=$(curl -s -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1:8001/health 2>/dev/null || echo 000)
    if [ "$hc" = "200" ]; then
      printf 'PASS %-26s HTTP 200\n' "gateway 8001 /health"
    else
      # ★宽限：容器还在加载权重时 /health 必然是 5xx（上游没起来）。这是**每次起栈/换班**
      #   都会出现的正常态；照报 CRIT 会让"每次切换窗口都产生假 CRIT"（README §8 让外部监控
      #   直接 grep CRIT）。判据：容器 health 仍是 starting ⇒ SKIP 并说明原因。
      local hs; hs=$(docker inspect dsv41-head --format '{{.State.Health.Status}}' 2>/dev/null || echo "")
      if [ "$hs" = "starting" ]; then
        printf 'SKIP %-26s HTTP %s（引擎仍在加载权重，容器 health=starting ⇒ 正常态）\n' "gateway 8001 /health" "$hc"
      else
        printf 'FAIL %-26s HTTP %s\n' "gateway 8001 /health" "$hc"; bad_n=$((bad_n+1))
      fi
    fi
  elif [ "$ROLE" != "head" ]; then
    printf 'SKIP %-26s 网关只部署在 head（本机 role=%s）\n' "gateway 8001 /health" "$ROLE"
  else
    printf 'SKIP %-26s 启动路径不检查业务面（GUARD_CHECK_GATEWAY=0）\n' "gateway 8001 /health" ""
  fi
  # ---- 2026-09-20 H3：保活单元崩溃循环断言（四机、每次 check 都判） ----
  # Restart=always 会把"连环崩溃"掩盖成一直 active：2026-09-19 的 38 连败就是
  # 事后翻 journal 才发现，期间任何巡检都报绿。systemctl restart 会清零 NRestarts，
  # 故超阈 = 自动重启在连环发生 = 真异常（人工重启不误报）。Result!=success 且
  # 非 active 同样出声（StartLimit 触顶后单元进 failed，进程早没了）。
  # ⚠语义分流（四机同步首跑补丁）：head 的单元=launcher（起真栈，重启即事故，
  # NRestarts>3 FAIL）；worker 侧同名单元=launcher-waiter（等容器出现再 docker wait，
  # 开窗/停泊期等不到→exit→Restart=always 属预期，NRestarts 累积是常态——02 实测
  # 120 次）。waiter 只断言 active；NRestarts>500 仅 WARN（真死循环保险丝）。
  # 两机 Description 都含 launcher-waiter ⇒ 分流键用本机 role 不用 Description。
  local _ku="dsv41-serve.service"
  if systemctl --user is-active --quiet "$_ku" 2>/dev/null || systemctl --user is-failed --quiet "$_ku" 2>/dev/null; then
    local _nr _rs
    _nr=$(systemctl --user show -p NRestarts --value "$_ku" 2>/dev/null)
    _rs=$(systemctl --user show -p Result --value "$_ku" 2>/dev/null)
    if [ "$ROLE" != head ]; then
      # 2026-09-21 防静默补丁（三路子代理交叉审计实锤）：旧逻辑只看 NRestarts>500，
      # 单元 failed（start-limit 触顶/ExecStop 断链）时仍打「PASS waiter active」——
      # 02/03/04 三机 failed 躺了数小时无人知。failed 必 FAIL；NRestarts 仍只做保险丝。
      local _as
      _as=$(systemctl --user show -p ActiveState --value "$_ku" 2>/dev/null)
      if [ "$_as" = failed ]; then
        printf 'FAIL %-26s waiter ActiveState=failed Result=%s NRestarts=%s（start-limit 触顶或单元断链；复位：systemctl --user reset-failed %s && systemctl --user start %s）\n' "保活:$_ku" "${_rs:-?}" "${_nr:-0}" "$_ku" "$_ku"
        bad_n=$((bad_n+1))
      elif [ "${_nr:-0}" -gt 500 ]; then
        printf 'WARN %-26s waiter NRestarts=%s（>500 疑真死循环；journalctl --user -u %s）\n' "保活:$_ku" "${_nr:-0}" "$_ku"
      else
        printf 'PASS %-26s waiter active（restarts=%s 属预期累积）\n' "保活:$_ku" "${_nr:-0}"
      fi
    elif [ "${_nr:-0}" -gt 3 ]; then
      printf 'FAIL %-26s NRestarts=%s（>3 自动重启连环发生；Restart=always 掩盖崩溃循环）\n' "保活:$_ku" "$_nr"
      printf '     -> 首因：journalctl --user -u %s | head -50\n' "$_ku"
      bad_n=$((bad_n+1))
    elif [ "$_rs" != "success" ] && [ -n "$_rs" ]; then
      printf 'WARN %-26s Result=%s（上次执行结果非 success）\n' "保活:$_ku" "$_rs"
    else
      printf 'PASS %-26s NRestarts=%s Result=%s\n' "保活:$_ku" "${_nr:-0}" "${_rs:-?}"
    fi
  else
    printf 'SKIP %-26s 用户单元未加载（维护/停泊态）\n' "保活:$_ku"
  fi
  echo

  # ---- 2026-09-21 门禁统筹（当日排查面全覆盖）：GID 洞 / NVML 时钟 / 停泊容器复活 ----
  # 三项都来自 2026-09-21 断电连环事故的实锤：GID 洞=NCCL 61 死、02 时钟楔死=
  # TP4 全体 prefill 减半（PD 安全模式）、sparkDash 复活=polkitd 风暴复发风险。
  echo "── 2026-09-21 排查面防线 ──────────────────────────────"
  # ① GID 洞常巡（断电后遗症之首；idx=3 与 .env.tp4 NCCL_IB_GID_INDEX_FORCE 对齐，
  #    改集群 GID 策略时这里同步改。洞口修复见 ~/w6-kit/FABRIC-GID-REPAIR-RUNBOOK.md §2）
  # 审计 P1 修：旧 `[ -d … ] || continue` 让「四口全缺」（mlx5 驱动塌=断电后真实
  # 形态）保持 _gid_holes 空 → PASS「无洞」——恰在 fabric 已死时宣布无洞。实查口数。
  _gid_holes="" _gid_missing="" _gid_seen=0
  for _hca in rocep1s0f0 rocep1s0f1 roceP2p1s0f0 roceP2p1s0f1; do
    if [ ! -d "/sys/class/infiniband/$_hca" ]; then _gid_missing="$_gid_missing $_hca"; continue; fi
    _gid_seen=$((_gid_seen+1))
    [ "$(cat /sys/class/infiniband/$_hca/ports/1/gid_attrs/types/3 2>/dev/null)" = "RoCE v2" ] \
      || _gid_holes="$_gid_holes $_hca"
  done
  if [ "$_gid_seen" -lt 4 ]; then
    printf 'FAIL %-26s HCA 缺失(%s/4)：缺%s —— 驱动塌/固件未就绪≠无洞，fabric 已不可用形态\n' "fabric:GID" "$_gid_seen" "$_gid_missing"
    bad_n=$((bad_n+1))
  elif [ -n "$_gid_holes" ]; then
    printf 'FAIL %-26s GID 洞(idx3)：%s —— NCCL 将 modify_qp 61 死；修复=runbook §2 IP 环回\n' "fabric:GID" "$_gid_holes"
    bad_n=$((bad_n+1))
  else
    printf 'PASS %-26s 四口 idx3 全 RoCE v2（无洞）\n' "fabric:GID"
  fi
  # ② NVML 时钟/温度（PD 安全模式病：P0+高util+<1200MHz+低瓦数+零标志）。
  #    只在采样窗内撞上 util≥50 才判负（空转态判不了，诚实报 SKIP 不假阳）；
  #    楔死机的修复=拔墙上 AC 冷断电（warm reboot 无效），runbook §7。
  # 审计 P1 修：nvidia-smi 失败/字段空/N.A 时三采样全部落空 → 旧逻辑走
  # 「PASS 采样窗全空转」——驱动半死（断电后目标场景）被当健康。NVML 不可读 =
  # SKIP/UNKNOWN，不计 PASS；数字性另加守卫（N/A 比较的报错噪音一并消除）。
  _hit=0 _clkmin=99999 _utmax=0 _tmpmax=0 _nvml_bad=0
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    _nvml_bad=1
  else
    for _i in 1 2 3; do
      read -r _u _c _t < <(nvidia-smi --query-gpu=utilization.gpu,clocks.sm,temperature.gpu \
        --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' | awk -F',' '{print $1, $2, $3}')
      if [ -z "${_u:-}" ] || ! [[ "$_u" =~ ^[0-9]+$ && "${_c:-x}" =~ ^[0-9]+$ ]]; then _nvml_bad=1; break; fi
      [ "$_u" -ge "$_utmax" ] && _utmax=$_u
      [ "${_c:-99999}" -lt "$_clkmin" ] && _clkmin=$_c
      [[ "${_t:-0}" =~ ^[0-9]+$ ]] && [ "$_t" -gt "$_tmpmax" ] && _tmpmax=$_t
      if [ "$_u" -ge 50 ] && [ "${_c:-9999}" -lt 1200 ]; then _hit=1; break; fi
      sleep 2
    done
  fi
  if [ "$_nvml_bad" = 1 ]; then
    printf 'SKIP %-26s NVML 不可读（nvidia-smi 缺失/驱动半死/字段 N.A）——时钟健康未知≠健康；断电后高发，人工复核\n' "gpu:时钟"
  elif [ "$_hit" = 1 ]; then
    printf 'FAIL %-26s GPU 时钟楔死（util=%s%% clock=%sMHz）＝PD 安全模式嫌疑：修复=关机拔墙上 AC 1-2 分钟（warm reboot 无效）；runbook §7\n' "gpu:时钟" "${_u}" "${_c}"
    bad_n=$((bad_n+1))
  elif [ "$_tmpmax" -ge 85 ]; then
    printf 'WARN %-26s GPU 温度峰值 %s°C ≥85（热风险；nvfancontrol MOK 未 enroll 前裸奔态）\n' "gpu:温度" "$_tmpmax"
  elif [ "$_utmax" -ge 50 ]; then
    printf 'PASS %-26s 负载采样健康（util峰=%s%% clock谷=%sMHz 温峰=%s°C）\n' "gpu:时钟" "$_utmax" "$_clkmin" "$_tmpmax"
  else
    printf 'PASS %-26s 采样窗全空转（util<50 不判楔死=防假阳；clock=%sMHz 温=%s°C）\n' "gpu:时钟" "$_clkmin" "$_tmpmax"
  fi
  # ③ 停泊容器复活（docker restart 策略在断电/重启后把停泊容器拉回；sparkDash
  #    轮询=31万 SSH 登录/天 ⇒ polkitd 泄漏复发。发现即 WARN+给停法）
  _zomb=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE '^sparkdash' | tr '\n' ' ')
  if [ -n "$_zomb" ]; then
    printf 'WARN %-26s 停泊容器复活：%s（断电拉回；轮询致 polkitd 风暴。停：docker update --restart=no %s && docker stop %s）\n' "docker:停泊复活" "$_zomb" "$_zomb" "$_zomb"
  else
    printf 'PASS %-26s 无 sparkDash 系停泊容器在跑\n' "docker:停泊复活"
  fi
  echo
  # 审计 P2 修：guards.conf 缺失或 ROLE=unknown 时循环 0 行、bad_n=0 → 空真 ALL-OK。
  # 没判定任何东西≠全绿。
  local _total; _total=$(read_guards 2>/dev/null | wc -l)
  if [ "$_total" -eq 0 ] || [ "$ROLE" = unknown ]; then
    echo "CHECK RESULT: UNKNOWN（注册表 0 行或角色未知 $ROLE——一票未判≠全绿；检查 $CONF 与 hostname）"
    return 1
  fi
  if [ "$bad_n" = 0 ]; then echo "CHECK RESULT: ALL-OK"; return 0; fi
  echo "CHECK RESULT: $bad_n PROBLEM(S)"; alert CRIT "$bad_n guard problem(s) on $(hostname)"; return 1
}

# ==============================================================================
cmd_preflight() {
  # 开窗/首启前置断言。与例行 check 的唯一区别：**真的判定 PRECOND**。
  # 用法（在停掉生产、准备启动之前跑）：
  #     bash guardctl.sh preflight
  # 退出码 0 = 可以启动；非 0 = 有必需前置未满足，**不要启动**。
  echo "guardctl preflight on $(hostname) role=$ROLE —— $(date -Is)"
  echo "（开窗前置断言；这些条件在生产正常运行时本就不成立，故不在例行 check 里判定）"
  echo
  local bad_n=0
  while IFS='|' read -r _ r n kind arg want req desc; do
    local v d; IFS='|' read -r v d <<<"$(precond_verdict "$n" "$kind" "$arg" "$want")"
    case "$v" in
      OK)   printf 'PASS %-26s %s\n' "前置:$n" "$d" ;;
      SKIP) printf 'SKIP %-26s %s\n' "前置:$n" "$d" ;;
      *)    printf '%s %-26s %s\n' "$([ "$req" = yes ] && echo FAIL || echo WARN)" "前置:$n" "$d"
            [ "$req" = yes ] && bad_n=$((bad_n+1))
            echo "     -> $desc" ;;
    esac
  done < <(read_preconds)
  # 自恢复链必须一并断言：冷却窗被锁死时启动，等于放弃自愈能力。
  while IFS='|' read -r _ r n state chain cool req desc; do
    local v d; IFS='|' read -r v d <<<"$(recovery_verdict "$n" "$state" "$chain" "$cool")"
    case "$v" in
      OK)   printf 'PASS %-26s %s\n' "自恢复:$n" "$d" ;;
      SKIP) printf 'SKIP %-26s %s\n' "自恢复:$n" "$d" ;;
      HELD) printf 'WARN %-26s %s\n' "自恢复:$n" "$d" ;;   # 开窗期间停泊是**预期**态，不挡启动
      *)    printf '%s %-26s %s\n' "$([ "$req" = yes ] && echo FAIL || echo WARN)" "自恢复:$n" "$d"
            [ "$req" = yes ] && bad_n=$((bad_n+1))
            echo "     -> 修复：echo 0 > $state" ;;
    esac
  done < <(read_recoveries)
  echo
  if [ "$bad_n" = 0 ]; then echo "PREFLIGHT RESULT: READY（前置齐备，可以启动）"; return 0; fi
  echo "PREFLIGHT RESULT: BLOCKED —— $bad_n 项必需前置未满足，**不要启动**"
  alert CRIT "$bad_n 项开窗前置未满足 on $(hostname)"
  return 1
}

# ==============================================================================
cmd_explain() {
  local want="${1:-}"
  local shown=0
  while IFS='|' read -r _ r u ty rp p m req desc; do
    role_match "$r" || continue
    [ -n "$want" ] && [ "$want" != "$u" ] && continue
    shown=1
    local v d; IFS='|' read -r v d <<<"$(guard_verdict "$u" "$ty" "$rp" "$p" "$m" "$req")"
    echo
    echo "${B}──────────────────────────────────────────────────────────────${N}"
    echo "${B}$u${N}   [role=$ROLE  当前=$v]"
    echo "  作用    : $desc"
    echo "  实现    : Type=$ty  Restart=$rp"
    echo "  ExecStar: ${p:--}"
    echo "  基线md5 : $m   （实际 $(u_md5 "$p")）"
    echo "  判定    : $d"
    case "$ty" in
      oneshot)
        echo "  ${Y}★ 这是 oneshot，最容易静默失效${N}"
        echo "    它的触发源是定时器。若它的主进程卡住不退出，单元会永远停在"
        echo "    'activating'，而定时器的 NextElapse 会变成 infinity —— 守卫从此"
        echo "    永不触发，且没有任何日志表明它坏了（2026-09-11 实测 40 分钟无人知）。"
        echo "    验证：systemctl is-active $u  应为 inactive/dead 而不是 activating"
        echo "          systemctl show vllm-healthcheck.timer -p NextElapseUSecMonotonic  不应是 infinity"
        echo "    修复：HP=\$(systemctl show -p MainPID --value $u)"
        echo "          kill -TERM \$HP; for c in \$(pgrep -P \$HP); do kill -TERM \$c; done"
        echo "          （必须连子进程一起信号：bash 会推迟处理信号直到前台子进程返回）"
        echo "    停了的后果：引擎卡死不健康时无人重建，只能等人工发现。" ;;
      simple)
        echo "  验证：systemctl is-active $u 应为 active"
        echo "        tr '\\0' ' ' < /proc/\$(systemctl show -p MainPID --value $u)/cmdline 应指向 $p"
        echo "    停了的后果：本机 vLLM 容器退出后不再被拉起（自愈链断）。" ;;
    esac
  done < <(read_guards)
  while IFS='|' read -r _ r t dep req desc; do
    role_match "$r" || continue
    [ -n "$want" ] && [ "$want" != "$t" ] && continue
    shown=1; echo; echo "${B}$t${N}   [$desc]"
    echo "  场景    : $(timer_verdict "$t" "$dep")"
    echo "  ${Y}判定口径：NextElapseUSecMonotonic == infinity 即为失效${N}（不是"没到点"，是"永不"）。"
  done < <(read_timers)
  # ★循环变量必须叫 pw 而不是 want：want 是函数开头那个"只看某一行"的过滤器，
  #   用同名变量接行内字段会把它覆盖成第一行的期望值，于是后面每一行都被自己的过滤器滤掉
  #   （2026-09-17 实测：explain 一条 PRECOND 都显示不出来，而 explain 恰恰是开窗前要读的东西）。
  while IFS='|' read -r _ r n kind arg pw req desc; do
    [ -n "$want" ] && [ "$want" != "$n" ] && [ "$want" != "前置:$n" ] && continue
    shown=1; echo; echo "${B}前置:$n${N}   [$desc]"
    echo "  检查    : kind=$kind 参数=${arg:--} 期望=${pw:--} 必需=$req"
    echo "  当前    : $(precond_verdict "$n" "$kind" "$arg" "$pw")"
    echo "  ${Y}这是**只读**检查，不满足时本套件只报告、不代你动手${N}"
    case "$kind" in
      memavail) echo "  为什么  : 窗口 2 实测四机全部宿主机 OOM（worker 被 shmem-rss 25.10 GiB 杀掉）。" ;;
      file)     echo "  为什么  : 这是红线的载体——未经完整 sha256 的权重目录**禁止挂载**给任何容器。" ;;
      proc)     echo "  为什么  : 守护的失效是**无声的**——进程没了不会报错，只在事故复盘时才被发现（2026-09-15 W4：pin 8M 时四机无止损守护 ⇒ 全局 OOM 连杀）。" ;;
      envpin)   echo "  为什么  : 生产旋钮散在 .env.tp4 里，改一处就换一种内存/性能形态；把**已批准值**钉成一行，漂移即报警。" ;;
    esac
  done < <(read_preconds)
  while IFS='|' read -r _ r n state chain cool req desc; do
    [ -n "$want" ] && [ "$want" != "$n" ] && [ "$want" != "自恢复:$n" ] && continue
    shown=1; echo; echo "${B}自恢复:$n${N}   [$desc]"
    echo "  状态文件: $state"
    echo "  链脚本  : $chain"
    echo "  冷却窗口: ${cool}s"
    echo "  当前    : $(recovery_verdict "$n" "$state" "$chain" "$cool")"
    echo "  ${Y}★ 这个链的失效是**无声的**：state 被写成未来时间戳后，判据"
    echo "    NOW-LAST < COOLDOWN 恒真 ⇒ 永不重建，且没有任何日志表明它坏了。"
    echo "    2026-09-11 实测 state=1789104989、NOW−LAST=−49518（负！）。${N}"
    echo "  修复    : echo 0 > $state   （清零后下一次探针失败即可正常重建）"
    echo "  根治    : 链脚本需含负值护栏 [ \$((NOW-LAST)) -ge 0 ]，且 state 写入点"
    echo "            必须在容器**真正删除成功之后**（不能'先占锁再动手'）。"
  done < <(read_recoveries)
  [ "$shown" = 1 ] || { echo "没有匹配的守卫：$want"; echo "本机($ROLE)可用：$(read_guards | awk -F'|' -v r="$ROLE" '$2==r{print $3}' | tr '\n' ' ')"; return 2; }
}

# ==============================================================================
cmd_doctor() {
  hdr "内核级故障痕迹（OOM / 看门狗 / NV_ERR）"
  # 审计 P2 修：journalctl 不可读时 grep -c 输出 0 与真零事件不可区分——先探活，
  # 不可读记 NA 并在告警文案明示（journal_watch.sh 已修同款，此处同步）。
  local oom wd nv
  if ! journalctl -k --since "-24h" --no-pager >/dev/null 2>&1; then
    oom=NA; wd=NA; nv=NA
    warn "journalctl -k 不可读（权限/journal 损坏）——OOM/看门狗/NV_ERR=UNKNOWN，勿当零事件"
  else
  oom=$(journalctl -k --since "-24h" --no-pager 2>/dev/null | grep -c 'oom-kill:' || true)
  wd=$(journalctl -k --since "-24h" --no-pager 2>/dev/null | grep -ciE 'watchdog.*(panic|reset)|sbsa' || true)
  nv=$(journalctl -k --since "-24h" --no-pager 2>/dev/null | grep -c 'NV_ERR_NO_MEMORY' || true)
  fi
  # 近期性门槛：NV_ERR 是**一次性事件**（一次超额分配就刷一批），已结束的旧事件在整个 24h
  # 窗里会一直把 CRIT 叫下去（实测 298 次全部落在 16.5 小时前的一段 7 小时里，之后归零），
  # 而"永远叫"的告警等于训练人忽略告警通道。⇒ 近 1h 有才 CRIT，24h 只作记录。
  nv1h=$(journalctl -k --since "-1h" --no-pager 2>/dev/null | grep -c 'NV_ERR_NO_MEMORY' || true)
  info "近 24h: oom-kill=$oom  看门狗事件=$wd  NV_ERR_NO_MEMORY=$nv（其中近 1h=$nv1h）"
  [ "$oom" != 0 ] && [ "$oom" != NA ] && alert CRIT "近 24h 有 $oom 次内核 OOM（设备内存不进 cgroup，--memory 挡不住）"
  if [ "$wd" != 0 ] && [ "$wd" != NA ]; then
    alert CRIT "近 24h 有 $wd 次看门狗 panic/reset —— 经验上这对应"回收抖动"而非干净 OOM，**不会留 oom-kill 行**，靠 OOM 计数的守卫看不见它"
  fi
  if [ "$nv" = NA ]; then :
  elif [ "$nv1h" != 0 ]; then alert CRIT "近 1h 有 $nv1h 次 NV_ERR_NO_MEMORY（统一内存被超额分配，可能硬锁死宿主机）"
  elif [ "$nv" != 0 ]; then info "近 24h 的 $nv 次 NV_ERR_NO_MEMORY 均已超过 1h（历史事件，不升级为告警）"; fi

  hdr "GPU 时钟深诊断（PD 安全模式 burn 探针·2026-09-21）"
  # 02 实锤病：断电/OOM 后 PD 进安全模式，SM 钉 513-728MHz（零标志/warm reboot 无效）。
  # burn=生产镜像跑 6s matmul 同时采样时钟：健康负载态 2380+MHz/40W+；楔死<1200MHz/<25W。
  # GPU 被占（栈在跑）时 SKIP——burn 会与引擎争用，规则=生产在跑禁 GPU 测试。
  local _img; _img=$(grep -E '^IMAGE=' "$HOME/dsv41-flash-dgxsparks/.env.tp4" 2>/dev/null | tail -1 | cut -d= -f2 | tr -d '"')
  _img=${_img:-dsv41-sglang-optimized:0.2.7}
  if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | grep -q '[0-9]' \
       || docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^dsv41-'; then
      # 审计 P2 修：容器已起、CUDA 未初始化的窗口只看 compute-apps 会误判停态——
      # 探针（~1GiB 显存足迹）打进正在预留 GMU 池的引擎可致 OOM+反向假 CRIT。
      warn "GPU 有计算进程或 dsv41 容器在跑（栈在役/起栈中？）——burn 探针跳过（生产在跑禁 GPU 测试）；负载态判别由 check 的采样窗兜底"
    elif ! docker image inspect "$_img" >/dev/null 2>&1; then
      warn "本机缺 $_img 镜像——burn 探针跳过"
    else
      docker run --rm --gpus all --entrypoint python "$_img" -c "
import torch, time
a = torch.randn(8192, 8192, device='cuda'); b = torch.randn(8192, 8192, device='cuda')
t0 = time.time()
while time.time() - t0 < 6: c = a @ b; torch.cuda.synchronize()
" >/dev/null 2>&1 &
      _bp=$!; sleep 4
      read -r _bu _bc _bw < <(nvidia-smi --query-gpu=utilization.gpu,clocks.sm,power.draw --format=csv,noheader,nounits 2>/dev/null | tr -d ' ' | awk -F',' '{print $1, $2, $3}')
      wait $_bp 2>/dev/null
      if [ "${_bc:-0}" -ge 1500 ]; then
        info "burn 探针：util=${_bu:-?}% clock=${_bc:-?}MHz power=${_bw:-?}W —— 健康（≥1500MHz）"
      else
        alert CRIT "burn 探针：util=${_bu:-?}% clock=${_bc:-?}MHz power=${_bw:-?}W —— PD 安全模式楔死确诊（修复=关机拔墙上 AC 1-2 分钟；warm reboot 无效；runbook §7）"
      fi
    fi
  fi

  hdr "守卫脚本自检"
  while IFS='|' read -r _ r u ty rp p m req desc; do
    role_match "$r" || continue
    if [ -f "$p" ]; then
      if grep -qE '\(([^|()]+)\|\1\)' "$p" 2>/dev/null; then
        warn "$u: $p 的正则里有**完全相同的两个分支**（如 (X|X)），是改名遗留——语义上等价于单个分支，建议清理"
      fi
      bash -n "$p" 2>/dev/null && info "$u: $p 语法 OK" || alert CRIT "$u: $p 语法错误（bash -n 失败）"
    fi
  done < <(read_guards)

  hdr "探针状态文件（冷却自锁的历史雷区）"
  local d=/opt/aicad-prod/state
  if [ -d "$d" ]; then
    for f in "$d"/healthcheck-rebuild.*; do
      [ -f "$f" ] || continue
      local v; v=$(cat "$f" 2>/dev/null)
      case "$v" in
        ''|*[!0-9]*) alert CRIT "$(basename "$f") 内容非数字('$v') —— 旧版会让冷却判据退化；p3 已按 0 处理" ;;
        *) local now; now=$(date +%s)
           if [ "$v" -gt "$now" ]; then alert CRIT "$(basename "$f")=$v 是**未来时间戳**（now=$now）—— 这正是"冷却窗自锁"的成因，p3 的负值护栏会放行"
           else info "$(basename "$f")=$v （now=$now，正常范围）"; fi ;;
      esac
    done
  else warn "$d 不存在"; fi

  hdr "GB10 平台健康（社区实测的两类静默退化）"
  if command -v nvidia-smi >/dev/null 2>&1; then
    local clk
    clk=$(nvidia-smi --query-gpu=clocks.sm --format=csv,noheader,nounits 2>/dev/null | head -1)
    if [ -n "${clk:-}" ]; then
      info "SM 时钟 = ${clk} MHz"
      awk -v c="$clk" 'BEGIN{exit !(c<1000)}' && \
        alert CRIT "SM 时钟 ${clk}MHz 低于 1GHz：GB10 已知的"时钟闩锁"，nvidia-smi 看不出原因，**重启无效，只有拔掉电源适配器 30–60s 能清除**"
    fi
    local tot; tot=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)
    info "memory.total = ${tot:-N/A}（GB10 上常报 N/A，属正常，不是故障）"
  else warn "nvidia-smi 不可用"; fi

  hdr "统一内存现实核对（自解释）"
  cat <<'EOF'
  设备内存不进入任何 OS 计数器：生产 worker 持约 97 GiB 设备内存时，
  VmRSS 仅 3.7–4.0 GiB、RssShmem 仅 224 MB、cgroup memory.current 仅 16 GiB。
  因此 --memory/-swap 与任何 cgroup 上限都**无法**防止这一类的 OOM；
  唯一真正起作用的杠杆是 --gpu-memory-utilization 相对整块 121.63 GiB 池的取值。
  另：vLLM 的启动可用内存检查用的是 MemFree 而非 MemAvailable，**页缓存会被算作已用**，
  在把大表映射/缓存进 page cache 的栈上，重启时可能误报"启动内存不足"；
  对策是在重启路径上执行：sync && echo 3 > /proc/sys/vm/drop_caches（需 root）。
EOF
  return 0
}

# ==============================================================================
# 总开关：hold / release
# ------------------------------------------------------------------------------
# 停泊桩必须与单元类型匹配，这是 2026-09-11 那次事故的直接教训：
#   * oneshot  → 桩必须**立即 exit 0**。若写成 sleep 循环，单元永远停在
#                activating，定时器 NextElapse 变 infinity ⇒ 守卫永久失效。
#   * simple+Restart=always → 桩必须**驻留不退出**（sleep 循环）。若 exit 0，
#                systemd 会立刻重启它，形成重启风暴。
# ==============================================================================
STUB_ONESHOT='#!/bin/bash
# guardctl HOLD (oneshot 安全桩)：立即成功退出，不碰任何容器。
# oneshot 桩**绝不能**写成 sleep 循环——那会让单元永卡 activating、定时器
# NextElapse 变 infinity，守卫静默永久失效（2026-09-11 事故根因）。
# 恢复：bash guardctl.sh release <tag>
echo "[guardctl-hold] oneshot parked (no-op, exit 0) on '"'"'$(hostname)'"'"'"
exit 0
'
STUB_SIMPLE='#!/bin/bash
# guardctl HOLD (simple 安全桩)：驻留不退出，避免 Restart=always 重启风暴。
# 恢复：bash guardctl.sh release <tag>
export HOME=/home/liux***ya
echo "[guardctl-hold] hold active on '"'"'$(hostname)'"'"' since $(date -Is); unit parked, no container action"
while :; do sleep 3600; done
'

# ------------------------------------------------------------------------------
# 止损守护（oom_gate.sh monitor）—— systemd 之外的"裸进程"守卫
# ------------------------------------------------------------------------------
# 它是 nohup 裸进程、不是单元 ⇒ 上面那套"停泊桩"机制**看不见它**。2026-09-16 实测踩到：
# hold 打印"守卫已全部停泊（容错链为关闭状态）"，而 `oom_gate.sh monitor -f 1.5 -a` 仍在跑。
# 后果不是"守卫在役"，而是**自伤**：开窗时内存本就该低（池子空出来才好启动），
# 它会按窗口内完全合法的低内存去 `docker stop` 生产容器。
# 处置：hold 时 TERM 掉并把 **cwd + 原 argv** 记到 state/hold-<tag>.oomgate；
#       release 时按原样 nohup 起回，再用 guards.conf 的 proc 模式断言确实在役。
oomgate_state_file() { printf '%s/hold-%s.oomgate' "$STATE_DIR" "$1"; }
oomgate_pattern() {   # guards.conf 里 oom-gate-floor 的 proc 模式 = 真身 argv
  awk -F'|' '$1=="PRECOND" && $3=="oom-gate-floor" && $4=="proc" {print $5}' "$CONF" 2>/dev/null | head -1
}
cmdline_of() { tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null | sed 's/ *$//'; }

hold_oomgate() {  # <tag>
  local tag="$1" f; f=$(oomgate_state_file "$tag")
  local pids; pids=$(pgrep -f 'oom_gate[.]sh monitor' 2>/dev/null || true)
  [ -n "$pids" ] || { info "止损守护：本机无 oom_gate monitor 在役（无需处置）"; return 0; }
  : > "$f"
  local p line cwd n=0
  for p in $pids; do
    line=$(cmdline_of "$p")
    # 排除 ssh/nohup 留下的 `bash -c ...` 包装壳：它只是父壳，重挂时不能照抄，
    # 否则 release 会起出两份 monitor（两套 -a 同时 docker stop）。
    case "$line" in *" -c "*) kill -TERM "$p" 2>/dev/null || true; continue ;; esac
    cwd=$(readlink "/proc/$p/cwd" 2>/dev/null || echo "$HOME")
    printf '%s\t%s\n' "$cwd" "$line" >> "$f"
    kill -TERM "$p" 2>/dev/null || true
    n=$((n+1))
  done
  sleep 2
  local left; left=$(pgrep -f 'oom_gate[.]sh monitor' 2>/dev/null | wc -l)
  if [ "$left" -gt 0 ]; then
    alert CRIT "止损守护仍有 $left 个进程未停（TERM 被忽略？）—— 开窗前必须人工确认"; return 1
  fi
  info "止损守护已停泊 $n 个（argv 记入 $f），release 时按原样重挂"
}

release_oomgate() {  # <tag>
  local tag="$1" f; f=$(oomgate_state_file "$tag")
  [ -s "$f" ] || { rm -f "$f"; return 0; }
  local cwd line n=0
  while IFS=$'\t' read -r cwd line; do
    [ -n "$line" ] || continue
    info "重挂止损守护：cd $cwd && nohup $line"
    ( cd "$cwd" 2>/dev/null && nohup $line >>"/tmp/oom-gate-monitor-$(hostname).log" 2>&1 & )
    n=$((n+1))
  done < "$f"
  rm -f "$f"
  sleep 3
  local pat; pat=$(oomgate_pattern)
  if [ -n "$pat" ]; then
    local cnt; cnt=$(pgrep -f "$pat" 2>/dev/null | wc -l)
    if [ "$cnt" -gt 0 ]; then ok "止损守护已重挂 $n 个（模式 '$pat' 命中 $cnt）"
    else alert CRIT "止损守护重挂失败（模式 '$pat' 零命中）⇒ 本次收工**没有兜底**，立即人工拉起"; return 1; fi
  else
    warn "guards.conf 里没有 oom-gate-floor 的 proc 模式，无法断言守护是否在役"
  fi
}

cmd_hold() {
  local tag="${1:-}"; [ -n "$tag" ] || { echo "用法: guardctl.sh hold <tag>，例如 hold 20260912T0300Z-v41" >&2; return 2; }
  hdr "停泊全部守卫  tag=$tag  host=$(hostname) role=$ROLE"
  local fail=0
  while IFS='|' read -r _ r u ty rp p m req desc; do
    role_match "$r" || continue
    [ -f "$p" ] || { info "$u: 无脚本，跳过"; continue; }
    if [ -f "$p.$tag" ]; then warn "$u: 已存在备份 $p.$tag，跳过（防覆盖上一次的原始备份）"; continue; fi
    cp -p "$p" "$p.$tag" || { alert CRIT "$u: 备份失败"; fail=1; continue; }
    local tmp; tmp=$(mktemp "$p.hold.XXXXXX") || { fail=1; continue; }
    if [ "$ty" = oneshot ]; then printf '%s' "$STUB_ONESHOT" > "$tmp"; else printf '%s' "$STUB_SIMPLE" > "$tmp"; fi
    chmod --reference="$p" "$tmp" 2>/dev/null || chmod 755 "$tmp"
    mv -f "$tmp" "$p" || { alert CRIT "$u: 替换失败"; fail=1; continue; }
    info "$u 已停泊（$ty 专用桩）；备份 $p.$tag"
  done < <(read_guards)
  # 立刻让 systemd 采用停泊桩：kill MainPID。oneshot 也 kill —— 否则正在跑的真实
  # 探针可能在窗口内 docker rm -f 掉测试容器。
  while IFS='|' read -r _ r u ty rp p m req desc; do
    role_match "$r" || continue
    local pid; pid=$(u_prop "$u" MainPID)
    if [ -n "${pid:-}" ] && [ "$pid" != "0" ]; then
      info "重启 $u 以采用停泊桩 (MainPID=$pid)"
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done < <(read_guards)
  sleep 4
  # 审计 P1 修（诚实化）：在册 GUARD 行 path 多为 "-"（桩替换循环整体空转），
  # 而 kill MainPID 对 systemd 托管 Restart=always 的单元只是弹指——10s 后被
  # 原样拉回（2026-09-16 修过的「hold 假话」在 09-18 单元化后回归）。
  # 停泊的判据改为「复查仍在停泊态」，不再以「我们做了动作」作数：
  # 桩在位 或 单元已 inactive/failed 视为停泊确认；active 且无桩=CRIT。
  while IFS='|' read -r _ r u ty rp p m req desc; do
    role_match "$r" || continue
    local _act _parked=0
    _act=$(u_state "$u")
    { [ "$p" != "-" ] && [ -f "$p" ] && is_parked "$p"; } && _parked=1
    if [ "$_act" = active ] && [ "$_parked" = 0 ]; then
      alert CRIT "$u: 停泊后复查仍 active 且无桩（Restart=always 复活？）——hold 未真正生效；人工: systemctl stop $u 或确认其在册 path"
      fail=1
    else
      info "$u 停泊确认（state=$_act$([ $_parked = 1 ] && echo "+桩在位")）"
    fi
  done < <(read_guards)
  # ★ 单元之外的裸进程守卫：不处理它，"守卫已全部停泊"就是假话（见 hold_oomgate 注释）
  hold_oomgate "$tag" || fail=1
  hdr "停泊后核对"
  cmd_status silent
  if [ "$fail" = 0 ]; then
    alert WARN "守卫已全部停泊（含止损守护，tag=$tag）；维护窗口期间容错链为**关闭**状态，收工务必 release"
    return 0
  fi
  alert CRIT "停泊过程有失败项，务必人工核对"; return 1
}

cmd_release() {
  local tag="${1:-}"; [ -n "$tag" ] || { echo "用法: guardctl.sh release <tag>（与 hold 同一 tag）" >&2; return 2; }
  hdr "恢复全部守卫  tag=$tag  host=$(hostname) role=$ROLE"
  local restored=0
  while IFS='|' read -r _ r u ty rp p m req desc; do
    role_match "$r" || continue
    if [ -f "$p.$tag" ]; then
      mv -f "$p.$tag" "$p" && { info "$u 已还原 $p (md5 $(u_md5 "$p"))"; restored=$((restored+1)); }
    else
      info "$u: 无 $p.$tag 备份（可能未 hold 过）"
    fi
  done < <(read_guards)
  # ★停泊的**自恢复链脚本**也要还原：它不在 GUARD 行里（vLLM 时代的单元已 RETIRED），
  #   所以上面那个 GUARD 循环碰不到它 —— 这正是 01 上那枚停泊桩能挂 6 天的原因：
  #   release 报"无备份（可能未 hold 过）"，而真身备份就在旁边躺着。
  while IFS='|' read -r _ r n state chain cool req desc; do
    role_match "$r" || continue
    if [ -f "$chain.$tag" ]; then
      mv -f "$chain.$tag" "$chain" && { info "自恢复链 $n 已还原 $chain (md5 $(md5sum "$chain" 2>/dev/null | cut -c1-12))"; restored=$((restored+1)); }
    elif is_parked "$chain"; then
      info "自恢复链 $n 仍是停泊桩，但找不到 $chain.$tag ⇒ 需人工还原（别留桩）"
    fi
  done < <(read_recoveries)

  # simple 单元：kill MainPID 让 systemd 重新 exec 真实脚本。
  # ⚠只重启**真的被停泊过**的单元。旧版对每一个 simple 单元都 kill —— 于是 release 会顺手
  #   重启根本没被 hold 的服务（2026-09-17 实测：concurrency-proxy-v2 = 生产 8001 网关，
  #   被无谓地 TERM 了一次，在途请求会断）。这不是"无害的额外动作"，是生产影响。
  while IFS='|' read -r _ r u ty rp p m req desc; do
    role_match "$r" || continue
    [ "$ty" = simple ] || continue
    [ -f "$p.$tag" ] || continue          # 本次 hold 动过它才谈得上"重新 exec"
    local pid; pid=$(u_prop "$u" MainPID)
    if [ -n "${pid:-}" ] && [ "$pid" != "0" ]; then
      if is_parked "$p"; then info "$u 仍是停泊桩，跳过重启（先解决还原失败）"; continue; fi
      info "重启 $u 以采用真实脚本 (MainPID=$pid)"
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done < <(read_guards)
  # ★ oneshot：**必须显式回收停泊进程**。这是 2026-09-11 事故的正解——
  #   回退脚本只重启了 simple 监视器，停泊的 oneshot 一直活着，单元永卡
  #   activating，定时器变成 infinity，P1 重建守卫静默永久失效。
  while IFS='|' read -r _ r u ty rp p m req desc; do
    role_match "$r" || continue
    [ "$ty" = oneshot ] || continue
    local st; st=$(u_state "$u")
    if [ "$st" = "activating" ]; then
      local pid; pid=$(u_prop "$u" MainPID)
      if [ -n "${pid:-}" ] && [ "$pid" != "0" ]; then
        info "回收停泊的 oneshot $u (MainPID=$pid)"
        kill -TERM "$pid" 2>/dev/null || true
        local c; for c in $(pgrep -P "$pid" 2>/dev/null); do
          kill -TERM "$c" 2>/dev/null || true   # 必须连子进程：bash 会推迟信号到前台子进程返回
        done
        sleep 3
        info "$u 现在：$(u_state "$u")/$(u_prop "$u" SubState)"
      fi
    fi
  done < <(read_guards)
  # 断言触发链真的重新武装（不要相信"脚本已还原"就等于"守卫已恢复"）
  local wedge=0
  while IFS='|' read -r _ r t dep req desc; do
    role_match "$r" || continue
    local v d; IFS='|' read -r v d <<<"$(timer_verdict "$t" "$dep")"
    if [ "$v" = OK ]; then ok "$t 已重新武装：$d"; else
      alert CRIT "$t 仍未武装：$d ⇒ 守卫依旧失效，不要就此收工"; wedge=1
    fi
  done < <(read_timers)
  [ "$restored" != 0 ] || warn "没有还原任何文件（tag 是否写错？）"
  release_oomgate "$tag" || wedge=1
  if [ "$wedge" = 0 ]; then
    alert WARN "守卫已恢复并确认重新武装 (tag=$tag)"
    return 0
  fi
  return 1
}

# ==============================================================================
cmd_watch() {
  local every="${1:-60}"
  echo "guardctl watch: 每 ${every}s 检查一次，只在状态变化时告警。Ctrl-C 退出。"
  declare -A last
  while :; do
    while IFS='|' read -r _ r u ty rp p m req desc; do
      role_match "$r" || continue
      local v d; IFS='|' read -r v d <<<"$(guard_verdict "$u" "$ty" "$rp" "$p" "$m" "$req")"
      if [ "${last[$u]:-}" != "$v" ]; then
        # HELD = 脚本是停泊桩，即**有意**的维护态。cmd_check 已按 WARN 处理且不计入 bad_n，
        # 这里必须同口径：README §8 让外部监控直接 grep CRIT，若把 HELD 也算 CRIT，则每次
        # 维护窗口都会往告警通道灌假警报——那正是 v0.4.1 修掉的"喊狼来了"。仍出声，但不占 CRIT。
        case "$v" in
          OK)   info "$u -> OK" ;;
          HELD) alert WARN "$u -> $v （$d）" ;;
          *)    alert CRIT "$u -> $v （$d）" ;;
        esac
        last[$u]="$v"
      fi
    done < <(read_guards)
    while IFS='|' read -r _ r t dep req desc; do
      role_match "$r" || continue
      local v d; IFS='|' read -r v d <<<"$(timer_verdict "$t" "$dep")"
      if [ "${last[$t]:-}" != "$v" ]; then
        [ "$v" = OK ] && info "$t -> OK" || alert CRIT "$t -> $v （$d）"
        last[$t]="$v"
      fi
    done < <(read_timers)
    # ★RECOVERY 必须纳入观察面：链被停泊/冷却窗被写成未来时间戳这两件事**没有任何日志**，
    #   而 watch 是常驻观察器——旧版只迭代 GUARD+TIMER，于是这两类无声失效要等人手跑 check
    #   才被发现（2026-09-17 交叉审核 I1）。
    while IFS='|' read -r _ r n state chain cool req desc; do
      local v d; IFS='|' read -r v d <<<"$(recovery_verdict "$n" "$state" "$chain" "$cool")"
      local k="rec:$n"
      if [ "${last[$k]:-}" != "$v" ]; then
        case "$v" in
          OK)   info "$k -> OK" ;;
          SKIP) info "$k -> SKIP（$d）" ;;
          HELD) alert WARN "$k -> $v （$d）" ;;
          *)    alert CRIT "$k -> $v （$d）" ;;
        esac
        last[$k]="$v"
      fi
    done < <(read_recoveries)
    sleep "$every"
  done
}

# ==============================================================================
cmd_snapshot() {
  local out="$GUARD_DIR/BASELINE.md"
  {
    echo "# 守卫基线快照（guardctl snapshot）"
    echo
    echo "主机: $(hostname)   角色: $ROLE   时间: $(date -Is)"
    echo
    echo "| 单元 | Type | Restart | ExecStart | md5(12) | 状态 |"
    echo "|---|---|---|---|---|---|"
    while IFS='|' read -r _ r u ty rp p m req desc; do
      role_match "$r" || continue
      local v d; IFS='|' read -r v d <<<"$(guard_verdict "$u" "$ty" "$rp" "$p" "$m" "$req")"
      echo "| $u | $(u_prop "$u" Type) | $(u_prop "$u" Restart) | $p | $(u_md5 "$p") | $v |"
    done < <(read_guards)
    while IFS='|' read -r _ r t dep req desc; do
      role_match "$r" || continue
      echo "| $t (timer) | timer | - | $dep | - | $(timer_verdict "$t" "$dep" | cut -d'|' -f1) |"
    done < <(read_timers)
    echo
    echo "> 更新本文件即等于承认"当前状态是新的正确基线"。"
    echo "> 若脚本被合法修改，请同时更新 guards.conf 里的期望 md5，否则 check 会持续报 DRIFT。"
  } > "$out"
  echo "已写入 $out"
  grep -E '^\| vllm|^\| concurrency' "$out" | sed 's/^/  /'
}

# ==============================================================================
case "${1:-status}" in
  status)  cmd_status ;;
  check)   cmd_check ;;
  explain) shift; cmd_explain "${1:-}" ;;
  preflight) cmd_preflight ;;
  doctor)  cmd_doctor ;;
  hold)    shift; cmd_hold "${1:-}" ;;
  release) shift; cmd_release "${1:-}" ;;
  watch)   shift; cmd_watch "${1:-60}" ;;
  snapshot) cmd_snapshot ;;
  -h|--help|help)
    sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *) echo "未知子命令: $1（用 help）" >&2; exit 2 ;;
esac
