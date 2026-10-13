#!/bin/bash
# adapter-sync.sh — adapter 权威源四机同步/对表工具（ENV-GOVERNANCE-20261010 落实件）
#
# 【为什么存在】DEPLOY-SPLIT-OPEN-20261010：W2 F-1 件只落 01 致 head31/worker30 门
#   分裂（-v ~/migrate-assets/dsv41/adapter 各机自挂，真源=各机本地目录，无同步纪律）。
#   镜像 main-79cafec0 实测**不含** /opt/dsv41（docker create+cp 亲验 2026-10-10）⇒
#   bind mount 是 adapter 的唯一供给面——部署漂移=直接生效，无镜像兜底。
#
# 【权威源】dgxspark01:~/migrate-assets/dsv41/adapter（唯一真源；一切件变更先落 01，
#   再用本工具 --apply 下发四机）。镜像无烘件=不存在第三源兜底，此纪律为硬前置。
#
# 【用法】（必须在 dgxspark01 上运行）
#   bash ~/luz030-opt-campaign/tools/adapter-sync.sh --check          # 只读对表（缺省模式；红=exit 1）
#   bash ~/luz030-opt-campaign/tools/adapter-sync.sh --apply          # rsync 01→02/03/04（无删除）
#   bash ~/luz030-opt-campaign/tools/adapter-sync.sh --apply --prune  # 先备份差异件再 --delete 对齐（先存后删律）
#   bash ~/luz030-opt-campaign/tools/adapter-sync.sh --check \
#        --expect sitecustomize.py=79b8143e indexer_budget.py=fd03078d   # 权威源锚断言
#   bash ~/luz030-opt-campaign/tools/adapter-sync.sh --selfcheck       # 本地逻辑自检（零 ssh 零集群）
#
# 【指纹口径】find -type f 排除 __pycache__（.pyc 按机生成，非部署面）；
#   LC_ALL=C sort（教训：四机 locale 异同曾致 md5 清单排序错位=假差异，DEPLOY-SPLIT §一勘误家族）。
#
# 【红线】零容器操作/零 sudo/零 kill；--apply 属部署窗动作（bind mount 文件替换对已
#   import 进程无扰=先例 W2 补齐 04:5xZ 产线 200 无扰动，但新件生效需下次 boot）；
#   --prune 恒先存后删（备份目录 ~/migrate-assets/dsv41/adapter-archive-<ts>/<host>/）。
#
# 【红出口】0=全等/同步后全等；1=对表红（--check 发现不一致）；2=锚断言红/用法错；
#   3=ssh/权威源缺位等环境红；4=apply 后复检仍不一致（fail-loud，禁止静默通过）。
set -uo pipefail

AUTH_HOST="dgxspark01"
HOSTS=(dgxspark01 dgxspark02 dgxspark03 dgxspark04)
ADAPTER_DIR="$HOME/migrate-assets/dsv41/adapter"
ARCHIVE_ROOT="$HOME/migrate-assets/dsv41"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8)
MODE=""

red()   { printf '[adapter-sync][RED] %s\n' "$*" >&2; }
info()  { printf '[adapter-sync] %s\n' "$*"; }

usage() { sed -n '2,30p' "$0" | grep -E "^#   bash|^#   " | head -12; exit 2; }

# ── 参数解析 ──
EXPECT_LIST=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check)    MODE="check" ;;
    --apply)    MODE="apply" ;;
    --prune)    PRUNE=1 ;;
    --selfcheck) MODE="selfcheck" ;;
    --expect)   [ $# -ge 2 ] || { red "--expect 需 FILE=md5 前8位 参数"; exit 2; }
                EXPECT_LIST+=("$2"); shift ;;
    *)          if [[ "$1" =~ ^[A-Za-z0-9_./-]+=[0-9a-fA-F]{8}$ ]]; then
                  EXPECT_LIST+=("$1")          # 裸 FILE=md5 形态也收（--expect 后可连写多对）
                else
                  red "未知参数: $1"; usage
                fi ;;
  esac
  shift
done
[ -n "$MODE" ] || MODE="check"

