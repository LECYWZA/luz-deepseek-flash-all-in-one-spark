# deploy/ — 0.3.1 定型形部署面（env 键面 + SPEC serve 参 + adapter 现役件 + boot 链）

> 权威表=`docs/registry/FORM-REGISTRY-031.md`（三形三元组+部署面指纹）；
> 操作规程=`docs/runbook/OPS-MANUAL-031.md`。本目录=可发布快照，逐件 md5 锚
> 见下表（与 FORM-REGISTRY §二对表）。

## env/ — 两形收录与状态位

| 件 | 键数 | md5 | 状态 |
|---|---|---|---|
| `PROD-R51W5-spec1.env` | 50 | **15767aa6** | **当前产线复原目标/在役形**（=48 键 8c8c166d 逐字+FP8/TG 两键） |
| `PROD-R51W5-FL6FIX-spec1.env` | 51 | 2ac74586 | **FL6 转正在飞**（50 键逐字+第 51 键 DSV41_FL6_RECALL_FIX=1）——转正即用形，呈裁后经 boot 生效；机理档=`docs/research/FL6-RECALL-BUG-ANALYSIS-20261013.md`；呈裁全档=战役仓 docs/research/FL6-FIX-RESULT-20261013.md（归档位） |

回退链两级（自 50 键在役形）：48 键 PROD-R1INK48L2PF6O12C1（8c8c166d）→
47 键 PROD-R1STDLL128L2PF6O12C1（99e7ec92）+深回退 45 键 PROD-R1STDLL128L2PF6
（34977bf0）——三件随仓收录=`tools/packages/cfgmgmt/payload/env/`（cfgmgmt 包
回退链库，md5 对表 FORM-REGISTRY-031 §一全中；服务器在役位=~/migrate-assets/
dsv41/env/）。

## SPEC6-SERVE-REF.md — serve 六参

50 键定型形 serve 参谱=**SPEC6**（五参基座+swa256），全文与用法见
[SPEC6-SERVE-REF.md](SPEC6-SERVE-REF.md)。

## adapter/ — 供给面整面快照（B1 收录 2026-10-13）

**83 件/约 3.0M**（顶层 68+fi_r1/ 6+lib/ 1+overlay/ 3+tests/ 5；sitecustomize 55b1e412
装载缝+boot 装载闭包 48 件+留役休眠件 10+`.so` 运行库+dspark_sps 表+构建源）。
收录口径（剔 `*.bak*` 39+变体 1+EP1 陈旧清单 2）与排除名单逐件、FL6 终值注记见
[adapter/README.md](adapter/README.md)；逐件 md5=[adapter/MANIFEST.md5](adapter/MANIFEST.md5)。

## bin/ — r3-boot-arm.sh 部署链

> 服务面其余模块（overlay/nccl/b12x/kit/models.d/sentinel）落位映射与部署序
> 见 `docs/DEPLOY-GUIDE.md` §5。

| 件 | md5 | 用途 |
|---|---|---|
| `r3-boot-arm.sh` | c051bb41 | ARM 主 boot 链（env 注入/overlay 挂载/横幅门/池门 9,600,000） |
| `r3-boot.sh` | — | 基座 boot（无 ARM 注入面） |
| `r3-stop.sh` | 5ad87830 | 四机停靴（先存后删律配套） |
| `r3-watchdog.sh` | — | 水位/健康看护 |
| `r3-window.sh` | — | 窗口冒烟（环网一句话探针） |
| `r3-gate-env-lint.sh` | 5337c6cf | env 键面 lint 拒绝门（红=拒起） |
| `r3-gate-assert-lint.sh` / `r3-gate-banner-contract.sh` / `r3-gate-endpoint-lint.sh` | — | 断言/横幅合同/端点 lint 三门 |

boot 规程（点火前缀/沉降 600s 律/warm 64k×2 第一动作/warm 门 4500/5000/
四查）——见 OPS-MANUAL 第一章。产线基座镜像=SGLang 上游 main-79cafec0
（NOTICE §4）。

## 内网 IP 说明

本目录与 docs/ 各档含内网 IP/主机名（dgxspark01-04 等）——内网部署文档性质，
按密钥扫描策略保留（SCAN-REPORT.md）；对外发布时如需脱敏按该档处置行执行。
