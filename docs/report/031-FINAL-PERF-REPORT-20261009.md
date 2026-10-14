# LuZ-0.3.1 终版性能测试报告（三模型全量）— v2 定稿

> 状态：**v2 定稿（2026-10-12 CODE31 窗升档；v1=198aa50 DRAFT 承接，原节保留，
> 增量章按「T1 组合窗红窗+W5 单独转正+split 留库+chunk8192 判负」最新战况填写）**。
> **定型形性能读数=QA31 回填位**（§三-B/§十；50 键 W5 单独转正形未跑性能靴，
> 本报告不预填）。
> 法源：ACHIEVEMENT-031-FINAL.md（RATIFY-CG 转正窗收口档，两形定板+四线终表）
> +LL128-ADOPT 读数臂+RING4096-R2 判负门档+F6' 认证门+KV-LIFE-20261009 终报
> （logs/KV-LIFE-20261009/READINGS.md）+E3A-DOSE-RECALL-RESULT-20261011
> +COMBO-STACK-RESULT-20261012+用户裁定档（commit fd5c7e5）。口径：sparkDash（上游=MiaAI-Lab/sparkDash，github.com/MiaAI-Lab/sparkDash；本仓工具=tools/bench/sd_bench.py 九项定义对表复刻）——口径正典档=docs/registry/BENCHMARK-SOURCE.md。原口径行：sparkDash
> ②尺 c1 5 发中位（②/③同靴比=1.000，仪器层一致已证）；0731 目标 60/104、VL
> 目标 50/90（用户钦定 vLLM 0.4.5 时代锚）。**数字源=窗档锚点引注制（本报告
> 不复制原始数，逐数带出处）**。

## 一、版本定板总览

| 模型 | 形名 | env md5 | KV 池 | 图态 | 部署位 |
|---|---|---|---|---|---|
| V4.1 | R1STDLL128（v1 时点产线在役） | 2de48070…（43 键） | 9,600,000 | FULL_AND_PIECEWISE 产线 | r3prod 四机 8899 |
| **V4.1（0.3.1 定型形）** | **PROD 50 键**（§一-B） | 15767aa6（48 键 8c8c166d 逐字+FP8/TG 两键） | 9,600,000 | 同上 | r3prod 四机 8899 |
| 0731 | **STD0731-CG-R1** | bdfd95906b22ffe9296fa965ecd907be（24 键） | 7,026,688 | decode 8 图 bs1-8 | FORM-REGISTRY 登记 |
| VL | **STDVL-K6CG-R1** | 17a9a199acc5d32ff96a29adace5521b（19 键） | 4,800,000 | stock 梯 10 图 | FORM-REGISTRY 登记 |

决定性杠杆=**decode-CG 解锁**（0731/VL 同形成对 +79.0%/+73.0%，步墙 75→50ms；0731 解锁组合
=pin7103136+mf 0.89+--cuda-graph-max-bs-decode 8，sustained 6433M≥6144 执法绿；VL=k6 冻结
线全过+decode-CG +79.7%/+73.6%，两模型比率一致=机理同源）。

## 一-B、0.3.1 定型形章（v2 增；战况=COMBO-STACK-RESULT-20261012 + 裁定 fd5c7e5）

- **定型形**：**50 键**（`arms/COMBO-C0-spec1.env`，md5 15767aa6=现役 48 键
  PROD-R1INK48L2PF6O12C1（8c8c166d）逐字+`DSV41_PREFILL_SP_FP8=1`+
  `DSV41_PREFILL_SP_TAIL_GATHER=1`）+**SPEC6 六参**+**W5 件 prefill_sp.py
  32cf9abf**（2026-10-13 00:02:23Z 转正窗换入产线 adapter 面）+R1 八件面
  4b40a123（kv_fp4 feaaadd4+fi_r1/ 六件；R1-PROMO2/FULLGATE 部署链四机全等）
  +产线 overlay o12c1-prod（29 活件，scheduler 5b6fe2a3）。**回退两级**：
  50→48 键（8c8c166d+两键 unset=W5 件键关语义=0497e566 等价〔FP8_MOE 口径注记
  见 FORM-REGISTRY〕）→47 键（99e7ec92）。
