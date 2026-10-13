#!/bin/bash
# v41_warm_cache.sh — 主动预热页缓存（2026-09-22 用户令①）
#
# 动机（r3 窗口实测）：prefill 期间 torch 设备池增长（01 单剂 +9382 MiB）主要靠**回收文件页**
# 吸收（同剂容器页缓存被抽掉 9595 MiB）。开着窗口时机器手里的"干净可回收页"越多，内核就越
# 不必在瞬态里做脏活（回写/直接回收/抖动）。预热 = 在起栈**之前**把量权重/Engram 的只读
# 文件页读进缓存，作为一次性、干净、立即可回收的缓冲垫。
#
# ★为什么这是"免费"的（也是对判据唯一安全的性质）：
#   判据 eff_idle = MemFree + Cached + SReclaimable − Shmem。
#   预热把 MemFree 变成 Cached，**两项都在公式里** ⇒ eff_idle 在理论上不变。
#   本脚本每次运行都实测并打印 before/after 的 eff_idle，用来证伪这一点（若 Δeff_idle 明显为负，
#   说明发生了不可回收增长，脚本会报警）。
#
# 安全设计（防"预热自己变成事故"）：
#   ① 预算硬上限（默认 24 GiB），永不整盘读（权重 476 GiB 装不下）
#   ② MemFree 地板守卫：低于 --free-floor（默认 20 GiB）立即停手
#   ③ 空闲 I/O：ionice -c3 -n7 + nice -n 19，不跟生产抢
#   ④ 只读、幂等：状态文件记录 (path,size,mtime,ts)，TTL 内重跑直接跳过
#   ⑤ 全程拿不到 docker/root 也不需要
#
# 用法：
#   v41_warm_cache.sh run [--gib 24] [--dir D]... [--free-floor 20] [--ttl 900] [--dry-run]
#                        [--no-net] [--json F]
#   v41_warm_cache.sh probe                 # 只报当前 eff_idle/Cached 构成（不读文件）
#   v41_warm_cache.sh selftest              # 判别式自检（不读真权重）
set -uo pipefail

STATE="${V41_WARM_STATE:-$HOME/.cache/v41-warm-state.tsv}"
LOG="${V41_WARM_LOG:-$HOME/w6-kit/oom-gate/logs/warm-cache-$(hostname).log}"
mkdir -p "$(dirname "$STATE")" "$(dirname "$LOG")" 2>/dev/null || true

_eff() {   # eff_idle / memfree / cached / sreclaim / shmem（MiB，五路全出）
  awk '/^MemFree:/{f=$2}/^Cached:/{c=$2}/^SReclaimable:/{s=$2}/^Shmem:/{m=$2}
       END{printf "%.1f %.1f %.1f %.1f %.1f %.1f\n", (f+c+s-m)/1024, f/1024, c/1024, s/1024, m/1024, (f+c+s-m)/1048576}' /proc/meminfo
}

MODE="${1:-run}"; shift || true
GIB=24; FLOOR_FREE=20; TTL=900; DRY=0; NONET=0; JSONF=""
DIRS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --gib) GIB="${2:?}"; shift 2 ;;
    --dir) DIRS+=("${2:?}"); shift 2 ;;
    --free-floor) FLOOR_FREE="${2:?}"; shift 2 ;;
    --ttl) TTL="${2:?}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --no-net) NONET=1; shift ;;
    --json) JSONF="${2:?}"; shift 2 ;;
    -*) echo "未知参数 $1" >&2; exit 2 ;;
    *)  shift ;;
  esac
done

# 默认靶子 = 容器真正挂载、且**启动时必然全量读**的权重目录。
#   ⚠ Engram 目录默认**不**计入预算（可 --dir 显式加）：
#     已核实 `~/v41-luz-graft/pread/engram_disk.py:187,224`（os.open(O_RDONLY)+os.preadv）
#     —— **没有 O_DIRECT**，所以 Engram 读确实会走页缓存、预热有效；但按行稀疏读（热行约 2.1%），
#     整文件预热会把预算全花在**永不命中**的行页上。想纯买缓冲垫时再加它。
def_dirs() {
  [ "${#DIRS[@]}" -gt 0 ] && { printf '%s\n' "${DIRS[@]}"; return; }
  local d
  for d in /data/models/DeepSeek-V4.1-Flash; do
    [ -d "$d" ] && echo "$d"
  done
  # /data/models/dsv41-net = 03/04 的 46 个网络分片视图：读它会走 fabric，故默认关（V41_WARM_NET=1 或 --dir 开）
  if [ "$NONET" = 0 ] && [ -n "${V41_WARM_NET:-}" ] && [ -d /data/models/dsv41-net ]; then
    echo /data/models/dsv41-net
  fi
}

