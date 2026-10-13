#!/usr/bin/env bash
# boot_warmup.sh — F-10 首靴热身协议（BOOT-LOWSPEED-ROOTCAUSE-20261010 §4.2 规格，b433d01；
#   总卡 701d2d3 §三 F-10 行；W2 试点、W3 验收门配套）
#
# 【为什么存在】Fam-A 主族=V4.1 流量空窗 ≥8h 后首靴 prefill 慢模式（出生即慢、整靴恒慢、
#   重启即愈；KV-V41/W1-B1 两例）。热身=在测试/验收流量之前，用**真实 serving 请求**把
#   冷态税先缴掉（载体①分配器/硬件冷态与载体②EMPTY_CACHE 税两假设下均通用——连续 chunk
#   使分配器达稳态，调查员 §4.2 红线合规论证）。
#
# 【触发面】长空窗（≥8h；两档制〔用户裁定 2026-10-10 #11〕：GAP≥5h=哨兵必跑档、GAP≥8h=热身档；
#   空窗阈值边界 (5h,8h) 未采样=OPEN 试点期回校）。空窗时长由值守声明（GAP_H，小时；<8h 拒跑，FORCE=1 可越——如实入账）。
#   「V4.1 流量空窗」口径=末次 V4.1 形测试流量拆线 → 本次点火（非机器空闲——§2.3 勘误律）。
#
# 【协议序列（固定爬梯）】boot → 哨兵首发（tools/boot_sentinel.sh，cold 读数登记）→
#   若 SLOWBOOT → 本件热身爬梯：4×8k 真文本单发 →（短歇）→ 2×32k →（短歇）→ 1×128k →
#   末级速率 ≥0.7×per-form 锚=[WARMUP-OK] 完成横幅；<0.7×=[WARMUP-INSUFFICIENT]——
#   **不重试爬梯、不自动重启、不换靴**：标靴呈裁，不在慢靴上取正式锚/验收读数（§4.2）。
#   → 哨兵复测（RECHECK=1 缺省；恢复=记「热身可愈」继续窗，正式锚取复测后并注记）。
#
# 【量具口径（与 F-9 哨兵共用）】sd_bench --mode pr --pr-filler real --sizes <size> 单发串行
#   （禁并发——KV-V41 prep1 教训）；每调用内建 uuid fresh salt；速率=链 A=prompt_tokens/TTFT
#   （sd_bench tok_s 键）；per-form 锚表=tools/boot_sentinel_anchors.tsv（形+参钉面同哨兵：
#   ARM_ENV_FILE md5 + SPEC_EXTRA_ARGS 归一指纹——形/参不符不判，防 Fam-C 伪影）。
#
# 【🔴红线（本件存在性约束，违反=作废）】禁 drop_caches、禁任何形式的**页缓存主动预热**
#   （不 cat/vmtouch/dd 权重与语料、不触碰 /proc/sys/vm 面）——热身只用真实请求流量。
#   注：每 boot 本含四机 drop_caches（boot 流程内建），页缓存面恒冷、本件不触碰该面。
#   红线自检=selfcheck 对本件非注释行扫描禁词自证（含判别力负控：注入禁词必红）。
#
# 【锚序纪律（与 F-6 一靴一锚新鲜律相容）】冷首发/热身各级读数单独入「boot 健康档案」
#   （本件台账）**不作正式锚**；「新鲜」=热身后、盐前缀、首正式档。W 窗若需「冷态读数
#   即判据」须卡内预声明，二者不混（§4.2）。
#
# 【台账】logs/<ARM_TAG>/state/boot-warmup-ledger.jsonl（逐发+逐级+末级判档全记）+
#   boot_ledger.txt 追加 WARMUP 行。
#
# 【用法】
#   GAP_H=9 ARM_TAG=W2-XXX ARM_ENV_FILE=... SPEC_EXTRA_ARGS="..." bash tools/boot_warmup.sh
#   GAP_H=9 ... DRY_RUN=1 ...                            # DRY：只打计划
#   bash tools/boot_warmup.sh --selfcheck                # 自检（DRY 计划+级序+红线自证+负控）
# 环境变量：GAP_H(必填，小时) ARM_TAG(必填) ARM_ENV_FILE/SPEC_EXTRA_ARGS(形参钉面，同哨兵)
#   FORCE(默认 0；GAP_H<8 越权用，入账) RECHECK(默认 1；热身后哨兵复测)
#   CAMPAIGN/BASE_URL/SDBENCH/ANCHOR_TABLE/STEP_TIMEOUT_S/HEALTH_CHECK/HEALTH_WAIT_S/DRY_RUN
#   LADDER(默认 "4:8192 2:32768 1:131072"，发数:档位) LEVEL_GAP_S(默认 20，级间歇)
# 【护栏】8899 硬拒（G5）；不起靴、不 ssh、不 docker、不 flush、不动引擎状态——只发真实 PR 请求。
set -uo pipefail

