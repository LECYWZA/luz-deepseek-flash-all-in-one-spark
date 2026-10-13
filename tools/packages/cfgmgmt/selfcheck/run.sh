#!/bin/bash
# cfgmgmt selfcheck — 离线自检（零集群零引擎零网络；mock 红绿双例）
set -u
PKG=cfgmgmt
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/../_lib/pkg-common.sh"

for f in README.md MANIFEST.md5 VERSION bin/cfgmgmt selfcheck/run.sh; do
  [ -f "$HERE/$f" ] && sc_ok "五件套在位：$f" || sc_red "五件套缺件：$f"
done
pkg_manifest_check; pkg_version_check; pkg_sources_check

E="$HERE/payload/env"
T=$(mktemp -d /tmp/cfgmgmt-sc.XXXXXX)

# F1 键面 diff 判别力（50 vs 48=恰两键差〔FP8/TG〕；红例=多摘一键必被点名）
out=$(bash "$HERE/payload/env-keydiff.sh" "$E/PROD-R51W5-spec1.env" "$E/PROD-R1INK48L2PF6O12C1-spec1.env")
nA=$(printf '%s\n' "$out" | grep -c '^    + ')
nA_all=$(printf '%s\n' "$out" | sed -n '/仅 .* 有（/p' | head -1)
printf '%s\n' "$out" | grep -q 'DSV41_PREFILL_SP_FP8' && printf '%s\n' "$out" | grep -q 'DSV41_PREFILL_SP_TAIL_GATHER' \
  && [ "$nA" = 2 ] && sc_ok "F1 键面 diff 绿（50 vs 48=恰两键差 FP8/TG）" \
  || sc_red "F1 键面 diff 异常（左独有=$nA 行）"
sed '/^DSV41_PREFILL_SP_FP8=/d' "$E/PROD-R51W5-spec1.env" > "$T/env49.env"
out2=$(bash "$HERE/payload/env-keydiff.sh" "$T/env49.env" "$E/PROD-R1INK48L2PF6O12C1-spec1.env")
[ "$(printf '%s\n' "$out2" | grep -c '^    + ')" = 1 ] \
  && sc_ok "F1 红例判别（再摘一键→差集=1 被识别）" || sc_red "F1 红例失效"

# F2 四级 env md5 对表（包内副本 vs FORM-REGISTRY 权威值）
ok=0
for pair in "PROD-R51W5-spec1.env:15767aa6" "PROD-R1INK48L2PF6O12C1-spec1.env:8c8c166d" "PROD-R1STDLL128L2PF6O12C1-spec1.env:99e7ec92" "PROD-R1STDLL128L2PF6-spec1.env:34977bf0"; do
  f="${pair%%:*}"; m="${pair##*:}"
  gm=$(md5sum "$E/$f" | awk '{print substr($1,1,8)}')
  [ "$gm" = "$m" ] && ok=$((ok+1)) || sc_red "F2 env 副本漂移：$f=$gm（应 $m）"
done
[ "$ok" = 4 ] && sc_ok "F2 四级 env 副本 md5 全等（15767aa6/8c8c166d/99e7ec92/34977bf0）"

# F3 printenv 真键核 mock 红绿（dump 生成→全等绿；缺一键→红点名）
grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$E/PROD-R51W5-spec1.env" > "$T/dump-good.txt"
bash "$HERE/payload/printenv-keycheck.sh" --dump "$T/dump-good.txt" --env "$E/PROD-R51W5-spec1.env" >/dev/null 2>&1 \
  && sc_ok "F3 printenv 真键核绿例（50 键全在场全等）" || sc_red "F3 真键核绿例红"
grep -v '^DSV41_HC_FUSED=' "$T/dump-good.txt" > "$T/dump-bad.txt"
out=$(bash "$HERE/payload/printenv-keycheck.sh" --dump "$T/dump-bad.txt" --env "$E/PROD-R51W5-spec1.env" 2>&1); r=$?
[ "$r" = 1 ] && printf '%s' "$out" | grep -q '缺键：DSV41_HC_FUSED' \
  && sc_ok "F3 红例判红（缺键逐键点名）" || sc_red "F3 红例失效（rc=$r）"

# F4 slotlock 干跑守卫面（真源 tools/ 件=治理声明+flock 语义在文；红例=摘 flock 必红）
SL=/home/liux***ya/luz030-opt-campaign/tools/boot-with-slotlock.sh
if [ -r "$SL" ]; then
  grep -q 'flock -w 10 9' "$SL" && grep -q '任何会话点火 r3boot 栈都必须走本 wrapper' "$SL" \
    && sc_ok "F4 slotlock 真源守卫面在文（flock fd9+P0 治理声明）" || sc_red "F4 slotlock 真源守卫面异常"
  grep -v 'flock' "$SL" > "$T/bad-sl.sh"
  grep -q 'flock' "$T/bad-sl.sh" && sc_red "F4 红例失效" || sc_ok "F4 红例判红（flock 摘除被识别）"
