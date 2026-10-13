# deploy/adapter/ — adapter 现役件快照（0.3.1 定型形）

> 权威构成表=FORM-REGISTRY-031 §二；同步工具=selfheal 包 adapter-sync.sh
> （--apply/--check/--expect，四机全等律）。生产真源=宿主
> `~/migrate-assets/dsv41/adapter/`（bind mount 面，不烘焙——cfgmgmt 包红线）。

## 逐件 md5 锚（本仓快照 2026-10-13 核）

| 件 | md5 | 归属 |
|---|---|---|
| `kv_fp4.py` | feaaadd4 | R1 FP4-KV 八件面（严格布尔解析+路由门+fail-safe 双跑+横幅三态） |
| `fi_r1/__init__.py` | 0b6f13f1 | R1 八件面 |
| `fi_r1/t_r1_equiv.py` | 2fe0c0c3 | R1 八件面（49 GREEN 对拍链） |
| `fi_r1/csrc/sparse_mla_sm120_prefill_fp4.cu` | 6e1a5461 | R1 八件面 |
| `fi_r1/csrc/sparse_mla_sm120_fp4_jit_binding.cu` | 9bf19842 | R1 八件面 |
| `fi_r1/include/flashinfer/attention/sparse_mla_sm120/fp4_extra_traits.cuh` | 75d38608 | R1 八件面 |
| `fi_r1/include/flashinfer/attention/sparse_mla_sm120/prefill_kernel_fp4.cuh` | b72d85ea | R1 八件面 |
| `prefill_sp.py` | **32cf9abf** | **W5 定型件**（stage2 MXFP8+出口直聚；2026-10-13 00:02:23Z 转正入役；回退件=0497e566 键关语义等价） |
| `spark_prefill_split.py` | eb53ea12 | TPsplit 库版（split 判负留库件；检查点复原律四机同值） |
| `fl6_recall.py` | b87cbb5e | FL6 召回修复件（SWA interior retirement+match retract；第 51 键门控） |
| `sitecustomize.py` | **55b1e412** | **FL6 接线后稳定版**（见下） |

## sitecustomize.py 状态注记（FL6 时点）

- 本仓收录 **FL6 接线后稳定版（md5 55b1e412）**=FL6-FIX-20261013 验证窗 S2
  部署 v2 形（elif 两支接线+EngramFinder 白名单两行——v1 漏白名单=死代码休眠
  教训在档），2026-10-13 10:44Z 四机同步+门函数管线直证。
- **产线现状（2026-10-13 窗终 rollback 后）=50 键原形 sitecustomize 2c4baad3**
  （FL6 未转正；fl6_recall.py 四机已摘除）。
- **休眠语义**：接线后版本在**未设第 51 键**（DSV41_FL6_RECALL_FIX）时逐字
  原版行为——与 2c4baad3 配 50 键 env 行为等价，回退零成本；设键=激活
  （值域 1/retire/retract 三态，DEPLOY-NOTES 门控表）。
- 变更谱系：2c4baad3（产线原形）→〔`sitecustomize-wire-v2.diff` 重放〕→
  55b1e412（本仓件）；diff 件随仓收录供审计重放。转正 runbook=
  `docs/research/FL6-FIX-RESULT-20261013.md` §九。

## 与 overlay 面的关系

overlay o12c1-prod（29 活件，scheduler 5b6fe2a3 等）不在本目录——派生面上游
文件按上游许可（NOTICE §2），产线经 `SGLANG_OVERLAY_DIR` 由 boot 链挂载
（r3-boot-arm :317-341）；指纹与构成=FORM-REGISTRY §二。
