# knapcio RoCE/NCCL 通信运行时面深调研 — 2026-10-07

- **战役**：LuZ-0.3.1→0.3.2 / knapcio RoCE-NCCL 通信优化专案深调研代理（纯案头，零集群）。
- **调研对象**：`~/knapcio-v41-audit-20260925`（knapcio/DeepSeek-V4.1-Flash-4x-DGX-Spark-TP4，MiaAI-Lab 兄弟分支，同 GB10/CX7 硬件栈）。
- **与第一轮的分工**：`KNAPCIO-FABRIC-TUNING-20261007.md`（下称 R1）已覆盖持久化机制/hairpin 队列表/trust 矛盾/交换机双形态，本文不重复；本文=**通信运行时面**（NCCL env 全集、NCCL 库本体、RoCE 双形通信路径、QOS 运行时值、数据背书面、坑沿革、逐项对表）。R1 §五主会话裁定的挂起项（ROCE_MAX_SIZE 降帽/PFC prio0/LL128 裁剪/trust 双模板）在 §四对表。
- **我方对表基线**：`~/dsv41-flash-dgxsparks/.env.tp4`（生产现役键面）+ R1 §2.1 参数表 + 我方 `docs/taskcards/C1B-ROCENANTE-ONESHOT-EVAL-20261001.md`（RoCEnante 机制级评估，已完成的部分引用不重复）。OPEN-28b/28c 两代理报告**截稿时未出**（docs/ 全树检索无产物），§四按 R1 已知候选对表。
- **纪律声明**：全部发现带仓内 文件:行 锚；仓内没有的如实记「无」。knapcio git 共 109 commit（`git log --oneline | wc -l`=109），无 revert 类提交（grep -i revert 零命中），坑主要来自注释/文档/上游 issue 记档。

---

## §一 七路调研逐路发现

### 路 1 · NCCL env 全集（三处来源分层：env 文件默认值 / ring 注入 / 启动器注入）

**A. 生产默认层（switched 形态，`.env.tp4.example:14-33`，`.env.example:14-33` 同）**

| 键 | 值 | 锚 | 注释论证 |
|---|---|---|---|
| NCCL_SOCKET_IFNAME | `enP7s7` | .env.tp4.example:15 | 「Gloo/NCCL TCP bootstrap on the LAN NIC. Data plane prefers RoCE」——管理面/数据面分离 |
| IB_HCA | `rocep1s0f0,rocep1s0f1`（默认）| .env.tp4.example:16 | 生产实跑两 rail 各一口 `rocep1s0f0,roceP2p1s0f0`（docs/history.md:118「both rails」）——**每 PCI 根域取一口**，非同卡两口 |
| NCCL_NET | `IB` | :17 | 无注释（RoCE 数据面） |
| NCCL_IB_DISABLE | `0` | :18 | 无注释 |
| NCCL_P2P_DISABLE | `1` | :19 | **无数据注释**（GB10 无跨节点 P2P；单 GPU/节点使 P2P/SHM 传输无意义——推断，仓内无原文明示） |
| NCCL_SHM_DISABLE | `1` | :20 | 同上 |
| NCCL_DEBUG | `WARN` | :21 | :30 注「INFO 单靴看 communicator/channel/protocol 选择」=调试用不留产 |
| NCCL_BUFFSIZE | `1048576`（1MiB）| :26 | **有实测**（:22-25 原文）：「NCCL 连接缓冲住 pinned host RAM（GB10=GPU 内存）：默认（4MiB Simple+4.69MiB LL128+0.5MiB LL per connection，512 连接）每节点 4.7GiB；实测 pinned 5.0GB→**0.14GB**。decode AR=61KB（LL），prefill 用 Simple」 |
| NCCL_LL128_BUFFSIZE | `262144`（256KiB）| :27 | 同上注释内（LL128 无收益故裁） |
| NCCL_PROTO | `^LL128` | :28 | 同上 |
| NCCL_MAX_NCHANNELS | `8`（switched 默认）| :29 | **无数据注释**（注意：4 只在双平面可选块 :83，见 R1 表行 2 的勘误——R1 把 MIN=4/MAX=4 记成 ring 主线，实际 MAX=4 仅双平面块，ring 注入只设 MIN=4） |
| NCCL_DEBUG_SUBSYS | `INIT,ENV` | :31 | 无 |
| NCCL_HOST_DIR | `$HOME/nccl-2.30.7` | :32 | 打补丁库的家目录（路 2） |

**B. ring 注入层（opt-in，`files/nccl.sh:100-124`，开关 `NCCL_SWITCHLESS_RING_ONLY=1`）**：`NCCL_SWITCHLESS_RING_ONLY=1`、`NCCL_ALGO=Ring`、`NCCL_SKIP_TREE_CONNECT=1`、`NCCL_IB_SUBNET_PREFIX_LEN=24`、`NCCL_MIN_NCHANNELS=4`、`NCCL_P2P_LEVEL=SYS`（六键头+worker 同串镜像，`.env.tp4.example:49-62` 为注释版）。校验规则（nccl.sh:126-150）：NNODES=TP_SIZE=4、`NCCL_OVERLAY_PIP=1`、`NCCL_NET=IB`、SUBNET_AWARE_ROUTING=1、MIN≤MAX（MAX 缺省上限 32——**ring 形态不钉 MAX**）。

**C. 启动器注入层（每容器，switched/ring 共通，`start.sh:306-322` 头 + `:421-431` worker 镜像串）**：`NCCL_CROSS_NIC=1`（:313）、`NCCL_IB_MERGE_NICS=0`（:314）、`NCCL_IB_SUBNET_AWARE_ROUTING=1`（:315）、**`NCCL_CUMEM_ENABLE=0`**（:316，无数据注释）、BUFFSIZE 兜底 4194304（:318）、LL128_BUFFSIZE 兜底 `-2`（:319，负值=NCCL 内部比例式）、PROTO 兜底 `LL,LL128,Simple`（:320）、MAX_NCHANNELS 兜底 32（:321）、DEBUG_SUBSYS 兜底 INIT（:322）、`NCCL_IB_GID_INDEX=<逐主机发现值>`（:339 注入；:738-741 `gid_index_local/remote` 探测 HEAD_IP/WORKER_IPS，缺省 `NCCL_IB_GID_INDEX:-3`）。

