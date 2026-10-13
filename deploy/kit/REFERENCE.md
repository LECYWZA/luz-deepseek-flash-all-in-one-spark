# REFERENCE.md — 上游引用总登记（单一登记处）

> **生成日期**：2026-09-23（`luz0.2.8pre` 冻结日）
> **性质**：本项目**唯一**的"上游编号 → 仓库归属"登记表。此前这些编号散落在 `V41-*.md` 报告、
> `w6-kit/guard/` 的脚本头注与 `guards.conf` 注释里，**没有任何一处集中登记**。
> **烘焙落点**：`/opt/dsv41/kit/REFERENCE.md`（与本目录下的 `GLOSSARY.md` 一并入镜像）。
>
> ## 口径与纪律（读表前必读）
> 1. **只用编号 + 本地上下文 + 允许的外网核对动作（WebFetch/WebSearch）**。**不编 URL、不编 PR 标题。**
> 2. 每条都带**状态**与**出处**：
>    - `已核实(web)` = 本次用 WebFetch 打到该编号的页面，标题/状态/日期来自页面本身。
>    - `上下文推断：<file:line>` = 只能从代码/文档上下文判定仓库与含义，**未**打网络。
>    - `归属未核实` = 本地上下文不足以确定仓库或含义，**如实标注**。
> 3. `状态` 列只写四类：**已合入 / 未合入 / 已否决 / 背景**（背景 = 只作参照，未进入判决链）。
> 4. 行号只用于**冻结件 / 带日期的历史报告**（并注明"（该文件为冻结件，行号稳定）"）；指向**仍在被编辑**
>    的文件一律用**节名 / 行名 / 引文**锚定。（2026-09-23 修复轮修订：原文写"行号一律为 2026-09-23 实测的行号"
>    —— **那正是引用漂移的病根**：6 个目标文件当天都被改过，登记的行号随即集体失准，本轮全部改锚点。）

---

## 0. 采集范围与总量

| 项 | 值 |
|---|---|
| 采集目录 | `/home/liux***ya/w6-kit/`、`/home/liux***ya/dsv41-flash-dgxsparks/`（含 `docs/`、`scripts/`、`image-patches/`、`sglang-overlay*/`）、`/home/liux***ya/*.md` |
| 采集命令 | 见 §11 的**复算脚本**（同一脚本同时给出本节的"引用点 / 编号数"与 §11 的"缺口数"）。原文只写了一句 `grep -rnoE '(PR ?#\|#)[0-9]{4,6}' --include=*.{sh,py,md,conf} <DIR>` —— **复算不了 §11 的"±2 行"判据**，2026-09-23 换成可运行脚本 |
| 去重后编号数 | **305 个**（2026-09-23 复算脚本实测；不含 vendored 树、不含 `g1r*` 构建/实验树） |
| 引用点（文件:行）总数 | **1766 个**（同上实测；⚠ **把本册与 `GLOSSARY.md` 自身也算在内** ⇒ 两册每增删一个编号字样此数即变，复算一律以本册**第 11 节的脚本**为准，本值只代表 2026-09-23 落笔时点） |
| 本次 web 逐条核实 | **28 条**（§12 表列全；复算 = 表内行数，命令见 §12） |
| 无法归属 | **见 §13** |

> ⚠ **本表不收录 vendored 上游源码树内的编号**：`w6-kit/fi-main/`、`fi-main2/`、`fi-src/`、
> `fi016-src/`、`fi18-wheels/`、`fi-wheels/`、`cutlass*/`、`b12x-site/`、`patches028/`、
> `w6-kit/reference/` 下的第三方配方树，以及 `w6-kit/s0-dspark-*/`（fork 全量快照）。
> 理由：那些 `#NNNN` 是**上游自己源码里的注释**（如 `flashinfer/flashinfer/jit/*.py` 里的
> `PR #3145`），不是我方引用，登记它们会把登记处淹没。例：`w6-kit/fi-main/flashinfer/moe_ep/.../handle.py:PR #3453`
> 是 flashinfer 上游自带的引用，非我方。

---

## 1. NVIDIA `open-gpu-kernel-modules`

| 编号 | 一句话 | 状态 | 对我方的影响 | 出处 |
|---|---|---|---|---|
| **#1358** | **我方楔死根因的上游 issue**：GB10(DGX Spark) 在统一内存压力下 `_memdescAllocInternal @ mem_desc.c:1359` 报 `NV_ERR_NO_MEMORY (0x51)`，随后**整机静默楔死**（无 OOM kill、无 panic、pstore 空，需断电）。驱动 595.84 与 580.173.02 均复现，aarch64、内核 `6.17.0-1032-nvidia`。 | **未合入**（open，本次实测仍在动） | **最高优先**。本地 A/B 已证 flavor 可换（open 专有模块 3/3 打死 vs 全跑完）；上游 5 条评论 `author_association` **全 NONE**、**无任何"已修复版本"**、watchdog 从未触发（与我们"无 panic/pstore、VRAM 常还空着"一致）。评论②给出并列第二轴=**内核版本**（`7.0.0-1019` 挂 / `6.17.0-1032` 正常）；评论①：`uvm_global_oversubscription=0` 把硬楔死降级为可恢复的 global OOM sweep。 | `~/V41-DRIVER-FLAVOR-WINDOW-20260922.md:3`、`~/V41-UPSTREAM-TRACK-20260922.md:58`、`~/V41-DRIVER-VERIFY-VERDICT-20260922.md:68`、`~/V41-CTX600K-READINESS-20260922.md:111` ｜ web: `https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1358` → **已核实(web)**：标题与状态与本地记载逐点吻合 |

---

## 2. SGLang（`sgl-project/sglang`）

> ⚠ **口径警告（本地已有明文）**：上游 sglang 已到 **v0.5.20**、PR 编号四万级；我方 fork 自称
> "0.2.7 基线"，**编号体系对不上**。一切可用性必须按**文件/函数内容回指**，不得按版本号硬套
> （`~/V41-UPSTREAM-TRACK-20260922.md:12`）。

### 2.1 高价值条目（判决链完整登记）

