# FL6-FIX-RESULT-20261013 — FL6 修复验证窗·结果档（部分绿呈裁位）

- **窗标识**：FL6-FIX-20261013（窗档 `logs/FL6-FIX-20261013/`；run.log=全程流水；判读线窗前冻结零事后改）
- **窗卡**：`docs/taskcards/FL6-FIX-WINCARD-20261013.md`（含 3b 满池档扩展+判读线 ⑦⑧+满池段水位新线）
- **修复件**：`dev/fl6-recall/fl6_recall.py`（B1 完成退休+A match 回缩；主会话亲核验收 6dd2644；桌面双臂 6/6+对照 0% 复现，本窗预检复跑再证）
- **OUTAGE**：2026-10-13T10:02:15Z 起 → 收窗时点见 §八（产线 50 键原形复原在役）
- **窗判读总词**：**部分绿呈裁位（④处置位）**——QA31 cp30 红位（0/3 全 miss）**未复现**：cp30 复测引擎源 **3/3 全命中锚位逐值**（cached 9,728/35,072/277,760 与 E3A-T256 绿锚完全同值）；严格冻结双门（每档 ≥98%+TTFT 比 <0.05）= **2/3**：L0001（8k 最小档）引擎 98.09% ✓ 但 TTFT 比 0.056 ≥0.05 边际出线，出线纯分母面（本窗 fill_orig 5.289s 比锚 11.104s 快 2.1 倍；replay 分子 0.296s 比锚 0.306s 更快=锚位等同）；满池档（99.96% 池水位）同型读数；回归面/水位面/部署面全绿。**转正与否=主会话呈裁**（呈裁件=本档 §五+§九 runbook）；产线已按窗卡 §三.5 缺省复原目标复原 50 键原形+原指纹 2c4baad3。

---

## 一、执行序实录（boot 槽串行；规避律④ 逐靴 1800s+warm 64k×4）

| 段 | 时点（UTC） | 内容 | 结果 |
|---|---|---|---|
| 预检 | 10:01 前案头 | 双臂复跑：修复臂 6/6 绿+对照臂 test_10 红位复现（bug 判别力直证） | 绿 |
| S0+S1 | 10:01:55–10:02:15 | 判读线窗前冻结（run.log 10:02Z 段）+产线 logs 先存→r3-stop 拆净→**OUTAGE-START=10:02:15Z** | 绿 |
| S2 部署 v1 | 10:02:41 | ENV51 创建（50 键逐字+第 51 键 DSV41_FL6_RECALL_FIX=1；md5 2ac74586）+fl6_recall.py 入位（b87cbb5e）+sitecustomize elif 两支接线（2c4baad3→d5dc42a4）+adapter-sync 四机全等 | 绿 |
| S3 靴1 | 10:32:17–10:42:45 | **FL6FIXA1**（ENV51）：boot rc=0+8898=200+target_verify 45.10s+warm 门 6091.4+四查全套绿；**[fl6_recall] 横幅=0 行** → fail-closed 红停位命中 | **红停（部署面）** |
| S2 部署 v2 | 10:43:44–10:44:41 | 根因=EngramFinder.find_spec **白名单漏加**两模块（sitecustomize:132 评审 F-1 注释「漏加则本分支永不触发」=elif 死代码=门控休眠）；修正=白名单补两行（d5dc42a4→**55b1e412**）+四机同步+门函数管线子 shell 假绿 bug 同步修正 | 绿（FL6FIXA1 拆靴净 OK） |
| S3 靴2 | 11:13:47–11:23:44 | **FL6FIXA2**（ENV51）：boot rc=0+8898=200+target_verify 45.22s（健康带）；**[fl6_recall] 横幅门真绿：四容器各 tree_core/swa patched=2 行+零漂移拒起=门控生效直证**（boot-checks/FL6FIXA2-fl6banner.txt+docker logs 原始行）；warm 64k×4=4107→6131→6121→6064，**warm 门=6113.6**；四查全套（banner29:4+池 9,600,000+O12 四秩+R1 fail-safe PASS×4+MISMATCH=0+chunk 4096）+E3A 横幅三断言绿（prefix_tails=256；swa_tokens=125,440=27,136+384×256） | 绿 |
| S4 FL6 复测 | 11:24–11:39 | flush 回池自证绿→fill12（11.16% 带）→recall12（3 热+6 冷）→fill30（**27.61%**=QA31 红位同载态带）→recall30（3 热+6 冷）+judge v3+原始件 | 见 §二/§三 |
| S5 满池档 | 11:57–12:32 | 降线（qmg 6000→2500+water floor 6000→1500=窗卡 §五 授权）→fill100 至 docs 耗尽 **89.06%**（plan 语料 2 文档 span 无效 UTF-8 字节=FAIL×2 如实注记）→cp100 召回（@89.06%）→evict +988,685 毛灌至 99.35% | 见 §四 |
| S5b 修正续段 | 12:31–12:32 | 越界灌 S0003-5 净 839,334 至 **99.96% 池水位**（avail 3,584；跨 100% 触发真 LRU 剔除）→cp101 满池召回 3 档→+10% 追加（毛 988,685 重发）→probe 四发 | 见 §四 |
| S6 回归面 | 12:40–12:51 | flush 回池净→线复原（qmg/water 回 6000）→GSM8K n200→needle 3 发→水位四查→warm 门复检→memcg 终面 | 全绿（§六） |
| S7 窗终处置 | 12:55 起 | 裁定=④部分绿呈裁位 ⇒ rollback（§七）；拆测试靴→原形供给面（sitecustomize 2c4baad3+fl6_recall.py 四机摘除先存后删）→沉降 1800s→产线复原靴（r3prod/8899，ENV50）→warm 义务+四查+smoke→**OUTAGE-END**（§八） | 见 §八 |

