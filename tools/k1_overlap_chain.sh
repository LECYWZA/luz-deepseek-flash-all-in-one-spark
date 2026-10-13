#!/bin/bash
# A24-K1-F2：K1 重叠束重火链（F1 判定 521e81f 回开发修复后；本版=K1-FIX 改造）
#   =九门可执行化 + 四项 F1 修复改造：
#   ①件A needle 已重钉部署面（armed 安装钉生产 mxfp8_b12x 漏斗改道面+闭包溯
#     stock 漏斗；拔 adapter 件必拒 boot=测试面保真律；A12 横幅新含 funnel_face=b12x）；
#   ②件B 接线定谳=服务路径无调用者（K1B-WIRING-VERDICT-20261003.md）⇒ 默认
#     K1B_WIRED=0：重火臂=arms/K1-OVERLAP-A1-spec1.env 30 键（A22B 29+件A 单键；
#     B/C 键缺席=件C 触发链 C⊂B 同断，armed-but-inert 纪律禁 4 键惰走）；A1/A1b/
#     A12/S4/S6 语义按此形态（见各门内 K1B_WIRED 分支）；K1B_WIRED=1 保留 4 键
#     仪器化形态（臂=原 K1-OVERLAP-spec1.env 33 键；S6=预登记零发射红如期，主会
#     会话裁示才用）；
#   ③位等门补位（链设计 §五 兑现）：A/B 双靴同构对照（A=A22B 29 键 stock 面 vs
#     B=K1 臂，同 salt 同序固定驱动器，GRAPHS=0 双靴形态，δ≥190s+UMA 复静，
#     RED=撤臂即止省六格）；dump 口径=API exit 面（greedy 文本+逐 token logprob
#     逐字节对比）——与链设计「T61 harness 张量 exit 面」的偏差如实登记：K1 三
#     件无 dump plumbing，张量面需 B-WIRE 二期同窗补（判读面以 GSM8K+accept 双
#     哨兵兜底）；
#   ④适配器基线参数化（切产后共享路径现役=6dae6ba6 RS 形）：门0f 槽杂耍段=
#     四机备份现役→装 A22B 基线 065d158b（自 bak 槽 t62c）→火毕还原现役+md5
#     复核（回滚段自动执行）；杜绝覆盖生产件（备份槽名 k1fix 时间戳专用，
#     旧槽 t61~t62c 仍全不碰）。
# 授权=F1 判定 §三.1（521e81f）：修复毕=重火授权（读数面同 F1 令+位等门）。
# 锚（不变，A22B/A22-C1REV 判定卡）：prose c1=78.73 code c1=123.42 c8=21.56
#   c12=17.11 c16=14.53（A22B 自举 78.83/123.70/20.95/17.62/14.73 双口径）；PR
#   四档 3401.9/3717.7/4004.1/4103.8（负判线 32k<3662）；GSM8K 地板=0.966；
#   accept=软参照 [2.90,3.30]+A22B 旧锚 3.225 report-only；census S1-S6 锚同 F1
#   （K1B_WIRED=0 时 S4=report-only〔件C 未接线预期 ~0〕、S6=k1c stats 缺席
#   断言+缺口横幅；S5/RING_LL 硬门不变）。
# trip 律（标准链律）：GSM8K<0.966 或安全硬门红（[roce_ar] REFUSED≠0/非白名单
#   残差/TP8≠4/4/refusing to boot/NCCL 面/S5 出带/RING_LL>4.0/health 塌/位等门
#   RED）=先取证（preserve→~/l10-incident/k1f2-<ts>）再 teardown+回滚+零流量
#   不重试；PR32k<3662=负判线（读数全收，census 后容器留场交主会话）；六格/
#   accept/S1-S4=读数照实留档（判读归主会话）。
# 红线：8898 only（8899=生产口绝不发流量）；集群串行（.slot-lock 自维护）；
#   needle ≤128k（PR 顶档 32k）；不 drop_caches；不动水线；prefill_sp.py 仅按
#   门0f 槽杂耍律动作（备份+还原+md5 复核三连环，其余任何时刻零触碰）；旧槽
#   t61~t62c 全不碰；sudo 仅 r3-boot 内置流；F1/2A/3 现场目录只读；不写判定卡
#   不裁定。
# 教义沿用：mkdir 先于重定向；只认 READY 不认横幅；断言带反向判别；docker
#   残留日志先存档再停；water LC_ALL=C；按机计数；PR 路径绝对化；accept json mean。
set -uo pipefail
cd ~/luz030-opt-campaign
D=logs/A24-K1-F2; L=$D/chain.log; TS=$(date -u +%Y%m%dT%H%M%SZ); INC=~/l10-incident/k1f2-$TS
RR=~/migrate-assets/b12x/b12x/comm/roce_ring
ADP=~/migrate-assets/dsv41/adapter
# ── F2 参数化：件B 接线形态 + 基线槽杂耍 ──
K1B_WIRED="${K1B_WIRED:-0}"                      # 0=A-only 重火（默认，定谳形态）；1=4 键仪器化（主会话裁示）
if [ "$K1B_WIRED" = 1 ]; then ARM_FILE=arms/K1-OVERLAP-spec1.env; ARM_KEYS=33; else ARM_FILE=arms/K1-OVERLAP-A1-spec1.env; ARM_KEYS=30; fi
BASELINE_PS_MD5=065d158b2f3c6b7e4bae809d40d38f58   # A22B 基线 prefill_sp（无争议基线世界）
BASELINE_PS_SRC=prefill_sp.py.bak-deepcarry-t62c    # 基线正本槽（只读拷源；旧槽零触碰=只 cp 不写）
BACKUP_SLOT=prefill_sp.py.bak-pre-k1fix-$TS        # 现役备份专用新槽（时间戳；绝不复用旧槽）
LIVE_PS_MD5=""                                     # 门0f 实测现役 md5（还原判据）
mkdir -p "$D/boot-acceptance" "$D/battery" "$D/pr" "$D/census" "$D/verify" "$D/biteq" "$INC"
printf 'pid=%s\nARM_TAG=A24-K1-F2\nphase=chain-running\nK1B_WIRED=%s\nARM_FILE=%s\nstart=%s\n' "$$" "$K1B_WIRED" "$ARM_FILE" "$(date -u +%FT%TZ)" > .slot-lock
log(){ echo "[$(date -u +%FT%TZ)] $*" | tee -a "$L"; }
water(){ for h in 01 02 03 04; do ssh -o ConnectTimeout=8 dgxspark$h "LC_ALL=C free -m | awk '/Mem:/ {print \$7}'" 2>/dev/null | tr '\n' ' '; done; }
ctn(){ [ "$1" = 01 ] && echo r3boot-head || echo r3boot-worker; }
fetch_logs(){ for h in 01 02 03 04; do ssh -o ConnectTimeout=8 dgxspark$h "docker logs --since $1 $(ctn $h)" >"$D/boot-acceptance/boot$h-$2.log" 2>&1; done; }
preserve(){ fetch_logs "$1" scene; cp "$ARM_FILE" "$INC/" 2>/dev/null; grep -h 'roce_ar' "$D"/boot-acceptance/boot*-scene.log 2>/dev/null | sort -u >"$INC/roce_ar_banners.txt"; grep -hE '\[k1_overlap\]|\[k1w\]|\[k1c\]|\[k1\] site=' "$D"/boot-acceptance/boot*-scene.log 2>/dev/null | sort -u >"$INC/k1_banners.txt"; cp -r "$D/boot-acceptance" "$INC/" 2>/dev/null; cp -r "$D/biteq" "$INC/" 2>/dev/null; log "现场已 cp → $INC"; }
lock_done(){ printf 'pid=%s\nARM_TAG=A24-K1-F2\nphase=%s\nend=%s\n' "$$" "$1" "$(date -u +%FT%TZ)" > .slot-lock; }
md5r(){ if [ "$1" = 01 ]; then md5sum "$2" 2>/dev/null | awk '{print $1}'; else ssh -o ConnectTimeout=10 dgxspark"$1" "md5sum '$2'" 2>/dev/null | awk '{print $1}'; fi; }

