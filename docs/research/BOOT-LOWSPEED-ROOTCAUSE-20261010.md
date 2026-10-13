# BOOT-LOWSPEED-ROOTCAUSE-20261010 · 「集群 boot 掉低速」专项：历史实例全盘点 + 统一根因框架 + 三层修复设计

- 案别：用户令「反复遇到 boot 掉入低速，排查根因+彻底修复」。
- 纪律：纯案头只读调查（零集群操作、零 docker/ssh/boot、零流量）；**W1 判别窗在飞（logs/W1-20261010/ 只读）**；本报告不触碰任何运行中进程。
- 法源起点：docs/research/ENGRAM-PREFILL-DEGRADATION-FORENSICS-20261009.md（=R-0，v2 主判「靴级出生慢模式」）+ docs/taskcards/PREFILL-FIX-CAMPAIGN-CARD-20261009.md（F-1..F-8+W1-W3 排程）+ docs/taskcards/W1-DISCRIMINATION-EXECUTION-CARD-20261009.md（v1.1）。
- 断言口径：【实证】=读到日志/档案原文；【推断】=推演；【OPEN】=证据不足以定谳。所有实例带 file:line / 档路径锚。

---

## 0. 一页定谳

1. **「反复 boot 掉低速」在历史档案中实为四个不同家族**，只有一族是真正的「复发性慢模式」：
   - **Fam-A（主族，R-0 族）「V4.1 长流量空窗后首靴 prefill 慢模式」**：全档共 **2 个自有实例**——KV-V41（10-09 12:40 靴，全靴 723-1,035 tok/s）与 **W1-B1（10-10 00:21 靴，探针 8 轮全 801-821 tok/s，R-0 复现坐实）**——同 env（43 键产线同形）、同「首次流量即慢、整靴恒慢非劣化型、radix/decode 面 fine、重启即愈」签名。共性前置态=**V4.1 prefill 流量空窗 ≥8h 后的首个 V4.1 形靴**（§2.1/§3.2）。外部同族参照=knapcio「lane 服役 15h prefill −30%、重启恢复、cause open」。
   - **Fam-B「靴内残留态/靴龄累积」**：DRIFT-INC-20261004（复原靴自首个重通信相位起均匀 4× 慢、落后者 rank2、干净重启即愈）——与 Fam-A 的判别差=Fam-B 在靴内累积/残留，Fam-A 出生即慢。
   - **Fam-C「形/参/量具伪影低速」**：T4PW/OPEN28A 10-07 事件（表观 −49~54% 持续 5+ 靴）终裁=四参缺 `--enable-decoder-swa-bounded-replay` 的参面伪影+形面放大，**非环境慢模式**——检测层的头号误报源。
   - **Fam-D「fabric 事件族」**：断电（10-07 01:34Z）与链路翻转 GID 出洞（10-08 22:18 INCIDENT-2218）——多为靴失败/楔死而非低速，已有 FABRIC-SELFHEAL 守护。
2. **载体判读（W1-B1 交叉后）**：R-0 三载体中，**③（KV-V41 独有食谱）降级为非必要载体**（B1 未跑食谱仍慢）；**①（首靴冷态）获现场证据**（B1=8h 产线在役后首个测试靴、纯文学首流量即慢）；**②（EMPTY_CACHE 税）仍活着**（B1 同键在役，终判挂 B3/F-2 臂在飞）。
3. **新发现的边界**：V4.1 流量空窗 ≤~5h 的历史首靴全部健康（READ ~1h、A23-E0 ~3.5h、F6PRIME ≤5h10m），≥8h 的两个首靴全慢——**阈值落在 (5h, 8h) 开区间，未采样【OPEN】**。
4. **弱新信号【推断】**：两个慢靴 boot 时长 9m08s/9m35s vs 同形快靴 7m46-7m57s（+1.2-1.6min）——建议入 boot 台账常采字段（§4.1）。
5. 修复三层：**检测**=boot 后 prefill 哨兵（fail-visible 横幅+台账，形/参钉面防 Fam-C 误报；新立 F-9）；**预防**=开窗首靴热身协议（合法热身面=真实 serving 流量，**禁主动预热页缓存红线不动**；新立 F-10，可并入 F-9 一条协议）；**修复**=按载体（①热身+硬件体检呈裁／②F-2 臂在飞→键值改形呈裁／③driver 修正=F-6/F-7 已覆盖；Fam-B 干净重启协议；Fam-C/Fam-D 已有件）。
6. 与 W1 在飞数据**无冲突**：B1 verdict 行（run.log:74）与本报告判读同向；probe 9-12 轮与 B2/B3 腿在飞，终值归执行窗。

---

## 1. 调查范围与方法