CAMPAIGN="${CAMPAIGN:-$HOME/luz030-opt-campaign}"
ARM_TAG="${ARM_TAG:-}"
GAP_H="${GAP_H:-}"
FORCE="${FORCE:-0}"
RECHECK="${RECHECK:-1}"
ARM_ENV_FILE="${ARM_ENV_FILE:-}"
SPEC_EXTRA_ARGS="${SPEC_EXTRA_ARGS:-}"
BASE_URL="${BASE_URL:-http://127.0.0.1:8898/v1}"
SDBENCH="${SDBENCH:-$HOME/dsv41-flash-dgxsparks/bench/sd_bench.py}"
ANCHOR_TABLE="${ANCHOR_TABLE:-$CAMPAIGN/tools/boot_sentinel_anchors.tsv}"
STEP_TIMEOUT_S="${STEP_TIMEOUT_S:-900}"
HEALTH_CHECK="${HEALTH_CHECK:-1}"
HEALTH_WAIT_S="${HEALTH_WAIT_S:-600}"
DRY_RUN="${DRY_RUN:-0}"
LADDER="${LADDER:-4:8192 2:32768 1:131072}"
LEVEL_GAP_S="${LEVEL_GAP_S:-20}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENTINEL="$SCRIPT_DIR/boot_sentinel.sh"
GREEN_AT=0.7

# ── selfcheck 分支（DRY 计划+级序+红线 grep 自证+负控；零集群零流量）──
if [ "${1:-}" = "--selfcheck" ]; then
  python3 - "$0" <<'PYSELF'
import json, os, re, shutil, subprocess, sys, tempfile, textwrap

SCRIPT = os.path.abspath(sys.argv[1])
CAMP_ROOT = os.path.dirname(os.path.dirname(SCRIPT))
ENV43 = os.path.expanduser("~/migrate-assets/dsv41/env/PROD-R1STDLL128-spec1.env")
ARGS5 = ("--prefill-decode-interval 16 --max-queued-requests 32 --min-free-slots-delay 1 "
         "--enable-decoder-swa-bounded-replay --reasoning-parser deepseek-v41")

tmp = tempfile.mkdtemp(prefix="warmup-selfcheck-")
# mock sd_bench：按 --sizes 值出各档速率；MOCK_MODE=insufficient 时 128k 慢
mock = os.path.join(tmp, "mock_sd_bench.py")
open(mock, "w").write(textwrap.dedent('''\
    #!/usr/bin/env python3
    import json, os, sys
    argv = sys.argv[1:]
    jo = argv[argv.index("--json-out") + 1]
    size = int(argv[argv.index("--sizes") + 1])
    mode = os.environ.get("MOCK_MODE", "ok")
    ttft_by = {8192: 2.4, 32768: 8.2, 131072: 36.5}
    tok_by = {8192: 3900.0, 32768: 4290.0, 131072: 3900.0}   # 健康带（V41B/C/W1-B2 量级）
    if mode == "insufficient": tok_by[131072] = 1800.0        # 末级 <0.7×3861
    row = {"target": size, "prompt_tokens": size, "ttft_s": ttft_by[size],
           "tok_s": round(tok_by[size], 1), "filler": "real"}
    json.dump({"pr": [row]}, open(jo, "w"))
    print(f"mock warmup size={size} tok_s={tok_by[size]}")
'''))
os.chmod(mock, 0o755)

