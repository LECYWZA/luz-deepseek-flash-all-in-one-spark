#!/bin/bash
# T62-3/A24-T62-3-ANCHOR：锚同功率靴链——stock(065d158b)+A22B 协议复刻
#   （arms/A22B-CAP256K-spec1.env 29 键）GSM8K n=500 逐题留档+accept 窗。
# 授权=docs/verdicts/T62-2A-ADJUDICATION-20261003.md §四（df63716）：
#   desk ①纸面 spec ②A22B env 溯源 ③GSM8K 驱动器同源；集群单靴零部署
#   （现役 065d158b 复核在位即可，**零 adapter 部署/零 .bak 动作**——
#   t61~t62b 旧槽全不碰）；读数全收不裁定（三分支判词归主会话）。
# 构成与同源性（段1.3 证明方式）：
#   - GSM8K 段=tools/t62b_ar_slice_chain.sh:337-342 **逐字复用**（唯一
#     delta=$D 输出目录；驱动器/参数/n=500/题源全同：gsm8k_dsv41.py
#     md5 2e964be9，题源 ~/data/gsm8k_test.jsonl [0:500] 定序）——
#     diff 证明见 logs/A24-T62-3-ANCHOR/gsm8k_segment_diff_vs_t62b.txt；
#   - accept 段=t62b:344-351 逐字（3×256 预热+accept_window.py json mean）；
#   - 靴法=tools/a22b_cap256k_chain.sh:78 原样（ARM_ENV_FILE=A22B-CAP256K
#     spec；SPEC_EXTRA_ARGS 同值四键）；env 键断言=29（A22B 键集，非 31）。
# 与 t62b 链的差异（全部为授权书明示项）：
#   ① 无部署/无回滚段（本靴零 adapter 动作；门0 改为"现役=065d158b
#      4/4 复核"=点火前置，不等于回滚锚角色）；
#   ② 无 battery/PR/rowband/census 段（非本靴目的；c1/c8 抽格按授权
#      "链内顺带可得才收"——本链无顺带源，不加跑）；
#   ③ GSM8K <0.97 与 accept 出窗**不触发链中止**（锚读数必须全收，
#      照实留档；三分支判词与窗判读归主会话不写判定卡）。
# 红线：8898 only（8899=生产口绝不发流量）；sudo 仅 r3-boot 内置流（本链
#   零 sudo 直调）；集群串行（.slot-lock 自维护）；needle ≤128k（本链零
#   needle）；不 drop_caches（r3-boot-arm.sh 内置对称 drop_caches 为
#   A22B 协议复刻的 stock 靴程序自有部分，非本链外加动作）；不动水线；
#   GPU 门禁 /tmp/k1-gpu-batch.lock 在=轮询至消失（>90min 报等待中止）；
#   .bak 旧槽 t61~t62b 全不碰；F1/2A 现场目录只读；不写判定卡不裁定；
#   K1 k1_overlap 树他人件勿携带。
# 教义沿用：mkdir 先于重定向；只认 READY 不认横幅；每断言带反向判别；
#   断言红处置=先取证（preserve→~/l10-incident/a24t62c-<ts>）再 teardown。
set -uo pipefail
cd ~/luz030-opt-campaign
D=/home/liux***ya/luz030-opt-campaign/logs/A24-T62-3-ANCHOR; L=$D/chain.log; TS=$(date -u +%Y%m%dT%H%M%SZ); INC=~/l10-incident/a24t62c-$TS
ADP=~/migrate-assets/dsv41/adapter
mkdir -p "$D/boot-acceptance" "$INC"
printf 'pid=%s\nARM_TAG=A24-T62-3-ANCHOR\nphase=chain-running\nstart=%s\n' "$$" "$(date -u +%FT%TZ)" > .slot-lock
log(){ echo "[$(date -u +%FT%TZ)] $*" | tee -a "$L"; }
water(){ for h in 01 02 03 04; do ssh -o ConnectTimeout=8 dgxspark$h "LC_ALL=C free -m | awk '/Mem:/ {print \$7}'" 2>/dev/null | tr '\n' ' '; done; }
ctn(){ [ "$1" = 01 ] && echo r3boot-head || echo r3boot-worker; }
fetch_logs(){ for h in 01 02 03 04; do ssh -o ConnectTimeout=8 dgxspark$h "docker logs --since $1 $(ctn $h)" >"$D/boot-acceptance/boot$h-$2.log" 2>&1; done; }
preserve(){ fetch_logs "$1" scene; cp arms/A22B-CAP256K-spec1.env "$INC/" 2>/dev/null; grep -h 'roce_ar' "$D"/boot-acceptance/boot*-scene.log 2>/dev/null | sort -u >"$INC/roce_ar_banners.txt"; cp -r "$D/boot-acceptance" "$INC/" 2>/dev/null; log "现场已 cp → $INC"; }
lock_done(){ printf 'pid=%s\nARM_TAG=A24-T62-3-ANCHOR\nphase=%s\nend=%s\n' "$$" "$1" "$(date -u +%FT%TZ)" > .slot-lock; }
md5_four(){ # 四机现役 prefill_sp.py md5 表（$1=标注）；日志只入 $L，stdout 仅回显计数（供命令替换捕获）
  ok=0
  for h in 01 02 03 04; do
    if [ "$h" = 01 ]; then md=$(md5sum "$ADP/prefill_sp.py" | awk '{print $1}');
    else md=$(ssh -o ConnectTimeout=10 dgxspark$h "md5sum ~/migrate-assets/dsv41/adapter/prefill_sp.py" 2>/dev/null | awk '{print $1}'); fi
    [ "$md" = "065d158b2f3c6b7e4bae809d40d38f58" ] && ok=$((ok+1))
    echo "[$(date -u +%FT%TZ)] md5[$1] dgxspark$h active=$md（$ok/4 累计=065d158b）" >> "$L"
  done
  echo $ok; }