| 编号 | 一句话 | 状态 | 对我方的影响 | 出处 |
|---|---|---|---|---|
| **#40352** | 候选块稀疏打分：prefill consumer indexer 由**全 `[tokens, context]` 稠密打分**改为**只对 ~2048 个已发布候选块**打分（表 `[tokens, 2048×8]` bf16 ⇒ 每 chunk ≈0.5 GB，≈70×↓；256K TTFT −22%）。落点 `candidate_indexer*.py` / `deepseek_v4_backend.py`。 | **已合入**（建 09-19 / **合 09-22，仅 main，不进 v0.5.20**）｜**已核实(web)** | ★**与我方 `mask_b` 同量级、同形状、同位置**：上游被干掉的是「262K 时每 layer `[tokens, context]` fp32 ≈17 GB + 4.3 GB bool mask」，我方 `mask_b` 实测 `[t_len, lc]` bool ≈**4.85 GiB/次**。⇒ A 条（非末 chunk 行界）是**把它关小**（止血）；#40352 是**不再物化它**（根治）。**移植前置**：须先做文件/函数级回指，不能按版本号判断可移植性。附注：新路径改从**私有 `torch.cuda.MemPool`** 分配，文中写明"私有 pool 在内存压力下**不会**被释放"（警告项）。 | `~/V41-UPSTREAM-TRACK-20260922.md:20-33`、`:119`、`~/V41-DRIVER-VERIFY-VERDICT-20260922.md:186` ｜ web: `https://github.com/sgl-project/sglang/pull/40352`（标题 "[DSv4.1] Score prefill consumer index layers on candidate blocks with DeepGEMM"） |
| **#40444** | per-rank idle 回收：`SGLANG_EMPTY_CACHE_INTERVAL`（默认 −1 关）**只在 rank0 触发**（`IdleSleeper` 被 `pp_rank==0 and attn_tp_rank==0 and attn_cp_rank==0` 门控），而分配器是**每进程**的 ⇒ 其余 rank 缓存块永不归还。修法=把回收移进 `Scheduler.on_idle()`。 | **未合入**（open 09-20，等 code owner，CI 挂在 label gate）｜**已核实(web)** | ★**我方已交叉核对：无此盲点**。`_maybe_idle_release()` 由 `on_idle()` 直接调用（`dsv41-flash-dgxsparks/sglang-overlay.ctx600k-probe/scheduler.py:4755`），`on_idle` 由 `event_loop_normal/overlap` 在**每个 TP rank 进程**执行（`run_event_loop` 无 rank 门控）；rank0 门只卡住其下游的 `maybe_sleep_on_idle`。⇒ **FIX-B 是逐 rank 各自开火**。 | `~/V41-UPSTREAM-TRACK-20260922.md:49` ｜ web: `https://github.com/sgl-project/sglang/pull/40444`（"Reclaim the idle device cache on every rank"） |
| **#39482** | SM121 进 DeepGEMM packed-scale 选择：DGX Spark(SM121) 上 configurer 启用了 runner 但 **UE8M0 scale 标志没开**（arch 只匹配 SM120），导致走 FP32 scale ⇒ 撞 DeepGEMM 的 power-of-two scale 断言。修法=`sm_version in (120, 121)`。 | **已合入**（09-18 merged by BBuf）｜**已核实(web)** | **判决链（必须写全，本项目最曲折的一条）**：<br>① **9/14 QW2 判 NOGO**：SM121 纳入 DeepGEMM 启用+UE8M0 ⇒ **全路径慢 ~100×**（accept c12 agg 26 t/s、prefill 11K 1421、bench c1=2.3），输出仍对（GSM8K 20/20）⇒ 立即回滚。<br>② **9/20 重新 triage**：改判为"**立即带入 0.2.7**"（上游 09-18 已合）。<br>③ **0.2.7 采用**：`image-patches/0.2.7/configurer.py` = upstream verbatim。<br>④ **9/21 疑为 prefill 2.25× 回退元凶**：0.2.7 批 PRv3 全档均匀回落（8192-c1 4992→2210-2821），A/B 臂=`sglang-overlay/configurer.py:42` 回到 0.2.4 行为（UE8M0 仅 SM100，121 不进）。<br>⑤ **9/22 破案**：真因 = **dgxspark02 PD 安全模式时钟楔死**（721 MHz@96%util/15W；拔墙 AC 冷断电修复）。排除链实证：镜像/UE8M0/#40024 路径/fabric/autotune 表/ctx/口径**全部排除**；修复后 8192-c1 = 4619-4875。<br>⇒ **A/B 回退臂条件未成立**（回退臂与对照臂同慢）⇒ **0.2.8pre 保留原版（不回退 #39482）**。 | 判决链出处：`r4-ops-20260914/evidence/quickwins-20260915/QUICKWINS-VERDICT.md:17-27`（QW2 NOGO）、`~/V41-UPSTREAM-TRIAGE-20260920.md:56`（立即带入）、`dsv41-flash-dgxsparks/image-patches/0.2.7/README.md:4`（采用）、`dsv41-flash-dgxsparks/sglang-overlay/configurer.py:42-45`（A/B 臂）、`~/V41-027-INCIDENT-AND-WINDOW-REPORT-20260921.md:11-38`（破案）；另 `V41-SGLANG-OPS-ROUND2-20260914.md:248`、`dsv41-flash-dgxsparks/start.sh` 的 `SGLANG_OVERLAY_MAP` 里 `configurer.py` 条目（注释 `#39482 UE8M0(121 in tuple)`） ｜ web 标题 "[Bugfix] Include SM121 in DeepGEMM packed-scale selection" |
| **#40024** | shortest-prefill-first 调度：等待队列按**剩余未命中 prefill** 排序，短请求预留**续算预算**，禁第二个未完成 chunk；API 用 "per-pass continuation limit" 保形。 | **已合入**（09-18 merged，5 commits）｜**已核实(web)** | **已在 0.2.7 镜像内**（`image-patches/0.2.7/schedule_policy.py` = upstream 适配版，**default OFF**，与 `DSV41_PREFILL_SHARE_TOKENS` 共存）。上游正式版 = 我方私有 share 旋钮的"正式上游版"；**正对我方 ≥32K 逐请求独占断崖**。 | `dsv41-flash-dgxsparks/image-patches/0.2.7/README.md:5`、`.../schedule_policy.py:209,576,1264`、`.../scheduler.py:3713`、`dsv41-flash-dgxsparks/start.sh` 的 `image_arg_preflight()` 上方注释块（`只有 0.2.7+ 认（#40024 正式版合入）`）、`~/V41-UPSTREAM-TRIAGE-20260920.md:9,34` ｜ web 标题 "[Scheduler] Add shortest-prefill-first scheduling"（**注意：本次核实页面里 `chunked_req_limit` 字面未出现**，我方记载用了这个名字，属本地命名） |
| **#40217** | `[DeepSeek-V4.1] Bound dense prefill indexer memory`：dense prefill indexer 的 FP32 scores 与 bool 候选掩码共存，`6*T*N bytes` @16K chunk + 1M ctx ≈ **96 GiB/GPU**。改动=scores/top-k 按**行块 + 2 GiB 预算**；**候选块 ID 存层间**而非全量 bool 掩码，掩码只按当前 tile 造（int32 块 ID 把 1M ctx 的掩码从 **16 GiB → 128 MiB**）。B200 实测峰值 **96.01 → 2.72 GiB**。 | **已合入**（09-20 merged by main，6 commits）｜**已核实(web)** | ★**我方镜像内有 native port**（最小形态，2026-09-20）：`sglang-overlay.ctx600k/deepseek_v4_backend.py`（及 `-probe` 树）的 `# DSV41 #40217 native port (minimal form, 2026-09-20)` 注释行起，把 mixed 批的"全行回退"改为"子集尾 publish"，把无界项从 `[chunk≤8192, lc]`（245K 前缀 ≈2.0 GiB、600K 角落 4.9 GiB）压到 `[tail≤128, lc]`。<br>另：**第三方 0.2.4 同格挂死 vs 我方 0.2.6 同格 16/16 ok = 外部实锤**，掩码 bound 的另两案（非末批空发布 / 块粒度 publish+consume shim）**判定=未落**（需消费方不变量证明，不盲上）。<br>⚠ 本地文档曾把它记作"**外部报告**（未注仓库）"——**本次核实纠正为 sglang 上游 PR**。 | 代码：`sglang-overlay.ctx600k/deepseek_v4_backend.py`（及 `-probe` 树）的 `# DSV41 #40217 native port (minimal form, 2026-09-20)` 注释行；台账：`w6-kit/guard/BASELINE.md` 的「2026-09-19（深夜终窗）：v11 上线 + chunk 8192 落地 + 调度限份开关」节 → `掩码 bound（#40217 思想）` 行（判定=**未落**）、`w6-kit/guard/README.md` §16「引用与出处」的 `#40217` 行、`~/V41-EXTERNAL-AUDIT-40217-VERDICT-20260919.md`（§三 测绘+规格，实测存在 6914 B）；实证：`~/V41-OPTIMIZATION-MASTER-PLAN-V4-20260920.md:14`（0.2.6 已修，131072×C16 两靴 16/16） ｜ web 标题 "[DeepSeek-V4.1] Bound dense prefill indexer memory (#40217)" |
| **#39187** | `[DeepSeek-V4.1] Bound the dense prefill indexer transient: row-chunk logits, tail-only candidate masks`：`_low_ratio_index_topk_dense` 三改（行块 + `_DENSE_INDEXER_LOGITS_BUDGET_BYTES` 2 GiB 预算；候选掩码写进**一块预分配** tensor 而非 concat 拷贝；SWA bounded replay 下只发布**各请求尾行**）。自报 300K 瞬态 49.7 → 10.7 GB、600K 从 OOM → ~9.6 GB。 | **已否决**（**closed 未合**，19 commits，CI 全红）｜**已核实(web)** | ★**本地代码把它标成 "Port of upstream PR #39187"**（`deepseek_v4_backend.py:3375`），但它 **closed 未合**；**真正合入的是 #40217**（同一改动的后继）。⇒ 登记口径应为"**我方移植的实为 #40217；代码注释里的 #39187 是它的前身（未合）**"。后续 rebase 上游 main 时应按 #40217 对齐。 | 代码：`deepseek_v4_backend.py` 的 `# Port of upstream PR #39187 onto this tree's candidate_masks convention` 注释行（ctx600k / -probe / ctx600k-oldpool 三树同锚点；行号随编辑漂移，一律用锚点）；台账：`~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:29,136`、`~/V41-SGLANG-OPS-ROUND2-20260914.md:77,123` ｜ web: pull/39187 与 pull/40217 两页均实拉 |
| **#39123** | `[DSV4.1] Paged KV cache layouts for FlashMLA's V4.1 fp8 / fp4 formats`：新增 V41（**528 B/token**，fp8 + ue8m0 scale/32）与 V41_FP4（**288 B/token**，e2m1 + e4m3 scale/16，"extra-cache only"）；584 B 的 V4 布局仍是默认，除非 `SGLANG_DSV4_KV_LAYOUT=v41`。 | **已合入**（合进 **`dsv4.1` 分支**，09-13）｜**已核实(web)** | 我方 **FP4 主 KV** 的来源：`image-patches`/overlay 的 `repack_fp4_to_v4.py`（PR#39123 fork + H1-H5 加固，FP4 主 KV→584B V4 形态桥），bytes/token **1670.75 → 912.25**（池 ≈×1.9），在役 `fork-v4-fp4`。把 M0/M1 从"自研 12-18 人日"降到"cherry-pick + 适配 ~6-10 人日"。 | `dsv41-flash-dgxsparks/start.sh` 的 `SGLANG_OVERLAY_MAP` 里 `#39123 fork-v4-fp4 pool + repack bridge` 段注（FP4 main KV 段首）、`~/V41-FP4-MAIN-KV-PROJECT-20260915.md:18,22`、`~/V41-OPERATOR-INVENTORY-AND-ROLLBACK-LEDGER-20260919.md:30`、`w6-kit/guard/guards.conf` 的 `sglang-kv-layout` 行（`SGLANG_DSV4_KV_LAYOUT=fork-v4-fp4` pin） ｜ web 标题 "…Paged KV cache layouts for FlashMLA's V4.1 fp8 / fp4 formats - #39123" |
| **#39257** | `fix: derive compact ragged CUDA graph slots from request width`：`_ragged_capture_slots` 用了 `min(num_tokens, max_bs)`，在非最大 CUDA graph tier 下算出**错误请求几何**；改为按各 tier 的 captured request width 推导并断言整除。 | **未合入**（open，5 个 code owner 待审）｜**已核实(web)** | **已知（我方 U1 门）**。我方 `RAGGED_VERIFY_MODE=static` 形态规避 ✓；**切 compact 前必修**。QW1 实测：compact 激活成功但**首跑即崩**（engram target-verify 假设"每请求恰好 draft_token_num 行"），判 **NOGO-for-now**，回 static。解锁收益 = SPS 表 **+10.5%**。 | `w6-kit/guard/BASELINE.md`（⚠ 2026-09-23 复核：该册 **全无 `0.2.6`／`#39257` 注记**（`grep -n '0\.2\.6\|#39257' ~/w6-kit/guard/BASELINE.md` 零命中）——原登记的"`:14`（0.2.6 已修注记）"**查无对应物**，按"不许编造"**删掉该行号指针**，本条状态以本行「状态」列为准）、`~/V41-OPS-ROUND1-SELECTION-20260914.md:21,35`、`~/V41-OPERATOR-INVENTORY-AND-ROLLBACK-LEDGER-20260919.md:65,124`、`r4-ops-20260914/evidence/quickwins-20260915/QUICKWINS-VERDICT.md:3-15` ｜ web 标题一致，状态 open |
| **#34554** | `[Scheduler] Add --long-prefill-token-threshold to bound one request's share of the prefill batch`：opt-in flag（默认 0=关）限制**单请求可吃的 prefill chunk 预算**，治"长 prompt 吃满 chunk 预算把后队饿死"的 multi-tenancy 公平性问题。 | **已否决**（**closed**，3 commits，CI 失败）｜**已核实(web)** | ★**本地把它记作"外部报告（未注仓库）"，本次核实= sglang 上游 PR**（且已 closed）。我方落地形态 = `schedule_policy.py` 的 **prefill 限份补丁**（`DSV41_PREFILL_SHARE_TOKENS`，v11，overlay 42 条，默认 0=关）；外部站点实测它**必须改源码**（`--long-prefill-token-threshold` 在其版本不存在）。**注意上游被否，我方的私有实现是独立走通的路径。** | `w6-kit/guard/BASELINE.md` 的「2026-09-19（深夜终窗）：v11 上线 + chunk 8192 落地 + 调度限份开关」节 → `v11` 行（原文 `L1186 思想，外部报告/#34554 借鉴`）、`w6-kit/guard/README.md` §16「引用与出处」的 `#34554` 行（登记为"仓库未注+编号，未附链接"）、`dsv41-flash-dgxsparks/start.sh` 的 `SGLANG_OVERLAY_MAP` 里 `schedule_policy.py` 条目（注释 `scheduler prefill share cap (L1186 idea, #34554)`）、`dsv41-flash-dgxsparks/image-patches/0.2.7/schedule_policy.py:1270`、`~/V41-EXTERNAL-AUDIT-40217-VERDICT-20260919.md:13` ｜ web 标题一致，状态 closed |
| **#39095** | `[DSV4] Chunk the indexer MQA logits by query rows under a free-memory budget`：C4 indexer 每层建一张 fp32 logits（query rows × compressed context）⇒ 长上下文确定性 OOM；修法=按 query rows 分块 + `SGLANG_DSA_MQA_LOGITS_FREE_MEM_FRACTION` 预算（`dsv4/metadata.py` 算 `rows_per_chunk`，一次 `mem_get_info`）。 | **已合入**（09-19 merged，11 commits）｜**已核实(web)** | **我方 FIX-D 的对位上游件**：我方 = 行 × 固定 128 MiB + **宽度 16384 网格坍缩**（尺寸精确恒定，vs 上游用地板抖动的自适应预算）。**回移判定=不手工回移**（下次 rebase 上游 main 自然带入；届时保上游删我方块、宽度网格思想带上）。⚠ 上游 `mem_get_info` 在 UMA 上跟 **MemFree 而非 MemAvailable** ⇒ 在 GB10 系统性低估（vLLM #35356 要修的坑）。 | 代码：`dsv41-flash-dgxsparks/sglang-overlay.ctx600k/deepseek_v4_backend.py:3456`、`.../deepseek_v4_memory_pool.py:607,646`（各 overlay 变体同款） ｜ web 标题一致，merged 09-19 |
| **#56457** | `[Bug] … QSA indexer: per-chunk logits buffer grows with max_seq_len, caching allocator keeps every size, device OOM/hang on unified-memory GB10 (SM121) during long prefill`（**issue**，非 PR）。 | **未合入**（issue，open）｜**已核实(web)** | ★**我方 FIX-D 的独立印证**：与 #39095 同族。我方代码注释把它与 #39095 并列引为"per-chunk stranding 病"的外部锚（"maintainer fix 建议 reserve the worst case / fixed workspace"）。⚠ 本地文档写作"vLLM #56457"——**本次核实：`vllm-project/vllm` 下该号是 issue（标题与上文一致），仓库确为 vLLM**。同时提示 `VLLM_SPARSE_INDEXER_MAX_LOGITS_MB` 与"取 workspace manager"两条修法。 | 代码：`dsv41-flash-dgxsparks/sglang-overlay.ctx600k/deepseek_v4_backend.py:3455`、`.../deepseek_v4_model.py:283`（probe 树） ｜ web: `vllm-project/vllm` issue 56457，open |

### 2.2 其余 sglang 编号（按本地出处登记；未逐条打网络）

> 归属栏：`推` = 上下文推断（给出依据行）；`未` = 归属未核实。状态栏里的日期/结论**全部照抄本地出处**，未复核。