results = []
def note(ok, msg, why="-"):
    results.append((msg, bool(ok), why)); print(f"  [{'PASS' if ok else 'FAIL'}] {msg}"
                                                 + ("" if ok else f"：{why}"))

def run_case(name, env_extra, want_rc=None, must_have=(), must_not_have=(), tmpwin=None):
    env = dict(os.environ, CAMPAIGN=tmp, SDBENCH=mock, RECHECK="0", HEALTH_CHECK="0",
               ANCHOR_TABLE=os.path.join(CAMP_ROOT, "tools/boot_sentinel_anchors.tsv"),
               ARM_TAG=tmpwin or f"WC-{name}", BASE_URL="http://127.0.0.1:8898/v1",
               STEP_TIMEOUT_S="60")
    env.update(env_extra)
    p = subprocess.run(["bash", SCRIPT], env=env, capture_output=True, text=True, timeout=300)
    out = p.stdout + p.stderr
    why = []
    for s in must_have:
        if s not in out: why.append(f"缺字面[{s}]")
    for s in must_not_have:
        if s in out: why.append(f"禁字面现[{s}]")
    if want_rc is not None and p.returncode != want_rc:
        why.append(f"rc={p.returncode}≠{want_rc}")
    note(not why, name, "; ".join(why) or "OK")
    return out

print("== F-10 boot_warmup selfcheck（DRY 计划+级序+红线 grep 自证+mock 末级两态+负控；零集群零流量）==")

# W1 DRY 计划打印 + 哨兵复测 DRY 行 + 零台账写入（负控）
win = "WC-W1"
out = run_case("W1-dry-计划打印", dict(DRY_RUN="1", GAP_H="9", ARM_ENV_FILE=ENV43,
                                       SPEC_EXTRA_ARGS=ARGS5, RECHECK="1"), want_rc=0,
               must_have=("爬梯计划", "L1 8192x4", "L2 32768x2", "L3 131072x1",
                          "--mode pr --pr-filler real", "哨兵复测（RECHECK=1）",
                          "form=2de48070", "anchor=3861"),
               must_not_have=("[WARMUP-OK]",), tmpwin=win)
note(not os.path.exists(os.path.join(tmp, "logs", win, "state", "boot-warmup-ledger.jsonl")),
     "W1-dry-零台账写入(负控)", "DRY 态竟写台账")

# W2 级序正确：L1 8192 → L2 32768 → L3 131072（计划中顺序严格递增；档序=爬梯律）
i1, i2, i3 = out.find("L1 8192x4"), out.find("L2 32768x2"), out.find("L3 131072x1")
note(0 <= i1 < i2 < i3, "W2-级序正确 8192→32768→131072", f"idx={i1},{i2},{i3}")

# W3 红线自检 grep 自证：非注释行扫描禁词=零命中（禁词拼装构造，文件内不出现完整字面）
def redline_scan(path):
    toks = ["drop" + "_caches", "vm" + "touch", "posix" + "_fadvise",
            "/proc/sys/" + "vm", "dd " + "if=", "read" + "ahead"]
    hits = []
    for n, ln in enumerate(open(path, encoding="utf-8"), 1):
        if ln.lstrip().startswith("#"):
            continue
        for t in toks:
            if t in ln: hits.append((n, t))
    return hits
hits = redline_scan(SCRIPT)
note(not hits, "W3-红线自证：非注释行无禁词（页缓存主动预热面为零）", f"命中 {hits[:3]}")

# W4 红线负控：注入一条禁词调用到副本 → 扫描必须红（判别力——喂坏输入看它因正确理由变红）
#   注：注入串在文件内拼装构造（不落完整禁词字面），避免 W3 自扫误中本行。
poison = os.path.join(tmp, "poison_copy.sh")
poison_line = "\necho 3 > /proc/sys/" + "vm/" + "drop" + "_caches\n"
open(poison, "w").write(open(SCRIPT).read() + poison_line)
note(bool(redline_scan(poison)), "W4-红线负控：注入禁词必红（扫描器判别力）")