- **T1 组合窗战况**（COMBO-STACK-RESULT-20261012：三臂 C0/C1/C2 七门）——
  **红窗回退现役 48 键形**：门 1 chunk 主判红（C1/C0 四档 8k −2.29 出带/32k
  −0.98 带内/64k −1.18/128k −1.26 远低于 ≥+5%/≥+3% 冻结线+DE c1 81.38<81.5；
  归因注记=通信面 census 排除+GEMM tiling 变体族/重叠结构主候选+社区基座差
  实锤〔knapcio A/B 链非同具形不可平移〕）⇒ **chunk8192 判负不进形**（0.3.2
  观察位；16384 永禁维持）；门 2 split 差分 128k +2.41% 出带正⇒**呈裁后用户
  裁定 split 留库不转正**（6498aa39 在库；C2/C1 过线系 chunk8192 交互项参照系
  已红，对目标形直接差分缺位；复活位=定型微调/0.3.2 单臂差分）；门 3 质量
  四件主体绿（GSM8K 0.976/0.966/0.972×三臂+needle 3/3×三臂+qeval 71/75×三臂
  逐题 75/75 全等双直证）+**accept 挂账复测面红**（C1/C0 成对 2.55 vs
  2.925=−12.8% 出带⇒挂账不收口+σ=0 塌陷签名红面记档〔cumulative gauge 空闲
  采样动力学归因注记〕）；门 4 census 绿（C0=W5-D3 形精确复现+C1 形状保持
  〔u8 双流 17 层×8 chunk+字节比 1/1.94〕+repack 族归零+C1 新族 5 个俱 tiling
  几何变体+C2 签名=RoCE 自研核集合面）；门 5 水位绿；门 6 sparkDash 配对位
  （C1 128k 5806.0 对 knapcio PR#11 5462.13=+6.3% 名义）；门 7 回退承载一体
  （双复原直证+产线 boot 8899 四查六参全绿+W5 横幅撤净直证）。
- **组合账对账**（T1 窗数据）：C0 步墙 648.6ms/step 对 866 基线 **−25.1%**、
  对 677 目标 −4.2% 兑现带内（COMBO-STACK-RESULT §组合账）——**该读数为
  T1 组合形（50 键 SPEC7 系）靴；W5 单独转正 50 键 SPEC6 形的性能读数=QA31
  承接案 A' 回填位，本报告不预填**。
- **双复原直证**：split 件 eb53ea12 三度核+W5 件 0497e566 复回+面 4b40a123×4
  复回+产线 8899 四查六参全绿+W5 横幅=0 撤净+printenv R1INK=1×4 FP8/TG/SPLIT
  unset×4+warm 步 4023.8→5937.5+smoke 正靶 3/3+02 机两守护未动（OUTAGE
  16:22:01→19:33:00Z 3h10m59s）。

## 二、0.3.1 四线达成度（终表，法源 ACHIEVEMENT-031-FINAL §一）

| 面 | 目标 | 读数（定板形源） | 认证复跑（同形） | 复跑 Δ | 达成 |
|---|---|---|---|---|---|
| 0731 prose | 60 | **81.22** | 81.07 | −0.18% 带内 | **135%** |
| 0731 code | 104 | **123.21** | 123.22 | +0.01% 带内 | **118%** |
| VL prose | 50 | **63.16** | 63.16 | +0.00% 同值 | **126%** |
| VL code | 90 | **112.93** | 113.21 | +0.25% 带内 | **125%** |

## 三、V4.1 现役线

- **A 面（v1 时点=43 键 R1STDLL128 读数，保留原值）**：
  - **C1 ②尺 sparkDash=79.32**（78.64-79.41 极差 1.0%；②尺首测入册，对保底 82 差
    −0.85%=既有 C1 缺口面，属 0.3.2 面）。
  - **PR 128k=4666.6**（LL128 中性确认 −0.8% 带内；对 5100 差 −8.5%——knapcio
    定谳后真文本等值差 −2.9~−6.3%，M2 主路径 CG+β+O12≈5596 属 0.3.2）。
  - **agg600k=3039.0-3056.1**（LL128/RING4096 两窗带内）；**c16=14.53**（双红线绿）。
  - LL128 三键协议行全套实证（P2b Socket 回落=0/P5 NCCL WARN=0×4 机/RoCEnante
    max_size=262144 联动）；水位省存四机聚合 +2856~+3182MB。