| 编号 | 一句话（来自本地上下文） | 状态 | 对我方的影响 | 出处（file:line）｜归属 |
|---|---|---|---|---|
| #24861 | 上游早有的 "idle periodic cache emptying" 路径，`empty_cache()` 已抽成后端无关 helper | 已合入（05-10） | 我方 idle-release 长期应**优先复用既有 env/机制**，而非新造 `DSV41_*` 门（已入队） | `~/V41-UPSTREAM-TRACK-20260922.md:50` ｜推 |
| #28511 | ReplaySSM spec-verify（Part B of **RFC #28511**）：linear-attn target-verify | 背景（RFC） | 我方 `server_args.py` 的对应注释锚 | `dsv41-flash-dgxsparks/image-patches/0.2.7/server_args.py:2743` ｜推 |
| #31016 | DSpark confidence 线（与 #34024） | 背景 | 接受长度正确性同族 | `~/V41-UPSTREAM-TRACKING-20260914.md:33` ｜推 |
| #32888 | `_update_prefill_budget` 按 page-ceiled 长度扣减 ⇒ batch 到不了 chunk 上限（16368 vs 16384） | 已合入（09-14） | 修同类（chunk 利用率）；0.2.7 评估项 | `~/V41-UPSTREAM-TRIAGE-20260920.md:35`、`~/V41-OPTIMIZATION-MASTER-PLAN-V4-20260920.md:111` ｜推 |
| #33403 | 上游跟进项（先核查存在性） | 背景 | 低 | `~/V41-OPS-ROUND1-SELECTION-20260914.md:21` ｜未 |
| #33616 / #35214 | mHC Post+Pre 融合**默认开**（v0.5.18） | 已合入 | 我方 env 默认已同上游（True），但当前靴实际=关 ⇒ 待闸 | `~/V41-UPSTREAM-CHECK-20260918.md:17` ｜推 |
| #33831 | DSpark confidence 线 | 背景 | 同 #31016 | `~/V41-UPSTREAM-TRACKING-20260914.md:33` ｜推 |
| #34024 | DSpark confidence 用 checkpoint 固有 gamma（与 #31016 同族） | 背景 | 切 compact 前必修族 | `~/V41-UPSTREAM-TRACKING-20260914.md:33`、`~/V41-UPSTREAM-TRIAGE-20260920.md:39` ｜推 |
| #34053 | KV 定尺寸要把**常驻权重**算进 profile 基线（否则池过度分配 ⇒ graph capture OOM；63434 tokens/15.48 GB → 38430/9.38 GB），且须在分布式 MIN 前按 rank 本地修正 | 已合入（08-27） | 与我方"池锚不可复现（GMU 随机游走）"经验同族——上游答案="把基线取对"，我方="锁池" | `~/V41-UPSTREAM-TRACK-20260922.md:51` ｜推 |
| #34155 | DSV4 1M 上下文 nonpaged indexer OOM | 背景 | CTX600K 族的同构上游报告 | `~/V41-CTX600K-VERIFICATION-PLAN-20260921.md:129` ｜推 |
| #34234 | draft KV 池必须用 **draft 自身几何**精算 bytes/token（否则估 20480 vs 实 10240 ⇒ 池超配） | 已合入（08-10） | DSpark 侧可核对同款字段 | `~/V41-UPSTREAM-TRACK-20260922.md:52` ｜推 |
| #34846 | `[DSpark] Fix draft MoE expert-location dispatch to restore speculative acceptance`：非恒等放置下 draft 跑**错专家**，伤接受率（accept len 1.61→3.38，吞吐 161.64→313.24 tok/s） | 未合入（open）｜**已核实(web)** | 我方 `init_expert_location=trivial` ⇒ **判不适用**（trivial 布局不打此 bug），降为观察项 | `~/V41-SGLANG-OPS-ROUND2-20260914.md:201,254`、`~/r4-ops-work/r9-ops-20260914/evidence/upstream-followup-20260915/UPSTREAM-FOLLOWUP.md:55` ｜ web 标题一致（open） |
| #34878 | `[SM12x] b12x MXFP4 MoE: align with vLLM's pin, share the arena, run W4A8` | 未合入（open draft 08-14） | **与我方路线同侪**；蓝本（含 up_gate 布局陷阱：sglang W13=`[up;gate]` 而 vLLM=`[gate;up]`；arena 共享修 250 MB×46 层） | `~/V41-B12X-OFFICIALIZATION-ANALYSIS-20260913.md:92,105`、`~/V41-UPSTREAM-TRACK-20260922.md:111` ｜推 |
| #35413 | SPS/预算排程线（#38897 family） | 背景 | static 模式损失的直接对应物 | `~/V41-UPSTREAM-TRACKING-20260914.md:31` ｜推 |
| #35899 / #38685 | SM12x b12x 算子线（draft/未合） | 未合入 | 观望 | `~/V41-UPSTREAM-TRACKING-20260914.md:34` ｜未 |
| #36083 | 层 20 出 16384 候选 → 24/28/32/36 只评候选（= #39057 同族思路） | 背景 | CED 优化报告（`~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md`）§1「上游调研吸收：CED 8 项的逐项判决」表的「项 1.3 解码器 4 个 indexer 重算层 20 的选择」行 ｜推 |
| #36288 / #36933 | mixed chunk 基建 + spec 共存（v0.5.19 起） | 已合入（08-27/31） | 我方 fork **私有同款**，长期应对齐减冲突 | `~/V41-UPSTREAM-TRIAGE-20260920.md:37` ｜推 |
| #36583 / #36911 | CUDA graph 池按实测尺寸 / 加载期引用导致 KV 算小 | 背景 | 内存面家族，评估 | `~/V41-UPSTREAM-TRIAGE-20260920.md:43` ｜推 |
| #36649 / #36845 | **不取**（Qwen 专用） | 已否决（本地判定） | 无 | `~/V41-OPS-ROUND1-SELECTION-20260914.md:24` ｜推 |
| #36796 | SM121 kernel 瓶颈清单 + NCCL 实参 | 未合入（open） | 调优清单 | `~/V41-UPSTREAM-TRIAGE-20260920.md:54` ｜推 |
| #36797 | NVFP4 KV 在 SM121 比 fp8_e4m3 decode **慢 ~29%** | 背景 | **KV dtype 选型警示**（我方 `fork-v4-fp4` 主 KV 需自查此点） | `~/V41-UPSTREAM-TRIAGE-20260920.md:53` ｜推 |
| #36941 | **GB10 长 prefill(>40K) 耗尽统一内存静默杀 worker rank，head 挂 collective 自终止**（2×Spark TP2、chunk 8192、DFLASH D=5、fp8 KV、mem-frac 0.92；40k 过、54-62k 时 rank 静默死，容器 `OOMKilled=false ExitCode=0`） | 未合入（open 08-29，静默）｜背景 | ★**与我方第三方 0.2.4 131072×C16 挂死同构**；我方 0.2.6 已过同格（T1 家族缓解），**根因族上游仍 open**，长档保留门禁 | `~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:141`、`~/V41-UPSTREAM-TRIAGE-20260920.md:50`、`~/V41-UPSTREAM-TRACK-20260922.md:55` ｜推 |
| #36943 | `--enable-symm-mem` 下 `ncclCommWindowRegister` 静默死锁 | 未合入（open） | 我们未开 symm-mem ✓ | `~/V41-UPSTREAM-TRIAGE-20260920.md:59` ｜推 |
| #37188 | DSpark 性能线（一部分） | 背景 | 观望 | `~/V41-UPSTREAM-TRACKING-20260914.md:32` ｜未 |
| #37326 | MTP 接受率随 uptime 衰减至 ~0（吞吐 −2.9×），重启恢复 | 未合入（open） | **监控项**：接受率 vs uptime 看板 | `~/V41-UPSTREAM-TRIAGE-20260920.md:25,57` ｜推 |
| #37478 | `dsa_indexer_kpool.py` 里 `_should_chunk_mqa_logits` **定义但零调用者**；超 2.147 GB 地址上限落 `gl.store` fallback 编译失败 ⇒ LLVM assert **abort 掉每个 TP rank** | 未合入（open 09-01） | ★**一条不经 NVRM 就能杀光的静默死法**，值得与 `_low_ratio_index_topk_dense` 热路径对照 | `~/V41-UPSTREAM-TRACK-20260922.md:54` ｜推 |
| #37479 / #37737 | DGX Spark 2×GB10 DSV4-Flash 官方 cookbook | 背景 | 抄作业对照（chunk 档/KV dtype/NCCL 实参） | `~/V41-UPSTREAM-TRIAGE-20260920.md:52` ｜推 |
| #37502 | parked chunked req 计入内存不变量 | 已合入（09-03） | 防误报泄漏，带入 | `~/V41-UPSTREAM-TRIAGE-20260920.md:42,125` ｜推 |
| #37610 / #38941 | **全树 grep 零痕迹**的两项 MERGED PR | 待判定 | Z3 残留核查（30 分钟 content-level 判定：在/不在/要不要） | `~/V41-OPTIMIZATION-MASTER-PLAN-V3-20260919.md:36` ｜未 |
| #37712 | GLM kpool `fp8_mqa_logits` 物化 **73.65 GB** | 背景 | CTX600K 族的第三方同病 | `~/V41-CTX600K-VERIFICATION-PLAN-20260921.md:130` ｜未 |
| #37892 | topk_v1 非法访存、paged prefill 永远到不了 v2 | 背景 | **不命中**（当前靴 22h + 9 个历史日志零命中） | `~/V41-UPSTREAM-CHECK-20260918.md:14` ｜推 |
| #37898 | SM120 32GB 档 chunked_prefill 2k→4k 实证 | 背景 | 小显存档对照 | `~/V41-UPSTREAM-TRIAGE-20260920.md:55` ｜推 |
| #38170 | SM120 默认 FI b12x NVFP4 GEMM | 未合入（draft） | SM12x b12x 算子线 | `~/V41-UPSTREAM-TRACKING-20260914.md:34` ｜推 |
| #38235 | scratch capacity 必须由调度器契约推导——2×DGX Spark 实测**需 412,183,756 B 而只预留 400,008,864 B ⇒ 双 rank 终止** | 未合入（open 09-06） | "按容量分配"必须与调度器最大行数契约一致（= b12x `outs[cap]` 家族） | `~/V41-UPSTREAM-TRACK-20260922.md:110` ｜推 |
| #38319 | chunked prefill + radix insert 竞态（QSA 族上报） | 背景 | 无崩溃迹象；fork 有防竞态工程化 | `~/V41-UPSTREAM-CHECK-20260918.md:18` ｜推 |
| #38364 | 共享 embed/lm_head 必须在**池定尺寸之前**，否则池偏小；修后 KV 容量 **+8.94%** | 已否决（closed 未合，结论明确） | **我方 DSpark 同样存在该时序问题** | `~/V41-UPSTREAM-TRACK-20260922.md:53` ｜推 |
| #38409 | `[Fix] Wait for PDL before reading DeepSeek V4 K cache locations`：融合核在 `PDLWaitPrimary` 前读 `out_loc`，可能选到过期 cache slot | 已合入（09-14）｜**已核实(web)** | ★**Lane D Wave 1 已转正**（我方镜像内含） | `dsv41-flash-dgxsparks/start.sh` 的 `SGLANG_OVERLAY_MAP` 里 `Lane D Wave 1` 段注（含 `PR38409`）、`~/V41-SGLANG-OPS-ROUND2-20260914.md:75` ｜ web 标题一致（merged 09-14） |
| #38420 → **#39420** | **号码纠正**：本地原记 #38420，真 PR = **#39420**（side-stream 保单流，已 merge dsv4.1） | 已合入 | **Lane D Wave 2** | `~/V41-SGLANG-OPS-ROUND2-20260914.md:16,76,79,237`、`dsv41-flash-dgxsparks/start.sh` 的 `SGLANG_OVERLAY_MAP` 里 `Lane D Wave 2` 段注（`PR39420 side-stream/graph single-stream`） ｜推 |
| #38478 | **open RFC**：FCFS 队头大请求 NO_TOKEN 即 break，队后小请求饿死 | 未合入（open RFC） | **正是我方 ≥32K 断崖的机制描述** | `~/V41-UPSTREAM-TRIAGE-20260920.md:12,36` ｜推 |
| #38679 / #39057 | compact 打分进 main（Hopper）；TP4 线性 compact 验证 | 已合入（09-11）/ 未合入（09-09 open） | U1 路线图输入 | `~/V41-UPSTREAM-TRIAGE-20260920.md:41` ｜推 |
| #38792 | comm/compute overlap（本地记作 **D3**） | 背景 | collective 27.7% + other 13.4% = **ring fabric 上最大软件杠杆**；本地 Z5 = "selective rebase，只取 SM120 direct SWA KV + FP8 wo_a hunk" | `~/V41-OPTIMIZATION-MASTER-PLAN-V3-20260919.md:38,83`、`~/V41-OPTIMIZATION-MASTER-PLAN-V4-20260920.md:36`、`~/V41-PR-TOPOLOGY-RING-VS-STAR-PAPER-20260920.md:212` ｜推 |
| #38897 | SPS profiler budget pins（SPS/预算排程线） | 背景 | static 模式损失的对应物 | `~/V41-UPSTREAM-TRACKING-20260914.md:31` ｜推 |
| #38902 | 姊妹 issue（packed FP4 主 KV，Hopper）**open 无代码** | 未合入（issue） | ⇒ M0/M1 从自研降为 cherry-pick（见 #39123） | `~/V41-FP4-MAIN-KV-PROJECT-20260915.md:21` ｜推 |
| #38936 | TP LM-head all-to-all NCCL graph buffer 突发挂死（已修） | 已合入 | 若开 symm-mem/graph 相关需对照 | `~/V41-UPSTREAM-TRIAGE-20260920.md:58` ｜推 |
| #38970 | V4.1 low-ratio indexer 的 DeepGEMM schedule（我方此前未记录） | 背景 | CED §3 对应项 | `~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:50` ｜推 |
| #38976 | eight-way split-K BF16 WO-A **无损** | 已合入（base=dsv4.1） | 社区给出更划算的**前插步** | `~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:171` ｜推 |
| #38979 | `[Perf] DSV4: up to -34% prefill TTFT on 840K-token prompts (B=1) via query-dim top-K reuse`（相邻 query 行 top-K 高度重叠 ⇒ 一个 leader 行代表一窗） | 未合入（open，opt-in `--deepseek-v4-prefill-reuse` 默认关）｜**已核实(web)** | ★**我方"挂错分支"判负案，并直接催生一条**纪律条款**：#38979 教训 = **窗口顺序伪影**——A/B 臂交替顺序、原始读数落盘，缺一不得转正。我方 `dsv4_prefill_reuse.py`（PR#38979 回移）判**死代码/关**。**Lane D Wave 3** 之一。 | `~/V41-OPERATOR-INVENTORY-AND-ROLLBACK-LEDGER-20260919.md:33`、`~/V41-OPTIMIZATION-MASTER-PLAN-V3-20260919.md:14,100`、`dsv41-flash-dgxsparks/start.sh` 的 `SGLANG_OVERLAY_MAP` 里 `Lane D Wave 3` 段注（`PR38979 prefill reuse`）、`~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:315` ｜ web 标题一致（open） |
| #39028 / #39365 | **不取**：DSV4.1 有原生 hook / 仅加载时间 | 已否决（本地判定） | 无 | `~/V41-OPS-ROUND1-SELECTION-20260914.md:24`、`~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:35` ｜推 |
| #39116 | DSV4 DSpark 接受长度修复 + host 气泡削减 | 已合入（09-12） | 修同类，评估带入 | `~/V41-UPSTREAM-TRIAGE-20260920.md:38,121` ｜推 |
| #39138 | EngramHasher（engram hash 内提交，合于 dsv4.1 侧支）——bitwise 等价 | 已合入 | **Lane D Wave 1**（已转正；`#39138/#38409 确认镜像缺失`→后补） | `~/V41-OPS-ROUND1-SELECTION-20260914.md:21,30,35`、`~/V41-SGLANG-OPS-ROUND2-20260914.md:75`、`dsv41-flash-dgxsparks/start.sh` 的 `SGLANG_OVERLAY_MAP` 里 `Lane D Wave 1` 段注（含 `PR39138`） ｜推 |
| #39154 | DSpark decode 每步 8 次 pinned H2D → kernel launch 参数（小而独立） | 未测（队列） | QW3，下一窗候选 | `~/V41-SGLANG-OPS-ROUND2-20260914.md:254`、`r4-ops-20260914/evidence/quickwins-20260915/QUICKWINS-VERDICT.md:29` ｜推 |
| #39158 | `hc_combine_norm` 上限 8→12（⚠ 先复现其 GB10 数值分叉报告） | 背景 | CED 再评项 | `~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:180` ｜推 |
| #39171 | FlashMLA pin bump | 已否决（本地判定：**对 GB10 无可用内容**——容器内 `import flash_mla` → `ModuleNotFoundError`） | 无 | `~/V41-OPTIMIZATION-MASTER-TASKPLAN-20260915.md:307` ｜推 |
| #39173 | compact ragged engram 小工程（~20-40 行）；跟踪其修复进展后可重启用 compact ragged verify | 未合入 | 与 #39257 关联 | `dsv41-flash-dgxsparks/docs/4DGX-dsv41-上游调研-20260913.md:75,91,111,351,387` ｜推 |
| #39193 | wo_a 守卫冲突（SM121 强制 False=上游坏路径） | 未合入 | **T4（wo_a fp8 重打包）的前置**：先解此守卫冲突 | `~/V41-OPERATOR-INVENTORY-AND-ROLLBACK-LEDGER-20260919.md:123` ｜未 |
| #39205 / #39666 | Mooncake backend（Engram 阻塞 + prefetch 三重 AND 的上游路线） | 背景 | 上层有路线，**本机修法需自研** | `~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:43` ｜推 |
| #39226 | deep_gemm MoE runner 在 SM121 capture 崩溃 | 背景 | **不命中**（生产 `moe_runner_backend='flashinfer_mxfp4'`） | `~/V41-UPSTREAM-CHECK-20260918.md:15` ｜推 |
| #39301 | dev-dsv41 缺 `-lcuda` → 静默回退，修后 BS1 +28% | 背景 | **P0 核查**（零成本高潜在） | `~/V41-OPS-ROUND1-SELECTION-20260914.md:17` ｜推 |
| #39302 / #40286 / #40558 | SM121 backend 缺口族 | 未合入 | **跟进清单（只盯状态，无动作）** | `~/V41-UPSTREAM-TRACK-20260922.md:126` ｜推 |
| #39336 | DSpark 性能线（被 #39370 取代） | 背景 | 无 | `~/V41-UPSTREAM-TRACKING-20260914.md:32` ｜推 |
| #39370 | decode + prefill kernel 合并优化（**取子项**：fast_argmax −46 µs / sharded_greedy / packed router ids −64 µs / fused MXFP8 quantize −56 µs；验证口径 EP1≠我方 EP2） | 已合入（拆子项取用） | 55 文件深改 ⇒ **冲突高危只拆子项** | `~/V41-OPS-ROUND1-SELECTION-20260914.md:23,30`、`~/V41-SGLANG-OPS-ROUND2-20260914.md:75` ｜推 |
| #39397 | 边界融合 2 核→1 launch（mHC single-pass / Mega-mHC 的开源侧唯一件） | 背景 | 官方 Mega-mHC 只在技术报告文字里 | `~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:41` ｜推 |
| #39622 / #47584 | "换精度"族（lm_head 每步跑 2 遍全 vocab 的邻近 PR） | 背景 | 与 #39365 family 并列；**lm_head 双遍问题无上游件 ⇒ 需自研** | `~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:35` ｜推 |
| #39807 | Support consumer Blackwell (SM120/SM121) for NVFP4 serving | 未合入 | 🔴 **高价值追踪**：若合入，R8「nvfp4 三重锁死」的 SM121 门被解 | `~/V41-UPSTREAM-CHECK-20260918-R2.md:35` ｜推 |
| #40006 | prefill burst 混批度统计 | 已合入（09-19） | **观测手段**——量化"一次 burst 混了几个请求" | `~/V41-UPSTREAM-TRIAGE-20260920.md:44,127` ｜推 |
| #40065 | fastsafetensors 逐 shard 释放 buffer | 未合入（open PR） | boot 内存卫生，rebase 项 | `~/V41-UPSTREAM-CHECK-20260919-R3.md:32` ｜推 |
| #40160 | FP4 grouped indexer 的 FP8 Tensor Core 路径 | 背景 | 追踪：indexer prefill 面的性能项 | `~/V41-UPSTREAM-CHECK-20260918-R2.md:38` ｜推 |
| #40161 / #40162 / #40173 / #40175 / #40177-79 | SM120 FP8 注意力后端 / NVFP4×MXFP4 draft 专家路由 / PD-CP 系列 / compact verify 相关 | 未合入（低优先） | #40162 = compact 门（与 #39257 并列的 U1 触发器）；#40177-79 = PD 分离系列（S4 短期不可用） | `~/V41-UPSTREAM-CHECK-20260918-R2.md:39`、`~/V41-OPERATOR-INVENTORY-AND-ROLLBACK-LEDGER-20260919.md:124`、`~/V41-PRDE-SCHEDULING-OPTIONS-20260919.md:16` ｜推 |
| #40200 | Batch bounded encoder SWA replay（V4.1） | 未合入 | 追踪：我方 CED 结论「encoder bounded replay 不做」，上游在做 | `~/V41-UPSTREAM-CHECK-20260918-R2.md:36` ｜推 |
| #40219 | V4.1 vision interleave CP | 未合入（open PR） | N/A（CP 架构） | `~/V41-UPSTREAM-CHECK-20260919-R3.md:33` ｜推 |
| #4030 | SM12x indexer 两级分块 top-k + 核内 causal offset，prefill 在 **128 MB scratch 上限**内跑 | 已合入（08-26） | 与我方 indexer 分块 + 固定预算**同向** | `~/V41-UPSTREAM-TRACK-20260922.md:113` ｜推 |
| #40574 / #40613 | #40574 两级 candidate indexer 统一（SM12x/CP 下 sparse prefill **仍在清单里**，open）；#40613 CP 下启用 DeepGEMM 稀疏 prefill（open 09-21） | 未合入（open） | **#40352 的周边跟踪件**，移植前置评估时一并看 | `~/V41-UPSTREAM-TRACK-20260922.md:33` ｜推 |
| #11910 | stream/device coupling（`scheduler.py` 内的上游注释锚） | 背景 | 我方 `image-patches/0.2.7/scheduler.py` 引用它说明 stream 耦合 | `dsv41-flash-dgxsparks/image-patches/0.2.7/scheduler.py:1172` ｜推（**sglang**） |
| #3738 | 某 path "introduced by FlashInfer #3738 and requires FlashInfer >= 0.6.18" | 背景 | ⇒ **该号属 FlashInfer，不属 sglang**（见 §4） | `dsv41-flash-dgxsparks/image-patches/0.2.7/server_args.py:2467` ｜推（**flashinfer**） |
| #10866 | 挂了一年没合的 Simple-EAGLE（DSpark 侧零命中） | 已否决（未合） | 我方 DSpark draft/verify 串行**无对应上游件** | `~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:45` ｜推 |
| #22208 / #31241 / #31955 | 极小 M 的 MoE 配置 / 融合 A GEMM 调度 / 按 M 在 fp8 与 bf16 间门控 | 背景 | 对照项；#31955 方向与我方 §1.5 混合臂一致 | `~/V41-B12X-PR34878-AND-DENSE-GEMM-20260915.md:140-142` ｜推 |