# W5 空窗门：GAP_H=3<8 拒跑（两档制 8h 热身门）；FORCE=1 越权放行且如实入账
run_case("W5a-空窗<5h 拒(负控)", dict(DRY_RUN="1", GAP_H="3", ARM_ENV_FILE=ENV43), want_rc=5,
         must_have=("ABORT: GAP_H=3.0h<8h",), tmpwin="WC-W5a")
run_case("W5b-FORCE 越权入账", dict(DRY_RUN="1", GAP_H="3", FORCE="1", ARM_ENV_FILE=ENV43,
                                    SPEC_EXTRA_ARGS=ARGS5), want_rc=0,
         must_have=("FORCE=1 越权（gap=3.0h<8h 已入账）", "爬梯计划"), tmpwin="WC-W5b")

# W6 mock 末级健康 → WARMUP-OK 横幅+台账+boot_ledger WARMUP 行
win = "WC-W6"
run_case("W6-末级≥0.7×锚-WARMUP-OK", dict(GAP_H="9", ARM_ENV_FILE=ENV43, SPEC_EXTRA_ARGS=ARGS5,
                                          MOCK_MODE="ok"), want_rc=0,
         must_have=("[WARMUP-OK]", "ratio=1.0101", "不作正式锚"), tmpwin=win)
lp = os.path.join(tmp, "logs", win, "state", "boot-warmup-ledger.jsonl")
rec = json.loads(open(lp).read().strip().splitlines()[-1]) if os.path.exists(lp) else None
note(rec and rec.get("verdict") == "WARMUP-OK", "W6-台账 verdict=WARMUP-OK")
note(rec and rec["form"]["env_md5"] == "2de48070" and rec["final"]["anchor"] == 3861.0,
     "W6-台账形钉面+末级锚 3861（128k 行）")
bl = open(os.path.join(tmp, "logs", win, "state", "boot_ledger.txt")).read()
note("WARMUP WARMUP-OK" in bl and "final_rate=3900.0" in bl, "W6-boot_ledger WARMUP 行")

# W7 mock 末级慢 → WARMUP-INSUFFICIENT：不重试不重启、标靴呈裁（判别力=唯变末级 mock 值）
win = "WC-W7"
run_case("W7-末级<0.7×锚-INSUFFICIENT", dict(GAP_H="9", ARM_ENV_FILE=ENV43, SPEC_EXTRA_ARGS=ARGS5,
                                             MOCK_MODE="insufficient"), want_rc=0,
         must_have=("[WARMUP-INSUFFICIENT]", "不重试爬梯、不自动重启", "不在慢靴上取正式锚"),
         must_not_have=("[WARMUP-OK]",), tmpwin=win)
rec = json.loads(open(os.path.join(tmp, "logs", win, "state", "boot-warmup-ledger.jsonl"))
                 .read().strip().splitlines()[-1])
note(rec.get("verdict") == "WARMUP-INSUFFICIENT" and abs(rec["final"]["ratio"] - 0.4661) < 0.005,
     "W7-台账 verdict=INSUFFICIENT ratio=1800/3861≈0.466")

# W8 负控：8899 拒；GAP_H 缺失拒
run_case("W8a-8899 拒(负控)", dict(GAP_H="6", BASE_URL="http://127.0.0.1:8899/v1"),
         want_rc=5, must_have=("ABORT: BASE_URL 含 8899",), tmpwin="WC-W8a")
run_case("W8b-无 GAP_H 拒(负控)", dict(ARM_ENV_FILE=ENV43, GAP_H=""), want_rc=5,
         must_have=("ABORT: GAP_H 未设",), tmpwin="WC-W8b")

n_pass = sum(1 for _, ok, _ in results if ok)
print(f"== selfcheck 结果：{n_pass}/{len(results)} PASS ==")
shutil.rmtree(tmp, ignore_errors=True)
sys.exit(0 if n_pass == len(results) else 1)
PYSELF
sc_rc=$?
echo "== boot_warmup --selfcheck 退出 rc=$sc_rc =="
exit "$sc_rc"
fi

