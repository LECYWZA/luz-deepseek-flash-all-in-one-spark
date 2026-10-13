# R1-FULLGATE-20261012 — R1 同窗成对 D0/D1 全门验证窗 结果呈裁档 · 2026-10-12

> **裁定权=主会话/用户；本档只呈报不落线。** 法源=派单文（R1 回炉第三步）+
> 窗卡 `docs/taskcards/R1-FP4KV-PROBE-WINCARD-20261011.md` §二 G0-G7 冻结稿
> （判读线零事后改；G3 门=本窗 D0 同窗×1.015；G6 出带记录不判红）。
> 窗全程台账=`logs/R1-FULLGATE-20261012/run.log`（窗终判读表 08:2xZ 段在档）。

## 〇、一句话结论

**绿窗呈裁：R1（kv_fp4 feaaadd4+fi_r1 F1/F2 八件）全门验证通过——同窗成对
PR 四档 +18.5~+22.3%（128k 主判档 ×1.2062，门 ×1.015 远超），census G4 repack
族 prefill 相归零（119.2ms/step 面消失）+fork 实例实名在场，fail-safe 首块
PASS×4（四秩 torch.equal）+biteq token/text 10/10，质量四件成对全绿——
转正候选达成全门判读线。** D1-R 红形复现尝试臂：960 量级红形**未复现**
（最差探针 ×0.685；快速重启后首请求 −31.5% 退化→第二请求即恢复健康带）⇒
红形根因=状态依赖进一步坐实但未闭合（快速重启单因子不闭合），产线规避律
两条有实测据导出。产线已完整复原（OUTAGE-END=08:13:05Z，停机 2h00m35s）。

## 一、窗编成与时间线（boot_ledger+run.log 全档）

- 基座（全臂同）=47 键 99e7ec92+overlay o12c1-prod（29 活件，交叉=0）+SPEC6
  六参（--swa-prefix-tails 256）；口 8898；boot 全经 tools/boot-with-slotlock.sh。
- **D0=R1FG-D0**（六参基座净形：R1 键 unset+R1 件不部署=产线净面 92d4c8ad+
  kv_fp4 954cab11，env md5 99e7ec92）；**D1=R1FG-D1**（+DSV41_FP4KV_R1_INKERNEL=1
  +R1 件四机部署 feaaadd4/fi_r1 F1/F2，env md5 8c8c166d=P3/rw2 复现形逐字节）；
  **D1-R=R1FG-D1R**（D1 拆靴后 +159s 快速重启同 env=窗史条件复刻，沉降律豁免
  按臂目的如实注记）。
- 部署链（seg3，rw2 部署段逐相位复用）：落件→adapter-sync --apply+--check 四机
  **4b40a123 全等**（=rw2 部署形逐字节）→容器布局预检 PRECHECK-OK→host 自检
  **49 GREEN/0 RED+12 断言+18 GREEN**（t_r1_equiv/sanity_host/t_difflocal_inject，
  部署面原位）。

| 时点(Z) | 事件 |
|---|---|
| 06:12:18-30 | 开窗：产线 health 200+logs×4 先存+r3-stop 净；面记档 92d4c8ad（=rw2 复原面逐字节）+dev 树 9 件指纹全绿；OUTAGE-START=06:12:30Z |
| 06:12:41-06:53:09 | D0 臂：boot rc=0（7m46s）→biteq R1D0→census 深窗→PR×5→DE→GSM8K n500→accept×2→needle 6/6→64k×2→smoke→拆靴净+memcg 绿 |
| 06:54:12-26 | R1 件部署段：面 4b40a123 四机+PRECHECK-OK+49/12/18 全绿 |
| 06:54:41-07:43:24 | D1 臂：沉降补足 506s→boot rc=0（7m57s）→暖位 4s（JIT 缓存命中）+fail-safe PASS×4→biteq R1D1+compare→census→G4 断言绿→PR×5（G3 过门）→DE→GSM8K→accept→needle→64k×3→smoke→拆靴净 |
| 07:46:00-07:55:08 | D1-R 臂（红形复现尝试）：BOOT-START 距 D1 拆靴 **159s≤180s** 窗史条件复刻→fail-safe PASS×4（判读有效）→64k 探针×2→判定→拆靴净 |
| 07:57:34-08:13:05 | RESTORE：R1 件撤除（面复回 **92d4c8ad** 四机逐字节+fi_r1 残件 0+归档 deploy/fi_r1-deployed-fullgate/）→沉降 600s→产线六参复原 boot rc=0 8899=200→四查+六参直读+printenv+smoke 3/3；**OUTAGE-END=08:13:05Z** |
| 全程 | 看门狗 TRIP=0（4 tag）；memcg 8/8 面绿；WATER-RED=0（四机 min 9586MB）；水位三明治 10 面；沉降律 2/2 过门（D1 600s 补足+RESTORE 600s）+D1-R 豁免段注记；02 机两守护未动 |