## 二、主判 cp30（判读线①；QA31 e3a-redo 微流程逐位复刻：同 driver/同 plan/同参/同序列；cwd=库根）

fill30 实灌 **27.61%**（2.65M tok；QA31 红位 27.54% 同载态带——判读可比性成立）。三档判读（judge v3+engine-cp30.log 原始行双源；锚=E3A-T256 绿锚 3/3）：

| 档 | 引擎 #cached-token | eng/prompt | TTFT replay(s) | fill orig(s) | TTFT 比 | 严格双门 | 锚同位 |
|---|---|---|---|---|---|---|---|
| L0001（8k 最旧小档） | **9,728** | **98.09%** | 0.296 | 5.289 | **0.056** | ✗（比 ≥0.05 出线） | cached 与锚逐值同；replay 0.296<锚 0.306 |
| L0005（32k） | **35,072** | **99.68%** | 0.306 | 14.581 | 0.021 | ✓ | cached 与锚逐值同 |
| L0017（278k 主力档） | **277,760** | **99.95%** | 0.873 | 61.422 | 0.0142 | ✓ | cached 与锚逐值同；锚比 0.0115 |

- **引擎源（判读权威源）=3/3 全命中**：三档 cached 值（9,728/35,072/277,760）与 E3A-T256 绿锚**逐值完全相同**——QA31 红位签名（cached=0×3+TTFT 比 0.63–1.00 全长重预填）**零复现**。
- **L0001 比值出线=纯分母面（呈裁注记，非改线）**：比值分子（replay TTFT=修复控的召回面）0.296s 比锚 0.306s 更快；出线全因分母——本窗 fill 首发 TTFT 5.289s 比锚窗 11.104s 快 2.1 倍（首发靴页态环境差；锚比 0.0276 若配本窗分母则为 0.0267=过线）。TTFT 比线 <0.05 的设计意图（防假命中归属）在本读数中不构成混淆面：引擎原始行直证 cached 9,728（98.09%）。
- 冷对照 6 发（H0001-H0006）全 miss=salt 文档预期 miss（冷位自洽，与 QA31 同型）。

## 三、cp12 位+机理直证（判读线②③）

- **② cp12=绿**：L0017（278k 主力档）99.95%+TTFT 比 0.0139（锚/QA31 同带同值 99.95%）；L0005 99.68%+0.0208；L0001 98.09%（比 0.0546 同分母面注记）——QA31 带（小档 miss=机理内落点）**提升为全命中**=修复增益面超出「保持同带」要求。冷对照 6 发全 miss 自洽。
- **③ 机理直证（record-only）**：fill30 末 `swa_evictable` **121,344 → 43,520（−64.1%）**，`swa_available`=81,408（SWA 池 65% 可用=远不饱和）；对 ~40k 线超 4,520=如实注记（残余面=cp12/cp30 冷热 9 文档重发再入树尾窗+warm 探针分支，非退休失效——退休钩子横幅在档）。满池段末 swa_evictable=50,176（swa_available 74,752）持续不饱和。**退休生效直证成立**（SWA 池不再于深载态饱和=召回尾窗存活的结构性前提恢复）。

