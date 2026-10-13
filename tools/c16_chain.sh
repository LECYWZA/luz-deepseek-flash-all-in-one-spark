#!/usr/bin/env bash
# c16_chain.sh —— C16×600K 压测窗链：boot(SPEC=0)→门→probe 先遣→arm a 十六发→收
set -u
cd ~/luz030-opt-campaign
D=logs/C16-600K-spec0
L=$D/chain.log
mkdir -p $D
log(){ echo "[$(date -u +%FT%TZ)] $*" | tee -a "$L"; }
water(){ awk '/^MemAvailable/{printf "%d", $2/1024}' /proc/meminfo; }
ok=0
for i in $(seq 1 150); do
  c=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 http://127.0.0.1:8898/health 2>/dev/null)
  [ "$c" = "200" ] && { ok=1; break; }; sleep 10
done
[ "$ok" = "1" ] || { log "health 超时"; exit 1; }
log "health 200 → steady 5min（water=$(water)M）"
sleep 300
bg=$(docker logs r3boot-head 2>&1 | grep -c 'banner complete: 28 gates')
ec=$(docker logs r3boot-head 2>&1 | grep -c 'prefill empty_cache hook installed')
ir=$(docker logs r3boot-head 2>&1 | grep -c 'idle-release wrap ARMED')
ag=$(docker logs r3boot-head 2>&1 | grep -c 'admission_gate: armed')
tb=$(docker exec r3boot-head printenv DSV41_TL_BUDGET_ELEMS 2>/dev/null)
sp=$(docker exec r3boot-head printenv SPEC 2>/dev/null || echo "?")
log "banner28=$bg hook=$ec idle=$ir admission=$ag TL_BUDGET=$tb"
[ "$bg" -ge 1 ] && [ "$ec" -ge 1 ] && [ "$ir" -ge 1 ] && [ "$ag" -ge 1 ] && [ "$tb" = "2478000000" ] || { log "ABORT 门未过"; exit 3; }
FLOOR=$(water); log "FLOOR=${FLOOR}M（≥18000 预检线）"
[ "$FLOOR" -ge 18000 ] || { log "SKIP：fresh 地板 <18G（设计卡预检线）"; exit 4; }
log "== 1. probe 先遣（单条 596k：admission 放行+水位基线+TTFT 锚）=="
timeout 3600 python3 tools/c16_600k_driver.py --base http://127.0.0.1:8898 --arm probe --seeds c16-probe-20261002 --json-out $D/probe.json >> "$L" 2>&1
log "probe rc=$? water=$(water)M"
python3 -c "
import json; d=json.load(open('$D/probe.json'))
print('probe:', d.get('rows',[{}])[0].get('status'), 'ttft=', d.get('rows',[{}])[0].get('ttft_s'), 'water_low=', d.get('water',{}).get('lowest_m'))" | tee -a "$L"
grep -q '"status": "PASS"' $D/probe.json 2>/dev/null || { grep -q SKIP $D/probe.json && log "probe SKIP（看原因）" || log "probe FAIL——不放十六发"; exit 5; }
sleep 120
log "== 2. arm a 十六发（16×596k+2k，齐射；预计 prefill ~69min）=="
timeout 9000 python3 tools/c16_600k_driver.py --base http://127.0.0.1:8898 --arm a --depths 0.25 0.5 0.75 --seeds c16-20261002 --json-out $D/c16.json >> "$L" 2>&1
log "arm-a rc=$? water=$(water)M"
cat $D/c16.json 2>/dev/null | python3 -c "
import json,sys; d=json.load(sys.stdin)
w=d.get('water',{})
print('n_pass=',d.get('n_pass'),'n_fail=',d.get('n_fail'),'n_skip=',d.get('n_skip'))
print('water: before=',w.get('before_m'),'lowest=',w.get('lowest_m'),'after=',w.get('after_m'),'aborted=',w.get('aborted'))
print('agg_prefill_tok_s=',d.get('agg_prefill_tok_s'),'ladder_ok=',d.get('ladder_monotonic_ok'))" | tee -a "$L"
docker logs r3boot-head 2>&1 | grep -E "STORM|retract|NO_TOKEN" | tail -5 | tee -a "$L"
log "== C16×600K 窗完 =="