## 二、成对实测面（判读主表）

### ① PR ②尺四档×5（arb_med 同窗成对；G3 主门）

| 档 | D0（净形） | D1（R1INK=1） | Δ | ttft D0→D1 |
|---|---|---|---|---|
| 8192 | 4226.8 | 5009.8 | **+18.52%** | 1.94→1.637s |
| 32768 | 4793.9 | 5862.3 | **+22.29%** | 6.837→5.591s |
| 65536 | 4824.3 | 5898.0 | **+22.26%** | 13.586→11.113s |
| **131072（主判档）** | **4689.3** | **5656.1** | **+20.62%（×1.2062）** | 27.953→23.175s |

- G3 门=D0 同窗×1.015=**4759.6** ⇒ D1@128k=5656.1 **远超过门**（W-optC ×1.008
  件线、设计预测带 +3.5~10.3% 均被超出）。
- **出带上 P1 对账（窗卡红退线条款）**：本窗 D0 深窗 repack 暴露=**119.2ms/step**
  （931 调用/16 步独流；P1 案头锚 79.42ms/step=W-optD 深载窗，本窗窗形更深）；
  census 步墙 828.3→679.2ms/step（**−18.0%**）+attn 族内核时间 130.1→115.6ms/step
  （−14.5ms）⇒ −149ms/step 消失面与 E2E 四档 +18.5~22.3% 同量级闭环——
  增益=设计收益（repack 整删）兑现+attn 内核面小改善，非异常面。
- D0 自锚：四档对 TPSPLIT-S3 D0（同 SPEC6 基座锚）−0.0/−0.0/−0.8/−0.2% 全
  IN-BAND=净形自锚成立。

### ② census V3.1 G4（prefill 相深窗逐窗账；一靴一 census 律，量具 6e073acd 零改）

| 面 | D0 深窗（16 步/13.3s） | D1 深窗（16 步/10.9s） |
|---|---|---|
| raw `(anonymous namespace)::repack_fp4_to_v4_kernel` | **931c / 1906.7ms=119.2ms/step 在读** | **0 调用（缺席）** |
| 族 kv_repack_fp4 | 119.182ms/step·60.6c | prefill 相**归零**（残=decode 变体 `_repack_fp4_to_v4_kernel` 38c@4µs=0.0097ms/step） |
| sparse_mla attn 族 | 130.1ms/step·**65.2c** | 115.6ms/step·**27.2c**（切片消失；预测 ~21 带侧，P3 实测 23.7 同带） |
| fork 分发器 fp4 实例 | —（stock 路） | **实名在场**：PBSX=128 288c/1692.9ms+PBSX=256 35c/109.1ms（≈P3 288c/1698.7+35c/107.0 跨窗复现） |

- decode 相 repack 仍在（D1 浅窗 912c/8.1ms=P3 同形 912c/8.4ms）=**非目标面设计
  保持**（断言限定 prefill 相窗口）。P1 自锚脚本（D1）总暴露 0.162ms/step=decode
  残量；D0 侧 P1 脚本跳过（单窗捕获）以逐窗族账 119.2ms/step 承载（同口径族值）。