# ── 回滚（G5 回退链 K1→A22B；键面已随臂下线=teardown 后树面回滚；F2：prefill_sp 按门0f 备份还原）──
rollback_tree(){
  log "== 回滚段（侧件 rm + sitecustomize 还原 28 [+b12x pristine（K1B_WIRED=1 时）] + prefill_sp 现役还原）=="
  if [ "$K1B_WIRED" = 1 ]; then
  rb_ok=0
  for h in 01 02 03 04; do
    CMD="cd $RR && cp -p roce_oneshot.py.bak-pre-k1b roce_oneshot.py && cp -p _oneshot_cute.py.bak-pre-k1b _oneshot_cute.py && cp -p _allgather_cute.py.bak-pre-k1b _allgather_cute.py && md5sum roce_oneshot.py _oneshot_cute.py _allgather_cute.py | awk '{print \$1}' | tr '\n' ' '"
    if [ "$h" = 01 ]; then out=$(bash -c "$CMD"); else out=$(ssh -o ConnectTimeout=10 dgxspark$h "$CMD"); fi
    log "rollback-b12x@$h = [$(echo $out)]"
    [ "$(echo $out)" = "d753a0d8905c8a6a644c1f3151e2bb7c 24201a8c747c0c036fdbb6ccc6e0a54b e2449aaec3a111a1b8ec95aeceeefda6" ] && rb_ok=$((rb_ok+1))
  done
  log "b12x 回滚 pristine $rb_ok/4（期望4）"
  else
  log "K1B_WIRED=0：b12x patch 未部署（0d 跳过）——pristine 校验面而非还原面"
  pr=0
  for h in 01 02 03 04; do
    m=$(md5r $h "$RR/roce_oneshot.py"); [ "$m" = "d753a0d8905c8a6a644c1f3151e2bb7c" ] && pr=$((pr+1))
    log "rollback-b12x-pristine@$h md5=$m"
  done
  rb_ok=$pr
  log "b12x pristine 在位 $pr/4（期望4；若 <4=patch 在场而 K1B_WIRED=0，登记不还原——树面处置归主会话）"
  fi
  # adapter 三件撤除+sitecustomize 还原，逐机结构化复核
  rb2=0
  for h in 01 02 03 04; do
    CMD="rm -f $ADP/k1_multistream.py $ADP/k1_union_prefetch.py $ADP/sitecustomize_k1.py; cp -p $ADP/sitecustomize.py.bak-pre-k1 $ADP/sitecustomize.py; ls $ADP | grep -c 'k1_' || true; md5sum $ADP/sitecustomize.py | awk '{print \$1}'; grep -c 'banner complete: 28 gates' $ADP/sitecustomize.py; grep -c 'from sitecustomize_k1 import' $ADP/sitecustomize.py || true"
    if [ "$h" = 01 ]; then out=$(bash -c "$CMD"); else out=$(ssh -o ConnectTimeout=10 dgxspark$h "$CMD"); fi
    nk=$(printf '%s\n' "$out" | sed -n 1p); scm=$(printf '%s\n' "$out" | sed -n 2p); mds=$(echo $scm); c28=$(printf '%s\n' "$out" | sed -n 3p); nd=$(printf '%s\n' "$out" | sed -n 4p)
    ok=0
    [ "$nk" = 0 ] && [ "$mds" = "8c2c8b143c3d670f5784c6aaa55dd53f" ] && [ "$c28" = 1 ] && [ "$nd" = 0 ] && ok=1
    log "rollback-verify@$h k1残留=$nk sc=$mds count28=$c28 needles=$nd ⇒ ok=$ok"
    [ $ok = 1 ] && rb2=$((rb2+1))
  done
  # prefill_sp 现役还原（门0f 槽杂耍闭环；未杂耍=恒等校验）
  rb3=0
  for h in 01 02 03 04; do
    if [ -n "$LIVE_PS_MD5" ] && [ "$LIVE_PS_MD5" != "$BASELINE_PS_MD5" ]; then
      CMD="cp -p $ADP/$BACKUP_SLOT $ADP/prefill_sp.py && md5sum $ADP/prefill_sp.py $ADP/$BACKUP_SLOT | awk '{print \$1}' | tr '\n' ' '"
    else
      CMD="md5sum $ADP/prefill_sp.py | awk '{print \$1}'"
    fi
    if [ "$h" = 01 ]; then out=$(bash -c "$CMD"); else out=$(ssh -o ConnectTimeout=10 dgxspark$h "$CMD"); fi
    m=$(echo $out | awk '{print $1}')
    [ "$m" = "${LIVE_PS_MD5:-$BASELINE_PS_MD5}" ] && rb3=$((rb3+1))
    log "rollback-prefill_sp@$h md5=$m（期望 ${LIVE_PS_MD5:-$BASELINE_PS_MD5}）"
  done
  log "== 回滚复核：b12x $rb_ok/4 + adapter/sitecustomize 面 $rb2/4 + prefill_sp 现役 $rb3/4（均期望4）==" | tee -a "$D/rollback-verify.txt"
  echo "b12x_ok=$rb_ok/4 adapter_sitecustomize_ok=$rb2/4 prefill_sp_ok=$rb3/4 live_ps=${LIVE_PS_MD5:-na} backup_slot=$BACKUP_SLOT ts=$(date -u +%FT%TZ)" >> "$D/rollback-verify.txt"
}
teardown_and_exit(){ # $1=exit code $2=phase（docker 残留日志先存档再停）
  log "== teardown（$2；docker 日志先存档再停）=="
  fetch_logs "${BOOT_TS:-12h}" td
  bash ~/migrate-assets/bin/r3-stop.sh >>"$L" 2>&1; log "stop rc=$?"
  left=0; for h in 01 02 03 04; do n=$(ssh -o ConnectTimeout=8 dgxspark$h "docker ps -a --format '{{.Names}}' | grep -c r3boot" 2>/dev/null); [ "${n:-1}" != 0 ] && left=$((left+1)); done
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8898/health 2>/dev/null)
  log "teardown 验证：容器残留机数=$left/4（期望0） 8898=$code（期望000）"
  [ "$left" != 0 ] && { ssh -o ConnectTimeout=8 dgxspark01 "docker logs --since 2h $(ctn 01)" >"$D/boot-acceptance/residue-head.log" 2>&1; log "残留容器：head 日志已存 $D/boot-acceptance/residue-head.log"; }
  rollback_tree
  lock_done "$2"; exit "$1";
}

# ══ 门0：靴前前置件（0a/0b=commit 在案；0c/0d/0e=部署三面复核；0f=基线槽杂耍）══
log "== 门0：靴前前置件 =="
[ -e /tmp/k1-gpu-batch.lock ] && { log "ABORT 门0：GPU batch lock 在场——报等待中止"; lock_done aborted-gpulock; exit 9; }
log "0a/0b 引用：mock p1/p7/p9/p11/p13+GPU p2-p6/p8/p10/p12/p13 全绿在案（K1-FIX 提交+MD5.txt day-7）"
log "== 门0c：adapter 三件 md5（期望 be14fcf2036ab4653310d84fb8bd7e5f/7c8e6b9f/0d5e2395（k1_multistream=F1 修复后新值；前值 66d30304=day-2 钉面红形态））=="
for h in 01 02 03 04; do
  m1=$(md5r $h "$ADP/k1_multistream.py"); m2=$(md5r $h "$ADP/k1_union_prefetch.py"); m3=$(md5r $h "$ADP/sitecustomize_k1.py")
  log "0c@$h = [$m1/$m2/$m3]"
  [ "$m1" = "be14fcf2036ab4653310d84fb8bd7e5f" ] && [ "$m2" = "7c8e6b9fa605248f86fc1d0f781d4b9f" ] && [ "$m3" = "0d5e2395b429862cd73b6ec86ca63a43" ] || { log "ABORT 门0c 红：@$h 侧件不对齐（旧形态冒充新读数家族）——停链回报"; lock_done aborted-gate0c; exit 1; }
done
log "== 门0d：b12x 三文件 patched md5+sentinel+roundtrip（K1B_WIRED=1 专属；=0 时 patch 不部署）=="
if [ "$K1B_WIRED" != 1 ]; then
  log "0d 跳过（K1B_WIRED=0：B/C 键缺席⇒分裂路径零进入⇒patch 面零需要；pristine 在位由回滚段校验）"
  pr_ok=0
  for h in 01 02 03 04; do
    ro=$(md5r $h "$RR/roce_oneshot.py"); [ "$ro" = "d753a0d8905c8a6a644c1f3151e2bb7c" ] && pr_ok=$((pr_ok+1))
  done
  log "0d-pristine@$pr_ok/4（期望4：切产后若 <4=patch 残留，登记回报主会话）"
  [ "$pr_ok" = 4 ] || { log "ABORT 门0d 红：K1B_WIRED=0 而 patch 在场（部署面与臂形态不符）——停链回报"; lock_done aborted-gate0d; exit 1; }
else
for h in 01 02 03 04; do
  ro=$(md5r $h "$RR/roce_oneshot.py"); on=$(md5r $h "$RR/_oneshot_cute.py"); ag=$(md5r $h "$RR/_allgather_cute.py")
  log "0d@$h = [$ro/$on/$ag]"
  [ "$ro" = "0f88ef0b79002b1d4a457c6aaf9e6331" ] && [ "$on" = "08287c3cd51015b618d9e975e897a1fe" ] && [ "$ag" = "994f9f9798fab0388833fd969e45f8c3" ] || { log "ABORT 门0d 红：@$h patched md5 不符——停链回报"; lock_done aborted-gate0d; exit 1; }
  if [ "$h" = 01 ]; then cp "$RR/_oneshot_cute.py" "$D/verify/h01_oneshot.py"; else scp -o ConnectTimeout=10 -q dgxspark$h:"migrate-assets/b12x/b12x/comm/roce_ring/_oneshot_cute.py" "$D/verify/h${h}_oneshot.py"; fi
