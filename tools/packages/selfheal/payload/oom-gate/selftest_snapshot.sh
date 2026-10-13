#!/bin/bash
# selftest_snapshot.sh — oom_gate.sh「止损前保护」的判别式自检（2026-09-22）
#
# 为什么要有这份自检：应了本项目的头号病类——**"有机制" ≠ "机制有效"**。
# 它要能证明的不是"脚本没报错"，而是这三条断言，且每条都能变红：
#   T1 顺序：现场快照必须**早于** docker stop 存在（止损前保护的全部意义所在）
#   T2 不阻断：快照失败/被关掉，止损照旧执行、退出码不变
#   T3 不误伤：未触发门槛时不动作（--once 单采样不许顺手停容器）
# T2 的反例（V41_GATE_SNAP=0）就是 T1 的判别对照：机制一被拿掉，T1 必须报红。
#
# 全程用假 docker（PATH 前置）+ 临时目录，不碰真容器、不写真告警账、不写 syslog。
set -uo pipefail

GATE="$(cd "$(dirname "$0")" && pwd)/oom_gate.sh"
[ -f "$GATE" ] || { echo "找不到 $GATE"; exit 2; }
TMP=$(mktemp -d /tmp/oomgate-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
cat > "$TMP/bin/docker" <<'STUB'
#!/bin/bash
echo "docker $*" >> "$FAKE_DOCKER_LOG"
case "$1" in
  # ★夹具要点：必须吐出一个名字，否则 `for c in $(docker ps ...)` 循环体永不执行，
  # 断言会"因为没有容器"而假绿——这正是本项目头号病类（测试环境而非测机制）。
  # ps 故意只给 **12 位短 id**（真 docker 的真实行为），让 cgroup 路径必须靠全 id/PID 反查，
  # 否则 30-docker.txt 会静默落空——T5 就是钉这条。
  ps)   echo "vllm-v41-head"; exit 0 ;;
  inspect) echo "${FAKE_CID_FULL}|${FAKE_CID_PID}|/vllm-v41-head"; exit 0 ;;
  stop)
    # ★判别点：止损**执行的那一刻**，现场文件是否已经在盘上
    if ls -1 "${V41_GATE_SNAP_DIR:-/nonexistent}"/*/10-meminfo.txt >/dev/null 2>&1; then
      echo "ORDER stop_after_snapshot=yes" >> "$FAKE_DOCKER_LOG"
    else
      echo "ORDER stop_after_snapshot=no" >> "$FAKE_DOCKER_LOG"
    fi
    ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/docker"

PASS=0; FAIL=0
ck() {  # $1=描述 $2=0/1(真/假)
  if [ "$2" = 1 ]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1"; FAIL=$((FAIL+1)); fi
}

export PATH="$TMP/bin:$PATH"
export FAKE_DOCKER_LOG="$TMP/docker.log"
export V41_GATE_ALERTS="$TMP/alerts.log"
export V41_GATE_LOG="$TMP/monitor.log"
export V41_GATE_NO_LOGGER=1          # 不写 syslog：演练不许制造假事故痕迹
export V41_GATE_SNAP_DIR="$TMP/snap"
# 夹具：假 docker 的 inspect 回**全 64 位 id**，PID 指向本自检 shell（其 /proc/PID/cgroup 真实可读）
export FAKE_CID_FULL="f60d33a608555a4d384bbbeb679c3d4507c980b6351f728c6630377a76c2e294"
export FAKE_CID_PID="$$"

run_gate() { : > "$FAKE_DOCKER_LOG"; : > "$V41_GATE_ALERTS"; : > "$V41_GATE_LOG"; \
             bash "$GATE" "$@" > "$TMP/out.txt" 2>&1; echo $?; }

echo "══ T1 应急线：现场必须先于 docker stop（-e 999999 强制击穿）"
export V41_GATE_SNAP=1
rc=$(run_gate monitor -e 999999 -a -f 0 -w 0 --once --iv 1)
ck "退出码=4（应急止损）" "$([ "$rc" = 4 ] && echo 1 || echo 0)"
ck "假 docker 收到过 stop" "$(grep -q '^docker stop' "$FAKE_DOCKER_LOG" && echo 1 || echo 0)"
ck "★stop 那一刻快照已在盘上（ORDER=yes）" "$(grep -q 'stop_after_snapshot=yes' "$FAKE_DOCKER_LOG" && echo 1 || echo 0)"
SD=$(ls -d "$V41_GATE_SNAP_DIR"/*/ 2>/dev/null | head -1)
ck "快照目录已建（$SD）" "$([ -n "$SD" ] && echo 1 || echo 0)"
NF=$(ls -1 "$SD" 2>/dev/null | wc -l)
ck "快照文件数 ≥8（实测 $NF）" "$([ "$NF" -ge 8 ] && echo 1 || echo 0)"
ck "10-meminfo.txt 含 MemFree 实数据" "$(grep -q '^MemFree:' "$SD/10-meminfo.txt" 2>/dev/null && echo 1 || echo 0)"
ck "00-trigger.txt 记录了原因 emer-" "$(grep -q 'why=emer-' "$SD/00-trigger.txt" 2>/dev/null && echo 1 || echo 0)"
ck "20-ps-rss.txt 有进程行" "$(grep -qE '^ *[0-9]+' "$SD/20-ps-rss.txt" 2>/dev/null && echo 1 || echo 0)"
ck "告警账已出声（CRIT 应急线击穿）" "$(grep -q '应急线击穿' "$V41_GATE_ALERTS" && echo 1 || echo 0)"
ck "日志含耗时报数" "$(grep -q '实耗 [0-9]*s' "$V41_GATE_LOG" && echo 1 || echo 0)"