**D. 双 PCI 域可选块（`.env.tp4.example:76-87` + nccl.sh:69-84）**：`NCCL_IB_EXTENDED_IPV4_GIDS=1`、`NCCL_IB_PRESERVE_PCI_DOMAIN=1`、`NCCL_IB_ROUTE_DIAGNOSTICS=1`、`NCCL_IB_QPS_PER_CONNECTION=1`、`NCCL_MAX_NCHANNELS=4`（有 sparkring#193 数据背书，见路 5）、`NCCL_DEBUG_SUBSYS=INIT,ENV,NET`（验证期加 NET）。

**E. 库挂载键**：`NCCL_OVERLAY_PIP=1` + `NCCL_PIP_SO=/opt/sglang/.../libnccl.so.2`（.env.tp4.example:56-57；overlay 盖写而非 LD_LIBRARY_PATH——DeepEP `check_nccl_so()` 双库中止问题，nccl.sh:12-14）、`NCCL_CONTAINER_DIR`、`NCCL_WORKER_DIR`（worker 侧家目录映射，nccl.sh:226-246）。

**F. 明确「无」**：全仓无 `NCCL_IB_TOS`（零命中）；`NCCL_IB_TC` 仅作为 b12x_next RoCE 代理的可读键存在（路 3-F），NCCL 配置面从未设置。无 NCCL_IB_HCA jersey 变体、无 NCCL_NTHREADS/NCCL_LAUNCH_MODE 类。**即 knapcio 的 NCCL RoCE 流量完全不带 DSCP/TOS 标记**。

### 路 2 · NCCL 库本体：patched sparkring 2.30.7，非 stock

- **谱系**：NCCL 2.30.7 + FujitsuPolycom/sparkring 的 `switchless-cycle`/`skip-tree-pat` 补丁，构建进 `$HOME/nccl-2.30.7`（库文件名 `libnccl.so.2.30.7`，nccl.sh:34）。补丁本体不在 knapcio 仓内（外部仓），仓内只有集成件；出处链=MiaAI-Lab #3（@Saolence）→#19 承继→knapcio rebase（nccl.sh:19-23、switchless-ring.md:644-650）。
- **库身份断言**：preflight 对 .so `grep -qa SWITCHLESS_RING_ONLY`，无 marker=拒绝 stock（nccl.sh:206-209）——「错库在换容器前死，不在 NCCL init 时死」。
- **双平面累计补丁**：`nccl-2.30.7-dual-pci-domain.patch` 把 listener GID 发布帽 `gidSlot<2` 提到 4，旗标门控；**必须单独打**（已含 switchless-cycle，叠打即坏，switchless-ring.md:256-262）。
- **挂载策略**：ring 态 overlay 盖写 pip 库；switched 态若 NCCL_HOST_DIR 有库则 `-v :/nccl:ro`+LD_LIBRARY_PATH（start.sh:353-357）——但 torch 走自身 RPATH，**LD_LIBRARY_PATH 只影响 ctypes 用户，替换不了 torch 用的库**（optional-setups.md:42、CHANGELOG:293-294，坑清单 §三-8）。
- **RoCEnante 侧运行时**：Dockerfile.canary-roce=上游 sglang `dsv4.1` 分支 pin f80c91a4b + rhys101 SG17 overlay（`runtime/sglang-rocenante.patch`）+ `runtime/roce_tp4_adapt.py`（TP8→TP4/双轨放宽+SGLANG_ROCE_MAX_SIZE 环境化）+ `runtime/b12x`（SG17 冻结版 b12x，source-provenance.json：base「SG4b qualified B12x 85d3681」，roce_revision 081b2359）+ `runtime/b12x_next`（b12x main a7d7d29b 改名共存）。
- **roce_ring 冻结副本的血统警示**（roce_ring-provenance.json source_note）：取的是 sparkring **bundle-source 冻结版（2026-09-06）**；sparkring 维护副本 third_party/b12x_roce 其后有 **三个修复未纳入**：跨序列回绕超时检测（f91b5c8）、原子 proxy 计数器（2d83bb6）、内存域与轮询修复（e4d0921）。knapcio 自己的改造=改名缓存隔离/PEER_HCA_MAPS 环境化/IDLE_SPINS 2e5→2e7。
- **我方对照**：我方 `/opt/nccl-ringonly` = LuZ 自建 2.30.7 路线（算法矩阵 Tree=0 达成 ring-only，**无** SWITCHLESS_RING_ONLY marker；`~/dsv41-flash-dgxsparks/BUILD-IDENTITY.md:190`、`scripts/nccl_selfcheck.sh:105-117` 自带双谱系探测）。两路线同基版本、不同补丁族（R1 行 1「不可互换」成立，此处补齐谱系细节）。

### 路 3 · RoCE 路径配置：switched（默认/生产）vs ring（research-only）双形

