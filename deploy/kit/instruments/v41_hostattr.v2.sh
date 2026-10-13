#!/usr/bin/env bash
# v41_hostattr.v2.sh —— 宿主侧归因采样器 v2（2026-09-22；**不覆盖 v1**，由窗口切换）
#
# v1 的三个缺口（都在 9/22 A1 窗口自暴露）：
#   ① **缺 swap 口径**：02 在 262144 剂量期冻结 19 分钟后自愈（内核只见 `task blocked >122s`×8 +
#      看门狗 SIGKILL 连锁、无 NVRM 风暴），而四机 swap 同款（16G /swap.img、swappiness=20）
#      ⇒ 抖动/回收是候选机制，**当时的量具完全看不见**。v2 加 `swap_used` + `/proc/vmstat`
#      的 pswpin/pswpout 累计（差分即换页速率，抖动的直接证据）。
#   ② **沉默即 0**：`dsv_*` 在 worker 上恒为 0（scope 未命中与"真的 0"无法区分）。v2 未命中时
#      落 `-1` 哨兵，分析器据此打 n/a，而不是给出一个假的 0（本项目反复踩的病类）。
#   ③ **列不自描述**：字段数一变，分析器按"字段数不符"整行丢弃且只报一个计数。v2 在文件头写
#      `#FIELDS ...`，分析器按名字取列 ⇒ 以后加列不再需要两边同时改。
#
# 接口与 v1 完全同形（窗口脚本无需改动）：
#   v41_hostattr.v2.sh loop <out.tsv> <iv秒> [max秒] | start <host> <out.tsv> <iv> [max]
#   v41_hostattr.v2.sh mark <out.tsv> <tag> | stop <out.tsv> | fetch <host> <out.tsv>
# 哨兵：-1 = 该项本机不可得（≠ 0）。单位统一 MiB（disk_* 为累计扇区数，pswp* 为累计页数）。
set -uo pipefail
CG=/sys/fs/cgroup
self=$(basename "$0")

# 列序的**唯一真源**：改这里就同时改了 #FIELDS 与输出
FIELDS="ms eff_idle memfree cached sreclaim shmem slab sunreclaim dock_file dock_anon dock_kernel user_file user_anon user_kernel dsv_file dsv_anon dsv_kernel disk_rd disk_wr swap_used pswpin pswpout"

now_ms() { date +%s%3N; }
is_local() { [ "$1" = "$(hostname)" ] || [ "$1" = localhost ] || [ "$1" = "$(hostname -s)" ] || [ "$1" = "$(hostname -f)" ]; }
saddr() { getent hosts "$1" 2>/dev/null | awk 'NR==1{print $1}'; }
ssh_to() { local h="$1"; shift; ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o "HostName=$(saddr "$h")" "$h" "$@"; }