- 考古面：logs/ 全部 168 窗档；boot 台账源=各窗 run.log「boot rc=0/OUTAGE」行+boot-checks/*-boot.log+state/boot_ledger.txt；速率源=prl6 三步法（sparkDash filler 口径）、agg600k、sd_bench 单发 PR、KV-LIFE rows.jsonl（真文本）、劣化探针（real filler）。V4.1 形 PR 判据统一锚：filler 8k-128k 健康带 **4271-4886**（M12F/P2/A24DDCOFF/GAUGEAB 锚族）；真文本 32k 健康带 **~3,860-4,250**（V41B/V41C 实测）。
- 判据（按任务书）：同形下 prefill 速率低于该窗健康对照 50%，或跨靴不可解释差 >2×。0731/VL 形窗（UNBLOCK/RATIFY/M0731W*/VLW*/QAVLW2/T17/O10/O13 等）的 c1 解码读数不构成 V4.1 prefill 证据，仅用于时间轴。

---

## 2. 低速靴实例登记表（横断面考古结果）

### 2.1 主登记表【实证】

| # | 日期/时窗(Z) | 靴 | 形+env | 前置态（关键差分） | 首流量速率 vs 同窗对照 | 持续范围 | 归因（家族/载体） |
|---|---|---|---|---|---|---|---|
| **LSI-1** | 10-04 13:59 点火 | r3prod 复原靴（PROD-RS 31 键 spec1） | 产形 | 前序：D2 靴 pinned-copy 违例崩（13:41）→D3 靴（快）→13:54-13:57 拆栈+回撤适配器+drop_caches→复原靴。发作窗 [13:52:51,14:05:14] | 捕获 s/it 8.92-11.15（晨同形 2.6-4.1，≈3-4×）；解码步墙 med 200ms（晨 50ms，4×）；落后者=rank2/dgxspark04（TP2 CPU 累计 66% vs 他秩 ≈197%） | 整靴恒慢（自首个重通信相位起），≥42min | **Fam-B 靴内/进程级残留态**——零改动干净重启全复原（步墙 54ms/gen 98-104/TP 比回 0.91）；fabric/内核/内存/时钟当场全绿（logs/DRIFT-INC-20261004/DRIFT-FORENSICS-20261004.md §〇、DRIFT-CLOSURE-20261004.md §三） |
| **LSI-2** | 10-07 08:24-17:10 | T4PW PRECHECK-EAGER4P／DISCRIM-5P-8K／ROLLBACK-BAK-5P-8K＋OPEN28A W1B-W6（≥8 靴） | 四参/五参、R1STD 36 键/无键混合 | 断电 01:34Z+冷启 02:55Z 后 6-7h；**发作窗 06:41→08:24Z**（A23-E0 末健康 06:41Z→EAGER4P#2 首塌 08:24Z，非冷启本身） | 四参 eager 四档 2176-2261（−49~54% vs M12F 锚）；五参 8k 首发 1189-1298/暖 1581-1691；W1B 稳态 chunk med 2294 | 跨靴持续（同参同 env 排除法做尽）至 10-07 17:46 B2（R1STD-五参）稳态 4882 复健康 | **Fam-C 形/参伪影**：终裁=缺 `--enable-decoder-swa-bounded-replay`（四参）→prefill_sp deepcarry REFUSED→纯 AR+整行 MPCN ≈2×；R1STD 键面对层 A 共享态的分布放大；**残余「冷首块路径」645-2294 tok/s 未定谳【OPEN】**（logs/T4PW-20261007/run.log:81-140、logs/OPEN28A-20261007/README.md §一/§五、logs/OPEN28B-LAYERB-20261007/README.md §二/§三） |
| **LSI-3** | 10-09 12:40:45-13:58 | KV-V41（8898，V4.1 43 键 LL128 同形 md5 2de48070） | 产线同形 | **V4.1 prefill 流量空窗 8h35m**：末次 V4.1 测试流量=LL128-ADOPT READ 靴 04:05:39 拆线（run.log:135-198）；其间 0731/VL 形窗连续在跑（UNBLOCK 04:40-09:52、RATIFY 10:15-12:03）；产线 12:01:39 复原后仅 38min（见 §2.3 勘误） | 首梯 L0001 9916pt/14.685s=675 tok/s；全靴聚合 723-1,035（lookups/min÷24,576 换算）；c16probe 1,254=全靴最快。对照：V41B（崩后 ~10min 复靴）solo 3,860-4,250、X5121 512k 3,068 | **整靴恒慢**（缓存两态 evictions≈0↔==reads 吞吐零变化；「渐进劣化」表象=v2 重读为并发/档位视图） | **Fam-A／R-0 靴级出生慢模式**，载体①②③呈裁（R-0 §0/§6.1）；563k 头崩（INCIDENT-1）另案=A-V1/A-V2（R-0 §3） |
| **LSI-4** | 10-10 00:21:33-（在飞） | W1-B1（8898，43 键产线同形 env=PROD-R1STDLL128-spec1.env） | 产线同形（+1 已披露 no-op 模块 indexer_budget，W1 卡 v1.1 §二） | **产线在役 8h00m36s 后首个测试靴**：r3prod 16:20:16Z 上线（KV-LIFE OUTAGE-END）→00:20:52 停（loads=0 纯闲、四机无测试窗）；boot 含四机对称 drop_caches（boot-checks/W1-B1-boot.log:14-18） | E1 首发 H0001 9099pt/17.971s=**506**、L0005 35185/44.206=**796**；劣化探针（real 32k）轮 1-8 **801-821 平直**（cum 0→672k+）；斜率门无劣化（不是劣化型） | **整靴恒慢=R-0 复现**（正式判读门=探针 EXEC；run.log:74 verdict 行已记「落 KV-V41 慢靴域」） | **Fam-A**：载体①（首靴态）现场证据成立；③食谱降级（B1 无食谱仍慢）；②EMPTY_CACHE 待 B3/F-2 臂（在飞）。E1 即时二连发全命中=radix 面健康（H1 容量方向，另线） |
| X-1 | 外部参照 | knapcio lane | 同配置 | lane 服役 15h | prefill −30% vs fresh 同配置 | 重启恢复 | cause open（~/knapcio-v41-audit-20260925/docs/upstream-watch.md:133-135 原文「a lane that had served 15 h ran ~30 % slower on prefill than the same config fresh (cause open, a restart recovers it)」） |

