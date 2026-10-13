#!/usr/bin/env bash
# clock-sm-guard.sh — R6 assertion probe (2026-09-20): actual SM clock must sit near the cap.
# Read-only. Exit 0=OK, 1=FAIL, 2=SKIP (nvidia-smi unavailable / no GPU visible).
# Rationale: gb10-clock-cap GUARD only checks the unit's *status*, not the *value* —
# a unit that runs but pins the wrong cap (or a value drift in -lgc args) passes the
# unit check while the fleet silently runs at the wrong clock. This probe reads the
# real clocks.sm and compares against the approved cap band.
#
# 判据出处（2026-09-23 补，此前只写"thermal/idle dips allowed"、无出处）：
#   · CAP=2400 的来历 = BASELINE.md 的「2026-09-20 GPU 时钟基线 2200→2400（用户指令，四机同步）」节
#     （该节现位于 `BASELINE.md:326-331`；2026-09-23 本文件同批改动后实测的行号），
#     生效证据逐字为 journal "gpuClkMin 0, gpuClkMax 2400" + 生产负载下 clocks.sm **2366–2379 MHz**。
#   · 判据带下的**实测依据** = WINDOW-RUNBOOK.md §7.2：健康负载态实测 **2359–2392 MHz**（判据带 2350-2400）、
#     楔死态 ~721 MHz（513-728 家族）；该行出处为 ~/V41-DRIVER-VERIFY-VERDICT-20260922.md:59-60。
#   · ⚠️ **TOL=150 本身的推导出处未核实**（为什么取 150 而非 100/200，全部现存文档只见取值、不见推导）
#     ⇒ 判据口径以 WINDOW-RUNBOOK.md §7 为准（§7.3 明确本带是**静态**口径，开窗前必须在**负载态**复判）。
#
# 消费方（2026-09-23 补）：由 `guards.conf` 的 `archscr` kind 消费 —— PRECOND 行名 `clock-sm-actual`
#   （本文件写入时实测 `guards.conf:110`）、与 `gb10-clock-cap.service`（:102）**分列两行**：
#   一行判单元状态、一行判**实际值**。
# ⚠️ **rc2 = 判不了，而非判过了**：`nvidia-smi` 不可用或无读数时退出 2（SKIP），
#   前置渲染为 SKIP 而非 PASS —— 不要把"没判"读成"过了"。
CAP=2400
TOL=150   # MHz band under cap that counts as "pinned"（出处见上方判据出处块；推导未核实）
command -v nvidia-smi >/dev/null 2>&1 || exit 2
sm=$(nvidia-smi --query-gpu=clocks.sm --format=csv,noheader,nounits 2>/dev/null | sort -n | tail -1)
[ -n "$sm" ] || exit 2
# 空闲 ⇒ SKIP（2026-09-23 修）。本脚本的判据是「cap 是否真的生效」，而 -lgc 是
#   `gpuClkMin 0, gpuClkMax 2400` —— **空闲降频是设计行为**，此时 clocks.sm 低
#   **不携带任何 cap 有效性信息**。旧版无此分支，于是「机器空闲」被渲染成 **FAIL**，
#   而 preflight 恰恰总在空闲态跑 ⇒ 必然误报；一条总在误报的闸门最终会被无视。
#   区分器用 utilization.gpu：楔死指纹是 **util ~96% 却 clocks.sm ~721MHz**（负载高、
#   时钟低），空闲是 util ~0 —— 前者仍走下面的 FAIL 分支，不被本条豁免。
#   取不到 util（部分驱动/容器内不可见）时**不豁免**，退回原判据（保守方向）。
util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | sort -n | tail -1)
if [ -n "$util" ] && [ "$util" -lt 5 ]; then
  echo "clocks.sm=${sm}MHz 但 GPU 空闲（util=${util}%）⇒ 读数不可用于判 cap 有效性，SKIP；须在负载态复判（WINDOW-RUNBOOK §7）"
  exit 2
fi
if [ "$sm" -ge $((CAP - TOL)) ] && [ "$sm" -le "$CAP" ]; then
  echo "clocks.sm=${sm}MHz within [CAP-TOL, CAP]=[$((CAP-TOL)),$CAP] — cap effective"
  exit 0
elif [ "$sm" -gt "$CAP" ]; then
  echo "clocks.sm=${sm}MHz ABOVE cap ${CAP}MHz — unit not enforcing (drift or overridden)"
  exit 1
else
  echo "clocks.sm=${sm}MHz below ${TOL}MHz under cap ${CAP} — cap may not be effective (check unit)"
  exit 1
fi