- **B 面（v2 增：键面演进读数链，性能面=QA31 回填位）**：43 键（2de48070）→
  45（34977bf0）→47（99e7ec92，O12 C1-PROD-PROMO 01:34Z 绿起）→48
  （8c8c166d，R1-PROMO2/FULLGATE，R1 in-kernel 转正在役：t_r1_equiv 49 GREEN
  四机+面 4b40a123）→**50（15767aa6，W5 单独转正）**。逐形 PR/agg/census 读数
  锚：47 键=TOOL-ANCHORS:48 行；48 键=R1-FULLGATE-RESULT-20261012；50 键=
  **QA31 §四/§五 承接位（本报告不预填）**。

## 四、质量面

- **GSM8K**：0731 成对 on 0.94/off 0.925 双落 0.93±0.02=用户裁定基线带内（**CG 无罪**定性）；
  VL 0.945 双杠绿（硬 ≥0.90+带 0.93±0.04）；V4.1 cert 线 0.985。
- **needle**：0731/VL 8k/32k/64k/73k 四档 PASS；V4.1 600k 3/3。
- **accept**：0771 冷读 3.34-3.44 零 1.00 塌陷（E1 门链首验）；VL /metrics 3.2；
  **0.3.1 尾态注记（v2）**：COMBO 门 3 accept 挂账复测面红（C1/C0 成对 2.55 vs
  2.925=−12.8% 出带，σ=0 塌陷签名；归因注记=cumulative gauge 空闲采样动力学；
  W5 窗同形曾判绿口径差如实呈报）——**挂账开放，0.3.2 decode 活跃期口径复测**
  （COMBO-STACK-RESULT 门 3 呈裁行）。
- 位等：VL k6 冻结线位等 True；compact 首调 bit-identical；R1/W5 位等面=R1
  fail-safe 双跑 PASS（49 GREEN 链）+W5 三重对拍 MXFP8 byte AG ON（COMBO 门 4
  census C0 形精确复现）。

## 五、护栏面（600k/c16 双红线）

- 两形 admission 护栏绿：超限请求（131072 est/596k est）均 400 干净拒绝（limit 48,828 tok 在役），
  零 OOM 零楔死。
- **CG×长 prefill 交互面首证绿**：48,469 实 tok 受理请求分块 prefill+needle 检索正确（两形同绿）。
- 0731 运行域边缘态如实注记（head 稳态 ~6.2-6.6G 对 6G abort 线余量 ~200-600M；长档电池 host
  滞留 ~600-700MB 必穿 6000，看护拆线排水零损失=设计动作）⇒ §九 admission 呈裁件。VL 无同构
  风险（min 19453M，余 13.4G）。

## 六、KV 缓存生命周期专项（8~512k 文学作品填充→全量召回→LRU 逐出）【v2 填充】

法源=logs/KV-LIFE-20261009/READINGS.md（终报）+E3A-DOSE-RECALL-RESULT-20261011
（剂量-召回）+QA31 §四/§五 承接位（50 键定型形 KV 面=QA31 回填）。

- **① 渐进填充（8~512k 文学文本）**：V4.1 r1 形梯 9.9k→277.9k 全 PASS（16 发）
  +512k 档「靴内早窗」救回（X5121 单发 565,393 tok PASS，184.3s）；512k 文学档
  populated-tree 两崩（INCIDENT-1/2）重试取消——证据=早窗+596k word-bag PASS
  （TTFT 475.2s）。VL（CG 形）梯 8k/16k/32k/41k×2 全 PASS；44k+ 档被 dense T×L
  admission 硬墙截断（limit 48,828）⇒标准靴实际可达 8~48.8k，256k/512k 需
  CTX_CAP 600000 特形靴。填充进度：VL 至 **4.76M/4.8M=99.2%**（「充分填充」
  达成）；V4.1 最高 17.5%（受两崩制约）。