### 2.2 健康对照靴（排除面，V4.1 形 PR 证据）【实证】

| 对照 | 靴时点 | V4.1 流量空窗 | 读数 | 锚 |
|---|---|---|---|---|
| H-1 LL128-ADOPT READ | 10-09 03:26:45 点火/03:34:31 rc | ~1h0m（末流量=RING4096-R2 agg600k 02:27:04） | sparkDash filler 8k=4225.2／128k=4666.6 IN-BAND；agg600k 3039（+0.66%） | logs/LL128-ADOPT-20261009/run.log:135,188-189,198 |
| H-2 RING4096-R2 | 10-09 01:20-02:53 | 短（MACGW 00:44-00:54 后即开） | agg600k 3056.1 GREEN；手动 32k PR 4835.2 | logs/RING4096-R2-20261009/run.log:412,462 |
| H-3 A23-E0 五臂 | 10-07 04:50-06:41 | ~3.5h（末流量=L1-F5 prl6 ~01:0x） | NCCL 臂 prl6 4437/4958/4962/4815（+1.8~2.2% IN-BAND）；E0 环 AR 全尺寸健康 | docs/research/OPEN28C-NCCL-CHANNEL-FORENSICS-20261007.md:48；logs/A23-E0-20261007/run.log:109-700 |
| H-4 F6PRIME B1 | 10-08 02:46 | ≤5h10m（末 prl6=P2 21:36 10-07；或计 F5PRIME 小流量则 ~1h16m） | prl6 四档锚带内（8k arb≈4211+，锚 4354/4848/4860/4728）；engine steady med 4944 | logs/F6PRIME-20261007/run.log:22,50-51 |
| H-5 F7TRIMODEL | 10-08 08:11-13:24 | 短 | agg600k 2996-3056 全带内 | logs/F7TRIMODEL-20261008/run.log:54,79,108 |
| H-6 P2-DUALANCHOR | 10-07 20:30-22:13 | 短 | prl6 四档 4271.0/4756.4/4842.9/4704.5；engine med 4921-4927 | logs/P2-DUALANCHOR-20261007/run.log:24,38 |
| H-7 M12F/A24DDCOFF/GAUGEAB | 10-05/10-06 | 密集窗日 | 4277.0-4886.3 全 IN-BAND（4096 档 3785.7 带外高为增益非低速） | logs/A24DDCOFF-20261005/run.log:69-72、logs/GAUGEAB-20261006/run.log:81-83 |
| H-8 KV-V41B/V41C | 10-09 14:06/14:33 | 分钟级（崩后 ~10min/~9min 复靴） | 真文本 solo 3,860-4,250；V41C L0017 277,907pt/73.889s=3761 | logs/KV-LIFE-20261009/bench/{KV-V41B,KV-V41C}/rows.jsonl；READINGS.md §2.1 |

**空窗阈值边界**：健康首靴空窗已观测至 ~5h（H-4 上界口径）；慢靴空窗两例均 ≥8h0m。**阈值∈(5h,8h) 未采样【OPEN】**。

### 2.3 种子实例核实与勘误【实证】

