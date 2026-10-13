#!/bin/bash
# t50_gate_boot.sh — W1/T50 门靴链（A23-α「先门后臂」的门）104 任务书 §T50 + 主计划 §八 W1
#
# 【形态】单次门靴 = A22-C1REV 带面基座 + 唯一增量 DSV41_SPARK_PREFILL_TP_SPLIT=1
#   （arms/A23-ALPHA-gate.env，A22-C1REV-spec1.env 逐字节复制+1 键）。不跑 battery 六格
#   （省时——门绿后 T51 主臂再全链），顺载 R41 水线四点 + R42 eval 三件套落基线
#   （W0 波「不单独烧靴」裁定，主计划 §八 W0 段）。产物全落 logs/A23-ALPHA/gate-boot/。
#
# 【门验收（全 grep 断言；红=现场留档后 teardown，禁带病进臂）】
#   G1 env 达容器（printenv TP_SPLIT=1）
#   G1b DSPARK_BLOCK_SIZE=5 显式断言（部署面空白②：printenv 钉扎位+四机 checkpoint+引擎
#      gamma=5 横幅三源合一——灾备复原 draft=6 漏验险封口）
#   G2 重锚版 20 锚 grep（SPARKPREFILLSPLIT-PORT-20261002 §4 清单；容器内 main-79cafec0 树）
#      + 4 个旧基座负探针（A19 拒靴六钩名——新树必须为 0）
#   G3 [prefill_split] gate=1 门报（正签名在 / gate=0、gate=(unset)、backend drifted、
#      refusing to boot 负签名不在）+ "DSV41 prefill TP split initialized"（no init collective 版）
#   G4 W21 雷反证：docker logs 无 init 期集合通信回退签名（fallback×init/comm 组合；
#      白名单=[sparse_wire] 良性横幅，20261002 诊断定谳）
#   G5 28 门横幅（[ep1f] banner complete: 28 gates reported，按机计数）+ [arm] +env=30
#      注入行（宿主侧 chain.log 本靴段；A22-C1REV 实测 29+1）
#   G6 A22 面继承断言：ROCE_TP8_READY 武装机数 4/4 + [roce_ar] REFUSED=0 + 非白名单残差=0
#   （基座带面不变式——PR 四档平证明 face 对 prefill 无扰，主计划 §八 W1）
#
# 【grep 教义（今日 8 例陷阱全沿袭 a22c1rev 已修形态）】每条断言就地配
#   「喂坏输入会因正确理由变红」反向判别注释（断言必须带判别力自检——fabricctl
#   selftest/F03 同宗）：锚定签名（grep -F 定串/BRE 中 + 为字面量）、LC_ALL=C、
#   按机计数（非横幅行数——READY 横幅×2/rank 陷阱 fc94c89）、本地变量不携 ~
#   （13975a1）、正则量词/元字符转义、白名单先行（cccf363 sparse_wire）。
#
# 【点火形态】门1 idle → 门2 fabric（tools/fabric_gate.sh，P1 回移件）→ 门3 四机 md5
#   （spark_prefill_split=eb53ea12… 重锚件；roce_ar=932fe12b… A22 面不变式）→
#   slotlock wrapper 包 boot（P0 治理：跨会话靴槽锁）→ health 200 → steady 5min → 断言链。
# 红线：accept<3.0（G3 窗 [3.0,3.5] 下沿=A2d 通道②塌陷签名）→ 中止后续；GSM8K<0.95 同。
# 教义：mkdir 先于重定向；boot 间隔≥6min+四机≥112G；8898 only；teardown 前 docker logs 必存（G5）。
set -uo pipefail
cd ~/luz030-opt-campaign
D=logs/A23-ALPHA/gate-boot; L=$D/chain.log; TS=$(date -u +%Y%m%dT%H%M%SZ); INC=~/l10-incident/a23gate-$TS
mkdir -p "$D/boot-acceptance" "$D/water" "$D/eval" "$INC"
VERDICT=$D/GATE-VERDICT.txt; : > "$VERDICT"
log(){ echo "[$(date -u +%FT%TZ)] $*" | tee -a "$L"; }
vput(){ echo "$*" >> "$VERDICT"; }
ctn(){ [ "$1" = 01 ] && echo r3boot-head || echo r3boot-worker; }
fetch_logs(){ for h in 01 02 03 04; do ssh -o ConnectTimeout=8 dgxspark$h "docker logs --since $1 $(ctn $h)" >"$D/boot-acceptance/boot$h-$2.log" 2>&1; done; }
preserve(){ fetch_logs "$1" scene; cp -r "$D/boot-acceptance" "$INC/" 2>/dev/null; log "现场已 cp → $INC"; }
bail(){ # bail <exit-code> <原因>：留档→teardown→写判定→退出（禁保靴过夜）
  local code="$1"; shift
  vput "T50-GATE: RED — $*"
  log "ABORT $* —— G5 教义：teardown 前日志已存，现场 cp → $INC"
  preserve "$BOOT_TS"; bash ~/migrate-assets/bin/r3-stop.sh >>"$L" 2>&1
  exit "$code"
}
# R41 水线四点打点（四机并行 ssh；LC_ALL=C free + 容器 RSS；dd2cf07 locale 修正沿袭）
water4(){ # water4 <phase>
  local phase="$1" h ts m rss summ=""; ts=$(date -u +%FT%TZ)
  for h in 01 02 03 04; do
    ( ssh -o ConnectTimeout=8 dgxspark$h "LC_ALL=C free -m | awk '/Mem:/ {print \$7}'; docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' 2>/dev/null | grep '^r3boot'" >"$D/water/raw-$phase-$h.txt" 2>/dev/null ) &
  done; wait
  for h in 01 02 03 04; do
    m=$(head -1 "$D/water/raw-$phase-$h.txt" 2>/dev/null)
    rss=$(tail -n +2 "$D/water/raw-$phase-$h.txt" 2>/dev/null | tr '\n' ';')
    printf '%s\t%s\tdgxspark%s\tMemAvail=%sM\tRSS=%s\n' "$ts" "$phase" "$h" "${m:-?}" "${rss:-none}" >> "$D/water/water.tsv"
    summ="$summ dgxspark$h=${m:-?}M"
  done
  log "R41 water[$phase]$summ（容器 RSS 明细 → $D/water/）"
}

