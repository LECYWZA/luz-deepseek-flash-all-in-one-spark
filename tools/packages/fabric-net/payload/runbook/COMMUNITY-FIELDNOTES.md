# COMMUNITY-FIELDNOTES — 环网恢复四症状（社区田野笔记摘译+出处索引）

> **性质**：案头登记件（COMMUNITY-DELTA-20261012 §5.1.2 建议「runbook 案头登记件」；
> TOOLS31-PACKAGE-PLAN §二 P1-4 吸收面；§七.6 默认口径=**摘译+出处链接**，非逐字收编）。
> **出处**：社区仓（只读审计库 ~/knapcio-v41-audit-20260925 谱系上游）docs/
> switchless-ring.md:503-527，来源 issue Mia#40/#41，commit fa13563（2026-10-09 21:33）。
> **吸收判读**（COMMUNITY-DELTA-20261012 :104/:141）：我方环网车队同险面；零集群不动，
> 仅编入运维索引备查。与 `FABRIC-GID-REPAIR-RUNBOOK.md`（正典动作）关系=**互补面**：
> 本件登记「症状→鉴别法」，正典 runbook 登记「本车队的处置动作序」。

## 四症状速查（症状 → 鉴别法 → 社区恢复命令 → 我方对应件）

| # | 症状 | 鉴别法（采什么） | 社区恢复命令 | 我方对应面 |
|---|---|---|---|---|
| 1 | **RoCEv2 IPv4 GID 从 index 3 漂到 4**（netplan apply/重插线后） | `ibv_show_gid`（或 /sys/class/infiniband/<hca>/port_1/gids/3）看 types/3 是否仍=RoCE v2、v2@3 是否空 | `modprobe -r mlx5_ib && modprobe mlx5_ib` 重注册 | fabric-guard F-G5（洞/错值二分）→ fabric-gid-heal.sh 四前置环回重铺（**唯一 auto_ok 项**）；判读线 NCCL_IB_GID_INDEX=3 零改（集群一致性律） |
| 2 | **端口 state=ACTIVE 而 carrier 假活跃**（每几秒抖 0） | 采样 `/sys/class/net/<iface>/carrier`（**非**一次性 state 读——state=ACTIVE 不作数） | （社区=诊断面；恢复随线缆/驱动位） | fabric-guard F-G1 链路态同采+Q2 down-回窗判据；doctor 面（本包 diag/fabric-doctor.sh）逐口 carrier 采样 |
| 3 | **mesh marker 被 _kill 后残留流表把 TX 塌到 ~14Gb/s** | 链路层 TX 吞吐对锚（~14Gb/s 级塌陷签名；Mia#40：RoCEnante 装后同族） | `modprobe -r mlx5_core`（重载驱动）；**停 mesh 必须走 unit 勿 pkill**（残留流表根因） | 停 mesh=dsv41-mesh.service unit 面正典（fabric-guard 头注律）；TX 塌=Q3 持续性判据+fabric-sentinel 32MB AR 带外告警 |
| 4 | **NFS 软挂载假在线**（挂载点死亡仍显 mounted） | `timeout` 下按 shard 数逐点探（**非** `mountpoint` 单查——软挂载假阳性） | 同左（探测法即恢复前置） | 权重/语料 NFS 面核查（VL-NFS/WEIGHTS-NFS 复原窗先例：按 shard 数 timeout 探测） |

## 补丁 NCCL 安装路径（同源 :109-150 摘译）

- **Route A**=sparkring 发布产物，**双 sha256 钉扎**（下载件+解包件双核）。
- **Route B**=nccl v2.30.7-1+dual-PCI-domain 单补丁自建，**禁叠层**（多补丁叠加=不可溯源面）。
- 我方现役=上游 main-79cafec0 基座+NCCL_IB_* 家族键（s4_bench.sh 生产同款 env）；
  补丁路径仅在未来换 NCCL 底座窗启用，启用时本节升格为动作序。

## 伴随注记（L2PF 惰性）

社区 :551-558：L2_PREFETCH 在 `SGLANG_ROCE_ALLREDUCE=0` 环网靴上惰性（无 plan 学习、
零损零得）。我方产线 ROCE_ALLREDUCE=on（50 键形 DSV41_ROCE_RING=1∧SGLANG_ROCE_ALLREDUCE=1）
无涉——登记备查，防未来裁关 ALLREDUCE 时漏评 L2PF 交互。

——TOOLS31 P1 案头吸收 / 2026-10-13（零集群零流量；摘译口径，原文以出处行号为准）。
