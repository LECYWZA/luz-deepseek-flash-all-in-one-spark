# FORM-REGISTRY-031 — LuZ-0.3.1 定型形档案（三形三元组+部署面指纹+键面清单）· 2026-10-12

> **法源**：CODE31-REVIEW-PLAN-20261012 §4.3（STATE/FORM-REGISTRY 先例同族）。
> **权威面声明**：本档=0.3.1 定型后键面/指纹的**新权威表**（TOOL-ANCHORS 产线
> 复原目标行将随 QA31 md5 重钉同日同步指向本档，CODE31-COMMENT-AUDIT CA-3）。
> **现役形 md5 注记**：50 键 env=15767aa6（=48 键 8c8c166d 逐字+FP8/TG 两键，
> `arms/COMBO-C0-spec1.env`）；**FL6-PROMO 转正窗 2026-10-13 闭 GREEN：现役定版
> =51 键 ENV51 `~/migrate-assets/dsv41/env/PROD-R51W5FL6-spec1.env`（2ac74586=
> 仓内 `deploy/env/PROD-R51W5-FL6FIX-spec1.env` 同 md5 异名；+sitecustomize
> 55b1e412+fl6_recall.py b87cbb5e 四机+cp30 锚位 99.95%/DE 82.17 实役直证），
> 50 键形降为一级回退，回退级次顺延**；**W5-PROMO 转正窗 2026-10-13 00:02:23Z 已将
> prefill_sp.py 32cf9abf 换入产线 adapter 面（本窗亲历时点）**——部署面集合
> md5（W5 面 20753511 族）转正窗收口后由 QA31 复核回填。

## 一、三形三元组表

| 形 | env 件（md5） | 键数 | SPEC 参谱 | 池门 | adapter 面 | overlay | 状态 |
|---|---|---|---|---|---|---|---|
| **50 键定型形（L0）** | `~/luz030-opt-campaign/arms/COMBO-C0-spec1.env`（**15767aa6**；仓内异名同值=`deploy/env/PROD-R51W5-spec1.env`） | 50 | **SPEC6 六参**=五参基座+`--swa-prefix-tails 256`（五参=`--prefill-decode-interval 16 --max-queued-requests 32 --min-free-slots-delay 1 --enable-decoder-swa-bounded-replay --reasoning-parser deepseek-v41`；KV-LIFE desk/lib.sh:11+E3A §六） | 9,600,000 | 4b40a123+**W5 件 32cf9abf** | o12c1-prod（29 活件） | **0.3.1 定型交付形**（裁定 fd5c7e5；QA31 案 A' 性能读数承接）；FL6 转正后=一级回退形 |
| 48 键形（L1） | `~/migrate-assets/dsv41/env/PROD-R1INK48L2PF6O12C1-spec1.env`（**8c8c166d**；仓内同值=`tools/packages/cfgmgmt/payload/env/` 同名件） | 48 | SPEC6 同上 | 9,600,000 | 4b40a123+0497e566 | o12c1-prod | 二级回退形（=50 键两键 unset；W5 件键关=0497e566 语义等价〔FP8_MOE 口径注记见 §四〕） |
| 47 键形（L2） | `~/migrate-assets/dsv41/env/PROD-R1STDLL128L2PF6O12C1-spec1.env`（**99e7ec92**；仓内同值=`tools/packages/cfgmgmt/payload/env/` 同名件） | 47 | SPEC6 同上（swa 256 在役） | 9,600,000 | 4b40a123+0497e566 | o12c1-prod | 三级回退形（R1 in-kernel 键 unset=构造性回退；FULLGATE G5 先例） |
| （45 键深回退 L3） | PROD-R1STDLL128L2PF6（34977bf0；仓内同值=`tools/packages/cfgmgmt/payload/env/` 同名件） | 45 | 五参（无 swa256） | 9,600,000 | 零 overlay | 零 | 四级深回退（零 overlay bump boot 一次；TOOL-ANCHORS 先例） |

## 二、部署面指纹

- **R1 八件面 4b40a123**（48 键形在役面，四机全等=FULLGATE/REWORK2/PROMO2 三窗
  直证）构成件（本窗 md5 亲核 2026-10-12）：
  `kv_fp4.py`=feaaadd4；`fi_r1/__init__.py`=0b6f13f1；`fi_r1/t_r1_equiv.py`=
  2fe0c0c3；`fi_r1/csrc/sparse_mla_sm120_prefill_fp4.cu`=6e1a5461；
  `fi_r1/csrc/sparse_mla_sm120_fp4_jit_binding.cu`=9bf19842；
  `fi_r1/include/.../fp4_extra_traits.cuh`=75d38608；
  `fi_r1/include/.../prefill_kernel_fp4.cuh`=b72d85ea；
  `sitecustomize.py`=79b8143e（R1 装载缝挂点）。