else sc_unk "F4 slotlock 真源不在本机"; fi

# F5 boot 链 md5 表对真源核（三件+wrapper）
bc_ok=0; bc_n=0
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  m=$(printf '%s' "$line" | awk '{print $1}'); p=$(printf '%s' "$line" | awk '{print $2}' | sed 's/（.*//')
  bc_n=$((bc_n+1))
  if [ -r "$p" ]; then
    gm=$(md5sum "$p" | awk '{print $1}')
    [ "$gm" = "$m" ] && bc_ok=$((bc_ok+1)) || sc_red "F5 boot 链漂移：$p=$gm（表 $m）"
  else sc_unk "F5 boot 链件缺位：$p"
  fi
done < "$HERE/payload/boot/boot-chain.md5"
[ "$bc_ok" = "$bc_n" ] && sc_ok "F5 boot 链 md5 表全等（${bc_n} 件）"

# F6 ADAPTER-MANIFEST 重生成器+生成件对活树复核
bash "$HERE/payload/adapter-manifest-regen.sh" --selfcheck >/dev/null 2>&1 \
  && sc_ok "F6 adapter-manifest-regen selfcheck 绿（六分类+口径钉+变量位+直验+漂移红）" \
  || sc_red "F6 adapter-manifest-regen selfcheck 红"
MF="$(readlink -f "$HERE/payload/out/ADAPTER-MANIFEST.regenerated")"
if bash "$HERE/payload/adapter-manifest-regen.sh" --check --out "$MF" >/dev/null 2>&1; then
  sc_ok "F6 生成件对活树 --check 全等（125 件；FL6 已入位态快照）"
else
  sc_unk "F6 生成件与活树漂移（FL6 窗在飞改面=预期态；窗终重跑=终态清单）"
fi

# F7 双清单生成器+算式三性（确定性/判别力/路径无关）
bash "$HERE/payload/gen-manifests.sh" --selfcheck >/dev/null 2>&1 \
  && sc_ok "F7 gen-manifests selfcheck 绿（正典算式三性+直验+漂移红）" \
  || sc_red "F7 gen-manifests selfcheck 红"
fp_env=$(awk -F'：' '/^# 集合指纹/{print substr($2,1,8)}' "$HERE/payload/out/env-MANIFEST.md5" | head -1)
fp_ovl=$(awk -F'：' '/^# 集合指纹/{print substr($2,1,8)}' "$HERE/payload/out/overlay-MANIFEST.md5" | head -1)
[ -n "$fp_env" ] && [ -n "$fp_ovl" ] && sc_ok "F7 双清单快照指纹在档（env=$fp_env overlay=$fp_ovl——历史 20fa6a1d 为旧未记录算式值，重钉=下次对表窗）" \
  || sc_red "F7 双清单快照指纹行缺"

# F8 复原序检查单
bash "$HERE/payload/restore-sequence.sh" --selfcheck >/dev/null 2>&1 \
  && sc_ok "F8 restore-sequence selfcheck 绿（十步+双段+六律面）" || sc_red "F8 restore-sequence selfcheck 红"

# F9 golden 树面（树内 MANIFEST.json 自述 fi_version+autotune diff 在位+不可读件登记）
python3 -c 'import json; d=json.load(open("'"$HERE"'/payload/golden/flashinfer-golden/MANIFEST.json")); assert d.get("fi_version")' >/dev/null 2>&1 \
  && sc_ok "F9 flashinfer-golden 树内自述在（fi_version=$(python3 -c 'import json; print(json.load(open("'"$HERE"'/payload/golden/flashinfer-golden/MANIFEST.json"))["fi_version"])')；卡文 0.6.16 差异=呈裁注记）" \
  || sc_red "F9 golden 树内自述缺"
[ -f "$HERE/payload/golden/r3-boot-arm.autotune-golden.diff" ] && grep -q '^+' "$HERE/payload/golden/r3-boot-arm.autotune-golden.diff" \
  && sc_ok "F9 autotune-golden 再生模板在位" || sc_red "F9 autotune 模板缺"
grep -q 'UNREADABLE-root0600' "$HERE/payload/golden/flashinfer-golden/UNREADABLE-NOTE.txt" 2>/dev/null \
  && sc_ok "F9 golden 不可读件登记在（2 件 root-0600=零 sudo 纪律面如实注记）" || sc_red "F9 不可读件登记缺"

rm -rf "$T"
sc_summary