---

## 3. vLLM（`vllm-project/vllm`）

| 编号 | 一句话 | 状态 | 对我方的影响 | 出处 |
|---|---|---|---|---|
| **#52645** | `[Bugfix][Parser] Recover DeepSeek V4 tool calls with malformed DSML wrappers`：DSML invoke 块完整但外层 `tool_calls` opener 缺失/畸形时结构化调用丢失；修法加 provisional-start / provisional-commit 标记，bare invoke 作为恢复候选，校验函数名后只在 invoke-end 提交。 | **未合入**（open，ready for review，带 `needs-rebase`）｜**已核实(web)** | ★**我方 0.2.4 工具调用截断三保证的来源（回移）**，`BASELINE.md` 的「2026-09-19（收官）：v0.2.3 正式检查点 + 客户坑审计 + V3 矩阵 + git 提交」节 → `工具调用截断三保证（vLLM #52645 回移）` 条记"vLLM #52645 回移 + finish() 桩测 13/13"。⚠ 本地把它登记为"**仓库+编号，未附链接**"——本次已核实为 vLLM PR。**注意上游只到 open，我方是自持回移。** | `w6-kit/guard/BASELINE.md`（「2026-09-19（收官）」节 → `工具调用截断三保证（vLLM #52645 回移）` 条）、`w6-kit/guard/README.md` §16「引用与出处」的 `vLLM #52645` 行、`dsv41-flash-dgxsparks/start.sh` 的 `SGLANG_OVERLAY_MAP` 里 `tool-call truncation semantics (vLLM #52645 port)` 注（v0.2.4 patch）、`~/V41-TOOLCALL-TRUNCATION-AUDIT-20260919.md`、`~/crossreview-detector-patch-20260919.md:34` ｜ web 标题一致 |
| **#55569** | **机理**：稀疏 indexer prefill logits = (chunk queries × prefix pools) fp32，231K 时 **≈475 MB/layer**，**每个 chunk 形成新尺寸** ⇒ 缓存分配器不断要新 segment；**UMA 上驱动在分配器 OOM-retry 清缓存之前就返回 `NV_ERR_NO_MEMORY`**。验证：`VLLM_SPARSE_INDEXER_MAX_LOGITS_MB` **512→64 即平**；`expandable_segments:True` 单独也修好默认值 ⇒ **机理是碎片，不是单次调用绝对大小**。 | 未合入（open 09-06） | ★与**我方 FIX-A（`max_split_size_mb=256`）反噬实锤并已回退**互为**独立印证**——两个团队在不同代码库上得出同一结论 | `~/V41-UPSTREAM-TRACK-20260922.md:37,126`、`~/V41-CTX600K-READINESS-20260922.md:66`（600k env budget 512→128 MiB，方向与 512→64 一致） ｜上下文推断（本地未附 URL） |
| **#58068** | **修法**：按 `ceil(max_model_len / compress_ratio)` **固定宽度**分配、再窄化成 `[M,N]`；新 env `VLLM_SPARSE_INDEXER_FIXED_LOGITS_WIDTH`（**未设 = 仅集成/UMA GPU 默认开**）。★文中明确：`max_split_size_mb:256`、私有 MemPool、`expandable_segments:True` **都被试过，"更差或无效"**。 | 未合入（open 09-22，等 code-owner）｜**已核实(web)** | 我方 **FIX-D「宽度分桶（9185 尺寸→2）」是同一思想的局部实现**；上游把它推广成"一个固定宽度覆盖全模型" ⇒ 我方分桶档位**可进一步收敛到 1 档** | `~/V41-UPSTREAM-TRACK-20260922.md:38-41` ｜ web 标题 "[Bugfix][Attention] Fixed-width sparse indexer prefill logits so long prefills reuse allocator blocks (#55569)" |
| **#56457** | 见 §2.1（vLLM issue，与本表 #55569 同族） | 未合入（issue open）｜**已核实(web)** | 同 §2.1 | 代码 `deepseek_v4_backend.py` 的 `#56457` 注释行（FIX-D 分桶说明内） ｜ web |
| **#45284** | `[Model][Transformers backend] Fuse q/k/v and gate/up linear groups`：把 attention QKV 三元组与 SwiGLU MLP 对融合成 packed 层（`QKVParallelLinear, MergedColumnParallelLinear`），缩 transformers backend 与原生模型的每步计算差（granite-4.1-8b TP4 TTFT 从 +17% → +0.1%）。 | **已否决**（**closed，被 #47187 取代**，带 `needs-rebase`）｜**已核实(web)** | 本地把它列在 B12X-PR34878 报告的行内（"dense 侧 111 次小 GEMM 这个数字偏低"讨论的邻接件）；**本次核实纠正状态为 closed/superseded**。 | `~/V41-B12X-PR34878-AND-DENSE-GEMM-20260915.md:13` ｜ web 标题与状态一致 |
| #35356 | 自该 PR 起，集成 GPU 的"free memory"口径有陷阱 | 已合入 | 我方 FIX-D 判定里明确引用：**UMA 上 `mem_get_info` 跟 MemFree 非 MemAvailable = #35356 要修的坑** ⇒ 上游 #39095 的自适应预算在 GB10 系统性低估 | `w6-kit/reference/GLM-5.3-Flash-NVFP4-1M-KV-4x-DGX-Spark/docs/GB10-KV-MEMORY-LADDER.md:32`（我方参考树内） ｜推 |
| #39634 | `Integrate flashinfer b12x MoE and FP4 GEMM kernels for SM120/121` **引入 b12x**（真身=SM12x 专用 NVFP4/MXFP4/MXFP8 CuteDSL 内核家族） | 已合入 | b12x 的出处 | `~/V41-UPSTREAM-TRIAGE-20260920.md:63` ｜推 |
| #47599 | 共享 workspace 的 `max_rows` 变化使已编译小核失效 ⇒ ~**17.5 s 全引擎 stop-the-world**，需启动期按最大 token **先撑开 workspace 再编译** | **已否决**（closed 未合） | ★**解释了我们要 golden 锁 warmup 的深层原因** | `~/V41-UPSTREAM-TRACK-20260922.md:56` ｜推 |
| #47982 / #48698 | capacity 须按 `dp_size` 缩放，且 **`min_num_tokens=0`，不让 8192 调优地板污染 workspace** | 已合入（已修） | b12x `outs[cap]` 契约家族的正解方向之一 | `~/V41-UPSTREAM-TRACK-20260922.md:112` ｜推 |
| #49079 | 单机 GB10 sm_121 上 b12x 使**峰值激活 ~46.61 GiB**、KV 由 ~58.38 GiB 降到 **~25.59 GiB**（权重/图内存不变） | 未合入（open） | 我方"b12x 抬高门槛"的**外部同案** | `~/V41-UPSTREAM-TRACK-20260922.md:109` ｜推 |
| #49760 / #46307 | #49760：`VLLM_UNIFIED_MEMORY_HOST_RESERVE_GB` 默认 **8.0** 或池的 5%（分配前 `min(budget, MemAvailable − host_reserve)` 封顶）；#46307：启动 profile 瞬态不受 util 约束 ⇒ 整机 wedge，需断电 | 背景 | 与**我方内存地板守卫**语义可直接对齐：上游取 max(8 GiB, 5%)，我方取 1.5 GiB（2026-09-23 起；原 3）因已实测出瞬态本征量级；方向一致 | `~/V41-UPSTREAM-TRACK-20260922.md:83` ｜推 |
| #50538 | reload 后重建 experts ⇒ **已捕获的 CUDA graph 读已释放存储**、引擎阻塞 >10 分钟 | 未合入（open draft 07-31） | 与我方图捕获 + workspace 生命周期同族，**值得自查** | `~/V41-UPSTREAM-TRACK-20260922.md:57,123` ｜推 |
| #47808 | adaptive verification（0.28.0 含） | 已合入 | **fork 自带 #47808 式置信门控链已在树**（`scheduler.py:276-281 _conf_gate` + `:2150-2175` survival=cumprod 截尾） | `~/V41-CAMPAIGN-PLAN-V2-20260912.md:232`、`w6-kit/G1R7VL-VLLM028-MERGE-FEASIBILITY-20260903.md:17` ｜推（**vLLM**） |
| #47926 / #47930 | APC（自动前缀缓存）× draft-KV 污染（`#47930` 号在同一行；`#47926` 见 V41-CAMPAIGN-PLAN-V2:206 邻行） | 背景 | bug 面在我树完整（APC 默认开） | `~/V41-CAMPAIGN-PLAN-V2-20260912.md:206` ｜未 |
| #51725 | 自适应 spec 预算（0.28.0） | 已合入 | fork 血统项 | `w6-kit/G1R7VL-VLLM028-MERGE-FEASIBILITY-20260903.md:17`、`~/V41-CAMPAIGN-PLAN-V2-20260912.md:227` ｜推 |
| #50424 | 量化 Markov 头 | 已合入（上游件） | 后续臂 | `w6-kit/G1R7VL-VLLM028-MERGE-FEASIBILITY-20260903.md:17`、`w6-kit/G1R7VL-BAKED5-20260903.md:46` ｜推 |
| #52016 / #52018 / #52017 | b12x dense linear / b12x FP4 MoE / b12x attention | 已合入（#52017 09-01 才合 → 0.29） | b12x 的 vLLM 接入面 | `w6-kit/G1R7VL-VLLM028-MERGE-FEASIBILITY-20260903.md:17-18` ｜推 |
| #51538 / #52499 | DSpark × SM120 修复（08-15 / 08-16） | 已合入 | **fork 基线 v0.26.1.dev0+20260805 早于这两个 ⇒ draft 轨头号嫌疑** | `~/V41-CAMPAIGN-PLAN-R2-20260913.md:12` ｜推 |
| #51318 / #52492 / #52836 | 上游三件套核对：#51318（fork 的 `deepseek_v4/sparse_mla.py` 已是修后形态，但那是 SM9/10 FlashMLA 路径）；#52492 守卫**在场** | 已合入 | R8 窗口核对项 | `~/V41-R8-WINDOW-REPORT-20260913.md:16`、`V41-COMMUNITY-XREF-20260913.md:53` ｜未 |
| #53574 / #52448 | #53574 = **64 行界二分段**；#52448 = **breakable 家族** | 背景 | 上游 bug 全谱（`evidence/agent-graphbug-upstream.md`） | `~/V41-R8-WINDOW-REPORT-20260913.md:19` ｜未 |
| #52291 / #52292 | #52291 多节点 autotune **死锁**（分布式 autotuner 每 tactic all-reduce 在 host-staged NCCL 上死锁——**GB10 级 fabric 正中**）；#52292 op… | 未合入（#52291 open） | 与 `/tmp` 日志、autotune 稳定性同族 | `w6-kit/G1R7VL-PROD-PENDING-FIXES-20260907.md:117` ｜推 |
| #54566 / #54618 / #54631 / #55636 / #55405 / #55180 / #55234 / #55299 / #55341 / #54110 / #56278 / #56137 / #55670 / #55696 / #55661 / #55581 / #53425 / #53521 / #53522 / #55455 / #55459 / #52451 / #55264 / #55042 / #55107 / #53435 / #54788 / #54997 / #54048 / #53090 / #53630 / #51318 / #52502 / #50416 / #50004 / #49486 / #48047 / #45861 / #52823 / #52802… | **逐条含义见 `V41-COMMUNITY-XREF-20260913.md` 与 `w6-kit/G1R7VL-*-2026090*.md` 的行内描述**（vLLM 社区 v0.28/v0.29 特性与 bug 群）。本表不复制其描述行以避免二手失真；几条已抽到上方单独行。 | 多为已合入/背景 | 逐条见各出处；**对我方影响=观望/对照，未进判决链** | 出处：`V41-COMMUNITY-XREF-20260913.md:24-67`、`w6-kit/G1R7VL-COMMUNITY-RERESURVEY-20260907.md:100-108`、`w6-kit/G1R7VL-PROD-PENDING-FIXES-20260907.md`、`w6-kit/G1R7VL-BASELINE-DELIVERY-20260908.md:45` ｜**归属未核实（逐条）** |

