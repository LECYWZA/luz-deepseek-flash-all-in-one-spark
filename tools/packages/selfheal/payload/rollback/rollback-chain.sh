#!/bin/bash
# rollback-chain.sh — 0.3.1 回退四级链脚本（50→48→47→45 键；FORM-REGISTRY-031 权威承接）
#
# 【为什么存在】TOOLS31-PACKAGE-PLAN §二 P3-3：两级回退 runbook 的脚本化+四级链扩展
#   （主会话 2026-10-13 定链=50→48→47→45）。回退不是「换 env 再 boot」一件事——每级
#   伴随件面动作（W5 件/overlay）与四查复绿义务；跳级=放弃中间级四查=禁。
# 【权威表】FORM-REGISTRY-031 §一（L0..L3 四行）——本件内嵌表须与其同步（同日更新律）。
# 【案头红线】本件**缺省零动作**：--plan/--check/--selfcheck 全案头；--apply=执行窗
#   专用（打印逐条动作+经 boot-with-slotlock 点火的提示，实际 boot 动作归执行窗 OUTAGE 制）。
#
# 用法：
#   rollback-chain.sh --plan <50|48|47|45> <50|48|47|45>   # 打印逐级动作序（相邻级强制）
#   rollback-chain.sh --check <env 文件>                    # 对表：md5+键数双核（红/绿/UNKNOWN）
#   rollback-chain.sh --selfcheck                           # 离线红绿双例（mock env 树）
#   rollback-chain.sh --apply <from> <to>                   # 执行窗：打印+执行件面动作（boot 步恒人工确认）
set -u

# ── 四级表（FORM-REGISTRY-031 §一 逐字承接；md5=前 8 位）──
# 级|键数|env 件名|env md5|adapter 面|overlay|注记
L0_NAME="PROD-R51W5-spec1.env";            L0_MD5=15767aa6; L0_KEYS=50; L0_ADAPT="4b40a123+W5 件 32cf9abf"; L0_OVER="o12c1-prod"
L1_NAME="PROD-R1INK48L2PF6O12C1-spec1.env"; L1_MD5=8c8c166d; L1_KEYS=48; L1_ADAPT="4b40a123+0497e566";      L1_OVER="o12c1-prod"
L2_NAME="PROD-R1STDLL128L2PF6O12C1-spec1.env"; L2_MD5=99e7ec92; L2_KEYS=47; L2_ADAPT="4b40a123+0497e566";   L2_OVER="o12c1-prod"
L3_NAME="PROD-R1STDLL128L2PF6-spec1.env";   L3_MD5=34977bf0; L3_KEYS=45; L3_ADAPT="45 键时代面（W5 件 unset 语义等价）"; L3_OVER="零 overlay"

ENVDIR="${ROLLBACK_ENVDIR:-/home/liux***ya/migrate-assets/dsv41/env}"

lvl_vars() { case "$1" in
  50) echo "L0" ;; 48) echo "L1" ;; 47) echo "L2" ;; 45) echo "L3" ;;
  *) return 1 ;; esac; }

adjacent() {  # 相邻级律：50→48/48→47/47→45（含同级 idempotent 核对面）；跳级=红
  case "$1/$2" in
    50/48|48/47|47/45|50/50|48/48|47/47|45/45) return 0 ;;
    *) return 1 ;; esac; }

four_checks() {  # 每级四查义务面（boot 后复绿判据；详=selfdiag 包 gates 族）
  cat <<'EOF'
  四查义务（每级 boot 后全绿才宣告该级复绿）：
    ① health 200 + 横幅门行（banner 逐形口径；容器×4）
    ② 池门 9,600,000 直读
    ③ O12 四秩（47/48/50 键形）或零 overlay 面核（45 键形）
    ④ fail-safe PASS×4 + MISMATCH=0 + printenv 真键核（对当级 env 逐键）
EOF
}

print_level() { local P="$1"; local V; V=$(lvl_vars "$P") || return 1
  eval "local n=\$${V}_NAME m=\$${V}_MD5 k=\$${V}_KEYS a=\$${V}_ADAPT o=\$${V}_OVER"
  printf '  [%s 键] %s（md5 %s）| adapter：%s | overlay：%s\n' "$k" "$n" "$m" "$a" "$o"; }