1. **「晨靴劣化（首请求 ~5950 → 数发后 ~600，跨 flush 存活）」**（logs/KV-LIFE-20261009/READINGS.md:71）——核实=**KV-V41 靴 1 的 prep1-kjv-era 相位读数，非独立实例**。其「快首发」行（L0004 12,564pt/ttft 1.426s 等，bench/KV-V41/rows.prep1-kjv-era.jsonl 首批）已被 R-0 §7.2 判为**旧计划前缀延伸伪影**（radix 命中前缀使 ttft 虚短；两判同向：不得引作健康上界）。本报告将该种子登记为 LSI-3 的 v1 表述，以 R-0 v2「恒慢靴」读数为准。
2. **KV-V41 前置态「8h 产线空闲」表述精度勘误**：R-0 §0 称「8h 产线空闲后首靴（12:39 产线停→12:40:45 点火）」。台账复核：产线栈实际 12:01:39 才由 RATIFY-CG 复原（logs/RATIFY-CG-20261009/run.log:222，OUTAGE-END 12:03:36 :242）→KV-LIFE 12:39:56 停=**产线在役仅 ~38min**。8h26m 的真实口径=**V4.1 形测试流量空窗**（末次 V4.1 测试=LL128-ADOPT READ 04:05:39 拆线→KV-V41 12:40:45 点火=8h35m；其间机器未闲，0731/VL 形窗连续在跑）。**方向不变**（长空窗后首靴慢），但精确共性是「V4.1 prefill 流量空窗」而非「机器空闲」——W1-B1（真 8h 机器纯闲）与 KV-V41（8h 有他形活动）双双落慢域，恰说明载体不在「机器是否忙」而在「V4.1 靴/流量是否缺席 ≥8h」。
3. **knapcio 15h lane**：原文核实（upstream-watch.md:133-135），−30%、重启恢复、cause open。注意其前置是「服役 15h」（=Fam-B 靴龄轴）而非「空窗后首靴」（Fam-A 轴）——knapcio 案两轴兼容，作外部同族参照时按此注记。

### 2.4 「被当噪声略过」的低速靴挖掘结果【实证+如实呈报】

- **T4PW 判别靴族（DISCRIM-5P-8K 1297.9/1581.9、ROLLBACK-BAK-5P-8K 1189.5/1691.1）**：窗内自判逻辑写明「仍 ~2200 ⇒ B/环境面」（logs/T4PW-20261007/run.log:81）——两靴仍慢时窗已收，当时未终判；后续 OPEN28A/B 链终裁为参面伪影（§2.1 LSI-2）。**这是全档最接近「被略过」的低速靴族**，但其归属已被终裁，不改变 Fam-A 清单。
- **OPEN28A W1-W6 六靴（823-2437 chunk tok/s）**：同理，归属 LSI-2（Fam-C）。
- **「冷首块路径」残余**（OPEN28B §三：当日冷首块 645-2294 tok/s vs 健康锚缺档不可定量）——**未定谳残留面**，现象上与 Fam-A「首流量慢」有重叠，但当日已被形/参混杂污染、健康同口径锚缺档，案头不可重开【OPEN，登记为 Fam-A 的潜在历史前兆，待 W1/W2 哨兵数据回看】。
- **F5PRIME S1/S2（10-08 00:52/01:19）**：仅 lm_cert verify 流量，未取 PR 读数——无速率证据，不入表（如实注记）。
- **产线读数形混杂**（=「产线相对位悬空」例）：10-07 12:16Z 起产线被静默换成无键形，OPEN28A §四坐实「-42%→-17% 恢复」曲线混入形变（logs/OPEN28A-20261007/README.md §四）——**产线四查必须含形核面（banner/env md5）的教训**，现役四查已含。

### 2.5 晨窗 vs 午窗系统差：**不存在**【实证】

慢靴发生时点：LSI-1 13:59、LSI-2 08:24、LSI-3 12:40、LSI-4 00:21；健康靴遍布 00:52-21:36。判别变量是**靴前置态**（空窗时长/前栈事件/形参），非一日内时辰。W1-B1（深夜）与 KV-V41（正午）同慢、A23-E0（凌晨）与健康 READ（凌晨）同快，直接反证时辰假说。

---

## 3. 统一根因框架

### 3.1 四族分解与「反复」的载体统一性判断

| 族 | 实例 | 慢的面 | 出生相 | 愈法 | 载体统一性 |
|---|---|---|---|---|---|
| **Fam-A 长空窗首靴 prefill 慢模式** | LSI-3、LSI-4（+X-1 兼容） | prefill 4-5×（knapcio −30%） | **出生即慢**（首流量相位起恒定） | 立即复靴（V41B/V41C）或（knapcio）重启 | **统一**：两自有实例同 env/同签名/同前置态（V4.1 流量空窗 ≥8h 后首靴）；radix（E1 即时二连发命中）、decode、质量面全健康 ⇒ 载体在 prefill 计算路径上受靴级状态调制 |
| **Fam-B 靴内残留态/靴龄累积** | LSI-1（+X-1 的 15h 轴） | decode+捕获 4×（全通信路径） | 复原靴首个重通信相位即在场 | 零改动干净重启 | rank2 落后者+CPU 不对称签名；与 Fam-A 共享「重启即愈」表型但轴向不同（累积 vs 空窗） |
| **Fam-C 形/参/量具伪影** | LSI-2 | prefill ~2×（表观） | 随形/参 | 改参/形即愈 | 非慢模式；检测层必须先排除 |
| **Fam-D fabric 事件** | ENVDEG 断电族/INCIDENT-2218 GID 洞 | 多为靴失败/楔死 | 事件驱动 | GID 环回/netplan canonical（已部署） | 已有守护（fabric-guard v2） |