# ── 本地逻辑自检（零 ssh 零集群；temp dir 三态判别力）──
selfcheck() {
  local T rc=0
  T=$(mktemp -d /tmp/adapter-sync-selftest.XXXXXX) || { red "mktemp 失败"; exit 3; }
  mkdir -p "$T/a" "$T/b1" "$T/b2"
  printf 'x\n' >"$T/a/f1.py"; printf 'y\n' >"$T/a/f2.py"
  printf 'x\n' >"$T/b1/f1.py"                      # b1=f1 同 f2 缺
  printf 'x\n' >"$T/b2/f1.py"; printf 'z\n' >"$T/b2/f2.py"; printf 'q\n' >"$T/b2/extra.py"  # b2=f2 异+多件
  mkdir -p "$T/a/__pycache__" "$T/b1/__pycache__"; printf 'p\n' >"$T/a/__pycache__/f1.pyc"; printf 'p2\n' >"$T/b1/__pycache__/f1.pyc"

  manifest_of() { ( cd "$1" && find . -type f ! -path "*__pycache__*" | LC_ALL=C sort | xargs -r md5sum 2>/dev/null | LC_ALL=C sort ); }

  # T1: 同树 → 全等
  if diff -q <(manifest_of "$T/a") <(manifest_of "$T/a") >/dev/null; then info "selfcheck T1 同树全等 PASS"; else red "selfcheck T1 FAIL"; rc=1; fi
  # T2: 缺件 → 必红
  if diff -q <(manifest_of "$T/a") <(manifest_of "$T/b1") >/dev/null; then red "selfcheck T2 缺件未检出 FAIL"; rc=1; else info "selfcheck T2 缺件检出 PASS"; fi
  # T3: 内容异+多件 → 必红
  if diff -q <(manifest_of "$T/a") <(manifest_of "$T/b2") >/dev/null; then red "selfcheck T3 内容漂移未检出 FAIL"; rc=1; else info "selfcheck T3 内容漂移+多件检出 PASS"; fi
  # T4: __pycache__ 排除 → pyc 差异不算漂移
  if diff -q <(manifest_of "$T/a") <( (cd "$T/a" && find . -type f ! -path "*__pycache__*" | LC_ALL=C sort | xargs -r md5sum | LC_ALL=C sort) ) >/dev/null; then info "selfcheck T4 pycache 排除 PASS"; else red "selfcheck T4 FAIL"; rc=1; fi
  # T5: --expect 解析
  local k v; k="${EXPECT_TEST_KEY:-sitecustomize.py}"; v="${EXPECT_TEST_VAL:-0123abcd}"
  if [ "${#v}" -eq 8 ] && [[ "$k" == *.py ]]; then info "selfcheck T5 expect 形态 PASS（$k=$v 占位）"; else red "selfcheck T5 FAIL"; rc=1; fi
  rm -rf "$T"
  if [ "$rc" = 0 ]; then info "selfcheck 5/5 ALL-GREEN"; else red "selfcheck 有红项（见上）"; fi
  exit "$rc"
}
[ "$MODE" = "selfcheck" ] && selfcheck

# ── 权威源前置 ──
[ "$(hostname)" = "$AUTH_HOST" ] || { red "本工具须在 $AUTH_HOST 上运行（当前 $(hostname)）"; exit 3; }
[ -f "$ADAPTER_DIR/sitecustomize.py" ] || { red "权威源缺位：$ADAPTER_DIR/sitecustomize.py"; exit 3; }

# ── 锚断言（--expect FILE=md5 前 8 位；红=权威源本身可疑，拒同步拒放行）──
for e in "${EXPECT_LIST[@]:-}"; do
  [ -n "$e" ] || continue
  k="${e%%=*}"; v="${e#*=}"
  real=$(md5sum "$ADAPTER_DIR/$k" 2>/dev/null | cut -c1-8)
  [ "$real" = "$v" ] || { red "锚断言红：$k 期望 $v 实得 ${real:-缺失}——权威源与预期不符，拒绝继续（防把坏源同步四机）"; exit 2; }
  info "锚断言 PASS：$k=$v"
done