# ── 门1：四机 idle（无 r3boot 容器/无链进程；自排除=链名 t50_gate，防裸 pgrep 自匹配）──
# 反向判别自检：喂「02 机有链进程在跑」形态 → pgrep 计 1>0 → 红——红因=槽被占；
# 喂本链自身 → grep -vc t50_gate 排除自匹配（nohup.selfmatch 事故形态，反向外壳）。
log "== 门1：四机 idle（无 r3boot 容器/无链进程；自排除 t50_gate）=="
for h in 01 02 03 04; do
  bad=$(ssh -o ConnectTimeout=8 dgxspark$h "docker ps -a --format '{{.Names}}' | grep -c r3boot; pgrep -af 'chain[.]sh|r3[-]boot' | grep -vc t50_gate" 2>/dev/null)
  log "idle dgxspark$h: $(echo $bad | tr '\n' ' ')"
  echo "$bad" | grep -qv '^0$' && { log "ABORT 门1 红：dgxspark$h 非净——单链串行，停手回报"; exit 1; }
done

# ── 门2：fabric 门（P1 治理回移件：F00-F10 22 项+hairpin 8192+tc in_hw+GID3 16/16）──
log "== 门2：fabric_gate（tools/fabric_gate.sh；明细 logs/fabric-gate/）=="
bash tools/fabric_gate.sh >> "$L" 2>&1 || { log "ABORT 门2 红：fabric 门 fail-closed（exit 9 语义）"; exit 9; }

# ── 门3：四机 adapter md5 对齐（重锚件身份+A22 面不变式）──
# 反向判别自检：喂「03 机还是 0607ad2e 旧件」形态 → md5 输出≠eb53ea12… → 红——红因=件身份漂移
# （越权部署件教训：eb53ea12 系另会话部署，身份必须四机断言，主计划 §八 W1）。
SPARK_MD5=eb53ea124e09da51224d7c066a69fa46   # ~/migrate-assets/dsv41/adapter/spark_prefill_split.py（本机 2026-10-02 实测）
ROCE_MD5=932fe12b5736959afa0a257e15c16acd     # ~/migrate-assets/dsv41/adapter/roce_ar.py（D1 审计四机全等值）
log "== 门3：四机 md5（spark_prefill_split=$SPARK_MD5 roce_ar=$ROCE_MD5）=="
for h in 01 02 03 04; do
  got=$(ssh -o ConnectTimeout=8 dgxspark$h "md5sum ~/migrate-assets/dsv41/adapter/spark_prefill_split.py ~/migrate-assets/dsv41/adapter/roce_ar.py" 2>/dev/null)
  echo "$got" | tee -a "$L"
  echo "$got" | grep -q "$SPARK_MD5" || { log "ABORT 门3 红：dgxspark$h spark_prefill_split md5≠eb53ea12（重锚件未对齐）"; exit 3; }
  echo "$got" | grep -q "$ROCE_MD5"   || { log "ABORT 门3 红：dgxspark$h roce_ar md5≠932fe12b（A22 面不变式破）"; exit 3; }