done
python3 - "$D/verify" <<'PY' | tee -a "$L"
import re, sys, glob, hashlib
BEGIN = re.compile(r'#\s*\[k1b:([a-z0-9]+)\]\s*begin'); END = re.compile(r'#\s*\[k1b:([a-z0-9]+)\]\s*end\s*$')
def strip(t):
    out=[]; sid=None
    for ln in t.splitlines(keepends=True):
        if sid is None:
            m=BEGIN.search(ln)
            if m: sid=m.group(1); continue
            out.append(ln)
        else:
            m=END.search(ln)
            if m and m.group(1)==sid: sid=None
    assert sid is None, f'unbalanced {sid}'
    return ''.join(out)
ok=0
for p in sorted(glob.glob(sys.argv[1]+'/h*_oneshot.py')):
    raw=open(p).read(); s=strip(raw)
    md=hashlib.md5(s.encode()).hexdigest()
    n_sent=len(BEGIN.findall(raw))
    good = md=='24201a8c747c0c036fdbb6ccc6e0a54b'
    print(f"0d-roundtrip {p.split('/')[-1]}: sentinel_blocks={n_sent} stripped_md5={md} pristine={'OK' if good else 'MISMATCH'}")
    ok += good
print(f"0d-roundtrip {ok}/4 OK")
sys.exit(0 if ok==4 else 1)
PY
[ $? -eq 0 ] || { log "ABORT 门0d 红：strip-roundtrip 不回 pristine——停链回报"; lock_done aborted-gate0d; exit 1; }
fi
log "== 门0e：sitecustomize 四 insertion+计数 29 =="
for h in 01 02 03 04; do
  CMD="grep -c 'from sitecustomize_k1 import' $ADP/sitecustomize.py; grep -c 'banner complete: 29 gates' $ADP/sitecustomize.py; md5sum $ADP/sitecustomize.py | awk '{print \$1}'"
  if [ "$h" = 01 ]; then out=$(bash -c "$CMD"); else out=$(ssh -o ConnectTimeout=10 dgxspark$h "$CMD"); fi
  nd=$(printf '%s\n' "$out" | sed -n 1p); c29=$(printf '%s\n' "$out" | sed -n 2p); mds=$(printf '%s\n' "$out" | sed -n 3p); mds=$(echo $mds)
  log "0e@$h needles=$nd count29=$c29 md5=[$mds]"
  [ "$nd" = 4 ] && [ "$c29" = 1 ] && [ "$mds" = "7936496adb8971f75140bf8a8ae8cc72" ] || { log "ABORT 门0e 红：@$h insertion/计数不符——停链回报"; lock_done aborted-gate0e; exit 1; }
done
log "== 门0f：prefill_sp 基线槽杂耍（切产后现役=6dae6ba6 RS 形；A22B 基线火须备份→装基线→火毕还原）=="
# 判据（F1 判定 §三.1）：四机实测现役 md5 → 备份专用新槽（时间戳，绝不复用旧槽）→
# 自 t62c 正本槽装 A22B 基线 065d158b → 四机复核。现役==基线时=零杂耍（记录即过）。
live_set=""; for h in 01 02 03 04; do m=$(md5r $h "$ADP/prefill_sp.py"); live_set="$live_set$m "; done
live_first=$(echo $live_set | awk '{print $1}')
if [ "$(echo $live_set | tr ' ' '\n' | sort -u | wc -l)" != 1 ]; then
  log "ABORT 门0f 红：四机现役 prefill_sp md5 不一致 [$live_set]——先定谳再杂耍，停链回报"; lock_done aborted-gate0f; exit 1
fi
LIVE_PS_MD5="$live_first"; echo "live_ps_md5=$LIVE_PS_MD5 baseline=$BASELINE_PS_MD5 backup_slot=$BACKUP_SLOT ts=$(date -u +%FT%TZ)" > "$D/baseline-state.txt"
if [ "$LIVE_PS_MD5" = "$BASELINE_PS_MD5" ]; then
  log "0f：现役==A22B 基线（$LIVE_PS_MD5）——零杂耍（回滚段恒等校验）"
else
  log "0f：现役=$LIVE_PS_MD5 ≠ 基线 $BASELINE_PS_MD5——槽杂耍启动（备份 $BACKUP_SLOT → 装 $BASELINE_PS_SRC）"
  jf=0
  for h in 01 02 03 04; do
    CMD="set -e; [ -f $ADP/$BASELINE_PS_SRC ] || { echo NOSRC; exit 1; }; src_md=\$(md5sum $ADP/$BASELINE_PS_SRC | awk '{print \$1}'); [ \"\$src_md\" = \"$BASELINE_PS_MD5\" ] || { echo BADSRC \$src_md; exit 1; }; [ -e $ADP/$BACKUP_SLOT ] && { echo SLOTEXISTS; exit 1; }; cp -p $ADP/prefill_sp.py $ADP/$BACKUP_SLOT; bak_md=\$(md5sum $ADP/$BACKUP_SLOT | awk '{print \$1}'); [ \"\$bak_md\" = \"$LIVE_PS_MD5\" ] || { echo BADBAK \$bak_md; exit 1; }; cp -p $ADP/$BASELINE_PS_SRC $ADP/prefill_sp.py; new_md=\$(md5sum $ADP/prefill_sp.py | awk '{print \$1}'); echo JUGGLED \$new_md"
    if [ "$h" = 01 ]; then out=$(bash -c "$CMD"); else out=$(ssh -o ConnectTimeout=10 dgxspark$h "$CMD"); fi
    log "0f-juggle@$h = $(echo $out)"
    echo "$out" | grep -q "JUGGLED $BASELINE_PS_MD5" && jf=$((jf+1))
  done
  [ "$jf" = 4 ] || { log "ABORT 门0f 红：基线装填 $jf/4（备份已在位不回收——还原段用）——停链回报"; lock_done aborted-gate0f; exit 1; }
  log "0f：基线装填 4/4（备份槽 $BACKUP_SLOT 已保全现役 $LIVE_PS_MD5；火毕回滚段还原+md5 复核）"
fi
log "门0 绿（0c 侧件三件/0d patch〔K1B_WIRED=$K1B_WIRED〕/0e insertion 29/0f 基线=${LIVE_PS_MD5}）"

# ══ 门1：四机 idle ══
log "== 门1：四机 idle（无 r3boot/无他线链/8898=000）=="
code0=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8898/health 2>/dev/null)
[ "$code0" = "000" ] || { log "ABORT 门1 红：8898=$code0≠000（端口被占）"; lock_done aborted-gate1; exit 1; }
for h in 01 02 03 04; do
  bad=$(ssh -o ConnectTimeout=8 dgxspark$h "docker ps -a --format '{{.Names}}' | grep -c r3boot; pgrep -af 'chain[.]sh|r3[-]boot' | grep -vc k1_overlap_chain" 2>/dev/null)
  log "idle dgxspark$h: $(echo $bad | tr '\n' ' ')"
  echo "$bad" | grep -qv '^0$' && { log "ABORT 门1 红：dgxspark$h 非净——单链串行，停手回报"; lock_done aborted-gate1; exit 1; }
done
# ══ 门2：fabricctl（01/02 全绿；03/04 仅 F10 NFS 豁免）══
log "== 门2：fabricctl 四机 =="
for h in 01 02 03 04; do
  ssh -o ConnectTimeout=10 dgxspark$h "python3 ~/dsv41-flash-dgxsparks/scripts/ring_mesh/fabricctl check" >"$D/gate-fabricctl-$h.log" 2>&1
  rc=$?; fails=$(grep -c '^FAIL ' "$D/gate-fabricctl-$h.log"); f10=$(grep '^FAIL ' "$D/gate-fabricctl-$h.log" | grep -c 'F10')
  log "fabricctl dgxspark$h rc=$rc FAIL=$fails(F10=$f10)"
  { [ "$h" = 01 ] || [ "$h" = 02 ]; } && [ "$fails" != 0 ] && { log "ABORT 门2 红：dgxspark$h FAIL=$fails"; lock_done aborted-gate2; exit 1; }
  [ "$fails" != "$f10" ] && { log "ABORT 门2 红：dgxspark$h 非 F10 失败项"; lock_done aborted-gate2; exit 1; }