**「反复」的主载体=Fam-A**。R-0 框架对 LSI-3/LSI-4 完全成立且获 W1-B1 交叉强化；Fam-B/C/D 是历史「boot 掉低速」表象的另三源，任何检测/预防设计必须做族间判别。

### 3.2 Fam-A 与 R-0 三载体的对照（W1-B1 交叉后）

- **载体①（首靴硬件/分配器冷态）——支持证据增强**：B1=8h 产线在役后首个测试靴、纯文学首流量（E1+探针）即 506-821 tok/s，未跑任何 KV-V41 食谱 ⇒ 慢模式不需要「空窗+食谱」复合，单「空窗后首靴」即够。排除面复用 R-0 §3.1（GREEN 零翻转/时钟 2385-2392MHz/水位健康）+ B1 hwstate 采样（GPU 54°C/12.37W/时钟事件原因干净/NVMe-SoC 55-59°C，logs/W1-20261010/bench/W1-B1/hwstate/dgxspark01.hwstate.txt）。
- **载体②（EMPTY_CACHE 税状态放大）——仍活**：B1 与 KV-V41 同键（DSV41_PREFILL_EMPTY_CACHE_TOKENS=8192，boot-checks/W1-B1-boot.log:24），B1 慢与②兼容；终判=B3/F-2 臂（arms/F2-EMPTYCACHE0-spec1.env，唯键差 8192→0）在飞。
- **载体③（KV-V41 独有食谱）——降级为非必要载体**：B1 未跑 calib×24/fill-召回循环/flush 多次/c16probe 交错仍慢 ⇒ 食谱非慢模式必要条件；保留为「KV-V41 靴内额外相位的可能放大器」（如 c16probe 饱和 churn、崩塌视图），归 F-6/F-7 量具债面。
- **boot 时长弱信号【推断】**：慢靴 KV-V41 9m08s（12:40:45→12:49:53，run.log:23-24）、W1-B1 9m35s（state/boot_ledger.txt）vs 快靴 V41B 7m57s（:65-66）/V41C 7m56s（:79-80）/LL128 三靴 7m46-7m57s（run.log:79,135,218）。样本=2 慢 5 快，+1.2-1.6min 差值方向一致但未过显著性；入台账常采（§4.1），不作判据。

### 3.3 R-0 框架之外的新假说（如实立档）

1. **「V4.1 靴活动重置共享态」假说（Fam-A 机制统一候选）**：慢态在「V4.1 流量缺席 ≥8h」后出现、在「一次 V4.1 靴+流量」后消失（V41B/V41C 分钟级复靴即快；Fam-B 的 DRIFT 复原同构）⇒ 载体是一个**被 V4.1 靴活动重置、在长时间无 V4.1 活动下漂移到劣化态的共享资源**。案头候选：宿主分配器/大页态（buddy 高阶漂移；每 boot drop_caches 不清分配器碎片）、NVMe 控制器/介质态（/engram 读路径与权重加载盘）、GPU/SoC 电源态（idle 深睡后首加载路径）、编译/triton 缓存态。**案头不可终判**；判别材料=W1-B1 已采 hwstate 包（buddyinfo/vmstat/telemetry）对照快靴 + W2 若判①则硬件体检呈裁。注意：KV-V41 空窗期内 0731/VL 靴不断重置「容器/GPU/页缓存」面仍慢 ⇒ 载体面应在他形靴**不触碰**或**触不全**的资源上（分配器高阶/NVMe 深层态候选性强于页缓存——页缓存每 boot 已 drop 且他形靴也加载权重）。
2. **Fam-A 与 Fam-B 可能同底两表型**【OPEN】：DRIFT（靴内残留）与 Fam-A（空窗后首靴）若最终同指向宿主分配器/NVMe 态，则为同一底层态的两种触发路径（累积 vs 漂移）。knapcio 15h lane（两轴兼容）是外部旁证。案头不合并，留 W2+ 数据。
3. **不解释项如实报**：LSI-2 的「冷首块路径」残余、(5h,8h) 空窗阈值、boot 时长差值——均 OPEN（§6）。

### 3.4 每实例归因行（汇总）