teardown_and_exit(){ # $1=exit code $2=phase 标注——docker 残留日志先存档再停；零 adapter 动作（无回滚段）
  log "== teardown（$2；docker 日志先存档再停）=="
  fetch_logs "${BOOT_TS:-12h}" td
  bash ~/migrate-assets/bin/r3-stop.sh >>"$L" 2>&1; log "stop rc=$?"
  left=0; for h in 01 02 03 04; do n=$(ssh -o ConnectTimeout=8 dgxspark$h "docker ps -a --format '{{.Names}}' | grep -c r3boot" 2>/dev/null); [ "${n:-1}" != 0 ] && left=$((left+1)); done
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8898/health 2>/dev/null)
  log "teardown 验证：容器残留机数=$left/4（期望0） 8898=$code（期望000）"
  [ "$left" != 0 ] && { docker logs --since 2h "$(ctn 01)" >"$D/boot-acceptance/residue-head.log" 2>&1; log "残留容器：head 日志已存 $D/boot-acceptance/residue-head.log"; }
  # 收尾现役 md5 复核（零动作复核：本靴未部署，现役应仍=065d158b）
  post_ok=$(md5_four post-teardown)
  log "收尾复核：现役 md5=065d158b $post_ok/4（期望4；本靴零 adapter 动作）"
  lock_done "$2"; exit "$1";
}

# ── 门-1：GPU 门禁 marker（K1-GPU-GATE-BATCH；在=轮询至消失，>90min 中止报等待）──
log "== 门-1：GPU batch lock /tmp/k1-gpu-batch.lock =="
waited=0
while [ -e /tmp/k1-gpu-batch.lock ]; do
  [ $waited -ge 90 ] && { log "ABORT 门-1：GPU lock 在场 >90min（$(cat /tmp/k1-gpu-batch.lock 2>/dev/null | head -1)）——报等待中止，不点火"; lock_done aborted-gpulock-wait; exit 9; }
  log "GPU lock 在场（等 ${waited}min）：$(head -1 /tmp/k1-gpu-batch.lock 2>/dev/null)"; sleep 60; waited=$((waited+1))
done
log "GPU lock 缺席=可点火"

# ── 门0：现役 adapter=065d158b 4/4（零部署前置：锚基座在位才点火）──
log "== 门0：四机现役 prefill_sp.py md5 复核（期望 065d158b2f3c6b7e4bae809d40d38f58）=="
pre_ok=$(md5_four pre-boot)
[ "$pre_ok" = 4 ] || { log "ABORT 门0：现役非 065d158b（$pre_ok/4）——锚基座不在位，本靴零 adapter 动作无法自修，停报"; lock_done aborted-gate0-baseline; exit 1; }
log "门0 绿：现役=065d158b 4/4（stock 锚基座在位；本靴零 adapter 部署零 .bak 动作）"

