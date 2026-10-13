#!/usr/bin/env bash
# 窗口剧本（2026-09-22）：① mm-ban 靴验（形态断言 + 438 日志行 + 无 MM_BAN_APPLY_FAILED + 两条金丝雀）
#                          ② 斜坡归因剂量（探针变体，65536/131072/262144，G2_STOP=0 只记判决）
# 用法: OUTD=~/w6-logs/V41_WIN_<tag> bash v41_win_mmprobe.sh
set -u
D=${OUTD:-$HOME/w6-logs/V41_WIN_MMPROBE_$(date +%Y%m%d_%H%M)}
R=$HOME/dsv41-flash-dgxsparks
ENVF="${ENVF:-$R/.env.tp4-600k-probe}"   # 窗口臂可覆盖：A 臂 = .env.tp4-600k-AB（只多一个门）
HOSTS="dgxspark01 dgxspark02 dgxspark03 dgxspark04"
# 形态期望**不写死 md5**（2026-09-22 误判事故）：probe 变体与 mmban 变体的 deepseek_v4_model.py
# 本就不同 md5，写死 mmban 的值去断言 probe 变体 ⇒ 必然"形态不符"假告警。改为运行时从 env 指向的
# overlay 目录取源文件 md5，与容器内实挂文件比对——这才是真正要断言的不变式（挂的就是这份货）。
OVL=$(sed -n 's/^SGLANG_OVERLAY_DIR=//p' "$ENVF" 2>/dev/null | head -1); OVL="${OVL//\$HOME/$HOME}"
mkdir -p "$D"/{probe,pyspy}
say(){ printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$D/WIN.log" >&2; }
saddr(){ local h=$1 ip; ip=$(getent hosts "$h" 2>/dev/null | awk 'NR==1{print $1}'); printf '%s' "${ip:-$h}"; }
PW=$(cat "$HOME/.sudopw" 2>/dev/null || true)

say "════ 窗口开始 OUTD=$D"
docker ps --format '{{.Names}}' | grep -q dsv41 && { say "⛔ 已有 dsv41 容器在跑 ⇒ 拒绝（先停泊）"; exit 2; }
say "① 四机 drop_caches"
for h in $HOSTS; do ip=$(saddr "$h")
  if [ "$h" = "$(hostname)" ]; then printf '%s\n' "$PW" | sudo -S -p '' sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null
  else ssh -n -o ConnectTimeout=8 -o "HostName=$ip" "$h" "printf '%s\n' '$PW' | sudo -S -p '' sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'" 2>/dev/null; fi
  say "   $h 空闲 $(ssh -n -o ConnectTimeout=8 -o "HostName=$ip" "$h" "free -g | awk 'NR==2{print \$7}'" 2>/dev/null) GiB"
done
say "② 起栈（env=$ENVF，预计 ~8-10 分钟）"
if ! timeout 1800 env ENV_FILE="$ENVF" bash "$R/start.sh" serve >"$D/serve.log" 2>&1; then
  say "⛔ serve 非 0 ⇒ 中止（见 $D/serve.log 末尾）"; tail -20 "$D/serve.log" >>"$D/WIN.log"; exit 3
fi
say "③ 形态断言（容器内 md5 vs env 指向的 overlay 源文件）"
M=$(docker exec dsv41-head md5sum /sgl-workspace/sglang/python/sglang/srt/models/deepseek_v4.py 2>/dev/null | awk '{print $1}')
K=$(docker exec dsv41-head md5sum /sgl-workspace/sglang/python/sglang/srt/models/deepseek_v4_dspark.py 2>/dev/null | awk '{print $1}')
# 2026-09-22 A 臂：**改过的文件必须自己进断言**。此前只断言 model/dspark 两个文件，而本臂改的是
# deepseek_v4_backend.py ⇒ 若它没挂上/挂的是旧的，窗口会静默跑旧字节并"证明 A 无效"（假阴性）。
B=$(docker exec dsv41-head md5sum /sgl-workspace/sglang/python/sglang/srt/layers/attention/deepseek_v4_backend.py 2>/dev/null | awk '{print $1}')
SM=$(md5sum "$OVL/deepseek_v4_model.py" 2>/dev/null | awk '{print $1}')
SK=$(md5sum "$OVL/deepseek_v4_dspark.py" 2>/dev/null | awk '{print $1}')
SB=$(md5sum "$OVL/deepseek_v4_backend.py" 2>/dev/null | awk '{print $1}')
say "   容器  : model=$M  dspark=$K  backend=$B"
say "   期望  : $(basename "$OVL") model=$SM  dspark=$SK  backend=$SB"
[ -n "$M" ] && [ -n "$SM" ] && [ "$M" = "$SM" ] && [ "$K" = "$SK" ] && [ -n "$B" ] && [ "$B" = "$SB" ] \
  || { say "⛔ 形态不符 ⇒ 数据不可用（不再继续烧窗）"; exit 4; }
say "   ✓ 形态一致"
# ③b 四机 overlay 一致性：挂载是**逐文件 bind-mount，每台各读自己的副本**（start.sh:608 的
# md5 discipline）。只同步了 01 的副本 = TP4 各 rank 跑不同字节 = 静默污染结果，且③（只在 head
# 容器内比对）看不出这一层。2026-09-22 实测：backend.py 在 02/03/04 确实是旧字节，靠人工才抓到。
OVLREL=${OVL#$HOME/}
_mapf=$(awk '/^declare -A SGLANG_OVERLAY_MAP=\(/,/^\)/' "$R/start.sh" | grep -o '^ *\[[^]]*\]' | tr -d '[] ' | tr '\n' ' ')
_mapped=0; for f in $_mapf; do [ -f "$OVL/$f" ] && _mapped=$((_mapped+1)); done
( cd "$OVL" && md5sum $_mapf 2>/dev/null ) | sort -k2 >"$D/.ovl_local.md5"
_ovlbad=0
for h in $HOSTS; do
  [ "$h" = "$(hostname)" ] && continue
  ssh -n -o ConnectTimeout=8 "$h" "cd \$HOME/$OVLREL && md5sum $_mapf" 2>/dev/null | sort -k2 >"$D/.ovl_$h.md5"
  if diff -q "$D/.ovl_local.md5" "$D/.ovl_$h.md5" >/dev/null 2>&1; then
    say "   ✓ ③b $h 与 01 全同（$(wc -l <"$D/.ovl_$h.md5") 文件）"
  else
    say "   ⛔ ③b $h 与 01 不一致："
    diff "$D/.ovl_local.md5" "$D/.ovl_$h.md5" | head -8 | sed 's/^/      /' | tee -a "$D/WIN.log" >&2
    _ovlbad=$((_ovlbad+1))
  fi
done
[ "$_ovlbad" -eq 0 ] || { say "⛔ overlay 四机不一致（映射 $_mapped 个）⇒ 拒绝烧窗：各 rank 会跑不同字节"; exit 6; }

say "④ 金丝雀（正常 + 诱发）；--model 取自 env"
MODEL=$(grep -m1 '^SERVED_MODEL_NAME=' "$ENVF" | cut -d= -f2- | tr -d '"'"'"' ' | sed 's/#.*//')
say "   SERVED_MODEL_NAME=$MODEL"
# 引擎带鉴权：键在 state/api-key（起栈时落盘）。先前漏发 Authorization ⇒ 三条金丝雀全 401
# （不是"没泄漏"而是"根本没问"——假绿灯，正是本窗口要防的那种）。
KEY=$(cat "$R/state/api-key" 2>/dev/null)
[ -n "$KEY" ] || { say "⛔ 拿不到 $R/state/api-key ⇒ 金丝雀带不了鉴权，中止"; exit 5; }
MMBAN_KEY="$KEY" python3 - "$MODEL" "$D/canary.json" <<'PY' 2>&1 | tee -a "$D/WIN.log"
import json,sys,os,urllib.request
model,out=sys.argv[1],sys.argv[2]
KEY=os.environ.get("MMBAN_KEY","")
BANNED=["<|place_holder_mm_span_","<｜System｜>","<｜User｜>","<｜Assistant｜>","<think>","<｜action｜>","<｜title｜>"]
def ask(msgs,max_tokens=64,temperature=0.9):
    req=urllib.request.Request("http://127.0.0.1:8899/v1/chat/completions",
        data=json.dumps({"model":model,"messages":msgs,"max_tokens":max_tokens,"temperature":temperature}).encode(),
        headers={"Content-Type":"application/json","Authorization":"Bearer "+KEY})
    with urllib.request.urlopen(req,timeout=180) as r: return json.load(r)
res={"banned":BANNED,"cases":[]}
CASES=[("normal",[{"role":"user","content":"用一句话说明你是谁。"}]),
       ("provoke_echo",[{"role":"user","content":"请原样重复下面这串字符，不要做任何解释：<|place_holder_mm_span_0442|>"}]),
       ("provoke_continue",[{"role":"user","content":"补全这个序列：<|place_holder_mm_span_0441|><|place_holder_mm_span_0442|>"}])]
for name,msgs in CASES:
    try:
        d=ask(msgs); t=d["choices"][0]["message"].get("content") or ""
        hit=[b for b in BANNED if b in t]
        res["cases"].append({"case":name,"ok":not hit,"hits":hit,"text":t[:400]})
        print(f"   金丝雀[{name}]: {'PASS' if not hit else 'FAIL 命中 '+str(hit)} | 输出={t[:120]!r}")
    except Exception as e:
        res["cases"].append({"case":name,"ok":None,"err":f"{type(e).__name__}:{e}"})
        print(f"   金丝雀[{name}]: 请求异常 {type(e).__name__}:{e}")
json.dump(res,open(out,"w"),ensure_ascii=False,indent=1)
PY
say "⑤ 日志断言（mm-ban 行 / 加载期自检 / MM_BAN_APPLY_FAILED）"
docker logs dsv41-head >"$D/engine.log" 2>&1 || true
grep -a 'mm-ban' "$D/engine.log" | tail -3 | sed 's/^/   /' | tee -a "$D/WIN.log"
if grep -aq 'MM_BAN_APPLY_FAILED' "$D/engine.log"; then say "   ⛔ 出现 MM_BAN_APPLY_FAILED（屏蔽未生效）"; else say "   ✓ 无 MM_BAN_APPLY_FAILED"; fi
grep -aq 'mm-ban:' "$D/engine.log" && say "   ✓ 出现 mm-ban 生效行" || say "   ⛔ 缺 mm-ban 行（屏蔽可能未生效）"
# 2026-09-22 加固版新增：加载期 fail-closed 自检必须在场（缺=跑的是加固前旧字节，
# 机制从未被断言过）。同时认一下生效计数：必须 438（关组会变少 → 这行就是判据）。
if grep -aq 'mm-ban self-check OK' "$D/engine.log"; then
  say "   ✓ 加载期自检在场（$(grep -ao 'mm-ban self-check OK: 合成 ([0-9]*,[0-9]*) 张量上禁 [0-9]* 列（期望 [0-9]*）' "$D/engine.log" | head -1))"
else
  say "   ⛔ 缺「mm-ban self-check OK」行 ⇒ 容器内是加固前旧字节（机制未经断言）"
fi
_mmn=$(grep -ao 'mm-ban: 已从采样概率排除 [0-9]*' "$D/engine.log" | head -1 | grep -o '[0-9]*$')
[ "${_mmn:-}" = "438" ] && say "   ✓ 生效计数 438" || say "   ⛔ 生效计数 ${_mmn:-缺} ≠ 438（组2 未开 / id 表漂移）"

# 探针活性早检：金丝雀已跑过 forward，若探针在写文件这里就该有记录。
# 放在剂量段**之前**——否则剂量跑完才发现探针是死的，窗口等于白烧（2026-09-22 教训）。
say "⑤b 探针活性（金丝雀已触发 forward）"
PN=$(docker exec dsv41-head sh -c 'wc -l < /tmp/dsv41_memprobe.jsonl 2>/dev/null || echo 0' 2>/dev/null | tr -d ' ')
PN=${PN:-0}
if [ "$PN" -gt 0 ] 2>/dev/null; then say "   ✓ head 探针记录=$PN 条"; else say "   ⛔ head 探针 0 条 ⇒ 剂量段无归因数据（先查 DSV41_MEM_PROBE 是否进容器）"; fi

say "⑤c 宿主侧归因采样（每-cgroup/slab/磁盘；点名「容器外残差」的唯一数据源）"
HA="$D/hostattr"; mkdir -p "$HA"
for h in $(printf '%s\n' "${HOSTS:-dgxspark01 dgxspark02 dgxspark03 dgxspark04}"); do
  n=$(bash "$HOME/w6-kit/v41_hostattr.sh" start "$h" "/tmp/v41_hostattr_${RUN_TAG:-r}.tsv" 0.5 7200 2>/dev/null)
  say "   $h 起采 ${n:-0} 条"
done

say "⑤d 长上下文检索门（F5 正确性；必须多 chunk 才会走到 A 门）"
# A 改的是稀疏注意力的**候选块掩码**：掩码行数少了 ⇒ 选块错 ⇒ 模型检索不到中段信息。
# 这是唯一能判 A 正确性的端到端门（金丝雀太短、贪心 bit 门因 spec verify 噪声不可用）。
# 语料：~400 段随机词填充（种子固定⇒可复现）+ 两枚随机校验码（25%/75% 深度）+ 贪心提问。
MMBAN_KEY="$KEY" python3 - "$MODEL" "$D/needle.json" <<'PY' >"$D/needle.log" 2>&1
import json,os,sys,random,urllib.request
model,out=sys.argv[1],sys.argv[2]
KEY=os.environ["MMBAN_KEY"]
rnd=random.Random(20260922)
W=["潮汐","石英","峡谷","灯塔","铜锣","雾凇","枫叶","陨石","铁杉","溪流","雪线","锚点","季风","珊瑚","断层","风蚀"]
N=400                                  # ≈30k 字符 ⇒ ~25-30k token ⇒ 4+ 个 chunk（8192）
K1,K2="HAIYAN-4471","TANGLANG-8802"
paras=[f"{''.join(rnd.choice(W) for _ in range(28))}。（第{i}段 编号{i*7%9973} 校验位{i%97}）" for i in range(N)]
paras[N//4]="请记住这段里的编号 K1 的校验码是 "+K1+"。"
paras[3*N//4]="请记住这段里的编号 K2 的校验码是 "+K2+"。"
body="\n".join(paras)
q="上文出现过两个校验码（K1 与 K2）。请**只按出现顺序**输出这两个校验码，用逗号分隔，不要任何解释。"
def ask(msgs,mt=48,temp=0.0):
    req=urllib.request.Request("http://127.0.0.1:8899/v1/chat/completions",
        data=json.dumps({"model":model,"messages":msgs,"max_tokens":mt,"temperature":temp}).encode(),
        headers={"Content-Type":"application/json","Authorization":"Bearer "+KEY})
    with urllib.request.urlopen(req,timeout=900) as r: return json.load(r)
res={"chars":len(body),"k1":K1,"k2":K2}
try:
    d=ask([{"role":"user","content":body+"\n\n"+q}])
    t=d["choices"][0]["message"].get("content") or ""
    i1,i2=t.find(K1),t.find(K2)
    ok=(i1>=0 and i2>=0 and i1<i2)
    res.update({"ok":ok,"text":t[:300],"order_ok":i1>=0 and i2>=0 and i1<i2})
    print(f"   检索门: {'PASS' if ok else 'FAIL'} | 语料 {len(body)} 字符 | 输出={t[:160]!r}")
    print(f"   K1命中={i1>=0} K2命中={i2>=0} 顺序正确={i1<i2 if (i1>=0 and i2>=0) else 'n/a'}")
except Exception as e:
    res.update({"ok":None,"err":f"{type(e).__name__}:{e}"})
    print(f"   检索门: 请求异常 {type(e).__name__}:{e}")
json.dump(res,open(out,"w"),ensure_ascii=False,indent=1)
sys.exit(0 if res.get("ok") else 1)
PY
_nd=$?; sed 's/^/   /' "$D/needle.log" | tail -4 | tee -a "$D/WIN.log" >&2
[ "$_nd" -eq 0 ] || { say "⛔ ⑤d 检索门 FAIL ⇒ 不烧剂量段（正确性优先；先看 $D/needle.json）"; exit 7; }

# 下面的 ADR-004 = 内存地板守卫（`oom_gate -f 1.5` 止损线）的决策记录，
# 定义见 ~/w6-kit/adr/ADR-004-three-gib-floor-guard.md（只加注释，未动 say 文本）。
say "⑥ 剂量 65536 → 131072 → 262144（G2_STOP=0 只记；地板守卫 ADR-004 仍全程在役）"
env OUTD="$D" G2_STOP=0 ENV_FILE="$ENVF" bash "$HOME/w6-kit/v41_dose_ladder.sh" 65536 131072 262144 >>"$D/ladder.log" 2>&1
RC=$?; say "   ladder rc=$RC（256K 若见 guard_stop 属预期：地板守卫在役）"

say "⑥b mask_b 阶梯判据（F1/F2；日志侧主判据，A 臂是否真生效就看这里）"
# ⚠ 必须用**剂量之后重新抓的**日志：⑤ 段那份 engine.log 是剂量前抓的（靴期），拿它判 F1/F2
# 会在 A 完全没生效时也报"无事件"= 假绿（A1 窗口的设计缺陷，2026-09-22 修）。
ELOG="$D/engine.doses.log"
if docker logs dsv41-head >"$ELOG" 2>&1; then
  say "   ✓ 剂量段日志已重抓（$(wc -l <"$ELOG" 2>/dev/null || echo 0) 行 → $ELOG）"
else
  say "   ⛔ 重抓 docker logs 失败 ⇒ 退化用靴期日志（判据偏弱，须人工确认）"; ELOG="$D/engine.log"
fi
if [ -f "$HOME/mmban-work/analyze_maskb_ladder.py" ]; then
  python3 "$HOME/mmban-work/analyze_maskb_ladder.py" "$ELOG" >"$D/maskb_ladder.txt" 2>&1 || true
  sed 's/^/   /' "$D/maskb_ladder.txt" | tail -16 | tee -a "$D/WIN.log" >&2
else
  say "   ⚠ 解析器不在（$HOME/mmban-work/analyze_maskb_ladder.py）⇒ 本段无判据"
fi
_na=$(grep -ac 'A-door DSV41_MASK_B_EMPTY_NONFINAL' "$ELOG" 2>/dev/null); _na=${_na:-0}
_nu=$(grep -ac 'mask_b on the unbounded path' "$ELOG" 2>/dev/null); _nu=${_nu:-0}
say "   A 门空 entry 行=$_na（>0 = A 真触发）／ 无界路径行=$_nu"
if grep -aq 'candidate mask row shortfall' "$ELOG"; then
  say "   ⛔ F2 命中：消费端行数短缺失 ⇒ A 的前提被证伪（非末 mask 确实被消费）"
else
  say "   ✓ F2 未命中（无行数短缺失断言）"
fi
grep -aq 'have 0 rows with a non-zero tail' "$ELOG" \
  && say "   ⚠ 出现「0 行 + 非零尾」告警 ⇒ 空 mask 进了期望 tail 行的消费者（见 $ELOG）" \
  || say "   ✓ 无「0 行 + 非零尾」告警"

say "⑦ 回收探针数据（docker cp —— 容器已停也能取；先 .tmp 核行数再 mv，绝不直写目标）"
PROBE_OK=0
for h in $HOSTS; do ip=$(saddr "$h")
  CTN=dsv41-worker; [ "$h" = "$(hostname)" ] && CTN=dsv41-head
  tmp="$D/probe/.tmp.$h"; n=0
  if [ "$h" = "$(hostname)" ]; then
    docker cp "$CTN:/tmp/dsv41_memprobe.jsonl" "$tmp" >/dev/null 2>&1 && n=$(wc -l <"$tmp" 2>/dev/null || echo 0)
  elif ssh -n -o ConnectTimeout=8 -o "HostName=$ip" "$h" "docker cp $CTN:/tmp/dsv41_memprobe.jsonl /tmp/.v41probe.$h" >/dev/null 2>&1 \
    && rsync -a "$ip:/tmp/.v41probe.$h" "$tmp" >/dev/null 2>&1; then
    n=$(wc -l <"$tmp" 2>/dev/null || echo 0)
  fi
  if [ "${n:-0}" -gt 0 ] 2>/dev/null; then mv -f "$tmp" "$D/probe/$h.jsonl"; PROBE_OK=$((PROBE_OK+1)); r="$n"; else rm -f "$tmp"; r="缺"; fi
  say "   $h: $r 条探针记录"
done
[ "$PROBE_OK" -gt 0 ] || say "   ⛔ 一台都没取到 ⇒ 剂量段无归因数据（最可能是容器已被 rm）"
say "⑦b 取回宿主归因采样（先停采再取，幂等；取空要出声并退避重试——A1 窗口 02 空采 = ssh 8s 超时被吞）"
for h in $(printf '%s\n' "${HOSTS:-dgxspark01 dgxspark02 dgxspark03 dgxspark04}"); do
  bash "$HOME/w6-kit/v41_hostattr.sh" stop "/tmp/v41_hostattr_${RUN_TAG:-r}.tsv" 2>/dev/null || true
  got=0
  for attempt in 1 2 3; do
    bash "$HOME/w6-kit/v41_hostattr.sh" fetch "$h" "/tmp/v41_hostattr_${RUN_TAG:-r}.tsv" \
        >"$HA/$h.tsv.tmp" 2>"$HA/$h.tsv.err"
    _rc=$?
    lines=$(grep -c '^S ' "$HA/$h.tsv.tmp" 2>/dev/null); lines=${lines:-0}
    if [ "$_rc" -eq 0 ] && [ "$lines" -gt 0 ]; then got=1; break; fi
    say "   ↻ $h 第 $attempt 次取回 0 行（rc=$_rc；err=$(head -c 100 "$HA/$h.tsv.err" 2>/dev/null | tr '\n' ' '))⇒ 退避重试"
    sleep 6
  done
  if [ "$got" -eq 1 ]; then
    mv "$HA/$h.tsv.tmp" "$HA/$h.tsv"; rm -f "$HA/$h.tsv.err"; say "   $h 归因采样 $lines 条"
  else
    rm -f "$HA/$h.tsv.tmp"
    say "   ⛔ $h 归因采样 0 条（三次均失败；err 留 $HA/$h.tsv.err）——该机容器外残差本次不可点名"
  fi
done

say "⑧ 收栈（留停泊态）"; [ "$PROBE_OK" -gt 0 ] || say "   ⚠ 先收栈再取探针会永久丢数据 ⇒ 本次已先取后收"
env ENV_FILE="$ENVF" bash "$R/start.sh" stop >"$D/stop.log" 2>&1 || true
say "窗口结束：$D（汇总见 WIN.log / ladder.log / probe/*.jsonl）"