- LSI-1 → Fam-B（靴内残留态；重启复原实证；DRIFT-CLOSURE §三 A 坐实）。
- LSI-2 → Fam-C（参面伪影主因+形面放大+冷首块残余 OPEN）。
- LSI-3 → Fam-A（R-0；载体①②呈裁中，③降级）。
- LSI-4 → Fam-A（R-0 复现；载体①现场证据、②待 B3、③排除为必要条件）。
- X-1 → 外部（cause open；15h 服役轴=Fam-B 兼容，重启恢复同构）。

---

## 4. 彻底修复设计（机制级，三层）

### 4.1 检测层：boot 后 prefill 哨兵（新立 **F-9**；fail-visible 不 fail-safe）

- **挂点**：`tools/boot-with-slotlock.sh`（94 行，非侵入 wrapper）加可选后置步——环境开关 `BOOT_SENTINEL=1`（缺省关）时，在 boot 命令 rc=0 且 8898=200 后自动执行哨兵；不改 r3-boot-arm.sh 本体（零引擎面）。
- **量具**：一发/三发 sd_bench PR（复用 prl6 与 W1 探针口径）：≥8k 真文本或 filler 单发 ×3 取中位；**盐前缀保唯一**（sd_bench 每调用 uuid 加盐已在）防 radix 复用伪影（PR-ANCHOR-CONTAMINATION-AUDIT 律）；**首发单独登记为 cold-first 读数**（就是判别数据，勿弃）；速率=prompt_tokens/TTFT（链 A）。可选双源：引擎 chunk input throughput 行。
- **阈值（per-form 锚表，落 tools/ 侧配置件）**：filler 8k/32k/64k/128k 锚=4354/4848/4860/4728（M12F 族）；real 32k 锚=3900（V41B 带中值）。判档：≥0.7×锚=GREEN 行；0.5-0.7×=WARN 行；<0.5×锚=**SLOWBOOT 横幅**。
- **fail-visible 语义**：横幅打 ARM run.log+boot 台账（state/boot_ledger.txt 追加 `SENTINEL <verdict> rate=... anchor=... form=<env-md5/gates>` 行）+ 产线/测试值守可见；**不拦服务、不自动重启**（U1 教训：未验证绿的环境里自动动作放大问题——FABRIC-SELFHEAL-DESIGN §〇.6 律）。
- **Fam-C 防误报钉面（OPEN-28 教训硬化）**：哨兵判读前置形核=ARM_ENV_FILE md5+banner gates 数（30/31 兼容）+serve 参指纹（`--enable-decoder-swa-bounded-replay` 等五参在场断言）；形不符 → 输出 `ANCHOR-N/A` 不判快慢。量具污染防线：E1 式即时重放 hit（TTFT 比 <0.3）= radix 命中伪影 → 弃该发补发。
- **附带常采字段**：boot 时长（点火→rc=0，现台账 BOOT-START/END 已有，正式入哨兵行）——检验 §3.2 弱信号。
- **复用件**：tools/pr_degrade_probe_draft.py（探针 v2，--boot-end 参数；W1-B1 实战验证记录键完整）=哨兵的 in-run 加长版；prl6 三步法=锚维护量具；F-6 一靴一锚新鲜律=锚纪律。**F-9 本体=一个薄 shell/python 包装（估 <150 行）+锚表配置**，案头可写、呈主会话批后入役。

### 4.2 预防层：开窗前置协议——首靴热身（新立 **F-10**，可并入 F-9 作一条协议）

- **协议**：一切 W 窗/验收窗，8h+ 空闲后的首个 V4.1 靴固定序：**boot → 哨兵首发（cold 读数登记）→ 若 SLOWBOOT：热身序列（固定 PR 爬梯 8k→32k→128k ×1-2 轮，~3-5min 真实 serving 流量）→ 哨兵复测 → 恢复=记「热身可愈」继续窗（正式锚取复测后并注记）；不恢复=标靴，换靴或呈裁（不在慢靴上取正式锚/验收读数）**。
- **红线合规论证**：禁令=「禁主动预热**页缓存**」（不 cat/vmtouch 权重与语料）。热身面=**合法 serving 流量**（真实 prefill 请求），正是「把冷态税在测试流量前缴掉」的合法面；且每 boot 本含四机 drop_caches（W1-B1-boot.log:14-18）——页缓存面恒冷、热身不触碰该面。若载体②（EMPTY_CACHE 税）坐实，热身同样先行缴税（连续 chunk 使分配器达稳态），协议两载体通用。
- **锚序纪律（与 F-6 相容）**：冷首发读数单独入「boot 健康档案」不作锚；一靴一锚新鲜律的「新鲜」定义明确为「热身后、盐前缀、首正式档」；W 窗类型若需「冷态读数即判据」（如未来 A5 复刻），卡内预声明，二者不混。
- **排程面**：MASTER/窗卡模板增一句「开窗第一步=首靴哨兵」（W1 已事实执行：B1 探针=首流量相位——本协议=把偶发实践固化为强制步）。