- 聚合件稀释放注记：D1 聚合 sparse_mla 62.5c/step=浅（24 步 decode 密）+深两窗
  混合稀释；判读以同相深窗逐窗账（上表）为准。

### ③ biteq 位等（salt=woptd-biteq-v1 钉扎；10 项含混合并发集）

- **token/text 位等=10/10 全等（主判据绿）**；top_logprob 面 8/10 差（量级
  3e-6~2e-4）=**P3 窗 A/A 定谳同构跨靴噪声面**（量具缺陷=断言无底噪带，在档
  先例；本窗未新增 A/A 对照，按 P3 定谳律注记）。台账勘正注记在 run.log
  07:15:00Z 段（seg4 一条 `||` 回退消息误植「位等红」文案——判读以本节为准）。

### ④ 质量四件成对

| 件 | D0 | D1 | 判读 |
|---|---|---|---|
| GSM8K n500 | **0.958**（err=0） | **0.966**（err=0） | 两臂过 0.91 下沿门；成对 +0.8pt |
| needle 8k/32k×3 轮 | 6/6 | 6/6 | 绿（前缀缓存形态两臂同形注记=P3 同） |
| accept ×2 | a=2.56(σ.478) b=1.975(σ0) | a=b=2.575(σ0) | 出带下侧=**对照点位记录不判红**（G6 新口径律）；成对 a +0.6% 带内；D0 b 采样量具异常面（<2.0 边际+极差 25.8%）如实记，σ=0×3=S3 世系量具属性挂账同病 |
| DE c1 ②尺 | 81.25 | 77.79 | ×0.957=S3 形不劣化门（≥×0.95）**窄过**（门上 0.6pt）——如实注记呈裁（biteq token/text 位等与 GSM8K 成对绿为值面主证，DE 单量具面待跨窗复核） |
| smoke | 3/3 北京 | 3/3 北京 | 绿 |

### ⑤ 64k 孤立探针（独立量具；与 PR 档不可直比）

| 臂 | 值 | 注 |
|---|---|---|
| D0 净形 | **4755.6**（2 次中位） | P3 D0 量级带 ~4800 一致 |
| D1 | **5896.2**（3 次：5896.2/5770.9/5901.2） | rw2 健康形带 5765-5784 之上 |
| D1-R | run0=**4037.5**（16.23s）/run1=**5791.1**（11.32s），中位 4914.3 | 红形判定见 §三 |

## 三、D1-R 红形复现判定（第三臂；本窗判读产出之二）

- **条件复刻**：D1 拆靴后 **+159s** BOOT-START（≤3min 窗；P3 窗史=当日 6 靴
  连跑的「连续快速重启」因子）+同 env 8c8c166d+R1 件在位+fail-safe PASS×4
  （fork 路径在场=判读有效前提）。
- **结果**：960 量级红形**未复现**——run0=4037.5（vs D1 中位 **−31.5%**）→
  run1=5791.1（**−1.8%**，恢复健康带）；中位 4914.3=×0.833 部分退化带。
- **定谳**：①快速重启单因子对 R1 形有可测负效应（中位 −16.7%）但**不足以
  产生 P3 ×0.2 量级红形**——红形根因不闭合；②**首请求退化带（−31.5%）实测
  且第二请求即恢复**=快速重启后的 warm-up 面，非持续退化。根因仍开放三候选
  收窄：更深窗史（P3 6 靴连跑 vs 本臂单次快速重启）/JIT 冷态（本臂缓存命中
  4s，P3=F1 首建冷态未复刻）/相位轨道。
- **产线规避律（有实测据导出）**：R1 键形①**禁快速重启**（部分退化带 0.833
  实测）；②**首靴 warm 探针门**（首请求 −31.5% 退化面实测，warm 后恢复）。
- 状态依赖证据链汇总：rw2 同形净窗两靴健康（5765/5784）+本窗 D1 沉降 600s
  后健康（5896）+本窗 D1-R 快速重启=部分退化非红形 ⇒ **960 红形=非形固有，
  状态依赖坐实（rw2 ①）+单因子未闭合（本窗）**——红形复现需 P3 全状态重放
  （多靴连跑史+JIT 冷态），列为后续窗建议（rw2 ⑥-2 承接）。

