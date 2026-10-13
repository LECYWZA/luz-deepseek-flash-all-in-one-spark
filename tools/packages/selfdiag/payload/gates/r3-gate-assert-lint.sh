#!/usr/bin/env bash
# assert_lint.sh — 断言/verify 脚本反模式 lint 器（GATE-MATRIX L1/L6 支撑；QA-GATEHARDEN 20261005）
#
# 法源：INC-GOVERIFY-20261005（pipefail×grep -c 零计数退出码假红，「断言杀健康靴」族第 3 例）
#       + R1-LINE-CLOSURE-20261005 §四.1 + DOCTRINE-REGISTRY §15（判别力自检——本器反向用例
#       在 tests/run_tests.sh，喂坏输入必须因正确理由变红）。
# 规则（命中=RED，fail-closed 大声报到 stderr）：
#   A1  `grep -c …| grep -q` 管形：grep -c 零计数退出码 1 经 pipefail 污染管道 → 判据绿（计数 0）
#       时误触失败分支（L1 真身，INC-GOVERIFY 原案）；计数≥1 时 grep -q 早退亦有 SIGPIPE 竞态
#       （go_verify:44-48 正面断言同形隐患）。
#   A2  `grep -c … || FAIL/fail/exit/die/return/RED` 直连：零计数=判据绿时退出码 1 直接触发失败分支。
#   A3  赋值形 `x=$(…grep -c…)` 行尾接 `||`：赋值退出码=命令替换退出码（pipefail 污染同族）。
#   A5  curl 无 --max-time：挂起族（60min 平台 SIGTERM 斩主驱动的放大器，L6）。
#   A6  ssh 无 ConnectTimeout：挂起族同上。
# 正确形（本器自身亦遵守）：n=$(… | grep -c PAT || true); [ "$n" = 0 ] || FAIL=1
# 用法: assert_lint.sh <script.sh> [more.sh …]   出口 0=干净 1=有 RED 2=用法错（fail-closed）
set -uo pipefail
PROG="$(basename "$0")"
red=0

usage() { echo "用法: $PROG <script.sh> […]  出口 0=干净 1=RED 2=用法错" >&2; exit 2; }
report() { printf '[assert-lint][RED] %s:%s 规则%s %s\n' "$1" "$2" "$3" "$4" >&2; red=1; }
has() { printf '%s\n' "$1" | grep -q -- "$2"; }

[ $# -ge 1 ] || usage

for f in "$@"; do
  if [ ! -r "$f" ]; then
    printf '[assert-lint][RED] %s 不可读（fail-closed：不可读=在场=拒绝）\n' "$f" >&2
    red=1
    continue
  fi
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    case "$line" in ''|'#'*) continue ;; esac          # 空行/纯注释行不扫
    if has "$line" 'grep -c' && printf '%s\n' "$line" | grep -qE '\|[[:space:]]*grep -q'; then
      report "$f" "$lineno" A1 "grep -c 管入 grep -q：零计数退出码经 pipefail 误触失败分支（L1）；改 n=\$(…|grep -c …|| true) 后数值判定"
    fi
    if printf '%s\n' "$line" | grep -qE "grep -c[^;]*\|\|[[:space:]]*(FAIL|fail|exit|die|return|RED)\b"; then
      report "$f" "$lineno" A2 "grep -c 直连 ||FAIL：零计数=判据绿时退出码 1 触发失败分支；先 n=\$(…|| true) 再判"
    fi
    if printf '%s\n' "$line" | grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\$\(.*grep -c .*\)[[:space:]]*\|\|'; then
      report "$f" "$lineno" A3 "赋值捕获 grep -c 后接 ||：赋值退出码=替换退出码（pipefail 污染）；去行尾 || 或替换内 || true"
    fi
    if has "$line" 'curl' && ! has "$line" '--max-time'; then
      report "$f" "$lineno" A5 "curl 无 --max-time（挂起族=L6 SIGTERM 放大器）"
    fi
    if printf '%s\n' "$line" | grep -qE '(^|[;&|(]|[[:space:]])ssh([[:space:]]|$)' && ! has "$line" 'ConnectTimeout'; then
      report "$f" "$lineno" A6 "ssh 无 -o ConnectTimeout（挂起族，L6）"
    fi
  done < "$f"
done

if [ "$red" = 0 ]; then
  echo "[assert-lint] 干净（$# 件）：无 pipefail×grep -c / 挂起族反模式" >&2
  exit 0
fi
echo "[assert-lint] RED：断言脚本禁止上岗（先修反模式再过检；GATE-MATRIX L1）" >&2
exit 1