> **vLLM fork 源码树内的上游编号**（`w6-kit/g1r3-build/`、`g1r4-build/`、`g1r6-build/`、`g1r7-build/`、
> `g1r7-build/work/vllm/`、`g1r7-build/vl-baked6-ctx/vllm/`、`g1r7-build/g1r7-vl-ctx/vllm/`）：这些是我方
> vLLM fork 的**源码副本**，编号以注释形式存在。登记（**归属= vLLM，上下文推断**）：
> `PR #14142`（`models/deepseek_v4/attention.py:488/495/692/699`，TRT-LLM 3-way overlap Level 1）、
> `#44577`（多处：`attention.py:692`、`common/ops/cache_utils.py:784/832/837`、`nvidia/flashinfer_sparse.py:56`、
> `v1/attention/backends/mla/sparse_swa.py:97` = packed KV block_size）、
> `#3856`（`cache_utils.py:785/833/838`）、`#34303`（`config/model.py:313`）、`#40812`（`config/vllm.py:913`）、
> `#39177`（`envs.py:1240/1246`）、`#55636`（`vl-baked6-ctx/.../cache_utils.py:492`）、
> `#54566`（`fused_topk_bias_router.py:122`）、`#39324`（`s0-dspark-diff-20260910/gpu_model_runner_NEW.build.py:437`）。

---

## 4. FlashInfer（`flashinfer-ai/flashinfer`）

| 编号 | 一句话 | 状态 | 对我方的影响 | 出处 |
|---|---|---|---|---|
| **#5237** | `fix(jit): allow SM121 (DGX Spark GB10) in the moe_utils JIT arch filter`：`flashinfer/jit/moe_utils.py` 的 `supported_major_versions` 从 `[9,10]` 扩到含 12，否则 major-12 设备 `gen_moe_utils_module()` 直接 `RuntimeError`。 | **未合入**（open，作者 mythkina，已过 CodeRabbit，**无 approval 记录**）｜**已核实(web)** | ★**我方"步骤 0"的靶子，但结论是靶子不在我方路径上**：①#5237 的靶子 `moe_utils` **不在我方路径上**——我方 MoE 走 **b12x**，`moe_utils` 从未被取件（AOT 包里它只有 `sm_100a/sm_103a`，但包内 839/907 个模块都不参与我方路径）；②在役进程真正 mmap 的 AOT 模块只有 2 个（`fp4_quantization_120f`、`sparse_mla_sm120`），**都是 12x 原生**；③真正残留隐患是**机制性**的：`JitSpec.try_load()` 在 `is_aot` 时**直接 `return self.load(self.aot_path)`，不做任何 arch 校验** ⇒ 正确动作不是改取件逻辑而是**加一道体检**（= `flashinfer-arch-guard.sh`）。 | `w6-kit/guard/BASELINE.md` 的「2026-09-16 三次更新（步骤 9 判决 NOGO + 步骤 0 定谳 + 新增 arch 体检）」节 → `步骤 0 定谳（原命题需改写）` 条、`w6-kit/guard/guards.conf` 注释体里两处 `#5237`（`oom-gate-floor` 行上方的注释块）、`w6-kit/guard/flashinfer-arch-guard.sh` 头注的 `#5237` 背景段（**不写行号**：该脚本仍在改，2026-09-23 当天有过注释级改动）、`w6-kit/guard/README.md` §16「引用与出处」的 `#5237` 行（登记为"仓库+编号，未附链接"）、`~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:188` ｜ web 标题一致 |
| **#4380** | `feat(sm120): consolidate DSV4 sparse MLA top-k 192/256 support`：为 SM120/SM121 sparse MLA 后端加 DSV4 decode 实例化（topk=192/256，head 8-128）、单 cache prefill dispatch（BF16 QK）、TP8 prefill 的 padded H8 MG tile。取代 #4309/#4372/#3817/#3834。 | **已合入**（08-08 merged by bkryu）｜**已核实(web)** | 我方 l3fix 路径的起点：`install_and_probe.sh` 装 **flashinfer 0.6.18（contains #4380）** 进旁路容器，强制全新 JIT 编进**私有缓存**（绝不碰生产 `/root/.cache/flashinfer`），再跑 (H,192) 决定性探针。 | `w6-kit/install_and_probe.sh:2`、`w6-kit/a2_src_grep.sh:2,15`、`w6-kit/a5_commits.sh:3,7`、`w6-kit/bisect30.py:3`、`w6-kit/l3fix/REPORT.md` ｜ web 标题一致 |
| **#4598** | **issue**：`Sparse-MLA DSV4 decode autotuner: dense axis not bucketed, production shapes fall back to heuristic (+82%)`——decode 用 `extra_dense_topk` 预算、boot-time autotune 没覆盖 ⇒ 回退启发式分区（实测 **heuristic 656.97 µs vs best-tuned 360.50 µs = +82.2%**）。 | **未合入**（issue，open，`needs-triage`）｜**已核实(web)** | **autotune 覆盖域**与我方 golden 锁 warmup 同族；我方 v13 的多数表决 + golden 树正是不让这类"回退启发式"发生的机制 | 采集命中：`V41-...`（**本地仅见号，无独立上下文**——见 §12 缺口） ｜ web 标题与状态见上 |
| **#4603** | `feat(moe): allow B12xMoEWrapper to share pre-allocated workspaces`：`B12xMoEWrapper` 接受 `shared_static_workspace`/`shared_dynamic_workspace`/`shared_output` 三个可选构造参数，同形状 wrapper 复用同一组缓冲（MoE 层顺序执行故安全）。**同一模型 wrapper 总内存 ~68 GiB → ~1.2 GiB**（每层 static 640 + dynamic 506 + output 128 MiB，此前在 vLLM memory profiling 时 OOM）。 | **已合入**（08-25 merged by samuellees，2 commits）｜**已核实(web)** | ★**本清单里唯一的数量级内存杠杆**。我方在役 FlashInfer **0.6.18**，同时缺 **#4603（跨层 workspace 共享）** 与整个 **v0.7.0 的 SM121 修复** ⇒ 升级窗（"以 FlashInfer v0.7.0 + b12x 1.3.0 为构建锚一次性带入"）。⚠ 本地记载"v0.7.0 于 **09-22** 发布含 #4603"，而 **#4603 的合并日是 08-25** ⇒ 二者不矛盾（先合入、后随版本发布），但**不要把合并日当发布日**。 | `~/V41-UPSTREAM-TRACK-20260922.md:96,98`、`~/V41-DRIVER-VERIFY-VERDICT-20260922.md:186` ｜ web 标题与日期一致 |
| **#4802** | `Refactor Sparse MLA SM120`：SM120 sparse-MLA decode + prefill 重整；T=1 decode 14.9→11.3 µs（−24%，bitwise 一致）；用**标定解析模型 + 实测 decode/prefill 交叉点**取代 per-shape autotune 扫描；新增 GLM53_NOPE 与 DOTS3_SWA（滑窗 MLA）两个 model type；引入 `SparseMLASm120Wrapper` 与集中式 Python planner。 | **已合入**（09-03 merged by bkryu，57 commits）｜**已核实(web)** | 我方在役 0.6.18 **未含**（属 v0.7.0 批次）。本地社区重调研曾把 `#4802(#453aa7c)` 与 `#4850/#4931/#4973/#4955/#4993/#4990/#4749` 并列为 post1 包内容。 | `w6-kit/G1R7VL-COMMUNITY-RERESURVEY-20260907.md:107`、`V41-COMMUNITY-XREF-20260913.md:60`、`V41-UPSTREAM-TRACK-20260922.md:97` ｜ web 标题一致 |
| **#4598 / #4802** 备注 | 任务清单要求"`flashinfer #4598/#4802`"两条并列查证 | — | **#4598 = issue（autotuner 覆盖域），#4802 = PR（SM120 sparse MLA 重构）**，二者性质不同 | 同上 |
| **#5015** | padded spec batch 挂死 sparse MLA | 背景 | 我方 `RAGGED_VERIFY_MODE=static` 形态**规避** ✓（tonyd2wild 同判）；**切 compact 前需 #39257** | `~/V41-UPSTREAM-TRIAGE-20260920.md:109` ｜推 |
| **#5197** | DSv4.1 dual-cache（FP8 主 + FP4/FP8 extra，即 **FP4 KV 上游化**）、runtime page/head/topk dispatch（含 dsv4_1 族、非 2 幂 page）、L2-cold calibration（scratch 103→33 MiB） | 已合入（09-18 merged） | **T5/U2 的具体锚**：T5 = FlashInfer **核内读 288B**（FP4 KV 紧凑化），预期长 prefill −10%+；若 #5197 不含 SM121 须自研（K2-R 轨资产可复用） | `~/V41-UPSTREAM-TRIAGE-20260920.md:18,70`、`~/V41-OPTIMIZATION-MASTER-PLAN-V3-20260919.md:28,46` ｜推 |
| **#5174** | DSv4.1 ratio-2 层 prefill `extra_page_block_size=32` dispatch（>滑动窗 prompt 直接 Unsupported 崩）——上游化 sfxnz 的 GB10 patch | 未合入（open） | 评估带入 | `~/V41-UPSTREAM-TRIAGE-20260920.md:19,75` ｜推 |
| **#4484** | 空 KV 行 sentinel 伪概率修复（**乱码/幻觉类真内核 bug**） | 已合入 | **我方暴露**：0.6.18 未含修复 ⇒ 与我方乱码史（R8 已另定谳 verify logits 错位）不同源但同类症状；升 0.7.0rc3 一并消 | `~/V41-UPSTREAM-TRIAGE-20260920.md:20,72,108` ｜推 |
| **#5238** | mixed mxfp8×mxfp4 **仍**死在**预构建的 AOT 产物**里（不带 SM12x 镜像） | 背景（#5237 的后续 issue） | 与 `flashinfer-arch-guard.sh` 的动机同源（AOT 取件无 arch 校验） | `~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:196` ｜推 |
| #44577 | packed KV 的 block_size（"larger when packed"） | 背景 | 出现在我方 `flashinfer_sparse_l3_002.py` 与 vLLM fork 的 sparse MLA 路径 | `w6-kit/flashinfer_sparse_l3_002.py:53`、`w6-kit/g1r5-build/flashinfer_sparse.py:56` ｜推 |
| #2655 / #3170 / #11799 / #45317 / #51920 / #35577 / #51562 / #53635 / #52816 / #53906 / #3738 | 见 §10「外部参考树内编号」（`w6-kit/reference/GLM-5.3-Flash-NVFP4-1M-KV-4x-DGX-Spark/docs/*.md`）——多数为 SM121 fp8 MLA / sparse-MLA 后端选型 / DFlash2 的上游编号 | 背景 | 参考树内的自述，非我方生产引用 | 见 §10 |
| #3080 / #3874 / #4029 / #4012 / #4732 / #4661 / #4461 / #4746 / #4769 / #4781 / #4811 / #4847 / #4850 / #4909 / #4931 / #4952 / #4955 / #4973 / #4986 / #4990 / #4993 / #5024 / #5031 / #5039 / #5048 / #5061 / #5097 / #5142 / #5175 / #5214 / #3836 / #4223 / #49486… | FlashInfer 社区/版本批次条目（v0.6.18.post1 与 main cherry-pick 清单：post1 = `8bc3b57`，含 #4931 `skip_all_rows_active_check` 等） | 多为已合入/背景 | #5048 = DGX Spark 上 SM120 sparse-MLA swapAB prefill 间歇 hang 修复（**与 #4732 同族**）；#4781 = flashinfer-cubin 断供（4 条解法）；#3080 = `b12x_fused_moe`（FlashInfer PR） | `w6-kit/G1R7VL-COMMUNITY-RERESURVEY-20260907.md:107`、`V41-COMMUNITY-XREF-20260913.md:59-61`、`V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:51`、`V41-CAMPAIGN-PLAN-R2-20260913.md:25-26`、`w6-kit/patches-w4a4/flashinfer_b12x_moe_pooled.py:70` ｜**逐条归属未核实** |

---

## 5. b12x（SM12x NVFP4/MXFP4/MXFP8 CuteDSL 内核家族）