done

# ── 靴（经 slotlock wrapper：P0 跨会话靴槽锁；唯一增量=A23-ALPHA-gate.env 的 TP_SPLIT 键）──
BOOT_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ); log "== 靴（$BOOT_TS）：A23-ALPHA-GATE = A22-C1REV 带面 + TP_SPLIT=1（门靴，无 battery）=="
# 注：ARM_ENV_FILE 的 ~ 位于赋值前缀位（shell 展开面，13975a1 修正形态）；不进中间变量。
ARM_TAG=A23GATE SPEC=1 SPEC_EXTRA_ARGS="--prefill-decode-interval 16 --max-queued-requests 32 --min-free-slots-delay 1 --enable-decoder-swa-bounded-replay" ARM_ENV_FILE=~/luz030-opt-campaign/arms/A23-ALPHA-gate.env bash tools/boot-with-slotlock.sh bash ~/migrate-assets/bin/r3-boot-arm.sh >> "$L" 2>&1
log "boot rc=$?"
code=000
for i in $(seq 1 60); do code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8898/health 2>/dev/null); [ "$code" = "200" ] && break; sleep 20; done
[ "$code" = "200" ] || { log "ABORT health 20min 未达（code=$code）——保现场不重试原样回报"; preserve "$BOOT_TS"; exit 2; }
log "health 200 → steady 5min"; sleep 300
water4 boot   # R41 第 1 点：起靴
fetch_logs "$BOOT_TS" b1

# ── G1：env 达容器 ──
# 反向判别自检：喂「env 文件忘挂/键拼错」形态 → printenv 空 → ≠"1" → 红——红因=键未达容器（a19 门①同宗）。
e1=$(docker exec r3boot-head printenv DSV41_SPARK_PREFILL_TP_SPLIT 2>/dev/null | tail -1)
e2=$(docker exec r3boot-head printenv SGLANG_ROCE_ALLREDUCE 2>/dev/null | tail -1)
log "G1 容器 printenv: TP_SPLIT=$e1 ROCE_ALLREDUCE=$e2（G0 容器 printenv 面）"
[ "$e1" = "1" ] && [ "$e2" = "1" ] || bail 3 "G1 红：arm env 未达容器（TP_SPLIT=$e1 ROCE=$e2）"
vput "G1 env-reached: GREEN (TP_SPLIT=1 ROCE=1)"

# ── G1b：DSPARK_BLOCK_SIZE=5 显式断言（部署面空白②，主计划 §八 1eea52a：灾备复原漏验险）──
# 值面三源合一（现行产形 env 未注入、checkpoint 解析——A0S⁷ 判定卡「DSPARK_BLOCK_SIZE env
#   未显式设，checkpoint 默认解析=5」；printenv 空=合法解析态非红，非空≠5=红=显式钉扎漂移）：
#   ①容器 printenv（若注入须恰=5）②四机 checkpoint dspark_block_size=5（引擎解析源；
#   01/02=/data/models/DeepSeek-V4.1-Flash，03/04=/data/models/dsv41-net NFS）③引擎自报
#   横幅（运行态真值，armed≠路通教义）：head 'gamma=5, verify_num_draft_tokens=6' +
#   四机 server_args "speculative_num_draft_tokens': 6"（=5+1 恒等锚，BRE 中引号为字面量）。
# 反向判别自检：喂「灾备复原 draft=6」形态 → checkpoint 写 6 ⇒ ②计数 0 红；横幅 gamma=6/
#   verify=7 ⇒ ③锚计 0 红；printenv=6 ⇒ ①≠5 红——三源任一红即中止，红因=块宽漂移
#   （verify 窗与 accept 上限整体错位，S2 #7「parity 未线上核实」正身，CONFIG-BLINDSPOT §6）。
dbs_red=0
pbs=$(docker exec r3boot-head printenv DSPARK_BLOCK_SIZE 2>/dev/null | tail -1)
log "G1b printenv DSPARK_BLOCK_SIZE='$pbs'（空=checkpoint 解析合法态；非空须=5）"
{ [ -z "$pbs" ] || [ "$pbs" = "5" ]; } || { dbs_red=1; log "G1b RED：printenv DSPARK_BLOCK_SIZE=$pbs≠5（显式钉扎漂移）"; }
for h in 01 02 03 04; do
  case $h in 01|02) msrc=/data/models/DeepSeek-V4.1-Flash;; *) msrc=/data/models/dsv41-net;; esac
  ck=$(ssh -o ConnectTimeout=8 dgxspark$h "grep -Ec '\"dspark_block_size\" *: *5' $msrc/config.json" 2>/dev/null)
  log "G1b@$h checkpoint dspark_block_size=5 count=$ck（$msrc）"
  [ "${ck:-0}" -ge 1 ] || { dbs_red=1; log "G1b RED@$h：checkpoint dspark_block_size≠5（引擎解析源漂移）"; }