# ── 指纹采集（对表模式只读；01 本地直采，worker 经 ssh）──
collect() {  # <host> → stdout: 清单（md5 + 路径）
  local h="$1"
  if [ "$h" = "$AUTH_HOST" ]; then
    ( cd "$ADAPTER_DIR" && find . -type f ! -path "*__pycache__*" | LC_ALL=C sort \
      | xargs -r md5sum 2>/dev/null | LC_ALL=C sort )
  else
    ssh "${SSH_OPTS[@]}" "$h" "cd '$ADAPTER_DIR' && find . -type f ! -path '*__pycache__*' | LC_ALL=C sort | xargs -r md5sum 2>/dev/null | LC_ALL=C sort" 2>/dev/null
  fi
}

TS=$(date -u +%Y%m%dT%H%M%SZ)
AUTH_MANIFEST=$(mktemp /tmp/adapter-sync-auth.XXXXXX)
collect "$AUTH_HOST" >"$AUTH_MANIFEST" || { red "权威源清单采集失败"; exit 3; }
[ -s "$AUTH_MANIFEST" ] || { red "权威源清单为空（异常）"; exit 3; }

do_check() {
  local bad=0 h m fp
  AUTH_FP=$(md5sum "$AUTH_MANIFEST" | cut -c1-8)
  info "权威源 $AUTH_HOST 指纹=$AUTH_FP（活件 $(grep -c . "$AUTH_MANIFEST") 件，pycache 排除口径）"
  for h in "${HOSTS[@]:1}"; do
    m=$(mktemp /tmp/adapter-sync-$h.XXXXXX)
    if ! collect "$h" >"$m" || [ ! -s "$m" ]; then
      red "$h 清单采集失败（ssh 不通或目录缺）"; bad=1; rm -f "$m"; continue
    fi
    fp=$(md5sum "$m" | cut -c1-8)
    if [ "$fp" = "$AUTH_FP" ]; then
      info "$h 指纹=$fp 全等"
    else
      red "$h 指纹=$fp ≠ 权威 $AUTH_FP——差异件："
      diff "$AUTH_MANIFEST" "$m" | grep -E "^[<>]" | sed 's/^/    /' >&2
      bad=1
    fi
    rm -f "$m"
  done
  rm -f "$AUTH_MANIFEST" 2>/dev/null || true
  return "$bad"
}

do_apply() {
  local h rc=0 first_note=1
  for h in "${HOSTS[@]:1}"; do
    info "rsync $AUTH_HOST → $h（$( [ "${PRUNE:-0}" = 1 ] && echo '含 prune' || echo '仅增量' )）"
    # prune 律：先存后删——把 worker 上将被删除的件先备份，再 --delete
    if [ "${PRUNE:-0}" = "1" ]; then
      local ARC="$ARCHIVE_ROOT/adapter-archive-$TS/$h"
      ssh "${SSH_OPTS[@]}" "$h" "mkdir -p '$ARC'" || { red "$h 备份目录建败"; rc=1; continue; }
      rsync -a --delete --exclude __pycache__ --backup --backup-dir="$ARC" -e "ssh ${SSH_OPTS[*]}" \
        "$ADAPTER_DIR/" "$h:$ADAPTER_DIR/" || { red "rsync $h 失败"; rc=1; continue; }
      info "$h prune 完成（被删件已备份 $ARC）"
    else
      rsync -a --exclude __pycache__ -e "ssh ${SSH_OPTS[*]}" \
        "$ADAPTER_DIR/" "$h:$ADAPTER_DIR/" || { red "rsync $h 失败"; rc=1; continue; }
    fi
  done
  [ "$rc" = 0 ] || { red "apply 有失败机（fail-loud，不静默）"; exit 4; }
  info "apply 完成——复检四机全等："
}

case "$MODE" in
  check)
    if do_check; then
      info "四机全等（对表绿）"
      exit 0
    else
      red "四机对表红——以 01 为权威源，部署窗执行：--apply（必要时 --prune）"
      exit 1
    fi
    ;;
  apply)
    do_apply
    collect "$AUTH_HOST" >"$AUTH_MANIFEST" 2>/dev/null || { red "复检采集失败"; exit 3; }
    if do_check; then
      info "apply 后四机全等（绿）；注意：运行中容器已 import 的模块不受影响，新件于下次 boot 生效"
      exit 0
    else
      red "apply 后复检仍不一致——fail-loud 出口 4，禁止视为成功"
      exit 4
    fi
    ;;
  *) red "内部错：未知模式 $MODE"; exit 2 ;;
esac