**A. switched 形态通信路径**（生产 v2.3，README.md:70）：
- 包=`b12x.comm.roce`（SG17 血统），`SGLANG_ROCE_ALLREDUCE=1`（兼容旧键 SGLANG8_ROCE_ALLREDUCE，roce_tp4_adapt.py:12-14）；TP SUM AR ≤max_size 走单发 RDMA kernel（CUDA graph 内），>max_size 及非 SUM 走 NCCL。
- `SGLANG_ROCE_MAX_SIZE=2097152`（2MiB）：overlay 原默认 512KiB（roce_tp4_adapt.py:17-20 的 `os.environ.get("SGLANG_ROCE_MAX_SIZE", str(512*1024))`），2MiB=b12x 自身 DEFAULT_MAX_SIZE（roce_oneshot.py:44），**生产取 2MiB 的依据=16 请求档 decode 步 AR=983KB，2MiB 把它也路由进来**（optional-setups.md:38、history.md:117）。**关键：此 2MiB 数据全部产自交换式 fabric——每 peer 双 rail 直达，无 hairpin 中转**。
- `B12X_ROCE_HCA=rocep1s0f0,roceP2p1s0f0`：**每 PCI 根域一口**（两 rail 各一），`discover_hcas` 硬帽 ≤2 个 HCA（roce_oneshot.py:99-101 `explicit[:2]`）；port-1 GID 于 `NCCL_IB_GID_INDEX` 必须非零（:104-112）。
- `DSV41_ROCE_GATHER=2097152`（adapter/roce_gather.py）：all-gather ≤2MiB/rank 也走 oneshot（字节拷贝语义）。
- 其它默认：DEFAULT_MAX_GATHER_BYTES=16MiB、DEFAULT_GID_INDEX=3（与 NCCL_IB_GID_INDEX 共读，roce_oneshot.py:84-89）、GPU 侧 flag 自旋 B12X_ROCE_SPIN_LIMIT 默认 2×10⁷（≈20s，:49-51）、CPU proxy ROCE_IDLE_SPINS=2×10⁷（_roce_proxy.c:48，SG17 值）。
- 健康检查件：`synchronize_and_check_roce()` 挂在每个 result boundary——copy_done.synchronize 后 `runtime.check_health()`，传输停滞=步失败而非挂死（sglang-rocenante.patch:22-32,169-191）。

**B. ring 形态通信路径**（research-only，DSV41_ROCE_RING=1）：
- 包=`b12x.comm.roce_ring`（sparkring f16b5f4 冻结副本+三改造，见路 2）；四 HCA 全用、**每 peer 两路径**：邻接走本机线缆直达，对角（dist=2）经邻居 CX7 hairpin 硬件转发——QP RTR 时对角 QP 打 `flow_label=16383`（mlx5 映射为 UDP 源口 65535，被邻居 tc 规则匹配转发），邻接 QP flow_label=0（_roce_proxy.c:506-519）。
- 生产配方（.env.tp4.example:114 + docs/results/ring-mesh-20260925.txt:3-5）：`DSV41_ROCE_RING=1 SGLANG_ROCE_ALLREDUCE=1 SGLANG_ROCE_MAX_SIZE=262144 DSV41_ROCE_GATHER=262144 B12X_ROCE_HCA=<四口> B12X_ROCE_PEER_HCA_MAPS=<plan.py 产> B12X_ROCE_TWO_WAVE_THRESHOLD_BYTES=0`。
- **帽值论证（R1 P9 的深化）**：帽与 hairpin 干净尺寸联动——queue1024 帽 81920（80KB）/queue8192 帽 262144（256KB），`plan.py:206` 硬编码 `cap = 262144 if hairpin >= 8192 else 81920`；「8192 队列下 480KB 内零丢，**960KB 即便两波开也 64 drops**」（switchless-ring.md:549-554 表）。**knapcio 从未在 ring 上跑过 >256KB 的 RoCE AR**——2MiB 帽只在无 hairpin 的交换式上被数据背书。
- **two-wave**：默认阈 131072（128KiB，_roce_proxy.c:48），仅 world=4 且 4 HCA 时生效（:909-911）；「只在有丢包时才有意义」——配方里显式关（TWO_WAVE=0），因为配 256KB 帽后无丢包，两波反而多一次等待（switchless-ring.md:558-560、CHANGELOG:105-106「tested and not adopted: the two-wave schedule once nothing drops」）。
- 驱动资格面（mesh 前置）：`hairpin_num_queues=4`、`flow_steering_mode=hmfs`、eswitch=legacy、hw-tc-offload=on，plan.py 不齐即拒（switchless-ring.md:486-492）。
- 对角路径验证法：`ib_write_lat -d <dev> -x 3 --flow_label=16383` 打对角口，~10µs@61KB（直连 8.5µs），邻居规则计数器涨而 IpForwDatagrams 平=硬件转发成立（switchless-ring.md:531-535）。

**C. 无 mesh 的 ring 上**：RoCEnante 不可用（对角无路径），`SGLANG_ROCE_ALLREDUCE=0`、collectives 全走补丁 NCCL——NCCL 小消息地板 ~56µs/AR vs RoCEnante ~16µs，每 decode 步 ~90 个 AR（optional-setups.md:92-94）。

**D. NCCL↔RoCE 分工口径**（2026-09-19 profiler，upstream-watch.md:63-67）：RoCEnante 在役时 NCCL 余量=0.6ms/步（all_gather 0.288ms/265 次 + all_reduce 0.278ms/83 次 + broadcast 0.027ms），占 51.8ms 步的 0.56%。

**E. NCCL↔RoCE 分流几何**：RoCE 侧 ≤max_size 的 SUM AR/gather 走 oneshot；NCCL 承接其余（大 prefill collectives、非 SUM）。prefill 大 gather 已由 NCCL 承担（CHANGELOG:38-39「large prefill gathers over RoCE … prefill gathers already use NCCL」）。

**F. RoCE QP 的 TOS/TC 面（我方 trust 问题的延伸发现）**：SG17 `b12x` 两副本 QP RTR 的 `grh.traffic_class = 0` **硬编码**（roce/_roce_proxy.c:305、roce_ring/_roce_proxy.c:510）——RoCEnante 的 RDMA 流量**完全不带 DSCP**；仅 b12x_next 新代理有 `B12X_NEXT_ROCE_TRAFFIC_CLASS`/`NCCL_IB_TC` 可读键（_proxy.py:27-40 → _roce_proxy.c:308 `rtr.ah_attr.grh.traffic_class`），但 knapcio 任何配置未设（默认 0）。**即：在 trust=pcp 下，knapcio 与我方的 RoCEnante AR 流量同样全部落 prio0**——R1 行 5 的「我方独有矛盾」需要修正为：NCCL 面我方标 TOS46 被架空、RoCE 面双方都裸奔 prio0（knapcio 干脆两边都不标，出厂态自洽；我方标了一半被 pcp 架空，形成「标而无效」的中间态）。