dsv_scope() {
  # ★v1 的死法（2026-09-22 定性）：`id=$(docker inspect -f '{{.Id}}' dsv41-head 2>/dev/null || docker inspect -f '{{.Id}}' dsv41-worker 2>/dev/null)`
  # —— 容器不存在时 docker **先往 stdout 打一个空行再报错退出**，`||` 的兜底输出被拼在空行之后
  # ⇒ id = "\n<64 位 id>"（长度 65），路径里夹了换行 ⇒ [ -f ] 不中 ⇒ dsv_* 恒 0。
  # 01 正常只是因为 head 容器真存在、走不到兜底；worker 上从此一直静默报 0。
  # 修法：先**无格式探测**哪个容器存在（失败干净），再读 id 并剥所有空白。
  local c="" n id p
  for n in dsv41-head dsv41-worker; do
    if docker inspect "$n" >/dev/null 2>&1; then c="$n"; break; fi
  done
  [ -n "$c" ] || return 0
  id=$(docker inspect -f '{{.Id}}' "$c" 2>/dev/null | tr -d '[:space:]')
  [ -n "$id" ] || return 0
  for p in "$CG/system.slice/docker-$id.scope/memory.stat" "$CG/docker/$id/memory.stat"; do
    [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  done
}

sample_line() {   # $1 = epoch_ms
  local ms="$1" m="0 0 0 0 0 0 0" scopes dsv df da dk uf ua uk dsvf dsa dsk dr dw sw pi po
  m=$(awk '
    /^MemFree:/{f=$2} /^Cached:/{c=$2} /^SReclaimable:/{s=$2} /^Shmem:/{m=$2}
    /^Slab:/{sl=$2} /^SUnreclaim:/{su=$2}
    /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2}
    END{printf "%d %d %d %d %d %d %d|%d", (f+c+s-m)/1024, f/1024, c/1024, s/1024, m/1024, sl/1024, su/1024, (st-sf)/1024}' /proc/meminfo)
  sw="${m#*|}"; m="${m%|*}"
  read -r pi po < <(awk '/^pswpin /{i=$2} /^pswpout /{o=$2} END{printf "%d %d", i, o}' /proc/vmstat 2>/dev/null)
  dsv=$(dsv_scope)
  scopes=$(ls -d "$CG"/system.slice/docker-*.scope/memory.stat "$CG"/user.slice/memory.stat \
              "$CG"/docker/*/memory.stat 2>/dev/null | tr '\n' ' ')
  read -r df da dk uf ua uk < <(awk '
    FNR==1 { g = (FILENAME ~ /docker-/) ? "dock" : "user" }
    /^(file|anon|kernel) /{ split($0,a," "); v[g"/"a[1]] += a[2]/1048576 }
    END{ printf "%d %d %d %d %d %d", v["dock/file"], v["dock/anon"], v["dock/kernel"],
          v["user/file"], v["user/anon"], v["user/kernel"] }' $scopes 2>/dev/null)
  read -r dr dw < <(awk '$3 !~ /^(loop|ram|dm-|sr)/ {r+=$6; w+=$10} END{printf "%d %d", r, w}' /proc/diskstats)
  if [ -n "$dsv" ]; then
    read -r dsvf dsa dsk < <(awk '/^(file|anon|kernel) /{split($0,a," "); v[a[1]]=a[2]/1048576}
        END{printf "%d %d %d", v["file"], v["anon"], v["kernel"]}' "$dsv" 2>/dev/null)
  else
    dsvf=-1; dsa=-1; dsk=-1     # 哨兵：scope 未命中 ≠ 0（v1 的沉默即 0 病）
  fi
  printf 'S %s %s %s\n' \
         "$ms" "$m" "${df:-0} ${da:-0} ${dk:-0} ${uf:-0} ${ua:-0} ${uk:-0} ${dsvf:-0} ${dsa:-0} ${dsk:-0} ${dr:-0} ${dw:-0} ${sw:-0} ${pi:-0} ${po:-0}"
}

case "${1:-}" in
loop)
  out="${2:?out 文件}"; iv="${3:-0.5}"; max="${4:-7200}"
  stopf="$out.stop"; rm -f "$stopf"
  { printf '#HOST %s %s\n' "$(hostname)" "$(date +%s)"
    printf '#FIELDS %s\n' "$FIELDS"; } >>"$out"
  t0=$(date +%s); n=0
  while :; do
    [ -f "$stopf" ] && break
    [ $(( $(date +%s) - t0 )) -gt "$max" ] && break
    sample_line "$(now_ms)" >>"$out"
    n=$((n+1)); sleep "$iv"
  done
  printf '#END %s %s\n' "$(date +%s)" "$n" >>"$out"; rm -f "$stopf";;
mark) out="${2:?out}"; printf 'M %s %s\n' "$(now_ms)" "${3:?tag}" >>"$out";;
stop) : > "${2:?out}.stop";;
fetch)
  h="${2:?host}"; out="${3:?out}"
  if is_local "$h"; then cat "$out" 2>/dev/null; else ssh_to "$h" "cat '$out' 2>/dev/null"; fi;;
start)
  h="${2:?host}"; out="${3:?out}"; iv="${4:-0.5}"; max="${5:-7200}"
  rm -f "$out"; : > "$out"
  if is_local "$h"; then
    nohup bash "$0" loop "$out" "$iv" "$max" >/dev/null 2>&1 &
  else
    ssh_to "$h" "nohup bash '$HOME/w6-kit/$self' loop '$out' '$iv' '$max' >/dev/null 2>&1 &" || exit 1
    sleep 2
  fi
  sleep 2
  n=$( { is_local "$h" && cat "$out" || ssh_to "$h" "cat '$out'"; } 2>/dev/null | grep -c '^S ' )
  printf '%s\n' "${n:-0}";;
*) sed -n '2,25p' "$0"; exit 2;;
esac
