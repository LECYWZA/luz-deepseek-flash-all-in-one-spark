# RECIPE — <镜像代名：dsv41-sglang-optimized:0.3.1>（模板件；执行窗填写）
> TOOLS31 §5.2 每代配方律承载；先例=00-BAKED-BY-0.2.8.md / image-patches/<ver>/ 谱系。
> **PENDING-FINAL-GATE**：FL6 修复绿+定型宣告后执行窗启用本模板（BAKE-PENDING-FINAL-GATE.md）。

## 一、构建锚（唯一事实源三钉）
- git commit 锚：`<短 sha>`（构建时工作树**干净硬断言**——构建脚本第 2.5/6 步；脏树=拒建）
- 构建脚本：`build-0.3.1.sh`（与 RECIPE 同目录入 `image-patches/0.3.1/`）
- 基座镜像：`<上游基座：main-79cafec0 族/或转正版>`（adapter/overlay=bind mount 真源**不入镜像**——§五排除清单）

## 二、载荷表（装了什么——三类）
| 类 | 件 | 来源（仓内位→镜像位） |
|---|---|---|
| 运行期源码 | <overlay 族/引擎侧……按代填写> | <…→…> |
| 仓库↔镜像同步 | <…> | <…> |
| 工具载荷 | tools/packages/{fabric-net,selfdiag,selfheal,gateway,cfgmgmt} 五包（selfcheck 全绿版） | →/opt/dsv41/packages/<pkg>/ |
| 文档集 | docs/ 定稿报告/运维手册/形档案三件+TOOL-ANCHORS | →/opt/dsv41/docs/ |

## 三、排除清单（没装什么——与载荷表同等重要；SMOK_KEY 前科律）
- 密钥件：GW_API_KEY/SMOK_KEY/任何 `*secret*`/`*.env` 已填值件（模板件可入，值恒禁）
- `*.bak-*` / 日志 / `state/` / `__pycache__`（历史与运行态）
- **adapter 树与 overlay 树**（bind mount 真源律：镜像只载工具包与文档集；部署面
  集合指纹仍走宿主挂载核对——§5.4 边界=本清单显式注记）
- **宿主侧守护件**：fabric guards/oom-gate monitor/r3-watchdog/gateway units（00-BAKED
  「它是载荷不是运行时守卫」律：/proc//sys/cgroup 判据容器内无判据⇒不入镜像不接线不自启）

## 四、产物指纹三件
1. 包内：每包 `MANIFEST.md5`（md5sum -c 自验）+包级汇总指纹（VERSION FINGERPRINT）
2. 镜像 LABEL：`org.dsv41.kit_manifest_md5=<值>`（=五包 MANIFEST 拼流指纹；归档副本比值判同代）
3. `IMAGE-IDENTITY` 件（模板见同目录；~/migrate-assets/dsv41/IMAGE-IDENTITY 先例沿袭）

## 五、可复现硬门
- 冷构建连跑两次：`NOCACHE=1 TAG=<临时标签> bash build-0.3.1.sh` ×2，内容身份必须相等
- 拍扁 argv 双登记律核对（ARGV-PAIR-REGISTRY 成对+外部注入优先律——§5.3）
- 四机冒烟+指纹核对四件（卡 §5.4 序）+台账 `logs/TOOLS31-BAKE-<date>/`

——TOOLS31 T4 案头模板 / 2026-10-13（PENDING-FINAL-GATE）。
