# v4-vl-exp · DeepSeek-V4-Flash-Vision-Exp 注册卡 — 2026-10-06

> models.d 注册表卡。字段制=MULTIMODEL-GOV-CARD-20261004 §2.4；闭案法源=CD3-LINED-CARDS-20261006
> 卡二。誊录源=T13-VLBATTERY-CARD-20261005（VL 自锚面）+O13B-VL-PORT-CARD-20261006（600k 移植
> 案头设计）+GOV-CARD §1.3+VLW2R seg3/a9-fingerprint.txt。数字零手誊。

## §a 身份指纹

| 面 | 值 | 源 |
|---|---|---|
| config sha256（前 16，注册主键） | `6cd841bdd6702f5e` | GOV-CARD §1.3；A9 行另含 config md5 `c3afdf7706f7cfc5` |
| model_type / 层数 / 体积 | deepseek_v4 / 43 层 / bf16（视觉配置嵌套）/ 157G | GOV-CARD §1.3 |
| config 实测（打分几何面） | num_hidden_layers=43；compress_ratios 46 项（43 主层+3 MTP）分布={4:21, 128:20, 0:5}；index_n_heads=64 / index_head_dim=128；max_position_embeddings=1,048,576 | O13B §1.1 |
| 权重 A9 指纹（四机实测等值） | BYTES=**167831845209**（÷TP4=41.96G≈42.0G）；overlay_dig=`62f00b9eaaa5` ×4；PATH=`/models/DeepSeek-V4-Flash-Vision-Exp` | logs/VLW2R-20261005/seg3/a9-fingerprint.txt+O13B §四 |
| 模型类接管 | `deepseek_v4_vl.DeepseekV4ForCausalLM`+is_multimodal=True+unloaded 告警 0 | T13 §三 |
| VL overlay | `~/migrate-assets/v4vl/sglang-overlay.v4vl-79cafec0/`（28 件；对账=overlay-md5-manifest.txt 28 行） | O13B 头注+MVL-SPEC0 头注 |

## §b 四机路径（拓扑）

| 机 | 路径 / 形态 | 源 |
|---|---|---|
| dgxspark01 | `~/models/DeepSeek-V4-Flash-Vision-Exp`（home） | COMPAT-TASKBOOK §裁定 2 |
| dgxspark02 | `~/models/…` 与 `/data/models/deepseek-ai/…` 双在位（+vision-exp.sha256.manifest 对账面） | 同上+GOV-CARD §1.1 |
| dgxspark03 | `/data/models/deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` | 同上 |
| dgxspark04 | 同 03 | 同上 |

- 容器内统一 `/models/DeepSeek-V4-Flash-Vision-Exp`（MVL 驱动 per-machine host 映射）；**四机 157G 全在位零布机（W1 零传输）**。

## §c env 模板指针

- 基线草案=`arms/MVL-SPEC0.env`（仓库实测 **16 键**行；头注「未点火」草案；SGLANG_OVERLAY_DIR 指 overlay 28 件部署位）——本仓实测+文件头注。
- **T13 窗形**=VLW3B 池重裁形（**524288/0.55/watchdog900/FAULTHANDLER**）+memguard 全程守护零触发——T13 头注。
- **O13B 注记〔2026-10-06 已建勘误〕**：配套臂 env=`arms/O13B1-VL-SEG65536.env` **已建（O13B-DEV fe0a79f，8ac1258c）=19 键**（基=MVL-SPEC0 16 键程序化拷贝逐字节 cmp 全等+武装三键 TL_SEGMENT=1/ADMISSION=1/CTX_CAP=65536；port 卡「19→22」为笔误，拷贝基线=MVL-SPEC0 三窗实靴实证）；boot=logs/O13B-20261006/boot_mvl_600k.sh（3ff295f9）。

## §d boot 形

- **现役（基线）**=`logs/VLW2R-20261005/boot_mvl.sh`（在役 VL 驱动包装；默认 ARM_ENV_FILE=`arms/MVL-SPEC0.env`；A4 黑名单键只剥 env 不剥 install 本体）；窗专变体（不作基）=`boot_mvl_vlw3.sh`/`boot_mvl_vlw3b1.sh`/`boot_mvl_vlw2w31.sh`——O13B §三+本仓 logs。
- **待 O13B**=`boot_mvl_600k.sh`（新文件不覆写在役件；修订四处镜像 a7_reanchor_600k_m0731.diff `fba74d2d` 结构：ctx 131072→600000+`--max-total-tokens 7200000`+mrr16→12+水位地板 WATER_MARK_FLOOR_MB VL 线缺省 **12288**=C12 按线门槛；POOL_FINGERPRINT_EXPECT=7200000）——O13B §三。
- 容器/口：CTN_PREFIX=`r3boot-mvl`；API_PORT=`8898`；boot 三断言（模型类接管+is_multimodal=True+unloaded 无文本骨干键）；VL 恒 GRAPHS=0（boot_mvl.sh:215）。