### 路 4 · QOS/fabric 运行时值（与 R1「机制对照」互补：这里是**值**）

全仓 grep 证实（`mlnx_qos|pfc|trust` 命中=零配置处；`ethtool -G/-g` 零命中）：

| 面 | knapcio 值 | 锚 | 依据 |
|---|---|---|---|
| PFC/trust/收缓冲 | **完全未触碰**（出厂态：无 mlnx_qos 调用） | 全仓零命中 | 无 |
| NIC ring（ethtool -G） | 完全未调（出厂） | 零命中 | 无 |
| MTU（以太） | 9000，netplan 持久（`optional: true` 防阻 boot） | switchless-ring.md:311-334；plan.py:54-55 断言 | 布线文档 |
| RoCE path_mtu | QP 取 min(本端, 对端)，plan.py 期望值 **4096** | _roce_proxy.c:495-497；plan.py:123 | planner 断言（与以太 9000 分离的 RoCE 层 MTU——我方守护面未覆盖的独立值） |
| hairpin_queue_size | **8192**（hairpin.sh:8 缺省；dsv41-mesh.service:13 boot 重放；「8192 把干净尺寸提到 ~480KB」） | service 注释原文 | R1 已录的队列表 |
| hairpin_num_queues | 4 | switchless-ring.md:488 | sparkring 资格面 |
| flow_steering_mode | hmfs | 同上 | 同上 |
| GID index | 逐主机自动发现（缺省 3） | start.sh:738-741 | — |

**结论：knapcio 的 QOS/fabric「调优面」实际只有 hairpin 队列深+MTU+编址三项；prio 缓冲/PFC/trust/收环四项全出厂。** 他们不是「调得比我们好」，是「根本没调」——我方 prio0 缓冲扩容（R1 P2）若做=**超社区动作**，只能靠我方 s2 计数器证据自持（此判定与 R1 行 4/5/6 一致，此处为全量 grep 复核确认）。

### 路 5 · 性能数据背书面（哪些配置有数、哪些裸抄）

**有实测背书（可抄）**：
1. NCCL 缓冲三键（BUFFSIZE 1MiB/LL128 256K/PROTO ^LL128）：pinned 5.0GB→0.14GB 实测（.env.tp4.example:22-25）——**省存向背书，非性能向**（性能=中性论断：decode AR 走 LL 61KB、prefill 走 Simple，LL128 本就无收益）。
2. MIN/MAX_NCHANNELS=4 vs 8（双平面语境）：sparkring#193 四对八实测无 serving 收益且 +0.14GiB head 共享内存（.env.tp4.example:80-83、switchless-ring.md:366-371）。
3. **NCCL 通道/算法调优整体负结果**：`NCCL channel/algorithm tuning: measured, no gain or worse`（docs/history.md:273，2026-09-17 tested-and-not-adopted）——对他们是负结果记录，对我是「别再往这方向烧靴」的背书。
4. RoCEnante 512KiB 路由（switched）：+3% prose c1、+8% structured c1、+3.5% code c16 + 262k 冷 prefill 并发 16 流 soak 零传输错误（optional-setups.md:38）。
5. RoCEnante 2MiB 路由（switched）：c16 聚合 +4.5%、code c1 +3%、structured +3%（optional-setups.md:38 尾、history.md:117 gather 600→400µs/步）。
6. IDLE_SPINS 2e5→2e7：c1 步 40.6→37.1ms（-8.6%）、c2 -7%、c4 -6%（2e5 时 proxy 27% 采样在 decode 中打盹）（CHANGELOG:96-97、switchless-ring.md:454）。
7. hairpin 8192+256KB 帽+两波关：c2 -1%、c4 -1.3%、c1 不变（其 collective 50-60KB）（switchless-ring.md:455）。
8. 环 mesh 分步价（switchless-ring.md:451-456）：NCCL→RoCEnante over mesh 步时 -5.2%（51 任务 50 快）qeval 76.3→79.5；v2 叠加后 qeval 81.8/84.7/85.9（3 跑）。
9. 环 vs 交换机同日对（switchless-ring.md:466-476）：decode 步 prose 33.3 vs 33.0ms / code 38.1 vs 39.2ms（**环上 code 反快 2.8%**）；prefill 16k-128k 环 -4~5%（单链 bisection 代价）。
10. EP_SIZE=4→1（通信面）：MoE AR 5.9→~2.6ms/步；README.md:92「NCCL time per step 16.5→10.2ms」。
11. 帽-队列联动表（switchless-ring.md:549-554）：60K/100K/120K/240K/480K/960KB × queue1024/8192 的 µs/op+drops 全矩阵——**本仓最硬的通信面数据**，R1 已引，此处补齐「960KB@8192 两波开仍 64 drops」与「120KB@1024 3-4× 慢+many drops」两端点。

**无数据背书（裸设/缺省沿用，避坑标记）**：NCCL_MAX_NCHANNELS=8（switched 默认，无注释无表）；NCCL_CUMEM_ENABLE=0（start.sh:316 无注释）；NCCL_P2P_DISABLE/SHM_DISABLE=1（无注释）；CROSS_NIC=1/MERGE_NICS=0/SUBNET_AWARE_ROUTING=1（启动器缺省，无数据）；IB_HCA 生产从「同卡两口」改「两 rail 各一口」无独立 A/B 数据（history.md:118 一句「neutral within noise, kept」）。这些键**不构成可抄证据**，抄=抄缺省。

### 路 6 · 坑清单原始素材（沿革+注释+上游档）

knapcio 仓 109 commit 无 revert；坑密度集中在 switchless-ring.md「Pitfalls/Mesh pitfalls」两节 + provenance source_note + upstream-watch「Watch-outs」。已整编进 §三（带我方现状对照）。

### 路 7 · 与我方逐项对表