## 四、G0-G7 全门表（窗终判读；run.log 窗终段同文）

| 门 | 判读 | 依据 |
|---|---|---|
| G0 运行期零崩溃 | **绿**（fail-safe 横幅=绿子句满足 PASS×4；128k e2e 已承载；600k 深载未承载=案头缺口注记 P3 同注；四靴零崩溃零 TRIP） | failsafe-banner+prl6+boot_ledger |
| G1 值等价 | **绿**：host 49+12+18 全绿+设备端对拍 fail-safe PASS×4（torch.equal 输出+LSE，双时点复核）+biteq token/text 10/10 | §二③④ |
| G2 needle/qeval | **绿**（两臂 6/6；qeval 案头缺口注记） | bench/needle_r1-3 |
| G3 PR ②尺成对 | **绿（远超门）**：×1.2062@128k vs 门 ×1.015；出带上 P1 对账闭环（−149ms/step 消失面≈repack 119.2+attn 14.5） | §二①② |
| G4 census repack 归零 | **绿**（raw 缺席+族 prefill 相归零+sparse_mla 65.2→27.2c 切片证+fork 实例在场；decode 相=非目标保持；逐窗账承载） | §二② |
| G5 键关位等 | **绿（RESTORE 承载）**：R1/fi_r1 横幅=0×四机+mismatch 0+四查全绿+R1INK=unset×4+面 92d4c8ad 逐字节复回 | §六 |
| G6 accept 口径 | **对照点位**（两臂出带下侧不判红律；成对 a +0.6% 带内；D0 b 量具异常面如实记） | §二④ |
| G7 水位三明治 | **绿**（10 面全档+WATER-RED=0 min 9586MB+memcg 8/8+TRIP=0；census 净吃 717/425MB；scratch=decode 桥 27.4MiB 两臂同值，prefill scratch 构造性不再发生；fork JIT 驻留=容器路径 N/A P3 同病注记，代偿=fork loaded 横幅+JIT 缓存命中 4s） | state/sandwich+memcg+gpu-residency |

**总落点=G0-G5 七门全绿+G6 对照点位+G7 绿 ⇒ 绿窗呈裁（转正候选达成全门判读线）；
判读线零事后改。**

## 五、R1 转正呈裁件数据节（归主会话呈用户）

1. **成对 PR 四档差分**：+18.52/+22.29/+22.26/+20.62%（arb_med ×5 同窗成对；
   128k 主判档 ×1.2062，门 ×1.015；P1 对账闭环=出带上增益与 repack 119.2ms/step
   消失面+attn −14.5ms/step 同量级）。
2. **census G4 归零**：prefill 相 raw repack 核 931c/119.2ms/step→0+族归零+
   sparse_mla 切片消失（65.2→27.2c）+fork 分发器实例实名在场（PBSX128/256，
   跨窗 P3 复现）；decode 相 repack 非目标保持。
3. **biteq token/text 位等 10/10**（top_logprob 8/10=跨靴噪声域注记）+
   **fail-safe 首块 PASS×4**（四秩 torch.equal 输出+LSE；boot 后/census 后双时点）。
4. **质量四件**：GSM8K 0.958→0.966（err=0×2）+needle 6/6×2+accept 成对带内
   （出带=对照点位律）+smoke 3/3×3；DE c1 81.25→77.79（×0.957=S3 形门上窄过，
   单量具面如实注记待跨窗复核）。
5. **红形披露面**：960 红形未复现（D1-R 最差 ×0.685）；根因=状态依赖坐实但
   未闭合（快速重启单因子不足；首请求 −31.5% 退化→第二请求恢复=warm-up 面
   实测）；规避律两条（禁快速重启+首靴 warm 探针门）有实测据。