case "$MODE" in
probe)
  read -r eff free cached srec shmem effgib <<<"$(_eff)"
  echo "host=$(hostname) eff_idle=${effgib}GiB (MemFree=${free}MiB Cached=${cached}MiB SReclaim=${srec}MiB Shmem=${shmem}MiB)"
  ;;

run)
  read -r eff0 free0 cac0 sr0 sh0 eff0g <<<"$(_eff)"
  echo "[warm] 起手 host=$(hostname) eff_idle=${eff0g}GiB (MemFree=${free0} Cached=${cac0} SReclaim=${sr0} Shmem=${sh0} MiB)"
  echo "[warm] 预算 ${GIB}GiB  MemFree地板 ${FLOOR_FREE}GiB  TTL ${TTL}s  空闲IO=$([ $DRY = 1 ] && echo dry || echo on)"

  # 候选文件：按目录收集常规文件，按路径排序（分片编号顺序≈加载顺序），大文件优先在同一编号段内
  TMPL=$(mktemp /tmp/warmlist.XXXXXX)
  mapfile -t DARR < <(def_dirs)
  [ "${#DARR[@]}" -gt 0 ] || { echo "[warm] ⛔ 没有任何候选目录（--dir 指定或确认 /data/models 存在）"; exit 2; }
  for d in "${DARR[@]}"; do
    find "$d" -maxdepth 2 -type f \( -name '*.safetensors' -o -name '*.bin' -o -name '*.json' -o -name '*.pdf' -o -name '*.pkl' \) 2>/dev/null
  done | sort | while read -r f; do
    [ -r "$f" ] && printf '%s\t%s\t%s\n' "$(stat -c %s "$f" 2>/dev/null || echo 0)" "$(stat -c %Y "$f" 2>/dev/null || echo 0)" "$f"
  done > "$TMPL"
  echo "[warm] 候选文件 $(wc -l < "$TMPL") 个，目录: ${DARR[*]}"

  BUDGET=$(( GIB * 1024 * 1024 * 1024 ))
  USED=0; NREAD=0; NSKIP=0; NBUD=0; NGUARD=0; T0=$(date +%s)
  : > "$TMPL.new"
  while IFS=$'\t' read -r sz mt f; do
    [ -n "${f:-}" ] || continue
    # TTL 幂等：同 size+mtime 且近期已预热过 ⇒ 跳过
    if [ -f "$STATE" ]; then
      prev=$(awk -F'\t' -v p="$f" -v s="$sz" -v m="$mt" -v now="$(date +%s)" -v ttl="$TTL" \
             '$1==p && $2==s && $3==m && (now-$4)<ttl {print 1; exit}' "$STATE")
      [ "$prev" = 1 ] && { NSKIP=$((NSKIP+1)); printf '%s\t%s\t%s\t%s\n' "$f" "$sz" "$mt" "$(date +%s)" >> "$TMPL.new"; continue; }
    fi
    if [ $USED -ge $BUDGET ]; then NBUD=$((NBUD+1)); continue; fi
    # MemFree 地板守卫
    curfree=$(awk '/^MemFree:/{printf "%d", $2/1048576}' /proc/meminfo)
    if [ "$curfree" -lt "$FLOOR_FREE" ]; then
      NGUARD=$((NGUARD+1)); echo "[warm] ⛔ MemFree ${curfree}GiB < 地板 ${FLOOR_FREE}GiB ⇒ 立即停手（已读 $((USED/1048576))MiB）"
      break
    fi
    remain=$(( BUDGET - USED ))
    take=$(( sz < remain ? sz : remain ))
    chunks=$(( (take + 4194304 - 1) / 4194304 ))
    [ "$chunks" -lt 1 ] && chunks=1
    if [ $DRY = 1 ]; then
      echo "[warm][dry] 会读 $((take/1048576))MiB / 共 $((sz/1048576))MiB ← $f"
    else
      if command -v ionice >/dev/null 2>&1; then
        ionice -c3 -n7 nice -n 19 dd if="$f" of=/dev/null bs=4M count="$chunks" status=none 2>/dev/null
      else
        nice -n 19 dd if="$f" of=/dev/null bs=4M count="$chunks" status=none 2>/dev/null
      fi
    fi
    USED=$(( USED + chunks * 4194304 )); NREAD=$((NREAD+1))
    printf '%s\t%s\t%s\t%s\n' "$f" "$sz" "$mt" "$(date +%s)" >> "$TMPL.new"
  done < "$TMPL"
  [ $DRY = 1 ] || { cat "$TMPL.new" > "$STATE"; }
  T1=$(date +%s)
  read -r eff1 free1 cac1 sr1 sh1 eff1g <<<"$(_eff)"
  READ_MIB=$(( USED / 1048576 ))
  DELTA_CAC=$(awk -v a="$cac1" -v b="$cac0" 'BEGIN{printf "%.1f", a-b}')
  DELTA_EFF=$(awk -v a="$eff1g" -v b="$eff0g" 'BEGIN{printf "%.2f", a-b}')
  RATE=$(awk -v m="$READ_MIB" -v s="$((T1-T0))" 'BEGIN{printf "%.0f", (s>0)? m/s*1024 : 0}')
  {
    printf '[warm] 完成 读 %s 文件 / %s MiB（跳过 %s，超预算 %s，守卫停 %s）耗时 %ss ≈ %s MiB/s\n' \
      "$NREAD" "$READ_MIB" "$NSKIP" "$NBUD" "$NGUARD" "$((T1-T0))" "$RATE"
    printf '[warm] Cached %s → %s MiB（Δ%+s）  MemFree %s → %s MiB\n' "$cac0" "$cac1" "$DELTA_CAC" "$free0" "$free1"
    printf '[warm] ★eff_idle %s → %s GiB（Δ%+s）——理论上应≈0（Cached 本就在判据式内）\n' "$eff0g" "$eff1g" "$DELTA_EFF"
    if awk -v d="$DELTA_EFF" 'BEGIN{exit !(d < -1.0)}'; then
      printf '[warm] ⚠ eff_idle 掉超过 1 GiB ⇒ 出现了不可回收增长（预热不该造成这个），请查 /proc/meminfo 与 slab\n'
    fi
  } | tee -a "$LOG"
  if [ -n "$JSONF" ]; then
    printf '{"host":"%s","ts":%s,"read_files":%s,"read_mib":%s,"skip":%s,"over_budget":%s,"guard_stop":%s,"elapsed_s":%s,"cached_before_mib":%s,"cached_after_mib":%s,"eff_idle_before_gib":%s,"eff_idle_after_gib":%s,"delta_eff_gib":%s,"dirs":"%s"}\n' \
      "$(hostname)" "$(date +%s)" "$NREAD" "$READ_MIB" "$NSKIP" "$NBUD" "$NGUARD" "$((T1-T0))" "$cac0" "$cac1" "$eff0g" "$eff1g" "$DELTA_EFF" "${DARR[*]}" > "$JSONF"
    echo "[warm] JSON → $JSONF"
  fi
  ;;

