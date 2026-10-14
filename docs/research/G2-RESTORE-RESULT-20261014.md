# G2-RESTORE-20261014 — 收官窗结果档（镜像分裂定谳+0731 复测+产线复原+网关验证）

- 窗性：boot 执行窗（停机保持态继承；四机零容器/8898=8899=000 开窗亲证）。
- 法源：任务书 G2 收官窗（主会话）+docs/research/MATRIX-REGRESSION-0731VL-20261014.md（93d47ef）
  +TRIMODEL-MATRIX-RESULT §4（d902c5f）+GW-INFRAS-QUALITY-AUDIT §七验证窗卡（2acc7f3）。
- 执行序实绩：S1 镜像分裂定谳（重大翻转）→S2 0731 复测 **GREEN（塌陷消失定谳）**→S3 VL 抽验
  **GREEN（112.9 深带内）**→S4 产线复原 **GREEN**（OUTAGE 收口：00:19:46Z→07:45:33Z 共 445min）
  →S5 网关修复+V1-V5 **全绿（413 缺陷 rc3.8.4 窗内修复合并）**→S6 本档。
- 沉降律④全守（epoch 链：bake R3 05:57:37Z→S2 拆 06:30:30Z→S3 拆 07:06:53Z→S4 起 07:37:03Z，
  靴间 ≥1800s 逐门亲证）；slotlock 全靴；02 守护零触碰；sudo 管道式（~/.sudopw）；git tag
  零动作（主会话专属律遵守）。

---

## §一 S1 镜像 digest 分裂「修复」——定谳级翻转（分裂=形态差非内容差）

### 1.1 任务面与现态

任务书预设：01=0f075735 正确 vs 02-04=80e1ea89 漂移，修复=01 push 新 tag→02-04 pull 重钉。
四机实核（06:14Z）：01（containerd snapshotter 形）main-79cafec0 RepoDigest=sha256:0f075735…
（image ID=0f075735a6bf=索引 digest 显示形）；02-04（overlay2 经典形）digest=sha256:80e1ea89…
（image ID=b9cb6d00b677=config digest 形）。四机 docker 29.2.1 同版，存储驱动差=01 独异面的
形态学解释位。

### 1.2 执行与证据链（三步定谳）

1. **01 push 复推实验**：`docker tag nightly-dev-20260929-79cafec0 → main-79cafec0-pinned-0f075735`
   → push（全 70 层 already exists）→ **产出 digest=80e1ea89 逐字=「漂移」digest**；docker Info 行
   原文：「Not all multiplatform-content is present and only the available single-platform image
   was pushed / 0f075735→80e1ea89」——单平台复推必然扁平化：push 从本地镜像 config+层集重建
   manifest，其 digest=80e1ea89 ⇒ **01 本地内容=registry 现 tag 内容=02-04 内容**（sha256 决定
   字节的数学级证据）。
2. **registry 取证**：manifest 0f075735=MANIFEST_UNKNOWN（原 index 已被覆盖后 GC）；80e1ea89=
   OCI 单平台 manifest（config=b9cb6d00b677/70 屄/mediaType=oci.manifest）。
3. **01 containerd 内容库原文提取**（sudo 管道式）：blob 0f075735（sha256 校验全等，1611B，
   `application/vnd.oci.image.index.v1+json`）四子件：amd64=a294d9d4…、**arm64=80e1ea8979c5…（逐字
   =「漂移」digest）**、attestation×2。⇒ **原 index 的 arm64 子 manifest 就是 80e1ea89**。

### 1.3 定谳与处置

- **定谳**：四机 main-79cafec0 内容**逐字节同一、从未漂移**。「digest 分裂」=index digest（01
  containerd 拉取记 RepoDigest=多平台索引）vs 子 manifest digest（02-04 经典 docker 在 tag 被扁平化
  重推后拉取记 RepoDigest=单平台 manifest）的**显示形态差**。tag 扁平化重推事件（内容保持）发生
  在 01 原拉取之后、02-04 拉取之前，时点不可考（registry 无 tag 历史面）。