我方生产键面（`~/dsv41-flash-dgxsparks/.env.tp4:49-87`）vs knapcio：

| # | 面 | knapcio | 我方 | 差分判定 |
|---|---|---|---|---|
| 1 | 传输选键族 | NET=IB / IB_DISABLE=0 / P2P_DISABLE=1 / SHM_DISABLE=1 / SOCKET_IFNAME=enP7s7 | **逐键相同**（.env.tp4:49-54） | 一致（同源家族常识，双方同值） |
| 2 | 库 | $HOME/nccl-2.30.7 sparkring（SWITCHLESS_RING_ONLY marker 路线） | /opt/nccl-ringonly LuZ（算法矩阵 Tree=0 路线） | 等效 ring-only、不同补丁族（BUILD-IDENTITY.md:190）；nccl_selfcheck.sh:110-117 我方已可双谱系探测 |
| 3 | BUFFSIZE | 1MiB（实测省存背书） | **8MiB**（.env.tp4:62） | 差 8×；R1 P7 已登记裁剪候选 |
| 4 | LL128 | 256KiB+^LL128（背书见路5-1） | 未设（默认 4.69MiB+LL128 在列） | R1 P7 候选维持 |
| 5 | 通道数 | ring MIN=4 不钉 MAX；双平面 MIN=MAX=4（背书）；switched MAX=8（无背书） | MIN=4+MAX=4（EXTRA_DOCKER_ENV 内） | **我方=其双平面配方**，且有 #193+「调优无益或更糟」双背书——**维持不动** |
| 6 | CROSS_NIC/MERGE_NICS/SUBNET_AWARE | 1/0/1（启动器缺省） | 1/0/1（.env.tp4:64-66） | 一致 |
| 7 | CUMEM 键 | **NCCL_CUMEM_ENABLE=0**（设备侧 cumem） | **NCCL_CUMEM_HOST_ENABLE=0**（host 侧）——**不同键** | 键名分歧：两键语义不同（GDRCUMEM/cuMem 分配器 vs host buffer 注册路径），我方未设设备侧键；见 §二-3 |
| 8 | GID | 逐主机自动发现+preflight 校验（缺省 3） | NCCL_IB_GID_INDEX_FORCE=3 硬钉 | 我方更严（FORCE 变体），维持 |
| 9 | TOS/TC | **全不标**（NCCL 无 TOS；RoCE proxy traffic_class=0 硬编码） | NCCL_IB_TOS=46 在役（pcp 下被架空）；RoCE 侧同 0 | 我方「半标态」：NCCL 标了无效、RoCE 没标——**prio0 落点两营相同**（路 3-F） |
| 10 | IB 重传 | 不设（缺省） | NCCL_IB_TIMEOUT=1000 / RETRY_CNT=7 显式 | 我方显式钉缺省族值（RING 长 RTT 语义下 TIMEOUT=1000 高于 stock 缺省 18 的量纲换算——保守可维持，见 §二-9） |
| 11 | RoCE AR 帽 | switched 2MiB（直达路径背书）/ **ring 256KiB（hairpin 干净尺寸背书）** | RING mesh 在役 **2MiB**（SGLANG_ROCE_MAX_SIZE=2097152）+GATHER=512K+TWO_WAVE=0 | **P9 核心错配坐实**：我方把「switched 才背书的 2MiB」用在 ring 对角 hairpin 路径上，knapcio ring 配方从未超 256KB；960KB 即 64 drops（§四-2） |
| 12 | RoCE HCA 选法 | switched 每 rail 一口（≤2）；ring 四口全用+PEER_HCA_MAPS | 四口全用+MAPS（.env.tp4:87 同构） | 一致（ring 形态） |
| 13 | two-wave | ring 配方显式 0（无丢包时两波无益） | 0（.env.tp4:87） | 键同值同——但前提不同：他们 0 是配 256KB 帽，我方 0 是配 2MiB 帽单波直灌对角（C1B 卡 Q2① 同判） |
| 14 | IDLE_SPINS/SPIN_LIMIT | 2×10⁷（proxy C 宏+env） | 树内同值（C1B 卡 Q2① 已核：两份 _roce_proxy.c 均 2e7） | 一致，杠杆已耗尽 |
| 15 | QOS 数值面 | 全出厂（路 4） | pcp+PFC3/5 配置在但 idle+ring rx 已 8192 部署 | 我方已超社区（P2 prio0 缓冲候选仍待段 3/4 定值） |
| 16 | RoCE 健康检查 | result-boundary check_health（补 b12x#313） | 我方 A2 线冻结 RoCEnante（C1B 裁定维持），NCCL 主路径 | 不适用（我方未武装 RoCEnante 主产）——但 health-check 模式对 NCCL 面哨兵（fabric-sentinel）有借鉴 |
| 17 | 我方独有键 | — | NCCL_IGNORE_CPU_AFFINITY=1/SET_THREAD_NAME=1/NET_PLUGIN=none/TUNER_THRESHOLD=40960 | knapcio 无对应；我方自设项维持（各有本仓论证，非本次轴） |

---

## §二 吸收清单（呈裁表）

