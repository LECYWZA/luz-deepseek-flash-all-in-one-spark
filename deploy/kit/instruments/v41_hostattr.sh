#!/usr/bin/env bash
# v41_hostattr.sh —— 宿主侧归因采样器（2026-09-22 增补；补 memwatch 缺的那一半）
#
# 为什么需要它：r3 窗口归因卡在「容器外残差 2.4–2.9 GiB」——memwatch 只给宿主总口径
# （eff_idle/MemFree/Cached/SReclaimable/Shmem），探针只给容器内口径（cgroup/RSS/torch），
# 两者之差没人认领。本采样器补上中间层：**所有 docker scope 的合计 + dsv41 单容器 + user.slice
# 的 file/anon/kernel/slab 分项**，外加 slab 与磁盘读写累计 —— 于是"谁吃掉了页缓存/内存"
# 可以逐 cgroup 点名，且能看清"权重流读取回填页缓存"的速率。
#
# 接口与 v41_memwatch.sh 完全同形（便于窗口脚本一处接线）：
#   v41_hostattr.sh loop <out.tsv> <iv秒> [max秒]     # 本机采样循环（写 S 行）
#   v41_hostattr.sh start <host> <out.tsv> <iv> [max]
#   v41_hostattr.sh mark <out.tsv> <tag> | stop <out.tsv> | fetch <host> <out.tsv>
#
# 输出列（空格分隔，**统一 MiB**——v1 曾把 cgroup 的字节除 1024 得 KiB 而宿主列是 MiB，混用即量具病；M 行是标记，分析器按 #HOST/#END 分机）：
#   S <epoch_ms> eff_idle memfree cached sreclaim shmem slab sunreclaim   （宿主总口径，7 项）
#     dock_file dock_anon dock_kernel      # 全部 docker-*.scope 合计
#     user_file user_anon user_kernel      # user.slice（含本机会话/工具）
#     dsv_file  dsv_anon  dsv_kernel       # dsv41 容器那一个 scope（需运行中才有）
#     disk_rd_sect disk_wr_sect            # 真实块设备累计扇区（差分=读写速率）
set -uo pipefail
CG=/sys/fs/cgroup
self=$(basename "$0")

now_ms() { date +%s%3N; }
is_local() { [ "$1" = "$(hostname)" ] || [ "$1" = localhost ] || [ "$1" = "$(hostname -s)" ] || [ "$1" = "$(hostname -f)" ]; }
saddr() { getent hosts "$1" 2>/dev/null | awk 'NR==1{print $1}'; }
ssh_to() { local h="$1"; shift; ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o "HostName=$(saddr "$h")" "$h" "$@"; }

dsv_scope() {
  # dsv41 容器的 cgroup 路径（systemd 驱动=.scope / cgroupfs=/$CGID）；两次尝试都不中则空
  local id p
  id=$(docker inspect -f '{{.Id}}' dsv41-head 2>/dev/null || docker inspect -f '{{.Id}}' dsv41-worker 2>/dev/null)
  [ -n "$id" ] || return 0
  for p in "$CG/system.slice/docker-$id.scope/memory.stat" "$CG/docker/$id/memory.stat"; do
    [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  done
}

sample_line() {   # $1 = epoch_ms —— ★一行 20 字段，列序见文件头
  local ms="$1" m="0 0 0 0 0 0 0" scopes dsv df da dk uf ua uk dsvf dsa dsk dr dw
  m=$(awk '
    /^MemFree:/{f=$2} /^Cached:/{c=$2} /^SReclaimable:/{s=$2} /^Shmem:/{m=$2}
    /^Slab:/{sl=$2} /^SUnreclaim:/{su=$2}
    END{printf "%d %d %d %d %d %d %d", (f+c+s-m)/1024, f/1024, c/1024, s/1024, m/1024, sl/1024, su/1024}' /proc/meminfo)
  dsv=$(dsv_scope)
  scopes=$(ls -d "$CG"/system.slice/docker-*.scope/memory.stat "$CG"/user.slice/memory.stat \
              "$CG"/docker/*/memory.stat 2>/dev/null | tr '\n' ' ')
  # 一次 awk 吃所有 memory.stat：按 FILENAME 分组求和（每 scope 一个进程会太贵）
  read -r df da dk uf ua uk < <(awk '
    FNR==1 { g = (FILENAME ~ /docker-/) ? "dock" : "user" }
    /^(file|anon|kernel) /{ split($0,a," "); v[g"/"a[1]] += a[2]/1048576 }
    END{ printf "%d %d %d %d %d %d", v["dock/file"], v["dock/anon"], v["dock/kernel"],
          v["user/file"], v["user/anon"], v["user/kernel"] }' $scopes 2>/dev/null)
  # 磁盘与 dsv41 单独取（不混进上面那次 awk，避免串组）
  read -r dr dw < <(awk '$3 !~ /^(loop|ram|dm-|sr)/ {r+=$6; w+=$10} END{printf "%d %d", r, w}' /proc/diskstats)
  read -r dsvf dsa dsk < <(awk '/^(file|anon|kernel) /{split($0,a," "); v[a[1]]=a[2]/1048576}
      END{printf "%d %d %d", v["file"], v["anon"], v["kernel"]}' "${dsv:-/dev/null}" 2>/dev/null)
  printf 'S %s %s %s %s %s %s %s %s %s\n' \
         "$ms" "$m" "${df:-0} ${da:-0} ${dk:-0} ${uf:-0} ${ua:-0} ${uk:-0} ${dsvf:-0} ${dsa:-0} ${dsk:-0} ${dr:-0} ${dw:-0}"
}

case "${1:-}" in
loop)
  out="${2:?out 文件}"; iv="${3:-0.5}"; max="${4:-7200}"
  stopf="$out.stop"; rm -f "$stopf"
  { printf '#HOST %s %s\n' "$(hostname)" "$(date +%s)"; } >>"$out"
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
    sleep 2   # ★给远端 bash 落地时间：立刻 fetch 常见 0 行（memwatch 同款坑）
  fi
  sleep 2   # ★起采后等采样落地再数，否则恒返回 0（第一版就错在这：返回 0 让人以为起采失败）
  n=$( { is_local "$h" && cat "$out" || ssh_to "$h" "cat '$out'"; } 2>/dev/null | grep -c '^S ' )
  printf '%s\n' "${n:-0}";;
*) sed -n '2,30p' "$0"; exit 2;;
esac