> **仓库归属**：本地 vendored 包 `dsv41-flash-dgxsparks/b12x-site/b12x/**/__init__.py` 里的 `repo=` 字段
> 同时出现 `https://github.com/lukealonso/b12x`、`https://github.com/local-inference-lab/b12x`、
> `https://github.com/phaelon74/b12x`、`https://github.com/MadeBy561/b12x` 四个组织名
> ⇒ **不能把 b12x 归属单一 repo**。PyPI 包名 `b12x`（我方在役 **1.3.0**）。
> 真身定义：`~/V41-UPSTREAM-TRIAGE-20260920.md:63`（vLLM PR #39634 引入，FlashInfer 以 sync-to-b12x-HEAD 方式收编）。
> 我方历史线索 `#34878/#358/#364-367` 在公开仓未定位到（内部/已关闭线）。

| 编号 | 一句话 | 状态 | 对我方的影响 | 出处 |
|---|---|---|---|---|
| **#397** | `perf(moe): tune repacked W4A8 grids and preserve prepared capacity`：调 repacked W4A8-MX decode 核的物理 CUDA block 数（M16/M32 tile，每 SM 至多两块），并改为**用声明容量做 kernel prepare、用活行数做 launch mask** ⇒ 缩小的活批不再切换已编译表示；grid-override 查表跟随 prepared capacity。 | **已合入**（09-21 merged 进 master，8 commits）｜**已核实(web)**；⚠ 本地记载"合入 09-19"，**web 页显示 09-21** | ★**`outs[cap]` 契约**：capacity 以"声明容量"表达，**活行数只控制 launch mask**，并修一处容量契约缺陷。**直接对应我方"b12x MoE `outs[cap]` 3.025 GiB（21 层×4 cap，per-boot 一次性）"**——上游口径是 cap 是声明、活行数不该改缓冲大小 ⇒ 我方要么把 **cap 阶梯与调度器最大行契约锁死**，要么付一次拷出。⚠ 本次核实：页面上**"outs[cap]"字面未出现**（本地写法是简写），实质是"prepared capacity / live rows"契约。 | `~/V41-UPSTREAM-TRACK-20260922.md:100`、`~/V41-DRIVER-VERIFY-VERDICT-20260922.md:186` ｜ web 标题一致 |
| **#396** | `fix(wo): preserve packed projection layouts and decode tiles`：prepared WO（attention-output projection）执行保留 packed/tiled 权重布局与广播块 scale 出处；绑定时校验声明的权重契约；**避免 scratch 的 scale-padding 写**；恢复首投影的 96 线程 tile 调度。 | **已合入**（09-21 merged from `perf/wo-prepared-decode`，10 commits）｜**已核实(web)**；⚠ 本地记载"09-19 合" | **wo_a 保留 packed 投影布局、decode tile；scratch 绑定只建视图、不再触发 scale-padding 填充（少一次写瞬态）** ⇒ 我方 T4（wo_a fp8 重打包）的同族件。⚠ 本次核实：**该 PR 页归属 `local-inference-lab/b12x`**（不是 `lukealonso/b12x`）。 | `~/V41-UPSTREAM-TRACK-20260922.md:103` ｜ web |
| **#413** | 在 prepared capacity 内复用 plan、**逐次校验 live extent 而 capacity 不变** = "按容量分配但不失控"的范式 | 已合入（09-22 合，**本地记载**） | 与 #397/#407 同族：`outs[cap]` 契约家族的正解方向 | `~/V41-UPSTREAM-TRACK-20260922.md:101` ｜**归属未核实**（未打网络） |
| **#407** | 调优缓存按 **compute capability + SM 数**取键（非设备名） | 已合入（09-21 合，**本地记载**） | 我们"四机同构、缓存必须一致"的对照 | `~/V41-UPSTREAM-TRACK-20260922.md:102` ｜**归属未核实** |
| **#399** | arm64 GB10 **`sm_121a` + Breakable CUDA Graph replay 期间非法访存杀 worker** | 未合入（open 09-20） | ★**与我方图捕获 + workspace 生命周期同族，仍开放未修** ⇒ 行动项 = 认领"我们是否命中" | `~/V41-UPSTREAM-TRACK-20260922.md:104,123` ｜**归属未核实** |
| **commit `02407f65`** | E4M3 subnormal **原生解码** | 已合入（v8 回补） | `b12x-site/b12x/_lib/intrinsics.py` md5 `24b1049ac800` → `2302dd1ec28b`；GPU 256 编码回归全过 | `w6-kit/guard/BASELINE.md` 的「2026-09-19：v8 上线（b12x 上游回补）+ MoE on/off A/B 定谳」节 → `b12x-site intrinsics.py` 行、`w6-kit/guard/guards.conf` 的 v8 回补注释行（原文 `2026-09-19 v8 上线（b12x 回补 02407f65+ff36d2d1…）`）、`w6-kit/guard/README.md` §16「引用与出处」的 `b12x 02407f65` 行（登记为"仓库+短号，未附链接"） |
| **commit `ff36d2d1`** | MXFP8 **swizzle 越界读防护** | 已合入（v8 回补） | `b12x-site/b12x/_lib/dense_gemm.py` md5 `e2c5233f6a4b` → `75f774c2ef4d` | `w6-kit/guard/BASELINE.md` 的「2026-09-19：v8 上线（b12x 上游回补）+ MoE on/off A/B 定谳」节 → `b12x-site dense_gemm.py` 行、`w6-kit/guard/guards.conf` 的 v8 回补注释行（同上）、`w6-kit/guard/README.md` §16「引用与出处」的 `b12x ff36d2d1` 行 |
| **#3268** | （b12x 源码注释锚） | 背景 | 出现在 `b12x-site/b12x/_lib/dense_gemm.py:1758` | 同上文件 |
| **#5191** | b12x MXFP8 BK128 尾块 NaN：SF TMA 每 BK128 装 4 组 scale，K%128≠0 时消费 padding scale code（UE8M0 NaN=255 污染）。**触发场景恰是 (M,N,K)=(6,5120,576) shared-expert down proj = 我方 wo_a 同形**！ | 未合入（open） | ★**暴露面**：CI 形状矩阵补 `K∈{544,576,608}`；与我方"wo_a bf16 岛"病因学相关（T4 排查输入） | `~/V41-UPSTREAM-TRIAGE-20260920.md:66,116` ｜推 |
| **#5191 备注** | ⚠ 本地 `V41-CED-OPTIMIZATION-REPORT-V2-20260916.md` 里 `#5197`（FlashInfer）与 `#5191`（b12x）号形近，**勿混** | — | — | — |

---

## 6. DeepGEMM（`deepseek-ai/DeepGEMM`）

| 编号 | 一句话 | 状态 | 对我方的影响 | 出处 |
|---|---|---|---|---|
| **#324** | `feat: add sm120 support for DeepGEMM`：为 sm_120/sm_121 加 dense GEMM、grouped/MoE GEMM、einsum、hyper-connection prenorm、MQA-logits 核；RTX PRO 6000 Blackwell 上 FP8 ~96% roofline。作者 leavelet（与 lucifer1004），**合进 `nv_dev` 分支**（06-24）。 | **已合入**（nv_dev 分支）｜**已核实(web)** | ★**这是"DeepGEMM 在 SM121 上有路"的根**：#39482（把 SM121 纳入 packed-scale 选择）建在它之上；而我方 QW2 判"DeepGEMM@SM121 = 负优化"（全路径慢 ~100×）说明**"有支持"≠"有性能"**。本地另有记载：DeepGEMM **26/09 release = PR #432**（见下），**nv_dev 分支 8 月底的 NVFP4 MegaMoE + fused shared experts 系未在我方 pin ⇒ 重 pin 评估**。 | **本地无直接引用点**（本次补登记；仅 `V41-UPSTREAM-TRIAGE-20260920.md:81-82` 提到"nv_dev 仍未在我方 pin"） ｜ web 标题一致（merged into nv_dev, Jun 24） |
| **#432** | `Public Release 26/09`：V4.1 **层级稀疏 indexer**、**Mega Gate +30~75%**、**Mega mHC +45~85%**（我方 mHC prefill 9.3% 份额的对口加速器）、MoE backward +20%；DeepJIT 集成、epilogue 融合、更宽 cuBLASLt。★**新增 `use_deterministic_algorithms()`，默认 False**（= 默认非确定性）。 | **已合入**（09-10 merged into `main`）｜**已核实(web)** | **breaking：默认非确定性**——与我方 greedy 一致性测试直接相关。加速器对应我方 mHC prefill 份额 | `~/V41-UPSTREAM-TRIAGE-20260920.md:78-82` ｜ web 标题 "Public Release 26/09" 与四条内容逐点吻合 |

> **`deep_gemm` 相关（无编号）**：`~/V41-UPSTREAM-CHECK-20260918.md:15` 的 **#39226**（deep_gemm MoE runner 在
> SM121 capture 崩溃）**不命中**我方（生产 `moe_runner_backend='flashinfer_mxfp4'`）；
> `image-patches/0.2.7/configurer.py` 的 `_compute_enable_deep_gemm()` 是 #39482 的落点。

---

## 7. llama.cpp（`ggml-org/llama.cpp`）

| 编号 | 一句话 | 状态 | 对我方的影响 | 出处 |
|---|---|---|---|---|
| **#27918** | **issue**：`CUDA: VMM pool 32 GB VA cap blocks full offload of >32 GB models on unified-memory GPUs (GB10/GH200) — hangs instead of failing`。`CUDA_POOL_VMM_MAX_SIZE = 1ull << 35`（32 GB）使 `cuMemAddressReserve` 在模型需 >32 GB GPU VA 时失败，表现为 dmesg 里**误导性的 `NV_ERR_NO_MEMORY`** + 在 `cudaMemcpyAsync` 里**无限挂起**（不是干净报错）；workaround = **`GGML_CUDA_NO_VMM=1`**（104 GB 模型可全 offload）。 | **未合入**（issue，open 08-28，作者 drew913s）｜**已核实(web)** | ★**"整机楔死"并列假设链的第四轴**：「VA / pool 上限（`NV_ERR_NO_MEMORY` 是误报）」。⇒ 楔死取证必须加一列 **reserved-but-unusable 量**。与本项目 `_memdescAllocInternal`/`mem_desc.c:1359` 族同症状、不同路径。 | `~/V41-UPSTREAM-TRACK-20260922.md:71`（§3 并列四轴表）｜ web 标题与三处关键词（`CUDA_POOL_VMM_MAX_SIZE`/`cuMemAddressReserve`/`GGML_CUDA_NO_VMM`）全部命中 |

---

## 8. NVIDIA NCCL / 平台 / 论坛

| 编号 | 一句话 | 状态 | 对我方的影响 | 出处 |
|---|---|---|---|---|
| **#2213** | `NVIDIA/nccl#2213`：GB10 + 无 GDR + CPU-path 下 `ncclLocalOpAppend` SIGSEGV | 未合入（open） | CPU-path 稳定性问题群与我方 **ring-only** 形态共存性待长稳 | `dsv41-flash-dgxsparks/docs/4DGX-dsv41-上游调研-20260913.md:91`、`~/V41-UPSTREAM-TRIAGE-20260920.md:83` ｜推 |
| **#2353** | 同族（已关） | 已否决（closed） | 同族参照 | `~/V41-UPSTREAM-TRIAGE-20260920.md:83` ｜推 |
| **#2213 备注** | ⚠ **号冲突提示**：本地 `V41-UPSTREAM-TRACK-20260922.md` 等文档中 `#2213` 曾出现在 sglang 语境邻近行，实际归属 = **NVIDIA/nccl**（该文件自带 GitHub 链接） | — | — | `dsv41-flash-dgxsparks/docs/4DGX-dsv41-上游调研-20260913.md:91` |
| NVIDIA 论坛 **#358951** | 员工标记 closed、未认领 NVRM memdesc 路 | 已否决（closed） | 护栏层参照（关 swap / earlyoom / netconsole / KVM / 智能插座） | `~/V41-UPSTREAM-TRACK-20260922.md:84` ｜推 |
| 论坛 **362648** | `nvCheckOkFailedNoLog ... _memdescAllocInternal @ mem_desc.c:1359` 在 **CUDA runtime 之下、无 Python 层异常路径** ⇒ 系统卡死而非 CUDA OOM | 背景 | ★与 #1358 **同签名但无关 flavor** 的确证 | `~/V41-UPSTREAM-TRACK-20260922.md:74` ｜推 |
| 论坛 **383023 楼 76** | GB10 集群、580.178.04、2026-09-21：同一 `mem_desc.c:1359` **连报 13 次** + Xid 31 MMU fault | 背景 | ⇒ 该故障**不限于 NCCL/RoCE** | `~/V41-UPSTREAM-TRACK-20260922.md:75` ｜推 |
| 论坛 **#381911** / **#370309** / **#374742** | 社区帖（voktolom 09-05 等） | 背景 | 社区同硬件对照 | `w6-kit/G1R7VL-COMMUNITY-RERESURVEY-20260907.md:108` ｜**归属未核实** |
| **DGX Spark Known Issues**（无编号，更新 2026-09-10） | 官方口径：`cudaMemGetInfo` **不含可回收内存，不应单独依赖**；改读 `/proc/meminfo` 的 `MemAvailable`/`SwapFree`/`HugePages_*`；调试用 `drop_caches` | 背景 | ★**我方 `eff_idle = MemFree+Cached+SReclaimable−Shmem` 口径与官方建议一致**，可固化为 guard 基线 | `~/V41-UPSTREAM-TRACK-20260922.md:85` ｜推 |
| 社区 **tonyd2wild "Trap 13"** | 长跑/共享机器用**字节** pin KV 而不是 util 分数 | 背景 | 我方已是 `--kv-cache-memory` 字节锁池，一致 | `~/V41-UPSTREAM-TRACK-20260922.md:86` ｜推（标注为搜索摘要级 [S]） |

---

## 9. 外部报告 / 仓库未注（**本地反查缺口**）

