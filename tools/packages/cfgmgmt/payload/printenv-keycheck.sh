#!/bin/bash
# printenv-keycheck.sh — printenv 真键核（容器实况 dump 对 env 规格件逐键核；TOOLS31 §二 P5-1）
#
# 【为什么存在】QA31 §六/§七「printenv 真键核」是配置持久化的直证面——本件把人工 grep
#   口径脚本化：env 规格件每键必须在容器 printenv dump 中在场且值等；docker -e 注入序
#   last-wins 律下 printenv=生效真值源。
# 【输入】--dump <printenv 文本>（执行窗：docker exec <head 容器> printenv > dump.txt）
#         --env  <env 规格件>
# 【出口】0=全键在场全等/1=缺键或值差（红面逐键点名）/2=文件缺位或用法错
# 【红线】只读判读件（零容器操作——dump 由窗内采集，本件纯案头比对）。
set -u
DUMP=""; ENVF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dump) DUMP="${2:?}"; shift 2 ;;
    --env)  ENVF="${2:?}"; shift 2 ;;
    *) echo "用法：$0 --dump <printenv dump> --env <env 规格件>" >&2; exit 2 ;;
  esac
done
[ -r "${DUMP:-/nonexistent}" ] || { echo "[keycheck][RED] dump 不可读（执行窗先采：docker exec <head> printenv）" >&2; exit 2; }
[ -r "${ENVF:-/nonexistent}" ] || { echo "[keycheck][RED] env 规格件不可读" >&2; exit 2; }
rc=0; n=0; miss=0; diffv=0
while IFS='=' read -r k v; do
  case "$k" in ''|'#'*) continue ;; esac
  n=$((n+1))
  pv=$(grep -m1 "^$k=" "$DUMP" | cut -d= -f2-)
  if [ -z "$pv" ] && ! grep -q "^$k=" "$DUMP"; then
    echo "[keycheck][RED] 缺键：$k（env 规格件在册，容器 printenv 缺位）"; miss=$((miss+1)); rc=1
  elif [ "$pv" != "$v" ]; then
    echo "[keycheck][RED] 值差：$k（env=$v 容器=$pv——注入序/覆盖面呈报）"; diffv=$((diffv+1)); rc=1
  fi
done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENVF")
[ "$rc" = 0 ] && echo "[keycheck][OK] 真键核绿：$n 键全在场全等（$(basename "$ENVF")）"
[ "$miss" -gt 0 ] || [ "$diffv" -gt 0 ] && echo "[keycheck] 汇总：缺键 ${miss}+值差 ${diffv}/共 $n 键"
exit "$rc"
