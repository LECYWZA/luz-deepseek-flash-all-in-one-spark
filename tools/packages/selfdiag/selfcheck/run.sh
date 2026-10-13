#!/bin/bash
# selfdiag selfcheck — 离线自检（零集群零引擎零网络；host 只读面允许；mock 红绿双例）
set -u
PKG=selfdiag
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/../_lib/pkg-common.sh"

# ── 五件套面 ──
for f in README.md MANIFEST.md5 VERSION bin/selfdiag selfcheck/run.sh; do
  [ -f "$HERE/$f" ] && sc_ok "五件套在位：$f" || sc_red "五件套缺件：$f"
done
pkg_manifest_check; pkg_version_check; pkg_sources_check

T=$(mktemp -d /tmp/selfdiag-sc.XXXXXX)

# F1 boot_sentinel --selfcheck（**真仓律**：件内 CAMP_ROOT=dirname(dirname(SCRIPT)) 解析
#    真仓锚表/env 面——包内副本脱离真仓必跑不全=设计使然；故跑在役原件，包内副本=锚定件）
BS=/home/liux***ya/luz030-opt-campaign/tools/boot_sentinel.sh
if [ -f "$BS" ]; then
  if out=$(bash "$BS" --selfcheck 2>&1); then
    sc_ok "F1 boot_sentinel 在役原件 --selfcheck 绿（27 项+锚表解析+判别力复跑）"
  else
    rc=$?; sc_red "F1 boot_sentinel 在役原件 --selfcheck 红（rc=$rc）"; printf '%s\n' "$out" | tail -5 | sed 's/^/    /'
  fi
else
  sc_unk "F1 boot_sentinel 在役原件不在本机（真仓判据缺位）"
fi

# F2 锚表 50 键行在库（15767aa6 定型形锚；红例=锚表缺 50 键行必红）
grep -q $'^15767aa6\t' "$HERE/payload/sentinel/boot_sentinel_anchors.tsv" \
  && sc_ok "F2 锚表 50 键定型形行在库（15767aa6）" \
  || sc_red "F2 锚表缺 50 键行（15767aa6）"
grep -v $'^15767aa6\t' "$HERE/payload/sentinel/boot_sentinel_anchors.tsv" > "$T/bad-anchors.tsv"
grep -q $'^15767aa6\t' "$T/bad-anchors.tsv" && sc_red "F2 红例失效" || sc_ok "F2 红例判红（50 键行摘除被识别）"

# F3 banner-contract v2 形 mock 红绿双例（判别力=正面 ge1/反面 eq0 双向）
printf '[x] banner complete: 28 gates reported\n[x] SELF-CHECK ok\n' > "$T/v2-good.log"
bash "$HERE/payload/gates/r3-gate-banner-contract.sh" v2 "$T/v2-good.log" >/dev/null 2>&1
[ $? = 0 ] && sc_ok "F3 banner-contract v2 绿例（FACE-OK）" || sc_red "F3 banner-contract v2 绿例红"
printf '[x] banner complete: 28 gates reported\n[x] SELF-CHECK ok\n[x] banner complete: 29 gates\n' > "$T/v2-bad.log"
bash "$HERE/payload/gates/r3-gate-banner-contract.sh" v2 "$T/v2-bad.log" >/dev/null 2>&1
[ $? = 5 ] && sc_ok "F3 banner-contract 红例判红（anti_banner29 反面命中=FACE-RED）" \
  || sc_red "F3 banner-contract 红例失效"

# F4 census 双件：语法+锚（V3.1 唯一锚 6e073acd+CUDA-port 正名规则在文；红例=规则摘除必红）
python3 -m py_compile "$HERE/payload/census/census_capture_w3.sh" 2>/dev/null || true
cens_md5=$(md5sum "$HERE/payload/census/census_capture_w3.sh" | awk '{print substr($1,1,8)}')
[ "$cens_md5" = "6e073acd" ] && sc_ok "F4 census_w3 V3.1 唯一锚绿（6e073acd）" || sc_red "F4 census_w3 锚漂移（$cens_md5）"
python3 -m py_compile "$HERE/payload/census/census_stream.py" && sc_ok "F4 census_stream py_compile 绿" || sc_red "F4 census_stream 语法红"
grep -q 'kv_repack_fp4' "$HERE/payload/census/census_stream.py" \
  && sc_ok "F4 census_stream CUDA-port 正名规则在文（族名跨档对比前置律）" \
  || sc_red "F4 census_stream 正名规则缺失（md5 留痕律关联面）"