done
g3b=$(grep -Fc 'gamma=5, verify_num_draft_tokens=6' "$D/boot-acceptance/boot01-b1.log" 2>/dev/null || true)
n6=0
for h in 01 02 03 04; do
  c=$(grep -Fc "speculative_num_draft_tokens': 6" "$D/boot-acceptance/boot$h-b1.log" 2>/dev/null || true)
  n6=$((n6+${c:-0}))
done
log "G1b 引擎自报：head gamma=5/verify=6 锚计=$g3b；四机 server_args num_draft=6 计=$n6/4"
{ [ "${g3b:-0}" -ge 1 ] && [ "$n6" = 4 ]; } || { dbs_red=1; log "G1b RED：引擎解析面漂移（gamma 锚=$g3b num_draft6=$n6/4）"; }
[ "$dbs_red" = 0 ] || bail 3 "G1b 红：DSPARK_BLOCK_SIZE 有效值≠5（块宽漂移——verify 窗/accept 上限错位险）"
vput "G1b dspark-block-size-5: GREEN (printenv='${pbs:-unset→ckpt}' ckpt 4/4, gamma5-head + num_draft6 4/4)"

# ── G2：重锚版 20 锚 grep（容器 main-79cafec0 树；PORT 报告 §4：6 B2 主符号+14 辅助锚）──
SGL=/sgl-workspace/sglang/python/sglang
BK=srt/layers/attention/deepseek_v4_backend.py
K4=kernels/ops/attention/dsv4
V4=srt/layers/attention/dsv4/v41_indexer
ANCHORS=(
  "_low_ratio_index_topk|$BK"                    # 1 挂点类方法（backend:3073）
  "_as_int_list|$BK"                             # 2 模块级助手（backend:303）
  "is_draft_runner|$BK"                          # 3 wrap 期属性（backend:1198）
  "make_candidate_indexer(|$BK"                  # 4 结构门左手（backend:1128）
  "make_full_topk_indexer(|$BK"                  # 5 结构门右手（backend:1135）
  "_make_low_ratio_prefill_indexer_inputs|$BK"   # 6 7 位置参数 seam（backend:3176）
  "_get_low_ratio_selection|$BK"                 # 7 Selection 出口（backend:3148）
  "_publish_candidate_metadata|$BK"              # 8 原生尾切发布（backend:3213）
  "flat_index_logits_tiles|$K4/index_logits.py"  # 9 行瓦 logits（idx_logits:36）
  "select_candidate_block_ids|$K4/candidate_blocks.py" # 10 块选择（candidate_blocks:146）
  "topk_transform_ragged_v2|$K4/topk.py"         # 11 ragged topk（topk:185）
  "BlockIds|$V4/dense_blocks.py"                 # 12 int32 块表（dense_blocks:37）
  "DenseBlocksBackend|$V4/dense_blocks.py"       # 13 结构门类（dense_blocks:54）
  "get_deep_gemm_prefill_data|$V4/scoring.py"    # 14 打分数据（scoring:140）
  "write_selection|$V4/scoring.py"               # 15 原生尾写（scoring:59）
  "_DEEP_GEMM_SCORE_BUDGET_BYTES|$V4/scoring.py" # 16 预算缺省（scoring:27）
  "get_low_ratio_index_k_fp4|srt/mem_cache/deepseek_v4_memory_pool.py" # 17 fp4 K 槽（pool:1876）
  "is_extend_without_speculative|srt/model_executor/forward_batch_info.py" # 18 资格判（fbi:287）
  "def all_gather|srt/distributed/parallel_state.py"  # 19 AG 位置形参（ps:1340）
  "is_candidate_source|srt/layers/attention/dsv4/dsv41_sparse.py" # 20 indexer 四元族（sparse:188-193）
)
# 反向判别自检（负探针=判别力活体）：4 个旧基座符号（A19 拒靴缺的六钩可 grep 名）在新树必须计 0——
# 喂「误 grep 旧树 /tmp/v29-snap 形态」→ 正锚 1/4/6 计 0 红 且 负探针>0 红：两向同红=断言带判别力，
# 红因=树错非工具错。旧符号在新树 >0 同样红（=基座回退/混树部署）。
NEG_ANCHORS=(_dense_fp4_mqa_logits _index_protocol_on _candidate_indexer_primitives _DENSE_LOGITS_WIDTH_BUCKET)
log "== G2：20 锚 grep（容器树 $SGL）=="
a_pass=0; a_fail=0
for pair in "${ANCHORS[@]}"; do
  sym="${pair%%|*}"; path="${pair#*|}"
  c=$(docker exec r3boot-head grep -c -- "$sym" "$SGL/$path" 2>/dev/null || true); c=${c:-0}
  if [ "$c" -ge 1 ] 2>/dev/null; then a_pass=$((a_pass+1)); else a_fail=$((a_fail+1)); log "G2 RED 锚未命中: $sym @ $path (count=$c)"; fi
