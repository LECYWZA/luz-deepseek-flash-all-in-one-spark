# VL-NATIVE-RESULT-20261013 — 路径 B 开窗结果档（SGLang 基座原生 V4.1 视觉 + V4.0exp overlay 复原）

> 窗卡=docs/taskcards/VL-NATIVE-WINCARD-20261013.md（d21afc8，S0-S7 全序承载）。
> 状态：**收窗**（S0-S7 全序完 21:24Z；产线 51 键形复原在役 8899=200 亲证；本档=终钉）。
> 执行窗代理=VL-NATIVE 槽（boot 槽 OUTAGE 制；开窗 17:16Z 停产→21:13Z 复原点火）。

## §一 执行时间线（run.log 同源）

| 时点 | 事件 |
|---|---|
| 17:16:05Z | OUTAGE-START（S1 停产：r3-stop 四机净+8899=000；pre-stop logs×4 存档） |
| 17:46:57Z | 沉降律④过门（停产 epoch+1800s；含主会话 17:23:52Z 裁定门） |
| 17:47-17:48Z | S3 首靴红（快败 90s=Mxfp4 576 对齐墙；勘正 2 承载） |
| 17:49-17:57Z | S3R 重靴 UP（C24「先靴后钉」立即重靴先例；窗内一次） |
| 17:58-18:02Z | G-V1[L1] 全绿（图像首飞=V4.1 原生线） |
| 18:07Z | S4a 拆 L1（四机净+双口 000）→L2 门=18:33:59Z |
| 18:34-18:44Z | S4a L2 k6 靴 UP rc=0（18:34 点火）+G-V1[L2-k6] 轻量全绿→拆（L3 门=19:14:12Z） |
| 19:15-19:24Z | S4b L3 k6+CG 靴 UP rc=0+G-V1[L3-k6cg] 轻量全绿+CG bs16 直证→拆（S5 门=19:54:37Z） |
| 19:54-20:00Z | S5 VL40EXP 首靴=量具断言红（引擎全绿 health/pool/水位；勘正 4 承载）→cleanup rc=9 |
| 20:30-20:38Z | S5R 重靴 UP rc=0（沉降门 20:30:28Z 全守）→G-V5 全绿（V4.0exp 图像面首飞正式读数） |
| 20:38-20:43Z | S6 网关 VL 车道部署毕（env 0600+unit md5 对表+enable）→五探针+车道断言+端到端+开合 全绿；勘正 6（部署量具形缺陷瞬态口令残留→即刻净化零残留） |
| 20:43-20:45Z | S7 拆 S5R VL 靴（四机日志存档+D8 三查 PASS 四机 0/双口 000）→生产复原门=21:13:26Z |
| 21:13-21:21Z | S7 生产复原靴 VLNATIVE-S7 rc=0（r3prod/ENV51/SPEC6/池 9600000）→G-V4 全绿 |
| 21:22-21:24Z | G-V4 终面：DE c1=127.71（带外高侧呈裁）+printenv 四面 ×4+水位终面 WATER-RED=0+双口 8899=200/8898=000——**窗 S0-S7 全序完** |

## §二 四门读数

### G-V1 VL 冒烟门（L1=V4.1 原生 SPEC0/GRAPHS0 首靴；bench/gv1-L1.*）

| 用例 | HTTP | 语义判 | image_tokens | 备注 |
|---|---|---|---|---|
| knapcio 双形状（3024×588 红圆左+蓝方右） | 200 | **OK**（red/circle/blue/square+左右次序全中） | **1024/1024 SAT**（满额断言精确命中） | 跨栈语义=knapcio boot.py 同断言集（G-V2 面承载） |
| 官方 2 图对（carrots+corn） | 200 | OK（胡萝卜/玉米+食用部位） | 633/2048（动态计费带内） | |
| s3 OCR（digits 742） | 200 | OK（"742"） | 206/1024 | |
| d2 双图计数（2/5/多 3） | 200 | OK（2 根/5 根/多 3 根=跨图计数） | 412/2048 | |
| 文本 canary ×3 | 200 | 3/3 北京 temp0 | — | mm 靴文本面自证 |
| **门判** | **绿** | sem_red=0 | 满额+带内双面全过 | 勘正 3=断言语义分面（饱和图==cap/动态图带内） |