done
log "门3：dsv41-mesh unit（留档）"; for h in 01 02 03 04; do ssh -o ConnectTimeout=8 dgxspark$h "systemctl is-active dsv41-mesh" >>"$D/gate-mesh.txt" 2>&1; done; cat "$D/gate-mesh.txt" | tee -a "$L"
# ══ 门4：UMA 静默（≥6min 且四机≥112G）══
log "== 门4：UMA 静默（boot 间隔≥6min+四机≥112G）=="
quiet=0
for i in $(seq 1 40); do
  sleep 60; m=$(water); min=$(echo $m | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n | head -1)
  [ "$i" -ge 6 ] && [ "${min:-0}" -ge 112000 ] && { quiet=1; break; }
  log "quiesce ${i}min minMem=${min:-?}M raw=[$m]"
done
[ "$quiet" = 1 ] || { log "ABORT UMA 静默门 40min 未达——停手回报（不点火）"; lock_done aborted-quiesce; exit 7; }
log "UMA 静默达标（${i}min，min=${min}M）"

# ══ 位等门（链设计 §五：A/B 双靴同构对照，GRAPHS=0 双靴；RED=撤臂即止省六格）══
# A 靴=A22B 29 键基（stock 面，K1 键全缺席）vs B 靴=K1 臂（$ARM_FILE）；同 salt
# 同尺寸同序固定驱动器（禁 sd_bench uuid4 salt——T61 律）；δ 间隔 ≥190s+UMA 复静
# （T61 harness 法则）；dump 口径=API exit 面（greedy 文本+逐 token logprob 逐字节
# 对比）。偏差登记：链设计原文=张量 exit 面（T61 harness），K1 三件无 dump
# plumbing——张量面随 B-WIRE 二期补（K1B-WIRING-VERDICT §五）；GSM8K+accept 双
# 哨兵兜底判读。反向判别：驱动器 salt 随机化=A/B 文本必异=假红，故固定 salt。
EQ=$D/biteq; GRAPHS_OFF="--cuda-graph-backend-decode=disabled"
cat > "$EQ/eq_drive.py" <<'PY'
import json, sys, time, urllib.request
BASE = "http://127.0.0.1:8898"
SALT = sys.argv[1]; OUT = sys.argv[2]
SIZES = [512, 2048, 6144, 16384]
recs = []
for i, size in enumerate(SIZES, 1):
    salt = f"{SALT}{i:02d}"          # FIXED salt：两靴同文本同序（位等判据前提）
    prompt = (f"位等门固定驱动 {salt} " + "确定性内容逐字节可复现。" * (size // 16))[:size]
    body = json.dumps({"model": "deepseek-v4.1-flash", "prompt": prompt,
                       "max_tokens": 96, "temperature": 0, "seed": 7,
                       "logprobs": 1}).encode()
    req = urllib.request.Request(BASE + "/v1/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        d = json.load(r)
    ch = d["choices"][0]
    rec = {"salt": salt, "size": size, "text": ch.get("text", ""),
           "finish": ch.get("finish_reason")}
    lp = ch.get("logprobs") or {}
    rec["tok"] = lp.get("tokens"); rec["tlp"] = lp.get("token_logprobs")
    recs.append(rec)
    print(f"drive {salt}: size={size} tok={len(rec['tok'] or [])} finish={rec['finish']}", flush=True)
    time.sleep(2)
json.dump(recs, open(OUT, "w"), ensure_ascii=False, indent=1, sort_keys=True)
print(f"EQ-DRIVE DONE n={len(recs)} -> {OUT}", flush=True)
PY
eq_boot(){ # $1=side $2=ARM_TAG $3=env-file $4=drive-salt $5=out-json
  local side="$1" tag="$2" envf="$3" salt="$4" outj="$5" bts code
  bts=$(date -u +%Y-%m-%dT%H:%M:%SZ); log "== 位等靴$side（$bts）：$tag（GRAPHS=0 形态）=="
  ARM_TAG="$tag" SPEC=1 SPEC_EXTRA_ARGS="--prefill-decode-interval 16 --max-queued-requests 32 --min-free-slots-delay 1 --enable-decoder-swa-bounded-replay $GRAPHS_OFF" ARM_ENV_FILE="$envf" bash ~/migrate-assets/bin/r3-boot-arm.sh >> "$L" 2>&1
  log "eq-boot$side rc=$?"
  code=000
  for i in $(seq 1 60); do code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8898/health 2>/dev/null); [ "$code" = 200 ] && break; sleep 20; done
  [ "$code" = 200 ] || { log "ABORT 位等靴$side health 20min 未达（code=$code）——保现场原样回报"; preserve "$bts"; teardown_and_exit 2 "aborted-eq-health-$side"; }
  log "位等靴$side health 200 → steady 3min（四机 MemAvail: $(water)M）"; sleep 180
  timeout 1800 python3 "$EQ/eq_drive.py" "$salt" "$outj" 2>&1 | tee -a "$L"
  [ -s "$outj" ] || { log "ABORT 位等靴$side 驱动器零产物（$outj）——量具面红"; preserve "$bts"; teardown_and_exit 4 "red-eq-drive-$side"; }
  fetch_logs "$bts" "eq$side"
  bash ~/migrate-assets/bin/r3-stop.sh >>"$L" 2>&1; log "位等靴$side teardown rc=$?"
  local left=0 h n
  for h in 01 02 03 04; do n=$(ssh -o ConnectTimeout=8 dgxspark$h "docker ps -a --format '{{.Names}}' | grep -c r3boot" 2>/dev/null); [ "${n:-1}" != 0 ] && left=$((left+1)); done
  [ "$left" = 0 ] || { log "ABORT 位等靴$side teardown 未清（残留机数=$left）——残留态泄漏进下一靴，判据污染"; preserve "$bts"; teardown_and_exit 4 "red-eq-residue-$side"; }
}
eq_requiesce(){ # δ≥190s + UMA 复静（T61 harness 法则）
  local d0=$(date +%s) quiet=0 i m min
  for i in $(seq 1 40); do
    sleep 60; m=$(water); min=$(echo $m | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n | head -1)
    if [ $(( $(date +%s) - d0 )) -ge 190 ] && [ "${min:-0}" -ge 112000 ]; then quiet=1; break; fi
    log "eq-quiesce ${i}min minMem=${min:-?}M raw=[$m]"
  done
  [ "$quiet" = 1 ] || { log "ABORT 位等门 δ/复静 40min 未达——停手回报"; lock_done aborted-eq-quiesce; exit 7; }
  log "位等门 δ 复静达标（$(( $(date +%s) - d0 ))s，min=${min}M）"
}
eq_boot A A24K1F2-EQA /home/liux***ya/luz030-opt-campaign/arms/A22B-CAP256K-spec1.env k1f2a "$EQ/exitA.json"
eq_requiesce
eq_boot B A24K1F2-EQB "/home/liux***ya/luz030-opt-campaign/$ARM_FILE" k1f2b "$EQ/exitB.json"
python3 - "$EQ/exitA.json" "$EQ/exitB.json" <<'PY' | tee "$EQ/compare.txt" | tee -a "$L"
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
assert len(a) == len(b) and len(a) > 0, "drive-face mismatch"
ndiff = 0
for ra, rb in zip(a, b):
    same = (ra["text"] == rb["text"] and ra["tok"] == rb["tok"]
            and ra["tlp"] == rb["tlp"])
    if not same:
        ndiff += 1
        # 首异位定位（token 序）
        pos = next((i for i, (x, y) in enumerate(zip(ra["tok"] or [], rb["tok"] or [])) if x != y), -1)
        print(f"EQ-DIFF {ra['salt']}: text_equal={ra['text']==rb['text']} first_tok_diff={pos}")
print(f"EQ-COMPARE n={len(a)} diffs={ndiff} " + ("BITEQ-OK" if ndiff == 0 else "BITEQ-RED"))
sys.exit(0 if ndiff == 0 else 1)
PY
[ $? -eq 0 ] || { log "ABORT 位等门 RED：K1 臂 vs A22B 基线 exit 面位等破（快了但位等破=红，任务卡 §5 首行）——撤臂即止省六格"; preserve "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; teardown_and_exit 9 red-biteq; }
log "位等门 GREEN（A/B 双靴 exit 面逐字节相等；GRAPHS=0 形态）"
eq_requiesce

# ══ 靴1（主靴=K1 重火臂 $ARM_FILE；GRAPHS=产形缺省）══
BOOT_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ); log "== 靴1（$BOOT_TS）：A24-K1-F2=$ARM_FILE（$ARM_KEYS 键；K1B_WIRED=$K1B_WIRED）=="
ARM_TAG=A24-K1-F2 SPEC=1 SPEC_EXTRA_ARGS="--prefill-decode-interval 16 --max-queued-requests 32 --min-free-slots-delay 1 --enable-decoder-swa-bounded-replay" ARM_ENV_FILE=/home/liux***ya/luz030-opt-campaign/$ARM_FILE bash ~/migrate-assets/bin/r3-boot-arm.sh >> "$L" 2>&1
log "boot rc=$?"
code=000
for i in $(seq 1 60); do code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8898/health 2>/dev/null); [ "$code" = "200" ] && break; sleep 20; done
[ "$code" = "200" ] || { log "ABORT health 20min 未达（code=$code）——保现场不重试原样回报（容器尾日志看死因）"; preserve "$BOOT_TS"; teardown_and_exit 2 aborted-health; }
log "health 200 → steady 5min（四机 MemAvail: $(water)M）"; sleep 300

# ══ 门6：冒烟门+断言链 A-ref/A1-A15 ══
log "== 门6：断言链（A-ref+A1/A1b+A2-A11 RoCE 面+A12 K1 接线面+A13 拒靴+A15 冒烟）=="
fetch_logs "$BOOT_TS" b1
a(){ grep -F "$2" "$D/boot-acceptance/boot$h-b1.log" 2>/dev/null | wc -l; }
SW_BANNER='[sparse_wire] sparse-table pair REFUSED -> DenseBlocksBackend'
sw=$(cat "$D"/boot-acceptance/boot*-b1.log | grep -Fc "$SW_BANNER" || true)
refused=$(cat "$D"/boot-acceptance/boot*-b1.log | grep -Fc '[roce_ar] REFUSED' || true)
refo=$(cat "$D"/boot-acceptance/boot*-b1.log | grep -F 'REFUSED' | grep -Fvc "$SW_BANNER" || true)
log "A-ref：sparse_wire 良性横幅×$sw（期望 2/机×4=8 白名单只计数）；[roce_ar] REFUSED×$refused（真 DOA 签名=红线）；非白名单残差×$refo（兜底红线）"
[ "$refused" != 0 ] && { log "ABORT 断言红：[roce_ar] REFUSED×$refused——先 cp 后拆"; preserve "$BOOT_TS"; teardown_and_exit 4 red-refused; }
[ "$refo" != 0 ] && { log "ABORT 断言红：非白名单 REFUSED 残差×$refo——先 cp 后拆"; preserve "$BOOT_TS"; teardown_and_exit 4 red-refused-residual; }
h=01; n33=$(sed -n "/== 靴1（$BOOT_TS）：/,\$p" "$L" | grep -c '\[arm\] +env')
log "A1 arm-env 行数=$n33（期望 $ARM_KEYS；K1B_WIRED=$K1B_WIRED：0=30〔A22B 29+A〕/1=33〔+B×2+C〕；对象=chain.log 本靴段）"
[ "$n33" = "$ARM_KEYS" ] || { log "ABORT A1 红：arm-env 行数=$n33≠$ARM_KEYS——env 丢键/多键形态漂移，撤臂"; preserve "$BOOT_TS"; teardown_and_exit 4 red-armenv; }
if [ "$K1B_WIRED" = 1 ]; then
k1keys=0
for k in DSV41_MULTISTREAM_ALL_LAYERS=1 DSV41_ROCE_SPLIT_PHASE=1 DSV41_ROCE_EPILOGUE_PREFETCH=1 DSV41_L2_PREFETCH_MB=6; do
  n=$(sed -n "/== 靴1（$BOOT_TS）：/,\$p" "$L" | grep -Fc "\[arm\] +env $k")
  log "A1b 四 K1 键进靴：$k → $n（期望≥1）"
  [ "$n" -ge 1 ] && k1keys=$((k1keys+1))
done
[ "$k1keys" = 4 ] || { log "ABORT A1b 红：四 K1 键仅 $k1keys/4 进靴——臂键面未全达，撤臂"; preserve "$BOOT_TS"; teardown_and_exit 4 red-k1keys; }
else
# K1B_WIRED=0（定谳形态）：A 键进靴 + B/C 三键缺席断言（在场=臂形态与定谳不符）
nA=$(sed -n "/== 靴1（$BOOT_TS）：/,\$p" "$L" | grep -Fc '\[arm\] +env DSV41_MULTISTREAM_ALL_LAYERS=1')
log "A1b A 键进靴=$nA（期望≥1）；B/C 键缺席断言："
[ "$nA" -ge 1 ] || { log "ABORT A1b 红：A 键未进靴——撤臂"; preserve "$BOOT_TS"; teardown_and_exit 4 red-k1keys; }
bc=0
for k in DSV41_ROCE_SPLIT_PHASE=1 DSV41_ROCE_EPILOGUE_PREFETCH=1 DSV41_L2_PREFETCH_MB=6; do
  n=$(sed -n "/== 靴1（$BOOT_TS）：/,\$p" "$L" | grep -Fc "\[arm\] +env $k")
  log "A1b 缺席键 $k → $n（期望0）"
  [ "$n" = 0 ] && bc=$((bc+1))
done
[ "$bc" = 3 ] || { log "ABORT A1b 红：B/C 键在场而 K1B_WIRED=0——臂与定谳形态不符（armed-but-inert 禁），撤臂"; preserve "$BOOT_TS"; teardown_and_exit 4 red-k1keys-mode; }
fi
ready=0
for h in 01 02 03 04; do
  g2=$(a x 'gates=1/1 tp=4 max=262144 gather=524288'); g3=$(a x 'armed parallel_state face'); g4=$(a x 'armed pynccl face: ring=roce_ring max_size=262144')
  g5=$(a x 'RoCEnante ready: world=4 hcas=rocep1s0f0,rocep1s0f1,roceP2p1s0f0,roceP2p1s0f1 gid_index=3'); g6=$(a x 'ROCE_TP8_READY'); g7=$(a x 'ROCE_TP8_ROUTE')
  g8=$(a x 'sglang is using nccl==2.30.7'); g9=$(grep -ohE 'bytes_per_full_token=[0-9]+[.][0-9]+' "$D/boot-acceptance/boot$h-b1.log" 2>/dev/null | sort -u | tr '\n' ' '); g9b=$(a x 'max_total_num_tokens=9600000')
  g10=$(grep -c 'ep1f' "$D/boot-acceptance/boot$h-b1.log" 2>/dev/null); g11=$(grep -c 'NCCL WARN' "$D/boot-acceptance/boot$h-b1.log" 2>/dev/null)
  log "A2-A11@$h: gates=$g2 ps=$g3 pynccl=$g4 ready=$g5 TP8=$g6 route=$g7 nccl=$g8 bft=[$g9] mtn=$g9b ep1f=$g10 warn=$g11"
  [ "${g11:-0}" != 0 ] && { log "ABORT A11 红：@$h NCCL WARN=$g11——先 cp 后拆"; preserve "$BOOT_TS"; teardown_and_exit 4 red-ncclwarn; }
  [ "${g6:-0}" -ge 1 ] && ready=$((ready+1))
done
log "A9：bytes_per_full_token 实际=$g9（信息项；A22-C1REV 指纹 912.25）"
grep -h 'ROCE_TP8_READY' "$D"/boot-acceptance/boot*-b1.log | sort -u | tee "$D/roce_tp8_banner.txt" | tee -a "$L"
[ "$ready" -eq 4 ] || { log "ABORT A6 主判据 ROCE_TP8_READY=$ready/4——路由面残废停链，先 cp 后拆"; preserve "$BOOT_TS"; teardown_and_exit 5 red-tp8-notready; }
# A12 K1 接线面（按机计数 ≥1×4）：K1B_WIRED=1=[k1_overlap] 四面全装+件C armed+件B patch 面；
#   =0（定谳形态）=件A armed+funnel_face=b12x（needle 重钉读数面）+B/C 面缺席断言（在场=红）
k1ov_m=0; k1c_m=0; k1a_m=0; k1w_m=0; face_m=0; a13tot=0; bcface=0
for h in 01 02 03 04; do
  if [ "$K1B_WIRED" = 1 ]; then
    b1=$(a x '[k1_overlap] a=1/True b=1/1 c_mb=6'); b2=$(a x '[k1c] union window prefetch armed'); b3=$(a x '[k1] site=arm stream=main engine_md5=fb87a7f0'); b4=$(a x '[k1w] face=roce piece_c=armed'); b5=$(a x 'faces=gate:1,roce:1,moe:43L'); b6=$(a x 'bracket:1'); b7=$(a x 'refusals=0')
  else
    b1=$(a x '[k1_overlap] a=1/True b=(unset)/(unset) c_mb=(unset)'); b2=$(a x '[k1c] union window prefetch armed'); b3=$(a x 'funnel_face=b12x'); b4=$(a x '[k1w] face=roce piece_c=armed'); b5=$(a x 'faces=gate:0,roce:0,moe:0L/0e'); b6=$(a x 'bracket:0'); b7=$(a x 'refusals=0')
  fi
  rtb=$(grep -c 'refusing to boot' "$D/boot-acceptance/boot$h-b1.log" 2>/dev/null); a13tot=$((a13tot+rtb))
  log "A12@$h k1_overlap=$b1 k1c_armed=$b2 k1a_armed/funnel_face=$b3 k1w_roce=$b4 faces=$b5 bracket=$b6 refusals0=$b7 refusing_boot=$rtb"
  [ "${b1:-0}" -ge 1 ] && k1ov_m=$((k1ov_m+1)); [ "${b2:-0}" -ge 1 ] && k1c_m=$((k1c_m+1)); [ "${b3:-0}" -ge 1 ] && k1a_m=$((k1a_m+1)); [ "${b5:-0}" -ge 1 ] && face_m=$((face_m+1))
  if [ "$K1B_WIRED" = 0 ]; then
    # B/C 面缺席断言（在场=半装态红：件C armed 横幅/roce piece_c=armed 不应出现）
    cb2=$(a x '[k1c] union window prefetch armed'); cb4=$(a x 'piece_c=armed')
    [ "${cb2:-0}" = 0 ] && [ "${cb4:-0}" = 0 ] && bcface=$((bcface+1))
  fi
done
if [ "$K1B_WIRED" = 1 ]; then
log "A12 装载面计数：k1_overlap=$k1ov_m/4 k1c=$k1c_m/4 k1(A)=$k1a_m/4 faces=$face_m/4；A13 拒靴签名 total=$a13tot（期望0）"
{ [ "$k1ov_m" = 4 ] && [ "$k1c_m" = 4 ] && [ "$k1a_m" = 4 ] && [ "$face_m" = 4 ] && [ "$a13tot" = 0 ]; } || { log "ABORT A12/A13 红：装载面不全或拒靴签名在场（半装态=红）——先 cp 后拆"; preserve "$BOOT_TS"; teardown_and_exit 4 red-k1-faces; }
else
log "A12 装载面计数（定谳形态）：k1_overlap(30键横幅)=$k1ov_m/4 funnel_face=b12x(A armed)=$k1a_m/4 faces_all0=$face_m/4 B/C面缺席=$bcface/4；A13 拒靴签名 total=$a13tot（期望0）"
{ [ "$k1ov_m" = 4 ] && [ "$k1a_m" = 4 ] && [ "$face_m" = 4 ] && [ "$bcface" = 4 ] && [ "$a13tot" = 0 ]; } || { log "ABORT A12/A13 红：A 面不全/funnel_face≠b12x/B-C 面意外在场/拒靴签名（半装态或形态不符=红）——先 cp 后拆"; preserve "$BOOT_TS"; teardown_and_exit 4 red-k1-faces; }
log "S6 缺口横幅登记：件B/C 未接线=K1B-WIRING-VERDICT-20261003.md（服务路径无调用者；B-WIRE 二期补线前置清单在档）"
fi
grep -h '\[k1_overlap\]' "$D"/boot-acceptance/boot*-b1.log | sort -u | tee "$D/k1_overlap_banner.txt" | tee -a "$L"
ssh -o ConnectTimeout=8 dgxspark01 "docker exec r3boot-head sh -c 'ls /tmp/*roce* 2>/dev/null'" >"$D/roce_stats_files.txt" 2>&1; log "A6 stats JSON 候选: $(cat $D/roce_stats_files.txt | tr '\n' ' ')"
log "A15 冒烟 20-token（盐签名 k1a 内嵌）："
curl -s --max-time 60 http://127.0.0.1:8898/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"deepseek-v4.1-flash","messages":[{"role":"user","content":"用一句通顺的中文介绍长城。（k1a）"}],"max_tokens":40,"temperature":0}' | tee "$D/smoke.json" | tee -a "$L"; echo | tee -a "$L"

# ══ battery 六格（双口径：设计锚+A22B 自举）══
log "== battery 六格（设计锚 78.73/123.42/21.56/17.11/14.53 ±2% +A22B 自举 78.83/123.70/20.95/17.62/14.73 双口径）=="
( cd ~/luz030-opt-campaign && ARM_TAG=A24-K1-F2 bash tools/run_battery_v2.sh ) >> "$L" 2>&1
log "battery rc=$?（四机 MemAvail: $(water)M）"
BATS=$(ls -dt /home/liux***ya/luz030-opt-campaign/logs/A24-K1-F2/2* 2>/dev/null | head -1)
log "battery 目录=$BATS"
cells=$(python3 - "$BATS" <<'PY' | tee "$D/battery/six_cells.txt" | tee -a "$L"
import json, sys, os
ANCH = {"de_prose_c1.json": (78.73, 78.83), "de_code_c1.json": (123.42, 123.70),
        "de_prose_c8.json": (21.56, 20.95), "de_prose_c12.json": (17.11, 17.62),
        "de_prose_c16.json": (14.53, 14.73)}
d = sys.argv[1]; rc = 0
for fn, (anch, anch_b) in ANCH.items():
    p = os.path.join(d, fn)
    try:
        data = json.load(open(p))["de"]; v = sum(r["per"] for r in data) / len(data)
    except Exception as e:
        print(f"CELL {fn}: PARSE-FAIL {e}"); rc = 3; continue
    dp = (v - anch) / anch * 100.0; dpb = (v - anch_b) / anch_b * 100.0
    flag = "IN-BAND" if abs(dp) <= 2.0 else ("BELOW-BAND" if dp < 0 else "ABOVE-BAND")
    print(f"CELL {fn}: val={v:.2f} vs设计锚{anch}={dp:+.2f}% vsA22B自举{anch_b}={dpb:+.2f}% {flag}")
try:
    pr = json.load(open(os.path.join(d, "pr_4sizes.json")))["pr"]
    print("CELL pr_4sizes(battery 单趟,参考): " + " ".join(f"{r.get('size','?')}={r.get('tok_s')}" for r in pr))
except Exception as e:
    print(f"CELL pr_4sizes: PARSE-FAIL {e}")
sys.exit(rc)
PY
) ; cells_rc=$?
log "六格带检查 rc=$cells_rc（0=全带内；出带=TRIPWIRE-READ 照实留档判读归主会话；c8 哨兵复读见 census 段）"
fetch_logs "$BOOT_TS" b2
h=01
kv=$(cat "$D"/boot-acceptance/boot*-b2.log | grep -Fc '[k1] site=kv_write stream=alt0' || true)
lr=$(cat "$D"/boot-acceptance/boot*-b2.log | grep -Fc '[k1] site=low_ratio_sources stream=alt2' || true)
gr=$(cat "$D"/boot-acceptance/boot*-b2.log | grep -Fc '[k1] site=gate reason=' || true)
log "A14 件A engage 面（battery 后流量在场）：kv_write=$kv low_ratio_sources=$lr（quiet-once 首现即可；gate 拒因横幅×$gr 留档）——终判在 PR 段后"

# ══ PR 四档（pr_ladder6 三步法 arb 中位；对 A22B 锚；负判线 32k<3662）══
log "== PR 四档（锚 A22B 3401.9/3717.7/4004.1/4103.8；负判线 32k<3662）=="
( cd ~/luz030-opt-campaign && ARM_TAG=A24-K1-F2 SIZES="4096 8192 16384 32768" ANCHORS="4096:3401.9 8192:3717.7 16384:4004.1 32768:4103.8" bash tools/pr_ladder6.sh ) >> "$L" 2>&1
log "prl6 rc=$?（四机 MemAvail: $(water)M）"
PRL=$(readlink -f /home/liux***ya/luz030-opt-campaign/logs/A24-K1-F2/prl6/latest 2>/dev/null)
cp -f "$PRL"/prl6_summary.json "$D/pr/" 2>/dev/null
python3 - "$PRL/prl6_summary.json" <<'PY' | tee "$D/pr/four_tiers.txt" | tee -a "$L"
import json, sys
A22B = {4096: 3401.9, 8192: 3717.7, 16384: 4004.1, 32768: 4103.8}
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"PR-PARSE-FAIL {e}"); sys.exit(3)
rc = 0
rows = d.get("rows", d if isinstance(d, list) else [])
for r in rows:
    sz = r.get("size"); med = r.get("arb_median_tok_s") or r.get("median_tok_s")
    if sz is None or med is None: continue
    a = A22B.get(int(sz))
    dp = (med - a) / a * 100.0 if a else float('nan')
    print(f"PR {sz}: arb_median={med} vs A22B {a} = {dp:+.2f}%")
    if int(sz) == 32768:
        print(f"PR32k={med}（负判线 <3662；{'NEG-LINE-TRIGGERED' if med < 3662 else 'above-neg-line'}）")
