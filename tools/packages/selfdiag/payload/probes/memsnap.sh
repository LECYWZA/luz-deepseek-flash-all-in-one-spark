#!/usr/bin/env bash
# memsnap.sh <outdir> <tag> —— head 机内存快照：meminfo/free/引擎进程 smaps_rollup/docker stats/metrics
# 目的：分解"一次 8k needle 后 MemAvailable −3.6G 不回落"的落点（Anon vs File cache vs swap vs 进程）
set -u
D="$1"; T="$2"
mkdir -p "$D/$T"
date -Is > "$D/$T/ts"
free -m > "$D/$T/free.txt"
grep -E "^(MemFree|MemAvailable|Cached|AnonPages|SReclaimable|Shmem:|SwapTotal|SwapFree|Active\(file\)|Inactive\(file\)|PageTables|KernelStack)" /proc/meminfo > "$D/$T/meminfo.txt"

# 引擎进程（hostPID 可见）：scheduler / detokenizer / 入口 python3
: > "$D/$T/smaps.txt"
# 引擎进程是 root，smaps_rollup 需要 sudo（口令只走 ~/.sudopw，stdin 喂入，不落日志）
SUDOPW=$(cat ~/.sudopw 2>/dev/null)
for pid in $(pgrep -f "sglang::|detokenizer|/opt/sglang/bin/python3"); do
  { echo "== pid=$pid";
    printf '%s\n' "$SUDOPW" | sudo -S sh -c "grep -E '^(Rss|Pss|Private_Dirty|Anonymous|AnonHugePages|Swap):' /proc/$pid/smaps_rollup" 2>/dev/null; } >> "$D/$T/smaps.txt"
done

docker stats --no-stream --format "{{.Name}} {{.MemUsage}} {{.MemPerc}}" > "$D/$T/dockerstats.txt" 2>/dev/null
# 引擎侧水位仪表（池用量/队列）
curl -s http://127.0.0.1:8898/metrics 2>/dev/null | grep -E "token_usage|running-req|num_running|cache_hit|mem" | grep -v "^#" > "$D/$T/metrics.txt"
echo "snap $T done"
