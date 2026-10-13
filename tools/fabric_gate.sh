#!/bin/bash
# fabric_gate.sh — P1 治理项回移：fabricctl F00-F10 门（fail-closed）独立化（2026-10-02）
#
# 【为什么存在】主计划 §七 P1：「fabricctl boot 门（F00-F10 fail-closed）回移进 r3 链」——
#   RING-FACE-LANDING-VERIFICATION §6 列为「boot 前置门」，但此前只有 a22c1rev_chain.sh 门2
#   内联一段 fabricctl 计数，其余链脚本 grep 零命中（§8.2「起服必查」承诺未接线，C 代理发现）。
#   本件=可被任意 boot 前段一行钩入的独立门（形态：bash tools/fabric_gate.sh || exit 9）。
#
# 【断言面（四机 01-04）】
#   ① fabricctl check 22 项（F00-F10）逐机：01/02 须全绿；03/04 仅 F10（NFS automount 前缀，
#     fabricctl 头注自记的持久化已知项，非通讯面）可豁免——豁免政策= a22c1rev 门2 沿袭，
#     政策出处 RING-FACE-LANDING-VERIFICATION D5。
#   ② hairpin_queue_size=8192 逐机 4 PCI 口（devlink driverinit 值；断电重启回 1024=门红——
#     环研报 §2「fabric 运行态不会自己活过重启」五类首类）。256K 真身=8192 零丢包包络
#     （主计划 §七 二阶勘误：实测 480KB 内取 2× 余量的防丢包工程决策）。
#   ③ tc flower in_hw 逐机 ≥2 条（黄金态=topology.json tc_ingress_prefs：每机恰 2 transit 口
#     各 1 pref，fabricctl F04 同源断言；mesh 竞态后 tc 拒装/in_hw 丢失在此现形；分布=01/02 落
#     enP2p1s0*、03/04 落 enp1s0*，故按机求和不断言端口归属，D5 实测形态。⚠17:48Z 首战假红
#     勘误：原阈值 ≥4 与黄金态自相矛盾——2 口×1 pref=2/机才是健康形，教义第 9 例家族）。
#   ④ GID3 16/16：每机 4 RoCE 口 gid index 3 非空 RoCEv2（断电 GID 洞=modify_qp errno 61 现场；
#     期望 IP 的严格比对由 fabricctl F05 承担，本处为独立计数型复核——双层防「检查器不红」。
#     ⚠17:48Z 首战假红勘误：本机 show_gids 的 VER 列打印 'v2' 非 'RoCEv2'（原正锚字面量永假）；
#     全零 GID 真形=0000(:0000){7}（原负探针 0{4}(:0){7} 与之不匹配——两缺陷同修）。
#
# 【grep 教义（今日 8 例陷阱，本件逐条自检）】
#   - 锚定签名：PASS/FAIL 计数认 '^PASS '/'^FAIL ' 行首锚（fabricctl 输出行式
#     "PASS F00 detail"），防 detail 文本里的字样误命中（cccf363 同宗）。
#   - 本机 grep 实为 ugrep（RING-FACE 审计大小写意外命中先例）→ 全部 grep -E/-c 显式，
#     结果数值一律不再二次文本锚定。
#   - 远端命令含 ~ 由远端 shell 展开（合法面）；本地变量不携带 ~（13975a1 同宗）。
#   - LC_ALL=C 固定（dd2cf07：zh_CN free 输出杀量具——本件 free 不用，纪律沿袭）。
#   - 判别力自检（每断言配「喂坏输入必因正确理由红」，注释就地）：
#     ① 喂旧输出（FAIL F04 行）→ fails≥1 且非 F10 → 01/02 红、03/04 红——红因=通讯面坏；
#     ② hairpin 喂 1024（断电后未 heal 的真形态）→ 值≠8192 计 0 → 红——红因=queue 缩回；
#     ③ tc 喂 devlink reinit 后空 filter（§5.3 mesh 竞态真形态）→ in_hw 求和 0<4 → 红；
#     ④ GID3 喂全零 GID（§5.2 断电洞真形态）→ RoCEv2+非零地址判 0 → 红。
#     四类坏输入全是环研报记载的真实故障形态，非合成稻草人。
#
# 【输出】logs/fabric-gate/<ts>/：fabricctl-0X.log（逐机原始输出）+ hairpin-0X.txt +
#   tc-0X.txt + gid3-0X.txt + fabric_gate.summary；stdout 只打一行一断言。
# 【用法】bash tools/fabric_gate.sh（被 boot 前段钩入；红=exit 9 语义由调用方 || exit 9 落实，
#   本件自身红时 exit 1）。
set -uo pipefail
cd ~/luz030-opt-campaign

