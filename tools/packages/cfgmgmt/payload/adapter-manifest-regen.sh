#!/bin/bash
# adapter-manifest-regen.sh — ADAPTER-MANIFEST 重生成器（CODE31 P1-② 闭合件；TOOLS31 §二 P5）
#
# 【为什么存在】CODE31-REVIEW-REPORT §D.5：ADAPTER-MANIFEST 陈旧（≥3 件 md5 漂移+后增
#   20+ 件缺列）——呈裁后本件重生成：活清单法（find+md5sum，LC_ALL=C sort——adapter-sync
#   locale 教训口径）+逐件分类注记+sitecustomize 指纹**变量位**（FL6 接线后随窗重钉，
#   工具锚引用变量不引用硬值）。
# 【口径钉（CODE31 D.3，主会话裁定承载）】**29 活性 hook 面/40 挂装件**：
#   29 活性=24 env 键武装+3 COMMON_ENV 键武装（moe_b12x_next/deep_gemm_sm121/
#   engram_prefetch）+1 缺省开（mxfp8_b12x）+1 常开对（sparse_wire+admission_gate）。
# 【fl6_recall.py 位】FL6 修复件（md5 b87cbb5e=dev/fl6-recall 源同）**已入位**（2026-10-13
#   09:36Z，FL6 窗在飞）+sitecustomize 两行 elif 钩子（d5dc42a4）——本件按「已入位」终态
#   收列；**指纹终值=FL6 窗验证绿后的回填位**（PENDING-FL6-FINAL 注记行在档）。
# 【分类】active=29 活性面物理件族/inert=挂装惰性（D.2）/active-gated-fl6=第 51 键门控
#   （DSV41_FL6_RECALL_FIX 未设=休眠原版逐字）/loader=sitecustomize 装载缝/bak=历史备份
#   （RECIPE 排除清单恒拒入镜像）/support=支撑构建资料件/UNCLASSIFIED=白名单外呈报位。
# 【出口】0=生成或 --check 全等/1=--check 漂移/2=用法错/3=源目录缺位。
# 用法：adapter-manifest-regen.sh [--dir <adapter dir>] [--out <file>] [--check] [--selfcheck]
set -u
DIR=${ADAPTER_DIR:-$HOME/migrate-assets/dsv41/adapter}
OUT=""; CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --check) CHECK=1; shift ;;
    --selfcheck) exec bash "$0" --selfcheck-run "$0" ;;
    --selfcheck-run) S="$2"; shift 2; selfcheck_mode=1; break ;;
    *) echo "用法：$0 [--dir D] [--out F] [--check] [--selfcheck]" >&2; exit 2 ;;
  esac
done
[ -d "$DIR" ] || { echo "[adapter-mregen][RED] 源目录缺位：$DIR" >&2; exit 3; }

# ── 分类表（CODE31 D.1/D.2 物理件映射；FL6 承接）──
ACTIVE='engram_backend.py engram_prefetch.py mxfp8_b12x.py shared_pad_k.py l2_prefetch.py prefill_empty_cache.py idle_release.py moe_b12x_next.py wo_a_w8.py skip_nonfinal_decoder.py prefill_sp.py indexer_hoist.py verify_cap.py router_live.py lm_cert.py spec_sync_free.py folded_result_fence.py eager_glue.py replicated_split.py roce_ar.py roce_gather.py draft_head_fp8.py draft_head_fp8_tp4.py draft_main_proj.py hc_fused.py kv_fp4.py kv_fp4_repack.py deep_gemm_sm121.py sparse_wire.py seam_mount.py admission_gate.py admission_r1.py'
INERT='engram_compact.py token_req_compact.py verify_cap_static.py spark_prefill_split.py loop_abort.py draft_tau.py l2pf_attn.py indexer_budget.py moe_b12x.py replay_guard.py tp3_pad.py'

