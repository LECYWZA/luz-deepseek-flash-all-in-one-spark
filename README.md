# LuZ-deepseek-flash-all-in-one

**LuZ-0.3.1** —— DeepSeek-V4.1-Flash @ **4×NVIDIA DGX Spark（GB10，SM121）TP4
内部 RoCE 环网**全栈优化一体化交付（基于 SGLang 上游 `main-79cafec0` 的自有
优化层，许可注记见 [NOTICE](NOTICE) / [LICENSE](LICENSE)）。

---

## 一、三大模型完整性能测试报告（0.3.1 定版读数）

> 全量档=`docs/report/031-FINAL-PERF-REPORT-20261009.md`（v2 定稿）；定型形
> 服务口径读数承接 QA31 定型窗（`docs/quality/0.3.1-RELEASE-QUALITY.md` T2）。

### V4.1-Flash（主模型，0.3.1 定型形=50 键+SPEC6+W5 件；FL6 转正后现役=51 键，DE 82.17 见 §三）

| 指标 | 读数 | 对照 |
|---|---|---|
| **census 步墙（服务口径）** | **626.1 ms/step** | 866 基线 **−27.8%**；≤677 目标（裕度 +50.9）——收口达成 |
| **PR ②尺四档（×3 med, tok/s）** | 8k **5203.7** / 32k **6082.2** / 64k **6126.3** / 128k **5883.3** | 对组合窗 C0 ×3 四档 +0.14/+0.69/+0.60/−0.17% **全部带内（跨窗复现成立）**；128k 发布读数 5880.1 |
| **agg600k 聚合（5×200k 中位）** | **4958.5 tok/s** | 门=3005.2（ctx600k 不劣化绿；段极差 0.5% 稳态） |
| **DE c1 双点位（post 主分母）** | **81.67** | ≥80.0 收案绿（five=[81.58,81.73]） |
| **GSM8K / needle / qeval** | **0.97** / **600k 3/3** / **75/75 逐题全等** | 质量四件全绿 |
| 断言门禁 | 10/10 逐靴直证（16 口 idx3+fail-safe PASS 96 行×4 秩+banner29+池 9,600,000+MISMATCH=0） | WATER-RED=0 |

### 0731 兼容模型（decode-CG 解锁组合，STD0731-CG-R1 形）

| 指标 | 读数 | 目标 | 达成 |
|---|---|---|---|
| prose（c1 ②尺） | **81.22**（复跑 81.07，−0.18% 带内） | 60 | **135%** |
| code（c1 ②尺） | **123.21**（复跑 123.22，+0.01% 带内） | 104 | **118%** |

决定性杠杆=decode-CG 解锁（+79.0%/+73.0%，步墙 75→50ms；pin7103136+mf 0.89+`--cuda-graph-max-bs-decode 8`）。

### VL 兼容模型（STDVL-K6CG-R1 形）

| 指标 | 读数 | 目标 | 达成 |
|---|---|---|---|
| prose（c1 ②尺） | **63.16**（复跑 63.16，+0.00% 同值） | 50 | **126%** |
| code（c1 ②尺） | **112.93**（复跑 113.21，+0.25% 带内） | 90 | **125%** |

杠杆=decode-CG +79.7%/+73.6%（k6 冻结线全过；两模型比率一致=机理同源）。

### 0.3.1 特性构成

R1 FP4-KV in-kernel（八件面）+ W5 stage2 MXFP8/出口直聚（两键）+ E3-A SWA
召回 N=256（SPEC6 第六参）+ O12 调度间隙（三键）+ LL128 NCCL 协议（三键）+
FL6 召回修复（**51 键转正在役定版**，见 §三；FL6 面回退两级=摘键休眠/摘接线）。
键面回退链 51→50→48→47 键四级。

---

## 二、镜像下载（内网 registry 直链）

> registry=`192.168.5.187:5000`（四机可达）。指纹提取法：
> `docker inspect --format '{{index .RepoDigests 0}}' <镜像>`。

