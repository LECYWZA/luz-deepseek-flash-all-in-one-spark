#!/usr/bin/env bash
# safe_run.sh — 运行时层内存硬护栏（census 工具链防 OOM 第三层）
# 目的: 让任何 python 解析命令在 cgroup 硬上限内运行，物理上不可能打爆 GB10 UMA 121G。
#   背景: 2026-09-29 v1 json.load RSS 8.5G / 2026-09-30 v2.1 raw_decode RSS 13.6G 两次同型事故，
#   2026-09-30 census c8 采集期间四节点用户态冻结。进程自律（MemGuard）可被未来改动破坏，
#   cgroup 是内核强制的第二道不可绕过防线。
#
# 用法（部署到节点后）:
#   scp scripts/safe_run.sh node01:~/v41-opt/tools/
#   ssh node01 'bash ~/v41-opt/tools/safe_run.sh python3 ~/v41-opt/tools/census_stream.py \
#              ~/l10-quality/r12/xxx.trace.json.gz --top 45 --json out.json --mem-limit-mb 512'
#   或设别名: alias safe-py='bash ~/v41-opt/tools/safe_run.sh'
#
# 退出码:
#   子进程正常 → 透传子进程退出码
#   42         → 解析器 MemGuard 自检自灭（见 census_stream.py --mem-limit-mb）
#   子进程被 cgroup OOM kill（SIGKILL, 检测到 dmesg oom-kill 记录）→ 提示后仍返回 137
#
# 注意:
#   - systemd-run 在 GB10 节点（DGX Spark OS 镜像）是否可用【待窗口后核验】；
#     不可用时脚本自动 fallback 到 MemGuard-only 模式并打 WARN（此时只剩解析器自律一层）。
#   - MemorySwapMax=0: UMA 上 swap 无意义且会掩盖真峰值，直接禁掉。
#   - 需 root 或有 cgroup 委派（systemd-run --user --scope 对 MemoryMax 需要 root，
#     普通用户 + UserSlices 委派场景待核验，fallback 逻辑已覆盖）。
set -euo pipefail

MEM_MAX="${SAFE_RUN_MEM_MAX:-2G}"
SWAP_MAX="${SAFE_RUN_SWAP_MAX:-0}"

if [[ $# -eq 0 ]]; then
  echo "usage: safe_run.sh <command...>   (default MemoryMax=${MEM_MAX} SwapMax=${SWAP_MAX})" >&2
  exit 64
fi

if command -v systemd-run >/dev/null 2>&1; then
  exec systemd-run --quiet --user --scope --same-dir \
    -p MemoryMax="${MEM_MAX}" -p MemorySwapMax="${SWAP_MAX}" \
    "$@"
  # --scope: 前台同步运行，退出码透传；不进 nspawn/容器，无 PID namespace 变化
else
  echo "[safe_run] WARN: systemd-run 不可用（节点待核验），fallback 到无 cgroup 模式。" >&2
  echo "[safe_run]        此时仅剩进程自律护栏（census_stream.py --mem-limit-mb），务必带上该参数。" >&2
  exec "$@"
fi