## §e 锚带（T13 §一/§二/§三/§四誊录；VL 自锚禁与 V4.1/0731 对表）

### VL 面（首建入册）

- 官方 2 图对（文本形态/JSON 形态）=**2/2 200 全优**（胡萝卜-肉质根/玉米-颖果全对；pt 457/455）。
- 自建图集·单图（s1 红圆/s2 三横条/s3 数字 742）=**3/3 200 全优**；双图（d1 方-三角/d2 竖条计数/d3 数字 38-95）=**3/3 200 全优**（图序保持+跨图计数「多 3 根」全对）。
- 多图+长文（m1 三图形/m2 混合三图/m3 重复图，prompt≈3.18k tok）=**3/3 200 全优**（22-23s 级；OPEN-12 教训位池重裁形下全绿）。
- 4xx 错误形态（坏 base64/空 base64 体/悬空路径）=**3/3 400 优雅拒绝**（零崩）；超尺寸 16000×9000=**200 优雅受理（降采样）**，语义对零内存事故→OPEN-13。
- **人工三档评定汇总：11/11 发 200，优 11/合格 0/差 0**。

### 文本面（兼补 T12 step⑤ 欠账）

- GSM8K n200/8-shot/temp0.6/顺序/content=**0.93**（186/200，err=0）；marker 0.93；median_ct 90；两段 0.95/0.91；**串行吞吐 15.1 tok/s**。
- DE per-req tok/s（med of 5）prose c1/code c1/prose c8/c12/c16=**15.58 / 15.51 / 14.59 / 14.19 / 13.83**（c1 spread<2%；c16 [13.76-13.92]；与漂移查 2 gen_med 15.29 同带自洽）。
- accept（第六格）=**N/A**（SPEC=0 无投机对象，T13 口径注记）。

### 判据面

- 位等三对照双绿：图请求组三发 ct 33/33/33、纯文本组 65/65/65（content/reasoning 逐字节相等；biteq.jsonl 全文在档）。
- 漂移三查绿：查 1 capture=N/A（GRAPHS=0）；查 2 步墙 med=**75.0ms**≤140ms 结构门（8/8 发）；查 3 clean-restart steady 3/3+零重启+零异常。
- boot 门绿：池 **524288**/avail_gpu_mem **63.70GB**；新 A 门（MemAvailable 65.7-67.8G≥6G）；零 sparse-MLA 拒收×4（OPEN-9 签名零复发）。
- 水位：boot 后 65.7-67.8G→VL 面多图批谷底 **27.1G**（mm 累计消耗 ~38G 完成后不归还）→稳态 27-30G 至拆线；拆线后回升 118.7-119.5G；memguard 全程零触发（6G 线富余 4.5 倍）。

## §f 开放项（VL 线关联）

- **OPEN-13**：超尺寸图（16000×9000）未拒绝而受理（200+降采样+语义对+零崩）——「非崩」主判据达成、「拒绝」形态偏差；严格拒绝语义需 max-pixels 门（另案），量具口径追认归主会话（T13 §五）。
- **OPEN-14**：GSM8K n200=0.93<0.95 软参照位（−2pt 非 trip；候选因=无投机裸解码/temp0.6 采样面/自锚即此位；同 OPEN-11 形制归主会话）（T13 §五）。
- **W3 环境态未核**：MVL-SPEC0（未点火草案）与 T12 实靴臂 env 的差=O13B 窗前核对项（O13B §七.1）。
- **dspark k6 臂卡**：VL 投机唯一候选=k6（LUZ045 §78 num_nextn=3→k∈{3,6} 硬约束+γ 扫 FROZEN=CD1）；k6 首武装=新形**另立臂卡过六问**，不与 O13B 分幅件混靴（分靴落证律）（O13B §五）。

## §g 冷缓存注记

- 四机本地盘（无 NFS 面；01 home/02 /data+home/03/04 /data）——权重冷读=本地盘流。
- 首靴冷缓存纪律：步墙 75.0ms 结构门（同 0731 线法）；**mm 足迹不归还 ~38G 前科**=600k 形最高风险面（线性叠加 96.8+38≈134.8G 破 121G 上界推演）⇒ 认证负载全走纯文本+mm 批 T61 谓词律拒入或专项首靴实测（memguard 6G abort 线在位）（O13B §四）。
- OPEN-12 教训位（step④ 长混排引擎楔死）已由 VLW3B 池重裁形化解（T13 §一注：池重裁形下全绿）——留档不改判。