| 编号 | 一句话 | 状态 | 对我方的影响 | 出处（本地） | 归属判定 |
|---|---|---|---|---|---|
| **#40217**（旧记法） | 曾以"外部报告（未注仓库）"登记 | — | 本次已核实为 **sglang PR**（§2.1） | `w6-kit/guard/README.md` §16「引用与出处」的 `#40217` 行 | **已纠正** |
| **#34554**（旧记法） | 曾以"外部报告（未注仓库）"登记 | — | 本次已核实为 **sglang PR（closed）**（§2.1） | `w6-kit/guard/README.md` §16「引用与出处」的 `#34554` 行、`w6-kit/guard/BASELINE.md` 的「2026-09-19（深夜终窗）：v11 上线…」节 `v11` 行 | **已纠正** |
| **#5237 / #52645** | 只写编号、**本地从来没有 URL** | — | 本次已核实为 **flashinfer #5237 / vLLM #52645** | `w6-kit/guard/README.md` §16「引用与出处」的 `#5237` 行、`vLLM #52645` 行与节末「登记缺口（如实登记）」注（原文即自述"仓库+编号，未附链接"） | **已纠正** |
| **#29488** | "DSpark #29488" | **不存在** | ★ 本地明文：经 GitHub API 核实**返回 404**，**勿引用** | `~/V41-UPSTREAM-TRACK-20260922.md:14` | **已否决（幽灵号）** |
| **#260** | NVFP4 KV 的"质量前科" | 背景 | NVFP4 KV 不作为项的判据之一 | `V41-COMMUNITY-XREF-20260913.md:66` | **归属未核实** |
| **上游 PR "#7"（口径引用）** | "compact verify +10.5%（上游 PR#7 口径）" | 背景 | U1 门的收益口径 | `~/V41-OPTIMIZATION-MASTER-PLAN-V3-20260919.md:45` | **归属未核实**（疑似内部编号误记） |
| **#49863** | b12x 契约里两个我方没用上的机制（**issue**） | 背景 | b12x 官方化改造输入 | `~/V41-B12X-OFFICIALIZATION-ANALYSIS-20260913.md:74,232` | **归属未核实** |
| **#356 / #358 / #363 / #370 / #364-367** | eugr fork 的 DS4F 稳定性修复（乱码 / acceptance 塌缩）；#364-367 = mHC tile | 未合入（open） | 均不在 main ⇒ fork 血统项 | `w6-kit/G1R7VL-VLLM028-MERGE-FEASIBILITY-20260903.md:18,74,87`、`~/V41-B12X-OFFICIALIZATION-ANALYSIS-20260913.md` | **归属未核实**（"eugr" 是 fork 代号，非仓库名） |

---

## 10. 外部参考树内编号（`w6-kit/reference/GLM-5.3-Flash-NVFP4-1M-KV-4x-DGX-Spark/`）

> 这一棵树是**外部同侪的配方/诊断报告**（非我方生产路径）。其中的编号**自带链接或文件名**，
> 但**不是我方的引用**。登记以备查，归属按该树自述：

| 编号 | 一句话 | 出处 | 归属 |
|---|---|---|---|
| #2655 | XQA MLA decode 核（`mla_sm120.cu`）在 SM120 上**已是 fp8-e4m3-only** | `.../docs/issue-flashinfer-fp8-mla-sm121.md:71` | flashinfer | 
| #3170 | SM121 支持审计：SM120/SM121 共享 compute capability ⇒ 一次 FA2 fp8-MLA port 可覆盖 | `.../docs/issue-flashinfer-fp8-mla-sm121.md:70` | flashinfer |
| #11799 | SM12x cubin 未随 trtllm-gen 发布（`fp8_ds_mla` 路线不能替代） | `.../docs/issue-flashinfer-fp8-mla-sm121.md:72` | TRT-LLM / flashinfer |
| #45317 / #51920 | vLLM 在 SM121 上的 sparse-MLA 后端选择 | `.../docs/issue-flashinfer-fp8-mla-sm121.md:78` | vLLM |
| #35577 | TRITON_MLA fp8 KV request for SM12x（"fp8 = 2× context on consumer Blackwell" 动机） | `.../docs/issue-vllm-nope-fp8-ds-mla.md:56` | vLLM |
| #35356 | 自该 PR 起集成 GPU 的 "free memory" 口径有陷阱 | `.../docs/GB10-KV-MEMORY-LADDER.md:32` | vLLM |
| #51562 / #53635 | **PDL disabled on SM12x**（`is_arch_support_pdl`: `major >= 9` → `major in (9,10)`）+ indexer hardening | `.../docs/DEPLOY-REPORT.md:37` | vLLM |
| #52816 | DFlash2（merged 2026-08-21） | `.../docs/DFLASH2-SPECULATIVE-DECODING.md:22` | vLLM |
| #53906 | stock vLLM 缺 `glm5_next` 直到该 PR 合入 | `.../docs/DEPLOY-REPORT.md:138` | vLLM |
| #52816 / #53869 / PR#52816 | `overlay-dflash2/patch_registry_and_select.py` 内的 `PR#52816`（13 处） | `.../overlay-dflash2/patch_registry_and_select.py` | 未核实 |

---

## 11. 本地反查缺口（**待补出处**）

> 定义：**引用了编号，但本地既无 URL、也无仓库归属说明**；只能靠上下文推断，或完全无法归属。
> 判定方式（只读）：对每个 `#NNNN` 引用点取该行 ±2 行，检查是否含 `sglang|vllm|flashinfer|b12x|deepgemm|llama.cpp|open-gpu-kernel|nvidia|nccl|http|trt|flashmla|cutlass|megakernel|eugr|omlx|safetensors` 任一关键词（**不看大小写**）；全不命中的记为缺口。
> **统计（2026-09-23 复算脚本实测）：1766 个引用点中，417 个（306 个不同 `文件:行` 位置）落在"无仓库关键词"一侧。**
>
> **复算脚本**（把下面整段存成 `/tmp/count_refs.sh`，然后 `bash /tmp/count_refs.sh`；约 2-3 秒跑完。
> 之所以要脚本：原文只有一句 `grep`，**复算不了"±2 行"这一层**，等于留了个没人能复算的数）：
>
> ```bash
> #!/bin/bash
> # REFERENCE.md §0/§11 复算命令（2026-09-23 实测版；只读）
> H=/home/liux***ya
> EXC=(--exclude-dir=.git --exclude-dir='cutlass*' --exclude-dir='s0-dspark-*'
>      --exclude-dir=fi-main --exclude-dir=fi-main2 --exclude-dir=fi-src
>      --exclude-dir=fi016-src --exclude-dir=fi18-wheels --exclude-dir=fi-wheels
>      --exclude-dir=b12x-site --exclude-dir=patches028 --exclude-dir=reference
>      --exclude-dir='g1r[0-9]-build' --exclude-dir='g1r[0-9]-d'
>      --exclude-dir='g1r[0-9]-e' --exclude-dir='g1r[0-9]-ctx')
> KEY='sglang|vllm|flashinfer|b12x|deepgemm|llama\.cpp|open-gpu-kernel|nvidia|nccl|http|trt|flashmla|cutlass|megakernel|eugr|omlx|safetensors'
> HITS=$(grep -rnoE '(PR ?#|#)[0-9]{4,6}' --include='*.sh' --include='*.py' \
>      --include='*.md' --include='*.conf' "${EXC[@]}" \
>      "$H/w6-kit" "$H/dsv41-flash-dgxsparks" "$H"/*.md 2>/dev/null)
> printf '引用点：%s\n'          "$(printf '%s\n' "$HITS" | grep -c .)"
> printf '去重编号数：%s\n'      "$(printf '%s\n' "$HITS" | sed 's/.*#//' | sort -u | wc -l)"
> printf '%s\n' "$HITS" | while IFS=: read -r f n rest; do
>   lo=$(( n > 2 ? n - 2 : 1 ))
>   if ! sed -n "${lo},$((n + 2))p" "$f" | grep -qiE "$KEY"; then echo "缺口 $f:$n"; fi
> done | tee /tmp/gap.txt | grep -c '^缺口'
> printf '缺口位置（去重）：%s\n' "$(sort -u /tmp/gap.txt | wc -l)"
> # §11.2 的"缺口按文件聚合"表：下面两行直接生成
> sed 's/^缺口 //' /tmp/gap.txt | cut -d: -f1 | sort | uniq -c | sort -rn
> ```
>
> 本轮实测值（同一时点）：**引用点 1766 / 去重编号 305 / 缺口引用点 417 / 缺口位置 306**。
> ⚠ 前两个数**含本册与 `GLOSSARY.md` 自身**，两册一编辑就会变，所以只认脚本输出。
> ⚠ "缺口位置"（按 `文件:行` 去重）与"去重编号"（按编号去重）是**两个不同的量**，数值相近是巧合，**不是抄错**。

### 11.1 脚本 / 配置内的缺口（**最高优先，因为没有散文可回查**）

| 位置 | 编号 | 本地唯一上下文 | 状态 |
|---|---|---|---|
| `dsv41-flash-dgxsparks/image-patches/0.2.7/scheduler.py:1172` | `#11910` | `# stream/device coupling (#11910).` | 待补出处（推 sglang） |
| `dsv41-flash-dgxsparks/image-patches/0.2.7/schedule_policy.py:1270` | `#34554` | 见 §2.1（**已核实**） | 已补 |
| `dsv41-flash-dgxsparks/image-patches/0.2.7/schedule_policy.py:209,576,1264` | `#40024` | `# Experimental (upstream #40024, 2026-09-18)` | 已补（§2.1） |
| `dsv41-flash-dgxsparks/image-patches/0.2.7/server_args.py:2743` | `#28511` | `# ReplaySSM spec-verify (Part B of RFC #28511)` | 待补出处（推 sglang RFC） |
| `dsv41-flash-dgxsparks/sglang-overlay*/deepseek_v4_backend.py:3375/3411` | `PR #39187` | `# Port of upstream PR #39187 onto this tree's candidate_masks convention:` | **已补**（§2.1：closed 未合，真正合入的是 #40217） |
| `dsv41-flash-dgxsparks/sglang-overlay*/deepseek_v4_backend.py:3405/3422/3441/3458` | `#40217` | `# DSV41 #40217 native port (minimal form, 2026-09-20)` | **已补**（§2.1） |
| `dsv41-flash-dgxsparks/sglang-overlay*/deepseek_v4_memory_pool.py:607,646`、`deepseek_v4_model.py:283` | `#56457` / `#39095` | `# … per-chunk stranding disease (cf. vLLM #56457 …; SGLang #39095 rows chunking)` | **已补**（§2.1） |
| `dsv41-flash-dgxsparks/start.sh` 的 `image_arg_preflight()` 上方注释块（`#40024 正式版合入` 那句；**不写行号**） | `#40024` | `# "shortest-prefill-first" 只有 0.2.7+ 认（#40024 正式版合入）` | 已补 |
| `dsv41-flash-dgxsparks/start.sh` 的 `SGLANG_OVERLAY_MAP` 内四条注释（`#39482`=`configurer.py` 条、`#34554`=`schedule_policy.py` 条、`#52645`=`deepseekv32_detector.py` 条、`#39123`=FP4 main KV 段首；**不写行号**） | `#39482` / `#34554` / `#52645` / `#39123` | 均有上下文（无 URL） | **已补**（§2.1/§3） |
| `w6-kit/a2_src_grep.sh:2,15`、`a5_commits.sh:3,7`、`bisect30.py:3`、`install_and_probe.sh:2` | `#4380` | `Install flashinfer 0.6.18 (contains #4380)` / `python dispatch 表里的 192（#4380 的核心）` | **已补**（§4） |
| `w6-kit/flashinfer_sparse_l3_002.py:53`、`g1r5-build/flashinfer_sparse.py:56` | `#44577` | `block_size for unpacked KV, larger when packed (#44577)` | 待补出处（推 flashinfer） |
| `w6-kit/guard/flashinfer-arch-guard.sh` 头注的 `#5237` 背景段（两处；**不写行号**——该脚本 2026-09-23 当天仍有注释级改动） | `#5237` | `上游 #5237 只解开了 Python 层的 arch 过滤器…` | **已补**（§4） |
| `w6-kit/guard/guards.conf` 注释体里的 `#5237` 两处（`oom-gate-floor` 行上方的注释块；2026-09-23 注释级改动使原 `:140,144` 位移到 `:164,168`，**改为行名/注释体锚定，不再写行号**） | `#5237` | 同上（注释体） | **已补**（§4） |
| 同脚本头注的「`#5237` **的靶子 moe_utils** 经实测根本不在我方路径上」句（同上，不写行号） | `#5237` 靶子 | `#5237 的靶子 moe_utils 经实测根本不在我方路径上` | 已补 |
| `w6-kit/patches-w4a4/flashinfer_b12x_moe_pooled.py:70` | `#3080` | `Uses b12x_fused_moe from FlashInfer PR #3080` | 待补出处（推 flashinfer） |
| `w6-kit/patches028/`、`w6-kit/s1-patch-20260910/README.md:58` | `#48202`（RFC） | `（堵住 RFC #48202 fixed-shape async 记账坑）` | 待补出处 |
| `w6-kit/l3fix/src/moe_dispatch_0618.py:633` | `#3874` / `#4029` | `# cache (#3874, #4029; docs/design_docs/cute_dsl_kernel_cache.md)` | 待补出处（推 flashinfer） |
| `w6-kit/s0-dspark-diff-20260910/gpu_model_runner_NEW.build.py:437` | `#39324` | `# backends such as TRTLLM (#39324)` | 待补出处 |
| `w6-kit/bisect30.py:3`、`w6-kit/a5_commits.sh:3,7` | `#4380` | 见上 | 已补 |

### 11.2 报告内的缺口（按文件聚合；计数 = 该文件内落在缺口侧的引用点数）

| 文件 | 缺口点数 | 备注 |
|---|---|---|
| `~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md` | 37 | 大量 `#NNNN` 出现在 §1「上游调研吸收：CED 8 项的逐项判决」那张对照表的**同一行**里（表首列是 **v1 报告**的项号 1.1/1.2/1.3/2.1/2.2/3.3 等——**那些是项号，不是本报告的节号**；本报告 §3 之下无任何子节，故 v1 写法的"3.3 节"在本报告里查无此节），行内无仓库词 |
| `~/V41-SGLANG-OPS-ROUND2-20260914.md` | 31 | Lane D cherry-pick 预研表，行内只有编号 |
| `w6-kit/G1R7VL-PROD-PENDING-FIXES-20260907.md` | 29 | W9 时代的 vLLM fork 修复清单 |
| `~/V41-UPSTREAM-TRIAGE-20260920.md` | 24 | 三源调查表；本表已把其中高价值项抽成独立行 |
| **本册 `w6-kit/REFERENCE.md`** | 21 | ★**缺口在自己的登记册里**：§2.2 / §10 / §13 的"只写编号+`｜推`"行（如 `#33403`、`#37188`）。**这是登记口径的固有代价**，不是漏查 |
| **`w6-kit/GLOSSARY.md`** | 15 | 同上（§2/§6 里按代号引编号的行） |
| `~/V41-COMMUNITY-XREF-20260913.md` | 15 | 社区交叉引用表 |
| `~/V41-UPSTREAM-TRACK-20260922.md` | 12 | 本表主体来源 |
| 其余（**92 个文件**） | 合计 **233**（各 1-9） | 见 `/tmp` 采集；逐文件值 = §11 复算脚本最后两行的输出 |

