#!/usr/bin/env bash
# r1_stdform_chain.sh —— 标准形态认证火链【骨架 SKELETON；未授权不得执行】
#
# 形态 = RS 基线（6dae6ba6 已批切产形；若届时 v2 认证后件已切产则以现役为基，
#         本链门 0c 的 md5 基准届时刷新）+ R1 键（gather 消费面 + 形式感知准入）
#         + ctx 600k / MRR 16 / --max-total-tokens 9.6M + SPEC=1 生产 decode 形态。
# 令源 = docs/research/STDFORM-600K-9M-FEASIBILITY-20261003.md §七（74ee070）：
#         「标准形态达成前置=R1 上岗+一次 SPEC=1 16×~596k 满驻冒烟（带 memguard
#         9G 主动 abort+三态水位记录）；认证火=RS+R1+600k/16/9.6M 同窗」。
# R1 件 = opt1-dev/sparse_local_scoring_20261002/（六件+第二段补齐；FIRE-READINESS.md）。
# R1-FIX 修订（2026-10-04，R1STDFORM-NOGO-ADJUDICATION-20261003 §二立令）：seam 消费面
#         capture-safe 化（decode 图捕获路径去 nonzero=四机同靴同错根因；选路 (c) 列追踪
#         gather，等价性论证=R1-FIX-CAPTURESAFE-20261004.md）+dev 矩阵补相（容器 p12
#         「decode graph capture × seam 共存」+host 4f AST 门+变异 M17）+X-2 世系统一
#         （admission_r1=7769a33e）。seam_mount/reference_impl md5 已变——门 0c 基准
#         本轮刷新至 MD5.txt 的 R1-FIX 段；臂 env 零键变化（A25 不动）。
#
# ── 骨架纪律 ────────────────────────────────────────────────────────────────
# 本脚本缺省=--plan（只打印门序与断言清单，零集群动作）。真执行需同时满足：
#   ① --authorize（用户/主会话火令）② .slot-lock 空闲（K1/v2 等在飞线不冲突）
#   ③ R1 部署审批线已走（seam 三件+sitecustomize 分支入 adapter；本链不部署，
#      只断言 md5 三面四机全等=门 0c）。TL_BUDGET 不得设置（X1 反向红例在矩阵）。
# 红线：8898 only（8899=生产口绝不发流量）；集群串行；needle ≤128k（600k 面=
#   C16 式驱动器）；不 drop_caches；水线/oom-gate 地板 1.5G 禁区不动；prefill_sp.py
#   现役（065d158b 或届时 v2 认证件）全程零改动零 .bak；不写判定卡。
# tripwire 律（预登记）：GSM8K n500 < Ā−0.5pp（=0.9660 地板）或 accept 出
#   [2.90,3.30] 或 census ENGAGED 三同时不成立或水位破 9G 中止线=保现场+
#   teardown+回滚（R1 三件撤除+sitecustomize 还原）+零重试；DE/PR 带外读数照实留档。
set -uo pipefail

MODE=plan
[ "${1:-}" = "--authorize" ] && MODE=run
cd ~/luz030-opt-campaign

D=logs/A25-R1-STDFORM
ADP=~/migrate-assets/dsv41/adapter
R1DEV=~/luz030-opt-campaign/opt1-dev/sparse_local_scoring_20261002
ARM=arms/A25-R1-STDFORM-spec1.env
L=$D/chain.log

# ── 门序（十门；每门断言+失败处置）──────────────────────────────────────────
cat <<'GATES'
门0  前置：.slot-lock 空闲自持 + K1/v2 在飞线零冲突 + R1 部署审批线回执在档
      （R1-FIX 后重走：seam_mount/reference_impl 新 md5 入 adapter；admission/
      triton_kernel/selection_dump 三件 md5 未变 7769a33e/24d96f9d/35905ebe）
门0b 离线复验：host unit_xcheck（117 断言；含 4f decode 捕获面 AST 门）+ 容器冒烟
      （--network none --gpus all，十二相位；含 p12 decode graph capture × seam 共存
      =capture 零异常+replay 两情景对金标准+拔件红例）+ 变异 17/17 全杀（含 M17
      捕获面回归杀手）——本仓 dev 树态即火就绪态的再证