6. **转正形建议**：`DSV41_FP4KV_R1_INKERNEL=1` 单键 env 增量（47→48 键，
   md5 8c8c166d）+adapter 部署件 kv_fp4.py feaaadd4+fi_r1 F1/F2 八件（部署面
   4b40a123）+容器布局预检律常设；**键关=构造性回退**（G5 四查绿+rw2/P3 两度
   RESTORE 先例+A23-β 进程级 fail-safe 三窗实战零崩溃）。
7. **口径纪律**：孤立探针（4755.6/5896.2/4914.3）与 PR 档（4226.8-5898.0）
   不同量具不可直比；一切成对判读同窗承载（rw2 ⑤注记律复述）。

## 五-2、转正执行注记（R1-PROMO-20261012 窗；2026-10-12 09:49Z 执行代理落）

> 用户裁定转正（本档 §五-6 建议）后形切窗执行结果=**红停窗呈裁，转正未生效**。
> 窗档 `logs/R1-PROMO-20261012/`（run.log 全程台账+窗终判读）。

- **窗程**：2026-10-12 09:00:19-09:48:38Z；OUTAGE 09:01:15→09:48:38Z（47m23s）。
  部署链全绿（八件面 **4b40a123 四机全等**=本窗 D1 部署面逐字节+容器布局预检
  PRECHECK-OK+host 自检 49/12/18 复跑全绿+ENV48 `PROD-R1INK48L2PF6O12C1-spec1.env`
  =47 键逐字+R1INK 恰一键=48 键 **8c8c166d** 在库）；形切 boot rc=0 8899=200
  （沉降 600s 过门）；**断言1 fail-safe 首块 PASS×4 绿**（四秩 torch.equal
  09:17:32-39Z；R1 真路径生效直证）；四查+六参直读（256/125440/池 9,600,000）
  +printenv 四机 R1INK=1+DETINF=unset 全绿。
- **断言2 首靴 warm 探针门（规避律②工程化）=红**：boot 后第一用户请求即 64k
  孤立探针——run0=879.1/run1=938.9/run2=940.1，**中位 938.9 <4500 ⇒ P3 960
  量级红形在「boot 即发请求」面复现**（vs R1 健康带 5896=×0.159；三发持续不
  恢复）。按红线如实停窗呈裁不硬闯，回退执行。
- **通有/特异分离（D0 形 boot 即发补格，DEAUDIT §3.2 缺格闭格）**：47 键回退靴
  同法=3470.0（首请求 −27%）→第二发 **4792.1 恢复健康带** ⇒ 首请求 warm-up
  退化带=**通有面**（D1-R 4037.5→5791.1 同构）；R1 形持续 940 带（−84%）=
  **R1 特异放大**。条件面收窄：沉降 600s 后仍现+JIT 缓存命中（loaded 无
  build）仍现+功能面全绿（纯性能红形）⇒ 根因主候选=**R1 形 fork 路径首请求
  冷启动状态依赖**（boot 内建 warmup 仅 warm fail-safe 小块 rows=96；红形随
  请求历史消失=rw2/FULLGATE 大流量后健康直证）；哨兵 pgmajfault 01 机
  +12,178（冷页面直证）。rw2/FULLGATE「红形未复现」结论勘正=两窗探针均在
  大量请求后，流量前置条件缺位。
- **DE c1 复测点（升级双点位）=未采**：warm 门红停窗优先（GSM8K/DE 流量动作
  终止）；判读线窗前冻结在档（pre 分母 81.25 摆放分离+post 主分母 81.65+
  收案 ≥80.0/真降 <77.6/中间带 −3% 签名报警+spec_accept_length 伴读）——
  后续窗承接，未耗未改。
- **复原目标更替宣告（更正）**：派单预案更替=48 键 R1INK=1+面 4b40a123；
  **实际=更替未生效，复原目标不变=47 键 99e7ec92+954cab11 零 fi_r1（=现役
  产线终态，面 92d4c8ad 四机逐字节复回+R1INK=unset×4+R1/fi_r1 横幅 0+
  smoke 8899 3/3 绿）**；ENV48 在库未服役。规避律两条在役：①禁快速重启；
  ②**首靴 warm 探针门（本窗直证拦截有效——红形转正靴被门当场拦截，若无门
  将带病入役）**。R1 形再呈裁前置=红形根因闭合（首请求冷启动面复现+流量
  warm 后健康带验证）。