- **对回归案的影响**：TRIMATRIX §4.2「四机不同内容混跑 TP4」前提**根因级排除**；93d47ef H1
  （镜像内容漂移）在被 S2 复测检验前即被 S1 排除（叠加 S2 GREEN 后 H1/H2 双排除，见 §二）。
- **处置（按定谳修正原方案）**：①02-04 零动作（内容本就正确；「漂移改名留档」撤销=不做伪档）
  ②01 零动作 ③registry 留档 tag `main-79cafec0-pinned-0f075735`（→80e1ea89，本窗 push，可追溯锚；
  名注 0f075735=digest 追溯位实指其 arm64 子内容）④index 复原不可行注记：registry 内其余三子件
  （amd64+attestation×2）404 全 GC，复原需 amd64 子件及其 blob，docker.io 不可达。
- **再犯防护（G1 门修正建议）**：未来镜像身份核对改用「arm64 子 manifest digest（80e1ea89）+
  config digest（b9cb6d00b677）+容器内 cid」三级对表，**禁用 index/子形态 digest 混比**（本窗
  教训：容器内 cid 对表〔TRIMATRIX S3 G1 已行〕比 RepoDigest 显示更不可欺）。

---

## §二 S2 0731 回归复测——**修复定谳 GREEN（塌陷消失）**

### 2.1 形与执行

定板形逐字（TOOL-ANCHORS RATIFY-CG 行）：STD0731-CG-R1.env（bdfd9590 亲核）+boot_m0731_uv.sh
（RATIFY-CG 本尊）+定板全参（WATER 6000〔用户 10-14 放宽裁定沿袭〕/池 pin 7103136/MF 0.89/
`--cuda-graph-max-bs-decode 8`）经 slotlock（ARM_TAG=G2R2-0731）。沉降律④过门（距 bake R3 拆靴
2402s）；boot rc=0/8898=200/池 6974464∈pin 带 ±2%；四查绿。

### 2.2 塌陷点四点读数（sd_bench 统一量具；5 发中位）

| 点 | 读数（5 发） | 锚/带 | 判 |
|---|---|---|---|
| prose c1 | **80.93**（80.13-81.06 超紧带） | 81.22 ±3%＝[78.78,83.66]（Δ=−0.36%） | **带内 GREEN** |
| code c1 | **123.26**（122.9-123.35） | 123.21 ±3%＝[119.51,126.91]（Δ=+0.04%） | **带内 GREEN** |
| structured c1 | **136.0**（135.92-136.23） | 塌陷参考 42.75（0731 无锚） | 恢复（3.18×塌陷值） |
| structured c8 | **79.21** per / **564.01** agg | 塌陷域 [1.97,3.27]；锚 prose c8 32.99 | **塌陷签名消失**（agg 满线性） |

步墙定谳补证（teardown 引擎日志 40 decode 行反推）：**bs1 graph 档步墙中位 46ms**（锚 50ms/
塌陷 ~150ms）+**bs7/8 graph 档 75-170ms 域**（锚 117ms/塌陷 1544-1763ms）——93d47ef §1.3 塌陷
载体（decode 回放步墙中毒）**完全消失**。

### 2.3 归因裁定（如实面）

- 塌陷消失与 S1「镜像修复」**无因果链**（S1 证内容零变化）；env/参数/检查点面本窗零变化
  （同 bdfd9590 定板形逐字、A9 CFG 同锚）。⇒ 塌陷因子=**窗内瞬态**：10-14 01:28-04:20Z 四靴
  持续在位，06:22Z 靴消失；中间事件=VL 靴（04:50-05:13）+BAKE031R3 验靴（05:43-05:51）两轮完整
  boot/拆链+多轮 drop_caches。真因未定位（**未定瞬态因子**），H1（镜像漂移）/H2（24 键 env×
  adapter 交互）双排除。呈报主会话：0731 形读数已回锚域可放行使用；瞬态因子不可复现性=后续
  观察位（若再发=新窗新证据链，非本窗遗留）。
- 判读器勘正 1：lib.sh `de_read` 局部变量行一行式吞并 python3 → 判读读数空串 → 假 RED（数据面
  无损）；修复后离线复判=GREEN（同一 JSON）。JUDGEMENT-LINE 双行留痕（RED 假行+GREEN 复判行）。

---