| # | 项 | knapcio 做法 | 数据背书 | 我方现状差 | 移植成本 | 建议 | 持久化通道 |
|---|---|---|---|---|---|---|---|
| 1 | **ROCE_MAX_SIZE 环上降帽 2MiB→262144** | ring 配方帽=hairpin 干净尺寸（plan.py:206 自动联动） | 队列表 960KB@8192 两波开仍 64 drops；120KB@1024 3-4× 慢；其 ring 从未>256KB | 我方 ring mesh 在役 2MiB 单波灌对角 | env 一键（.env.tp4:87 行内改值）+回退同 | **改造抄·升级 P9**（R1 定「待实测」→本调研后社区证据已足额，仍遵主会话裁定等段 3/4 差分一并落，但建议置信档从「疑似」升「社区数据强支持」） | env 键呈用户裁（lutune 不涉） |
| 2 | **DSV41_ROCE_GATHER 同步对齐** | ring 配方 GATHER=MAX_SIZE=262144 | 同上（gather 分片同样过对角路径） | 我方 GATHER=524288（512K，介于其两形之间） | 同 #1 | 随 #1 联动改 262144（或 512K→若段 4 显示 gather 面无 oos 足迹则独判） | env 键呈用户裁 |
| 3 | **NCCL_CUMEM_ENABLE=0 补设**（键名勘误件） | start.sh:316 每容器注入 | 无数据（裸缺省沿用）——但语义=禁 cuMem 设备分配路径，与我 GB10 统一内存保守取向一致 | 我方只设了 CUMEM_HOST_ENABLE=0，设备侧键缺 | env 一键，零风险面（可回退） | **改造抄（低优先）**：呈裁补 NCCL_CUMEM_ENABLE=0，与既有 HOST 键成对；无背书故不直定 | env 键呈用户裁 |
| 4 | NCCL_LL128 裁剪三键 | BUFFSIZE 1MiB/LL128 256K/^LL128 | pinned 5.0→0.14GB 实测（GB10=GPU 内存） | 我方 8MiB+LL128 默认在列 | env 三键，boot 期 NCCL INFO 协议行核 | **维持 R1 P7 登记**（省存向独立立项级，主会话已裁「登记后续优化池」）；本调研无新反证 | env 键呈用户裁 |
| 5 | **帽-队列联动自动化** | plan.py 按发现的最小 hairpin 队列选帽（cap=262144 if ≥8192 else 81920） | 机制性（防错配复发） | 我方帽值手工定、与 mesh 队列深无联动断言 | fabricctl/lutune 加一条断言+推导 | **直接抄进 fabric-guard**：F-G4（hairpin=8192）与「env 帽值≤262144」一致性断言——错配态=CRIT「切点半切态」同族 | fabric-guard 断言（R1 §3.7 增量） |
| 6 | **对角路径探针**（ib_write_lat --flow_label=16383） | mesh 验证步：对角 ~10µs@61KB vs 直连 8.5µs+邻居规则计数器涨+IpForwDatagrams 平 | 其 runbook 实测值 | 我方 fabricctl selftest 无对角路径时延探针 | w6-kit 加探针（idle 门禁同 sentinel 纪律） | **改造抄**：入 fabric-sentinel 或 selftest 可选档（非每 5min，随哨兵低频）——对角 hairpin 面故障（marker/tc 丢）现在只能靠流量期 oos 事后发现 | fabric-sentinel 档 |
| 7 | ListenerRouting/路由记录判据 | `advertised=4 observed=4`+「overriding dev N with dev M preserving PCI root」 | 其排障实录 | 我方 guardctl/fabricctl 已有 GID 面，无 NCCL 路由面判据 | 日志 grep 断言 | **改造抄**（R1 行 11 已提，此处确认实现位：NCCL_DEBUG_SUBSYS=INIT,ENV,NET 单靴诊断档，不常开） | 诊断 runbook 件 |
| 8 | RoCE 健康检查模式（result-boundary） | sglang-rocenante.patch:22-32 每步结果界 check_health | b12x#313 wedge 的缓解件 | 我方 RoCEnante 冻结（C1B），不适用；NCCL 面 fabric-sentinel 已立 | — | **不抄（不适用）**；其「传输停滞=步失败而非挂死」的语义已由我方 sentinel+health 口径覆盖 | 不适用 |
| 9 | NCCL_IB_TIMEOUT=1000 维持评估 | 不设（stock 缺省族） | 无 | 我方显式 1000/7 | — | **不抄其「不设」**：我方 R1 P10 已裁「维持」（RING 对角 2 跳+hairpin 下更高 timeout 语义保守），knapcio 无交换机直达无此需——**我方更优不抄** | 已在役 |
| 10 | 通道数 MIN=MAX=4 维持 | #193 数据+「调优无益或更糟」 | 有 | 我方同值 | — | **不动**（双背书，路 5-2/3） | 已在役 |
| 11 | QOS 数值面（prio0 缓冲/PFC prio0） | **无任何 QOS 动作** | 无 | 我方 P2/P3 候选在飞 | — | **无件可抄**——knapcio 对此轴零证据；我方 s2 计数器是唯一证据源，维持 R1 定值路径不变 | lutune（R1 既定） |

---

## §三 避坑清单（knapcio 沿革/注释揭示 × 我方现状对照）