- **W5 面**：`prefill_sp.py`=**32cf9abf**（定型件，2026-10-13 00:02:23Z 入役）/
  0497e566（回退件=48 键形本尊，仓内真基线 `opt1-dev/prefill_sp_deepcarry_20261002/
  prefill_sp.py`）；W5+R1 合面集合指纹（QA31 卡「部署面 20753511」族）**转正窗
  收口后回填**。
- **overlay o12c1-prod**：29 件=23 镜像逐字节（上游 main-79cafec0 cmp 直证，
  CODE31-REVIEW-REPORT §C.1）+scheduler 5b6fe2a3（O12 件=三键调度间隙+PD-decode
  MM abort 守卫）+4 空 VL 占位+map a8bf0fd6；集合指纹 20fa6a1d（四机两遍核在
  档；算式未入仓档注记=审查 P2-8）。
- **boot 脚本链 md5**（本窗亲核）：`~/migrate-assets/bin/r3-boot-arm.sh`=
  c051bb41；`tools/boot-with-slotlock.sh`=fcaed824；`~/migrate-assets/bin/
  r3-stop.sh`=5ad87830。

## 三、50 键键面清单（键名→用途→值域→横幅面→呈裁档出处）

基座=48 键（8c8c166d，PROD-R1INK48L2PF6O12C1-spec1.env 逐字）+尾两键。横幅
面=sitecustomize `DSV41_SOURCE` 块门行（哨兵计数漂移注记=审查 P1-1；实核 29
门行）+各件安装期横幅。

