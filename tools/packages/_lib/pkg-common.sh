#!/bin/bash
# pkg-common.sh — 五工具包共用底座（TOOLS31-PACKAGE-PLAN-20261012 §一/§四.2 统一化承载）
#
# 【为什么存在】五包（fabric-net/selfdiag/selfheal/gateway/cfgmgmt）的 bin/<pkg> 入口与
#   selfcheck 需要同一套纪律：三态退出码（0 绿/1 红/2 无法判=ANCHOR-UNKNOWN 语义）、
#   MANIFEST md5sum -c 自验、VERSION 汇总指纹对表、在役源锚对表（同日更新律的机器执法）。
#   本件与 verdict.sh（诊断出口 JSON 三字段族）配对：verdict 管「诊断面」出口，
#   本件管「包面」出口——两处退出码语义一致（红优先于无法判）。
#
# 【指纹算式（包级汇总指纹；与 TOOL-ANCHORS 「集合指纹算式」行同源设计）】
#   LC_ALL=C find . -type f ! -name VERSION -print0 | LC_ALL=C sort -z | xargs -0 md5sum | md5sum
#   取前 8 位。排除 VERSION 自身（防自指）；不排除即锚（MANIFEST 覆盖一切非 VERSION 件）。
#
# 【用法】（bin/<pkg> 内）：
#   source "$(dirname "$0")/../_lib/pkg-common.sh"   # 包内相对；或绝对路径
#   PKG=fabric-net
#   pkg_manifest_check          # MANIFEST.md5 md5sum -c
#   pkg_version_check           # VERSION FINGERPRINT 对表
#   pkg_sources_check           # selfcheck/sources.tsv 在役源对表
#   sc_ok "…"; sc_red "…"; sc_unk "…"
#   sc_summary                  # 汇总打印+退出（0/1/2）
#
# 【红线】本件零集群零引擎零网络零 sudo；一切检查=案头/host 只读面。
set -u

SC_RC_RED=0; SC_RC_UNK=0; SC_RC_OKN=0

sc_ok()  { echo "[$PKG][OK] $*";  SC_RC_OKN=$((SC_RC_OKN+1)); }
sc_red() { echo "[$PKG][RED] $*"; SC_RC_RED=$((SC_RC_RED+1)); }
sc_unk() { echo "[$PKG][UNKNOWN] $*"; SC_RC_UNK=$((SC_RC_UNK+1)); }

sc_summary() {  # 汇总三态并按「红优先于无法判」退出（与 _lib/verdict.sh 判序一致）
  echo "[$PKG] selfcheck 汇总：OK=${SC_RC_OKN} RED=${SC_RC_RED} UNKNOWN=${SC_RC_UNK}"
  if   [ "${SC_RC_RED}" -gt 0 ]; then exit 1
  elif [ "${SC_RC_UNK}" -gt 0 ]; then exit 2
  else exit 0; fi
}

pkg_root() {  # pkg_root <名> → 包根绝对路径（battle repo tools/packages/<名>）
  local d="${BASH_SOURCE[0]%/*}"; echo "$(cd "$d/../$1" && pwd)"
}

pkg_fingerprint() {  # 重算包级汇总指纹（前 8 位；算式见头注；排除 __pycache__/*.pyc——
  local root; root=$(pkg_root "$PKG")     # .gitignore 同口径：pyc=运行残留非包内容）
  ( cd "$root" && LC_ALL=C find . -type f ! -name VERSION ! -path '*__pycache__*' ! -name '*.pyc' -print0 \
      | LC_ALL=C sort -z | xargs -0 -r md5sum | md5sum | awk '{print substr($1,1,8)}' )
}

pkg_manifest_check() {  # MANIFEST.md5 md5sum -c（# 注释行 GNU md5sum 容忍=先例实测）
  local root; root=$(pkg_root "$PKG")
  if [ ! -f "$root/MANIFEST.md5" ]; then sc_red "MANIFEST.md5 缺件（五件套不齐）"; return; fi
  local out rc
  out=$( cd "$root" && md5sum -c MANIFEST.md5 2>&1 ); rc=$?
  if [ "$rc" = 0 ]; then sc_ok "MANIFEST md5sum -c 全绿（$(grep -vc '^#' "$root/MANIFEST.md5") 件）"
  else sc_red "MANIFEST md5sum -c 红（rc=$rc）"; echo "$out" | sed 's/^/    /'; fi
}

