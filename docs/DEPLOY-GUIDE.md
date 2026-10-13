# DEPLOY-GUIDE — LuZ-0.3.1 从零部署指南（4×DGX Spark GB10 TP4 RoCE 环网）

> 目标：在四台 DGX Spark（GB10）上从零复原 LuZ-0.3.1 定型形生产栈。
> 规程法源=`docs/runbook/OPS-MANUAL-031.md`（boot/复原/回退三章）；形权威表=
> `docs/registry/FORM-REGISTRY-031.md`（三形三元组+部署面指纹）。

## 1. 硬件前置

| 项 | 要求 |
|---|---|
| 节点 | 4× NVIDIA DGX Spark（GB10，SM121，ARM aarch64，UMA 架构） |
| 拓扑 | TP4；内部 RoCE 环网（每机 4 口 HCA：rocep1s0f0/f1 + roceP2p1s0f0/f1；逐秩 PEER_HCA 映射表内嵌于 `deploy/bin/r3-boot-arm.sh` NODES 表） |
| 角色 | rank0=head dgxspark01（192.168.5.186）；rank1=dgxspark02（.187）；rank2=dgxspark04（.189）；rank3=dgxspark03（.188） |

## 2. 系统依赖（版本锚——系统级件不随仓分发，逐项对版）

| 组件 | 版本锚 | 核验法 |
|---|---|---|
| NVIDIA 驱动 | **580.173.02** | `nvidia-smi --query-gpu=driver_version --format=csv,noheader` |
| 内核 | **6.17.0-1031-nvidia**（arm64） | `uname -r` |
| CUDA 面 | **13.0**（容器内经 nvidia-container 注入） | `nvidia-smi`（右上 CUDA Version） |
| nvidia-container-toolkit | **1.19.1** | `dpkg -l \| grep nvidia-container-toolkit ` |
| NCCL 特殊栈 | **ring-only 构建 2.30.7**（`deploy/nccl/nccl-ringonly/libnccl.so.2.30.7`，fork 库盖 pip 路径同身份；pin 件挂 `/opt/ncclpin.so`） | boot 前置检查（r3-boot-arm.sh :165） |
| Docker | ≥支持 compose 前述 toolkit 的稳定版 | `docker info` |
| SSH 互信 | 四机 head→workers 免密（密钥登录；密码登录面见 `tools/ssh-password-login-20261013/` 运维件，凭据绝不入仓） | `ssh <worker> true` |

## 3. 镜像获取

