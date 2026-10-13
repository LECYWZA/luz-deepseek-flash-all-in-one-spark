#!/bin/bash
# ==============================================================================
# refresh-md5sums.sh — guard/ 传输完整性清单（MD5SUMS）的**唯一**生成器 / 校验器
#
# 为什么要脚本化（而不是"手打一条 find | md5sum"）：
#   2026-09-23 重建清单时，手打的口径是
#     `find . -maxdepth 1 -type f ! -name MD5SUMS ! -name '*.bak-*' | xargs md5sum`
#   —— 它把**两个运行期日志**收进了清单（gen-probe-dgxspark01.log / guard-alerts.log，
#   16 项 → 18 项）。日志内容自变（gen_probe 每 30min 追加、alert 每次告警追加）
#   ⇒ `md5sum -c` 几分钟后必然变红 ⇒ **闸门自失效**，而"总在报错的闸门会被无视"，
#   于是真正的传输损坏也没人看了。排除口径必须落在可执行、可复核的地方。
#
# 清单语义 = **治理产物的传输完整性**。因此排除表只有三类，每类都有理由：
#   ① MD5SUMS 自身 —— 自引用在算术上不可能；
#   ② *.bak-*     —— 历史快照，不是交付物（且会随手工备份无限增殖）；
#   ③ *.log       —— 运行期产物，内容自变 ⇒ 收了就等于给清单装了定时炸弹。
# 白名单 = 产物扩展名（sh/py/conf/md/service/timer）。**未命中白名单、也没被排除的文件
# 不是静默忽略，而是"未分类"**：生成时直接拒绝（逼一次人为判断），校验时打 WARN。
# 这样"新增了一类文件导致清单漏钉"与"误钉了不该钉的文件"都不可能静默发生。
#
# 用法：
#   bash refresh-md5sums.sh            # 重建清单（未分类文件则拒绝，退出码非 0）
#   bash refresh-md5sums.sh --check    # 只校验：清单是否与磁盘现状一致（供 verify-governance 调用）
#   bash refresh-md5sums.sh --quiet    # 配 --check：只在失败时出声
#   bash refresh-md5sums.sh --selftest # 合成自检（7 项断言，自己造夹具、自己清理）
# 环境：GUARD_DIR=<dir> 覆盖作用目录（仅供自检/演练，正常不用）
# ==============================================================================
set -uo pipefail

DIR="${GUARD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
MODE=write; QUIET=0
for a in "$@"; do
  case "$a" in
    --check)    MODE=check ;;
    --quiet)    QUIET=1 ;;
    --selftest) MODE=selftest ;;
    *) printf '未知参数：%s（见文件头用法）\n' "$a" >&2; exit 2 ;;
  esac
done

ok()   { [ "$QUIET" = 1 ] || printf '  \033[32mOK\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }
warn() { [ "$QUIET" = 1 ] || printf '  \033[33mWARN\033[0m  %s\n' "$*"; }
info() { [ "$QUIET" = 1 ] || printf '  %s\n' "$*"; }

# 产物扩展名白名单。新增一类文件时**显式改这一行** —— 这个"要动一次代码"的代价，
# 就是它与"静默漏钉"之间的全部差价。
ART_EXT='sh|py|conf|md|service|timer'
# 排除表（与文件头① ② ③ 一一对应）。改这里必须同步改文件头，否则文档与行为分叉。
excluded() {
  case "$1" in
    MD5SUMS|*.bak-*|*.log) return 0 ;;
    *)                     return 1 ;;
  esac
}

# ---- 分类：把本目录文件切成 [产物] / [未分类] 两堆（排除的都不进）--------------
declare -a ARTS=() UNKNOWN=() EXC=()
split_files() {
  ARTS=(); UNKNOWN=(); EXC=()
  local f
  while IFS= read -r f; do
    if excluded "$f"; then EXC+=("$f"); continue; fi
    if [[ "$f" =~ \.($ART_EXT)$ ]]; then ARTS+=("$f"); else UNKNOWN+=("$f"); fi
  done < <(find "$DIR" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | LC_ALL=C sort)
}

# 生成清单内容（相对名，按 LC_ALL=C 排序；md5sum 保持入参顺序）
gen_manifest() { ( cd "$DIR" && md5sum "${ARTS[@]}" ); }