门0c 部署门（三面 md5 四机全等）：adapter/{sparse_local_scoring 三件按部署单合并
      后的文件名} + sitecustomize 分支 + 本链引用的 md5 基准（MD5.txt 的 R1-FIX
      2026-10-04 段——旧认证火段基准随 NO-GO 作废）；
      ⚠ 合并 v2 项若在途：R1 的 prefill_sp 相邻文件面零接触，md5 各管各
门1  boot 门：r3-boot-arm.sh + $ARM；SERVER_ARGS 断言 --context-length 600000
      --max-running-requests 16 --max-total-tokens 9600000 --cuda-graph-max-bs-decode 16
      --chunked-prefill-size 4096 + SPEC=1（DSPARK draft 6）；四机 banner complete
门2  形态门（R1 ENGAGED 三同时）：①四机 boot log 含
      '[sparse_local_consume] gather consumer ENGAGED' ②含
      '[sparse_local_admission] form-aware admission ARMED' ③census 判别（门6）
      _fp4_gather_index_logits_kernel calls_per_step∈[3.8,4.2] 且
      _fp4_index_logits_kernel 降至 [0.8,1.2]——REFUSED 横幅=火中止（fail-closed）
门3  RS 横幅门：四机 rowband/prefill_sp 形态横幅（RS 形；ar_slice 弃用形绝不得现）
门4  准入门四相位实弹：④a 600,000 tok 探针请求过门（HTTP 200 非裸 curl——C16
      驱动器面）④b 4k 短 ctx 过门不受扰 ④c 键面 A/B：DSV41_SPARSE_LOCAL_CONSUME=0
      复跑 600k 探针必 400（门坍缩 dense 的活体证；A/B 后键复位+横幅复核）
      ④d DSV41_TL_BUDGET_ELEMS 未设（printenv 断言 unset——X1 反向红例活体）
门5  SPEC=1 满驻冒烟：c16_600k_driver.py 改制臂（SPEC=1 + 16×~596k+2k 齐射 +
      1s 水位三态 before/lowest/after + memguard_r1.py 9G 主动 abort 常备 +
      TTFT 阶梯单调 + verify 临时槽 retraction 观测（黄项验证=本火核心读数）
门6  census 三族（r12 采集）：ENGAGED 判别（门2③）+ RoceOneshot/RoceAG/RING_LL
      带内 + 索引桶 ms/step 降幅记录（不设门槛，只记录）
门7  DE 六格：prose c1/c8/c12/c16 + code c1/c8 对 A22B 锚（78.83/20.95/17.62/
      14.73/123.70/+c8code）±2% 带内；accept 窗 [2.90,3.30]
门8  PR 四档 + 64k/128k 首读：4k/8k/16k/32k 对 RS 锚（3714.6/4340.9/4727.8/
      4855.1）−5% 带内；64k/128k 档=史上首读（M1=64k≥4500 / M2=128k≥5500
      里程碑判读，首读不 trip 只留档）
门9  质量门：GSM8K n500 同功率（t62c 驱动器逐字复用）地板 0.9660（Ā=0.9710−
      0.5pp）；trip=保现场+teardown+回滚+零重试
GATES

if [ "$MODE" != run ]; then
  echo "[SKELETON] --plan 模式：门序与断言如上；真执行需 --authorize + 部署审批线回执 + slot 空闲。零集群动作。"
  exit 0
fi

# ══ 以下为执行体（授权后才到达；骨架期占位——执行代理届时按门序落具体命令）══
mkdir -p "$D"/{boot-acceptance,battery,pr,census,verify,admission-ab}
printf 'pid=%s\nARM_TAG=A25-R1-STDFORM\nphase=chain-running\nstart=%s\n' \
  "$$" "$(date -u +%FT%TZ)" > .slot-lock
log(){ echo "[$(date -u +%FT%TZ)] $*" | tee -a "$L"; }
water(){ for h in 01 02 03 04; do ssh -o ConnectTimeout=8 dgxspark$h \
  "LC_ALL=C free -m | awk '/Mem:/ {print \$7}'" 2>/dev/null | tr '\n' ' '; done; }

log "== 门0c 部署门：md5 三面四机全等（基准见 $R1DEV/MD5.txt 认证火段）=="
# md5r(){ ... } # 沿 k1_overlap_chain.sh 门 0c 形态；四机断言后进门 1
log "（骨架：执行代理落具体命令——本文件授权前不执行任何集群动作）"
log "== 骨架止于此：AUTHORIZE 前置未满（部署审批线回执），按纪律退出 =="
exit 9