见 [README §二](../README.md#二镜像下载内网-registry-直链)：现役基座
`192.168.5.187:5000/lmsysorg/sglang:main-79cafec0`（48.6GB，
sha256 `0f075735…cf3ae`）。四机 `docker pull` 后以 RepoDigest 对表指纹。
VL/0731 兼容模型镜像同节（vllm-openai 两形+dsv41-sglang-optimized 谱系）。

## 4. 权重目录布局

| 机 | 路径 | 内容 |
|---|---|---|
| dgxspark01/02 | `/data/models/DeepSeek-V4.1-Flash/` | V4.1-Flash 权重（`config.json` 在位=boot 前置检查项） |
| dgxspark03/04 | `/data/models/dsv41-net/` | 同权重网络盘位 |

权重注册卡（三模型谱系+指纹）：`deploy/models.d/`（v41-prod/v4-0731/v4-vl-exp）。
engram 分片（**宿主生成物，48G，不随仓分发**）：`~/dsv41-engram/engram-l1-r{0..3}of4.bin`
（+l14 族）——从既有集群同步或由 engram 构建管线产出；缺分片=boot 前置检查拒起。

## 5. 服务面部署（本仓 → 服务器落位映射）

| 本仓 | 服务器落位 | 说明 |
|---|---|---|
| `deploy/bin/` | `~/migrate-assets/bin/` | r3-boot-arm.sh 部署链（md5 c051bb41）+gate 四件+stop/watchdog |
| `deploy/adapter/` | `~/migrate-assets/dsv41/adapter/` | 现役件快照（sitecustomize 55b1e412 等 11 件；逐件锚=`deploy/adapter/README.md`） |
| `deploy/env/` | `~/migrate-assets/dsv41/env/` | 50 键现役形+51 键 FL6 形 |
| `deploy/overlay/o12c1-prod/` | `~/migrate-assets/v4vl/sglang-overlay.o12c1-prod/`（=`SGLANG_OVERLAY_DIR`） | 29 件=28 活件影子挂载+1 映射表（scheduler 5b6fe2a3 等；boot 链挂载计数断言==28——r3-boot-arm.sh `ov_n` 门；目录 29 件含 overlay-map.tsv 自身） |
| `deploy/nccl/nccl-ringonly/`+`ncclpin.so` | `~/migrate-assets/nccl-ringonly/`+`~/migrate-assets/ncclpin.so` | ring-only NCCL 2.30.7+pin 件（只读挂载 /opt） |
| `deploy/b12x/` | `~/migrate-assets/b12x/` | b12x/b12x_next MoE 计算树（boot 硬前置） |
| `deploy/kit/` | `~/w6-kit/`（或烘入 /opt/dsv41/kit/） | guard 守卫族+instruments 量具+adr（oom-gate 面单元让位 selfheal 包） |
| `tools/packages/` | 五包各自 README 部署位（如 gateway→/opt/aicad-prod/） | fabric-net/selfdiag/selfheal/gateway/cfgmgmt（含 systemd 单元面：oom-gate-monitor.service、concurrency-proxy-v2.service+10-gateway-hardening.conf drop-in） |
| `deploy/sentinel/`、`tests/unit/` | 案头/巡检位 | ar_probe 探针+b12x/row_store 单元测 |

部署序：目录映射→`tools/boot-with-slotlock.sh`+r3-boot-arm.sh 资产面前置检查
（adapter/NCCL/b12x_next/分片/权重五项在场，:165）→env/serve/adapter 三元组
对表 FORM-REGISTRY。

## 6. env 形选择（51 键 FL6 转正在飞）

| 形 | 件/md5 | 适用 |
|---|---|---|
| **50 键现役形**（缺省） | `PROD-R51W5-spec1.env` / 15767aa6 | 0.3.1 定型交付形（当前产线在役） |
| **51 键 FL6 形**（转正在飞） | `PROD-R51W5-FL6FIX-spec1.env` / 2ac74586 | FL6 召回修复呈裁通过后启用；**状态=部分绿呈裁位（2026-10-13 验证窗），终值回填位=呈裁落定后本表+`deploy/adapter/README.md` 时点注记更新** |

serve 参=SPEC6 六参（`deploy/SPEC6-SERVE-REF.md`）。回退链 50→48→47 键三级
（OPS-MANUAL 第三章逐级动作序）。adapter 的 sitecustomize 本仓件=FL6 接线后
稳定版（未设 51 键=休眠逐字原版，两形通用）。

## 7. boot 与四查

1. 点火：`ARM_TAG=<tag> ARM_ENV_FILE=<env 件> bash tools/boot-with-slotlock.sh bash ~/migrate-assets/bin/r3-boot-arm.sh`（靴槽锁+四机容器净核）。注：wrapper 缺省锁位=`~/luz030-opt-campaign/.slot-lock`（`CAMPAIGN=<目录>` 环境变量可覆写；全新机器无该目录时先 `mkdir -p` 或设 CAMPAIGN 指向任一可写目录，否则锁文件打开失败即拒起）。
2. 沉降 600s 律（前栈拆靴→点火 ≥600s）。
3. **四查**：①health GET 200；②printenv 四机真键核（与 env 件逐字）；③横幅直读（banner29+W5/R1/O12 armed 态）；④面指纹四机全等（adapter 面 md5 表对表）。
4. warm 请求步 64k×2 第一动作→warm 门（64k×3 中位 ≥4500 绿/≥5000 入役绿线）。

## 8. 验收门（定型形合格判据）

| 门 | 判据 |
|---|---|
| 池门 | boot 横幅池 9,600,000 |
| 断言门禁 | fail-safe PASS rows（四秩）+MISMATCH=0+16 口 idx3 |
| 性能带 | warm 门≥5000；PR 四档对定型带 ±3%；agg600k ≥3005.2 |
| 质量 | smoke 3/3；GSM8K 带；needle 3/3 |
| 水位 | WATER-RED=0（qmg 在役+02 机两守护不动红线） |

任一门红→按 OPS-MANUAL 第二章双复原义务（先撤件再产线 boot）+第三章回退链处置。
