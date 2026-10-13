#!/usr/bin/env bash
# water_sampler.sh — W5-STAGE2-20261012 水位 10s 采样器（四机 MemAvailable）
#   蓝本=logs/R1-PROMO2-20261012/desk/water_sampler.sh（仅 D 路径改写=本窗档）
set -u
D="$HOME/luz030-opt-campaign/logs/QA31-20261013"
STOP="${1:?stop-file}"
FLUSHF="$D/state/FLUSH"
OUT="$D/water-10s.txt"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=8"
: > "$OUT"
echo "# ts head_MB w02_MB w03_MB w04_MB min_MB" >> "$OUT"
sample(){ local gran="$1"
  h=$(awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo 2>/dev/null)
  w2=$($SSH dgxspark02 "awk '/^MemAvailable/{print int(\$2/1024)}' /proc/meminfo" 2>/dev/null)
  w3=$($SSH dgxspark03 "awk '/^MemAvailable/{print int(\$2/1024)}' /proc/meminfo" 2>/dev/null)
  w4=$($SSH dgxspark04 "awk '/^MemAvailable/{print int(\$2/1024)}' /proc/meminfo" 2>/dev/null)
  mn=$(printf '%s %s %s %s' "$h" "$w2" "$w3" "$w4" | tr ' ' '\n' | sort -n | head -1)
  echo "$(date -u +%FT%TZ) ${h:-?} ${w2:-?} ${w3:-?} ${w4:-?} ${mn:-?}${2:+ $2}" >> "$OUT"
  [ "${mn:-99999}" -lt 6000 ] 2>/dev/null && echo "$(date -u +%FT%TZ) WATER-RED min=${mn}MB (<6000 qamemguard floor)" >> "$OUT"
  sleep "$gran"
}
while [ ! -e "$STOP" ]; do
  if [ -e "$FLUSHF" ]; then sample 1 flush; else sample 10; fi
done
echo "# sampler stopped $(date -u +%FT%TZ)" >> "$OUT"