| # | 坑（knapcio 原始记载） | 锚 | 我方是否在坑里/如何绕 |
|---|---|---|---|
| 1 | ring 上 NCCL 默认建 tree→对角无直达→`ncclCommInitRank` unhandled system error 死 | switchless-ring.md:12-26 | **已绕**（ringonly 算法矩阵路线从根上 Tree=0；且我方不认 SWITCHLESS_RING_ONLY 键） |
| 2 | listener GID 发布帽 gidSlot<2：IB_HCA 第 3/4 口**静默零流量**，channel plan 看着对但计数器平 | switchless-ring.md:210-241 | **已解**（R1 行 11：我方四口有流量）；但「计数器证据原则」已入守护——保持 |
| 3 | 第二平面「线插着但没编址」（无 IPv4/MTU1500/GID 全零）=旗标全开也零字节 | switchless-ring.md:283-300 | 我方 16 口编址/MTU/GID 由 fabricctl 常巡——**不在坑** |
| 4 | plan.py 在 mesh 单元置 8192 **之前**跑=产出 81920 保守帽而非 262144（顺序坑） | switchless-ring.md:528-530 | 我方帽值人工管理无此自动化——**不适用**；若吸收 §二-5 联动断言则须同序（先 mesh 后帽） |
| 5 | **引擎在跑时重初始化 fabric function/停 mesh/marker=对角流量断+全 QP 落**（hairpin.sh 幂等跳过已达标口=安全例外） | switchless-ring.md:564-567 | **我方已在防**（面操作停机律+idle 双确认门，OPEN-28 §九两事故后纪律）；lutune 部署窗 idle 门=R1 §四-6 既定 |
| 6 | marker 无差别改写该设备上**所有** UDP 源口 65535 的 RDMA 包——该口必须保留 | switchless-ring.md:568-569 | 我方同款 mesh 在役=**同坑位**；fabricctl F 检查不含「65535 占用审计」——**建议补一条断言**（新增微项） |
| 7 | mesh 改归约序→单 prompt 贪心文本漂移、acceptance 摆动；qeval 中位本身跑间摆 2-3% | switchless-ring.md:571-576 | C1B 卡 Q2② 已吸收（我方 A2d 3.25→2.7 判定同根）；量具纪律=步时+多跑中位——**已建制** |
| 8 | torch 经自身 RPATH 载 pip NCCL：LD_LIBRARY_PATH 挂载换不了 torch 用的库，**只有 overlay 盖写有效** | optional-setups.md:42、CHANGELOG:293-294 | 我方 D3 件已「pip 路径盖写同身份」（RING-FACE-3REF D3）——**已绕**；但若未来换库须保持 overlay 路线勿退回 LD_LIBRARY_PATH |
| 9 | b12x#313 graph-replay wedge（长混合上下文流量下 rank 挂死，上游仍 open）；缓解=result-boundary 健康检查+一键回 NCCL | optional-setups.md:38、upstream-watch.md:15 | 我方 RoCEnante 冻结（C1B）——**不暴露**；若未来复活须带其健康检查件 |
| 10 | roce_ring 冻结副本**缺 sparkring 后续三修**（序列回绕超时/原子计数器/内存域轮询） | roce_ring-provenance.json source_note | 我方树=同一冻结副本（C1B 卡证）——**同坑位但被冻结令遮蔽**；复活 RoCEnante 时的前置升级项，记档 |
| 11 | sparkring 原版 proxy IDLE_SPINS=2e5 在 decode 间隙打盹（27% 采样） | _roce_proxy.c:47 注释、CHANGELOG:96-97 | 我方树已 2e7——**不在坑** |
| 12 | hairpin 1024 缺省下 >100KB 消息即溢出（oob+对端 oos/seq_err+go-back-N 3-4× 慢） | switchless-ring.md:543-548 | 我方 8192 boot 重放在役——**不在坑**（这正是 R1 P1/P6 的机理源） |
| 13 | 「有交换机时勿设 ring-only」（跳 tree=性能损失）；ring-only 与 switched 互斥 | switchless-ring.md:413-414 | 切换预留已建（DSV41_ROCE_RING 单键+mesh 撤除联动，R1 行 13）——**已防**；切窗时须同时撤 NCCL_ALGO=RING 与 mesh（切点半切态断言已设计 F-G6） |
| 14 | CPU 亲和对通信 proxy 无益：调度器钉 X925 -5.5%、proxy 单独钉=中性 | switchless-ring.md:577-578、CHANGELOG:105-106 | 我方 NCCL_IGNORE_CPU_AFFINITY=1 在役——取向一致；**不再试**（负结果已录） |
| 15 | Mia #14：九月 OTA `nvidia-spark-grub-kho`（kho=off）把 CX7 发送钉 12.7Gb/s（6.17.0-1032） | upstream-watch.md:137-139 | **我方未查**（s2/守护面无 /proc/cmdline 审计）——**建议入 fabric-guard F 档**：OTA 后 cmdline 含 kho 检查（新增微项，与 03 f0 FEC 同列「外部环境」面） |
| 16 | tonyd2wild：长跑后 GPU 时钟锁低（30-60s 断电才恢复）；15h 老链路 prefill 慢 30%（重启恢复，原因未明） | upstream-watch.md:127-133 | 与 OPEN-28「断电级冷启恢复」同族现象的**社区旁证**——不是 NCCL 参数坑而是「长运行深态」坑；我方 fabric-sentinel+判愈链即对冲件；**引证入 OPEN-28c 机制面**（若其代理需要社区先例） |
| 17 | ring NFS_SHARE=0 迁移残留：NFS 卷同名留存→探测过→静默走 NFS，exporter 一死才炸 | switchless-ring.md:143-159 | 我方生产 NFS 单独网段（10.0.22/23），mesh 数据面不载 NFS——**形不同不适用**；但「同名卷类型审计」（mount options 判型）手法可入我方 fabricctl NFS 检查 |
| 18 | 长跑 fleet 调优前必须重跑 fresh-boot prefill 基线对勘（「before trusting any tuning on a long-running fleet」） | upstream-watch.md:98-99,131-133 | 我方健康锚+判愈链即此思想——**已建制**；补强点：把「多日 uptime 后基线漂移」列为 sentinel 带外的解释项之一 |

---

## §四 与 OPEN-28b/c 定值候选对表（R1 §2.2 占位接口 + 已知候选）

OPEN-28b（RoCE 缓冲并发争用）/28c（NCCL 断电前后横幅）报告截稿未出；按 R1 已知候选逐项给 knapcio 证据向：