## 四、满池全容量召回档 3b（判读线⑦⑧；用户裁定 4d10357 语义承载）

**池位推进（如实）**：fill 集 docs 耗尽于 **89.06%**（plan 语料 2 文档 span 含无效 UTF-8 字节=UnicodeDecodeError FAIL×2 逐次重试在档；量具/语料冻结不改）→evict 段毛灌 +988,685 至 99.35%→S5b 越界灌 S0003-5（净 839,334）至 **99.96% 池水位**（avail 3,584 tokens；reserve 30k 止）——**9.6M FULL 池灌满带达成**。

**⑦ 满池召回 3 档@99.96%（engine-cp101.log 12:32:14/14/16 三行直读）**：

| 档 | 引擎 #cached-token | eng/prompt | TTFT 比 | 判 |
|---|---|---|---|---|
| L0001 | **9,728** | **98.09%** | 0.0552（分母面注记同①；replay 0.292s<锚 0.306s） | 引擎源 ✓ |
| L0005 | **35,072** | **99.68%** | 0.0225 ✓ | 双门 ✓ |
| L0017 | **277,760** | **99.95%** | 0.0139 ✓ | 双门 ✓ |

**满池位引擎源 3/3 全命中锚位逐值**（严格双门 2/3，L0001 同①分母面边际）——**满载语义（4d10357「9.6M 预分配池应可 100% 水位召回」）承载面闭合**；中途 cp100@89.06% 亦引擎源 3/3（9,728/35,072/277,760，engine-cp100.log 原始行）。

**⑧ 超池剔除档（record-only）**：
- **剔除激活直证（正向）**：补灌段 avail 钉 62,464 同时单发插入 279,778×3=LRU 实时剔除在档（跨 100% 即剔，受害者=最旧未触分支；热三档因 cp100 召回 MRU 刷新存活）——「超池才按工作流剔除」语义正向直证。
- **浅命中带未呈现（如实）**：+10% 追加（毛 988,685）全为已驻留文档重发=零净新增（语料新鲜面耗尽：fill 集 89.06% 止+salt 补灌耗尽+2 坏字节文档），probe 四发全命中（L0002 99.94%/L0001 98.09%/M0029 99.87%/M0005 99.93% 引擎直读）与零净新增自洽。记录位非门。
- 中间证据：evict 段 P0001 再入树首行 cached=165,888（~87.8% 部分驻留=补灌段部分剔除的痕迹面，engine-evict10b.log 12:32:19 行）。

**满池段水位面（窗卡 §五 新线）**：段内 min=**8,371MB**@12:11:49Z（距 1.5G 硬底 **+6,871MB**；<2G 预警 0 行；floor1500 红行 0；qmg2500 零触发；灌段水位 8.2–10G 稳态）。**E3A 时代「满载物理不可承载」预估（2.3–2.4KB/tok 外推 ~21G 增量）在本形实测不成立**（89–100% 灌段实测斜率 ~0.2KB/tok 量级=UMA 页池化生效）——水位新线裕度充裕，新线本身未被压近。

## 五、判读线总表（冻结线逐线；零事后改）

| 线 | 内容 | 读数 | 判 |
|---|---|---|---|
| ① 主判 cp30 | 3/3（≥98%+比<0.05 双源） | **引擎源 3/3 锚位逐值**；严格双门 2/3（L0001 比 0.056 分母面） | **部分绿呈裁（④位）** |
| ② cp12 位 | L0017 ≥99.9% 同带 | 99.95% 同值；小档升为命中 | **绿** |
| ③ 机理直证 | swa_evictable ≤~40k | 43,520（121,344→−64.1%；超 4,520 注记） | record（退休生效直证成立） |
| ④ 部分绿 | cp30 2/3（小档 92-96%） | 2/3 但小档=98.09% 锚位（非回缩带；④预设带不符如实注记）；退休横幅在档 | **呈裁位（本窗落点）** |
| ⑤ 红 | 0/3 复现 | 未复现（红签名零出现） | 未触发 |
| ⑥ 回归红 | 质量面/水位/复原任一红 | 全绿（§六） | 未触发 |
| ⑦ 满池档 | 100% 水位召回 3/3 | @99.96%：引擎源 3/3 锚位；严格双门 2/3（同①分母面） | 绿（严格口径注记呈裁同①） |
| ⑧ 超池剔除 | +10% 后浅命中带 record | 剔除激活直证（补灌段）；浅带未呈现（语料新鲜面耗尽） | record（如实） |