TS=$(date -u +%Y%m%dT%H%M%SZ)
D=logs/fabric-gate/$TS
mkdir -p "$D"   # 教义：mkdir 先于重定向
L=$D/fabric_gate.summary
log(){ echo "[$(date -u +%FT%TZ)] $*" | tee -a "$L"; }

HOSTS="01 02 03 04"
FABCTL='python3 ~/dsv41-flash-dgxsparks/scripts/ring_mesh/fabricctl check'   # 只读 check（ring 研报 §2.4；selftest/heal 非本件职权）
HP_PCI='0000:01:00.0 0000:01:00.1 0002:01:00.0 0002:01:00.1'                # hairpin.sh 固定四口表（四机同 PCI 布局）
NET_PORTS='enp1s0f0np0 enp1s0f1np1 enP2p1s0f0np0 enP2p1s0f1np1'              # topology.json ports 四口（全机同表）
ROCE_DEVS='rocep1s0f0 rocep1s0f1 roceP2p1s0f0 roceP2p1s0f1'                  # B12X_ROCE_HCA 同表
red=0

log "== fabric 门启动（四机 F00-F10 + hairpin 8192 + tc in_hw + GID3）=="

for h in $HOSTS; do
  H=dgxspark$h

  # ── ① fabricctl check 22 项 ──
  # 反向判别自检：喂含 'FAIL F04 ...' 的坏输出 → fails≥1 且 fails≠f10 → 两分支皆红（01/02 与 03/04 同红，
  # 因 F04 非豁免项）；裸 grep 'FAIL'（无行首锚）会误数 detail 文本里的字样——本处 ^FAIL 行锚防之。
  ssh -o ConnectTimeout=10 "$H" "$FABCTL" >"$D/fabricctl-$h.log" 2>&1
  rc=$?
  passes=$(grep -c '^PASS ' "$D/fabricctl-$h.log" || true)
  fails=$(grep -c '^FAIL ' "$D/fabricctl-$h.log" || true)
  f10=$(grep '^FAIL ' "$D/fabricctl-$h.log" | grep -c 'F10' || true)
  total=$(( ${passes:-0} + ${fails:-0} ))
  log "fabricctl@$H rc=$rc PASS=$passes FAIL=$fails(F10=$f10) total=$total/22"
  # 豁免政策三层判（顺序即优先级）：
  # ① 输出不完整（PASS+FAIL≠22：fabricctl 异常/半途而废）→ 红——fail-closed，防「检查器不红」；
  # ② 存在非 F10 失败项（通讯面断言红）→ 红（01-04 同标准）；
  # ③ 01/02 任何 FAIL（含 F10——01/02 无 NFS 豁免语义）→ 红；03/04 的 F10=已知非通讯面项，留档不红。
  if [ "$total" != 22 ]; then
    log "RED @$H：fabricctl 输出不完整（total=$total≠22，工具面异常）"; red=1
  elif [ "${fails:-0}" != "${f10:-0}" ]; then
    log "RED @$H：非 F10 失败项（通讯面红）明细："; grep '^FAIL ' "$D/fabricctl-$h.log" | tee -a "$L"; red=1
  elif { [ "$h" = 01 ] || [ "$h" = 02 ]; } && [ "${fails:-0}" != 0 ]; then
    log "RED @$H：01/02 零豁免（RING-FACE D5 政策）fails=$fails"; red=1
  elif [ "${f10:-0}" != 0 ]; then
    log "WARN @$H：F10×$f10（03/04 NFS automount 前缀已知项，非通讯面——留档不判红，D5 定谳）"
  fi

  # ── ② hairpin 8192 逐口 ──
  # 反向判别自检：断电重启后 mesh 未 heal（真形态）→ devlink 值回 1024 → grep -c '=8192' 计 <4 → 红；
  # 喂 81920（错配值）同样红——量词无歧义（精确串比对，非子串宽松匹配：值域取 ' value 8192 ' 定界）。
  ssh -o ConnectTimeout=10 "$H" "for p in $HP_PCI; do devlink dev param show pci/\$p name hairpin_queue_size 2>/dev/null | grep -o 'value [0-9]*'; done" >"$D/hairpin-$h.txt" 2>&1
  hp8192=$(grep -c 'value 8192' "$D/hairpin-$h.txt" || true)
  hpother=$(grep -c 'value ' "$D/hairpin-$h.txt" || true)
  log "hairpin@$H 8192口数=$hp8192/4（读到值行=$hpother）"
  [ "$hp8192" = 4 ] && [ "$hpother" = 4 ] || { log "RED @$H：hairpin 非 4/4=8192（明细：$(tr '\n' ' ' < "$D/hairpin-$h.txt")）"; red=1; }

  # ── ③ tc flower in_hw 按机求和 ──
  # 反向判别自检：mesh 竞态/devlink reinit 抹规则（§5.3 真形态）→ filter 空或仅 skip_sw → in_hw 计 0<2 → 红；
  # 单 transit 口规则丢（半塌）→ 1<2 → 红。健康形=2 transit 口各 1 pref=2/机（topology.json 黄金态，
  # fabricctl F04 同源 PASS；17:48Z 假红勘误后阈值由 4 改 2）。in_hw 为 tc(8) 输出固定字样、无大小写
  # 歧义面（ugrep 教义下仍取精确小写串）。
  ssh -o ConnectTimeout=10 "$H" "for p in $NET_PORTS; do tc -s filter show dev \$p ingress 2>/dev/null | grep -c in_hw; done" >"$D/tc-$h.txt" 2>&1
  tcsum=$(awk '{s+=$1} END{print s+0}' "$D/tc-$h.txt")
  log "tc-in_hw@$H 总数=$tcsum（期望≥2=2 transit 口各 1 pref，topology.json 黄金态；01/02 落 enP2p1s0*、03/04 落 enp1s0*，D5 分布）"
  [ "${tcsum:-0}" -ge 2 ] || { log "RED @$H：tc in_hw=$tcsum<2（明细 $(tr '\n' '/' < "$D/tc-$h.txt")）"; red=1; }

  # ── ④ GID3 非空 RoCEv2 逐口 ──
  # 反向判别自检：断电 GID 洞（§5.2 真形态）→ idx3 行缺失或 GID 全零 → 正锚计数 <4 → 红；
  # 行首锚 ^roce 防止 show_gids 表头/其他 idx 行的字样子串误命中（cccf363 锚定签名同宗）。
  # 格式真锚（17:48Z 假红勘误）：本机 show_gids 行式=DEV PORT INDEX GID [IPv4] VER DEVNAME，
  # VER 列 RoCEv2 打印 'v2'（非 'RoCEv2'）；v2 取独立字素定界 [[:space:]]v2[[:space:]]（GID 十六
  # 进制无 v、接口名无独立 v2 字素——无误命中面）；全零 GID 负探针=0000(:0000){7} 真形。
  ssh -o ConnectTimeout=10 "$H" "LC_ALL=C show_gids 2>/dev/null" >"$D/gid3-$h.txt" 2>&1
  g3=0
  for dvl in $ROCE_DEVS; do
    # 锚 dev+idx3+非全零 GID+VER 列 v2（RoCEv2）。⚠ugrep ERE 陷阱（本机 grep=ugrep 7.8.4，
    # 头注教义实证+1）：token 间脚手架群组形 (X+Y)* 遇 IPv4 列后混合空白串「␠␠^I」不回溯
    # → 永假（实测 0）；跨 token 尾锚一律取 .* 形（DFA 左最长可解，实测 1）。
    if grep -Eq "^${dvl}[[:space:]]+[0-9]+[[:space:]]+3[[:space:]]+[^[:space:]]" "$D/gid3-$h.txt" \
       && ! grep -Eq "^${dvl}[[:space:]]+[0-9]+[[:space:]]+3[[:space:]]+0000(:0000){7}" "$D/gid3-$h.txt" \
       && grep -Eq "^${dvl}[[:space:]]+[0-9]+[[:space:]]+3[[:space:]]+[^[:space:]].*[[:space:]]v2[[:space:]]" "$D/gid3-$h.txt"; then
      g3=$((g3+1))
    fi
  done
  log "gid3@$H 非空RoCEv2=$g3/4（严格期望IP比对在 fabricctl F05，本处独立计数复核）"
  [ "$g3" = 4 ] || { log "RED @$H：GID3 $g3/4（明细见 $D/gid3-$h.txt）"; red=1; }
done

if [ "$red" = 0 ]; then
  log "== fabric 门全绿（四机 F00-F10[03/04 F10 豁免政策内] + hairpin4/4 + tc≥2 + GID3 4/4）=="
  echo "FABRIC-GATE-PASS"
  exit 0
else
  log "== fabric 门红（fail-closed：禁起服；明细上方+ $D/）=="
  echo "FABRIC-GATE-FAIL"
  exit 1
fi
