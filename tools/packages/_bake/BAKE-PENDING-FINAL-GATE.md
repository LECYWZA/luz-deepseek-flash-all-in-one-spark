# BAKE-PENDING-FINAL-GATE — 容器烘焙段暂缓注记（TOOLS31 T4 §五承载）

> **状态（2026-10-13 案头批）**：烘焙**暂缓**——FL6（E3A cp30 召回红）修复未毕，
> 0.3.1 定型宣告未发。本目录只落**案头可完成件**：RECIPE 模板+IMAGE-IDENTITY 模板+
> 拍扁 argv 双登记规范（ARGV-PAIR-REGISTRY.template.tsv）。实际烘焙执行=FL6 修复绿+
> 定型宣告后**后继窗**（卡 §五全序照写，标 PENDING-FINAL-GATE）。
>
> **前置依赖四项（卡 §5.1，全绿才进烘焙）**：
> ①T1 组合窗定型形定谳+转正宣告（**当前阻塞项=FL6 修复**）；②T2 QA 全电池收案
> （RELEASE-QUALITY T2 节绿——QA31 已收=红窗，FL6 承接修复中）；③T3 文档集齐
> （定稿报告/运维手册/形档案——FORM-REGISTRY-031/OPS-MANUAL-031 已在档）；④五包
> 整备+selfcheck 全绿+T4-2 内嵌呈裁落格毕（五包=tools/packages/{fabric-net,selfdiag,
> selfheal,gateway,cfgmgmt}，就绪度见 docs/release/TOOLS31-PACKAGES-RESULT-20261013.md）。
>
> **案头纪律重申**：零 boot 零流量；~/migrate-assets 只读；本目录模板不含任何密钥值
> （SMOK_KEY 前科律：密钥件恒在 RECIPE 排除清单）。

## 烘焙序速览（后继窗执行面，本档只登记不执行）

1. 分发边界（卡 §〇 落位律）：镜像载 `tools/packages/<pkg>/`→`/opt/dsv41/packages/<pkg>/`
   +文档集；**宿主侧件不入镜像**（systemd unit/fabric 守护/网关 unit=部署面分发——
   00-BAKED-BY-0.2.8.md「它是载荷不是运行时守卫」律沿袭：/proc//sys/cgroup 判据全来自
   宿主接口的件，容器内无判据⇒不入镜像）。
2. RECIPE 件=唯一事实源（模板：`RECIPE.template.md`）；构建脚本 `build-<ver>.sh`；
   产物指纹三件：包内 `MANIFEST.md5` + 镜像 LABEL `kit_manifest_md5` + `IMAGE-IDENTITY`
   件（~/migrate-assets/dsv41/IMAGE-IDENTITY 先例沿袭）。
3. 冷构建可复现硬门：`NOCACHE=1 TAG=<临时标签>` 连跑两次，内容身份必须相等
   （00-BAKED 可复现性律原文）。
4. 拍扁 argv 成对律：`ARGV-PAIR-REGISTRY.template.tsv` 双登记+外部注入面保持优先
   （§5.3：SPEC_EXTRA_ARGS :396-398 注入+ARM_ENV_FILE 尾部覆盖律不因烘焙失效）。
5. 烘焙后四机冒烟+指纹核对四件（卡 §5.4）：boot 门链全绿→warm 步/门→四查+七参直读+
   printenv 真键核→**注入面成对核对**→smoke 3/3；指纹=包内 md5sum -c+LABEL 对表+
   IMAGE-IDENTITY 对表+部署面集合指纹（adapter 面 53469aab 口径〔sitecustomize=2c4baad3
   后〕/overlay 算式见 TOOL-ANCHORS——**烘焙不改 bind mount 面，adapter/overlay 仍走
   宿主挂载真源**，镜像只载工具包与文档集；此边界=RECIPE 排除清单显式注记）。
6. 台账：烘焙窗档 `logs/TOOLS31-BAKE-<date>/`（RECIPE 副本+构建日志双跑比对+冒烟四查件+
   指纹表）。

——TOOLS31 T4 案头批 / 2026-10-13（PENDING-FINAL-GATE：FL6 修复绿+定型宣告后执行）。