# ── 门1：四机 idle（无 r3boot 容器/无他线链进程/8898=000）──
log "== 门1：四机 idle =="
code0=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8898/health 2>/dev/null)
[ "$code0" = "000" ] || { log "ABORT 门1 红：8898=$code0≠000（端口被占）"; lock_done aborted-gate1; exit 1; }
for h in 01 02 03 04; do
  bad=$(ssh -o ConnectTimeout=8 dgxspark$h "docker ps -a --format '{{.Names}}' | grep -c r3boot; pgrep -af 'chain[.]sh|r3[-]boot' | grep -vc t62c_anchor" 2>/dev/null)
  log "idle dgxspark$h: $(echo $bad | tr '\n' ' ')"
  echo "$bad" | grep -qv '^0$' && { log "ABORT 门1 红：dgxspark$h 非净——单链串行，停手回报"; lock_done aborted-gate1; exit 1; }
done
# ── 门2：fabricctl check 四机（01/02=全绿；03/04 仅 F10 NFS 豁免——a22b 语义原样）──
log "== 门2：fabricctl 四机 =="
for h in 01 02 03 04; do
  ssh -o ConnectTimeout=10 dgxspark$h "python3 ~/dsv41-flash-dgxsparks/scripts/ring_mesh/fabricctl check" >"$D/gate-fabricctl-$h.log" 2>&1
  rc=$?; fails=$(grep -c '^FAIL ' "$D/gate-fabricctl-$h.log"); f10=$(grep '^FAIL ' "$D/gate-fabricctl-$h.log" | grep -c 'F10')
  log "fabricctl dgxspark$h rc=$rc FAIL=$fails(F10=$f10)"
  { [ "$h" = 01 ] || [ "$h" = 02 ]; } && [ "$fails" != 0 ] && { log "ABORT 门2 红：dgxspark$h FAIL=$fails"; lock_done aborted-gate2; exit 1; }
  [ "$fails" != "$f10" ] && { log "ABORT 门2 红：dgxspark$h 非 F10 失败项"; lock_done aborted-gate2; exit 1; }
done
log "门3：dsv41-mesh unit（留档）"; for h in 01 02 03 04; do ssh -o ConnectTimeout=8 dgxspark$h "systemctl is-active dsv41-mesh" >>"$D/gate-mesh.txt" 2>&1; done; cat "$D/gate-mesh.txt" | tee -a "$L"

# ── UMA 静默门（主靴前置：≥6min 且四机≥112G——a22b 原样）──
log "== UMA 静默门 =="
quiesce(){ quiet=0
  for i in $(seq 1 40); do
    sleep 60; m=$(water); min=$(echo $m | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n | head -1)
    [ "$i" -ge 6 ] && [ "${min:-0}" -ge 112000 ] && { quiet=1; break; }
    log "quiesce ${i}min minMem=${min:-?}M raw=[$m]"
  done
  [ "$quiet" = 1 ]; }
quiesce || { log "ABORT UMA 静默门 40min 未达——停手回报（不点火）"; lock_done aborted-quiesce; exit 7; }
log "UMA 静默达标（${i}min，min=${min}M）"

# ── 主靴（A22B 协议复刻：stock 065d158b + A22B-CAP256K 29 键 env；靴法=a22b:78 原样）──
BOOT_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ); log "== 主靴（$BOOT_TS）：A24-T62-3-ANCHOR=A22B 协议复刻（stock adapter+29 键）=="
ARM_TAG=A24-T62-3-ANCHOR SPEC=1 SPEC_EXTRA_ARGS="--prefill-decode-interval 16 --max-queued-requests 32 --min-free-slots-delay 1 --enable-decoder-swa-bounded-replay" ARM_ENV_FILE=/home/liux***ya/luz030-opt-campaign/arms/A22B-CAP256K-spec1.env bash ~/migrate-assets/bin/r3-boot-arm.sh >> "$L" 2>&1
log "boot rc=$?"
code=000
for i in $(seq 1 60); do code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8898/health 2>/dev/null); [ "$code" = "200" ] && break; sleep 20; done
[ "$code" = "200" ] || { log "ABORT health 20min 未达（code=$code）——保现场不重试原样回报（容器尾日志看死因）"; preserve "$BOOT_TS"; teardown_and_exit 2 aborted-health; }
log "health 200 → steady 5min（四机 MemAvail: $(water)M）"; sleep 300