## 五-3、转正重试窗 v2 注记（R1-PROMO2-20261012 窗；2026-10-12 10:49Z 执行代理落）

> 前窗 §五-2 红停窗后行为级修复验证+转正重试：**转正规程内加 warm 请求步
> （boot 后第一动作=64k 合成 prefill×2，fresh salt，不接产线流量；产线脚本
> 零改动）**——本窗结果=**全绿收案，转正生效**。窗档 `logs/R1-PROMO2-20261012/`
> （run.log 全程台账+判读线窗前冻结段+窗终判读）。

- **窗程**：2026-10-12 09:59:47-10:49Z；OUTAGE 10:01:31→10:48:49Z（47m18s）。
  部署链前窗同款逐字节（八件面 **4b40a123 四机全等**+容器布局预检
  PRECHECK-OK+host 自检 49/12/18 复跑全绿+部署前面 92d4c8ad 亲核+ENV48
  =48 键 **8c8c166d** 核绿）；沉降 600s 过门；boot R1PROMO2 rc=0 8899=200。
- **断言面（六项全绿）**：①fail-safe 首块 PASS×4+fork loaded×4+JIT 缓存命中；
  ②**warm 请求步（核心新增）=req1 4016.4 tok/s（16.318s，通有首请求退化带）
  →req2 5844.5 tok/s（11.214s，第二发即恢复 R1 健康带 5704-5932）——warm
  修复生效面**；③warm 门探针 ×3=5797.0/5910.1/5784.2 中位 **5797.0 ≥5000 绿**
  （vs 前窗同形无 warm 步=879.1/938.9/940.1 持续 940 带：**940 红形不复现，
  红形=warm 步后消失面坐实**；探针期 pgmajfault 四机 +448/+267/+5/+643=轻面
  vs 前窗红形期 01 机 +12,178）；④四查+六参直读（256/125440/池 9,600,000）
  +printenv 四机 R1INK=1+DETINF=unset；⑤DE c1 双点位=**收案**：pre-GSM8K
  82.06（分母 81.25 摆放分离面）→GSM8K n500（22m30s）acc=0.96 err=0
  →post-GSM8K **82.12 ≥80.0 收案线**（主分母 81.65 ⇒ ×1.0057，高于 D0 暖位
  紧带上沿 81.68；**FULLGATE D1 77.79 降带不复现**；spec_accept_length 伴读
  pre=3.55/post=3.3，无显著低于 D1 带 2.575 面=C1 报警不触发）；⑥smoke 3/3。
- **根因面收窄（呈裁数据）**：同形同面（48 键+4b40a123+沉降 600s+JIT 命中）
  前窗无 warm 步=940 带持续；本窗 64k×2 后健康带——唯一差=warm 请求步 ⇒
  **940 红形=首请求冷启动状态依赖（boot 内建 warmup 仅 rows=96 小块不足）
  获行为级证据支持**；req1=4016=通有首请求 warm-up 带（D0 形 3470/D1-R
  4037.5 同量级）非 R1 特异放大（前窗三发持续 940=特异放大面，本窗第二发
  即恢复=放大面未现）。
- **复原目标更替宣告（本窗生效）**：**此后产线复原目标=48 键
  PROD-R1INK48L2PF6O12C1-spec1.env（8c8c166d）+八件面 4b40a123**（回退件=
  47 键 99e7ec92+954cab11 零 fi_r1；回退链=R1-PROMO 前窗 R.1-R.3 同法：
  kv_fp4 本尊复回+fi_r1 归档撤净+adapter-sync --prune+沉降+47 键 boot）；
  **规避律三条在役**：①禁快速重启（≥600s 沉降律）；②首靴 warm 探针门
  （64k×3 中位 ≥5000）；③**warm 请求步=boot 后第一动作 64k 合成 prefill×2**
  （本窗直证有效）。产线现役=R1 形续役不拆靴（8899=200 终态核在档）。