（L2/L3 轻量复跑+V4.0exp 臂读数回填位）

**L2（k6+GRAPHS0；18:34-18:44Z）**：G-V1[L2-k6] 全绿——knapcio 1024/1024SAT 语义 OK
（逐字同 L1 答案）+官方对 633 语义 OK+canary 3/3；server_args 直证
speculative_algorithm=DSPARK+num_draft_tokens=6+SPEC6 六参全在位（prefill_decode_interval
16/max_queued 32/min_free_slots_delay 1/decoder_swa_bounded_replay True/reasoning_parser
deepseek-v41/swa_prefix_tails 256）+disable_cuda_graph True+池 9600000+mm 三直证四机全绿
（boot-checks/mm-direct-VL41N-K6.txt）。**mm×k6 共面=R2 风险面首证绿**（target_verify
结构性豁免=§1.1 案头定谳的动态闭合）。件7 设备足迹：L2=90,847MiB/机（vs L1 86,489
=draft 模型增量 ~4.3G，无事件性跳变）。

**L3（k6+CG bs16=生产 serve 参数面全量等价形；19:15-19:24Z）**：G-V1[L3-k6cg] 全绿
——knapcio 1024/1024SAT+官方对 633+canary 3/3；`cuda_graph_max_bs_decode': 16` 直证
+池 9600000+mm 三直证四机全绿（boot-checks/mm-direct-VL41N-K6CG.txt）。**S4 阶梯
SPEC0→k6→k6+CG 三级全绿=mm×k6×CG 三共面（R2 风险面）闭合**；L3 形=生产参数面逐字
等价（boot 脚本 L3 全量等价核绿）=「转正后 8899 图像开放 serve 面与今日逐字相同」的
动态预证。件7 足迹 L3=93,148MiB/机（CG 增量 ~2.3G，无事件性跳变；OPEN-26 家族
形态=零）。

### G-V3 工程接线直证门（L1 靴；boot-checks/mm-direct-VL41N-S3R.txt）

| 直证项 | 读数 | 判 |
|---|---|---|
| mm 后端 triton_attn 两行 | 四机逐机 notset=1+using=1 | 绿（生产同款） |
| mm KV 0.10G 预留 | 四机逐机=1 | 绿 |
| processor 扫描 | 四机逐机≥1（mimo_v2 ignore=已知无害） | 绿 |
| 图像 token 计数带 | 见 G-V1 表+prompt_tokens 增量≈图 token | 绿 |
| mm 能力面 | /model_info has_image_understanding=true | 绿 |
| 池指纹 | max_total_num_tokens=9600000∈[9408000,9792000] | 绿 |
| 网关路由命中 | （S6 回填） | — |

### G-V4 回归哨兵门（S7；boot-checks/VLNATIVE-S7-fourcheck.txt + bench/VLNATIVE-S7/）

| 查项 | 读数 | 判 |
|---|---|---|
| 8899 四查-banner | banner29:4（head 横幅面） | 绿 |
| 8899 四查-池 | max_total_num_tokens=9,600,000 | 绿（生产指纹复位） |
| 8899 四查-R1 | fail-safe dual-run **PASS (rows=96)** head+三 worker 各 1（×4）；MISMATCH=0 | 绿 |
| 8899 四查-chunk | chunked_prefill_size=4096 | 绿 |
| fl6 横幅 | tree_core patched + swa patched（mode=both）四机 ×2 行全 | 绿 |
| smoke 3/3 | 北京 temp0 ×3（8899 产线 smoke 一次先例例外） | 绿 |
| DE c1（--type code） | **per_med=127.71**（125.72-127.92 五发紧带）vs 锚带 [76.9,80.0] | **带外高侧=增益向非回归向，呈裁不停窗**（锚=R1CERT4 G5 旧认证态 79.19=前 W5-FP8/FL6/SWA-tails 时代；四查+池+smoke 全绿佐产线健康） |
| 51 键 printenv ×4 | FP8 族（DRAFT_HEAD_FP8=1+PREFILL_SP_FP8=1）+TG=1+R1INK=1+FL6FIX=1 四机全 | 绿 |
| 双口终核 | **8899=200 / 8898=000**（+8001=200 v2 文本车道；8002=502=VL 车道认证期自然态〔上游 8898 拆线〕，转正切 8899 即复 200） | 绿 |