# ── 断言链 A-ref/A1-A11（A22B 断言面原样；A1 键数断言=29 硬门）──
log "== 断言链 A-ref/A1-A11（A22B 协议复刻面；cap 预期=262144）=="
fetch_logs "$BOOT_TS" b1
a(){ grep -F "$2" "$D/boot-acceptance/boot$h-b1.log" 2>/dev/null | wc -l; }
SW_BANNER='[sparse_wire] sparse-table pair REFUSED -> DenseBlocksBackend'
sw=$(cat "$D"/boot-acceptance/boot*-b1.log | grep -Fc "$SW_BANNER" || true)
refused=$(cat "$D"/boot-acceptance/boot*-b1.log | grep -Fc '[roce_ar] REFUSED' || true)
refo=$(cat "$D"/boot-acceptance/boot*-b1.log | grep -F 'REFUSED' | grep -Fvc "$SW_BANNER" || true)
# 反向判别：真 DOA 签名/非白名单残差≠0=RoCE 面残废（a22b 同款）。
log "A-ref：sparse_wire 良性横幅×$sw（期望 2/机×4=8，白名单留档不判红）；[roce_ar] REFUSED×$refused（真 DOA 签名=红线）；非白名单 REFUSED 残差×$refo（兜底红线）"
[ "$refused" != 0 ] && { log "ABORT 断言红：[roce_ar] REFUSED×$refused——先 cp 后撤臂"; preserve "$BOOT_TS"; teardown_and_exit 4 red-refused; }
[ "$refo" != 0 ] && { log "ABORT 断言红：非白名单 REFUSED 残差×$refo——先 cp 后撤臂"; preserve "$BOOT_TS"; teardown_and_exit 4 red-refused-residual; }
h=01; n29=$(sed -n "/== 主靴（$BOOT_TS）：/,\$p" "$L" | grep -c '\[arm\] +env')
# 反向判别：键行数签名锚——≠29=A22B 键集复刻失败（丢键/多键；29=γ1 21+C1 族 7+TP_SIZE）。
log "A1 arm-env 行数=$n29（期望 29=A22B 键集，非 31；对象=chain.log 本靴段）"
[ "$n29" = 29 ] || { log "ABORT A1 红：arm-env 行数=$n29≠29——A22B env 复刻失败，撤臂"; preserve "$BOOT_TS"; teardown_and_exit 4 red-armenv; }
ready=0
for h in 01 02 03 04; do
  g2=$(a x 'gates=1/1 tp=4 max=262144 gather=524288'); g3=$(a x 'armed parallel_state face'); g4=$(a x 'armed pynccl face: ring=roce_ring max_size=262144')
  g5=$(a x 'RoCEnante ready: world=4 hcas=rocep1s0f0,rocep1s0f1,roceP2p1s0f0,roceP2p1s0f1 gid_index=3'); g6=$(a x 'ROCE_TP8_READY'); g7=$(a x 'ROCE_TP8_ROUTE')
  g8=$(a x 'sglang is using nccl==2.30.7'); g9=$(grep -ohE 'bytes_per_full_token=[0-9]+[.][0-9]+' "$D/boot-acceptance/boot$h-b1.log" 2>/dev/null | sort -u | tr '\n' ' '); g9b=$(a x 'max_total_num_tokens=9600000')
  g10=$(grep -c 'ep1f' "$D/boot-acceptance/boot$h-b1.log" 2>/dev/null); g11=$(grep -c 'NCCL WARN' "$D/boot-acceptance/boot$h-b1.log" 2>/dev/null)
  log "A2-A11@$h: gates=$g2 ps=$g3 pynccl=$g4 ready=$g5 TP8=$g6 route=$g7 nccl=$g8 bft=[$g9] mtn=$g9b ep1f=$g10 warn=$g11"
  # A6 计"武装机数"非横幅行数：每 rank READY 横幅 2 条（TPn + [roce_ar]）⇒健康四机行数和恒=8。
  [ "${g6:-0}" -ge 1 ] && ready=$((ready+1))