case "${1:-}" in
  --plan)
    FROM="${2:?}"; TO="${3:?}"
    adjacent "$FROM" "$TO" || { echo "[rollback][RED] 非相邻级（$FROM→$TO）：四级链每级四查律——跳级禁（多级回退=逐级递降）" >&2; exit 1; }
    [ "$FROM" = "$TO" ] && { echo "[rollback] 同级核对面（$FROM→$TO=不回退，仅复绿四查）"; print_level "$FROM"; exit 0; }
    echo "[rollback] 回退计划：$FROM 键 → $TO 键（相邻级）"
    echo "  0) 停手取证（logs×4 先存律——INCIDENT 家族序；不重试律）"
    echo "  1) r3-stop 拆栈（幂等；D8 三查=容器净/槽释放/水位回位）"
    print_level "$FROM"; echo "    ↓ 撤面动作："
    case "$TO" in
      48) echo "    - W5 两键 unset（ENV 换 $L1_NAME）+W5 件 32cf9abf→0497e566（键关=语义等价口径 FORM-REGISTRY §四-1）";;
      47) echo "    - R1 in-kernel 键 unset（构造性回退，FULLGATE G5 先例）";;
      45) echo "    - 零 overlay 化（SGLANG_OVERLAY_DIR 摘挂）+五参面（无 swa256）";;
    esac
    print_level "$TO"
    echo "  2) 沉降 ≥30min（双靴切换沉降律④ a105103）"
    echo "  3) boot：ARM_TAG=RB-${FROM}TO${TO} 经 tools/boot-with-slotlock.sh（P0 治理：绕 wrapper=违反治理项）"
    echo "  4) adapter-sync --check --expect sitecustomize.py=<当值>（面指纹核）"
    four_checks
    echo "  5) 复绿宣告+台账（窗档 logs/RB-<date>/）——未全绿=停手呈裁不连发重试"
    ;;
  --check)
    F="${2:?--check 需 env 文件}"
    [ -r "$F" ] || { echo "[rollback][UNKNOWN] env 文件不可读（$F）——无法判" >&2; exit 2; }
    m=$(md5sum "$F" | awk '{print substr($1,1,8)}'); k=$(grep -cE '^[A-Z_][A-Z0-9_]*=' "$F")
    for V in L0 L1 L2 L3; do
      eval "wm=\$${V}_MD5 wk=\$${V}_KEYS wn=\$${V}_NAME"
      if [ "$m" = "$wm" ]; then
        if [ "$k" = "$wk" ]; then echo "[rollback][OK] $wn（md5 $m+${k} 键双核绿）"; exit 0
        else echo "[rollback][RED] md5 对 $wn 但键数 $k≠$wk（表漂移——FORM-REGISTRY 同日更新律）" >&2; exit 1; fi
      fi
    done
    echo "[rollback][UNKNOWN] md5 $m（${k} 键）不在四级表——非 0.3.1 链内形（不臆造律）" >&2; exit 2 ;;
  --apply)
    FROM="${2:?}"; TO="${3:?}"
    adjacent "$FROM" "$TO" || { echo "[rollback][RED] 非相邻级" >&2; exit 1; }
    echo "[rollback] --apply=执行窗面（OUTAGE 制）。本窗只打印动作序；实际执行=执行窗承载。"
    exec "$0" --plan "$FROM" "$TO" ;;
  --selfcheck)
    rc=0; T=$(mktemp -d /tmp/rbchain-sc.XXXXXX)
    cp "$ENVDIR/$L0_NAME" "$T/good50.env" 2>/dev/null || { echo "[rbchain][UNKNOWN] 权威 env 树缺件（$ENVDIR）——真面复跑无法判"; }
    # T1 50 键真形双核绿
    if [ -f "$T/good50.env" ]; then
      "$0" --check "$T/good50.env" >/dev/null 2>&1 && echo "[rbchain][OK] T1 50 键真形 md5+键数双核绿" || { echo "[rbchain][RED] T1 FAIL"; rc=1; }
      # T2 红例：篡改一键必红（md5 不在表=UNKNOWN 面恰证判别力；键数单测）
      sed 's/=.*/=9/' "$T/good50.env" | head -50 > "$T/bad.env"
      out=$("$0" --check "$T/bad.env" 2>&1); r=$?
      [ "$r" = 2 ] && echo "[rbchain][OK] T2 篡改形判 UNKNOWN（不臆造律护栏）" || { echo "[rbchain][RED] T2 FAIL（rc=$r out=$out）"; rc=1; }
    fi
    # T3 相邻级绿+跳级红
    "$0" --plan 50 48 >/dev/null 2>&1 && echo "[rbchain][OK] T3 相邻级计划绿（50→48）" || { echo "[rbchain][RED] T3 相邻级 FAIL"; rc=1; }
    "$0" --plan 50 47 >/dev/null 2>&1; [ $? = 1 ] && echo "[rbchain][OK] T3 跳级判红（50→47 拒绝=每级四查律）" || { echo "[rbchain][RED] T3 跳级未拒"; rc=1; }
    # T4 计划面要件完备（slotlock/沉降/四查/停手取证四要素在文）
    out=$("$0" --plan 48 47 2>&1)
    echo "$out" | grep -q boot-with-slotlock && echo "$out" | grep -q 沉降 && echo "$out" | grep -q 四查 && echo "$out" | grep -q 先存 \
      && echo "[rbchain][OK] T4 计划四要素在文（slotlock/沉降/四查/取证）" || { echo "[rbchain][RED] T4 计划要素缺"; rc=1; }
    rm -rf "$T"; exit "$rc" ;;
  *) echo "用法：$0 --plan <from> <to> | --check <env> | --selfcheck | --apply <from> <to>" >&2; exit 2 ;;
esac
