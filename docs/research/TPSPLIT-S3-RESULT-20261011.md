# TPSPLIT-S3-RESULT-20261011 — TPSplit 步3 六门全门面复测窗（结果档）

> 窗位：TPSPLIT-S3 复测窗（boot 槽独占；四机 dgxspark01-04）。
> OUTAGE：2026-10-11T23:45:14Z → 2026-10-12T02:37:08Z（2h51m54s；六靴全绿+双复原完）。
> 设计权威（判读线法源，零事后改）：TPSPLIT-XCHECK-20261011.md §五（六门草案）+§六
> （归因隔离）；TPSPLIT-S2-MEASURE-20261011.md S2+S2B 节；TPSPLIT-S2-D1BLOCK-20261011.md
> §六.2（部署面法源）。判读带值=§〇 预登记（第一臂点火前落档）。
> 执行档：logs/TPSPLIT-S3-20261011/（run.log 全纪）。
> 臂编成：D0=47 键 99e7ec92+overlay o12c1-prod（原生直用）+SPEC6 六参净形（重锚）；
> D1=同基座+单键 DSV41_SPARK_PREFILL_TP_SPLIT=1+修复件 6498aa39 四机部署（D1BLOCK
> 裁定 r2；原件 eb53ea12 存档 .bak-s3-eb53ea12 三档互证，窗后逐字节复原 ×2 度核）。
> 口：测量 8898（r3boot）/产线 8899（r3prod）；boot 全经 tools/boot-with-slotlock.sh；
> qmg 全程（floor 6000）；6 靴全经 ≥10min 沉降律；boot 期水位看门狗（零 TRIP）。

---

## 〇、判读线预登记（开窗时点冻结；测量前落档）

（本节为开窗时原文，未改动——带值与法源注记见 git 历史首版。摘要：门2 128k 主判档
预期带 [+3.0,+4.5]%、出带下→回炉 census 对账呈裁不硬转正；门3 dense_b12x ≤0.70 形状
证+AG 增量记账+无新族>0.5%+AR≤2×D0 无 RING_LL；门4 GSM8K≥0.95 硬线+needle 3/3+
accept 成对差分 ≤5% 主判+绝对带 [2.90,3.30] 挂账+σ=0 且出带=T50 红；门5 WATER-RED=0+
D1 boot 低水 ≥D0−512MB；门6 先撤件后 boot+四查+printenv+smoke。）

## 一、窗执行纪要（臂原始数；7 段 6 靴全绿）

| 靴（BOOT 时戳） | 形 | 门断言 | 量具面 |
|---|---|---|---|
| TPS3-D0（23:45:22） | D0 净形（eb53ea12 在役） | 四查绿；gate1=0 init=0（键面无污染）；engaged=0 | census 64k win0 **轻窗**（见 §三.1 度诊）+PR 四档×5+GSM8K n500=**0.962**+accept **2.575×2**+DE c1=**81.65**+needle **3/3**+smoke 3/3 |
| （00:31 部署段） | 6498aa39 四机落位 | 部署断言 ×4 绿；host 自检前 21/21→后 18/21（A1/B1/B2 语义翻红=部署生效直证，S2B 同律） | — |
| TPS3-D1（00:34:44） | D1（+单键+6498aa39） | **boot 门全绿**：gate1=4/gate0=0/init=1/refuse=0/drift=0/seam=3/RED3=0；engaged≥1（**真路径尾横幅**=split 执行直证） | census 64k win0+win1 双**重窗**+PR 四档×5+GSM8K n500=**0.964**+accept **2.5×2**+DE c1=**81.68**+needle **3/3**+smoke 3/3 |
| TPS3-D0C（01:24:16） | D0 净形（撤件后） | 同 D0 绿 | census 64k 补采：win0 **重窗**（15 步×823ms）+win1 轻窗+smoke 3/3 |
| TPS3-D1-128C（01:45:21） | D1 同形 | 同 D1 绿；engage 横幅 layer=2 rows=4096 **width=32768**（=128k 请求第 16 chunk 首engage） | census 128k：win0+win1 双**重窗**（31 步×~840ms 各）+smoke 3/3 |
| TPS3-D0-128C（02:07:07） | D0 净形（二度撤件后） | 同 D0 绿；engaged=0 | census 128k：win0 **重窗**（31 步×847ms；win1 预算门拒=护栏有效）+smoke 3/3 |
| E3S3-RESTORE（02:28:00） | 产线六参新产线形 | 四查绿+门6 面绿（§四） | smoke 3/3（8899 正靶） |

