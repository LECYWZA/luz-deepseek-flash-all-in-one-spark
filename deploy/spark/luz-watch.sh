#!/bin/bash
mkdir -p /root/luz-logs
OUT=/root/luz-logs/watch.log
: > "$OUT"
for i in $(seq 1 1200); do
  T=$(date +%T)
  H=$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:8888/health 2>/dev/null)
  C=$(docker ps -a --format '{{.Names}}|{{.Status}}' 2>/dev/null | grep -E '^r3boot-' | tr '\n' ' ')
  echo "### $T i=$i health=$H | ${C:-无r3boot容器}" >> "$OUT"
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx 'r3boot-head'; then
    echo "PARAM: $(docker inspect r3boot-head --format '{{json .Config.Cmd}}' 2>/dev/null | grep -oE 'swa-prefix-tails|tool-call-parser|enable-cache-report|sleep-on-idle|context-length|api-key|deepseek-v4.1-flash' | sort -u | tr '\n' ' ')" >> "$OUT"
    echo "LOG: $(docker logs --tail 4 r3boot-head 2>&1 | tr '\n' '|')" >> "$OUT"
    echo "STATE: $(docker inspect r3boot-head --format '{{.State.Status}}' 2>/dev/null)" >> "$OUT"
  fi
  if [ "$H" = "200" ]; then echo "### HEALTH_200 $T" >> "$OUT"; break; fi
  sleep 10
done
echo "### WATCH_END $(date +%T)" >> "$OUT"
