#!/usr/bin/env bash
# endpoint_lint.sh — 测试脚本 8899 生产端口字面量扫描（GATE-MATRIX L18；QA-GATEHARDEN 20261005）
#
# 法源：r3-boot-arm.sh:15（测试窗固定 8898，避开 concurrency-proxy→8899 活生产转发路径，㉑/㉕
#       防污染）+ PROD-RS-GATE-RUNBOOK:14（8899 生产动作=用户令）+ README-RELEASE §3（QA 人工窗）。
# 规则：非注释/非白名单标记行出现 8899 字面量=RED（禁止把测试流量打到 8899 生产面）。
# 白名单（缺省全关，--allow 显式开）：
#   comment      纯注释行（# 开头）提及 8899 的纪律/文档说明；
#   marker       行尾带显式 opt-in 标记 `# qa-gate:8899-allowed`（切产/复原验证步专用，留痕可审计）。
# 8898（测试靴）/8001（只读网关）出现仅 INFO 计数（口径登记，不红）。
# 用法: endpoint_lint.sh [--allow comment,marker] <script> [more …]
#   出口 0=干净 1=RED 2=用法错（fail-closed：不可读=在场=红）。
set -uo pipefail
PROG="$(basename "$0")"
ALLOW=""
FILES=()

usage() { echo "用法: $PROG [--allow comment,marker] <script> […]  出口 0=干净 1=RED 2=用法错" >&2; exit 2; }
while [ $# -ge 1 ]; do
  case "$1" in
    --allow) [ $# -ge 2 ] || usage; ALLOW="$2"; shift 2 ;;
    -*) usage ;;
    *) FILES+=("$1"); shift ;;
  esac
done
[ "${#FILES[@]}" -ge 1 ] || usage
allow_comment=0; allow_marker=0
[ -z "$ALLOW" ] || for a in ${ALLOW//,/ }; do
  case "$a" in
    comment) allow_comment=1 ;;
    marker)  allow_marker=1 ;;
    *) printf '[endpoint-lint][RED] 未知白名单项 %s（fail-closed）\n' "$a" >&2; exit 1 ;;
  esac
done

red=0
for f in "${FILES[@]}"; do
  if [ ! -r "$f" ]; then
    printf '[endpoint-lint][RED] %s 不可读（fail-closed：不可读=在场=红）\n' "$f" >&2
    red=1
    continue
  fi
  n8898=$(grep -c '8898' "$f" || true); n8898=${n8898:-0}
  n8001=$(grep -c '8001' "$f" || true); n8001=${n8001:-0}
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    case "$line" in *8899*) ;; *) continue ;; esac      # 只看含 8899 的行
    if [ "$allow_marker" = 1 ]; then
      case "$line" in *'# qa-gate:8899-allowed'*) printf '  [SKIP] %s:%d 显式 opt-in 标记（留痕）\n' "$f" "$lineno"; continue ;; esac
    fi
    if [ "$allow_comment" = 1 ]; then
      case "$line" in
        \#*|*[[:space:]]\#*)
          case "$line" in
            *零流量*|*禁*|*纪律*|*复原*|*GO*|*人工窗*|*生产面*)
              printf '  [SKIP] %s:%d 注释纪律行\n' "$f" "$lineno"; continue ;;
          esac ;;
      esac
    fi
    printf '[endpoint-lint][RED] %s:%d 出现 8899 字面量（生产端口；测试流量禁打——改 8898 或加显式 opt-in 标记留痕）：%-.60s\n' "$f" "$lineno" "$line" >&2
    red=1
  done < "$f"
  printf '[endpoint-lint][INFO] %s 8898×%s（测试靴口径）/8001×%s（只读网关口径）\n' "$f" "$n8898" "$n8001"
done

if [ "$red" = 0 ]; then
  echo "[endpoint-lint] 干净（${#FILES[@]} 件）：8899 白名单外零引用（GATE-MATRIX L18）" >&2
  exit 0
fi
echo "[endpoint-lint] RED：8899 生产面引用在案——禁止上岗（GATE-MATRIX L18）" >&2
exit 1
