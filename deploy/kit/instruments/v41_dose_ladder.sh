#!/bin/bash
# v41_dose_ladder.sh v2 — 单流长上下文剂量阶梯（判据=内存瞬态，非 NVRM）
#
# 2026-09-22 用户令改造（v1 → v2）：
#   · **撤 NVRM 判决**（"这个门禁没有效果"）——0x51/mem_desc 族行与剂量不相关，
#     每档必出、静置不增长，拿它当停手条件等于阶梯永远走不动。NVRM 行数**只记录**。
#   · 新判据 = 「形态修复后内存瞬态峰值 ≤3G，控制在内存地板守卫（3G）范围内」：
#       硬闸 G1：剂量期四机 min 有效空闲 ≥ FLOOR_G（默认 3，**独立于守卫止损线**——守卫 2026-09-23 起
#       -f 1.5；G1 必须高于它，否则实验会一路开到守卫那条不可逆的 docker stop）
#       主闸 G2：瞬态峰值 transient = settled − min(dose) ≤ TRANSIENT_G（默认 3）
#     两闸都量在 **oom_gate 同款口径**（MemFree+Cached+SReclaimable−Shmem）上，
#     250ms 逐机采样（v41_memwatch.sh）——v1 只看剂量末一个点，峰值必然漏。
#   · 剂量驱动换 **原生 PRv3 采集器**（容器内，计时基点在请求发出前）：
#       v1 用的宿主侧 bench_v2 pr 模式计时坏（ttft 基准取在响应头之后 ⇒
#       prefill_tps 虚高 1e8），且无内存列。PRv3 另有 8192-c1=4500 的校准锚。
#
# 用法：
#   ENV_FILE=.env.tp4-600k ./v41_dose_ladder.sh 16384 32768 65536 131072 262144 524288
#   ANCHOR=1 ...   # 先跑 8192-c1 锚（对照 gate canary 基线）
#   GATES_ONLY=1 ...（只起量具自检）/ DRY_RUN=1 ...（只打印）
set -uo pipefail
export LC_ALL=C