sys.exit(rc)
PY
pr32=$(python3 -c "
import json,sys
try:
    d=json.load(open('$PRL/prl6_summary.json'))
    for r in (d.get('rows') or []):
        if int(r.get('size',0))==32768: print(r.get('arb_median_tok_s') or r.get('median_tok_s') or 0)
except Exception: print(0)" 2>/dev/null)
neg=0; python3 -c "exit(0 if float('${pr32:-0}')>=3662 else 1)" 2>/dev/null || neg=1
[ "$neg" = 1 ] && log "PR32k=$pr32 <3662——负判线触发（读数续收全，census 后容器留场交主会话）"
# A14 终判（PR 段后大流量）：engage 两 face 必须在场
fetch_logs "$BOOT_TS" b3
kv2=$(cat "$D"/boot-acceptance/boot*-b3.log | grep -Fc '[k1] site=kv_write stream=alt0' || true)
lr2=$(cat "$D"/boot-acceptance/boot*-b3.log | grep -Fc '[k1] site=low_ratio_sources stream=alt2' || true)
log "A14 终判（PR 后）：kv_write=$kv2 low_ratio_sources=$lr2（期望各≥1；armed-but-never-engaged=装载面红）"
{ [ "${kv2:-0}" -ge 1 ] && [ "${lr2:-0}" -ge 1 ]; } || { log "ABORT A14 红：件A engage 面零横幅（armed-but-never-engaged）——先 cp 后拆"; preserve "$BOOT_TS"; teardown_and_exit 4 red-k1a-engage; }

# ══ GSM8K n=500（t62c 驱动器逐字复用=同功率协议；地板 0.966 trip）══
log "== GSM8K 500（同驱动器 gsm8k_dsv41.py 2e964be9/题源 [0:500]/temp0.6/8-shot/并发1/max1024；地板=0.966）=="
timeout 5400 python3 /home/liux***ya/dsv41-flash-dgxsparks/bench/gsm8k_dsv41.py --base http://127.0.0.1:8898 --model deepseek-v4.1-flash --nq 500 --out-raw $D/gsm8k_raw.json --out-summary $D/gsm8k_summary.json >> "$L" 2>&1
log "gsm8k rc=$?"; cat $D/gsm8k_summary.json 2>/dev/null | tee -a "$L"
gacc=$(python3 -c "import json;print(json.load(open('$D/gsm8k_summary.json'))['accuracy_content'])" 2>/dev/null)
log "GSM8K n=500=$gacc（地板 0.966=T62 终局 Ā0.971−0.5pp；对照：stock 0.972/0.970、Ā=0.971、T62-RS 0.982、2A 0.956）"
python3 -c "exit(0 if float('${gacc:-0}')>=0.966 else 1)" 2>/dev/null || { log "RED GSM8K=$gacc <0.966——质量地板塌陷：先取证后拆，中止保现场回滚（标准链律）"; preserve "$BOOT_TS"; teardown_and_exit 6 red-gsm8k; }
log "GSM8K 过地板（判读归主会话）"

# ══ accept 窗（3×256 预热；report-only 软参照 [2.90,3.30]+A22B 3.225 并列）══
log "== accept（3×256 预热后读；软参照 [2.90,3.30]+A22B 旧锚 3.225 并列报，report-only 不 trip）=="
for i in 1 2 3; do python3 /home/liux***ya/dsv41-flash-dgxsparks/bench/sd_bench.py --base-url http://127.0.0.1:8898/v1 --key-file /dev/null --mode de --type prose --concurrency 1 --max-tokens 256 --runs 1 >/dev/null 2>&1; done
python3 tools/accept_window.py --base http://127.0.0.1:8898 > $D/accept.json 2>&1; cat $D/accept.json | tee -a "$L"
acc=$(python3 -c "import json;print(json.load(open('$D/accept.json'))['mean'])" 2>/dev/null)
log "accept=$acc（软带 [2.90,3.30]；A22B 旧锚 3.225；T62 三新靴 2.95-3.075；窗判读归主会话）"

# ══ 字节双 tripwire 预检（件C 预取字节 ≤534MB；证据面——S6 终判在 census 段）══
# K1B_WIRED=0（定谳形态）：件C 未装=stats 面预期缺席——预检改为缺席断言（在场=形态不符红）
if [ "$K1B_WIRED" = 0 ]; then
log "== 字节预检（K1B_WIRED=0：[k1w] stats 面缺席断言——件C 未接线，在场=红）=="
fetch_logs "$BOOT_TS" b4
statson=0
for h in 01 02 03 04; do
  n=$(ssh -o ConnectTimeout=8 dgxspark$h "docker logs --since $BOOT_TS $(ctn $h) 2>&1 | grep -cF '[k1w] stats step='" 2>/dev/null)
  log "stats-absence@$h = $n（期望0）"
  [ "${n:-0}" = 0 ] || statson=$((statson+1))
done
[ "$statson" = 0 ] || { log "ABORT 预检红：K1B_WIRED=0 而 [k1w] stats 在场（件C 意外装载=臂与定谳形态不符）——先 cp 后拆"; preserve "$BOOT_TS"; teardown_and_exit 4 red-k1c-unexpected; }
else
log "== 字节双 tripwire 预检（[k1w] stats 六键；>0 且 ≤534MB/步）=="
fetch_logs "$BOOT_TS" b4
for h in 01 02 03 04; do
  ssh -o ConnectTimeout=8 dgxspark$h "docker logs --since $BOOT_TS $(ctn $h) 2>&1 | grep -F '[k1w] stats step=' | tail -2" > "$D/stats_$h.txt" 2>/dev/null
  log "stats@$h: $(cat $D/stats_$h.txt | tr '\n' '|' )"
done
fi

# ══ census r12.1 + 族级断言 S1-S6（判别核心）══
log "== census（r12.1 护栏版 tag=k1_overlap conc=1；对照基线=a22b_cap256k wall42.12/busy50.85/113.2%）=="
timeout 1500 bash tools/census_capture_r12.sh k1_overlap 1 >> "$L" 2>&1; cenrc=$?
log "census rc=$cenrc"
cp -f ~/l10-quality/r12/k1_overlap_census_c1.json "$D/census/" 2>/dev/null; ls -la ~/l10-quality/r12/k1_overlap_* 2>/dev/null | tee -a "$L"
# 全族面再解析（--top 300=完整 103 族；基线+本火同器同法=census 家族名可比性；
# top-45 json 保留作 r12 序列可比档，S1 族和以完整面计）
log "== census 全族面再解析（v41-opt census_stream --top 300 ×2：基线+本火）=="
timeout 600 python3 ~/v41-opt/tools/census_stream.py ~/l10-quality/r12/k1_overlap_census_c1.trace.json.gz --top 300 --json "$D/census/k1_full.json" >>"$L" 2>&1; log "k1_full rc=$? $(ls -la $D/census/k1_full.json 2>/dev/null | awk '{print $5}')B"
timeout 600 python3 ~/v41-opt/tools/census_stream.py ~/l10-quality/r12/a22b_cap256k_census_c1.trace.json.gz --top 300 --json "$D/census/a22b_full.json" >>"$L" 2>&1; log "a22b_full rc=$?"
log "== census 族级断言 S1-S6（busy 平/wall 降/busy-wall 比升=重叠特征签名；件C 命中=MoE FC1/FC2 ↓≥0.5；Roce 带内=NIC 正交性；RING_LL<4.0）=="
python3 - "$D/census/k1_full.json" "$D/census/a22b_full.json" "$D" "$K1B_WIRED" <<'PY' | tee "$D/census/family_assert_S1S6.txt" | tee -a "$L"
import json, sys, re, os, glob
k1p, basep, D, wired = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    k1 = json.load(open(k1p)); base = json.load(open(basep))
except Exception as e:
    print(f"CENSUS-PARSE-FAIL {e}"); sys.exit(3)
def rows(d): return d.get("rows", [])
def pick(rs, prefix):
    for r in rs:
        if str(r.get("family", "")).startswith(prefix): return r
    return None
def fam(rs, name):
    return next((r for r in rs if r.get("family") == name), None)
SM = ['sparse_mla attn', 'hc_mix_stats', 'hc_mix_reduce', 'mhc_post_split_h', 'hc_combine']
MOE = ['MoE FC1 (w4a8 ph1)', 'MoE FC2 (w4a8 ph2)', 'MoE b12x Silu']
# indexer/整型族：fp4_index_logits + mbtopk 机件四尾名（DigitCounts/TopK+WithinK/radixSort/DigitCumSum
# ——v41-opt tail-44 归一名，基线实测四族和 0.856≈设计 0.876）+ repack const_int + pagetable
IDX_PAT = re.compile(r'_fp4_index_logits_kernel|pagetable overlay|const_int_const_unsigned_char|nsigned_int_unsigned_int_unsigned_int_short_|loat_unsigned_int_unsigned_int_unsigned_int_|at_cuda_detail_TensorInfo_unsigned_int_bool_|DigitCumSum_short_unsigned_int')
def sums(d):
    rs = rows(d); out = {}
    out['sm'] = sum(fam(rs, f)['ms_per_step'] for f in SM if fam(rs, f))
    out['sm_missing'] = [f for f in SM if not fam(rs, f)]
    out['moe'] = sum(fam(rs, f)['ms_per_step'] for f in MOE if fam(rs, f))
    idx = [(r['family'][:40], r['ms_per_step']) for r in rs if IDX_PAT.search(r['family'])]
    out['idx'] = sum(v for _, v in idx); out['idx_fams'] = idx
    out['fc12'] = sum(fam(rs, f)['ms_per_step'] for f in MOE[:2] if fam(rs, f))
    out['fc1'] = fam(rs, MOE[0]); out['fc2'] = fam(rs, MOE[1])
    return out
K, B = sums(k1), sums(base)
k1rows, baserows = rows(k1), rows(base)
one_k, one_b = pick(k1rows, 'ri32gmemalign16_ptri32gmemalign16'), pick(baserows, 'ri32gmemalign16_ptri32gmemalign16')
ag_k, ag_b = pick(k1rows, 'i32gmemalign16_ptri32gmemalign16'), pick(baserows, 'i32gmemalign16_ptri32gmemalign16')
ar_k, ar_b = fam(k1rows, 'nccl.AR'), fam(baserows, 'nccl.AR')
fmt = lambda r: "-" if r is None else f"{r['ms_per_step']}ms@{r['calls_per_step']}cps"
rc = 0
print(f"census header: steps={k1.get('steps')} wall={k1.get('wall_ms_per_step')} busy={k1.get('gpu_busy_ms_per_step')} busy_pct={k1.get('gpu_busy_pct')}（a22b 基线 wall 42.12/busy 50.85/113.2%）")
# S1 三族 busy 平（重叠主签名上半；±5% 带；出带=判读档：busy 增=红向/MoE 降=件C 红利域 S4 裁）
for name, kk, bb, des in (('sparse_mla/hc', K['sm'], B['sm'], 4.27), ('indexer/整型', K['idx'], B['idx'], 1.94), ('MoE', K['moe'], B['moe'], 18.24)):
    dp = (kk - bb) / bb * 100.0 if bb else float('nan')
    inb = "IN-BAND(±5%)" if abs(dp) <= 5.0 else ("ABOVE-BAND(busy增=红向)" if dp > 0 else "BELOW-BAND")
    print(f"S1 {name}: k1={kk:.3f}ms vs a22b实算={bb:.3f}ms = {dp:+.2f}% vs设计锚{des} {inb}")
    if abs(dp) > 5.0 and dp > 0 and name != 'MoE':
        print(f"  S1-READ-RED向 {name}: busy 增方向出带（重叠未发生而重排发生）——判读档留档")
print(f"S1 idx 族构成（k1）: " + ", ".join(f"{f}={v}" for f, v in K['idx_fams']))
if K['sm_missing']: print(f"S1 WARN 缺族: {K['sm_missing']}")
# S2 wall 降（主签名中）
w_k, w_b = k1.get('wall_ms_per_step', 0), base.get('wall_ms_per_step', 0)
dw = w_k - w_b
print(f"S2 wall: {w_b} → {w_k}（Δ={dw:+.2f}ms；预期带 40.1-41.0=−1.2~−2.0ms；Δwall>0=重叠零收割读数，判读归主会话）")
print(f"   {'S2-IN-EXPECTED-BAND' if 40.1 <= w_k <= 41.0 else 'S2-OUT-OF-EXPECTED-BAND（读数留档）'}")
# S3 busy/wall 比↑
bu_k, bu_b = k1.get('gpu_busy_ms_per_step', 0), base.get('gpu_busy_ms_per_step', 0)
r_k, r_b = bu_k / w_k if w_k else 0, 1.207
print(f"S3 busy/wall: {bu_k}/{w_k}={r_k:.3f} vs 基线 1.207（{'>1.207 签名成立' if r_k > 1.207 else '≤1.207 签名未立（读数）'}）")
# S4 件C 附加：MoE FC1/FC2 ↓≥0.5ms/步（K1B_WIRED=0=report-only：件C 未接线预期 ~0）
d_f = (B['fc12'] - K['fc12'])
if wired == "0":
    print(f"S4 MoE FC1/FC2: {fmt(B['fc1'])}+{fmt(B['fc2'])}={B['fc12']:.3f} → {fmt(K['fc1'])}+{fmt(K['fc2'])}={K['fc12']:.3f}（↓{d_f:.3f}ms/步；REPORT-ONLY：件C 未接线（K1B-WIRING-VERDICT），预期 ~0——判读归主会话）")
else:
    print(f"S4 MoE FC1/FC2: {fmt(B['fc1'])}+{fmt(B['fc2'])}={B['fc12']:.3f} → {fmt(K['fc1'])}+{fmt(K['fc2'])}={K['fc12']:.3f}（↓{d_f:.3f}ms/步；≥0.5=件C 命中判读；<0.5=件C 落空读数——判读归主会话）")
# S5 通讯带内（±10% 硬门=安全族：出带=件C 挤占/NIC 正交性破 → RED）
for name, rk, rb, anch in (('RoceOneshot', one_k, one_b, 2.452), ('RoceAG', ag_k, ag_b, 1.093)):
    if rk is None:
        print(f"S5 RED：{name} 族缺失——RoCE 路由面丢失"); rc = 1; continue
    dp = (rk['ms_per_step'] - anch) / anch * 100.0
    inb = abs(dp) <= 10.0
    print(f"S5 {name}: {fmt(rk)} vs 锚 {anch} = {dp:+.2f}%（a22b 实算 {fmt(rb)}）{'IN-BAND(±10%)' if inb else 'OUT-OF-BAND'}")
    if not inb:
        print(f"S5 RED：{name} 出 ±10% 带——预取挤占通讯（NIC/DRAM 正交性破），件C 预算键回议"); rc = 1
# RING_LL 残余（<4.0 硬门）
if ar_k is None:
    print("WARN：nccl.AR 行缺失（RING_LL 残余不在带——判别读数缺项留档）")
elif ar_k['ms_per_step'] > 4.0:
    print(f"RED：nccl.AR={ar_k['ms_per_step']}ms 膨胀（γ1 无面基线 9.614ms 特征=路由面丢失）"); rc = 1
else:
    print(f"RING_LL 残余: {fmt(ar_k)}（a22b {fmt(ar_b)}；<4.0 带内）")
# S6 件C 自观测量：K1B_WIRED=1=stats 六键+bytes_issued/步双 tripwire 硬门；
#   =0（定谳形态）=stats 面缺席断言（在场=件C 意外装载=红）+缺口横幅
stats_lines = []
for p in sorted(glob.glob(os.path.join(D, 'stats_0*.txt'))):
    for ln in open(p):
        m = re.search(r'step=(\d+).*?bytes_issued=(\d+)', ln)
        if m: stats_lines.append((os.path.basename(p), int(m.group(1)), int(m.group(2))))
if wired == "0":
    if stats_lines:
        print("S6 RED：K1B_WIRED=0 而 [k1w] stats 在场——件C 意外装载（臂与定谳形态不符）"); rc = 1
    else:
        print("S6 ABSENT-AS-EXPECTED：件B/C 未接线（K1B-WIRING-VERDICT-20261003.md：all_reduce_send 服务路径无调用者，件C 触发链 C⊂B 同断）——零发射为定谳形态预期，B-WIRE 二期补线前置清单在档")
elif not stats_lines:
    print("S6 RED：[k1w] stats 横幅缺席=量具红（p12 前置未跑形态/bracket 未装）"); rc = 1
else:
    best = max(stats_lines, key=lambda t: t[1])
    src, step, by = best
    per_step_mb = by / step / 1e6 if step else 0.0
    print(f"S6 stats 最新: {src} step={step} bytes_issued={by}B ⇒ {per_step_mb:.3f}MB/步（tripwire: >0 且 ≤534MB）")
    if by <= 0 or per_step_mb <= 0:
        print("S6 RED：bytes_issued=0——零发射=触发链断（split-SEND 钩子服务路径无调用者形态），件C 触发链未驱动"); rc = 1
    elif per_step_mb > 534.0:
        print("S6 RED：bytes_issued/步 >534MB——截断律失灵"); rc = 1
    else:
        print("S6 IN-TRIPWIRE-BAND（0<每步≤534MB）")
print("census-S1S6 " + ("RED" if rc else "GREEN"))
sys.exit(rc)
PY
cenS_rc=$?
[ "$cenS_rc" != 0 ] && { log "ABORT census 族断言红（rc=$cenS_rc）——按 tripwire 律先取证后拆（S5/S6/RING_LL 安全族红=回滚），回报主会话"; preserve "$BOOT_TS"; teardown_and_exit 8 red-census-S; }
log "census 族断言 GREEN（S1-S4 判别读数+S5/S6 安全门过；数值判读归主会话）"

# ══ 负判线形态：容器留场交主会话（不 teardown 不回滚；树面处置归主会话）══
if [ "$neg" = 1 ]; then log "== 负判（PR32k<3662）：读数全收毕，容器留场交主会话（树面回滚延后）=="; log "== A24-K1-F2 链完（负判形态）water=$(water)M =="; lock_done negative-pr-keepboot; exit 0; fi

# ══ teardown → 回滚 → 门9 验证 ══
log "== teardown 主靴 =="
teardown_and_exit 0 completed