### 水位门（全窗）

- water-10s 带：**WATER-RED=0 全窗**（17:16-21:24Z）；产线在役终面四机 MemAvailable
  11.6-14.4G ≥floor 6000；VL 靴期各段水位读数在 run.log/各 boot log。
- mm 足迹哨（F7 J6）：件7 设备账本 mm-footprint.tsv 全程（L1 86,489/L2 90,847/L3 93,148/
  S5R pre 82,972→post 87,557→steady 87,557 MiB/机）；**>8G 拒新 mm 即停窗=零触发**。

## §三 V4.0exp 臂（S5；boot-checks/VL40EXP-S5R-boot.log + mm-direct-VL40EXP-S5R.txt + bench/gv1-S5R-v40exp.*）

- **overlay 复原**：28 件整树自 archive-20261012/MANIFEST.csv:5 名单律复原→
  ~/migrate-assets/vl-native/sglang-overlay.v4vl-79cafec0（VL 专用新目录；o12c1-prod 零触碰；
  归档区只读取件）→四机 rsync 同步，正典集合指纹 **cbf986df×4 全等**（三件 post-L0 活件
  vs 旧清单 pre-L0 md5 差=披露 4；backend 锚 4d7c6d2c 直核）。
- **S5R 靴**（20:30:40 点火，沉降门 20:30:28Z 全守）：rc=0——池 **4,800,000**∈
  [4704000,4896000]+ctx 600000+mrr 12+四机水位 23.5-23.9G≥20480+mm 直证绿
  （**头位分面**：head kv010=1/processors=2/concurrency=1+三 workers kv010=1/processors=1；
  concurrency 行=head 侧 tokenizer-manager 专属行〔勘正 4〕；triton 两行=overlay 形
  0 命中不设断言=mm 注意力走 dsv4 后端）。首靴 19:54 量具断言红非引擎红
  （引擎全绿被误判=cleanup；勘正 4 量具修正后重靴）。
- **G-V5 首飞读数**（384/图 政策；bench/gv1-S5R-v40exp.jsonl；20:36-20:38Z）：全 200 语义对
  +canary 3/3：

| 用例 | HTTP | 语义判 | image_tokens |
|---|---|---|---|
| knapcio 双形状 | 200 | OK（red/circle/blue/square+次序） | **340/384**（预算内动态计费） |
| 官方 2 图对（carrots+corn） | 200 | OK（胡萝卜肉质根/玉米籽粒） | 420/768 |
| s1 红圆（自建） | 200 | OK（红色的圆形） | 207/384 |
| s3 OCR 742（自建） | 200 | OK（答形「7, 4, 2」=742） | 206/384 |
| d2 双图计数（自建） | 200 | OK（2/5/多 3 跨图计数） | 415/768 |
| 文本 canary ×3 | 200 | 3/3 北京 | — |

- **384 政策判定**：全用例预算内动态计费（大图 knapcio 340<384=resize-into-budget 形非
  帽满；与 V4.1 1024 政策的帽满计费不同形——不跨模型对表数值只对各自政策，窗卡 §五
  满额断言注记承载）。量具勘正 5：judge_seq 分隔容形+--no-sat 面（commit b56ea1b）。
- **足迹三账本**（F7 J6/L0RETRY J4-J6 冻结线）：①件6 host 水位 10s 带 WATER-RED=0
  全窗；②件7 设备账本 mm-footprint.tsv：pre 82,972→G-V5 后 87,557→steady 87,557 MiB/机
  （mm 载入增量 ~4.5G 后稳态零增长=无泄漏形态；>8G 拒新 mm 即停窗=零触发）；③
  image_tokens 读数账本=bench summary.json（5 用例全读数在档）。

## §四 网关车道（S6；01 机）

- **形态**：第二实例 concurrency-proxy-vl.service（unit=包件 md5 对表落位 bd6fc3e8+
  10-gateway-hardening.conf drop-in 803B）+ /opt/aicad-prod/secrets/gateway-vl.env
  （root:0600；UPSTREAM=8898 认证期/PORT=8002/MAX_CONCURRENCY=8/DEDUP_ENABLE=0/
  GW_API_KEY 值在位零打印——禁入包/unit/镜像/日志红线全守）。