| 镜像 | 用途 | 体量 | sha256 指纹 |
|---|---|---|---|
| `192.168.5.187:5000/lmsysorg/sglang:main-79cafec0` | **现役基座**（V4.1+0731 形；运行期注入 adapter/overlay/env） | 48.6GB | `sha256:0f075735a6bf913a7cc1cd7ece4f526ae8af70fc5b88fdc02d9efe92a61cf3ae` |
| `dsv41-sglang-optimized:0.2.9-ep1q2-fin2` | 优化烘焙谱系（0.2.9 现值；ep1u-fin/ep1q2f 前代） | 47.3GB | `sha256:f51d0f2ac9b47adfe4e1052682624ecd7b9ef7dbe20ebf98c4c01b1380f43b8f` |
| `192.168.5.187:5000/vllm/vllm-openai:LuZ0.4.5-DeepSeek-v4-Flash-DGXspark-TP4-Ring-VL-S1-20260910b` | VL 形（vLLM 基座 S1） | 35.9GB | `sha256:0098a90d4e529f82a419b6dbda3e606bb27408358e7daa16f8e25627342c2478` |
| `192.168.5.187:5000/vllm/vllm-openai:LuZ0.4.5-DeepSeek-v4-Flash-VL-DGXspark-TP4-Ring` | VL 形（基线） | 35.9GB | `sha256:357e2f8e36ae4f5523601a2aa6c96933088877046ab14a422f4291dc456f2c12` |

```bash
# 拉取现役基座（四机各一，或 head 拉+docker save 分发）
docker pull 192.168.5.187:5000/lmsysorg/sglang:main-79cafec0
docker inspect --format '{{index .RepoDigests 0}}' \
  192.168.5.187:5000/lmsysorg/sglang:main-79cafec0   # 指纹核对=上表 sha256
```

**离线/外发备选**：GitHub Releases 提供分卷 tar（`docker save <镜像> | split -b 2G`
分卷；接收端 `cat 卷* | docker load` 后按上表 sha256 复核）——Release 资产
挂载位待推送后建（见推送待办）。dsv41-sglang-optimized 谱系当前仅在集群本机
（`docker images` 本地位，未推 registry）——分发走 docker save 分卷。

---

## 三、快速上手与 FL6 状态位

**形三元组**=env 键面（`deploy/env/`）+SPEC serve 六参（`deploy/SPEC6-SERVE-REF.md`）
+adapter/overlay 面（`deploy/adapter/`、`deploy/overlay/`）——三件齐一才可 boot；
**boot 四查**=health 200/printenv 四机逐字/横幅直读/面指纹四机全等。从零部署
全流程见 **[docs/DEPLOY-GUIDE.md](docs/DEPLOY-GUIDE.md)**。

**FL6 召回修复（51 键，转正在役定版）**：FL6-PROMO 转正窗已闭 GREEN——产线现役
=51 键修复形 **ENV51 `PROD-R51W5FL6-spec1.env`（2ac74586，服务器在役位名；仓内
异名同值件=`deploy/env/PROD-R51W5-FL6FIX-spec1.env`）+sitecustomize 55b1e412
+fl6_recall.py b87cbb5e 四机全等**+SPEC6+overlay o12c1-prod；8899=200 在役健康。
实役直证：**cp30 召回锚位 99.95%+DE 82.17**。回退链两级：一级=摘第 51 键（键关
=sitecustomize 休眠逐字原版行为，不动 adapter 面）；二级=摘接线（按
`sitecustomize-wire-v2.diff` 逆向回 2c4baad3 并摘 fl6_recall.py）。adapter 供给面
=B1 整面快照 83 件（`deploy/adapter/`，见其 README 收录口径）。机理档=
`docs/research/FL6-RECALL-BUG-ANALYSIS-20261013.md`。

## 四、仓库结构

```
docs/        定版成果：report(终版性能报告 v2)/runbook(OPS-MANUAL)/registry(FORM-REGISTRY)/
             quality(RELEASE-QUALITY)/research(FL6+红带两大 bug 定谳档)/DEPLOY-GUIDE/
             ACKNOWLEDGEMENTS(定版 110 条：上游谱系/社区同行/官方资产/外部对照/工具田野)
deploy/      服务面全集：env(两形)/bin(r3 链)/adapter(现役件)/overlay(o12c1-prod 29 件)/
             nccl(ring-only 库+ncclpin)/b12x(计算树)/kit(guard/instruments)/models.d(权重注册卡)/sentinel
tools/       全树工具：packages(五包+_lib+_bake)/boot-with-slotlock/census 面板族/judge/
             boot_sentinel/量具与门禁脚本/patches/ssh-password-login 运维件
tests/       fl6-recall(双臂 6 测)/unit(b12x/row_store)/whitebox(14 件矩阵)
```

CHANGELOG（0.3.0→0.3.1 十条）· SCAN-REPORT（密钥扫描）· NOTICE/LICENSE（许可）