## §三 S3 VL 单点抽验（保险位）——GREEN

- 形：VL40EXP-R2-C24T（arms/VL40EXP-R2-C24T.env 8a8154a4 亲核）+boot_mvl40exp_r2.sh+v4vl
  overlay 复原树，经 slotlock（ARM_TAG=G2R3-VL）。沉降律④过门（距 S2 拆靴 2183s）；boot
  07:00:37Z rc=0/8898=200/池 4800000 pin 带判绿四查绿。
- 单点读数：**structured c1=112.9**（5 发 111.34-113.37）对 c1 级锚 112.68（TRIMATRIX G4 出典）
  **+0.2%，±15% 容带 [95.78,129.58] 深带内**——保险位过（镜像面统一后的逻辑等效复证；亦与
  TRIMATRIX S3 全矩阵 structured c1 112.83 同域互证）。判读 JRC=0 GREEN；拆靴净（07:06:53Z
  epoch 落账，四机零容器/8898=000 亲证）。
- 对照意义：S2（0731 raw-image 链）与 S3（VL overlay 链）同窗双绿=回归因子确已整体消失，
  「0731 链独有暴露面」的形间差异不再表达（与 §二归因「未定瞬态因子已消失」自洽）。

---

## §四 S4 产线复原（停机窗收官）——GREEN

- 形：51 键终值形（ENV51 `PROD-R51W5FL6-spec1.env` md5 2ac74586/51 键亲核+DSV41_FL6_RECALL_FIX=1）
  +SPEC6 六参+overlay o12c1-prod（r3-boot-arm 原生挂载块）+sitecustomize 55b1e412/fl6 b87cbb5e
  现役件面，经 slotlock（ARM_TAG=FINAL-Restore，CTN_PREFIX=r3prod:8899）。