- **② 全量召回（填满前最旧可召回）**：判读真值源=TTFT 差分+调度器日志双源
  （`usage.cached_tokens` API 恒 0 已知缺陷不采）。**VL 绿**：10k 级热/冷=
  0.073（TTFT 省 92.7%，引擎命中 9728/9916=98.1%），「合理区间」实测带
  0.07-0.10；**V4.1 r1 形红**：全尺寸热=冷（radix 前缀复用惰性）——异常而非
  标定（SWA cap 模式交互嫌疑面，未定谳）。**E3A 剂量-召回（v2 补）**：
  `--swa-prefix-tails` 256 档召回大幅恢复坐实（cp12 278k 主档 99.95% 全命中、
  cp30 压力位 3/3 全命中 98.09-99.95%；64 档同位基线全 0⇒剂量-召回单调恢复）；
  384 档水位红除名（qmg 6000 硬门拆线）；**256 档已转正在役**（E3A-PROMO-20261011
  窗，六参产线形；COMMUNITY-DELTA-20261012 §对照表「E3-A N=256 在役」）。
- **③ LRU 逐出（填满后动态剔除最旧）**：VL 满池逐出链五步全证（自动剔旧叶→
  miss 重入树→540k 压力相→刷新存活 98.1% vs 未刷新同龄 0 命中对照→页精确
  LRU 干净对照）——**③ 绿**；M0193 46k 最新档 miss=开放异常（OPEN-29）。
- **SWA 分型**：V4.1 r1=cap 模式（swa 51,712/tails 64）；0731/VL=ratio 0.1。
  E3A 剂量面（tails 64→125,440 池档〔Δ+1.64G 实测〕→174,592〔+2.74G〕，
  max_total_num_tokens 9.6M 不缩；水位紧机 13,928→10,960→9,613MB）。
- **256k-512k 特形靴档位**：VL 需 CTX_CAP 600000 特形靴（KV-LIFE 弃尾）；
  V4.1 512k=早窗+word-bag 双证据。**QA31 承接位**：50 键定型形（W5 转正+
  chunk8192 缺席）KV 剂量面/满载位复测=QA31 §四/§五（满载位=E3A 判据③ 数据
  缺位〔9.6M 池 GB10 UMA 物理不可满载〕0.3.2 池项）。

## 七、水位形态（三模型）

- V4.1：ring rx 8192→4096 后新稳态；F3 缺额=NIC 页池良性代价，12.95G 新常态口径
  （E3A 后注：256 档尾预算下紧机 10,960MB、384 档 9,613MB=水位红除名依据）。
- 0731：池 7,026,688（ring4096 回升 +332k tokens 分账 +2.64G KV）；CG 形边缘态见 §五。
- VL：floor 6144 余 15G，无水位约束。

## 八、集群变更账（本版本周期，全部在役；v1 七项+10-09 后增量四项）

1. **ring rx 8192→4096**（lutune d003736d+guard fa5e536b 各 1 行；判负门零触发）。
2. **fabric 自愈体系四件**：guard v2（F-G1..G10+Q1-Q7+熔断）/fabric-gid-heal.sh（四前置+Tier1/2）/
   fabric-restore-gate.sh（Phase1 只告警）/topology.json 期望态；netplan canonical 16 条/机。
3. **B2 GID 断言块**（r3-boot-arm.sh a85c0c68，16 口 idx3 断言，首战 4/4）。
4. **macgw /30 迁专口**（macgw0 macvlan bridge；MPI wireup 恢复绿=INCIDENT2218 遗留①闭）。
5. **LL128 三键采纳**（产线 43 键形；fail-closed gate 18/18）。
6. **守卫治理**：审计 A-1..A-20 全批（频率面零改动=用户裁定）+GUARD-MATRIX 总档+16 项修复
   实施卡（801d279，转段第一批）。
7. banner 契约 30 门（cert_head 新门）。
8. **（v2 增）O12 主机间隙三键产线化**：SCHED_ASYNC=1+RECV_INTERVAL=4 采纳（47 键
   99e7ec92 起）+产线 overlay o12c1-prod 29 件（scheduler 5b6fe2a3；C1-PROD-PROMO
   20261011 形切窗绿起；ALLOC_KEEPALIVE 未采=ring 2 缺省逐位 stock）。