- 部署/撤除链：部署（00:31）→首度撤除（01:22，D0C 净形前提）→二度部署（01:41，
  D1-128C 前提）→二度撤除（02:00，D0-128C 前提）→复原段三度核（02:27:58，cp 幂等
  same ×4）。全程在役面零漂移遗留。
- 全窗：WATER-RED=**0**（min 8186MB）；看门狗零 TRIP；沉降律 6/6 过门（403s/544s/360s/
  203s/363s 各补足至 ≥600s）。

## 二、六门判读表（窗终产出；判读线=§〇 预登记零事后改）

| 门 | 判据（预登记） | 实测 | 判 |
|---|---|---|---|
| **门1 位等** | S2B 在档承载不重测+D1 needle 3/3 哨兵 | S2B 判读表②（on/off 行集法医带内）引用在档；D1 needle 8k/32k/128k=**3/3 PASS**（选择路径健康面；split 真路径执行=engaged 横幅在真路径尾 :247-252 直证） | **绿** |
| **门2 性能** | 128k Δ∈[+3.0,+4.5]%；32k \|Δ\|≤5%；8k \|Δ\|≤5%；64k 首读；DE c1 ≥D0×0.95 | PR ②尺成对（仲裁×5 中位，同窗）：**128k D0=4699.3 → D1=4764.4（Δ=+1.385%）=出带下**（ttft 27.894→27.513s 同向 −1.37%）；32k +0.786% 带内；8k +0.780% 带内；64k −0.282%（首读，见 §三.3 注）；DE c1 81.65→81.68（+0.04%）不劣化 | **主判档出带下→回炉 census 对账呈裁（不硬转正）**；32k/8k/DE 绿 |
| **门3 census** | dense_b12x ≤0.70；AG 增量记账；无新族>0.5%；AR≤2×D0 无 RING_LL | 同窗成对重窗（128k win0×win0，31 步×31 步；engage 面=chunks 16-32≈55% 行）：**dense_b12x=1.025（形状证不复现）**；nccl.AG 78.61→91.99（**+13.38ms/步 +17.0%**）+nccl.RS 81.45→96.65（+15.20 +18.7%）=**合计 +28.6ms/步**；topk_ragged 13.49→9.11（**−32.5%**）+CUtensorMap 25.83→17.25（**−33.2%**）=计算侧 −13.0ms/步；**零新族/零消失族**；nccl.AR 12.41→11.21（**0.903**，calls 3.7=3.7，us_max 56619→15751） | **①形状证缺口（红面如实）+②增量已记账+③绿+④绿（AR 反降，无 RING_LL 签名）**；对账结论见 §三.4 |
| **门4 质量+accept** | GSM8K ≥0.95 硬线；needle 3/3 两臂；accept 成对差分 ≤5% 主判；[2.90,3.30] 挂账；σ=0×2 且出带=T50 红 | GSM8K：D0 **0.962**/D1 **0.964**（n500 err=0）；needle 3/3 两臂；accept：D0 2.575×2 / D1 2.5×2（σ=0×4=量具属性，W-OPTD D0 先例 2.425 σ=0 同域）→**成对差分 2.91% ≤5% 带内**；绝对带双臂外=挂账对照（n500 域口径差在档）；均值带内⇒T50 签名不成立 | **绿**（挂账面如实注记） |
| **门5 水位** | WATER-RED=0；D1 boot 低水 ≥D0−512MB；三明治全档 | 全窗 WATER-RED=**0**（四机 min **8186MB**）；boot 窗低水：D0 **10807MB** / D1 **10629MB**（Δ=−178MB，容差内；分片瞬态 ≤stock 1/4 律=D1 瞬态与 stock 近平，无放大）；三明治 6 面（boot-tail/post-census/steady×两臂）+water-10s 全档 | **绿** |
| **门6 回退** | 先撤件后 boot；四查；swa 直读；SPLIT=unset ×4；smoke | 复原序 ✓（02:00 撤件→02:27:58 三度核 eb53ea12×4 cmp=same→02:28 产线 boot）；**四查绿**（8899=200/banner31=4/池 9,600,000/O12 armed 1+1+1+1）；swa_prefix_tails'=**256**+swa_tokens=**125440**；s2dump_absent=0+split_absent=0+split_initialized=0+MISMATCH=0；printenv 四机 **SPLIT=unset** S2DUMP=unset；smoke 3/3（8899） | **绿**（键关=stock 零耦合直证） |

