#!/bin/bash
# regen-manifest.sh <pkg> — 五包 MANIFEST.md5 再生成器（TOOLS31 §一同日更新律工具面）
#
# 【律】包内容任何变更 ⇒ 同日重生成 MANIFEST.md5 + VERSION（指纹重算）+ TOOL-ANCHORS 行。
#   本件只做第一步+提示后两步；不自动改 TOOL-ANCHORS（人工核后手改，防误写权威表）。
#
# 【算式】LC_ALL=C sort（adapter-sync locale 教训律）；排除 VERSION（自指）与 MANIFEST.md5
#   自身（自指）；md5sum 行格式（md5sum -c 直验；# 注释头行 GNU md5sum 容忍=先例实测）。
#
# 用法：bash tools/packages/_lib/regen-manifest.sh fabric-net
set -u
LIB="$(cd "$(dirname "$0")" && pwd)"
PKG="${1:-}"
case "$PKG" in
  fabric-net|selfdiag|selfheal|gateway|cfgmgmt) ;;
  *) echo "用法：$0 <fabric-net|selfdiag|selfheal|gateway|cfgmgmt>" >&2; exit 2 ;;
esac
ROOT="$LIB/../$PKG"
cd "$ROOT" || exit 3

HDR="$(mktemp)"; BODY="$(mktemp)"   # 临时件一律在 /tmp——防包内重定向体被 find 收入（竞态实测）
{
  echo "# MANIFEST.md5 — $PKG 包逐件清单（md5sum -c 自验；# 注释行 md5sum 容忍）"
  echo "# 律：内容变更→本件同日再生成（bash tools/packages/_lib/regen-manifest.sh $PKG）"
  echo "#     +VERSION 指纹重钉 +TOOL-ANCHORS 同日更新（三联动缺一=同日更新律红）"
} >"$HDR"
LC_ALL=C find . -type f ! -name VERSION ! -name MANIFEST.md5 ! -path '*__pycache__*' ! -name '*.pyc' -print0 \
  | LC_ALL=C sort -z | xargs -0 md5sum > "$BODY"
cat "$HDR" "$BODY" > MANIFEST.md5 && rm -f "$HDR" "$BODY"

FP="$( LC_ALL=C find . -type f ! -name VERSION ! -path '*__pycache__*' ! -name '*.pyc' -print0 | LC_ALL=C sort -z | xargs -0 -r md5sum | md5sum | awk '{print substr($1,1,8)}' )"
N=$(grep -vc '^#' MANIFEST.md5)
echo "[$PKG] MANIFEST.md5 已再生成（$N 件）；构成件汇总指纹=$FP"
echo "[$PKG] 次步（人工）：VERSION 内 FINGERPRINT=$FP 重钉 + TOOL-ANCHORS 指纹行同日更新。"