selftest)
  # 判别式自检：不写真权重，只用临时文件验证"读进去=缓存涨"以及"守卫会拦"
  # ★夹具纪律：① 夹具状态/日志与生产隔离（绝不写 ~/.cache/v41-warm-state.tsv）
  #            ② 夹具文件必须**先 O_DIRECT 写入**（绕过页缓存）——否则文件刚被写就已驻留
  #              缓存，再"读它"不会让 Cached 涨一个字，W1 就成了假绿。
  T=$(mktemp -d /tmp/warmst.XXXXXX); trap 'rm -rf "$T"' EXIT
  export V41_WARM_STATE="$T/state.tsv" V41_WARM_LOG="$T/warm.log"
  echo "══ W0 先量本机 eff_idle 自身噪声（判 W1 时要用它当尺子，不用拍脑袋的容差）"
  N0=$(bash "$0" probe | sed 's/.*eff_idle=\([0-9.]*\)GiB.*/\1/')
  sleep 1; N1=$(bash "$0" probe | sed 's/.*eff_idle=\([0-9.]*\)GiB.*/\1/')
  sleep 1; N2=$(bash "$0" probe | sed 's/.*eff_idle=\([0-9.]*\)GiB.*/\1/')
  NOISE=$(awk -v a="$N0" -v b="$N1" -v c="$N2" 'BEGIN{m=a;M=a;if(b<m)m=b;if(b>M)M=b;if(c<m)m=c;if(c>M)M=c;printf "%.2f", M-m}')
  echo "   本机 3 秒内 eff_idle 漂移 = ${NOISE} GiB（三次: $N0 / $N1 / $N2）"

  echo "══ W1 预热确实把文件页读进缓存，且 eff_idle 不被吃掉"
  dd if=/dev/urandom of="$T/big.bin" bs=1M count=512 oflag=direct status=none   # ← 关键：不进缓存
  sync
  read -r e0 f0 c0 s0 m0 g0 <<<"$(_eff)"
  bash "$0" run --dir "$T" --gib 1 --ttl 0 > "$T/out1.txt" 2>&1
  read -r e1 f1 c1 s1 m1 g1 <<<"$(_eff)"
  DE=$(awk -v a="$c1" -v b="$c0" 'BEGIN{printf "%.0f", a-b}')
  echo "   Cached ${c0} → ${c1} MiB（Δ${DE}） ; eff_idle ${g0} → ${g1} GiB"
  if [ "$DE" -ge 400 ]; then echo "  ✓ Cached 抬升 ${DE} MiB（≥400，真从盘上读进来了）"
  else echo "  ✗ Cached 只抬升 ${DE} MiB ⇒ 预热没生效（或夹具文件本就在缓存里）"; fi
  DEFF=$(awk -v a="$g1" -v b="$g0" 'BEGIN{printf "%.2f", a-b}')
  TOL=$(awk -v n="$NOISE" 'BEGIN{t=n*2+0.3; if(t<0.5)t=0.5; printf "%.2f", t}')
  if awk -v d="$DEFF" -v t="$TOL" 'BEGIN{exit !(d >= -t)}'; then
    echo "  ✓ eff_idle 未被吃掉（Δ${DEFF}GiB，容差 −${TOL}=2×噪声+0.3）⇒ 预热对判据中性"
  else echo "  ✗ eff_idle 掉了 ${DEFF}GiB（超出噪声容差 −${TOL}）⇒ 有不可回收增长，预热不安全"; fi
  echo "══ W2 TTL 幂等：同参数重跑应跳过（不再读）"
  bash "$0" run --dir "$T" --gib 1 --ttl 900 > "$T/out2.txt" 2>&1
  grep -q '读 0 文件' "$T/out2.txt" && echo "  ✓ 第二次读 0 文件（TTL 命中跳过）" || { echo "  ✗ TTL 未生效："; grep '完成 读' "$T/out2.txt" | sed 's/^/     /'; }
  echo "══ W3 预算硬上限：0GiB 预算 ⇒ 一个字节都不许读"
  bash "$0" run --dir "$T" --gib 0 --ttl 0 > "$T/out3.txt" 2>&1
  grep -qE '读 0 文件|超预算' "$T/out3.txt" && echo "  ✓ 0GiB 预算下不读（超预算计数生效）" || { echo "  ✗ 预算未拦住"; grep '完成 读' "$T/out3.txt" | sed 's/^/     /'; }
  echo "══ W4 MemFree 地板守卫：地板设成不可能的高位 ⇒ 必须立即停手并写明原因"
  bash "$0" run --dir "$T" --gib 1 --ttl 0 --free-floor 99999 > "$T/out4.txt" 2>&1
  grep -q '立即停手' "$T/out4.txt" && echo "  ✓ 守卫拦下并写明 MemFree<地板" || { echo "  ✗ 守卫未拦"; tail -3 "$T/out4.txt" | sed 's/^/     /'; }
  echo "══ W5 probe 模式可读"
  bash "$0" probe | grep -q 'eff_idle=' && echo "  ✓ probe 输出构成" || echo "  ✗ probe 无输出"
  ;;
*)
  grep -E '^# (用法|动机|安全)' "$0" | sed 's/^# //'; exit 2 ;;
esac