## §h C24-4.8M-VL 形条目（2026-10-06 案头预登记；§d 7.2M 记录不动）

- **形=C24-4.8M-VL**：池 `--max-total-tokens 4,800,000`+ctx 600000+mrr 12（SPEC=0 无草稿，同值=两线同形纪律）——设计点=**CTX600k×8 并发恰等**；mrr 与池解耦共存同 0731 线（DOCTRINE §三）。
- **boot**=`dev/c24-compat48m/boot_mvl_600k_48m.sh`（基=logs/T17-20261006/boot_mvl_600k.sh=O13B e457e564 修正版内容；断言同步=池 4800000+指纹带 [4,704,000,4,896,000]（VL 自推 8,847,616 楔死前科值显式拒防）+chunk4096 断言钉+DRY-RUN 段；overlay 28 件挂载面零改）；臂 env=O13B1-VL-SEG65536.env 19 键零改。
- **KV 账（每机）**：4.8M×7,086.75B=**34.02G**（7.2M 形 51.02G→**释放 17.01G/机**）；静态自洽 34.02+42.0=76.0G<108.9G 帽。
- **水位地板缺省**=**32,768**（4.8M 重推导：基线谷 17,847MiB（O13B K5 水位谷=16384 重钉法源读数）+池缩释放 16,219MiB=预测谷 34,066−1G→1024 倍数下取整；首靴实测重钉同法）。
- **靴 1 水位事件+重钉终值（C24 靴2 实测闭值 2026-10-06）**：首发引擎面全绿但水位断言红（head 32,367M<32,768M；预测谷 34,066 偏乐观 ~1.7G）→§九裁定 3 落地覆写 **16,384** 重靴（先靴后钉，窗内一次为限）；主电池（非 mm 面）实测谷 **32,678M** ⇒ **水位终值=30,720**（谷−1G→1024 倍数下取整；vlimg 碾降相=OPEN-26 事故面不计入地板语义——C24-VERDICT-20261006 §四）。
- **池构成六元组（4.8M 实测）**：full 4,800,000/swa 480,000/c4 1,200,000/c128 37,500/**c4_state 15,000（SPEC=0 环 8）**/**c128_state 1,664（环 128）**（两靴同值 delta=0；CAPACITY-MRR12 §3.3）。
- **SPEC=0 口径注记**：7,086.75=SPEC=0 形系数（无草稿项、环减半）；K6 臂武装时系数切 SPEC 形（~7,939.19 级）+实配合计增量 +~6.2-6.8 GB/机+水位地板重推导义务——**7,086.75 不得跨口径引用**。
- **自推浮带注记**：VL 自推三读数 8,516,352/8,763,392/8,847,616（avail 56.36/57.99/VLW3 形 GB(log) 驱动，同形漂 ±1.5-3.9%）——自推不可作锚；靴脚本 fail-closed 拒防（8,847,616=楔死前科值显式带外自检）。
- **mm 侧瞬态控制面（OPEN-23 家族，INCIDENT-20261006-T17VL-OPEN23）**：chunk4096 断言钉+mm 批默认拒入沿 T17 C3（T61 谓词；K-mm 未闭账）+UMA 靴窗中止门 4G；流式数据处理落点与设备侧哨兵（S1-S5）=C24-DOCTRINE §二（工程落位待 OPEN-23 深因卡派单）。
- **mm 面终态（OPEN-26，2026-10-06；翻案裁定 78b3858）**：vlimg 段九项 200 后 ~22G/机四机同步崩落楔死=**池余量假说证伪**（4.8M+四件防护全开复发）——真身=**设备侧（UMA 可见）mm 前向不归还足迹的事件性跳变**（host 面全链 A 级排除；B 段四机跨度 0.67G=每 rank 同构；与 KV 池正交维持）；**VL mm 全相位停飞**待 MM-TRANSIENT（修复路由=件2 ViT/嵌入流式分块主修+新增件7 分配器卫生〔empty_cache+设备侧足迹账本；expandable_segments=True 永禁〕+件6 账本只计 host 驻留；VL 长跑可用性=件2+件7 落地前不可判）；非 mm 面=C24 靴2 已认证（C24-VERDICT-20261006 §三）。
- **状态**=C24 靴2 非 mm 面已认证+mm 面 OPEN-26 停飞挂账（窗卡=docs/taskcards/C24-COMPAT48M-WINCARD-20261006.md；GSM8K 0.93 双杠沿 534647c 冻结线实测过；exact-65536/AGG 扩展档=FAULT-ABORT 缺口在册不补跑）。

——models.d 注册表·v4-vl-exp / 2026-10-06（案头零集群；誊录自 T13+O13B+GOV-CARD；§h=C24 追加）