### 4.3 修复层：按载体定（族×载体矩阵）

| 载体/族 | 修法 | 件映射 |
|---|---|---|
| Fam-A ①冷态 | 热身协议（4.2）+ 硬件面体检呈裁（boot hwstate 包标准化：buddyinfo/vmstat 缺页/NVMe-SoC telemetry/时钟位——W1-B1 已采此包，固化到 F-9 哨兵附带采集）；若判 knapcio 同族（重启恢复、cause open）→ 维护窗级呈裁件「首靴慢靴整机体检/必要时冷重启」（用户决策级，参 ENVDEG NIC flap 先例的处置层级） | F-9/F-10 新立；体检项呈裁 |
| Fam-A ②EMPTY_CACHE 税 | B3/F-2 臂在飞；若坐实 → 键值改形呈裁（新形=43 键唯键差 EMPTY_CACHE_TOKENS 8192→0/降档；**产线复原目标恒 R1STDLL128 43 键 2de48070 不变，直至呈裁通过**） | **F-2 已有件（在飞）** |
| Fam-A ③食谱 | driver 修正：calib ×24 重复句自污染（真实 cpt 3.66-4.09）+旧计划前缀延伸伪影面+flush 循环判读注记 | **F-6/F-7 已有件（案头已落）** |
| Fam-B 靴内残留态 | 干净重启协议（零改动重起，DRIFT-CLOSURE 已验证全绿判据组）；早期标记：捕获相位 s/it（>2× 晨锚即红）+TP 秩 CPU 对称性抽查 | 新立小件（值守判读条款，可挂 F-9 横幅判读面） |
| Fam-C 形/参伪影 | 形/参钉面入哨兵（4.1）；窗卡判读门前置「同形同参自证」 | F-9 内含；GATE-MATRIX 防呆已有（0dfc86a） |
| Fam-D fabric | fabric-guard v2（F-G10 翻转检测+GID 自愈+告警）已部署 | **已有件（FABRIC-SELFHEAL）** |

### 4.4 与总卡 F 件映射总表

| 层 | 件 | 状态 |
|---|---|---|
| 检测 | F-6 真文本锚建制+pr_degrade_probe 实装（量具基座） | 已有件（3796b9f+探针 v2，W1 实战） |
| 检测 | F-8 观测面 worker logs/teardown 加固 | 已有件 |
| 检测 | **F-9 boot 哨兵**（slotlock 可选步+横幅+台账+锚表+形钉面） | **需新立（本报告 §4.1 规格）** |
| 预防 | **F-10 首靴热身协议**（开窗固定序+锚序纪律） | **需新立（本报告 §4.2 规格；可并入 F-9）** |
| 修复 | F-2 EMPTY_CACHE 臂 | 已有件（在飞 W1-B3） |
| 修复 | F-3 A5 因子（=W1 靴序 B1/B2） | 已有件（在飞） |
| 修复 | F-1 indexer row-chunk（W2）／F-4 Engram 容量／F-5 止血组 | 已有件（W2 呈裁） |
| 修复 | F-7 案头勘误五件 | 已有件（已落） |
| 修复 | Fam-B 早期标记条款 | 需新立（小件，挂 F-9） |

---

## 5. 与 W1/W2/W3 排程的接入点

1. **W1（在飞）**：本报告登记 LSI-4 已并入判读面——B1=「首靴×纯文学」格 **R-0 复现**（run.log:74 同向）。B2（复靴×完整食谱）与 B3（F-2 臂）结果直接落 W1 卡 §三判读门总表：B2 快+B1 慢 ⇒ 载体①坐实主载；B3 快（vs B2 慢）⇒ 载体②坐实；两腿判读互斥面已在卡。**建议**：B2/B3 起靴时顺手记 boot 时长（台账已有），并入 §3.2 弱信号样本。
2. **W2（修复窗）**：按 W1 定谳武装 F-1（+F-4 若判 Engram 面）+563k 重放取证照卡执行；**建议每靴挂 F-9 哨兵试点**（零集群增量：探针/量具已在工具箱，只需薄包装+锚表；呈主会话批后用）；若判载体① → W2 靴序前加热身序列（F-10 试点），563k 重放的大档必须不在冷态首靴上跑（崩死面 A-V1 与靴龄态交差的既有判读不受影响——重放取证本就设计在老化后）。
3. **W3/W3'（QA 验收）**：验收门建议追加两条：①「首靴哨兵 ≥0.7× 形锚」（W3 若含 8h+ 空闲后首靴则直接采；否则以热身后锚为准+台账 cold 读数在档）；②「boot 台账含 SENTINEL 行」（观测面完备性）。KV 终验窗（512k 文学档）在终形上重跑时同样先哨兵后大档。
4. **呈裁件汇总（主会话决策面）**：F-9/F-10 新立；载体②若坐实的键值改形；载体①若坐实的硬件体检项/维护窗级处置；Fam-B 早期标记条款。