report_classes() {
  info "目录 $DIR"
  info "产物 ${#ARTS[@]} 项｜排除 ${#EXC[@]} 项（$(printf '%s ' "${EXC[@]}" 2>/dev/null)）"
}

# ---- 自检 ---------------------------------------------------------------------
selftest() {
  local rc nfails=0
  # ⚠ 这里**不能**把 T 声明成 local：trap 在 EXIT 时才触发，那时函数局部变量已出栈，
  #   `set -u` 会报"T: 未绑定的变量"（本脚本首跑实测到），于是清理静默不做、夹具残留。
  ST_T=$(mktemp -d /tmp/refresh-md5sums-st.XXXXXX)
  T="$ST_T"
  trap 'rm -rf "$ST_T"' EXIT
  mkdir -p "$T/g"
  cp "${BASH_SOURCE[0]}" "$T/g/refresh-md5sums.sh"
  printf 'echo hi\n'      > "$T/g/aaa.sh"            # 产物
  printf '# t\n'          > "$T/g/bbb.md"            # 产物
  printf 'x\n'            > "$T/g/ccc.log"           # 排除：运行期产物
  printf 'x\n'            > "$T/g/ddd.bak-20260920"  # 排除：历史
  printf '{}\n'           > "$T/g/eee.json"          # 未分类

  # 1) 未分类文件 ⇒ 生成必须**拒绝**（否则"清单漏钉"静默通过）
  GUARD_DIR="$T/g" bash "$T/g/refresh-md5sums.sh" --quiet >/dev/null 2>&1
  if [ $? -ne 0 ]; then ok "① 未分类文件 ⇒ 生成被拒（退出码非 0）"; else bad "① 未分类文件却生成了清单（静默漏钉温床）"; nfails=$((nfails+1)); fi

  # 2) 移走未分类文件后生成成功，且清单恰为 3 项产物
  rm -f "$T/g/eee.json"
  GUARD_DIR="$T/g" bash "$T/g/refresh-md5sums.sh" --quiet >/dev/null 2>&1 || { bad "② 正常目录却生成失败"; nfails=$((nfails+1)); }
  [ -f "$T/g/MD5SUMS" ] || { bad "② 未产出 MD5SUMS"; nfails=$((nfails+1)); }
  local listed; listed=$(awk '{print $2}' "$T/g/MD5SUMS" 2>/dev/null | sort | tr '\n' ' ')
  if [ "$listed" = "aaa.sh bbb.md refresh-md5sums.sh " ]; then
    ok "② 清单恰为 3 项产物：$listed"
  else
    bad "② 清单内容不对：[$listed]（应为 aaa.sh bbb.md refresh-md5sums.sh）"; nfails=$((nfails+1))
  fi

  # 3) 排除表生效：日志/备份/自身都不在清单里
  if grep -qE '(ccc\.log|ddd\.bak-20260920|MD5SUMS )' "$T/g/MD5SUMS"; then
    bad "③ 排除表失效：日志/备份/自身混入清单"; nfails=$((nfails+1))
  else ok "③ 排除表生效（*.log / *.bak-* / MD5SUMS 均未钉）"; fi

  # 4) 未改动 ⇒ --check 通过（否则闸门"总在报错"）
  GUARD_DIR="$T/g" bash "$T/g/refresh-md5sums.sh" --check --quiet >/dev/null 2>&1 \
    && ok "④ 无改动时 --check 通过" || { bad "④ 无改动却报不一致（假阳性）"; nfails=$((nfails+1)); }

  # 5) 改一个产物 ⇒ --check 必须**抓到并点名**
  printf 'echo changed\n' > "$T/g/aaa.sh"
  local out
  out=$(GUARD_DIR="$T/g" bash "$T/g/refresh-md5sums.sh" --check 2>&1); rc=$?
  if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'aaa.sh'; then
    ok "⑤ 就地改产物 ⇒ --check 抓到并点名 aaa.sh"
  else
    bad "⑤ 改了产物 --check 却放过（rc=$rc）"; nfails=$((nfails+1))
  fi

  # 6) 产物缺项（被删）⇒ --check 必须报不一致
  rm -f "$T/g/bbb.md"
  GUARD_DIR="$T/g" bash "$T/g/refresh-md5sums.sh" --check --quiet >/dev/null 2>&1 \
    && { bad "⑥ 产物被删却报一致"; nfails=$((nfails+1)); } || ok "⑥ 产物被删 ⇒ --check 报不一致"

  # 7) 日志变了**不应**影响 --check（这正是本次事故的靶心）
  GUARD_DIR="$T/g" bash "$T/g/refresh-md5sums.sh" --quiet >/dev/null 2>&1   # 先归零
  printf 'more log lines\n' >> "$T/g/ccc.log"
  GUARD_DIR="$T/g" bash "$T/g/refresh-md5sums.sh" --check --quiet >/dev/null 2>&1 \
    && ok "⑦ 运行期日志追加 ⇒ --check 仍通过（清单不再自失效）" \
    || { bad "⑦ 日志追加让 --check 变红 ⇒ 闸门会自失效（本次事故复现）"; nfails=$((nfails+1)); }

  rm -rf "$T"; trap - EXIT
  echo
  if [ "$nfails" = 0 ]; then echo "SELFTEST: PASS (7/7)"; return 0; fi
  echo "SELFTEST: FAIL ($nfails 项)"; return 1
}

