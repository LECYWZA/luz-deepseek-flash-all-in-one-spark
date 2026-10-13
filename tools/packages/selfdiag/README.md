# selfdiag（P2 自诊断工具包）

> TOOLS31-PACKAGE-PLAN-20261012 §二 P2 承载。整备位=`tools/packages/selfdiag/`；烘焙位=
> `/opt/dsv41/packages/selfdiag/`。**案头/部署双用**：census/gates/sentinel/judge 族=既有
> 在役锚点件的收编副本（判读语义零改律），target_verify_reg.sh=本包新件（V1 登记器）。

## 为什么存在

0.3.1 定型窗（QA31）的判读面由五族件构成：census 画像（V3.1 分窗）、四查门禁（横幅/池/
O12/fail-safe）、boot 慢靴哨、水位/内存探针、E3A judge v3——它们散在 tools/、
~/migrate-assets/bin、logs/<窗>/desk 三处。本包收编为可 md5 锚定、可自检、可随镜像交付
的一处，并补上 QA31 §V1 立线的 target_verify 登记器（免费预测哨兵）。

## 用法

`bin/selfdiag help`；`bin/selfdiag selfcheck`（离线红绿）；`bin/selfdiag tv-reg
--from-log <docker-logs> --boot <靴名> <tsv>`（V1 登记）；`bin/selfdiag run <件名>`
（转发在役件，语义零改）。

## 构成（详=MANIFEST.md5；在役源对表=selfcheck/sources.tsv）

| 族 | 件 | 来源/在役位 |
|---|---|---|
| census/ | census_capture_w3.sh（**V3.1 分窗唯一锚 6e073acd**；TOOL-ANCHORS 规则 7） | tools/（一切窗 census 采集相位唯一锚） |
|  | census_stream.py（解析器；CUDA-port→kv_repack_fp4 正名规则=跨档对比前置律；md5 留痕律=规则 4） | tools/ |
| gates/ | r3-gate-{env,endpoint,assert}-lint.sh（boot 前置键面/端口字面量/断言谱系） | ~/migrate-assets/bin/（QA-GATEHARDEN 20261005 家族） |
|  | r3-gate-banner-contract.sh（键面横幅合同比对器；v2 形=stock 现形） | ~/migrate-assets/bin/ |
|  | verify-governance.sh（治理包自检=「装到错误版本」防御；QA31 §七-8 承接升格件） | ~/migrate-assets/dsv41/kit/guard/（**属地件**：断言同目录 guard 族，包内副本=锚定件非运行位） |
| sentinel/ | boot_sentinel.sh（F-9 慢靴哨；--selfcheck 零集群 mock 快/慢/负控）+boot_sentinel_anchors.tsv（50 键 15767aa6 行=QA31 实测锚 5329.6 带 5100-5420） | tools/（锚表含 CA-5 例值勘误） |
|  | target_verify_reg.sh（**本包新件**；QA31 state/target_verify.tsv 格式逐字承接；健康带 46-49s/>75s 预测红；纯登记非判读） | TOOLS31 §二 P2 承载（REDBAND-ROOTCAUSE 2c9cc93 谱系） |
| probes/ | water_sampler.sh（四机 10s MemAvailable；<4096MB 记 RED 行；**窗路径逐窗改写律**=每窗拷贝改 D=先例） | logs/QA31-20261013/desk/（最近窗实例） |
|  | memsnap.sh（内存取证：meminfo/free/smaps_rollup/docker stats/metrics） | tools/ |
| judge/ | judge_arm.py（**judge v3**：闭包归属法 Σnew-token=prompt−首行 cached 恒等式；QA31 冻结锚 1bf45676）+replay_doc.py（文档重放寻址） | logs/QA31-20261013/desk/（E3A 判读真值源方法件） |

## 排除了什么

- **qmg/qamemguard 看护件不在本包**（归 selfheal 包；qmg 头注红线=测试窗件绝不进生产
  boot 链——常驻化=用户裁定面，QA31 §八-3 呈裁项）。
- **census v3 窗口系（opt1-dev/census_v3_20261004）不收编**：分析侧谱系件，TOOL-ANCHORS
  在锚，收编=双源风险。
- **kernel_census_v2.py 被禁版零收编**（内存失控前科，TOOL-ANCHORS 淘汰栏）。
- **密钥/口令零携带**；water_sampler/memsnap 属 host 面件（容器内无判据，烘焙镜像不带
  自动接线）。
- **无任何自动动作面**：诊断→verdict JSON→人/操作员读 suggest（auto_ok 白名单唯 GID
  heal，归 fabric-net 包）。

## 红线注记

1. **一靴一 census 定律**：census 必须为靴内首相位；多 census=每 census 专用新鲜靴
   （TOOL-ANCHORS 规则 5）。塌形引擎画像禁令+健康形水位盯守（>0.5G/min 弃采）在役。
2. **fail-visible 优先**：慢靴哨横幅+台账不 abort 不自动重启（U1 律）；target_verify
   >75s 只 WARN 登记，处置=呈裁面。
3. **量具 md5 留痕律**：census 产物必须记录所用解析器 md5；judge 读数窗对表 QA31 冻结
   锚（selfcheck F5 UNKNOWN=升级须注记的护栏）。
4. **横幅口径注记**：r3-gate-banner-contract v2 形=stock 面合同（banner28）；当前 50 键
   产线=banner29:4 口径（CODE31 P1-① 修正后；QA31 §七-8 承载）——合同表新增形走该件
   既有「形态注册」面，本包零改。

——TOOLS31 T4 P2 / 2026-10-13 案头整备。