- **判读**（§4.3 两断言+五探针沿袭）：P4 健康穿透 200/P3 直连对照 200/管理面鉴权正证
  （无 key /gw/health+/gw/metrics 均 401+带 key 200）/版本行
  `concurrency-proxy-v2-rc3.8.2`/requests_total 6→12 增量直证（图像探针命中）。
  **P1-auth 红=rc3.8.2 契约设计面**（业务路径不代理鉴权、鉴权=上游 VLLM_API_KEY 负责
  〔concurrency_proxy_v2.py:105-106 契约注记〕；本靴上游未设 key 故穿透 200）非部署缺陷。
- **端到端**：图像请求经 :8002 全绿（knapcio 340/384+官方对 420/768=与直连 8898 读数
  逐字同=车道零内容畸变；bench/gv1-S6-lane-v40exp.jsonl）。
- **车道开合**：停=8002→000+8898 直连 200（隔离亲证）→复起 200。**v2 本尊零扰动**：
  8001 车道 pid 30290 全窗未动（开窗基线=终核同 pid）。
- **勘正 6（部署量具形缺陷）**：S() 函数封装 sudo 管道形在凭据缓存窗内 -S 不消费 stdin
  首行→口令行曾瞬态入 drop-in/unit（15/960B，0644）~60s；即刻覆写净化+三件 grep -F
  口令残留扫描零命中+md5 对表全等；修复形=sudo -k 每次强制消费+install 文件参数位
  （内容不经 stdin）。口令轮换=呈裁位（宿主级凭据非本窗资产）。
- 车道终态=enabled 在档（UPSTREAM 切 8899=转正呈裁位；02 机两守护零触碰）。

## §五 勘正与披露

1. **勘正 1（案头截获）**：V4.1 臂 MODEL_DIR 03/04 初写 dsvl-net（=Vision-Exp NFS），
   预核 sha256 截获后修正为 **dsv41-net**（=V4.1-Flash NFS，cfg 8be45ce0 四机实证；
   commit 1cbe5d5）。
2. **勘正 2（首靴红实证）**：S3 首靴 90s 快败=ValueError Mxfp4FlashinferCutlassMoEMethod
   requires hidden/intermediate multiples of 128（got 5120/576）=SM121 cutlass 128 对齐墙。
   根因=COMMON_ENV 误承 C24 剥离面（缺 DSV41_MOE_B12X_NEXT=1）。修正=COMMON_ENV 换
   **生产启动器公共面逐字**（r3-boot-arm.sh:216-283：b12x MoE/engram pread/FP4KV_PORT/
   SM121 候选对键+/engram 四秩挂载）。「零 DSV41_* 性能键」律辖臂 env（51 键族零注入）
   不变——臂 env 仍 5 约定键。commit ad66e8e/871e3cd。重靴=先靴后钉先例（C24 §九
   裁定 3；败靴未服役态）窗内一次。
3. **勘正 3（量具）**：image_tokens 断言语义分面（饱和图==cap；动态图 0<v≤cap）——
   实测官方对 633/s3 206/d2 412=分辨率动态计费（min_pixels 295936+max 1024 帽政策）；
   commit 44f7b74。
4. **manifest 旧清单披露（S5 复原）**：overlay-md5-manifest.v4vl-79cafec0.txt=10-05 旧
   清单（vit/vl/moe_hash_topk 三件 md5=pre-L0 形=bak-pre-l0 同值）；复原内容=归档树
   **活件**（=后 L0 根治形=STDVL-R2 认证态；backend 4d7c6d2c 认证锚直核全等）。取件律
   =manifest 28 件**名单**对表（防 .bak/optc 混入）+逐件 cmp 全等核。
5. **集合指纹口径**：f26c4888=旧未记录算式产物（gen-manifests.sh 头注「不再复现义务」）；
   正典算式重钉=归档 34 件 b1330d8b/复原 28 件 **cbf986df**（×4 机全等）。
6. **足迹账本口径**：GB10 UMA 平台 --query-gpu memory.*=N/A ⇒ 件7 设备账本用进程表
   C 类行 MiB 合计（mm_footprint_snap.sh；desk 件）。
