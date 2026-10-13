#!/usr/bin/env bash
# a14b_chain.sh —— knapcio 连1 两件 + FOLDED_FENCE 配对链：
# 门（banner28+hook+idle / spec_sync_free armed / eager_glue stage / folded_fence / 容器 env 三键）
# → battery v2（DE 六格+PR 四档；对照锚 = A0S⁷ c1 58.70 / code 100.88 / c8 20.19 / c12 16.90 / c16 14.51）
# → accept（3×256 预热）→ GSM8K 200
# 用法: 由 nohup 起在靴后；log 落 logs/<ARM>/
set -u
cd ~/luz030-opt-campaign
D=logs/A14B-trio2-spec1
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
nd=$(docker logs r3boot-head 2>&1 | grep -c 'verify_num_draft_tokens=6')
[ "$nd" -ge 1 ] || { log "ABORT block_size 位错（verify_num_draft_tokens!=6）"; exit 3; }
ec=$(docker logs r3boot-head 2>&1 | grep -c 'prefill empty_cache hook installed')
ir=$(docker logs r3boot-head 2>&1 | grep -c 'idle-release wrap ARMED')
sf=$(docker logs r3boot-head 2>&1 | grep -c '\[spec_sync_free\] armed')
eg=$(docker logs r3boot-head 2>&1 | grep -c '\[eager_glue\] stage: draft sampling params staged')
ff=$(docker logs r3boot-head 2>&1 | grep -c '\[folded_fence\]')
ev1=$(docker exec r3boot-head printenv DSV41_SPEC_SYNC_FREE 2>/dev/null)
ev2=$(docker exec r3boot-head printenv DSV41_EAGER_GLUE 2>/dev/null)
ev3=$(docker exec r3boot-head printenv DSV41_FOLDED_FENCE 2>/dev/null)
log "banner28=$bg hook=$ec idle=$ir sync_free=$sf eager_glue=$eg fence=$ff"
log "容器 env: SYNC_FREE=$ev1 EAGER_GLUE=$ev2 FOLDED_FENCE=$ev3"
[ "$ev1" = "all" ] && [ "$ev2" = "all" ] && [ "$ev3" = "1" ] || { log "ABORT 连1 键未达容器"; exit 3; }
[ "$sf" -ge 1 ] && [ "$eg" -ge 1 ] && [ "$ff" -ge 1 ] || { log "ABORT 件横幅未武装（armed≠count：逐件横幅是唯一证据）"; exit 3; }
[ "$bg" -ge 1 ] && [ "$ec" -ge 1 ] && [ "$ir" -ge 1 ] || { log "ABORT 基座门未过"; exit 3; }
log "== battery v2（DE 六格+PR 四档；锚=A0S⁷ c1 58.70/code 100.88/c8 20.19/c12 16.90/c16 14.51，带±2% DE/±5% PR）=="
ARM_TAG=A14B bash tools/run_battery_v2.sh >> "$L" 2>&1; log "battery rc=$? water=$(water)M"
log "== accept（3×256 预热）=="
for i in 1 2 3; do python3 ~/dsv41-flash-dgxsparks/bench/sd_bench.py --base-url http://127.0.0.1:8898/v1 --key-file /dev/null --mode de --type prose --concurrency 1 --max-tokens 256 --runs 1 >/dev/null 2>&1; done
python3 tools/accept_window.py --base http://127.0.0.1:8898 > $D/accept.json 2>&1; cat $D/accept.json | tee -a "$L"
log "== GSM8K 200 =="
timeout 1800 python3 ~/dsv41-flash-dgxsparks/bench/gsm8k_dsv41.py --base http://127.0.0.1:8898 --model deepseek-v4.1-flash --nq 200 --out-raw $D/gsm8k_raw.json --out-summary $D/gsm8k_summary.json >> "$L" 2>&1
log "gsm8k rc=$?"; cat $D/gsm8k_summary.json 2>/dev/null | tee -a "$L"
log "== A14B 链完 =="