**窗总判**：六门中门1/门4/门5/门6 全绿；门2 主判档（128k）**出带下**（+1.385%<+3.0%
带下沿）按预登记走 census 对账呈裁路径**不硬转正**；门3 dense 形状证子项**不复现**（红
面如实）。按 T50 先例律（六门全绿+accept 带内⇒转正呈裁），**本窗不满足转正前提——
呈裁主会话**，裁面=§三.4/§五。

## 三、判读明细与法医

### 1. census 窗效度三段链（64k 首拍轻窗→D0C 重窗补采→128k 回炉对）

- 首 D0 臂 census win0=**轻窗**（24 步×~40ms=请求 decode 尾；step_diffs 5.7→49ms 法医；
  kv_repack/sparse_mla 稀失=零 prefill 采集）——**非同形窗，门3 配对失效**。处置=D0C
  补采靴（同法同脚本同 env）win0 重窗 15 步×823ms（与 W-OPTD D0 census win0 同构
  15 步×821ms=跨窗复现性锚）。
- **W3_FIRST_WINDOW_BUDGET_MB 2048→1024 护栏再校准**（D0C/D1-128C/D0-128C 三段预
  登记后使用；非量具改：census_capture_w3.sh md5 **6e073acd** 全窗不变；实测单窗净吃
  791-2366MB 下安全意图〔余量−净吃−flush 峰≥4GiB〕保持，win1 拒门仍有效〔D0-128C
  win1 实拒=护栏工作直证〕）。
- 128k 回炉对=门2 出带下预登记路径的执行（「回炉 census 对账呈裁」）。

### 2. engage 几何定谳（本窗实测锚定 S2B 模型）

- engage 判据实测=**width（增长 context/ratio）≥32768**：64k 单请求（65536 tok，
  4096/chunk×16）仅**末 1 chunk** engage（首 D1 臂 census 期横幅 rows=4096
  width=32768=第 16 chunk 精确吻合）；128k 单请求（32 chunk）**chunks 16-32 共 17
  chunk engage≈55% 行**（D1-128C 横幅 width=32768=第 16 chunk 首engage）。⇒ 与 S2B
  「p96k 尾 9 chunk engage/p64k 全 stock」同模型闭环。
- 「engaged」横幅=one-shot per (ratio,source) 键（spark_prefill_split.py:240-242
  `if key not in tp._logged`）且位于**真路径尾**（gather+publish 后 return True 前，
  :216-252）——横幅在场=split 确已执行（非仅 eligibility 评估）。

### 3. PR 64k 档首读注记

64k 档 Δ=−0.282%：engage 几何下 64k PR 请求仅末 chunk（1/16 行）engage⇒预期效应
≈+0.1-0.2%，实测 −0.28% 在噪声带内——**与 engage 模型一致，非异常**。8k/32k 两档
+0.78% 同幅=靴间小系统差（非 engage 面；键关零耦合下 D1≈D0 的旁证）。

### 4. 门2 出带下的 census 对账结论（呈裁核心）

- **预期收益池在当前栈不复现**：+3-4.5% 预期建基于 dense_b12x 族 −40% 回收模型
  （XCHECK §三⑥/定谳件 A3 口径），但本窗 128k 成对重窗实测 **dense_b12x=61.53→
  63.09（1.025，零降幅）**——engage 确证（55% 行）下该族不变⇒**A3 世系的族归因
  在当前栈（o12c1-prod+现基座）不成立**（或 split-target logits GEMM 不落
  dense_blockscaled 族、或 M 维 1/4 切分对该族时间无削减——两假设窗内不可分，如实
  留案）。
- **实账**：计算侧节省=topk_ragged −32.5%（rank 局部 1/4 行 topk）+CUtensorMap
  −33.2%，合计 −13.0ms/步；集合侧增量 AG +17.0%/RS +18.7% 合计 **+28.6ms/步**
  （engage chunk 折算 ≈52ms/chunk 毛增，AG 单独 ≈24.4ms/chunk——**超出 XCHECK
  ~20.5ms/chunk 上界 ~1.2×**，如实记）；kernel-busy 净 +15.6ms/步（+1.86%）。
  **E2E +1.39% 与 kernel-busy 反号⇒实收益来自重叠/临界路径效应而非 GEMM 时间削减**。
- 呈裁面：split-on（修复件形）=**真实但小幅**的 128k E2E 收益（+1.39%，ttft
  −381ms），质量四件套全绿、位等带内、回退零耦合——但收益量级远低于 +3-4.5%
  预期带且 census 对账显示预期模型的核心回收池不存在。**裁定权归主会话/用户**
  （候选裁面：a) 按实收 +1.39% 重评是否值得转正〔叠加 AG/RS +18% 通信面代价〕；
  b) 先族归因复核〔A3 世系 vs 现栈 census 族映射〕再裁；c) 冻结不转正）。