REPO="${REPO:-$HOME/dsv41-flash-dgxsparks}"
ENV_FILE="${ENV_FILE:-.env.tp4-600k}"
# ENV_FILE 既可能是相对名（.env.tp4-600k）也可能是绝对路径（窗口脚本传 $R/.env.tp4-600k-probe）。
# 一律 "$REPO/$ENV_FILE" 拼接在后者下变成 …/dsv41-flash-dgxsparks//home/… ⇒ grep 静默读空文件。
# 2026-09-22 实测后果：拿不到 API_KEY ⇒ rc=2 空跑，整个剂量段（含三档剂量）被跳过，探针 0 条。
case "$ENV_FILE" in /*) ENV_PATH="$ENV_FILE";; *) ENV_PATH="$REPO/$ENV_FILE";; esac
HOSTS="${HOSTS:-dgxspark01 dgxspark02 dgxspark03 dgxspark04}"
OUTD="${OUTD:-$HOME/w6-logs/V41_LADDER_$(date +%Y%m%d_%H%M)}"
RUN_TAG="${RUN_TAG:-$(date +%H%M%S)}"
MW="/tmp/v41_memwatch_${RUN_TAG}.tsv"
SELF="$HOME/w6-kit/v41_memwatch.sh"
MWREPORT="$HOME/w6-kit/v41_memwatch_report.py"
CONTAINER="${CONTAINER:-dsv41-head}"
WCONTAINER="${WCONTAINER:-dsv41-worker}"
EP="${EP:-http://127.0.0.1:8899}"
FLOOR_G="${FLOOR_G:-3}"
TRANSIENT_G="${TRANSIENT_G:-3}"
# G2（transient ≤ TRANSIENT_G）语义开关（2026-09-22 用户令后定）：
#   1 = 超线即停手（判据即停手条件）；0 = 超线**只记判决不停手**，阶梯继续升档。
#   判 0 的前提是 G1（四机 min eff_idle ≥ FLOOR_G，高于守卫止损线）仍然硬停——
#   即"机器安全"由 G1 守，G2 是「修复是否达标」的验收线，两者不是一回事。
G2_STOP="${G2_STOP:-1}"
BASE_S="${BASE_S:-30}"
SETTLE_S="${SETTLE_S:-60}"
MW_IV="${MW_IV:-0.25}"
ANCHOR="${ANCHOR:-0}"

mkdir -p "$OUTD/mw"
LEDGER="$OUTD/LEDGER.tsv"
[[ -f "$LEDGER" ]] || printf "ts\tdose\tphase\ttps\twall_s\tttft_s\tmin_eff_idle_gb\tmin_free_gb\tdip_gb\tpersist_gb\ttransient_gb\tG1\tG2\tnvrm_delta\tkv_used_after\texit\tnote\n" >"$LEDGER"

# say 一律走 stderr（2026-09-22 账本写坏事故）：`read -r ... <<<"$(gate_dose ...)"` 会把
# 被调函数**及其所有子调用**的 stdout 一起捕获——mw_fetch 里的一句诊断（"量具自检：只有
# 3/4 机…"）就被当成了 min_eff_idle/dip/transient 三个字段写进账本（那行看上去像数据，
# 实际是中文句子）。诊断信息永远不许进可被捕获的 stdout。
say() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
ledger() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date '+%F %T')" "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}" "${8:-}" \
    "${9:-}" "${10:-}" "${11:-}" "${12:-}" "${13:-}" "${14:-}" "${15:-}" "${16:-}" "${17:-}" >>"$LEDGER"; }

API_KEY="$(grep -m1 '^API_KEY=' "$ENV_PATH" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"'')"
MODEL="$(grep -m1 '^SERVED_MODEL_NAME=' "$ENV_PATH" 2>/dev/null | cut -d= -f2-)"
# 引擎实际认可的那把在 state/api-key（每次起栈由 boot.py 落盘）；env 里那份可能不是引擎用的。
# 有它就用它（键值绝不打印，只报来源）。
if [ -s "$REPO/state/api-key" ]; then
  API_KEY="$(cat "$REPO/state/api-key")"; KEY_SRC="state/api-key"
else
  KEY_SRC="$ENV_PATH"
fi
[[ -n "$API_KEY" ]] || { say "拿不到 API_KEY（$ENV_PATH 与 $REPO/state/api-key 都为空）"; exit 2; }
NHOST=0; for _h in $HOSTS; do NHOST=$((NHOST + 1)); done
# 地板守卫自己的日志：剂量后按「新增行里有没有地板击穿」判是不是守卫把栈停掉的
# （2026-09-22：256K 档就是守卫 ADR-004 止损 —— 必须能一眼看出，不能靠猜）。
# ADR-004 = 内存地板守卫（`oom_gate -f 1.5` 止损线，2026-09-23 起）的决策记录，
# 定义见 ~/w6-kit/adr/ADR-004-three-gib-floor-guard.md。
GLOG="$HOME/w6-kit/oom-gate/logs/oom-gate-monitor-$(hostname).log"

nvrm_remote() {
  ssh -n -o ConnectTimeout=8 "$1" 'o=$(journalctl -k --no-pager 2>/dev/null); rc=$?
    if [ $rc -ne 0 ] || [ -z "$o" ]; then echo NA; else printf "%s\n" "$o" | grep -cE "NVRM|Xid|NV_ERR"; fi' 2>/dev/null || echo NA
}

overlay_n() { docker inspect "$CONTAINER" --format '{{range .Mounts}}{{.Destination}}
{{end}}' 2>/dev/null | grep -c 'sgl-workspace/sglang'; }

# 形态自查：容器实挂 overlay 文件数 vs 本 env 指向的 overlay 目录文件数。
# 不写死数字（写死会随 overlay 增删变成假断言）：真实不变式 = 「目录里每个文件都在容器里」。
overlay_expect() {
  local dir
  dir="$(sed -n 's/^SGLANG_OVERLAY_DIR=//p' "$ENV_PATH" 2>/dev/null | head -1)"
  dir="${dir//\$HOME/$HOME}"
  [[ -n "$dir" && -d "$dir" ]] || { printf 'NA'; return; }
  find "$dir" -maxdepth 1 -type f -name '*.py' 2>/dev/null | wc -l
}

kv_used() {
  curl -s -m 8 -H "Authorization: Bearer $API_KEY" "$EP/metrics" 2>/dev/null \
    | awk '/^sglang:kv_used_tokens\{/{printf "%.0f", $2; exit}'
}
flush_cache() {
  local i code
  for i in 1 2 3 4 5 6; do
    code=$(curl -s -m 60 -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $API_KEY" "$EP/flush_cache" 2>/dev/null)
    [[ "$code" == 200 ]] && return 0
    say "  [flush] HTTP $code（大概率 warmup/在途），10s 后重试 $i/5"
    sleep 10
  done
  return 1
}

mw_start() {
  local h n=0 bad=0
  for h in $HOSTS; do
    if ! SELF="$SELF" bash "$SELF" start "$h" "$MW" "$MW_IV" 7200; then say "⛔ 采样起停失败：$h"; bad=1; fi
  done
  sleep 2
  for h in $HOSTS; do
    if [[ "$(bash "$SELF" fetch "$h" "$MW" 2>/dev/null | grep -c '^S ')" -gt 0 ]]; then n=$((n + 1)); else say "   ⚠ 无采样：$h"; fi
  done
  say "memwatch 起停核查：$n/$NHOST 机有采样"
  (( n >= NHOST )) || { say "⛔ 量具缺机（$n/$NHOST）—— 没有量具就不起剂量"; return 1; }
  return 0
}
mw_mark() { for h in $HOSTS; do bash "$SELF" at "$h" mark "$MW" "$1" >/dev/null 2>&1 || true; done; }
mw_stop() { for h in $HOSTS; do bash "$SELF" at "$h" stop "$MW" >/dev/null 2>&1 || true; done; }
# 取回：**原子**（先写 .tmp 再核点数再 mv）。2026-09-22 事故：旧版 `> 目标文件` 在 ssh
# 失败时会把该机**已有**的整轮采样截成 0 字节（02 的数据就是这样丢的——机器没坏，是量具
# 把自己的证据抹了）。取回失败一律保留旧文件 + 出声，绝不留 0 字节假文件。
mw_fetch() {
  local h f tmp c bad="" nm=0
  for h in $HOSTS "$(hostname)"; do
    f="$OUTD/mw/memwatch.$h.tsv"; tmp="$f.tmp"
    if bash "$SELF" fetch "$h" "$MW" >"$tmp" 2>/dev/null; then c=$(grep -c '^S ' "$tmp" 2>/dev/null); else c=0; fi
    if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -gt 1 ]; then mv -f "$tmp" "$f"; else
      rm -f "$tmp"; bad="${bad:+$bad,}$h"; say "   ⚠ 取回失败（保留旧文件，本档该机不可用）：$h"
    fi
  done
  MW_FETCH_BAD="$bad"
  for f in "$OUTD"/mw/memwatch.*.tsv; do
    [[ -f "$f" ]] || continue
    if grep -q '^S ' "$f" && { [[ -z "${MW_EXPECT_MARKS:-}" ]] || grep -q '^M ' "$f"; }; then nm=$((nm + 1)); fi
  done
  NM_OK=$nm
  # 只有「该有标记的场景」（剂量档）才把缺标记当告警——GATES_ONLY 本就不打标记，
  # 在那里喊狼来了只会训练出「忽略这行」的习惯（本量具存在的意义正是不静默）。
  (( nm >= NHOST )) || say "⚠ 量具自检：只有 $nm/$NHOST 机${MW_EXPECT_MARKS:+（含标记）}数据可用"
}

# ── 探针快照（2026-09-22 事故后加固）───────────────────────────────────────────
# 用 docker cp 而不是 `docker exec cat`：cp **对已停容器同样有效**，而 exec 只对运行中的
# 容器有效。上一轮 256K 档被地板守卫止损（容器 stop）后，⑦ 步 exec 全部失败；更糟的是
# 那里写的是 `docker exec … > 目标文件`——重定向**先**把目标截成 0 字节再执行，于是
# 已经把 01/03/04 采回来的证据被自己抹掉，随后 ⑧ 的 stop 又把容器 rm 掉 ⇒ head 的 57 条
# 记录永久丢失。两条纪律：① 每档都取（容器被 rm 就再也取不到）② 先写 .tmp、核到行数再 mv。
probe_snapshot() { # $1=tag（dose 值 / final）
  local tag=$1 host ctn tmp n ok=0 tot=0
  mkdir -p "$OUTD/probe"
  for host in $HOSTS; do
    ctn="$WCONTAINER"; [[ "$host" == "$(hostname)" ]] && ctn="$CONTAINER"
    tmp="$OUTD/probe/.tmp.$host.$tag"; n=0
    if [[ "$host" == "$(hostname)" ]]; then
      docker cp "$ctn:/tmp/dsv41_memprobe.jsonl" "$tmp" >/dev/null 2>&1 && n=$(wc -l <"$tmp" 2>/dev/null || echo 0)
    elif ssh -n -o ConnectTimeout=8 "$host" "docker cp $ctn:/tmp/dsv41_memprobe.jsonl /tmp/.v41probe.$tag" >/dev/null 2>&1 \
      && rsync -a "$host:/tmp/.v41probe.$tag" "$tmp" >/dev/null 2>&1; then
      n=$(wc -l <"$tmp" 2>/dev/null || echo 0)
    fi
    if [[ "${n:-0}" =~ ^[0-9]+$ ]] && [ "${n:-0}" -gt 0 ]; then
      mv -f "$tmp" "$OUTD/probe/$host.$tag.jsonl"; ok=$((ok + 1)); r="$n"
    else
      rm -f "$tmp"; r="缺"
    fi
    printf '   探针快照[%s] %-11s %s 条\n' "$tag" "$host" "$r" >&2
    tot=$((tot + 1))
  done
  say "   探针快照[$tag]：$ok/$tot 机取到"
}

gate_dose() { # $1=dose → "G1 G2 minid trans dip persist minfree NHOST_OK"  #   第 8 个 token = 有效机数（NM_OK）——调用方据此判「量具缺机 ⇒ 本档数据无效」。
  mw_fetch
  local js="$OUTD/mw/report.json"
  python3 "$MWREPORT" "$OUTD/mw" --floor "$FLOOR_G" --transient "$TRANSIENT_G" --settle "$SETTLE_S" \
    --json "$js" >"$OUTD/mw/report.$1.txt" 2>&1
  python3 - "$js" "$1" "${NM_OK:-0}" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1]))
except Exception:
    print("NA NA NA NA NA NA NA NA"); sys.exit(0)
for r in d["doses"]:
    if r["dose"]==sys.argv[2]:
        print(("OK" if r["G1_floor_ok"] else "FAIL"), ("OK" if r["G2_transient_ok"] else "FAIL"),
              r["min_eff_idle_gib"], r["max_transient_gib"], r["max_dip_gib"],
              r["hosts"][r["worst_host"]]["persist_gib"], r["min_free_gib"], sys.argv[3]); break
else:
    print("NA NA NA NA NA NA NA")
PY
}

run_dose() { # $1=dose → "tps wall ttft"
  local dose="$1" tmo log after_dir
  tmo=$(( dose / 4500 * 6 + 300 ))
  log="$OUTD/prv3_${dose}.log"
  timeout "$tmo" docker exec -e PREFILL_SIZES="$dose" -e CONCURRENCIES=1 \
    "$CONTAINER" python3 /state/prv3_collector.py >"$log" 2>&1
  local rc=$?
  after_dir=$(ls -t "$REPO/state/bench-results" 2>/dev/null | head -1)
  python3 - "$REPO/state/bench-results/$after_dir" "$dose" "$rc" <<'PY'
import json,sys,statistics,os
d, dose, rc = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    recs=json.load(open(os.path.join(d, f"{dose}-c1-w0.json")))
except Exception:
    print("NA NA NA"); sys.exit(0)
good=[r for r in recs if not r.get("error")]
if not good:
    print("NA NA NA"); sys.exit(0)
wall=max(r["t_end"] for r in good)-min(r["t0"] for r in good)
tot=sum(r["prompt_tokens"] for r in good)
tt=[r["ttft_s"] for r in good if isinstance(r.get("ttft_s"),(int,float))]
print(f"{tot/wall if wall else 0:.0f} {wall:.2f} {(statistics.median(tt) if tt else float('nan')):.3f}")
PY
}

say "端点=$EP env=$ENV_FILE 容器=$CONTAINER 输出=$OUTD"
say "闸门：G1 四机 min eff_idle ≥ ${FLOOR_G}G（高于守卫止损线 -f，硬停手）；G2 transient ≤ ${TRANSIENT_G}G（G2_STOP=${G2_STOP}，0=只记判决）；NVRM 仅记录"
say "采样：memwatch ${MW_IV}s/发 四机；基线窗 ${BASE_S}s；静置 ${SETTLE_S}s"

if [[ -z "${SKIP_ENGINE_CHECK:-}" ]]; then
  if systemctl --user is-active --quiet dsv41-serve.service 2>/dev/null; then
    say "⛔ dsv41-serve.service active —— 开窗纪律要求先 systemctl --user stop（拒绝在保活单元下跑剂量）"
    exit 3
  fi
  if ! curl -fsS -m 8 -H "Authorization: Bearer $API_KEY" "$EP/v1/models" >/dev/null 2>&1; then
    say "⛔ 引擎 /v1/models 不可达（栈未就绪）"; exit 3
  fi
fi
_ov_live=$(overlay_n); _ov_exp=$(overlay_expect)
say "形态自查：容器实挂 overlay 文件数=$_ov_live / overlay 目录=$_ov_exp"
if [[ -n "${SKIP_ENGINE_CHECK:-}" ]]; then
  # 只给「量具自检」用（栈停着时验证采样/取回/报告链路）。**不许**在跳过的状态下跑剂量：
  # 形态自查是「容器里跑的确实是我们认定的那份 overlay」的唯一断言，跳过它采到的数不算数。
  say "⚠ SKIP_ENGINE_CHECK=1：跳过服务/overlay 前置（仅限量具自检，不得跑剂量）"
elif [[ "$_ov_exp" != NA && "$_ov_live" != "$_ov_exp" ]]; then
  say "⛔ overlay 挂载数不一致（目录里有文件没进容器）⇒ 形态不是我们认定的那个，拒绝起剂量"
  exit 3
fi
NVRM0=$(nvrm_remote "$(hostname)")
say "NVRM 基线（仅记录）：本机=$NVRM0"

if [[ -n "${GATES_ONLY:-}" ]]; then
  mw_start || exit 1
  sleep 5; mw_fetch
  for f in "$OUTD"/mw/memwatch.*.tsv; do printf '    %-30s %s 行\n' "$(basename "$f")" "$(grep -c '^S ' "$f")"; done
  mw_stop
  say "GATES_ONLY 结束（未起剂量）"; exit 0
fi

[[ $# -gt 0 ]] || { say "用法：$0 <dose...>（或 GATES_ONLY=1）"; exit 2; }
DOSES=("$@"); [[ "$ANCHOR" == 1 ]] && DOSES=(8192 "${DOSES[@]}")

if [[ -n "${DRY_RUN:-}" ]]; then
  for d in "${DOSES[@]}"; do
    say "DRY: dose=$d → docker exec -e PREFILL_SIZES=$d -e CONCURRENCIES=1 $CONTAINER python3 /state/prv3_collector.py"
  done
  exit 0
fi

mw_start || exit 1
MW_EXPECT_MARKS=1   # 剂量档开始后「缺标记」才算量具缺机（GATES_ONLY 不打标记，不适用）
RC=0
for dose in "${DOSES[@]}"; do
  say "══ 剂量 $dose（单流 c=1，容器内原生 PRv3）"
  if ! flush_cache; then
    say "⛔ flush_cache 持久失败 ⇒ 停手（跨档 radix 复用=虚高 + 内存累积双坑）"
    # 16 个字段：dose,phase, 之后 12 空（tps..kv_used_after）, exit=4, note
    ledger "$dose" "flush" "" "" "" "" "" "" "" "" "" "" "" "" 4 "flush_failed"
    RC=1; break
  fi
  kv_before=$(kv_used)
  say "  静置 ${BASE_S}s 建基线（kv_used=$kv_before）…"
  sleep "$BASE_S"
  mw_mark "START:$dose"
  gmark=$(wc -l <"$GLOG" 2>/dev/null || echo 0)
  read -r tps wall ttft < <(run_dose "$dose")
  mw_mark "END:$dose"
  say "  PRv3: tps=$tps wall=${wall}s ttft=${ttft}s"
  say "  静置 $((SETTLE_S + 30))s 等回落（idle-release）…"
  sleep $((SETTLE_S + 30))
  kv_after=$(kv_used)
  read -r G1 G2 MINID TRANS DIP PERSIST MINFREE NHOK <<<"$(gate_dose "$dose")"
  # 量具不完整（缺机/无数字）⇒ 本档**全列 NA**：宁可空着，也不许把诊断句子当数据写进账本。
  VOK=1
  if [[ "$G1" != OK && "$G1" != FAIL ]] || [[ ! "${NHOK:-0}" =~ ^[0-9]+$ ]] || [ "${NHOK:-0}" -lt "$NHOST" ]; then VOK=0; fi
  if [[ "$VOK" == 0 ]]; then
    say "  ⛔ 量具不完整（有效机 ${NHOK:-?}/$NHOST）⇒ 本档内存列全部写 NA"
    MINID=NA; TRANS=NA; DIP=NA; PERSIST=NA; MINFREE=NA; G1=NA; G2=NA
  fi
  say "  内存：min_eff_idle=${MINID}G min_free=${MINFREE}G dip=${DIP}G persist=${PERSIST}G transient=${TRANS}G | G1=$G1 G2=$G2"
  probe_snapshot "$dose"    # 每档先取走探针证据：容器可能在本档末被守卫 stop、被 ⑧ rm
  grep -E 'base=' "$OUTD/mw/report.$dose.txt" 2>/dev/null | sed 's/^/    /'
  # 趋势列只在「本档有效」时算：失败档的 settled 窗落在守卫杀栈之后（117G 空闲），
  # 差值毫无意义（旧版写出的 +113.17 就是这么来的）。
  DTRANS=""
  if [[ "$VOK" == 1 && "$tps" != NA ]]; then
    DTRANS=$(python3 - "$OUTD/mw/report.json" "$dose" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: print(""); raise SystemExit
for r in d["doses"]:
    if r["dose"]==sys.argv[2]:
        v=r.get("d_transient_gib"); print("" if v is None else f"{v:+.2f}"); break
PY
)
  fi
  say "  Δtransient${DTRANS:+=${DTRANS}G}（相对上一档；趋势列，不参与判决）"
  NVNOW=$(nvrm_remote "$(hostname)")
  if [[ "$NVNOW" =~ ^[0-9]+$ && "$NVRM0" =~ ^[0-9]+$ ]]; then NVD=$((NVNOW - NVRM0)); else NVD=NA; fi
  say "  NVRM 本机 $NVRM0 → $NVNOW（增量 $NVD，仅记录不判决）"
  # 栈是否还活着 + 是不是守卫停的（剂量末的收尾判据，两条都写进账本 note）
  CSTATE="$(docker inspect "$CONTAINER" --format '{{.State.Status}}/{{.State.ExitCode}}' 2>/dev/null)"
  note=""
  if [[ -n "$CSTATE" && "$CSTATE" != running/* ]]; then
    RC=1; note="container_down($CSTATE)"
    if tail -n +$((gmark + 1)) "$GLOG" 2>/dev/null | grep -q '地板击穿'; then
      # 下面的 ADR-004 = 内存地板守卫（`oom_gate -f 1.5` 止损线，2026-09-23 起）的决策记录，
      # 定义见 ~/w6-kit/adr/ADR-004-three-gib-floor-guard.md（只加注释，未动 note 值与 say 文本）。
      note="$note,guard_stop(ADR-004)"; say "  ⛔ 容器已退出：$CSTATE，且守卫日志出现「地板击穿」⇒ 守卫止损（按 ADR-004）"
    else
      say "  ⛔ 容器已退出：$CSTATE（守卫日志无地板击穿行 ⇒ 非守卫止损，另查）"
    fi
  fi
  if [[ "$VOK" == 0 ]]; then RC=1; note="${note:+$note,}meter_incomplete(${NHOK:-?}/$NHOST)"; fi
  if [[ "$G1" == FAIL ]]; then RC=1; note="${note:+$note,}floor_breach(G1)"; fi
  if [[ "$G2" == FAIL ]]; then
    if [[ "$G2_STOP" == 1 ]]; then RC=1; note="${note:+$note,}transient>${TRANSIENT_G}G(G2,停手)"
    else note="${note:+$note,}transient>${TRANSIENT_G}G(G2,记录)"; fi
  fi
  [[ -n "$DTRANS" ]] && note="${note:+$note,}dTrans=${DTRANS}"
  if [[ "$tps" == NA ]]; then RC=1; note="${note:+$note,}no_prv3_cell"; fi
  ledger "$dose" "dose" "$tps" "$wall" "$ttft" "$MINID" "$MINFREE" "$DIP" "$PERSIST" "$TRANS" "$G1" "$G2" "$NVD" "$kv_after" "$RC" "$note"
  [[ "$RC" == 0 ]] || { say "  ⛔ 闸门未过 ⇒ 阶梯停手（不升档）"; break; }
done
mw_stop
probe_snapshot final    # 收尾再取一次（覆盖最后一段落状态；停了的容器 cp 照样有效）
mw_fetch
python3 "$MWREPORT" "$OUTD/mw" --floor "$FLOOR_G" --transient "$TRANSIENT_G" --settle "$SETTLE_S" \
  --json "$OUTD/mw/report.json" >"$OUTD/mw/report.final.txt" 2>&1
say "阶梯结束（RC=$RC）；账本=$LEDGER"
sed -n '1,12p' "$OUTD/mw/report.final.txt"
exit $RC