[ "$MODE" = selftest ] && { selftest; exit $?; }

# ---- 主流程 -------------------------------------------------------------------
split_files
if [ "${#ARTS[@]}" = 0 ]; then
  bad "本目录解析出 0 项产物 ⇒ 口径或目录错了（别用空清单当过通过）"
  exit 1
fi
if [ "${#UNKNOWN[@]}" != 0 ]; then
  for f in "${UNKNOWN[@]}"; do
    if [ "$MODE" = write ]; then
      bad "未分类文件：$f —— 请决定：钉进清单（加进 ART_EXT 白名单）还是排除（加进 excluded 排除表），不要让它悬空"
    else
      warn "未分类文件：$f（未钉进清单，也未在排除表内陈述理由）"
    fi
  done
  [ "$MODE" = write ] && exit 1
fi

TMP=$(mktemp) || { bad "mktemp 失败"; exit 1; }
gen_manifest > "$TMP" || { bad "md5sum 计算失败"; rm -f "$TMP"; exit 1; }

if [ "$MODE" = write ]; then
  report_classes
  cp "$TMP" "$DIR/MD5SUMS"; rm -f "$TMP"
  n=$(grep -c . "$DIR/MD5SUMS")
  # ⚠ 判据必须**与 locale 无关**：宿主（zh_CN）下 md5sum -c 打 `: 成功`，而镜像内（C/POSIX）
  #   打 `: OK` —— 原写法 `grep -c ': 成功'` 在容器里恒为 0，于是"回读校验只过 0/N"，
  #   一个恒假的计数会被当成闸门坏了（2026-09-23 在 0.2.8pre 镜像里实测到）。
  #   这条只有**在真容器里跑**才现形：宿主上怎么试都是绿的（量具陷阱③：正则只认自家格式）。
  nok=$( cd "$DIR" && LC_ALL=C md5sum -c MD5SUMS 2>/dev/null | grep -c ': OK$' )
  # ⚠ grep 计数必须与项数**相等**才算通过：`md5sum -c | grep -c` 在"一项都没匹配上"时
  #   会打印 0 而退出码非 0，只看退出码会被 `||` 兜底吃掉（量具陷阱①）。
  if [ "$nok" = "$n" ]; then
    ok "MD5SUMS 已重建：$n 项，回读校验 $nok/$n 相符"
  else
    bad "MD5SUMS 回读校验只过 $nok/$n —— 不要分发这份清单"
    exit 1
  fi
  exit 0
fi

# --check：与磁盘现状对账
if [ ! -f "$DIR/MD5SUMS" ]; then
  warn "MD5SUMS 不在本目录 —— 传输完整性未校验（在役布局可无；交付布局应随包带上）"
  rm -f "$TMP"; exit 0
fi
if diff -q "$DIR/MD5SUMS" "$TMP" >/dev/null; then
  n=$(grep -c . "$TMP"); rm -f "$TMP"
  ok "MD5SUMS 与磁盘现状一致（$n 项产物）"
  exit 0
fi
bad "MD5SUMS 与磁盘现状不一致（左=清单，右=现状；运行期日志/备份的变化不会出现在这里）"
diff "$DIR/MD5SUMS" "$TMP" | sed 's/^/      /'
rm -f "$TMP"
exit 1