### 5. accept/质量面注记

- 成对差分 2.91% 带内（主判据绿）；双臂 σ=0×2=metrics 量具属性（W-OPTD D0 2.425
  σ=0 先例同域）——T50 红哨（σ=0 且出带）未触发。绝对带 [2.90,3.30] 双臂外
  =n500 预热域口径差挂账（W-optC 定谳先例 n500 域 2.25-2.55）。
- GSM8K D1 0.964≥D0 0.962（硬线上双绿）；needle/DE/smoke 全绿。

## 四、双复原（RESTORE）证据

1. **修复件撤除**（复原序正确：先撤件再产线 boot——S2B 勘误教训序律）：三度执行
   （01:22 首度/02:00 二度/02:27:58 复原段 cp 幂等核）——四机
   spark_prefill_split.py=**eb53ea12 ×4**（md5+字节级 cmp same；.bak-eb53ea12/
   .bak-s2b-eb53ea12/.bak-s3-eb53ea12 三档互证同指纹）。
2. **产线复原**（E3S3-RESTORE，OUTAGE-END=**2026-10-12T02:37:08Z**，boot rc=0）：
   up8899=**200**；banner31=**4**（E3A 参照形 b50fda1 同值）；池
   **max_total_num_tokens=9600000**；O12 armed **1+1+1+1**（四秩）；
   `swa_prefix_tails': 256` 横幅直读+swa_tokens=**125440**（=27136+384×256）；
   s2dump_absent=0/split_absent=0/split_initialized=0/MISMATCH=0；printenv 四机
   O12SCHED=1 RECV4=4 **SPLIT=unset** S2DUMP=unset；smoke 3/3 北京（8899 正靶）。
   复原段窗水位零 WATER-RED（全窗 min 8186MB）。

## 五、证据索引

| 证据 | 路径 |
|---|---|
| 窗全纪 run.log | `logs/TPSPLIT-S3-20261011/run.log` |
| 六门量具原始件 | `logs/TPSPLIT-S3-20261011/bench/TPS3-D{0,1}/`（prl6/gsm8k/accept_s{1,2}/de/needle/smoke3）+`logs/TPS3-D{0,1}/prl6/`（量具原生档） |
| census 四靴件 | `logs/TPSPLIT-S3-20261011/census/`（TPS3-D0-V31〔轻窗存档〕/TPS3-D1-V31/TPS3-D0C-V31/TPS3-D1-128C-V31/TPS3-D0-128C-V31 各 *_w3w*.census.json+console+聚合） |
| census 成对判读件 | `logs/TPSPLIT-S3-20261011/desk/s3-census-paired.json`+`desk/s3_census_compare.py` |
| 部署/自检面 | `boot-checks/host-selfcheck-{pre,post}-deploy.out`（两次部署段各一对） |
| boot 门断言面 | `boot-checks/TPS3-*-s3-banner.txt`+`-s3-post.txt`（六靴） |
| 拆靴容器日志 | `teardown/TPS3-*/r3boot-*.docker.log`（engaged 横幅真路径证据在档） |
| 水位三明治+采样 | `state/sandwich.txt`+`water-10s.txt`（WATER-RED=0） |
| 复原四查+新产线形 | `state/prod-postcheck.txt`+run.log 复原段 |
| 臂 env | `arms/TPSPLIT-S3-D0-spec1.env`（=产 env 逐字节 99e7ec92）+`arms/TPSPLIT-S3-D1-spec1.env`（+单键 bc48d54f） |
| 量具指纹 | pr_ladder6_x5=7253586b（W-OPTD 逐字节）；census_capture_w3=6e073acd；w1_longctx_bench=e31f61d4；gsm8k_dsv41=2e964be9；water_sampler/watchdog=S2B 骨架仅 D 路径换 S3 |
| 设计权威（只读） | TPSPLIT-XCHECK §五/§六；TPSPLIT-S2-MEASURE S2+S2B 节；TPSPLIT-S2-D1BLOCK §六.2 |

——TPSPLIT-S3 复测窗终：六门判读表在 §二；门2 主判档出带下+门3 形状证缺口=呈裁面
（§三.4）；双复原证据在 §四；判读线零事后改（§〇 预登记+git 首版可溯）；裁定权归
主会话/用户。