---

## 6. OPEN 项与如实呈报

1. **载体① vs ② 终判**：W1-B2/B3 在飞，本报告不预判（与在飞数据无冲突；probe 9-12 轮与 B2/B3 终值归执行窗）。
2. **空窗阈值 (5h,8h) 未采样**：如需精确定界，机会性补一次 ~6h 空闲后首靴哨兵（可挂任一自然窗，勿专为它停机）。
3. **boot 时长差值**：2 慢 5 快，【推断】级，待 F-9 台账积累。
4. **LSI-2 冷首块路径残余**（OPEN28B §三）：与 Fam-A 关系未定谳——当日形/参混杂+健康同口径锚缺档，案头不可重开；登记为 Fam-A 潜在前兆，待哨兵数据回看。
5. **「V4.1 靴活动重置共享态」假说的物理载体**（分配器高阶/NVMe 深层态/GPU-SoC 电源态/编译缓存）：案头不可终判；W1-B1 hwstate 包在档待对照，终判挂 W2+。
6. **knapcio 15h lane cause open**（外部）：只能作同族参照，不能引作机制证据。
7. **R-0 §0「8h 产线空闲」表述精度**：本报告 §2.3.2 已勘误（产线在役实为 38min；8h35m=V4.1 流量空窗）——方向不变，供后续报告引用时更正口径。

## 7. 证据索引（本报告全部引用源）

- R-0：docs/research/ENGRAM-PREFILL-DEGRADATION-FORENSICS-20261009.md（§0 :10-15；§1.3 表 :59-65+v2 时间线 :67-81；§6.1 R-0/载体 :186-192；§6.3 A5 :212-214；§7 勘误 :225-228）。
- KV-LIFE：logs/KV-LIFE-20261009/{run.log:23-24,65-66,79-80,186-187；READINGS.md:13-18,71；bench/KV-V41/{rows.jsonl,rows.prep1-kjv-era.jsonl,c16probe.json,calib.json}；bench/KV-V41B/rows.jsonl；bench/KV-V41C/rows.jsonl}。
- W1（只读在飞）：logs/W1-20261010/{run.log:21,34-39,43-56,74-75；state/boot_ledger.txt；boot-checks/W1-B1-boot.log:14-18,24,84；bench/W1-B1/{e1_immediate.jsonl,probe_exec2.log,hwstate/dgxspark01.hwstate.txt}}。
- 时间轴：logs/LL128-ADOPT-20261009/run.log:79,135,188-189,198,218；logs/RING4096-R2-20261009/run.log:186,412,462,536；logs/UNBLOCK-0731-VL-20261009/run.log:39；logs/RATIFY-CG-20261009/run.log:39,222,242；logs/MACGW-30-MIGRATION-20261009/run.log:24,79。
- LSI-1：logs/DRIFT-INC-20261004/{DRIFT-FORENSICS-20261004.md §〇/§二；DRIFT-CLOSURE-20261004.md §二/§三}。
- LSI-2：logs/T4PW-20261007/run.log:81-140；logs/OPEN28A-20261007/README.md §一/§四/§五；logs/OPEN28B-LAYERB-20261007/README.md §二/§三；logs/ENVDEG-20261007/README.md（一句话结论）；logs/OPEN28-HEAL4P/prl6/（经 ENVDEG recovery 引）；docs/research/OPEN28C-NCCL-CHANNEL-FORENSICS-20261007.md:48,117-121。
- 健康对照：logs/A23-E0-20261007/run.log:109-700；logs/F6PRIME-20261007/run.log:22,50-51；logs/F7TRIMODEL-20261008/run.log:54,79,108；logs/P2-DUALANCHOR-20261007/run.log:24,38；logs/A24DDCOFF-20261005/run.log:69-72；logs/GAUGEAB-20261006/run.log:81-83；logs/M12FORMAL-20261005/run.log:4-7。
- 外部：~/knapcio-v41-audit-20260925/docs/upstream-watch.md:133-135（15h lane）、:91-99（fresh-boot 基线建议）。
- 战役件：docs/taskcards/PREFILL-FIX-CAMPAIGN-CARD-20261009.md（F 表 :44-53、排程 :55-63、时序 :66-75）；docs/taskcards/W1-DISCRIMINATION-EXECUTION-CARD-20261009.md（判读线 :44-51、判读门总表 :67-75、挂载面披露 :29-34）；arms/F2-EMPTYCACHE0-spec1.env；tools/{boot-with-slotlock.sh,pr_degrade_probe_draft.py}。

——纯案头调查报告 / 2026-10-10（W1 窗在飞时点只读成文；零集群操作）