done
log "A9：bytes_per_full_token 实际=$g9（信息项；A22-C1REV 指纹 912.25）"
grep -h 'ROCE_TP8_READY' "$D"/boot-acceptance/boot*-b1.log | sort -u | tee "$D/roce_tp8_banner.txt" | tee -a "$L"
[ "$ready" -eq 4 ] || { log "ABORT A6 主判据 ROCE_TP8_READY=$ready/4——路由面残废停链，先 cp 后撤臂"; preserve "$BOOT_TS"; teardown_and_exit 5 red-tp8-notready; }
ssh -o ConnectTimeout=8 dgxspark01 "docker exec r3boot-head sh -c 'ls /tmp/*roce* 2>/dev/null'" >"$D/roce_stats_files.txt" 2>&1; log "A6 stats JSON 候选: $(cat $D/roce_stats_files.txt | tr '\n' ' ')"
log "A11 冒烟 20-token（salt 签名 t62c 内嵌）："
curl -s --max-time 60 http://127.0.0.1:8898/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"deepseek-v4.1-flash","messages":[{"role":"user","content":"用一句通顺的中文介绍长城。（t62c）"}],"max_tokens":40,"temperature":0}' | tee "$D/smoke.json" | tee -a "$L"; echo | tee -a "$L"

# ── GSM8K 500（锚同功率主读数；**t62b 链 GSM8K 段逐字复用**，仅输出目录不同）──
log "== GSM8K 500（锚同功率；与 2A 完全同驱动器同题序同采样态：gsm8k_dsv41.py 2e964be9/题源 [0:500]/temp0.6/8-shot/并发1/max1024）=="
timeout 5400 python3 /home/liux***ya/dsv41-flash-dgxsparks/bench/gsm8k_dsv41.py --base http://127.0.0.1:8898 --model deepseek-v4.1-flash --nq 500 --out-raw $D/gsm8k_raw.json --out-summary $D/gsm8k_summary.json >> "$L" 2>&1
log "gsm8k rc=$?"; cat $D/gsm8k_summary.json 2>/dev/null | tee -a "$L"
gacc=$(python3 -c "import json;print(json.load(open('$D/gsm8k_summary.json'))['accuracy_content'])" 2>/dev/null)
# 锚读数照实留档不截断（三分支判词归主会话；本靴无 <0.97 中止——锚测量必须全收）
log "GSM8K n=500 锚读数=$gacc（0.97 门与三分支判词归主会话；对照：A22B n200=0.975/A22A n200=0.985/2A n500=0.956）"

# ── accept 窗（3×256 预热；**t62b 链 accept 段逐字复用**；窗 [3.1,3.4] 判读归主会话）──
log "== accept（3×256 预热后读，窗[3.1,3.4]；A22B 对照 3.225）=="
for i in 1 2 3; do python3 /home/liux***ya/dsv41-flash-dgxsparks/bench/sd_bench.py --base-url http://127.0.0.1:8898/v1 --key-file /dev/null --mode de --type prose --concurrency 1 --max-tokens 256 --runs 1 >/dev/null 2>&1; done
python3 tools/accept_window.py --base http://127.0.0.1:8898 > $D/accept.json 2>&1; cat $D/accept.json | tee -a "$L"
acc=$(python3 -c "import json;print(json.load(open('$D/accept.json'))['mean'])" 2>/dev/null)
# 锚读数照实留档（<3.1/>3.4 均不中止——窗判读归主会话）
log "accept=$acc（窗 [3.1,3.4]；判定归主会话 vs A22B 3.225）"

# c1/c8 抽格：授权"链内顺带可得才收，不为它加跑"——本链（GSM8K+accept）无 battery
#   runner 顺带源，不加跑（accept 预热 3×256 输出弃置非格读数）。留此注记为收证完整性。

# ── 收尾：teardown（docker 日志先存档）→现役 md5 复核→封槽（零 adapter 动作全程）──
log "== teardown 主靴 =="
teardown_and_exit 0 completed
