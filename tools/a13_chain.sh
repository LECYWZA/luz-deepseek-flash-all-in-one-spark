#!/usr/bin/env bash
# A13 L2PF 产形态链（census 背书 + R0c-v2 c8+ + accept + DE 三格）
# 硬门：①l2pf_attn gate=1 armed=True+master=1 ②banner 25 ③无 wo_a twins（D2 不得混入）
# 量具序（arms README 事故后纪律）：steady → census（新鲜余量窗）→ accept → DE
set -u
cd ~/luz030-opt-campaign
D=logs/A13-L2PF-prod-spec1
L=$D/chain.log
mkdir -p "$D" "$D/de"
log(){ echo "[$(date -u +%FT%TZ)] $*" | tee -a "$L"; }
ok=0
for i in $(seq 1 150); do
  c=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 http://127.0.0.1:8898/health 2>/dev/null)
  [ "$c" = "200" ] && { ok=1; break; }; sleep 10
done
[ "$ok" = "1" ] || { log "health 超时"; exit 1; }
log "health 200 → steady 5min"
sleep 300
log "== 0. 硬门禁（缺即 abort）=="
lp=$(docker logs r3boot-head 2>&1 | grep -c 'l2pf_attn.*gate=1.*armed=True')
log "l2pf_armed=$lp"; [ "$lp" -ge 1 ] || { log "ABORT: l2pf_attn 未武装"; exit 3; }
ms=$(docker logs r3boot-head 2>&1 | grep -cE 'l2pf_attn.*master=1|L2 prefetch master')
log "l2pf_master=$ms"; [ "$ms" -ge 1 ] || { log "ABORT: L2PF master 横幅缺失"; exit 3; }
bg=$(docker logs r3boot-head 2>&1 | grep -c 'banner complete: 25 gates')
log "banner25=$bg"; [ "$bg" -ge 1 ] || { log "ABORT: banner≠25"; exit 3; }
tw=$(docker logs r3boot-head 2>&1 | grep -c 'fp8 twins for')
log "woa_twins=$tw(须=0，D2 不得混入)"; [ "$tw" -eq 0 ] || { log "ABORT: twins 在=D2 混入，非单变量"; exit 3; }
docker logs r3boot-head 2>&1 | grep -E '\[l2pf_attn\]|\[l2_prefetch\]' | tail -4 | tee -a "$L"
log "== 1. census c1（L2PF c1 归因，新鲜余量窗）=="
MEM_GATE_GB=16 bash tools/census_capture_r12.sh A13-L2PF-c1 1 >> "$L" 2>&1
log "census c1 rc=$?"
avail=$(awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo)
log "c1 后 MemAvailable=${avail}MB"
log "== 2. census c8（R0c-v2 c8+ 归因顺车）=="
if [ "$avail" -ge 18000 ]; then
  MEM_GATE_GB=16 bash tools/census_capture_r12.sh A13-R0cV2-c8 8 >> "$L" 2>&1
  log "census c8 rc=$?"
else
  log "余量<18G，c8 census 跳过（防 E1 型水位）"
fi
log "== 3. accept_window =="
python3 tools/accept_window.py --base http://127.0.0.1:8898 > $D/accept_window.json 2>> "$L"
log "accept rc=$?"; cat $D/accept_window.json | tee -a "$L"
log "== 4. DE 三格（对照 A0S′ 50.44/85.16/14.05 与 A10 50.69/87.36/13.72）=="
B="python3 $HOME/dsv41-flash-dgxsparks/bench/sd_bench.py --base-url http://127.0.0.1:8898/v1 --key-file /dev/null"
$B --mode de --type prose --concurrency 1 --json-out $D/de/prose_c1.json >> "$L" 2>&1; log "c1 rc=$?"
$B --mode de --type code  --concurrency 1 --json-out $D/de/code_c1.json  >> "$L" 2>&1; log "code rc=$?"
$B --mode de --type prose --concurrency 8 --json-out $D/de/prose_c8.json  >> "$L" 2>&1; log "c8 rc=$?"
log "== A13 链完 =="
