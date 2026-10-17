# LuZ-0.3.1 @ 4×DGX Spark GB10 — 实机部署记录（LECYWZA 集群）

本目录记录 `LECYWZA` 在自有 **4×DGX Spark（GB10，SM121）TP4 RoCE 环网** 集群上的
LuZ-0.3.1 部署配置与实测数据。

- 基线：上游 [`luxingcom/luz-deepseek-flash-all-in-one`](https://github.com/luxingcom/luz-deepseek-flash-all-in-one) `main` @ `3d588a5`
- 本分支 `spark-live-1017-14m` = 上游 + 如下本机化配置

## 一、集群

| 机器 | 角色 | 管理网 | QSFP 第一平面 |
|---|---|---|---|
| spark-1 | rank0 = head | 192.168.123.103 | 100.1 / 101.1 |
| spark-2 | rank1 | 192.168.123.109 | 100.2 / 102.2 |
| spark-3 | rank2 | 192.168.123.232 | 102.3 / 103.3 |
| spark-4 | rank3 | 192.168.123.65 | 103.4 / 101.4 |

- 环网：四机环 1-2-3-4-1，**异号口对接**（f0 → 下一台 f1），MTU 9000
- 主机名统一解析到管理网（`/etc/hosts`: spark-1~4 → 192.168.123.x）
- 权重单源：spark-1 `/root/NewModels/DeepSeek-V4.1-Flash-1017`（476G），worker 走 NFS 只读挂 `/mnt/luz-weights`

## 二、与上游默认的差异（本部署配置）

| 项 | 上游默认 | 本部署 |
|---|---|---|
| 机器/管理段 | dgxspark01-04 / 192.168.0.201-204 | spark-1~4 / 192.168.123.x |
| 权重路径 | `/data/models/DeepSeek-V4.1-Flash` | `/root/NewModels/DeepSeek-V4.1-Flash-1017` |
| worker 权重 | 本地盘 / `/data/models/dsv41-net` | 单源 NFS（spark-1 导出 → `/mnt/luz-weights`）|
| `--context-length` | 600000 | **1048576**（1M）|
| `--max-total-tokens` | 9600000 | **14000000** |
| 端口 | 8898（测试）/ 8899（产线）| **8888** |
| API key | 无 | **luojiecong** |
| 模型名 | deepseek-v4.1-flash | deepseek-v4.1-flash（不变）|
| SPEC 参谱 | SPEC6 六参 + A8/A9 + W-G（脚本固定面）| 交付版脚本 SERVER_ARGS 缺第 6–9 参 ⇒ 经 `SPEC_EXTRA_ARGS` 全量注入九参 |
| NCCL PEER_HCA | 上游环序（同号口）| 按本集群**异号口**重推（与 mia 现网值一致）|
| engram | `~/dsv41-engram`（各 rank 打包分片）| 同路径，四机硬链接各自 `engram-l1-r{0..3}of4.bin` |
| 权重 NFS 容器 | `dsv41-nfs`（mia 时代 Abliterated）| `luz-nfs`（导出 1017；避开 `dsv41-*` 前置守卫）|

## 三、启动/停止

| 文件 | 作用 |
|---|---|
| `luz-stop-mia.sh` | 停旧栈（存 docker logs）→ 权重 NFS 切到 1017 → worker 挂载 |
| `luz-boot.sh` | 点火：沉降 ≥600s 校验 → `tools/boot-with-slotlock.sh` → 九参 + overlay + 8888 |
| `r3-boot-arm.spark.sh` | 本机化启动链（NODES/PEER_HCA/模型/端口/ctx/api-key/池门）|
| `PROD-R51W5-1017.env` | 51 键 env 形（`B12X_ROCE_PEER_HCA_MAPS` 与 `SPARSE_LOCAL_ADMISSION_CTX_CAP` 本机化）|
| `luz-watch.sh` / `luz-monitor.sh` | 10 秒级采样（health/容器/参数/四机 MemAvailable/KV 池）|

一键流程：
```bash
bash /root/luz-stop-mia.sh     # 停旧栈 + NFS 切 1017（记录沉降起点）
# 等待 ≥600s（OPS-MANUAL 沉降律）
bash /root/luz-boot.sh         # 点火（内部再校验沉降）
```

## 四、实测数据（2026-10-18，1017 权重，ctx 1M）

### 启动与 warm 门
- `health` 200；四机容器 Up；`The server is fired up and ready to roll!`
- 池（当时 9.6M 门）：`max_total_num_tokens=9600000`，profiled 上限 **19,846,912**（`bytes_per_full_token=912.25`，`available_bytes=19.67 GB`）
- **warm 门**：64k × 3 中位 **5698 tok/s**（GREEN，门槛 4500）
- **1M 冷 prefill**：**398–404 s**（≈2,490 tok/s；64k 时 5,700 tok/s）

### KV 容量三段法（池 9.6M）
| 台阶 | 驻留 tokens | 逐会话命中率 |
|---|---|---|
| 阶段1（8×1M）| 7,960,648 | s1–s8 全部 **0.9961–1.0**（零驱逐）|
| 阶段2（+tail 650K，扩容）| 8,612,372 | 全部 **0.9997–1.0** |
| 阶段3（+第 10 个 1M，超池门）| 9,607,453 | 全部 **0.9907–1.0**（每会话均匀回收 ~0.85% 尾巴，无整会话驱逐）|

**结论**：本部署在默认池配比（`swa_full_tokens_ratio=0.8`，未调 ratio）下，
**8M 级驻留零驱逐**；超池门后表现为均匀尾巴回收而非整会话 LRU 驱逐。
（对照：mia 栈需 `--swa-full-tokens-ratio 0.065`、池仅 ~3.3M）

### 内存（全程 256 采样点，MemAvailable）
| 机器 | 最低 | 最高 |
|---|---|---|
| spark-1 | 11.68 GB | 14.15 GB |
| spark-2 | 13.74 GB | 16.03 GB |
| spark-3 | 13.86 GB | 15.98 GB |
| spark-4 | 13.89 GB | 15.91 GB |

- `weight_gb=75.157` / `graph_gb=4.908` / KV 按 `912.25 B/token`
- 池门从 9.6M 提到 **14M** 的依据：profiled 19.85M，14M 时 KV ≈12.8GB，留 7G+ 系统余量

## 五、镜像

| 镜像 | 说明 |
|---|---|
| 上游内网 registry `192.168.0.202:5000/lmsysorg/sglang:main-79cafec0` | 上游现役基座（不可达）|
| `dsv41-sglang-optimized:0.3.1-r3` | 上游发布交付镜像（网盘/内网），引擎 `0.0.0.dev1+g79cafec01` |
| **`luojiecong/luzi-dsv41-sglang-optimized:0.3.1-r3`** | **本部署镜像（Docker Hub，与 r3 同内容）** |

拉取：
```bash
docker pull luojiecong/luzi-dsv41-sglang-optimized:0.3.1-r3
```
