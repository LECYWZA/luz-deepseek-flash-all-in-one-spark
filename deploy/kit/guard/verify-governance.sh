#!/bin/bash
# ==============================================================================
# verify-governance.sh — 治理包装完自检（齐备性 + 语法 + 能力断言）
#
# 为什么需要它：md5 表挡不住"装到了**错误的版本**"这类失效 —— 表和文件可以互相自洽，
# 而那份文件本身是早期版本（本轮实测到的真事：交付包里的 `jit-header-refresh.sh` 是早期
# 版本，缓存挂在容器 /root 下、没有 --overlay-map，而当时表上的 md5 与它**恰好一致**）。
# 所以这个自检**不抄任何数字**，只做两件事：自己算（文件在不在、语法过不过），
# 以及断言**行为特征**（这一版必须具备的能力、以及必须**不**具备的危险动作）。
#
# 判据来自真实踩过的坑，每一条都对应一次事故或一次误判：
#   · jit-header-refresh.sh 必须支持 --overlay-map（否则驱动容器编译的是**基座镜像**的源码树，
#     而不是要交付的那棵树；实测表现为 `identifier "V41_FP4" is undefined`）；
#   · 它的缓存**不得**挂在 /root 下（容器以 uid 1000 跑、镜像 /root 是 0700 ⇒ 挂那里不仅写不进，
#     更糟的是 `--check` 会对**所有**变体静默报 MISS —— 一个永远不会 PASS 的闸门等于没有闸门）；
#   · 它**不得**删除缓存（只发布、绝不删除：删会砸掉正在跑的服务命中的产物，
#     而服务在快路径上不加锁，一旦 miss 就在服务进程内编译，不受容器内存上限保护）；
#   · guardctl.sh 的 `watch` 必须把 HELD 记为 WARN（HELD=有意的维护态；记成 CRIT 会让每次
#     开窗都往"外部监控 grep CRIT"的通道里灌假警报，即 v0.4.1 修掉的"喊狼来了"）；
#   · guardctl.sh 的 hold/release 必须处理裸进程守卫（`oom_gate.sh monitor` 不是 systemd 单元，
#     "停泊桩"那套机制看不见它 ⇒ 开窗时它会按窗口内完全合法的低内存去 docker stop 生产）。
#
# 用法：bash verify-governance.sh          （退出码 0=全过；非 0=有 FAIL）
#       bash verify-governance.sh --quiet  （只打印结论）
# ==============================================================================
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