- 沉降律④过门（距 S3 拆靴 1843s）；boot 07:37:03Z→**rc=0/8899=200（07:45:24Z）**。
- 四查全套绿：up=200/**banner29=29**/**池 max_total_num_tokens=9600000**/swa sizing（mode=cap
  swa_tokens=125440/prefix_tails=256）/**R1 fail-safe dual-run PASS（rows=96 bit-equal）**/
  mismatch=0/**chunked_prefill_size=4096**。
- fl6 横幅：四机 tree_core_patched=2/swa_patched=2/drift_refuse=0（4×2 全）。
- printenv 四键×4：四机全 O12SCHED=1/R1INK=1/FP8=1/TG=1/FL6FIX=1。
- smoke 3/3 绿（北京 temp0）；memcg preboot/postboot 双绿。
- 终核：8899=200/8898=000/r3prod 四机=4/r3boot 残=0。
- **OUTAGE 台账收口：START=2026-10-14T00:19:46Z（TRIMODEL S2 停产）→END=2026-10-14T07:45:33Z
  （S4 复原终核绿），持续 445min**（logs/G2-RESTORE-20261014/state/OUTAGE.tsv）。

---

## §五 S5 网关生产验证（V1-V5）+在役三项修复+rc3.8.3→rc3.8.4 吸收

### 5.1 修复面（先修后验；判读线=2acc7f3 §七冻结块）

| 项 | 动作与核验 |
|---|---|
| rc3.8.3 吸收 | /opt/aicad-prod/scripts+~/gateway-migration-staging/proxy 双拷贝 9cf978d2（旧 e1a01162 废止）；py_compile 绿；sources.tsv 同日重钉 |
| A1 | 主 unit `Environment=CHUNK_IDLE_TIMEOUT` 180→600（备份 .pre-A1A10.bak）；进程 env 亲核=600 |
| A8 | 包件 10-gateway-hardening.conf 落 v2.service.d（md5 对表）；ProtectSystem=strict/NoNewPrivileges=yes 生效亲核 |
| A10 | GW_API_KEY 轮换 14→47 字符（/etc/default/concurrency-proxy-v2 内改值；0600 保持；旧值废止于 01 面）。**实态注记**：unit 文件实读零 GW_API_KEY 行（值位本就在 EnvironmentFile）——审计 D5「值在 unit」表述与 §0.1/实态不符，本窗按实态执行=轮换+域核，「迁出 unit」面=已在位零动作 |
| **rc3.8.4**（窗内新修） | V2b 413 判读线缺陷：dispatch 兜底 except 吞 aiohttp HTTPException（64MiB client_max_size 帽）→错译 500〔journal traceback :791 实证〕；修=`except web.HTTPException: raise` 透传；包源改件+三联动重钉（MANIFEST/VERSION 0.3.2-gwfix2 指纹 f8322934/TOOL-ANCHORS 同日行）+在役吸收（f0a47b17 双拷贝+双实例 restart）；复测=**413/0.0s 零挂死** |
| restart 瞬断窗 | [07:50:30,07:50:37]Z（rc3.8.3+A1/A8/A10）+[08:06:53,08:06:59]Z（rc3.8.4）；产线 8899 不受触（网关层动作） |

### 5.2 V1-V5 逐面判读

| 面 | 读数与判读 |
|---|---|
| **V1 并发压测面 GREEN** | 8001 梯 8/16 全 200；N+1=17 并发（非终止提示词 2000 tok 持槽）→**16×200+1×429（Retry-After=30）**；8002 梯 4/8 全 200+9 并发→8×200+1×429（Retry-After=30）；queue_wait_peak=4.87s<5（8001）/3.08s<20（8002）；收尾 active_streams=0；queue_full_drops=0；rejected_429_queue 计数与注入对账（0→1）。初轮自然 EOS 提前释槽致 N+1 未触发（勘正 3=补正件 V1b 非终止提示词重梯闭合判读线） |
| **V2 VL 大 body 面 GREEN 带瞬态注记** | 1/4/16MB 全 200（TTFT 0.32-0.55s）；RSS 终峰 115MB≪1.5G；64MB 档一次瞬态 502=陈旧池化连接竞态（**不复发**：复跑 4/4 200+阈扫 24-60MB 六档全 200+裸 aiohttp 直打 61.4MiB 200+journal 定因 ClientOSError(32)；机理=relay_plain 非流式路径无建连重试面——改进候选 C6 登记）；真 413 档（68.7MiB>67,108,864B）=413/0.0s（rc3.8.4 后）；内容级对照 choices/usage 逐字同（via=direct=『灰色』；id/created=请求性字段不计——勘正 4=初轮全文哈希对照法把请求性字段卷入误判不等） |
| **V3 故障注入面 GREEN（五件全过）** | 钻孔代理（systemd-run 瞬态单元 8017→8898 死上游，零产线触面）：死上游 GET=502 毫秒级；POST 流=错误帧+[DONE]（无静默截断）；30s 观察窗 6 发 GET 全 502；假上游（dummy_upstream.py）复起自愈 GET=200+POST DONE=1；journal 成因类 WARNING 8 行（A6 修复面实证）；清理净（8898=000） |
| **V4 时延对照面 4/5 GREEN+1 带外项** | 文本：小档 ΔTTFT=−4.21ms/Δtotal=−1.53%；76K 档 +1.74ms/+0.46%；500K 级档 −28.72ms/−3.58%（负增量=网关侧更快，带内噪声）；图像 1MB 档 0.01ms/−0.01%；**图像 16MB 档 +24.8ms/+7.03%=带外项呈裁**（机理=16MB 字节物理三遍：request.read+sanitize 扫+body_key 全量 sha256〔B1 治本代价〕+aiohttp 写；gwtest B3 rc3.3 先例 +31.7ms 同量级；B2 预检不涉案=对照 body 无 stream 键 rc3.4 预检已在役；改进候选 C7=DEDUP=0 车道跳过 body_key 计算，呈裁不盲改）。读数口径注记=3 发中位全暖路径（radix 缓存公平化交错） |
| **V5 观测复证面 GREEN** | /metrics 经 8001=200（Prometheus 靶复绿）；双实例 /gw/metrics 全计数族落档（rc3.8.4 版本串）；dedup 阳性对照：并发同 body 双发 A=200/B=429（Retry-After=60）、rejected_429_duplicate 0→1（**C2 裁定依据成立=dedup 在役可触发可对账**）；queue 计数与压测注入对账；queue_full_drops=0 |
| **终态面** | gw-health 8001/8002=200/200（新钥 Bearer）；文本冒烟 8001=北京（rc3.8.4 后复走）；图像冒烟 8002=灰色+usage.image_tokens=382；8001/8002/8899 终态全 200 |

### 5.3 遗留与呈裁位（如实注记）

- **C6**（新立）：relay_plain（非流式）路径无建连级重试面（流式路径有 RETRY_CONNECT）——
  陈旧池化连接竞态窗内一次 502 的机理位；低频（窗内 1/数十发）。
- **C7**（新立）：DEDUP_ENABLE=0 车道跳过 body_key 计算（16MB 全量 sha256 ~10-15ms 纯浪费面）。
- **C2 承接**：dedup 阳性对照已立（可触发可对账）——裁撤 vs 治本保留的裁定依据齐。
- 交付仓同步需求（主会话承载）：0731 修复后终态读数行（80.93/123.26/136.0/79.21 四点）+
  网关在役面注记（rc3.8.4+A1/A8/A10 落位+GW_API_KEY 已轮换——交付仓模板值位空注记不变，
  01 在役值不外泄）。

---

## §六 勘正台账与披露

1. **勘正 1（判读器 bug·假红）**：lib.sh `de_read` 局部变量行一行式吞并 python3 调用→判读
   读数空串→S2 初判假 RED；数据面无损（bench JSON 五发全在），修复后离线复判=GREEN
   （JUDGEMENT-LINE 双行留痕）。
2. **勘正 2（三联动顺序）**：rc3.8.4 首序在 regen-manifest 后改 sources.tsv→指纹漂移 selfcheck
   RED=2；按正确序（内容全改毕→regen→VERSION 重钉→TOOL-ANCHORS 同步）重做后 OK=16 RED=0。
3. **勘正 3（V1 判读面）**：初轮 V1 用自然 EOS 提示词（「数到 100」提前收束释槽）→N+1 未及
   队列超时；补正件 V1b 非终止提示词（2000 tok 持槽）重梯→429 判读线闭。
4. **勘正 4（V2 对照法）**：初轮「逐字同」用全文哈希对照把 id/created 请求性字段卷入→必然
   不等；修正为内容级对照（choices+usage）=逐字同。
5. **披露（V2 瞬态 502）**：64MB 档一次 502（陈旧池化连接竞态）不复发（4/4+六档阈扫+裸
   aiohttp 直打全 200），journal 定因在档；改进候选 C6。
6. **披露（V4 带外项）**：图像 16MB 档 +24.8ms/+7.03% 超冻结线（5ms/3%）——字节物理机理
   归因+先例对表在 §5.2；呈裁不盲改（C7）。
7. **披露（S1 处置偏离原方案）**：原任务书方案（02-04 pull 新 tag+漂移改名留档）按定谳
   撤销——内容同一则不做伪档；registry pinned tag 留档为可追溯锚。
8. **披露（warm 步 400）**：S2/S3 warm（64k probe）在 0731 形撞 admission CTX_CAP 65536 边界
   400（形属性先例同源），rc=1 如实记；bench 点自热承载，读数不受影响。
9. **披露（A10 实态修正）**：审计 D5「值在 unit」与实态不符（值在 EnvironmentFile）——按
   实态执行轮换；Mac 实例自有钥（mac-deploy staging 副本持有旧值）=Mac 侧自载面，01 轮换
   不影响 Mac 实例自身 /gw/*（其钥独立），但**同值复用卫生注记**呈报主会话。

## §七 commits 与交付

- 本档 commit（S6）：docs/research/G2-RESTORE-RESULT-20261014.md+logs/G2-RESTORE-20261014/
  run.log（-f；窗档工件 logs/G2-RESTORE-20261014/ 全量入档）。
- 关联在役/包面变更（同窗承载，随本档 commit）：tools/packages/gateway/（rc3.8.4+
  MANIFEST/VERSION/sources.tsv 三联动 f8322934）+docs/TOOL-ANCHORS.md（gateway 行同日重钉）。
- 交付仓增量（主会话验收后编排，本窗零交付仓动作）：§5.3 所列两件。

——G2 收官窗执行代理 / 2026-10-14（boot 槽停机保持态继承；完报后交棒主会话验收）