9. **（v2 增）R1 fp4-KV in-kernel 八件**：`DSV41_FP4KV_R1_INKERNEL=1`（48 键
   8c8c166d 起）+fi_r1/ JIT 壳六件+kv_fp4.py R1 面（面 4b40a123 四机全等；
   t_r1_equiv 49 GREEN+sanity 12 部署链复跑锚；fail-safe 双跑+永久回退律）。
10. **（v2 增）W5 两键单独转正**：`DSV41_PREFILL_SP_FP8=1`+`DSV41_PREFILL_SP_TAIL_GATHER=1`
    （50 键 15767aa6）+W5 件 32cf9abf（2026-10-13 00:02Z 换入；AG-in MXFP8 字节
    AG〔~1/1.94 wire，17/21 层〕+出口尾行直聚〔~15× wire 减〕两脸；三重对拍
    fail-safe；chunk8192 判负不随包、split 留库不转正=同裁定档 fd5c7e5）。
11. **（v2 增）E3A 剂量参数族**：`--swa-prefix-tails` 64→**256（转正在役，六参
    产线形，E3A-PROMO-20261011）**/384（水位红除名）三档剂量账入档（SWA 池
    51,712/125,440/174,592 精确对表，max_total_num_tokens 9.6M 不缩；E3A-DOSE-
    RECALL-RESULT §二/§六+COMMUNITY-DELTA-20261012 §对照表）。

## 九、呈裁件与挂账汇总（v2 更新）

- **admission 收紧**：48,828→40,960 tok（=DSV41_TL_BUDGET_ELEMS 1.678e8；⚠X1 律冲突⇒纯呈裁，
  未批不动；配套一靴决策树 min≥6500 收案/<6000 转 host 池治理）。
- **0.3.2 池移交清单（v2 更新）**：①A23-β TBO/bypass 观察位；②CG-β 停车（t4-patch
  形 0847a7cd 留库）；③E3A 满载位数据缺位（9.6M 池 UMA 物理不可满载；256 档
  已转正收案）；④chunk8192 观察位（判负定谳=社区 A/B 链非同具形不可平移）；⑤split
  复活位（6498aa39 在库；复活条件=定型微调/单臂差分）；⑥accept 挂账 decode
  活跃期口径复测（COMBO 门 3）；⑦LL128-VL 根因（两靴预算）；⑧0731 floor
  6144 vs 9216 重估；⑨gate --live 修复（已知 P1 在档）；⑩c16 driver
  KeyError（转段量具修复）；⑪CODE31 注释修订批次 CA-1..CA-5+哨兵计数修正
  （CODE31-COMMENT-AUDIT §一）；⑫boot_sentinel 锚表定型三形回填
  （CODE31-WHITEBOX-MATRIX W-1）。
- 携入包（0.3.2 择入）：0731 FS2+FENCE / VL compact+align（双窗增验=携入零代价，c1 带内）。
- 挂账：TOOL-ANCHORS §十八重评；6 项对角 GID 目标（B1 扩展）；MD5SUMS 债；
  KV-LIFE OPEN-29（M0193 46k miss）；V4.1 radix 惰性根因（SWA 交互嫌疑面）。

## 十、结论

0.3.1 交付语义（用户定名）=两兼容模型（0731/VL）可用化交付：**四线 135/118/126/125%
全破，质量面带内，护栏面绿，两形定板入册**；V4.1 产线经 43→45→47→48→**50 键**
演进链定型（R1 in-kernel+W5 两键+O12+LL128 全采纳，chunk8192 判负/split 留库），
**50 键定型形性能读数=QA31 承接案 A'（50 键 SPEC6）回填后本报告 v2 即闭环**。
KV 专项章（§六）已按 KV-LIFE 终报+E3A 剂量-召回填充。随即转入 bug 修复/可用性
提升阶段（第一批=守卫修复窗 16 项+admission 呈裁件+0.3.2 池清单⑫项）。

——主会话 v1 / 2026-10-09；CODE31 T3 文档窗升 v2 / 2026-10-12（数字源=各窗验收档
锚点引注；QA31 回填位三处明标：§一-B 组合账、§三-B 50 键读数、§六 QA31 承接位）。
