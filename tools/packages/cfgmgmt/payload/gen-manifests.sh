#!/bin/bash
# gen-manifests.sh — env/overlay 双清单生成器（TOOLS31 §二 P5-5；CODE31 P2-8 算式闭合件）
#
# 【为什么存在】集合指纹 20fa6a1d（overlay）/20753511 族（W5 面）算式未入仓档
#   （CODE31 六法未复现——boot 侧以挂载面路径计算，未记录）。本件**钉正典算式**：
#
#   集合指纹 = ( LC_ALL=C find <dir> -type f -print0 | LC_ALL=C sort -z | xargs -0 md5sum | md5sum ) 前 8 位
#
#   （=adapter-sync 活清单法+pkg-common.pkg_fingerprint 同源设计：路径无关纯内容序）
#   历史值 20fa6a1d=旧未记录算式产物，**不再复现义务**——下一次对表窗以本算式重算重钉
#   （新旧值过渡注记入 TOOL-ANCHORS；呈裁承载）。
# 【双清单】env 树（~/migrate-assets/dsv41/env）+overlay 树（~/migrate-assets/v4vl/
#   sglang-overlay.o12c1-prod）各产 MANIFEST.md5（md5sum -c 直验）+集合指纹行。
# 【出口】0=生成/1=红/2=用法错/3=源缺位。
# 用法：gen-manifests.sh env|overlay [--dir <D>] [--out <F>] | --selfcheck
set -u
KIND="${1:-}"
DIR=""; OUT=""
case "$KIND" in
  env)     DIR="/home/liux***ya/migrate-assets/dsv41/env" ;;
  overlay) DIR="/home/liux***ya/migrate-assets/v4vl/sglang-overlay.o12c1-prod" ;;
  --selfcheck) exec bash "$0" selfcheck-run "$0" ;;
  selfcheck-run) S="$2"; shift 2; sc=1; DIR="" ;;
  *) echo "用法：$0 env|overlay [--dir D] [--out F] | --selfcheck" >&2; exit 2 ;;
esac
if [ "${sc:-0}" != 1 ]; then
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) DIR="${2:?}"; shift 2 ;;
      --out) OUT="${2:?}"; shift 2 ;;
      *) echo "用法错：$1" >&2; exit 2 ;;
    esac
  done
  [ -d "$DIR" ] || { echo "[genmf][RED] 源目录缺位：$DIR" >&2; exit 3; }
fi

set_fp() {  # 正典集合指纹算式（本件钉定；前 8 位）
  ( cd "$1" && LC_ALL=C find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r md5sum | md5sum | awk '{print substr($1,1,8)}' )
}

gen_one() {  # gen_one <dir> <out 目标（空=stdout）>
  local d="$1" o="$2" fp n now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ); fp=$(set_fp "$d")
  {
    echo "# MANIFEST.md5（$kind 树；生成 $now；源=$d）"
    echo "# 集合指纹（正典算式=LC_ALL=C find -type f|sort -z|xargs -0 md5sum|md5sum 前 8 位）：${fp}"
    echo "# 律：树内容任何变更→同日重生成+TOOL-ANCHORS 指纹行更新（三联动）"
    ( cd "$d" && LC_ALL=C find . -type f -print0 | LC_ALL=C sort -z | xargs -0 md5sum )
  } > "${o:-/dev/stdout}"
  n=$(cd "$d" && find . -type f | wc -l)
  [ -n "$o" ] && echo "[genmf] 已生成 $kind 清单：$o（$n 件，集合指纹=$fp）" \
              || echo "[genmf] $kind 清单（stdout）：$n 件，集合指纹=$fp"
}

if [ "${sc:-0}" = 1 ]; then
  rc=0; T=$(mktemp -d /tmp/genmf-sc.XXXXXX)
  mkdir -p "$T/tree/sub"; printf 'a' > "$T/tree/f1"; printf 'b' > "$T/tree/sub/f2"
  # T1 确定性：同树两算必等
  h1=$(set_fp "$T/tree"); h2=$(set_fp "$T/tree")
  [ -n "$h1" ] && [ "$h1" = "$h2" ] && echo "[genmf][OK] T1 集合指纹确定性（$h1）" || { echo "[genmf][RED] T1 FAIL"; rc=1; }
  # T2 判别力：内容一字节变必变指纹
  printf 'c' >> "$T/tree/f1"; h3=$(set_fp "$T/tree")
  [ "$h3" != "$h1" ] && echo "[genmf][OK] T2 判别力（变→$h3）" || { echo "[genmf][RED] T2 FAIL"; rc=1; }
  # T3 路径无关性：同内容树在别处=同指纹（正典算式核心性质——历史 20fa6a1d 不可复现根因）
  cp -r "$T/tree" "$T/tree2"; h4=$(set_fp "$T/tree2")
  [ "$h4" = "$h3" ] && echo "[genmf][OK] T3 路径无关性（挂载面/仓内两处同值——重钉可复现）" || { echo "[genmf][RED] T3 FAIL（$h4≠$h3）"; rc=1; }
  # T4 生成件 md5sum -c 直验
  bash "$S" env --dir "$T/tree" --out "$T/MF" >/dev/null 2>&1
  ( cd "$T/tree" && md5sum -c <(grep -v '^#' "$T/MF") ) >/dev/null 2>&1 && echo "[genmf][OK] T4 md5sum -c 直验绿" || { echo "[genmf][RED] T4 FAIL"; rc=1; }
  # T5 红例：列内件内容漂移后旧清单必红（md5sum -c 语义=检列内失配/缺件；**新增件不检**
  #    ——新增面由「清单行数 vs find|wc -l 计数比对」承载，见头注算式行同律）
  printf 'z' > "$T/tree/f1"
  ( cd "$T/tree" && md5sum -c <(grep -v '^#' "$T/MF") ) >/dev/null 2>&1 && { echo "[genmf][RED] T5 红例失效"; rc=1; } || echo "[genmf][OK] T5 红例判红（列内件漂移=校验失败）"
  rm -rf "$T"; exit "$rc"
fi

kind="$KIND"
if [ -n "${OUT:-}" ]; then gen_one "$DIR" "$OUT"; else gen_one "$DIR" ""; fi