done
n_pass=0; n_fail=0
for sym in "${NEG_ANCHORS[@]}"; do
  c=$(docker exec r3boot-head grep -c -- "$sym" "$SGL/$BK" 2>/dev/null || true); c=${c:-0}
  if [ "$c" = 0 ] 2>/dev/null; then n_pass=$((n_pass+1)); else n_fail=$((n_fail+1)); log "G2 RED 负探针命中(旧基座符号出现在新树): $sym (count=$c)"; fi
done
log "G2 正锚 $a_pass/20 负探针 $n_pass/4（旧符号须全零）"
{ [ "$a_pass" = 20 ] && [ "$n_pass" = 4 ]; } || bail 4 "G2 红：20 锚未全绿（正=$a_pass/20 负=$n_pass/4）——回 d7-dev 修复，禁带病进臂"
vput "G2 20-anchors+4-negprobes: GREEN ($a_pass/20, $n_pass/4)"

# ── G3：[prefill_split] 门报（正签名在、负签名不在）──
# 反向判别自检：喂「键未注入」形态 → 横幅实为 'gate=(unset)' → 正锚 grep -Fc '[prefill_split] gate=1 ' 计 0 红
# 且负签名 gate=(unset) 命中红；喂「注入=0/漂移守卫拒」→ gate=0 / backend drifted / refusing to boot 命中红。
# 正锚带尾空格（sitecustomize 打印形态 'gate=1 min_ctx=…'）——防 'gate=1x' 类前缀误配（锚定签名教义）。
SW_BANNER='[sparse_wire] sparse-table pair REFUSED -> DenseBlocksBackend'  # 白名单（20261002 诊断定谳：能力探针良性）
g_red=0
for h in 01 02 03 04; do
  f="$D/boot-acceptance/boot$h-b1.log"
  pos=$(grep -Fc '[prefill_split] gate=1 ' "$f" 2>/dev/null || true)
  neg0=$(grep -Fc '[prefill_split] gate=0' "$f" 2>/dev/null || true)
  negu=$(grep -Fc '[prefill_split] gate=(unset)' "$f" 2>/dev/null || true)
  init=$(grep -Fc 'DSV41 prefill TP split initialized' "$f" 2>/dev/null || true)
  drift=$(grep -Fc 'backend drifted' "$f" 2>/dev/null || true)
  refuse=$(grep -Fc 'refusing to boot' "$f" 2>/dev/null || true)
  log "G3@$h: gate1=$pos gate0=$neg0 unset=$negu init=$init drifted=$drift refuse=$refuse"
  { [ "${pos:-0}" -ge 1 ] && [ "${neg0:-1}" = 0 ] && [ "${negu:-1}" = 0 ] && [ "${init:-0}" -ge 1 ] && [ "${drift:-1}" = 0 ] && [ "${refuse:-1}" = 0 ]; } \
    || { g_red=1; log "G3 RED@$h：门报形态非武装（见上行计数）"; }