## 六、回归面（判读线⑥：全绿）

| 面 | 读数 | 判 |
|---|---|---|
| GSM8K n200 | **acc=0.98，err=0**（≥0.95 硬线；QA31 带 0.97 同域） | 绿 |
| needle 3 发 | 8192/32768/131072 = **3/3 PASS** | 绿 |
| warm 门复检 | **6103.6**（KV 全容量 torture 后靴健康终态） | 绿 |
| 水位四查 | 非满池段 WATER-RED=0（段 min 9,290>6000 产线常规线）；满池段按新线 0 红 0 预警 | 绿 |
| memcg 面 | 四机 pressure/hung=0 行（preboot/postboot/regression 三面） | 绿 |
| 回池 | flush 后 full_token_usage=0.0（100% 可用旁证；kv_available_tokens gauge flush 后缺位=量具注记〔QA31 同族已知缺陷〕） | 绿 |
| 看门狗/两守护 | TRIP=0 全窗；02 机 3535/3536 在档未动 | 绿 |

## 七、窗终处置（裁定与执行）

**裁定**（12:54Z run.log 落档；依 11:47Z 冻结读数+判读线零事后改律）：①严格双门 2/3=非全绿 ⇒ 不走转正支；非 ⑤/⑥红 ⇒ 不走红停支；落 **④部分绿呈裁位** ⇒ 产线按窗卡 §三.5 缺省复原目标执行 **rollback**。

**rollback 执行**：测试靴拆解（logs×4 先存）→原形供给面（sitecustomize 复原 **2c4baad3**+fl6_recall.py 四机摘除〔先存后删：档存 `logs/FL6-FIX-20261013/deploy/rollback-archive/`〕+adapter-sync --check --expect sitecustomize.py=2c4baad3 绿）→沉降 1800s→**产线复原靴 r3prod/8899（ENV50 15767aa6+SPEC6+o12c1-prod 29 件）**→warm 义务 64k×4+warm 门+四查+smoke 3/3→OUTAGE-END（§八）。

**回退链登记（两级，自产线在役形起）**：产线原形（50 键+2c4baad3）→〔转正 runbook §九 反向〕。**ENV51 件（`~/migrate-assets/dsv41/env/PROD-R51W5-FL6FIX-spec1.env`，md5 2ac74586/51 键）保留在库**=转正即用形（不经 boot 不生效）。

## 八、OUTAGE 与终态

- **OUTAGE**：2026-10-13T**10:02:15Z → 13:34:38Z**（3h32m23s；三靴串行=FL6FIXA1 红停靴+FL6FIXA2 测试靴+FL6FIX-RESTORE 复原靴，规避律④ 逐靴 1800s 沉降过门）。
- **终态（复原靴直证）**：boot rc=0+8899=200+target_verify 45.35s（健康带）+**warm 门 6121.7**+四查全套（banner29:4+池 9,600,000+O12 armed 四秩+R1 fail-safe PASS rows=96+MISMATCH=0）+smoke 3/3 北京+8898 收净 000+r3prod 四机 1×4+02 两守护在档未动+**[fl6_recall] 行计数=0（原版逐字休眠直证）**。
- **修复验证态**：生产级四机 TP4 实证完成——门控生效直证（四容器 patched 横幅）+cp30 引擎源 3/3 锚位+cp12 绿+满池 99.96% 3/3 锚位+机理直证（swa_evictable −64%）+回归面全绿+水位新线裕度充裕；唯一呈裁面=L0001 TTFT 比值分母效应（§二）。

## 九、转正 runbook（主会话呈裁后即用；预计 ~40min 含沉降）