| 候选 | knapcio 证据向 | 对表结论 |
|---|---|---|
| **P9 ROCE_MAX_SIZE 降帽**（2MiB→524288/262144） | **强支持**：①其 ring 配方帽=256KB 且从未超；②960KB@queue8192 两波开仍 64 drops、480KB 为零丢边界；③其 2MiB 正证据全部产自交换式直达路径（无 hairpin），拓扑前提不移植 | **升级**：R1「疑似错配待段 3/4」→「社区数据强支持降帽（262144 为社区配方值、524288 为零丢表上限内候选）」；终值仍遵主会话裁定待段 3/4 差分回填，但置信档上调 |
| **P2 prio0 收缓冲扩容** | **中性/无证据**：knapcio 全出厂态，prio0=19,872B 同款在跑且无 oob 记档（他们没查，不是没有） | **不变**：我方 s2 oob 130k-296k 签名仍是唯一证据；knapcio 既不背书也不反证——「超社区动作」定性维持 |
| **P3 PFC prio0 使能** | **无证据+侧面反证**：他们连 prio3/5 都未启（PFC 全出厂）；RoCE QP traffic_class=0=prio0 裸奔跑了全部基准（含 soak）无 PFC 依赖 | **降档参考**：p2p 直连上 RoCE 无 PFC 可跑通且达其全部性能数字——P3 维持「仅当 P2 差分不足才进档」的保守位 |
| **P7 LL128 裁剪+BUFFSIZE 核算** | **背书确认**：5.0→0.14GB pinned 实测；decode LL/prefill Simple 的协议分布论证 | **不变**（主会话已裁：登记后续优化池，独立立项级） |
| **P1 ring rx 8192**（已部署） | 无对应动作（他们没调 ring）——但其 hairpin 1024→8192 消 oob/oos 的同族数据是机理旁证 | **不变**（已部署+guard F-G1 在役） |
| **新发现候选：RoCE QP traffic_class** | b12x_next 有键（NCCL_IB_TC），SG17 两副本硬编码 0 | **新增登记（低优先）**：我方若未来在 switch 模板下走 dscp+PFC 无损设计，RoCEnante 复活时其 QP 须带 TC（需 patch SG17 副本或升级 b12x_next 线）；ring 模板 pcp 下无操作意义（全落 prio0 同现状） |
| **新发现候选：NCCL_CUMEM_ENABLE 键补设** | start.sh:316 无背书缺省 | 见 §二-3（呈裁项，非本役轴） |
| **OPEN-28c 机制面（断电级深态）** | tonyd2wild 双例（时钟锁低/15h 链路 -30% prefill，重启或断电恢复）=社区同族先例 | **引证材料**：非 NCCL 参数问题而是长运行深态面——供 28c 报告引为社区旁证（我方已按断电级处置收口，方向一致） |

---

## §五 七路摘要（一段版）

knapcio 的通信面 =「**sparkring 补丁 NCCL 2.30.7（ring-only+四 GID 发布）+ SG17 RoCEnante 单发 RDMA（switched 2MiB 直达/ring 256KB hairpin 联动帽）+ QOS 全出厂 + hairpin 队列深 8192**」。NCCL env 族与我方高度同源（NET/P2P/SHM/CROSS_NIC/MERGE_NICS/SUBNET_AWARE/通道 4/4 逐键同值），差分集中在：BUFFSIZE 1MiB vs 我 8MiB、LL128 裁剪 vs 我未裁、CUMEM 键名分歧、TOS 半标态（我 NCCL 标而 pcp 架空、RoCE 双营均 traffic_class=0 裸奔 prio0）、RoCE 帽 256KB vs 我 2MiB（ring 路径错配坐实）。数据背书最硬的三件=NCCL 缓冲省存实测、帽-队列干净尺寸矩阵、「NCCL 通道/算法调优无益或更糟」负结果；QOS 数值面他们零动作=我方 P2 为超社区动作须自持证据。坑面最高价值的四条=引擎在跑禁面操作（我方已律）、冻结副本缺三上游修复（我方同位）、marker 全改写 UDP65535（建议补审计）、OTA kho 钉 CX7 12.7Gb/s（建议入守护）。

## §六 来源锚

- knapcio clone `~/knapcio-v41-audit-20260925/`：`.env.tp4.example`（:14-33 fabric 默认、:34-116 ring/双平面/帽联动注释、:463-471 canary-roce 生产行）、`.env.example:14-33`、`files/nccl.sh`（:34 库名、:100-124 ring 注入、:126-150 校验、:155-197 GID 发现、:200-224 preflight）、`start.sh`（:72-94 缺省、:306-322 容器 env、:339/:738-741 GID、:353-357 库挂载）、`docs/switchless-ring.md`（:549-554 帽矩阵、:451-456 分步价、:466-476 环-交换机对、:486-492 驱动资格、:562-581 mesh pitfalls、:644-650 出处链）、`docs/optional-setups.md`（:25-42 RoCEnante/RPATH、:90-113 ring 生产段）、`CHANGELOG.md`（:79-106 ring 日志、:183-184 gather、:293-294 RPATH）、`docs/history.md`（:117-118 生产 Transport 行、:273 NCCL 调优负结果）、`README.md`（:70 Transport、:92 EP1、:156-161 注意事项）、`docs/upstream-watch.md`（:15 b12x#313、:63-67 NCCL 余量画像、:125-141 他队 watch-outs）、`docs/results/ring-mesh-20260925.txt`（:1-11 配置头）、`runtime/b12x/b12x/comm/roce/{roce_oneshot.py:44-51,84-116, _roce_proxy.c:48,302-306}`、`runtime/b12x/b12x/comm/roce_ring/{_roce_proxy.c:47-48,506-519, _path_config.py:11-25,59-98}`、`runtime/b12x/{roce_ring-provenance.json, source-provenance.json}`、`runtime/b12x_next/b12x_next/comm/roce/{_proxy.py:27-40, _roce_proxy.c:78,234-252,308}`、`runtime/roce_tp4_adapt.py`、`runtime/sglang-rocenante.patch:22-32`、`scripts/ring_mesh/{plan.py:54-55,123,206, hairpin.sh:6-18, dsv41-mesh.service:12-13, inventory.sh:14-18}`、`Dockerfile.canary-roce`
- 我方：`~/dsv41-flash-dgxsparks/.env.tp4:49-87`（生产键面）、`~/dsv41-flash-dgxsparks/BUILD-IDENTITY.md:190`、`~/dsv41-flash-dgxsparks/scripts/nccl_selfcheck.sh:105-117`、本仓 `docs/research/KNAPCIO-FABRIC-TUNING-20261007.md`（R1）、`docs/taskcards/C1B-ROCENANTE-ONESHOT-EVAL-20261001.md`、`docs/audits/RING-FACE-3REF-COMPARISON-20261002.md:118`

——knapcio RoCE/NCCL 通信优化专案深调研代理 2026-10-07（纯案头；§四对表接口待 OPEN-28b/c 报告出档后由主会话汇）