done
[ "$g_red" = 0 ] || bail 4 "G3 红：prefill_split 门报非 gate=1 武装态"
vput "G3 prefill_split-gate-banner: GREEN (4 机 gate=1+init, 零负签名)"

# ── G4：W21 雷反证（init 期零集合通信回退）──
# 反向判别自检：喂合成坏行 'NCCL INFO Init: fallback to socket comm' → 组合命中计 1 → 红——红因=雷签名在场；
# 白名单：[sparse_wire] 良性横幅（REFUSED→DenseBlocksBackend，语义保持回退说明，非集合通信回退）不含
# fallback×comm 组合词对，天然不命中——白名单注释写明其存在与豁免理由（cccf363 白名单先行教义）。
log "== G4：W21 雷反证（docker logs 无 init 期集合通信回退）=="
w21_red=0
for h in 01 02 03 04; do
  f="$D/boot-acceptance/boot$h-b1.log"
  hit=$(grep -i 'fallback' "$f" 2>/dev/null | grep -Ei 'init|comm|collective|nccl' | grep -Fvc "$SW_BANNER" || true)
  log "G4@$h: fallback×init/comm 组合=$hit（白名单 [sparse_wire] 良性横幅已豁免；期望 0）"
  [ "${hit:-1}" = 0 ] || { w21_red=1; grep -i 'fallback' "$f" 2>/dev/null | grep -Ei 'init|comm|collective|nccl' | head -5 | tee -a "$L"; }
done
[ "$w21_red" = 0 ] || bail 4 "G4 红：W21 雷签名（init 期集合通信回退）复现"
vput "G4 W21-flashback-disproof: GREEN (4 机零 fallback×init/comm)"

# ── G5：28 门横幅（按机计数）+ [arm] +env 注入行（30=29+1）──
# 反向判别自检（banner）：喂「sitecustomize 旧版 27 gates」形态 → 总数=1 而精确锚 '[ep1f] banner complete:
# 28 gates reported' 计 0 → 总数≠精确 → 红——红因=sentinel 数错（部分横幅形态，sitecustomize:601 头注教训）；
# 喂「死靴只打部分横幅」→ sentinel 行缺 → 精确计 0 → 红。两向皆红=判别力。
# 反向判别自检（env 行）：喂「误用 A22-C1REV 原 env」→ 29≠30 → 红；BRE 中 + 为字面量（A1 修正沿袭，
# 对象=chain.log 本靴段=宿主侧 r3-boot-arm.sh '[arm] +env' 输出，容器日志无此横幅）。
# ⚠18:08Z 第三次点火假红勘误（selfmatch 家族，门1 头注 nohup.selfmatch 同宗）：原计数 grep
# '\[arm\] +env' 无行首锚——本链 G5 自身 log 头注「== G5：28 门横幅 + [arm] +env=30 ==」含同
# 子串被计入 → 30 注入+1 自污染=31≠30 假红杀健康靴（实测注入恰 30 行、全键去重无重）。修正=
# ^\[arm\] 锚定（注入行列首裸 '[arm] '；本链 log() 行恒带 '[timestamp] ' 前缀——锚即自排除）。
log "== G5：28 门横幅 + env 注入 30（注意：本头注不写注入横幅原串，防 selfmatch）=="
g5_red=0
for h in 01 02 03 04; do
  f="$D/boot-acceptance/boot$h-b1.log"
  tot=$(grep -Fc 'banner complete:' "$f" 2>/dev/null || true)
  exact=$(grep -Fc '[ep1f] banner complete: 28 gates reported' "$f" 2>/dev/null || true)
  log "G5@$h: banner total=$tot exact28=$exact（期望 total=exact≥1）"
  { [ "${tot:-0}" -ge 1 ] && [ "$tot" = "$exact" ]; } || { g5_red=1; log "G5 RED@$h：sentinel 数错或部分横幅"; }