- **台账勘正两处（如实律）**：sentinel pgmajfault 初版误读 /proc/meminfo
  （字段缺）——warm 步三点 MemAvailable/Cached 在档、pgmajfault 缺档，
  勘正 /proc/vmstat 后 warm 门探针三点补面；printenv 计数器 awk 解析伪红
  勘正复判绿（原始档四行俱绿亲核）。

## 六、双复原义务证据（复原序律=先撤件再产线 boot；一次执行全绿）

- **R1 件撤除**：回滚前面=feaaadd4（预期）→本尊 954cab11 亲核（窗内档
  deploy/kv_fp4_954cab11_pristine.py）落位→fi_r1/+sanity_host 归档
  `deploy/fi_r1-deployed-fullgate/` 后撤净（**残件=0**）→adapter-sync
  --apply --prune+--check 四机面**复回 92d4c8ad 全等**（=部署前产线净面
  逐字节；prune 备份 adapter-archive 目录工具自持）。
- **产线六参复原**（08:05:09-08:12:55Z）：47 键 99e7ec92+overlay o12c1-prod
  +SPEC6 六参经 boot-with-slotlock ARM_TAG=R1FG-RESTORE，rc=0 8899=200；
  四查=200/banner31:4/池 9,600,000/O12 armed 四秩各一+**六参直读
  swa_prefix_tails'=256+swa_tokens=125440（=27136+384×256）**；R1 键横幅=0+
  fi_r1 横幅=0（四机）+MISMATCH=0=R1 件撤除直证；printenv 四机
  R1INK=unset×4+NCCL_PROTO=^LL128×4（基座值）；smoke 8899 正靶 3/3「北京」
  temp0。**OUTAGE-END=2026-10-12T08:13:05Z**（停机段 06:12:30→08:13:05=
  2h00m35s）。

## 七、红线合规声明

判读线零事后改（窗卡 §二冻结稿原文承载；量具 census 6e073acd/bench driver
e31f61d4/biteq 190d1399/pr_ladder6_x5 7253586b/probe ttft64k 全窗零改）；
容器删除前 logs 先存（prod×1 轮+三测试臂×4 俱存 teardown/）；sudo 零使用
口令零接触；~/sglang-main-src 零触碰；看门狗 TRIP=0/WATER-RED=0/memcg 8/8 绿；
02 机两守护未动；git=单文件 add 中文 message（本档一件）；台账勘正一处
（biteq `||` 回退文案误植，07:15:00Z 注记段在档=台账如实律）。

## 八、证据索引（窗根 `logs/R1-FULLGATE-20261012/`）

- run.log（全程台账+窗终 G0-G7 判读表+D1-R 判定+biteq 勘正注记）；
  state/boot_ledger.txt+sandwich.txt+memcg-*.txt+watchdog-*.log
- D0：bench/R1FG-D0/（prl6/gsm8k/accept/needle_r1-3/de_prose_c1/smoke3/
  ttft64k_isolated_probe.json）+census/R1FG-D0-V31_*.json+ biteq/R1FG-D0/
- D1：bench/R1FG-D1/（同构）+census/R1FG-D1-V31_*.json+biteq/R1FG-D1/+
  compare_R1D0_vs_R1D1.json+boot-checks/R1FG-D1-failsafe-banner.txt（PASS×4
  原文）+R1FG-D1-jit-build-lines.txt
- D1-R：bench/R1FG-D1R/ttft64k_isolated_probe.json+boot-checks/
  R1FG-D1R-failsafe-banner.txt
- 部署/复原：deploy/redeploy-fg-{apply,check}.log+fi_r1-container-precheck-fg.log+
  t_r1_equiv/sanity_host/t_difflocal_postdeploy_fg.log+adapter-rollback-fg-{apply,check}.log+
  fi_r1-deployed-fullgate/+state/prod-postcheck.txt+boot-checks/R1FG-RESTORE-boot.log

*窗执行链：本窗执行代理（seg1-seg6 全段+判读+本档；boot 槽独占全程）。*
