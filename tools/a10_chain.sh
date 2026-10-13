#!/usr/bin/env bash
# A10 L2PF 注意力缝臂快验链（SPEC=1，D2 折基）——门禁化（串链坑纪律）
set -u
cd ~/luz030-opt-campaign
D=logs/A10-L2PF-attn-spec1
L=$D/chain.log
mkdir -p "$D/dsgate"
log(){ echo "[$(date -u +%FT%TZ)] $*" | tee -a "$L"; }
ok=0
for i in $(seq 1 150); do
  c=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 http://127.0.0.1:8898/health 2>/dev/null)
  [ "$c" = "200" ] && { ok=1; break; }; sleep 10
done
[ "$ok" = 1 ] || { log "health 超时"; exit 1; }
log "health 200 → steady 4min"
sleep 240
log "== 0. 激活门禁 =="
n=$(docker logs r3boot-head 2>&1 | grep -c 'fp8 twins for'); [ "$n" -ge 1 ] || { log "ABORT: twins 缺失"; exit 3; }
m=$(docker logs r3boot-head 2>&1 | grep -cE '\[l2pf_attn\] gate=1|\[l2pf_attn\]'); [ "$m" -ge 1 ] || { log "ABORT: l2pf_attn 横幅缺失"; exit 3; }
docker logs r3boot-head 2>&1 | grep -E '\[l2pf_attn\]|\[l2_prefetch\]' | tail -4 | tee -a "$L"
log "== 1. ds_gate 短抽查 =="
python3 tools/ds_gate.py kld collect --panel short --model deepseek-v4.1-flash --out $D/dsgate/cand_short.json >> "$L" 2>&1
python3 tools/ds_gate.py kld compare logs/A0Sp-base-spec1/dsgate/cand_short.json $D/dsgate/cand_short.json >> "$L" 2>&1
log "ds_gate rc=$?"
log "== 2. DE 快测（c1 双格+c8 格；参照：A0S′+D2 折算 prose≈52.5/code≈86/c8≈14.6）=="
B="python3 $HOME/dsv41-flash-dgxsparks/bench/sd_bench.py --base-url http://127.0.0.1:8898/v1 --key-file /dev/null"
$B --mode de --type prose --concurrency 1 --json-out $D/de_prose_c1.json >> "$L" 2>&1; log "c1 rc=$?"
$B --mode de --type code  --concurrency 1 --json-out $D/de_code_c1.json  >> "$L" 2>&1; log "code rc=$?"
$B --mode de --type prose --concurrency 8 --json-out $D/de_prose_c8.json  >> "$L" 2>&1; log "c8 rc=$?"
log "== A10 快验链完 =="