done
envn=$(sed -n "/== 靴（$BOOT_TS）：/,\$p" "$L" | grep -c '^\[arm\] +env')
log "G5 env 注入行数=$envn（期望 30=29+1；对象=chain.log 本靴段，^ 锚自排除 log 行）"
[ "$envn" = 30 ] || { g5_red=1; log "G5 RED：env 注入=$envn≠30（env 文件派生或注入漂移）"; }
[ "$g5_red" = 0 ] || bail 4 "G5 红：装配门横幅/env 注入形态错"
vput "G5 banner28+env30: GREEN (4 机 sentinel 28/28, env=$envn)"

# ── G6：A22 面继承（ROCE 武装 4/4+零 DOA；fc94c89 按机计数沿袭）──
# 反向判别自检：喂「roce_ar 未武装」形态 → gates=0/0、无 TP8_READY → ready=0/4 → 红；喂真 DOA
# '[roce_ar] REFUSED' → 计>0 → 红；裸串 'REFUSED' 会撞 [sparse_wire] 白名单（14:21 假警报杀健康靴）
# —— REFUSED 断言锚定 '[roce_ar] REFUSED' 真签名+白名单残差兜底（cccf363 形态）。
log "== G6：A22 面继承断言 =="
ready=0; refused=0; refo=0; sw=0
for h in 01 02 03 04; do
  f="$D/boot-acceptance/boot$h-b1.log"
  g6=$(grep -Fc 'ROCE_TP8_READY' "$f" 2>/dev/null || true)
  [ "${g6:-0}" -ge 1 ] && ready=$((ready+1))   # 每机≥1 条即武装（横幅×2/rank 陷阱：计武装机数非行数）
  refused=$((refused+$(grep -Fc '[roce_ar] REFUSED' "$f" 2>/dev/null || true)))
  refo=$((refo+$(grep -F 'REFUSED' "$f" 2>/dev/null | grep -Fvc "$SW_BANNER" || true)))
  sw=$((sw+$(grep -Fc "$SW_BANNER" "$f" 2>/dev/null || true)))
done
log "G6: ROCE_TP8_READY 武装机数=$ready/4（横幅行数另计）[roce_ar]REFUSED=$refused sparse_wire良性=$sw（期望 2/机×4=8，白名单留档）非白名单残差=$refo"
{ [ "$ready" = 4 ] && [ "$refused" = 0 ] && [ "$refo" = 0 ]; } || bail 5 "G6 红：A22 面继承破（ready=$ready/4 refused=$refused 残差=$refo）"
vput "G6 A22-face-inherited: GREEN (ready=4/4, REFUSED=0, residual=0)"

# ── 冒烟 20-token（流量面最小验活）──
log "G-冒烟 20-token："
curl -s --max-time 60 http://127.0.0.1:8898/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"deepseek-v4.1-flash","messages":[{"role":"user","content":"用一句通顺的中文介绍长城。"}],"max_tokens":40,"temperature":0}' | tee "$D/smoke.json" | tee -a "$L"; echo | tee -a "$L"
grep -q '"content"' "$D/smoke.json" 2>/dev/null || bail 6 "冒烟无 content——服务面异常"
water4 steady   # R41 第 2 点：steady（冒烟后）

# ════════ 门段完（G1-G6 全绿才走到这里）——以下顺载 R41/R42 基线，不跑 battery 六格 ════════
vput "T50-GATE: GREEN — 六门全绿 $(date -u +%FT%TZ)；R41/R42 基线顺载如下"
log "== T50 门全绿 → 顺载 R41/R42（门靴不烧白靴：基线落 $D/eval）=="

# ── R42-①：GSM8K 200（门≥0.95=G3 下沿；现锚 0.975-0.99）──
# 反向判别自检：喂「TP_SPLIT 打坏前向」形态 → accuracy_content<0.95 → 红——红因=质量塌（P0 级，
# 104 风险表「重锚版零靴验」的兜底）；数值经 python 解析 JSON，不 grep 文本（pr_ladder6 坑③）。
log "== R42 GSM8K 200（G3 门≥0.95）=="
timeout 1800 python3 ~/dsv41-flash-dgxsparks/bench/gsm8k_dsv41.py --base http://127.0.0.1:8898 --model deepseek-v4.1-flash --nq 200 --out-raw "$D/eval/gsm8k_raw.json" --out-summary "$D/eval/gsm8k_summary.json" >> "$L" 2>&1
log "gsm8k rc=$?"
acc=$(python3 -c "import json;print(json.load(open('$D/eval/gsm8k_summary.json'))['accuracy_content'])" 2>/dev/null)
log "GSM8K accuracy_content=$acc（A22-C1REV 锚 0.98）"
python3 -c "exit(0 if float('${acc:-0}')>=0.95 else 1)" 2>/dev/null || bail 6 "R42 红：GSM8K=$acc<0.95（G3 下沿破——TP_SPLIT 质量面红，禁进 T51）"
vput "R42 gsm8k: $acc (GREEN >=0.95)"