# ── 守卫（红=正确理由拒跑）──────────────────────────────────────────────
case "$BASE_URL" in *8899*)
  echo "ABORT: BASE_URL 含 8899（生产口，G5 绝对隔离）: $BASE_URL" >&2; exit 5 ;; esac
if [ -z "$ARM_TAG" ] || [ "$ARM_TAG" = "unknown" ]; then
  echo "ABORT: ARM_TAG 未设（台账按 logs/<ARM_TAG>/ 落账，须窗名）" >&2; exit 5; fi
if [ -z "$GAP_H" ]; then
  echo "ABORT: GAP_H 未设（空窗小时数——V4.1 流量空窗口径，值守声明）" >&2; exit 5; fi
GAP_OK=$(python3 -c "
import sys
try: print('%.1f' % float(sys.argv[1]))
except ValueError: print('NaN')" "$GAP_H" 2>/dev/null)
if [ -z "$GAP_OK" ] || [ "$GAP_OK" = "NaN" ]; then
  echo "ABORT: GAP_H 非数值: $GAP_H" >&2; exit 5; fi
if python3 -c "exit(0 if float('$GAP_OK') < 8 else 1)" && [ "$FORCE" != "1" ]; then
  echo "ABORT: GAP_H=${GAP_OK}h<8h——未达热身触发面（两档制：≥5h 哨兵档/≥8h 热身档；边界 OPEN 试点回校）。FORCE=1 可越权（如实入账）" >&2
  exit 5
fi
[ -f "$ANCHOR_TABLE" ] || { echo "ABORT: 缺锚表 $ANCHOR_TABLE" >&2; exit 5; }
[ "$DRY_RUN" != "1" ] && [ ! -f "$SDBENCH" ] && { echo "ABORT: 缺 sd_bench $SDBENCH（DRY_RUN=1 可免）" >&2; exit 5; }
command -v python3 >/dev/null || { echo "ABORT: 无 python3" >&2; exit 5; }
if [ "$FORCE" = "1" ]; then
  echo "[WARMUP] FORCE=1 越权（gap=${GAP_OK}h<8h 已入账）——呈裁面如实记"
fi
if [ "$RECHECK" = "1" ] && [ ! -f "$SENTINEL" ]; then
  echo "[WARMUP] WARN：RECHECK=1 但缺 $SENTINEL——复测步降级跳过（入账）"; RECHECK=0; fi

# ── health 轮询（同哨兵契约）──
if [ "$HEALTH_CHECK" = "1" ]; then
  RROOT="${BASE_URL%/v1}"; code=""
  for _ in $(seq 1 $((HEALTH_WAIT_S / 15 + 1))); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$RROOT/health" 2>/dev/null)
    [ "$code" = "200" ] && break; sleep 15
  done
  if [ "$code" != "200" ]; then
    echo "[WARMUP] MEASURE-SKIP：health ${HEALTH_WAIT_S}s 内未达 200（code=${code:-none}）——不热身不判（如实红）" >&2
    exit 6
  fi
  echo "[WARMUP] health 200（$RROOT/health）→ 热身爬梯开始"
fi

# ── 主路径：形/参钉面→末级锚查→爬梯（真实 PR 流量）→末级判档→横幅+台账→（可选）哨兵复测 ──
WIN_DIR="$CAMPAIGN/logs/$ARM_TAG"
mkdir -p "$WIN_DIR/state"
export CAMPAIGN ARM_TAG ARM_ENV_FILE SPEC_EXTRA_ARGS BASE_URL SDBENCH ANCHOR_TABLE \
  STEP_TIMEOUT_S DRY_RUN LADDER LEVEL_GAP_S GREEN_AT GAP_OK FORCE WARMUP_WIN_DIR
WARMUP_WIN_DIR="$WIN_DIR"

python3 - <<'PYMAIN'
import datetime as dt
import hashlib
import json
import os
import re
import statistics
import subprocess
import sys
import time

win = os.environ["WARMUP_WIN_DIR"]
g = lambda k, d="": os.environ.get(k, d)
ARM_TAG, DRY = g("ARM_TAG"), g("DRY_RUN") == "1"
SDBENCH, BASE_URL, ANCHOR_TABLE = g("SDBENCH"), g("BASE_URL"), g("ANCHOR_TABLE")
SERVE_RAW, LADDER_S = g("SPEC_EXTRA_ARGS"), g("LADDER", "4:8192 2:32768 1:131072")
LEVEL_GAP_S, STEP_TIMEOUT = int(g("LEVEL_GAP_S", "20")), int(g("STEP_TIMEOUT_S", "900"))
GREEN_AT, GAP_H, FORCE = float(g("GREEN_AT", "0.7")), g("GAP_OK"), g("FORCE") == "1"
FILLER = "real"   # 热身律：真文本单发（禁 filler 伪口径——锚表 real 行同口径）
LEDGER = os.path.join(win, "state", "boot-warmup-ledger.jsonl")
BOOT_LEDGER = os.path.join(win, "state", "boot_ledger.txt")
ts_now = lambda: dt.datetime.now(dt.timezone.utc).strftime("%FT%TZ")
ladder = []
for part in LADDER_S.split():
    n, _, sz = part.partition(":")
    ladder.append((int(n), int(sz)))
final_size = ladder[-1][1]

# ── 1. 形/参钉面（与 F-9 哨兵共用口径：env md5+serve 指纹——形/参不符不判，防 Fam-C）──
form = {"env_file": None, "env_md5": None, "nkeys": None, "serve_md5": None, "gates": None,
        "pin_ok": False, "pin_reason": "no-env-file"}
envf = g("ARM_ENV_FILE")
if envf and os.path.isfile(envf):
    raw = open(envf, "rb").read()
    form["env_file"], form["env_md5"] = envf, hashlib.md5(raw).hexdigest()[:8]
    kv = dict(re.findall(r"^([A-Za-z_][A-Za-z0-9_.]*)=(.*)$", raw.decode(errors="replace"), re.M))
    form["nkeys"] = len(kv)
    form["pin_ok"], form["pin_reason"] = True, "ok"
elif envf:
    form["pin_reason"] = "env-file-missing"
form["serve_md5"] = (hashlib.md5(" ".join(sorted(SERVE_RAW.split())).encode()).hexdigest()[:8]
                     if SERVE_RAW.strip() else "EMPTY")

# ── 2. 末级锚查（per-form real <final_size> 行；通配 *；特异行优先）──
rows = []
for ln in open(ANCHOR_TABLE, encoding="utf-8"):
    if ln.startswith("#") or not ln.strip() or ln.startswith("env_md5"):
        continue
    c = ln.rstrip("\n").split("\t")
    if len(c) == 10:
        rows.append(dict(zip(("env_md5", "serve_md5", "filler", "size", "anchor", "band_lo",
                              "band_hi", "status", "form", "provenance"), c)))
num = lambda r: float(r["anchor"]) if r and re.match(r"^\d+(\.\d+)?$", r["anchor"] or "") else None
anchor, anch_reason = None, "no-form-pin（无 ARM_ENV_FILE 钉面）——不判，热身仍执行（预防面）"
if form["pin_ok"]:
    cands = sorted([r for r in rows if r["env_md5"] in ("*", form["env_md5"])
                    and r["serve_md5"] in ("*", form["serve_md5"]) and r["filler"] == FILLER
                    and r["size"] in ("*", str(final_size))],
                   key=lambda r: (r["env_md5"] == "*", r["serve_md5"] == "*", r["size"] == "*"))
    if cands and num(cands[0]) is not None and cands[0]["status"] == "OK":
        anchor = cands[0]
    else:
        anch_reason = f"形 {form['env_md5']}/{FILLER}/{final_size} 无锚行（或参面不符）——末级完成门不可判"

# ── 3. 爬梯（真实 serving 流量：sd_bench real 单发串行；级间短歇）──
plan_s = " → ".join(f"L{i+1} {sz}x{n}" for i, (n, sz) in enumerate(ladder))
print(f"[WARMUP] 爬梯计划：{plan_s}（filler={FILLER} 级间歇={LEVEL_GAP_S}s；"
      f"gap={GAP_H}h force={FORCE} form={form['env_md5']} serve={form['serve_md5']}）", flush=True)
if DRY and anchor:
    print(f"[WARMUP] DRY：末级 {final_size} 完成门锚={num(anchor):g}（{anchor['form']}，"
          f"带 {anchor['band_lo']}-{anchor['band_hi']}；≥{GREEN_AT}×=完成）", flush=True)

shot_dir = os.path.join(win, "state", "warmup", time.strftime("%Y%m%d-%H%M%S"))
os.makedirs(shot_dir, exist_ok=True)
levels = []
for li, (n_shots, size) in enumerate(ladder, 1):
    if li > 1 and not DRY:
        print(f"[WARMUP] 级间歇 {LEVEL_GAP_S}s（{ladder[li-2][1]}→{size}）", flush=True)
        time.sleep(LEVEL_GAP_S)
    elif li > 1:
        print(f"[WARMUP] DRY 级间歇 {LEVEL_GAP_S}s（{ladder[li-2][1]}→{size}）", flush=True)
    shots = []
    for si in range(1, n_shots + 1):
        jo = os.path.join(shot_dir, f"L{li}_s{si}.json")
        cmd = [sys.executable, SDBENCH, "--base-url", BASE_URL, "--key-file", "/dev/null",
               "--mode", "pr", "--pr-filler", FILLER, "--sizes", str(size),
               "--label", f"warmup-{ARM_TAG}-L{li}-s{si}", "--json-out", jo]
        print(f"[WARMUP] {'DRY ' if DRY else ''}L{li} shot{si}/{n_shots} size={size}: {' '.join(cmd)}", flush=True)
        if DRY:
            shots.append({"level": li, "shot": si, "size": size, "dry": True}); continue
        rec = {"level": li, "shot": si, "size": size, "json": jo}
        try:
            rc = subprocess.call(cmd, timeout=STEP_TIMEOUT)
        except subprocess.TimeoutExpired:
            rc = -9
        if rc != 0:
            rec["error"] = f"rc={rc}"; shots.append(rec); continue
        try:
            row = (json.load(open(jo)).get("pr") or [None])[0]
        except (OSError, json.JSONDecodeError):
            row = None
        if not row:
            rec["error"] = "no-pr-row"; shots.append(rec); continue
        rec.update({k: row.get(k) for k in ("prompt_tokens", "ttft_s", "tok_s")})
        print(f"[WARMUP] L{li} shot{si} size={size} tok_s={rec.get('tok_s')} "
              f"ttft={rec.get('ttft_s')}（链A）", flush=True)
        shots.append(rec)
    toks = [s["tok_s"] for s in shots if s.get("tok_s")]
    levels.append({"level": li, "size": size, "shots": shots,
                   "med_tok_s": round(statistics.median(toks), 1) if toks else None})

# ── 4. 末级判档（≥0.7×锚=完成；无锚/形参不符=不可判但热身流量已缴）──
fin = levels[-1] if levels else None
fin_rate = fin["med_tok_s"] if fin else None
a_num = num(anchor)
ratio = round(fin_rate / a_num, 4) if (fin_rate is not None and a_num) else None
if DRY:
    verdict = "DRY-RUN"
elif fin_rate is None:
    verdict = "MEASURE-FAIL"
elif a_num is None:
    verdict = "ANCHOR-NA（热身流量已缴，完成门不可判）"
else:
    verdict = "WARMUP-OK" if ratio >= GREEN_AT else "WARMUP-INSUFFICIENT"

rec = {"ts": ts_now(), "arm_tag": ARM_TAG, "dry": DRY, "protocol": "F-10 首靴热身",
       "gap_h": GAP_H, "force": FORCE, "form": form,
       "anchor": (dict(anchor, anchor=a_num) if anchor else None), "anchor_reason": anch_reason,
       "ladder_plan": LADDER_S, "levels": levels, "final": {"size": final_size, "tok_s": fin_rate,
                                                            "anchor": a_num, "ratio": ratio},
       "verdict": verdict, "thresholds": {"warmup_ok_ge": GREEN_AT},
       "base_url": BASE_URL, "sdbench": SDBENCH,
       "redline": "禁页缓存主动预热（缓存淘汰 sysctl/预热工具/cat 语料全禁）——本件只用真实请求流量"}

a_fmt = int(a_num) if (a_num is not None and a_num == int(a_num)) else a_num
warmup_line = (f"[{rec['ts']}] WARMUP {verdict} final_rate={fin_rate} size={final_size} "
               f"anchor={a_fmt if a_num else 'UNKNOWN'} ratio={ratio} gap={GAP_H}h "
               f"form={form['env_md5'] or '?'}/serve={form['serve_md5']}")

if verdict == "WARMUP-OK":
    print("\n".join([
        "═" * 68,
        f"[WARMUP-OK] 首靴热身完成：末级 {final_size} 速率 ≥ {GREEN_AT}× 形锚",
        f"  末级={fin_rate} tok/s（{FILLER} {final_size}，链A）⇒ ratio={ratio}"
        f"（锚 {a_num:g}，{anchor['form']}，带 {anchor['band_lo']}-{anchor['band_hi']}）",
        "  热身可愈性=阳性（Fam-A 处置面数据；若哨兵首发 SLOWBOOT→复测恢复=记「热身可愈」继续窗）",
        "  锚序纪律：冷首发/热身各级读数单独入 boot 健康档案**不作正式锚**——",
        "  正式锚=热身后、盐前缀、首正式档（F-6 一靴一锚新鲜律，二者不混）。",
        "═" * 68]), flush=True)
elif verdict == "WARMUP-INSUFFICIENT":
    print("\n".join([
        "═" * 68,
        f"[WARMUP-INSUFFICIENT] 末级 {final_size} 速率 < {GREEN_AT}× 形锚：{fin_rate}（ratio={ratio}，锚 {a_num:g}）",
        "  ── 处置纪律（fail-visible 不 fail-safe）──",
        "  不重试爬梯、不自动重启、不换靴——标靴呈裁；不在慢靴上取正式锚/验收读数（§4.2）。",
        "  Fam-A 热身可愈性=阴性证据（回 W2 呈裁面：换靴/整机体检/维护窗级处置呈用户决策）。",
        "═" * 68]), flush=True)
elif verdict == "DRY-RUN":
    print(f"[WARMUP] DRY：不写台账。would-append boot_ledger 行：\n  {warmup_line}", flush=True)
elif verdict == "MEASURE-FAIL":
    print(f"[WARMUP] MEASURE-FAIL：末级测量失败（明细入台账）——如实红，不冒充判定", flush=True)
else:
    print(f"[WARMUP] {verdict}：{anch_reason}——热身流量已缴（冷态税面照常先行），完成门待补锚后哨兵复测", flush=True)

if not DRY:
    with open(LEDGER, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    with open(BOOT_LEDGER, "a", encoding="utf-8") as f:
        f.write(warmup_line + "\n")
    print(f"[WARMUP] 台账已落：{LEDGER}（逐发明细={shot_dir}/）", flush=True)

print(json.dumps({"done": True, "verdict": verdict, "final_tok_s": fin_rate,
                  "ratio": ratio, "ledger": LEDGER}))
sys.exit(7 if verdict == "MEASURE-FAIL" else 0)
PYMAIN
rc=$?

# ── 哨兵复测（RECHECK=1 缺省；协议=热身后哨兵复测定「热身可愈」；fail-visible 不拦）──
if [ "$RECHECK" = "1" ] && [ "$rc" = 0 ]; then
  echo "[WARMUP] 哨兵复测（RECHECK=1）→ tools/boot_sentinel.sh（3 发中位对锚判档；恢复=记「热身可愈」）"
  if [ "$DRY_RUN" = "1" ]; then
    echo "[WARMUP] DRY：复测仅打印，不执行"
  else
    bash "$SENTINEL"
    echo "[WARMUP] 哨兵复测退出 rc=$?（fail-visible：不影响本件 rc）"
  fi
fi
exit "$rc"