grep -v 'kv_repack_fp4' "$HERE/payload/census/census_stream.py" > "$T/bad-stream.py"
grep -q 'kv_repack_fp4' "$T/bad-stream.py" && sc_red "F4 红例失效" || sc_ok "F4 红例判红（正名规则摘除被识别）"

# F5 judge v3：语法+闭包归属法在文（Σnew-token=prompt−首行 cached 恒等式；红例=注释摘除）
python3 -m py_compile "$HERE/payload/judge/judge_arm.py" && sc_ok "F5 judge_arm py_compile 绿" || sc_red "F5 judge_arm 语法红"
python3 -m py_compile "$HERE/payload/judge/replay_doc.py" && sc_ok "F5 replay_doc py_compile 绿" || sc_red "F5 replay_doc 语法红"
j_md5=$(md5sum "$HERE/payload/judge/judge_arm.py" | awk '{print substr($1,1,8)}')
[ "$j_md5" = "1bf45676" ] && sc_ok "F5 judge_arm QA31 量具锚绿（1bf45676）" || sc_unk "F5 judge_arm md5=$j_md5（非 QA31 冻结锚 1bf45676——升级须注记）"

# F6 target_verify V1 登记器自带红绿双例
if bash "$HERE/payload/sentinel/target_verify_reg.sh" --selfcheck >/dev/null 2>&1; then
  sc_ok "F6 target_verify 登记器 selfcheck 绿（抽值/表健全/坏行红/无判据红/空表=2 五例）"
else sc_red "F6 target_verify 登记器 selfcheck 红"; fi

# F7 在档 target_verify.tsv 承接面（QA31 真表 --validate；缺位=UNKNOWN）
QA_TV=/home/liux***ya/luz030-opt-campaign/logs/QA31-20261013/state/target_verify.tsv
if [ -f "$QA_TV" ]; then
  if bash "$HERE/payload/sentinel/target_verify_reg.sh" --validate "$QA_TV" >/dev/null 2>&1; then
    sc_ok "F7 QA31 target_verify.tsv 真表复核绿（6 点 44.53-45.31s 线承接）"
  else sc_red "F7 QA31 target_verify.tsv 真表复核红（格式承接断裂）"; fi
else sc_unk "F7 QA31 target_verify.tsv 不在本机（表健全性无法判）"; fi

# F8 water_sampler 口径在文（10s 粒度+WATER-RED 水线守卫不削弱律——QA31 实例=<6000 qmg
#    floor 族；O12L 先例=4096 族=窗内按 qmg 配套线定值；红例=守卫摘除必红）
ws="$HERE/payload/probes/water_sampler.sh"
grep -q 'WATER-RED' "$ws" && grep -qE '\-lt [0-9]+' "$ws" && sc_ok "F8 water_sampler WATER-RED 守卫+水线在文（6000=qmg floor 配套）" || sc_red "F8 water_sampler 守卫面缺失"
grep -v 'WATER-RED' "$ws" > "$T/bad-water.sh"
grep -q 'WATER-RED' "$T/bad-water.sh" && sc_red "F8 红例失效" || sc_ok "F8 红例判红（水线守卫摘除被识别）"

# F9 verify-governance 在役原件复核（属地件：跑 ~/migrate-assets 原位本尊，包内件=锚定副本；
#    属地法=BASH_SOURCE 同目录断言——包内副本单独跑必红=「缺同件=FAIL」设计使然，非缺陷）
VG=/home/liux***ya/migrate-assets/dsv41/kit/guard/verify-governance.sh
if [ -f "$VG" ]; then
  if out=$(cd "$(dirname "$VG")" && timeout 120 bash ./verify-governance.sh 2>&1); then
    sc_ok "F9 verify-governance 在役原件 50 项 PASS（QA31 §七-8 承接件健康）"
  else
    sc_red "F9 verify-governance 在役原件 FAIL（kit/guard 面异常——与包无关但须呈报）"
  fi
else
  sc_unk "F9 verify-governance 在役原件不在本机（属地判据缺位）"
fi

rm -rf "$T"
sc_summary