echo "══ T5 逐容器 cgroup：12 位短 id 静默落空必须被治住（2026-09-22 实测缺陷）"
ck "30-docker.txt 用了全 64 位 id" "$(grep -q "$FAKE_CID_FULL" "$SD/30-docker.txt" && echo 1 || echo 0)"
ck "★真的读到了 cgroup 文件（有 ## 路径行）" "$(grep -q '^  ## ' "$SD/30-docker.txt" && echo 1 || echo 0)"
ck "含 memory.peak（事后归因关键口径）" "$(grep -q 'memory.peak' "$SD/30-docker.txt" && echo 1 || echo 0)"
# ★T5 必须在 T1-对照（会 rm -rf 快照目录）之前读 $SD，否则断言读的是空路径=假红

echo "══ T1-对照（判别性）：V41_GATE_SNAP=0 时 T1 必须报红，且止损照做"
export V41_GATE_SNAP=0
rm -rf "$V41_GATE_SNAP_DIR"
rc=$(run_gate monitor -e 999999 -a -f 0 -w 0 --once --iv 1)
ck "退出码仍=4（保护关了不改变判决）" "$([ "$rc" = 4 ] && echo 1 || echo 0)"
ck "★同一断言此时为红（ORDER=no）——证明 T1 测的是机制不是环境" \
   "$(grep -q 'stop_after_snapshot=no' "$FAKE_DOCKER_LOG" && echo 1 || echo 0)"
export V41_GATE_SNAP=1

echo "══ T2 保护动作失败不得阻断止损（目录不可写）"
export V41_GATE_SNAP_DIR=/proc/definitely-not-writable
rc=$(run_gate monitor -e 999999 -a -f 0 -w 0 --once --iv 1)
ck "退出码仍=4" "$([ "$rc" = 4 ] && echo 1 || echo 0)"
ck "假 docker 仍收到 stop" "$(grep -q '^docker stop' "$FAKE_DOCKER_LOG" && echo 1 || echo 0)"
ck "日志明说'跳过，不影响止损'" "$(grep -q '不影响止损' "$V41_GATE_LOG" && echo 1 || echo 0)"
export V41_GATE_SNAP_DIR="$TMP/snap"

echo "══ T2b 地板线（-f 999999 -n 1）同一套保护，退出码=3"
rc=$(run_gate monitor -f 999999 -n 1 -a -w 0 -e 0 --once --iv 1)
ck "退出码=3（地板止损）" "$([ "$rc" = 3 ] && echo 1 || echo 0)"
ck "现场先于 stop（ORDER=yes）" "$(grep -q 'stop_after_snapshot=yes' "$FAKE_DOCKER_LOG" && echo 1 || echo 0)"
ck "原因记为 floor-" "$(grep -q 'floor-' "$V41_GATE_LOG" && echo 1 || echo 0)"

echo "══ T3 未击穿时不动作（--once 不许顺手停容器）"
rc=$(run_gate monitor -e 0 -f 0 -w 0 -a --once --iv 1)
ck "退出码=0" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
ck "假 docker 无 stop 调用" "$(! grep -q '^docker stop' "$FAKE_DOCKER_LOG" && echo 1 || echo 0)"
ck "日志含'未触发任何动作'" "$(grep -q '未触发任何动作' "$V41_GATE_LOG" && echo 1 || echo 0)"

echo "══ T3b 仅告警模式（无 -a）即使击穿也绝不 docker stop"
rc=$(run_gate monitor -e 999999 -f 0 -w 0 --once --iv 1)
ck "无 stop 调用" "$(! grep -q '^docker stop' "$FAKE_DOCKER_LOG" && echo 1 || echo 0)"
ck "日志含'仅告警模式'" "$(grep -q '仅告警模式' "$V41_GATE_LOG" && echo 1 || echo 0)"

echo "══ T5b 反例：id 退化为短 id + PID 不存在 ⇒ 必须显式 ⚠，不许静默"
export FAKE_CID_FULL="abc123def456"; export FAKE_CID_PID=999999
: > "$FAKE_DOCKER_LOG"
bash "$GATE" monitor -e 999999 -a -f 0 -w 0 --once --iv 1 >/dev/null 2>&1
SD2=$(ls -dt "$V41_GATE_SNAP_DIR"/*/ 2>/dev/null | head -1)
ck "打印了'未命中'告警行" "$(grep -q 'cgroup 路径未命中' "$SD2/30-docker.txt" && echo 1 || echo 0)"
ck "且不再有 ## 行（此时确无数据，不是假绿）" "$(! grep -q '^  ## ' "$SD2/30-docker.txt" && echo 1 || echo 0)"
export FAKE_CID_FULL="f60d33a608555a4d384bbbeb679c3d4507c980b6351f728c6630377a76c2e294"
export FAKE_CID_PID="$$"

echo "══ T4 snapshot 子命令（运维手动抓现场）"
: > "$FAKE_DOCKER_LOG"
out=$(bash "$GATE" snapshot adhoc 2>&1); rc=$?
ck "退出码=0" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
ck "stdout 打印现场路径" "$(printf '%s' "$out" | grep -q '现场=' && echo 1 || echo 0)"
ck "目录名带 adhoc 标记" "$(printf '%s' "$out" | grep -q 'adhoc' && echo 1 || echo 0)"

echo
echo "══ 汇总：通过 $PASS / 失败 $FAIL"
[ "$FAIL" = 0 ] || { echo "⛔ 有断言未过 ⇒ 止损前保护**不可上线**"; exit 1; }
echo "✓ 全过（含判别性对照：机制一拿掉，T1 即报红）"
