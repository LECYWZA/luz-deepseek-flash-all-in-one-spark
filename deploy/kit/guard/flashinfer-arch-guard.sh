#!/usr/bin/env bash
# flashinfer-arch-guard.sh —— SM121 上的 flashinfer AOT 取件体检
#
# 背景（2026-09-16 步骤 0 定谳）：
#   flashinfer 的 JitSpec.try_load() 逻辑是
#       if self.is_aot: return self.load(self.aot_path)      # is_aot = aot_path.exists()
#   —— 只要预编译包（flashinfer_jit_cache）里有同名 .so，就**直接取件，不做任何 arch 校验**。
#   于是「构造不抛错」≠「能在 SM121 上跑」：如果那个 .so 里只有 sm_100a/sm_103a 的 cubin
#   （arch-accelerated 对 SM121 不向前兼容）且无 PTX 兜底，就会在**首次核启动**时才炸，
#   而且报错点离病因很远。
#
#   上游 #5237（flashinfer 上游编号，未附链接，见 ~/w6-kit/REFERENCE.md）只解开了 Python 层的 arch 过滤器（supported_major_versions），
#   **治不了取件这一层**；而 #5237（同上，见 ~/w6-kit/REFERENCE.md）的靶子 moe_utils 经实测**根本不在我方路径上**
#   （我方 MoE 走 b12x）。真正该做的是**对在役路径做 arch 体检**，这就是本脚本。
#
# 用法：
#   flashinfer-arch-guard.sh             # 只查「当前进程真正映射进来」的模块（快，生产可跑）
#   flashinfer-arch-guard.sh --audit     # 扫整个 AOT 包，列出「无 12x cubin 且无 PTX」的模块（慢，只读）
#   flashinfer-arch-guard.sh --quiet     # 只在 FAIL 时输出
#
# 判定：模块 PASS ⇔ 它的 ELF cubin 里含 12.x arch（sm_120/sm_120a/sm_120f/sm_121/sm_121a）
#       **或** 含 PTX（compute_*，可由驱动 JIT 到 SM121）。两者皆无 ⇒ FAIL。
# 退出码：0 全过；1 有 FAIL；2 环境问题（容器没跑等）。
set -uo pipefail

CONTAINERS=(dsv41-head dsv41-worker)
MODE=live
QUIET=0
for a in "$@"; do
  case "$a" in
    --audit) MODE=audit ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "未知参数：$a" >&2; exit 2 ;;
  esac
done

say() { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }

# 一个 .so 的 arch 集合：ELF cubin 用 cuobjdump -lelf，PTX 用 cuobjdump -lptx
archs_of() {  # <container> <path>
  docker exec "$1" sh -c "cuobjdump -lelf '$2' 2>/dev/null | grep -oE 'sm_[0-9]+[af]?' | sort -u | tr '\n' ' '"
}
ptx_of() {    # <container> <path>
  docker exec "$1" sh -c "cuobjdump -lptx '$2' 2>/dev/null | grep -oE 'compute_[0-9]+[af]?' | sort -u | tr '\n' ' '"
}
# 12.x 家族 = 可在 SM121 上跑（120f/121a 是 family/arch-accelerated 变体，120 是基线）
ok_archs() {  # <arch line> <ptx line>
  printf '%s %s' "$1" "$2" | grep -qE 'sm_12[01][af]?|sm_120|compute_' && return 0
  return 1
}

total=0; fails=0; fail_list=""; ok_list=""

if [ "$MODE" = audit ]; then
  AOT=/opt/sglang/lib/python3.12/site-packages/flashinfer_jit_cache/jit_cache
  for c in "${CONTAINERS[@]}"; do
    docker ps --format '{{.Names}}' | grep -qx "$c" || continue
    say "=== $c 全包体检（$AOT）==="
    while read -r line; do
      path="${line%%|*}"; name="${line##*|}"
      a="$(archs_of "$c" "$path")"; p="$(ptx_of "$c" "$path")"
      total=$((total+1))
      if ! ok_archs "$a" "$p"; then
        fails=$((fails+1)); fail_list="$fail_list\n  [$c] $name  cubin={$a} ptx={$p}"
      fi
    done < <(docker exec "$c" sh -c "cd $AOT && for d in */; do f=\"\$d\$(basename \$d).so\"; [ -f \"\$f\" ] && echo \"$AOT/\$f|\${d%/}\"; done")
    break   # AOT 包四机同源，查一台即可
  done
  say "扫描模块数=$total  无 12x 可用产物=$fails"
  say "ℹ 包内存在不可用模块**本身不是故障**——只有在役路径真的取到它才是。"
  say "  在役路径的判据请看无参模式（live）。"
else
  for c in "${CONTAINERS[@]}"; do
    docker ps --format '{{.Names}}' | grep -qx "$c" || continue
    # 只认 comm（= 进程名前 15 字符 "sglang::schedu"）；不用 pgrep -f，否则
    # 本脚本自己在 `docker exec sh -c` 里的 argv 含同样字串会自匹配成假 PID。
    pids="$(docker exec "$c" sh -c "grep -l '^sglang::schedu' /proc/[0-9]*/comm 2>/dev/null | sed 's|/proc/||;s|/comm||'" | tr '\n' ' ')"
    if [ -z "${pids// /}" ]; then say "[$c] 无 scheduler 进程（未在役）"; continue; fi
    for p in $pids; do
      mods="$(docker exec "$c" sh -c "grep -o 'flashinfer_jit_cache/jit_cache/[^/]*' /proc/$p/maps 2>/dev/null | sed 's|.*/||' | sort -u")"
      if [ -z "$mods" ]; then say "[$c pid $p] 未映射任何 AOT 模块（全走 JIT 产物）"; continue; fi
      say "=== $c pid $p 在役 AOT 取件 ==="
      while read -r m; do
        [ -n "$m" ] || continue
        AOT=/opt/sglang/lib/python3.12/site-packages/flashinfer_jit_cache/jit_cache
        a="$(archs_of "$c" "$AOT/$m/$m.so" | xargs)"; pp="$(ptx_of "$c" "$AOT/$m/$m.so" | xargs)"
        total=$((total+1))
        if ok_archs "$a" "$pp"; then
          [ -n "$pp" ] && extra=" ptx={$pp}" || extra=""
          ok_list="$ok_list $m"
          say "  PASS  $m  cubin={$a}$extra"
        else
          fails=$((fails+1)); fail_list="$fail_list\n  [$c pid $p] $m  cubin={$a} ptx={$pp}"
          say "  FAIL  $m  cubin={$a} ptx={$pp}  ← 取到了 SM121 跑不了的产物"
        fi
      done <<< "$mods"
      say "  机型判据：SM121 ⇒ 可用 arch = {sm_120, sm_120a, sm_120f, sm_121, sm_121a} 或任意 compute_* PTX"
    done
  done
fi

if [ "$total" = 0 ]; then
  echo "flashinfer-arch-guard: 未找到可体检对象（容器未在役？）"; exit 2
fi
if [ "$fails" -gt 0 ]; then
  printf 'flashinfer-arch-guard: FAIL (%d/%d)%b\n' "$fails" "$total" "$fail_list"
  exit 1
fi
printf 'flashinfer-arch-guard: OK (%d 个取件全部 SM12x 可用:%s)\n' "$total" "$ok_list"
exit 0