classify() {  # classify <相对路径> → 分类标签
  local p="$1" b="${1##*/}"
  case "$b" in
    sitecustomize.py) echo "loader（装载缝+横幅面；指纹=SITECUSTOMIZE_MD5 变量位）"; return ;;
    fl6_recall.py)    echo "active-gated-fl6（第 51 键 DSV41_FL6_RECALL_FIX 门控；未设=休眠原版逐字）"; return ;;
    *.bak-*|*.bak-*)  echo "bak（历史备份——RECIPE 排除清单恒拒入镜像）"; return ;;
  esac
  for a in $ACTIVE; do [ "$b" = "$a" ] && { echo "active（29 活性面物理件族）"; return; }; done
  for i in $INERT;   do [ "$b" = "$i" ] && { echo "inert（挂装惰性：门键不在任何键面）"; return; }; done
  case "$b" in
    *.cu|*.cpp|*.so|*.sh|*.json|*.txt) echo "support（支撑/构建/资料件）"; return ;;
    *.py) echo "UNCLASSIFIED（白名单外——逐件呈报位：历史族/测量件候选，下次审查归类）"; return ;;
    *) echo "support（杂项）" ;;
  esac
}

gen_manifest() {  # 产 manifest 文本到 stdout
  local now sc_md5
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sc_md5=$(md5sum "$DIR/sitecustomize.py" 2>/dev/null | awk '{print substr($1,1,8)}')
  cat <<HDR
# ADAPTER-MANIFEST（重生成 $now；源=$DIR）
# 口径钉（CODE31 D.3 主会话裁定承载）：29 活性 hook 面/40 挂装件（24 env 键武装+
#   3 COMMON_ENV 键武装+1 缺省开+1 常开对）。骨架「26」数=旧计弃用。
# SITECUSTOMIZE_MD5=${sc_md5:-UNKNOWN}（**变量位**：FL6 接线后随窗重钉——工具锚引用本变量，
#   不引用硬值；当前值=生成时点实测，FL6 窗验证绿后以终值重跑本件）。
# PENDING-FL6-FINAL：fl6_recall.py（b87cbb5e）+sitecustomize 两行 elif 钩子已入位
#   （2026-10-13 09:36Z FL6 窗在飞）；FL6 验证窗终态后重跑本件=终态清单（回填位）。
# 算式：find -type f 排除 __pycache__；LC_ALL=C sort（adapter-sync locale 教训口径）；
#   md5sum -c 可直验本件（# 注释行 md5sum 容忍）。
# 分类附录（逐件 CLASS 注记行）：
HDR
  ( cd "$DIR" && LC_ALL=C find . -type f ! -path '*__pycache__*' -print0 | LC_ALL=C sort -z | xargs -0 md5sum ) \
    | while IFS= read -r line; do
        p=$(printf '%s' "$line" | sed 's/^[0-9a-f]*  //')
        printf '# CLASS:%s|%s\n%s\n' "${p#./}" "$(classify "${p#./}")" "$line"
      done
}

if [ "${selfcheck_mode:-0}" = 1 ]; then
  # 自检（离线 mock 树红绿双例；$S=本件路径）
  rc=0; T=$(mktemp -d /tmp/admreg-sc.XXXXXX)
  mkdir -p "$T/adapter"
  printf 'x' > "$T/adapter/sitecustomize.py"; printf 'y' > "$T/adapter/engram_backend.py"
  printf 'z' > "$T/adapter/fl6_recall.py"; printf 'w' > "$T/adapter/loop_abort.py"
  printf 'q' > "$T/adapter/legacy_thing.py"; printf 'b' > "$T/adapter/sitecustomize.py.bak-pre-x"
  out=$(bash "$S" --dir "$T/adapter" 2>/dev/null)
  # T1 分类判别：六类各得其所
  printf '%s' "$out" | grep -q 'CLASS:sitecustomize.py|loader' && echo "[admregen][OK] T1 loader 分类绿" || { echo "[admregen][RED] T1 loader FAIL"; rc=1; }
  printf '%s' "$out" | grep -q 'CLASS:engram_backend.py|active' && echo "[admregen][OK] T1 active 分类绿" || { echo "[admregen][RED] T1 active FAIL"; rc=1; }
  printf '%s' "$out" | grep -q 'CLASS:fl6_recall.py|active-gated-fl6' && echo "[admregen][OK] T1 fl6 门控分类绿" || { echo "[admregen][RED] T1 fl6 FAIL"; rc=1; }
  printf '%s' "$out" | grep -q 'CLASS:loop_abort.py|inert' && echo "[admregen][OK] T1 inert 分类绿" || { echo "[admregen][RED] T1 inert FAIL"; rc=1; }
  printf '%s' "$out" | grep -q 'CLASS:legacy_thing.py|UNCLASSIFIED' && echo "[admregen][OK] T1 UNCLASSIFIED 呈报位绿" || { echo "[admregen][RED] T1 UNCLASSIFIED FAIL"; rc=1; }
  printf '%s' "$out" | grep -q 'CLASS:sitecustomize.py.bak-pre-x|bak' && echo "[admregen][OK] T1 bak 分类绿" || { echo "[admregen][RED] T1 bak FAIL"; rc=1; }
  # T2 口径钉+变量位+PENDING 注记三头行
  printf '%s' "$out" | grep -q '29 活性 hook 面/40 挂装件' && echo "[admregen][OK] T2 口径钉头行在" || { echo "[admregen][RED] T2 口径钉缺"; rc=1; }
  printf '%s' "$out" | grep -q '^# SITECUSTOMIZE_MD5=' && echo "[admregen][OK] T2 变量位头行在" || { echo "[admregen][RED] T2 变量位缺"; rc=1; }
  printf '%s' "$out" | grep -q 'PENDING-FL6-FINAL' && echo "[admregen][OK] T2 PENDING-FL6-FINAL 回填位在" || { echo "[admregen][RED] T2 回填位缺"; rc=1; }
  # T3 md5sum -c 可直验（生成→落盘→校验绿）
  bash "$S" --dir "$T/adapter" --out "$T/MF" 2>/dev/null
  ( cd "$T/adapter" && md5sum -c <(grep -v '^#' "$T/MF") ) >/dev/null 2>&1 && echo "[admregen][OK] T3 md5sum -c 直验绿" || { echo "[admregen][RED] T3 直验 FAIL"; rc=1; }
  # T4 红例：改一文件后 --check 必红
  printf 'CHANGED' >> "$T/adapter/engram_backend.py"
  bash "$S" --dir "$T/adapter" --out "$T/MF2" 2>/dev/null
  printf 'x' > "$T/adapter/engram_backend.py"   # 复原为但改 sitecustomize
  printf 'ZZ' >> "$T/adapter/sitecustomize.py"
  ( cd "$T/adapter" && md5sum -c <(grep -v '^#' "$T/MF2") ) >/dev/null 2>&1 && { echo "[admregen][RED] T4 红例失效（漂移未检出）"; rc=1; } || echo "[admregen][OK] T4 红例判红（漂移=md5sum -c 失败）"
  rm -rf "$T"; exit "$rc"
fi

if [ "$CHECK" = 1 ]; then
  # --check：对在档 ADAPTER-MANIFEST 校验（缺省=源目录旁；路径先绝对化——校验面 cd 后不破）
  MF="$(readlink -f "${OUT:-$DIR/../ADAPTER-MANIFEST}")"
  [ -r "$MF" ] || { echo "[adapter-mregen][RED] 清单缺件：$MF" >&2; exit 3; }
  if ( cd "$DIR" && md5sum -c <(grep -v '^#' "$MF") ) >/tmp/admregen-check.out 2>&1; then
    echo "[adapter-mregen][OK] --check 全等（$(grep -vc '^#' "$MF") 件）"; exit 0
  else
    echo "[adapter-mregen][RED] --check 漂移："; grep -v ': 成功' /tmp/admregen-check.out | head -10 | sed 's/^/    /' >&2
    exit 1
  fi
fi

if [ -n "$OUT" ]; then gen_manifest >"$OUT"; echo "[adapter-mregen] 已生成：$OUT（$(grep -vc '^#' "$OUT") 件）"
else gen_manifest; fi