# ── R42-②：accept 窗读（3×256 预热，纯 decode 突发后读纪律；G3 窗 [3.0,3.5]）──
# 反向判别自检：喂「A2d 通道②塌陷形态」→ mean<3.0 → 红——红因=接受率塌（a22c1rev 红线 3.1 的 G3 下沿版）；
# >3.5 仅 WARN 留档（窗上沿越界不杀靴，交判定卡）。
log "== R42 accept（3×256 预热后读，带 [3.0,3.5]）=="
for i in 1 2 3; do python3 ~/dsv41-flash-dgxsparks/bench/sd_bench.py --base-url http://127.0.0.1:8898/v1 --key-file /dev/null --mode de --type prose --concurrency 1 --max-tokens 256 --runs 1 >/dev/null 2>&1; done
python3 tools/accept_window.py --base http://127.0.0.1:8898 > "$D/eval/accept.json" 2>&1; cat "$D/eval/accept.json" | tee -a "$L"
am=$(python3 -c "import json;print(json.load(open('$D/eval/accept.json'))['mean'])" 2>/dev/null)
python3 -c "exit(0 if float('${am:-0}')>=3.0 else 1)" 2>/dev/null || bail 6 "R42 红：accept=$am<3.0——通道②塌陷签名，中止后续（容器已 teardown 由 bail 执行）"
python3 -c "exit(0 if float('${am:-0}')<=3.5 else 1)" 2>/dev/null || log "WARN accept=$am>3.5（窗上沿越界，留档交判定卡不杀靴）"
log "accept=$am 在带"
vput "R42 accept: $am (GREEN >=3.0)"
water4 post-eval   # R41 第 3 点：battery 位（门靴无 battery，以 eval 三件套后代替打点）

# ── R42-③：needle 8k 快检（G1 面最小探针；8k≪48K dense 绕行红线）──
# 反向判别自检：喂「池挤压/长档塌」形态 → n_fail>0 或 SKIP → 记红——红因=检索面坏；
# 8k 属 dense 绕行态合法档（131072 才是 T×L 门 SKIP 态，A22 遗留登记同宗）。
log "== R42 needle 8k 快检 =="
timeout 600 python3 tools/needle_probe.py --base http://127.0.0.1:8898 --sizes 8192 --json-out "$D/eval/needle_8192.json" >> "$L" 2>&1
log "needle rc=$?"
np=$(python3 -c "import json;d=json.load(open('$D/eval/needle_8192.json'));print(d.get('n_pass'),d.get('n_fail'),d.get('n_skip'),d.get('gate_pass'))" 2>/dev/null)
log "needle8k pass/fail/skip/gate = $(echo $np | tr ' ' '/')"
python3 -c "import json,sys;d=json.load(open('$D/eval/needle_8192.json'));sys.exit(0 if d.get('gate_pass') else 1)" 2>/dev/null \
  || log "WARN needle8k gate_pass=false（$np——留档交判定卡；G1 全档阶梯归 T51）"
vput "R42 needle8k: $(echo $np | tr ' ' '/')"
water4 needle8k   # R41 第 4 点：needle 8k 后

# ── 收链：teardown（日志已全量落盘=fetch_logs 四次）+ 终态水线 ──
log "== teardown（G5：拆机前 docker logs 已存=boot/scene 两轮 fetch）=="
bash ~/migrate-assets/bin/r3-stop.sh >>"$L" 2>&1; log "stop rc=$?"
water4 post-teardown
vput "R41 water 4+1 点: $D/water/water.tsv（boot/steady/post-eval/needle8k/post-teardown）"
vput "T50-GATE: DONE $(date -u +%FT%TZ) —— 全部产物 $D/（门绿⇒T51 主臂可开：A23 全键+TPsplit+replay+512MiB）"
cat "$VERDICT" | tee -a "$L"
log "== T50 门靴链完（门绿+R41/R42 基线落档；四机 MemAvail 见 water.tsv）=="
