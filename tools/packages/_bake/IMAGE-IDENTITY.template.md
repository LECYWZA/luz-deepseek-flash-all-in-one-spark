# IMAGE-IDENTITY — <镜像 tag>（模板件；执行窗随镜像入 /opt/dsv41/ 填写）
> 先例=~/migrate-assets/dsv41/IMAGE-IDENTITY（0.2.8 谱系）；TOOLS31 §5.2 产物指纹件。
> PENDING-FINAL-GATE（烘焙执行窗启用）。

| 项 | 值 |
|---|---|
| IMAGE | <repo:tag> |
| 构建时点（UTC） | <ts> |
| git commit 锚 | <短 sha>（工作树干净断言通过） |
| kit_manifest_md5（LABEL） | <五包 MANIFEST 拼流指纹> |
| 五包指纹 | fabric-net=<FP> / selfdiag=<FP> / selfheal=<FP> / gateway=<FP> / cfgmgmt=<FP> |
| RECIPE 副本位 | image-patches/0.3.1/RECIPE.md（+build-0.3.1.sh） |
| 冷构建双跑比对 | <两次内容身份相等=PASS；差=拒发> |

## 拍扁 argv 成对律登记面（§5.3；与 RECIPE 载荷表成对——双登记缺一=红）

| 键（argv/环境键） | 镜像内置缺省值 | 来源注入面（外部覆盖位） | 对表核（四机冒烟步） |
|---|---|---|---|
| SERVER_ARGS 缺省段 | <值> | SPEC_EXTRA_ARGS 注入（r3-boot-arm :396-398；烘焙后仍可覆盖） | printenv+横幅双核 |
| COMMON_ENV 族键 | <值> | ARM_ENV_FILE 尾部覆盖律 | 同上 |
| <逐键填写…> | | | |

**双源漂移=红**：镜像内置与定谳 env 件不一致且无注入覆盖=配置分裂面（DEPLOY-SPLIT 前科族）。

## 边界注记（bind mount 真源律）
adapter/overlay 不入镜像（宿主挂载真源）；部署面集合指纹核对位=SITECUSTOMIZE_MD5 变量位
（FL6 窗终值回填）+overlay 正典集合指纹（TOOL-ANCHORS 算式行）。

——TOOLS31 T4 案头模板 / 2026-10-13（PENDING-FINAL-GATE）。