pkg_version_check() {  # VERSION 汇总指纹对表（漂移=红=包内容被改而 VERSION 未同日更新）
  local root; root=$(pkg_root "$PKG")
  if [ ! -f "$root/VERSION" ]; then sc_red "VERSION 缺件（五件套不齐）"; return; fi
  local want got
  want=$(awk -F= '$1=="FINGERPRINT"{print $2}' "$root/VERSION")
  got=$(pkg_fingerprint)
  if [ -z "$want" ]; then sc_red "VERSION 无 FINGERPRINT 行（五件套规范违约）"
  elif [ "$want" = "$got" ]; then sc_ok "VERSION 汇总指纹对表绿（$got）"
  else sc_red "VERSION 汇总指纹漂移（VERSION=$want 实算=$got）——TOOL-ANCHORS 同日更新律：改包内容必须同步重生成 VERSION/MANIFEST"; fi
}

pkg_sources_check() {  # selfcheck/sources.tsv：包件 ↔ 在役源 对表（TSV：包相对路径<TAB>源绝对路径<TAB>打包时源 md5）
  local root tsv; root=$(pkg_root "$PKG"); tsv="$root/selfcheck/sources.tsv"
  if [ ! -f "$tsv" ]; then sc_unk "sources.tsv 缺件（在役源对表面未建——无法判在役漂移）"; return; fi
  local p src want got n=0
  while IFS=$'\t' read -r p src want; do
    case "$p" in ''|'#'*) continue ;; esac
    n=$((n+1))
    if [ ! -e "$src" ]; then sc_unk "在役源缺位（$p ← $src 不在本机）——烘焙机/其余三机=正常态，01 权威机缺位=呈报"
      continue; fi
    if [ -d "$src" ]; then got=$( pkg_tree_md5 "$src" )
    else got=$(md5sum "$src" | awk '{print substr($1,1,8)}'); fi
    if [ "$got" = "$want" ]; then sc_ok "在役源锚对表绿：$p=$got"
    else sc_red "在役源漂移：$p（源 $src 现=$got 打包锚=$want）——包须同步吸收（同日更新律）"; fi
  done <"$tsv"
  [ "$n" -gt 0 ] || sc_unk "sources.tsv 空表（零登记）"
}

pkg_tree_md5() {  # 目录级指纹（与 cfgmgmt gen-manifests.sh 集合指纹同算式；前 8 位）
  ( cd "$1" && LC_ALL=C find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r md5sum | md5sum | awk '{print substr($1,1,8)}' )
}

# ── 本件自检（被 packages 级自检复用；红绿双例）──
pkg_common_selfcheck() {
  PKG=_lib
  local T rc=0
  T=$(mktemp -d /tmp/pkgcommon-selftest.XXXXXX) || return 1
  # T1 三态汇总裁决：纯绿→0
  ( SC_RC_RED=0; SC_RC_UNK=0; SC_RC_OKN=0; sc_ok x >/dev/null; sc_summary ) >/dev/null 2>&1
  [ $? = 0 ] && echo "[pkg-common][OK] T1 纯绿汇总退出 0" || { echo "[pkg-common][RED] T1 FAIL"; rc=1; }
  # T2 红→1
  ( SC_RC_RED=1; SC_RC_UNK=1; SC_RC_OKN=0; sc_summary ) >/dev/null 2>&1
  [ $? = 1 ] && echo "[pkg-common][OK] T2 红优先退出 1" || { echo "[pkg-common][RED] T2 FAIL"; rc=1; }
  # T3 仅无法判→2
  ( SC_RC_RED=0; SC_RC_UNK=2; SC_RC_OKN=0; sc_summary ) >/dev/null 2>&1
  [ $? = 2 ] && echo "[pkg-common][OK] T3 仅 UNKNOWN 退出 2" || { echo "[pkg-common][RED] T3 FAIL"; rc=1; }
  # T4 指纹确定性：同树两次算必相等
  mkdir -p "$T/tree/sub" && echo a > "$T/tree/f1" && echo b > "$T/tree/sub/f2"
  local h1 h2
  h1=$(pkg_tree_md5 "$T/tree"); h2=$(pkg_tree_md5 "$T/tree")
  [ -n "$h1" ] && [ "$h1" = "$h2" ] && echo "[pkg-common][OK] T4 集合指纹确定性（$h1）" || { echo "[pkg-common][RED] T4 FAIL"; rc=1; }
  # T5 指纹判别力：改一字节必变
  echo c >> "$T/tree/f1"
  local h3; h3=$(pkg_tree_md5 "$T/tree")
  [ -n "$h3" ] && [ "$h3" != "$h1" ] && echo "[pkg-common][OK] T5 指纹判别力（内容变→$h3）" || { echo "[pkg-common][RED] T5 FAIL"; rc=1; }
  rm -rf "$T"; return "$rc"
}
