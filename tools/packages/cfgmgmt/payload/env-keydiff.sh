#!/bin/bash
# env-keydiff.sh — 键面 diff 工具（两 env 件逐键差集+md5 表；TOOLS31 §二 P5-1）
#
# 【为什么存在】形间比对（50 vs 48 vs 47 vs 45 键）历来靠人工 diff——本件给出机器口径：
#   键集差（左独有/右独有/值差）+两件 md5，回退链与形档案对表共用。
# 【口径】键=行首 `^[A-Za-z_][A-Za-z0-9_]*=` 切词；注释/空行不计。
# 【出口】0=有 diff（正常态，diff 面即产出）/1=文件缺位/2=用法错。判读归人（不臆造）。
# 用法：env-keydiff.sh <envA> <envB>
set -u
[ $# = 2 ] || { echo "用法：$0 <envA> <envB>" >&2; exit 2; }
A="$1" B="$2"
[ -r "$A" ] || { echo "[keydiff][RED] $A 不可读" >&2; exit 1; }
[ -r "$B" ] || { echo "[keydiff][RED] $B 不可读" >&2; exit 1; }
ka=$(mktemp); kb=$(mktemp); va=$(mktemp); vb=$(mktemp)
grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$A" | sed 's/=.*//' | LC_ALL=C sort >"$ka"
grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$B" | sed 's/=.*//' | LC_ALL=C sort >"$kb"
grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$A" >"$va"; grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$B" >"$vb"
echo "== 键面 diff：$(basename "$A")（$(wc -l <"$ka") 键，md5 $(md5sum "$A" | awk '{print substr($1,1,8)}')） vs $(basename "$B")（$(wc -l <"$kb") 键，md5 $(md5sum "$B" | awk '{print substr($1,1,8)}')）=="
onlyA=$(comm -23 "$ka" "$kb"); onlyB=$(comm -13 "$ka" "$kb")
if [ -n "$onlyA" ]; then echo "-- 仅 $(basename "$A") 有（$(printf '%s\n' "$onlyA" | grep -c .) 键）："; printf '%s\n' "$onlyA" | sed 's/^/    + /'; fi
if [ -n "$onlyB" ]; then echo "-- 仅 $(basename "$B") 有（$(printf '%s\n' "$onlyB" | grep -c .) 键）："; printf '%s\n' "$onlyB" | sed 's/^/    + /'; fi
[ -z "$onlyA" ] && [ -z "$onlyB" ] && echo "-- 键集全等（值差另核）"
echo "-- 共有键值差："
join -t$'\t' <(sed 's/=/\t/' "$va" | LC_ALL=C sort) <(sed 's/=/\t/' "$vb" | LC_ALL=C sort) 2>/dev/null \
  | awk -F'\t' '$2!=$3{printf "    ! %s：%s → %s\n",$1,$2,$3}'
echo "== md5 表："
printf '    %s  %s\n' "$(md5sum "$A" | cut -d' ' -f1)" "$A"
printf '    %s  %s\n' "$(md5sum "$B" | cut -d' ' -f1)" "$B"
rm -f "$ka" "$kb" "$va" "$vb"
exit 0