fails=0
checks=0
ok()  { [ "$QUIET" = 1 ] || printf '  \033[32mOK\033[0m    %s\n' "$*"; checks=$((checks + 1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; checks=$((checks + 1)); fails=$((fails + 1)); }
warn(){ [ "$QUIET" = 1 ] || printf '  \033[33mWARN\033[0m  %s\n' "$*"; }

echo "guardctl verify-governance on $(hostname) —— $DIR"

# ---- 1) 齐备性 --------------------------------------------------------------
echo "[1] 齐备性"
# oom_gate.sh 允许与 guardctl 同目录（交付目录的排法）或 ../oom-gate/（在役排法）
OOM=""
for c in "$DIR/oom_gate.sh" "$DIR/../oom-gate/oom_gate.sh"; do
  [ -f "$c" ] && { OOM="$c"; break; }
done
for f in guardctl.sh guards.conf flashinfer-arch-guard.sh guard-onstart.sh \
         jit-header-refresh.sh jit_refresh_exec.py probe_deps_closure.py \
         overlay-drift-check.sh README.md BASELINE.md; do
  if [ -f "$DIR/$f" ]; then ok "$f"; else bad "$f 缺失"; fi
done
# 布局相关的两件：交付包必须带；在役布局（../oom-gate/ 那套）里它们本来就不是安装物。
# 旧版把 MD5SUMS 放进同一个必查表 ⇒ 在役布局永远 FAIL；反过来把缺失改成静默跳过又会让
# 交付包缺清单也看不出来（而文档还教人 `md5sum -c … 2>/dev/null`，没输出像通过）。
INSTALLED=0; [ -f "$DIR/../oom-gate/oom_gate.sh" ] && INSTALLED=1
for f in HOW-TO-INSTALL.md MD5SUMS; do
  if [ -f "$DIR/$f" ]; then ok "$f"
  elif [ "$INSTALLED" = 1 ]; then warn "$f 不在（在役布局的正常形态：HOW-TO-INSTALL 是交付文档、MD5SUMS 随包）"
  else bad "$f 缺失（交付包必须带）"; fi
done
if [ -n "$OOM" ]; then ok "oom_gate.sh（$OOM）"; else bad "oom_gate.sh 缺失（同目录或 ../oom-gate/ 都没有）"; fi

# ---- 2) 语法 ---------------------------------------------------------------
echo "[2] 语法"
for f in "$DIR"/*.sh; do
  [ -f "$f" ] || continue
  bash -n "$f" 2>/dev/null && ok "bash -n $(basename "$f")" || bad "bash -n 失败：$(basename "$f")"
done
[ -n "$OOM" ] && { bash -n "$OOM" 2>/dev/null && ok "bash -n oom_gate.sh" || bad "bash -n 失败：oom_gate.sh"; }
for f in "$DIR"/*.py; do
  [ -f "$f" ] || continue
  # ★不写字节码：`python3 -m py_compile` 会在**被检查的目录**里建 __pycache__，
  #   于是"装完自检"把交付目录（一个 git 仓）弄脏，`git status` 多出未跟踪项。
  PYTHONDONTWRITEBYTECODE=1 python3 -c 'import sys; compile(open(sys.argv[1],encoding="utf-8").read(), sys.argv[1], "exec")' "$f" 2>/dev/null \
    && ok "语法 $(basename "$f")（compile，不写字节码）" || bad "语法失败：$(basename "$f")"
done

# ---- 3) 能力断言（这一版必须具备 / 必须不具备）-------------------------------
echo "[3] 能力断言"
JHR="$DIR/jit-header-refresh.sh"
if [ -f "$JHR" ]; then
  # 剥掉注释再找：文件里有注释**描述**这个选项，未剥注释时"删掉实现、留下注释"也能过。
  grep -vE '^[[:space:]]*#' "$JHR" | grep -qF -- '--overlay-map' \
    && ok "jit-header-refresh.sh 支持 --overlay-map" \
    || bad "jit-header-refresh.sh 不支持 --overlay-map（会编译基座镜像的源码树，不是要交付的那棵）"
  # 只看非注释行：文件里有一句注释**描述**旧版曾删过缓存，不能把注释当成删除动作。
  if grep -vE '^[[:space:]]*#' "$JHR" | grep -qE '\brm[[:space:]]+-rf\b'; then
    bad "jit-header-refresh.sh 含 rm -rf（必须只发布、绝不删除：删会砸掉在役服务命中的产物）"
  else
    ok "jit-header-refresh.sh 无删除动作（只发布）"
  fi
  if grep -qE '^[[:space:]]*CONTAINER_CACHE="/root' "$JHR"; then
    bad "缓存挂在 /root 下（镜像 /root 是 0700、容器以 uid 1000 跑 ⇒ 写不进且 --check 对所有变体静默 MISS）"
  else
    ok "缓存未挂在 /root 下"
  fi
else
  bad "无法断言 jit-header-refresh.sh（文件缺失）"
fi

GC="$DIR/guardctl.sh"
if [ -f "$GC" ]; then
  grep -qE 'HELD\)[[:space:]]*alert[[:space:]]+WARN' "$GC" \
    && ok "guardctl watch 把 HELD 记为 WARN（维护态不占用 CRIT 通道）" \
    || bad "guardctl watch 未把 HELD 记为 WARN（开窗时会往 CRIT 通道灌假警报）"
  grep -qF 'oomgate_state_file' "$GC" \
    && ok "guardctl hold/release 处理裸进程守卫（oom_gate monitor）" \
    || bad "guardctl 未处理裸进程守卫（hold 后 monitor 仍在跑 ⇒ 会 docker stop 生产）"
  for k in proc envpin archscr; do
    grep -qF "$k)" "$GC" && ok "guardctl 支持前置 kind：$k" || bad "guardctl 缺前置 kind：$k"
  done
else
  bad "无法断言 guardctl.sh（文件缺失）"
fi

CC="$DIR/guards.conf"
if [ -f "$CC" ]; then
  for s in oom-gate-monitor oom-gate-floor sglang-pin sglang-kv-layout RETIRED-20260916; do
    grep -qF -- "$s" "$CC" && ok "guards.conf 含 $s" || bad "guards.conf 缺 $s"
  done
else
  bad "无法断言 guards.conf（文件缺失）"
fi

# 2026-09-17 修掉的三类缺陷，加断言防止回归（每一条都对应一次实测误判）
if [ -f "$GC" ]; then
  grep -qF 'chain_is_wired' "$GC" \
    && ok "自恢复判定有接线门槛（本机没有单元调用该链时 SKIP，而不是每次巡检报永久 WARN）" \
    || bad "自恢复判定缺接线门槛（worker 上会一直报一条无法清除的 WARN）"
  grep -qE '^[[:space:]]*skip\(\)' "$GC" \
    && ok "SKIP 是一等结论（不渲染成 WARN）" \
    || bad "SKIP 会被渲染成 WARN（每次巡检都叫一声 ⇒ 训练人忽略告警通道）"
  # proc 判定必须排除 `bash -c '…'` 包装壳，否则"真身死了"也能凑够期望数
  grep -qF "*\" -c \"*" "$GC" \
    && ok "proc 前置排除 shell -c 包装壳（真身死了不再被包装进程掩盖）" \
    || bad "proc 前置未排除包装壳（守护真身死了也可能判定为在役）"
fi
if [ -f "$CC" ]; then
  awk -F'|' '$1=="GUARD" && $7 ~ /^[0-9a-f]{12}$/ {c++} END{exit (c>0?0:1)}' "$CC" \
    && ok "至少一行守卫钉了真实 md5（DRIFT 不是永不触发的死闸门）" \
    || bad "没有任何守卫行钉 md5 ⇒ DRIFT 永不触发，而文档却要求同步 md5"
fi

OD="$DIR/overlay-drift-check.sh"
if [ -f "$OD" ]; then
  grep -qF 'SGLANG_OVERLAY_MAP' "$OD" \
    && ok "overlay-drift-check.sh 从 start.sh 解析 overlay 映射" \
    || bad "overlay-drift-check.sh 未解析 SGLANG_OVERLAY_MAP（判不出容器视角与盘上是否一致）"
fi

# ---- 4) 可执行位（提示级：所有调用点都用 `bash <file>`，不是硬门）--------------
for f in "$DIR"/*.sh "$DIR"/*.py ${OOM:+"$OOM"}; do
  [ -f "$f" ] || continue
  [ -x "$f" ] || warn "$(basename "$f") 无执行位（chmod +x 即可；调用点用 bash 跑，不影响功能）"
done

# ---- 5) 传输完整性（可选，随包生成）------------------------------------------
if [ ! -f "$DIR/MD5SUMS" ]; then
  # 缺清单要出声：旧版把它 `if [ -f ]` 静默跳过，而文档还教人 `md5sum -c ... 2>/dev/null`
  # ⇒ 操作员看到"没有输出"会当成通过。
  warn "MD5SUMS 不在本目录 —— 传输完整性未校验（交付布局应随包带上；在役布局可无）"
else
  echo "[4] 传输完整性 md5sum -c MD5SUMS"
  # ★`--ignore-missing` 不是假想防御，它对应一种**真实存在过的形态**：交付布局的清单确实含这两项。
  #   实测（2026-09-23）`~/v41-sglang-delivery/governance/MD5SUMS` 与
  #   `~/r4-ops-work/r9-ops-20260914/evidence/delivery-20260916/governance/MD5SUMS`
  #   （均 13 项、2026-09-16/17）里 `HOW-TO-INSTALL.md`(:6) 与 `oom_gate.sh`(:9) 都在册，
  #   且同目录两文件实体也在。不加 --ignore-missing 时，那种清单拿到在役布局来校验会永远
  #   "校验不过"，而实际上位文件逐字节都对——历史上一轮四机同时 FAIL 就是这个
  #   （不是坏了，是判据用错了布局）。
  #   2026-09-23 口径实测的另一半：在役清单（本目录 17 项产物表）与归档快照
  #   （luz0.2.8pre-kit/guard，16 项）都不含此二项。**两件事同时为真**——上一版注释写成
  #   "HOW-TO-INSTALL.md 从未存在过、没有任何一版清单含 oom_gate.sh"，被并行代理用上面那两份
  #   13 项清单当场证伪。口径写错比指标漂移更毒（量具自己说谎），故留全部坐标供复核。
  #   缺项按布局解释并逐个点名；oom_gate.sh 若出现则把**真位置**单独对一次哈希——这不是放水，
  #   是把"在位的那个 oom_gate 是不是包里那个"从看不见变成看得见。
  n_all=$(grep -c . "$DIR/MD5SUMS")
  present=$(comm -12 <(awk '{print $2}' "$DIR/MD5SUMS" | sed 's/^\*//' | sort) <(ls -1 "$DIR" | sort))
  n_here=$(printf '%s\n' "$present" | grep -c . )
  absent=$(comm -23 <(awk '{print $2}' "$DIR/MD5SUMS" | sed 's/^\*//' | sort) <(ls -1 "$DIR" | sort) | tr '\n' ' ')
  if [ "$n_here" = 0 ]; then
    bad "清单 $n_all 项在本目录一项都对不上 —— 这不是布局差异，是拿错了包"
  elif (cd "$DIR" && md5sum -c --ignore-missing MD5SUMS >/dev/null 2>&1); then
    ok "MD5SUMS：在位的 $n_here/$n_all 项逐字节相符（缺项按布局解释，见下）"
  else
    bad "MD5SUMS 校验不过（在位文件与清单不符 ⇒ 传输损坏或被就地改过）"
  fi
  for _m in $absent; do
    if [ "$_m" = "oom_gate.sh" ] && [ -n "$OOM" ]; then
      h_want=$(awk -v f="$_m" '$2==f{print $1}' "$DIR/MD5SUMS")
      h_got=$(md5sum "$OOM" | awk '{print $1}')
      if [ "$h_want" = "$h_got" ]; then
        ok "oom_gate.sh 不在本目录但真位置相符：$OOM"
      else
        bad "oom_gate.sh 与清单不符（want $h_want got $h_got @ $OOM）"
      fi
    else
      warn "清单含 $_m，本目录没有（交付布局专属文件，未随在役安装）"
    fi
  done

  # ★清单"是怎么生成的"也要能被复核。排除口径（*.log 运行期产物 / *.bak-* 历史 / MD5SUMS
  #   自身）唯一落在 refresh-md5sums.sh 里，这里调它的 --check 与磁盘现状对账。
  #   背景：脚本化之前是手打 glob，2026-09-23 重建时把两个运行期日志钉进了清单（16→18），
  #   而日志内容自变 ⇒ `md5sum -c` 几分钟后必然变红 ⇒ 闸门自失效、真损坏也没人看。
  if [ -f "$DIR/refresh-md5sums.sh" ]; then
    if _out=$(bash "$DIR/refresh-md5sums.sh" --check 2>&1); then
      # 剥掉子进程的 ANSI 色码：否则嵌套的绿色转义会原样打进本行（外观像损坏）
      ok "清单生成口径可复核：$(printf '%s\n' "$_out" | tail -1 | sed -e 's/\x1b\[[0-9;]*m//g' -e 's/^ *//')"
    else
      bad "清单与磁盘现状不一致（或存在未分类文件）——逐行如下："
      printf '%s\n' "$_out" | sed 's/^/      /'
    fi
  else
    warn "refresh-md5sums.sh 不在 —— 清单生成口径无法复核（只能看 md5sum -c 的结果）"
  fi
fi

# ---- 6) 行为断言：三处"闸门沉默"的历史缺陷必须已经被修掉 ----------------------
# 为什么这里"跑一遍"而不是 grep：B1/B2 都是**计数与渲染口径**的缺陷（打印 FAIL 却退出 0、
# role=all 的行永不判定），grep 只能证明字符串还在文件里，证明不了行为已变。这三条来自
# 2026-09-17 的对抗式交叉审核，其中 B3 的代价是真实的：01 上那枚停泊桩**挂了 6 天**而
# status/check 一路报 PASS/rc=0。
# ⚠ 在临时目录里跑**副本**：guardctl 的 alert() 会写 guard-alerts.log，不能在在役目录里跑。
if [ -f "$GC" ]; then
  T=$(mktemp -d /tmp/vg-behav.XXXXXX)
  cp "$GC" "$T/guardctl.sh"
  {
    printf 'GUARD|all|no-such-unit-zzz.service|simple|always|-|-|no|行为断言用合成项\n'
    printf 'TIMER|all|no-such-zzz.timer|no-such-zzz.service|no|行为断言用合成定时器\n'
  } > "$T/g.conf"
  export GUARD_CONF="$T/g.conf" GUARD_CHECK_GATEWAY=0
  # B1：required=no 的失效也必须让退出码非 0（旧版：打印 FAIL + "CHECK RESULT: ALL-OK" + rc=0）
  if bash "$T/guardctl.sh" check >/dev/null 2>&1; then
    bad "B1 回归：required=no 的守卫失效时 check 仍返回 0（会一边打印 FAIL 一边宣布 ALL-OK）"
  else
    ok "B1 行为：required=no 的失效计入问题数（check 退出码非 0）"
  fi
  # B2：role=all 的注册行必须能被判定（旧版：read_* 与显示循环两处都只认本机 role ⇒ 永不判定）
  if bash "$T/guardctl.sh" explain no-such-unit-zzz.service >/dev/null 2>&1; then
    ok "B2 行为：role=all 的注册行会被判定（explain 找得到）"
  else
    bad "B2 回归：role=all 的行仍被判为'没有匹配的守卫'（该行将永不被检查）"
  fi
  unset GUARD_CONF GUARD_CHECK_GATEWAY
  rm -rf "$T"
  # B3：停泊的链脚本必须报 HELD（旧版把它"翻译"成评估前像 ⇒ 渲染成 PASS）
  if grep -qE 'HELD\|链脚本是' "$GC"; then
    ok "B3 行为：停泊的 RECOVERY 链脚本是一等结论 HELD（不再渲染成 PASS）"
  else
    bad "B3 回归：停泊链脚本没有 HELD 结论（自愈链被关掉会以绿色呈现）"
  fi
fi

# ---- 结论 -------------------------------------------------------------------
echo
if [ "$fails" = 0 ]; then
  printf '\033[32mVERDICT: PASS\033[0m —— %d 项检查全过\n' "$checks"
  exit 0
fi
printf '\033[31mVERDICT: FAIL\033[0m —— %d 项检查中有 %d 项失败\n' "$checks" "$fails"
exit 1