> ⚠ **本表数字是 2026-09-23 复算脚本的实测值**（旧的 34/31/27/24/15/11/9/9/7 是首轮口径，与现在不同：
> 首轮把两册自身也当外部文件漏算了、且 ±2 行窗口/排除表写法有差异）。**要复算就照 §11 的脚本跑**，
> 不要引用本表的具体数字——它们是**时点量**（两册自身也在扫描面内）。

> ★ **本节不补**没有证据的链接。"没有 URL 的不要编 URL"（`w6-kit/guard/README.md` §16「引用与出处」节末的「登记缺口（如实登记）」注 原文；**不写行号**——该节是 2026-09-23 新增，行号仍在动）。

---

## 12. 本次逐条 web 核实清单（**28 条**）

> 复算（= 表内行数，2026-09-23 实测 28）：`awk '/^## 12\./,/^## 13\./' REFERENCE.md | grep -c '^| [0-9]* |'`
> （原写"30 条"，**数不出来**——表里只有 28 行，且其中 `#47187` 只是旁引，故按实测写成 28。）

**打到的页面（全部 `WebFetch`，2026-09-23）**：

| # | 编号 | 仓库 | 核实结论（一句话） |
|---|---|---|---|
| 1 | #1358 | NVIDIA/open-gpu-kernel-modules | open；标题与本地记载逐点吻合（含 `mem_desc.c:1359`、`0x51`、595.84/580.173.02） |
| 2 | #40352 | sgl-project/sglang | **Merged 09-22**；候选块稀疏 + `CandidateIndexer` 协议 + 内存节 |
| 3 | #40444 | sgl-project/sglang | **Open**；"Reclaim the idle device cache on every rank" |
| 4 | #39482 | sgl-project/sglang | **Merged 09-18**；"[Bugfix] Include SM121 in DeepGEMM packed-scale selection" |
| 5 | #40024 | sgl-project/sglang | **Merged 09-18**；"[Scheduler] Add shortest-prefill-first scheduling"；⚠ 页内无 `chunked_req_limit` 字面 |
| 6 | #40217 | sgl-project/sglang | **Merged 09-20**；掩码 16 GiB→128 MiB、峰值 96.01→2.72 GiB |
| 7 | #39187 | sgl-project/sglang | **Closed 未合**（19 commits，CI 全红）——与我方代码注释的"port of"口径需修正 |
| 8 | #39123 | sgl-project/sglang | **Merged 进 `dsv4.1` 分支 09-13**；V41 528 B / V41_FP4 288 B |
| 9 | #39257 | sgl-project/sglang | **Open**；compact ragged slots 由 captured request width 推导 |
| 10 | #34554 | sgl-project/sglang | **Closed**；`--long-prefill-token-threshold`（本地记为"外部报告"⇒ 纠正） |
| 11 | #39095 | sgl-project/sglang | **Merged 09-19**；按 query rows 分块 + 自由内存预算 |
| 12 | #34846 | sgl-project/sglang | **Open**；DSpark draft expert-location dispatch（accept 1.61→3.38） |
| 13 | #38979 | sgl-project/sglang | **Open**；query-dim top-K reuse（−34% prefill TTFT @840K） |
| 14 | #38409 | sgl-project/sglang | **Merged 09-14**；PDL wait before reading DSV4 K cache locations |
| 15 | #56457 | vllm-project/vllm | **Issue, Open**；per-chunk logits buffer 增长（本地口径"vLLM #56457"正确） |
| 16 | #52645 | vllm-project/vllm | **Open**（需要 rebase）；DSML orphan invoke 恢复 |
| 17 | #58068 | vllm-project/vllm | **Open**；fixed-width sparse indexer logits + `VLLM_SPARSE_INDEXER_FIXED_LOGITS_WIDTH` |
| 18 | #45284 | vllm-project/vllm | **Closed / 被 #47187 取代** |
| 19 | #5237 | flashinfer-ai/flashinfer | **Open**；`moe_utils` `supported_major_versions` 含 12 |
| 20 | #4380 | flashinfer-ai/flashinfer | **Merged 08-08**；SM120 DSV4 sparse MLA top-k 192/256 |
| 21 | #4598 | flashinfer-ai/flashinfer | **Issue, Open**；decode autotuner dense axis 未分桶（+82%） |
| 22 | #4603 | flashinfer-ai/flashinfer | **Merged 08-25**；跨层 workspace 共享 68 GiB→1.2 GiB |
| 23 | #4802 | flashinfer-ai/flashinfer | **Merged 09-03**；Refactor Sparse MLA SM120 |
| 24 | #397 | b12x | **Merged 09-21**（本地记 09-19）；prepared capacity vs live rows |
| 25 | #396 | b12x | **Merged 09-21**（本地记 09-19）；页归属 `local-inference-lab/b12x` |
| 26 | #27918 | ggml-org/llama.cpp | **Issue, Open 08-28**；`CUDA_POOL_VMM_MAX_SIZE=1<<35` + 误导性 `NV_ERR_NO_MEMORY` + `GGML_CUDA_NO_VMM=1` |
| 27 | #324 | deepseek-ai/DeepGEMM | **Merged（`nv_dev`）06-24**；sm120/sm121 支持 |
| 28 | #432 | deepseek-ai/DeepGEMM | **Merged 09-10**；Public Release 26/09（Mega Gate / Mega mHC / 默认非确定性） |

**未打网络、仅上下文推断的**：见各表「归属」列标 `推` 的行；**完全无法归属的**见 §13。

---

## 13. 查证失败 / 归属未核实清单（**如实登记，不许猜**）

### 13.1 明确不存在（**勿引用**）

| 编号 | 结论 | 依据 |
|---|---|---|
| **#29488**（记作 "DSpark #29488"） | **不存在**（GitHub API 返回 404） | `~/V41-UPSTREAM-TRACK-20260922.md:14` |

### 13.2 归属未核实（本地上下文不足以定仓库）

| 编号 | 本地出处 | 为什么定不了 |
|---|---|---|
| `#413` | `~/V41-UPSTREAM-TRACK-20260922.md:101` | 同段落写"b12x 本体：… GitHub 09-19～09-22 至少 6 个已合提交"，但 #413 页面未打；**b12x 的 GitHub 组织名本身在本地源码里有 4 个候选** |
| `#407` | `~/V41-UPSTREAM-TRACK-20260922.md:102` | 同上 |
| `#399` | `~/V41-UPSTREAM-TRACK-20260922.md:104,123` | 同上 |
| `#260` | `V41-COMMUNITY-XREF-20260913.md:66` | 行内只有"#260 质量前科"，无仓库词 |
| `#10866` | `~/V41-CED-OPTIMIZATION-REPORT-V2-20260916.md:45` | 只写"挂了一年没合的 Simple-EAGLE"；Simple-EAGLE 属哪个仓库未注 |
| `#49863` | `~/V41-B12X-OFFICIALIZATION-ANALYSIS-20260913.md:74,232` | 只写"上游 issue #49863" |
| `#48202`（RFC） | `w6-kit/s1-patch-20260910/README.md:58` | "fixed-shape async 记账坑"，无仓库 |
| `#374742` / `#370309` / `#381911` | `w6-kit/G1R7VL-COMMUNITY-RERESURVEY-20260907.md:108` | 已写明是 **NVIDIA forums** 主题号（非代码仓 PR），**具体页面未核** |
| `#2655 / #3170 / #11799 / #45317 / #51920 / #35577 / #51562 / #53635 / #52816 / #53906` | §10 各出处 | 在**外部参考树**内自述；其归属按该树 `docs/` 的文件名可推，但**未逐条打网络** |
| `#364-367` / `#356` / `#358` / `#363` / `#370` | `w6-kit/G1R7VL-VLLM028-MERGE-FEASIBILITY-20260903.md`、`~/V41-B12X-OFFICIALIZATION-ANALYSIS-20260913.md` | 前缀是 fork 代号 `eugr`，不是仓库名 |
| `#37610` / `#38941` | `~/V41-OPTIMIZATION-MASTER-PLAN-V3-20260919.md:36` | 本地明文：**"全树 grep 零痕迹的 2 项 MERGED PR"**——连内容都没定位到 |
| `#45861` / `#48047` / `#49486` / `#50004` / `#51725` / `#52823` / `#52502` / `#50416` / `#51318` / `#52492` | `~/V41-CAMPAIGN-PLAN-V2-20260912.md:206`（`#45861`，其余未逐一定位）、`~/V41-COMMUNITY-XREF-20260913.md` 等 | 数字出现于"现役已用融合面盘点"等**列表行**，行内无仓库词 |
| §3 末行的"社区 v0.28/v0.29 特性与 bug 群"（约 40 个号） | `V41-COMMUNITY-XREF-20260913.md:24-67`、`w6-kit/G1R7VL-COMMUNITY-RERESURVEY-20260907.md:100-108` | 大部分行有 "vLLM:" 前缀（可推 vLLM），但**逐条含义未核**，故整批标 `归属未核实（逐条）` |

### 13.3 归属与本地记载**不一致**（本次纠正，**以本表为准**）

| 编号 | 本地旧记法 | 本次核实 |
|---|---|---|
| #40217 | "外部报告（未注仓库）" | **sglang 上游 PR**（merged 09-20） |
| #34554 | "外部报告（未注仓库）" | **sglang 上游 PR**（closed） |
| #39187 | 代码注释 "Port of upstream PR #39187"（暗示已合） | **closed 未合**；真正合入的是 **#40217** |
| #45284 | 未标状态 | **closed / superseded by #47187** |
| #397 / #396 | 本地记"合入 09-19" | web 页显示 **09-21 merged** |

---

## 14. 自检（核验脚本与实测输出）

**纪律**：本表登记的每个 `file:line` 用**只读**命令核一遍（文件存在 + 行号在范围内 + 该行**确实提到**那个编号）。
核验脚本、实测输出、以及首轮实测揪出的**已修正错位清单**，统一登记在
`~/w6-kit/GLOSSARY.md` **§5**（同一脚本同时核两份文件，输出合并统计）。

**复算命令**（脚本正文见 GLOSSARY §5.1；本节数字就是它的输出，改表即变）：

```bash
awk 'BEGIN{p=0} /^```python/{p=1;next} /^```$/{if(p){p=0}} p' ~/w6-kit/GLOSSARY.md > /tmp/refcheck.py
python3 /tmp/refcheck.py                                        # 两册合计
sed 's|^         ("GLOSSARY.md".*|         ]|' /tmp/refcheck.py > /tmp/refcheck-ref-only.py
python3 /tmp/refcheck-ref-only.py                               # 只算本表
```

> ⚠ 2026-09-23 修复轮把指向 **6 个目标文件**（`WINDOW-RUNBOOK.md`、`adr/ADR-004-*.md`、`oom-gate/README.md`、
> `guard/README.md`、`guard/BASELINE.md`、`guard/guards.conf`）的**行号引用改成了节名/行名锚点**
> ⇒ 本表的 `file:line` 引用点数**比首轮少**，少掉的就是那些行号（**这正是修的目标，不是漏检**）。
> **首轮值 134 行 / 164 个 / 134-134 已作废**（且首轮口径与 GLOSSARY §5.1 的脚本对不上，见 GLOSSARY §5.2）。

| 统计（2026-09-23 复跑） | 本表（单册） | 两表合计 |
|---|---|---|
| 含引用的登记行 | **133 行** | **230 条** |
| `file:line` 引用点 | **163 个** | **414 个** |
| 文件不存在 | **0** | **0** |
| 行号超范围 | **0** | **0** |
| 条目级通过 | **133 / 133** | **230 / 230** |

**首轮实测在本表揪出并已修正的 5 处真错**：

| # | 位置 | 原登记 | 实测 | 修正为 |
|---|---|---|---|---|
| 1 | `#40352` | `~/V41-CTX600K-READINESS-20260922.md:244` | **该文件全篇无 `#40352`** | `~/V41-DRIVER-VERIFY-VERDICT-20260922.md:186` + `~/V41-UPSTREAM-TRACK-20260922.md:119` |
| 2 | `#34846` | `~/V41-UPSTREAM-TRIAGE-20260920.md:17` | **该文件全篇无 `#34846`**（:17 是 #39482 行） | `~/r4-ops-work/r9-ops-20260914/evidence/upstream-followup-20260915/UPSTREAM-FOLLOWUP.md:55` |
| 3 | `#39187` | `...V41-SGLANG-OPS-ROUND2-20260914.md:76`、`...CED-OPTIMIZATION-REPORT-V2-20260916.md:315` | :76 是 `#39420` 行（`#39187` 在 :77）；:315 是 `#38979` 行（`#39187` 在 :29/:136） | `:77,123` 与 `:29,136` |
| 4 | `#55569` | `~/V41-UPSTREAM-TRACK-20260922.md:36` | :36 是**空行**（`#55569` 在 :35/:37） | `:37,126` |
| 5 | `#4603` / `#45861` 等 | `...UPSTREAM-TRACK-20260922.md:95-98`、`V41-CAMPAIGN-PLAN-V2-20260912.md:227,206` | 范围起点行不含该号 | `:96,98`；`:206` |

> 另有 **9 个引用点**落在"行内未提该代号"桶（**本册口径**；两册合计 85 = GLOSSARY 76 + 本册 9）——
> 含真·**上下文引用**（引的行是定义块的邻行 / 范围行，非字面量行）与**仪器口径所限**
> （首列是裸序号的行抽不出可比对 token）。**桶 ≠ 错误**：已逐条打印实际行内容人工复核，
> **无一处行号错位**。复算与逐条打印的命令见 GLOSSARY §5.1 末。详见 GLOSSARY §5。

---

*文件路径：`/home/liux***ya/w6-kit/REFERENCE.md`｜配套：`/home/liux***ya/w6-kit/GLOSSARY.md`*
