# LuZ-deepseek-flash-all-in-one

LuZ-0.3.1 一体化交付仓——**DeepSeek-V4.1-Flash @ 4×NVIDIA DGX Spark（GB10，SM121）
TP4 内部 RoCE 环网全栈优化**的可发布交付集（基于 SGLang 上游 `main-79cafec0`
的自有优化层，详见 [NOTICE](NOTICE)）。

> 仓性质：从战役仓 `luz030-opt-campaign` v0.3.1 定型版本蒸馏出的**干净起步交付仓**
> （独立 git init，tag `v0.3.1`；战役全程历史留在战役仓及其 bundle）。
> 密钥扫描硬门已过：全仓零凭据值，见 [SCAN-REPORT.md](SCAN-REPORT.md)。

---

## 版本特性摘要（0.3.1 定型形）

| 面 | 读数/内容 |
|---|---|
| **步墙（census 每步）** | 866 → **626 ms**（服务口径 **−27.8%**；QA31 定型窗 626.1 ≤ 677 目标，裕度 50.9） |
| **128k prefill 吞吐** | **5880 tok/s**（QA31 案 A' 定型形读数） |
| **R1 FP4-KV in-kernel** | `DSV41_FP4KV_R1_INKERNEL=1`（kv_fp4.py+fi_r1/ 八件面，fail-safe 双跑 49 GREEN 四机） |
| **W5 stage2 MXFP8** | `DSV41_PREFILL_SP_FP8=1`+`DSV41_PREFILL_SP_TAIL_GATHER=1`（prefill_sp.py 32cf9abf，出口直聚=tail gather 出口 RS） |
| **E3-A SWA 召回** | `--swa-prefix-tails 64→256`（N=256 转正在役；SPEC6 第六参） |
| **O12 调度** | `SGLANG_DSV4_O12_SCHED_ASYNC=1`+`RECV_INTERVAL=4`（三键调度间隙，产线化） |
| **FL6 召回修复** | fl6_recall.py（第 51 键 `DSV41_FL6_RECALL_FIX` 门控）——**转正呈裁在飞**，见下「FL6 状态位」 |
| **回退链** | 50 键 → 48 键 → 47 键三级（每级 boot 四查；OPS-MANUAL 第三章） |

质量面：GSM8K 0.97 / needle 600k 3/3 / qeval 75/75 全等 / PR 四档 ±3% 带内跨窗复现 / 水位 WATER-RED=0。

## 快速上手

**形三元组**（deploy 一个形 = env 键面 + SPEC serve 参 + adapter/overlay 面，三件齐一才可 boot）：

```
env 件（键面）        deploy/env/PROD-R51W5-spec1.env          # 50 键，md5 15767aa6
SPEC serve 参         deploy/SPEC6-SERVE-REF.md                # 六参
adapter 面（现役件）  deploy/adapter/                          # 五件+fi_r1/ 六件，指纹见 deploy/adapter/README.md
```

**boot 四查**（boot 收口核，OPS-MANUAL 第一章）：

1. health GET `200`；
2. `printenv` 四机真键核（键名+值与 env 件逐字）；
3. 横幅直读（adapter 29+ 横幅门行+W5/R1/O12 armed 态）；
4. 面指纹四机全等（adapter 面 md5 表对表）。

伴律：沉降 600s 律、warm 请求步 64k×2 第一动作、warm 门 4500/5000。

## 仓库结构

```
docs/
  report/     0.3.1 定稿报告（031-FINAL-PERF-REPORT v2）
  runbook/    运维手册（OPS-MANUAL-031：boot/复原/回退/巡检/呈裁七章）
  registry/   形档案（FORM-REGISTRY-031：三形三元组+部署面指纹+50 键清单）
  quality/    发布质量档（0.3.1-RELEASE-QUALITY + TOOLS31 五包就绪度）
  research/   关键研究档精选 15 篇（FL6 召回 bug/红带根因/组合叠加终局等）
deploy/
  env/        50 键现役形 + 51 键 FL6 形（两收录，状态见 deploy/README.md）
  bin/        r3-boot-arm.sh 部署链（boot/stop/watchdog/gate-lint 四件套）
  adapter/    adapter 现役件快照（kv_fp4/prefill_sp/spark_prefill_split/
              sitecustomize〔FL6 接线后〕/fl6_recall/fi_r1/ 六件）
  SPEC6-SERVE-REF.md  serve 六参参考
tools/packages/  五包整树（fabric-net/selfdiag/selfheal/gateway/cfgmgmt）+_lib
tests/
  fl6-recall/ FL6 测试件（双臂 6 测+案头 patch+部署注记）
  whitebox/   白盒矩阵档（CODE31 14 件期望基线复现）
  QA31-RESULT-POINTER.md  QA31 定型窗结果档指针
```

## FL6 状态位（51 键，转正在飞）

FL6 召回修复（QA31 cp30 红位的机理修复：SWA interior retirement + match retract）
验证窗 2026-10-13 收窗=**部分绿呈裁位**：cp30 红位未复现（复测 3/3 全命中），
严格冻结双门 2/3（L0001 TTFT 比 0.056 边际出线，出线纯分母面）——**转正与否=主
会话呈裁**。产线已复原 50 键原形；本仓收录**转正即用全套**：

- `deploy/env/PROD-R51W5-FL6FIX-spec1.env`（51 键，md5 2ac74586）
- `deploy/adapter/sitecustomize.py` = **FL6 接线后稳定版（md5 55b1e412）**——
  接线对未设第 51 键时**休眠=原版逐字**，与 50 键现役形（2c4baad3）行为等价；
- `deploy/adapter/fl6_recall.py`（b87cbb5e）+ 转正 runbook（docs/research/
  FL6-FIX-RESULT-20261013.md §九）。

## 各分档入口

- [0.3.1 定稿性能报告（v2）](docs/report/031-FINAL-PERF-REPORT-20261009.md)
- [运维手册](docs/runbook/OPS-MANUAL-031.md) · [形档案](docs/registry/FORM-REGISTRY-031.md) · [发布质量档](docs/quality/0.3.1-RELEASE-QUALITY.md)
- [版本沿革 CHANGELOG](CHANGELOG.md) · [许可与上游注记 NOTICE](NOTICE) · [密钥扫描报告](SCAN-REPORT.md)
- [deploy 部署面说明](deploy/README.md) · [adapter 指纹与 FL6 时点注记](deploy/adapter/README.md)
