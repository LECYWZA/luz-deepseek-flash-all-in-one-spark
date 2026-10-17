#!/bin/bash
# luz-monitor.sh — 每 10 秒采样：四台内存余量 + KV 池使用 + 测试最新进展
OUT=/root/luz-logs/monitor.log
: > "$OUT"
for i in $(seq 1 3000); do
  T=$(date +%T)
  M=""
  for h in spark-1 spark-2 spark-3 spark-4; do
    ma=$(ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $h "awk '/MemAvailable/{printf \"%d\", \$2/1024}' /proc/meminfo" 2>/dev/null)
    M="$M $h=${ma:-ERR}M"
  done
  KV=$(curl -s -m 3 -H "Authorization: Bearer luojiecong" http://127.0.0.1:8888/v1/loads 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin); l=d['loads'][0]
    print('used=%d/%d' % (l['num_used_tokens'], l['max_total_num_tokens']))
except Exception:
    print('ERR')
" 2>/dev/null)
  LAST=$(grep -vE '^\[|^DSV41|^prefill_sp|^roce_ar|^warning' /root/luz-logs/kv-test.log 2>/dev/null | tail -1)
  echo "$T | MEM$M | KV $KV | $LAST" >> "$OUT"
  if grep -qE '"verdict"|测试结束|ALL_HIT|CACHE_DROPPED' /root/luz-logs/kv-test.log 2>/dev/null; then
    echo "### 测试已出结论 $(date +%T)" >> "$OUT"
    break
  fi
  sleep 10
done
echo "### MONITOR_END $(date +%T)" >> "$OUT"