| 键 | 值（定型形） | 用途/门控面 | 横幅/直证面 | 档出处 |
|---|---|---|---|---|
| DSV41_HC_FUSED | 1 | hc_fused 单 K 融合（mhc 挂点；首调对拍失配永久回退） | `[hc_fused]` | P1a-2 |
| DSV41_INDEXER_HOIST | 1 | indexer hoist 三挂点（model/scoring/metadata；首调 eager 对拍） | `[indexer_hoist]` | B-R6 |
| DSV41_PREFILL_EMPTY_CACHE_TOKENS | 8192 | prefill 空 cache 阈（model_runner 挂点） | 安装期 | FIX 族 |
| DSV41_IDLE_RELEASE | 1 | idle 窗 empty_cache（scheduler 挂点） | 安装期 | FIX-B |
| DSV41_ENGRAM_CACHE_GIB | 0.5 | engram 页缓存顶（engram_backend；COMMON 层另注入 PACKED_DIR/CACHE_GIB=1 族） | `[engram-prefetch]` | EP1/R3 |
| DSV41_WO_A_W8 / _MID / _DROP | 1/1/1 | wo_a fp8 孪生（model+dspark 双挂点） | `[wo_a_w8]` | EP1f |
| DSV41_REPLICATED_SPLIT | wqkv_a,engram.wkv | ReplicatedLinear 列分片（linear 挂点；位等或拒） | `[replicated_split]` | EP1f |
| SGLANG_FLASHINFER_MOE_FUSED_FINALIZE | 0 | 引擎 MoE finalize 关（配合 b12x next） | — | EP1 |
| DSV41_SPEC_SYNC_FREE | all | rank0 广播 drop/merge/audit 三挂点 | `[spec_sync_free]` | EP1h |
| DSV41_EAGER_GLUE | all | stage cache 两挂点（sampler/draft） | `[eager_glue]` | EP1h |
| DSV41_FOLDED_FENCE | 1 | verify 结果折叠栅栏 | `[folded_fence]` | EP1f |
| DSV41_SKIP_NONFINAL_DECODER | 1 | 非末 chunk 跳 late-layer 尾窗（model+backend） | 安装期 | C0b |
| DSV41_DRAFT_HEAD_FP8 / _IMPL | 1/tp4 | draft 头 fp8 tp4 行瓦（dspark 挂点） | `[draft_head_fp8(_tp4)]` | P1a-1 |
| DSV41_DRAFT_MAIN_PROJ_SPLIT | 1 | draft 主投影分裂 | `[draft_main_proj]` | P1a-1 |
| DSV41_VERIFY_CAP | conf:0.1 | verify 截断六挂点+conf 头（dspark） | `[verify_cap]` | EP1o |
| DSV41_SHARED_PAD_K | 1 | shared pad K（fp8_utils+fp8 双挂点） | 安装期 | EP1 |
| DSV41_ROUTER_LIVE | 1 | 死行路由折叠（verify_cap 族） | `[verify_cap]` 行内 | EP1o |
| DSV41_MOE_B12X_NEXT_DETERMINISTIC | 1 | b12x next 确定式（臂键 DSV41_MOE_B12X_NEXT=1 由 COMMON_ENV 注入层） | b12x 自横幅 | EP1/W4 |
| DSV41_ROCE_RING + SGLANG_ROCE_ALLREDUCE | 1/1 | RoCEnante TP all-reduce 双门（pynccl+parallel_state） | `[roce_ar]` | I14-A |
| SGLANG_ROCE_MAX_SIZE | 262144 | RoCE AR 尺寸顶 | `[roce_ar]` 行内 | I14 |
| DSV41_ROCE_GATHER | 524288 | 小 gather 单发核 | `[roce_ar]` 行内 | EP1j |
| B12X_ROCE_HCA | rocep1s0f0,… | 四口 HCA 表 | b12x | I14 |
| B12X_ROCE_PEER_HCA_MAPS | 1=1/3,… | 属主映射表 | b12x | I14 |
| B12X_ROCE_TWO_WAVE_THRESHOLD_BYTES | 0 | 双波阈值关 | b12x | I14 |
| TP_SIZE | 4 | TP 钉（tp3_pad 惰性+roce_ar 门） | `[roce_ar] tp=` 行 | A7-S1 |
| DSV41_PREFILL_SP | 1 | prefill SP 三挂点（deep-carry stage1 基座） | `[prefill_sp]`（含 agin/tail_gather 态行） | P-SP/T61 |
| SGLANG_MAX_NEW_TOKENS_LIMIT | 65536 | 输出上限 | — | 产线 |
| DSV41_SPARSE_LOCAL_CONSUME / _TIER | 1/triton | R1 gather consume 缝（v41_indexer 挂点） | `[sparse_local]` | R1 FIRE |
| DSV41_SPARSE_LOCAL_ADMISSION / _CTX_CAP / _MRR | 1/600000/16 | R1 形知 admission（tokenizer_manager 进程内 probe） | `[sparse_local]` | R1 FIRE |
| DSV41_CERT_HEAD / _M / _LOG_EVERY / _DEBUG | 1/6/200/1 | lm_cert 认证筛幕三挂点（tri-state 门） | `[lm_cert]` | F6 件3 |
| NCCL_BUFFSIZE / NCCL_LL128_BUFFSIZE / NCCL_PROTO | 1048576/262144/^LL128 | LL128 三键（docker -e last-wins 注入序律） | ll128-gate 服务门 | LL128-ADOPT |
| DSV41_L2_PREFETCH / _MB | 1/6 | L2 预取五挂点 | `[l2_prefetch]` | EP1g/W-OPTA |
| SGLANG_DSV4_O12_SCHED_ASYNC / _RECV_INTERVAL | 1/4 | O12 调度间隙（overlay scheduler 键；DP/PP/disagg 拓扑拒起门） | `[O12] host-gap` | O12/C1-PROMO |
| DSV41_FP4KV_R1_INKERNEL | 1 | R1 in-kernel fp4 prefill（严格布尔；PORT 键=COMMON_ENV 注入层；fail-safe 双跑） | `[kv_fp4] r1_inkernel=`+fail-safe 三态 | R1/L10 |
| **DSV41_PREFILL_SP_FP8** | **1**（50 键增） | W5 AG-in MXFP8 字节 AG（严格布尔；资格层门 17/21+每 size 三重对拍+永久 bf16 回退） | `[prefill_sp]` agin_fp8 行+`MXFP8 byte AG ON`/`AG-in fp8 layer gate: 17/21` | W5/COMBO |
| **DSV41_PREFILL_SP_TAIL_GATHER** | **1**（50 键增） | W5 出口尾行直聚（严格布尔；整除门拒绝回退全行 AG+退化门） | `[prefill_sp]` tail_gather 行 | W5/COMBO |

**unset 即回退族**（键关=构造性 no-op）：FP8/TG/R1_INKERNEL；**禁设键**：
DSV41_SPARK_PREFILL_TP_SPLIT（split 留库不转正）、FP8_MOE（W5 弃用钉死——
32cf9abf 下恒 bf16+DEPRECATED 横幅，与 0497e566 行为口径差=审查 P2-7 注记）。

## 四、口径注记（诚实面）

1. **48↔50 键等价口径**：两新键 unset 时 32cf9abf 与 0497e566 语义等价的精确
   条件=FP8_MOE 键亦不在键面（生产 48/50 键面均不含 ⇒ 实际成立）。
2. 集合指纹 20fa6a1d 与 W5 面 20753511 的算式未入仓档——本档以逐件 md5 表为
   权威对表面（建议 0.3.2 把算式一句话入 TOOL-ANCHORS）。
3. hook 面计数口径（卡 §六.1 呈裁）：本档采用审查报告 §D.3「29 活性 hook 面」
   口径（24 env 键武装+3 COMMON_ENV+1 缺省开+1 常开对）；骨架「26」数为旧计。

——CODE31 T3 文档窗 / 2026-10-12（md5 亲核时点=窗内；转正窗换件时点 00:02:23Z
如实注记）。