7. **勘正 4（S5 量具断言头位分面）**：processor-concurrency 行=head 侧 tokenizer-manager
   专属行（首靴 fail-log 实证 head=1/workers=0 引擎全绿）→判读分面=KV 0.10G+processors
   逐机≥1+concurrency 仅 head≥1；commit 277dfef；重靴沉降门 1800s 全守。
8. **勘正 5（G-V5 量具两面）**：judge_seq 数字序列容分隔符（「7, 4, 2」=742 语义对）+
   --no-sat 全用例动态计费判读（V4.0exp 384 政策=预算内动态 340<384 非帽满）；commit
   b56ea1b。
9. **勘正 6（S6 部署量具形缺陷）**：详 §四——瞬态口令残留（~60s）→即刻净化+三件残留
   扫描零命中+md5 对表全等；修复形=sudo -k+install 文件参数位；口令轮换=呈裁位。

## §六 生产零扰动证明（S7 终核）

- **ENV51**：md5 **2ac74586**+51 键（boot 前预核+复原靴用同件）——全窗零触碰；
- **adapter 四件 ×4 机**：prefill_sp 32cf9abf/kv_fp4 feaaadd4/fl6_recall b87cbb5e/
  sitecustomize 55b1e412 全等（boot 前预核）——指纹面零动；
- **overlay o12c1-prod**：29 活件（预核）——VL 复原树独立目录 ~/migrate-assets/vl-native/
  （cbf986df）与 o12c1-prod 零交叠；
- **在役网关 v2（8001）**：pid 30290 全窗未动（开窗基线=终核同 pid）+8001=200 终核；
- **02 机两守护**：全窗零触碰（S6 全部动作限 01 机 unit/env 新件）；
- **产线复原直接复证**：四查全绿+池 9,600,000+smoke 3/3+DE c1 增益向=「VL 窗全程未触
  生产靴」的动态面复证；
- **烘焙镜像 0.3.1**（cid 658a5fe6436510ed）=交付资产位未动未切。

## §七 git 动作表（执行件）

| commit | 件 |
|---|---|
| 7c574f3 | dev/vl-native/boot_mvl41_native.sh（S2） |
| 1ee6f42 | arms/VL41N-SPEC0.env（S2） |
| 9ba903c/0e002c8 | dev/vl-native/vl_smoke_gv1.py（S2 量具+精化） |
| 20efa71/0b76f60 | dev/vl-native/boot_mvl40exp_r2.sh+arms/VL40EXP-R2-C24T.env（S5 预备） |
| 90de528/264c3b8 | arms/VL41N-K6.env+VL41N-K6CG.env（S4 阶梯） |
| 14142c0/2f2be41 | gateway 包 VL 车道 unit+env 模板（S6 预备；重烘焙窗 MANIFEST 重算法=§六窗卡） |
| 1cbe5d5/ad66e8e/871e3cd/44f7b74 | 勘正 1/2/2 续/3 |
| 277dfef/725d68a/b56ea1b | 勘正 4（S5 mm 直证头位分面）/G-V5 s1 例补/勘正 5（G-V5 量具两面） |

## §八 呈裁位

- **VL 形转正在役**（8899 单端点终态+网关车道 UPSTREAM 切 8899+8899 图像开放）=**呈裁位
  不自行裁定**（硬门已达：S4 阶梯三级全绿=mm×k6×CG 三共面闭合+V4.0exp G-V5 首飞全绿+
  双臂足迹账本零事件）；呈裁若过：车道 env UPSTREAM 改 8899+restart concurrency-proxy-vl
  （8002 复 200）+8899 图像开放 serve 面=L3 形逐字等价已动态预证；
- **DE c1 带外高侧**（127.71 vs [76.9,80.0]）：增益向非回归向（锚=旧认证态）；锚带更新
  与否=呈裁；
- **口令轮换**（勘正 6 后续）：宿主级凭据非本窗资产，轮换与否=呈裁；
- **重烘焙窗**（§六窗卡清单：gateway 包两新件〔concurrency-proxy-vl.service+
  gateway-vl.env.template〕MANIFEST 重算等）排程=呈裁；
- FORM-REGISTRY VL 形条目+models.d 两卡（v41-prod/v4-vl-exp）更新=案头面随呈裁承载。