1. `cp logs/FL6-FIX-20261013/deploy/rollback-archive/fl6_recall.py.adapter-copy ~/migrate-assets/dsv41/adapter/fl6_recall.py`
2. sitecustomize 按 `logs/FL6-FIX-20261013/deploy/sitecustomize-wire-v2.diff` 重放（elif 两支+**白名单两行**——FL6FIXA1 教训：白名单漏加=死代码休眠，横幅门 fail-closed 可拦）；重算 md5 应=55b1e412，落 expect 文件后 `adapter-sync --apply --check --expect sitecustomize.py=<新值> fl6_recall.py=b87cbb5e`
3. 沉降 ≥1800s 后产线 boot：`ARM_TAG=<tag> CTN_PREFIX=r3prod API_PORT=8899 SPEC=1 ARM_ENV_FILE=$ENV51 SPEC_EXTRA_ARGS="$SPEC6" SGLANG_OVERLAY_DIR=$OV_PROD bash tools/boot-with-slotlock.sh bash ~/migrate-assets/bin/r3-boot-arm.sh`
4. 门：`[fl6_recall]` 四容器两行 patched 横幅（缺=红停）+四查+warm 门+smoke；回退=摘 51 键（改用 ENV50 boot=休眠）或重放本 rollback。

## 十、量具与缺陷如实注记（零掩盖）

1. **S2 部署 v1 白名单漏加（本窗唯一部署红）**：DEPLOY-NOTES 接线法只登记 elif 两支，未登记 EngramFinder.find_spec 白名单两行（sitecustomize:132 评审 F-1 注释已警告「漏加则本分支永不触发」）→FL6FIXA1 门控休眠；[fl6_recall] 横幅门（fail-closed 冻结线）拦截=门设计生效实录；桌面案头测无法捕（FL6_USE_ADAPTER=1 直装旁路 EngramFinder）。已修正（55b1e412）+runbook 登记。
2. **lib.sh fl6_banner_check 管线子 shell 假绿 bug**：`{...}|tee` 内 bad=1 丢失→首靴误记绿；boot-checks 计数档（0 行）即时人核拆穿+同靴修正（读数落盘再判）。教训入档。
3. **judge/内联归属器亚秒连发窗错位**：cp100 L0001 吞 1-token 噪声行=0、cp101 L0005 吞 L0001 行——真值=engine-*.log 原始 Prefill 行直读（三档 cached 与 TTFT 带互证一致）；s5b 起注记 #new-token<50 噪声行过滤。
4. **plan 语料 2 文档 span 无效 UTF-8 字节**：fill 深载（>27.5%）首达域，UnicodeDecodeError FAIL×2 逐 fill 重试在档；满池补灌改走 salt 面（S0003-5）达成 99.96%。
5. **kv_available_tokens gauge flush 后缺位**：回池判读改用 full_token_usage 旁证（=0.0）；QA31 同族已知缺陷注记在先。
6. **driver acc/net 口径**：行 cached_tokens 来自 API usage（已知恒 0 缺陷）⇒ evict acc 与 fill net_tok 实为毛口径；池位真值=服务端 metrics（progress 0.9996=99.96%）。
7. **fill_orig 分母环境差**：本窗首发 fill TTFT 整体快于锚窗（页态/靴差），L0001 比值 0.056/0.0552 出线的唯一来源（§二分析）；不改线不重测（判读线零事后改+重测=事后改面）。

## 十一、档案指针

- 窗档：`logs/FL6-FIX-20261013/`（run.log 全程流水+desk/ 段脚本+bench/FL6FIXA1/e3a/{fill12,fill30,fill100,fill100b,recall12,recall30,recall100,recall101,evict10,evict10b}.log+engine-cp{12,30,100,101}.log+engine-evict10{,b}.log+judge-*.jsonl+metrics.jsonl+rows.jsonl）
- 部署档：`logs/FL6-FIX-20261013/deploy/`（sitecustomize-pre-fl6fix.py.txt 原版备份+wire-v1/v2.diff+adapter-sync 日志+rollback-archive/）
- 水位档：`logs/FL6-FIX-20261013/water-10s.txt`（三段 floor 标记 6000/1500/6000）
- 锚对拍件：`logs/E3A-SWAPREFIX-20261011/bench/E3A-T256/judge-cp30.jsonl`（绿锚）+`logs/QA31-20261013/bench/QA31-P3/e3a-redo/`（红位）
- 分析档：`docs/research/FL6-RECALL-BUG-ANALYSIS-20261013.md`（根因定谳）+`docs/research/QA31-RESULT-20261013.md`（红窗源）
