# oom-gate —— 内存地板守卫（GB10 四机止损闸门）

> 适用：4×DGX Spark（GB10 / SM121），dgxspark01..04
> 版本：脚本 `v1.1`（2026-09-22 15:17 加「止损前保护」）；单元 2026-09-18 起由 systemd 托管
> 位置：**四机** `~/w6-kit/oom-gate/`
> 架构决策记录：**`../adr/ADR-004-three-gib-floor-guard.md`**（为什么是这个量、为什么止损线是 1.5 GiB）
> 上游背景：本脚本是「2026-09-14 集群 OOM 事故 A1」的落地件，判据取自事故报告的 6.4 节 F1/G1-G4
> —— ⚠️ **该报告不在本仓库内**（本机未找到文件载体；同一份报告在 `~/V41-A23-PARAM-RESIZE-REVIEW-20260914.md` 里被引用，
> 可作旁证。本仓库内可复核的判据载体是 `oom_gate.sh` 头部「事故教训」段）

**一句话**：这是**四机唯一会 `docker stop` 的守卫**。它的职责不是"报告内存紧张"，
而是在内存地板被击穿时**主动杀掉本机推理容器**，把主机从 global OOM 里救出来。

---

## 1. 在被判据量：`eff_idle`

```
有效空闲(eff_idle) = MemFree + Cached + SReclaimable − Shmem     [KiB]
```

实现：`oom_gate.sh` 的 `eff_idle_kb()`（`awk` 单遍读 `/proc/meminfo`；**行号会漂，按函数名找**）。

**为什么不是别的量**（三条已定谳机理）：

1. **设备内存不进 RSS/cgroup** ⇒ `docker --memory` 拦不住 ⇒ **守不住就得停机**。
2. **device free 跟的是 `MemFree`，不是 `MemAvailable`**
   （实测 `MemFree 9.5 / Cached 103 / device free 9.1`）⇒ `MemAvailable` 在被检查量上系统性偏乐观；
   干净页缓存是可回收的、必须计入"有效空闲"。
3. **与量具同口径**：`v41_memwatch.sh` 与 `v41_memwatch_report.py` 用的是**逐字节同款**公式，
   避免"量具与被判据量不同口径"——这是本项目已付过学费的病类。
   ⇒ 改公式必须**两边同时改**。

> 一处历史包袱：`kind=memfree` 的注册项（`guards.conf` 的 `pool-free` 行）期望值是 **`110000` MiB ≈ 107.4 GiB**，
> 而 `pre -t` 的门限是 **110 GiB**。两者**不完全等价**，以 `guardctl preflight` 的实际判定为准。

---

## 2. 四条线（子命令与实参）

| 子命令 | 完整实参 | 门限 | 动作 | 退出码 |
|---|---|---|---|---|
| `pre` | `pre [-t GIB] [--strict-containers] [--local]` | `-t` 默认 **110 GiB** | **拒启**（硬门，非告警） | `0` 放行 / `1` 拒启 |
| `monitor` | 见 §2.1 | 四条线全在这个子命令里 | 见 §3 | `0`（`--once` 无触发）/ `3` / `4` |
| `baseline` | `baseline > file` | — | 采窗口基线（NVRM/host-OOM 计数） | — |
| `post` | `post <file>` | 任一增量 > 0 | **判假绿，结论作废** | `0` 干净 / `1` 被污染 / `2` 基线文件缺失 |
| `snapshot` | `snapshot [why]` | — | 手动落一份现场（不起守护） | `0` |

### 2.1 `monitor` 的在役实参（**必须逐字一致**）

```
oom_gate.sh monitor -w 6 -f 1.5 -n 3 --iv 10 -a -e 1
```

三处同源，逐字核对过：

| 出处 | 内容 |
|---|---|
| `/etc/systemd/system/oom-gate-monitor.service:9` | `ExecStart=/bin/bash /home/liux***ya/w6-kit/oom-gate/oom_gate.sh monitor -w 6 -f 1.5 -n 3 --iv 10 -a -e 1` |
| `../guard/guards.conf` 的 `oom-gate-floor` 行 | `PRECOND\|all\|oom-gate-floor\|proc\|oom_gate[.]sh monitor -w 6 -f 1.5 -n 3 --iv 10 -a -e 1\|1\|no\|…` |
| 运行中进程 argv（实测 `pgrep -af`，2026-09-23） | `846274 /bin/bash /home/liux***ya/w6-kit/oom-gate/oom_gate.sh monitor -w 6 -f 1.5 -n 3 --iv 10 -a -e 1` |

四个旋钮的含义与取值理由：

| 旋钮 | 值 | 含义 | 为什么是这个值 |
|---|---|---|---|
| `-w` | **6** | **警戒线：只记日志，不动作** | 用户"把地板买回 6"的原意，以可安全兑现的形态落地。此前"正常"与"逼近止损线"之间**没有任何信号** |
| `-f` | **1.5**（2026-09-23 起；原 3） | **止损线：动作 = `docker stop`** | 用户令 2026-09-23 由 3 下调（ADR-004 §0.1），**唯一会动手的值**。不可抬到 6——见下 |
| `-n` | **3** | 连续破线次数才动作（配合 `--iv 10` ⇒ 30 s 确认窗） | `-f` 是运营包络外的**提前**止损，可容忍确认延迟 |
| `--iv` | **10** | 采样间隔秒 | 3×10 s 确认窗；快于 `-f` 的语义所需，慢于 `-e` 的容错所需 |
| `-a` | — | 启用动作（去掉它 = 仅告警） | 2026-09-15 W4 的教训：无人值守时"只出声"等于没有 |
| `-e` | **1** | **应急线：单采样、零等待立即止损** | 最后 1 GiB 里**没有时间做确认**（实测：`0.9GiB<1GiB` 单采样开火） |

> ⚠️ **止损线为什么不能抬到 6（勿"顺手调大"；2026-09-23 起取 1.5）**：实测最坏合法负载 16 路 × 245.7K
> （= 生产 NSEQ）的 `eff_MIN = 6.58 GiB`。**止损线放到 6 就落在运营包络之内 ⇒
> 一个略重的合法负载就会不可逆地 `docker stop` 生产。**（依据 `guards.conf` 的 `oom-gate-floor` 行）
>
> ⚠️ **改任一条线必须同时改 `guards.conf` 的 `oom-gate-floor` 行**，否则报参数漂移。参数住在**运行进程的 argv** 里，
> 脚本文件里的只是默认值——所以注册表用 `proc` kind 而不是 `envpin`。

---

## 3. 动作与**动作顺序**（不可换）

### 3.1 判定优先级（`oom_gate.sh` 的 `monitor` 主循环 —— `while :; do … done` 那一段）

循环体里三条线**互不干扰**，顺序固定：

```
① -e 应急线（放在最前，这 1 GiB 里没有时间做确认）
② -w 警戒线（只记日志，各自计数、各自复位）
③ -f 地板线（需 -n 连续）
④ --once 短路退出（未触发任何动作才走到这里）
```

### 3.2 触发后的动作序列：**现场快照 → `sync` → `docker stop`**

```
snapshot("emer-<G>GiB" | "floor-<G>GiB")     # ① 先留现场
  ↓
timeout 3 sync                              # ② 再发 sync（带时间盒，有界放弃）
  ↓
for c in $(docker ps --format '{{.Names}}' | grep "$V41_PAT"); do
    docker stop -t 15 "$c"    # 应急线（各 ~15 s 短超时）
    docker stop -t 60 "$c"    # 地板线
done
```

**顺序为何不可换**：`sync` 在极端压力下可能长尾（写回 GB 级脏页），**现场不能赌它**。

**两条纪律**（`oom_gate.sh` 头部「纪律（防"保护动作本身变成事故"）」注释段 —— **行号会漂，按该行名找**）：

1. **永不改变止损决定**——快照/同步全失败也照旧 `docker stop`，**退出码不变**；
2. 每个采集器独立 `timeout 3`，fork/exec 在 <1 GiB 下可能失败，失败只是少几行；
   **绝不 fsync 整机**。

**被杀对象**：`V41_PAT="${V41_PAT:-vllm-v41-\|dsv41-}"`（BRE，`grep` 不带 `-E`）——
即本机所有匹配 `vllm-v41-*` 或 `dsv41-*` 的**运行中**容器。

---

## 4. 退出码语义

| 码 | 场景 | 备注 |
|---|---|---|
| `0` | `monitor --once` 单采样完成且未触发任何动作 | 自检/演练路径（`oom_gate.sh` 的 `--once` 短路退出分支：`if [ "$ONCE" = 1 ]`） |
| `0` | `pre` 四机全过 | 打印「四机全过，放行」 |
| `1` | `pre` 拒启（A1 硬门） | **拒启不是告警**——不许启动 |
| `1` | `post` 窗口被污染 | 任一 `ΔNVRM>0` 或 `ΔhostOOM>0` ⇒ 本轮结论作废（F2/F3） |
| `2` | 未知参数 / `post` 基线文件不存在 / 无子命令 | `oom_gate.sh` 的三处 `exit 2`（未知参数 / 基线文件不存在 / 无子命令——`usage` 兜底分支） |
| **`3`** | **地板击穿 ⇒ 已 `docker stop`** | 地板线，`-n` 连续确认后 |
| **`4`** | **应急线击穿 ⇒ 已 `docker stop`** | 单采样零等待 |

> 退出码是**判决的一部分**：`3`/`4` 都意味着"这台机器刚刚被守卫停掉了生产"，
> 任何读到它们的脚本都不许当普通失败处理（`v41_dose_ladder.sh` 的 `guard_stop(ADR-004)` 判据块就是照这个语义写的）。

---

## 5. `snapshot` 落了什么（13 类文件）

单采集器都有 `timeout 3` 时间盒；**输出协议：stdout 只出一行 = 目录路径**
（调用方 `dir=$(snapshot …)` 直接可用），进度/告警一律走 stderr
（否则会被命令替换吞掉，日志里什么都看不见）。

目录名：`$SNAPBASE/<hostname>.<YYYYmmddTHHMMSS>.<why>`，`why` ∈ `manual` / `emer-<G>GiB` / `floor-<G>GiB`。

| 文件 | 内容 | 为什么留 |
|---|---|---|
| `00-trigger.txt` | `why` / 时间 / 主机 / **当时的 gate 参数** / 有效空闲 / `uptime` | 事后复核"是哪条线、什么参数下打的" |
| `10-meminfo.txt` | `/proc/meminfo` 的 18 个关键字段 | 口径可复算 |
| `11-psi-memory.txt` / `11-psi-io.txt` / `11-psi-cpu.txt` | **PSI** | ★唯一给出"卡了多久"的官方口径 |
| `12-vmstat.txt` | `/proc/vmstat` 全量 | 回收/换页态势 |
| `13-loadavg.txt` | `/proc/loadavg` | — |
| `20-ps-rss.txt` | `ps -eo pid,ppid,rss,vsz,stat,etimes,comm --sort=-rss` | 进程树（`docker stop` 后即销毁） |
| `30-docker.txt` | `docker ps` / `docker stats --no-stream` / **逐容器 cgroup** | `memory.peak` = 本容器历史峰值，事后归因关键 |
| `32-cg-host.txt` | 本机（host）cgroup `memory.stat` + `memory.current` | — |
| `40-kernel.txt` | `dmesg` + `journalctl -k` 尾 60 行 | — |
| `41-counters.txt` | `NV_ERR_NO_MEMORY` 计数、`Out of memory: Killed` 计数 | 事后对账 |
| `50-v41-procs.txt` | 运行中的 `vllm-v41` / `dsv41` / `sglang` / `python3` 进程前 40 行 | 谁在被杀之列 |

**逐容器 cgroup 的坑（已修，勿改回去）**：必须用 `docker inspect` 拿**全 64 位** id。
`docker ps -q` 只给 12 位短 id，而 cgroup 目录名用全长 id——2026-09-22 实测短 id 拼路径
**全部落空，且是静默落空**（段落照打、路径一条没有，读者会误以为"这台机器没有 cgroup"）。
现行实现双路兜底：① PID 反查 `/proc/$pid/cgroup`（与 cgroup 驱动无关）② 两种已知布局；
两条都拿不到时**显式打 ⚠**，绝不静默（`oom_gate.sh` 的「逐容器 cgroup」采集段 —— **行号会漂，按该段注释找**）。

> **计数口径提醒**：`30-docker.txt` 里的 `memory.peak` 是 **cgroup/MEMCG** 口径。
> 与本 ADR/守卫判据的 `eff_idle` **不是同一个量**。历史教训：`guardctl doctor` 曾数的
> 964 条 oom-kill 全属监控栈 `dcgm-exporter` 的 MEMCG 级 60 s 重启环，与应用级 OOM 无关
> ⇒ **MEMCG 级与应用级 OOM 分开数**。

---

## 6. 环境旋钮

| 变量 | 默认 | 作用 |
|---|---|---|
| `V41_GATE_SNAP` | `1` | **关掉止损前现场快照**（`=0`）。判别式自检的反例就靠它 |
| `V41_GATE_SNAP_DIR` | `~/w6-kit/oom-gate/logs/site` | 快照根目录 |
| `V41_GATE_LOG` | `~/w6-kit/oom-gate/logs/oom-gate-monitor-$(hostname).log` | 守护自己的日志 |
| `V41_GATE_ALERTS` | `~/w6-kit/guard/guard-alerts.log` | 告警落盘位置（**与 `guardctl alert()` 同格式**，同一采集面可抓） |
| `V41_GATE_NO_LOGGER` | `0` | `=1` 不写 syslog（**自检用：防演练制造假事故痕迹**） |
| `GUARD_ALERT_HOOK` | 空 | 非空则 `curl` 一个 JSON webhook |
| `V41_PAT` | `vllm-v41-\|dsv41-` | 被杀容器的名字正则（BRE） |

**对外出声**（`oom_gate.sh` 的 `shout()`）三路并行：`guard-alerts.log` + `logger -t oom-gate -p daemon.err` + 可选 webhook。
三路都 `|| true`——**出声失败不影响止损**。

---

## 7. 日志位置

| 日志 | 路径 | 内容 |
|---|---|---|
| 守护主日志 | `~/w6-kit/oom-gate/logs/oom-gate-monitor-<hostname>.log` | 每次采样**只在越线时**落行：低于警戒线 / 破地板 / 击穿 / 复位 |
| 告警账 | `~/w6-kit/guard/guard-alerts.log` | 与 guardctl 同一本账（`CRIT`/`WARN` 行） |
| syslog | `logger -t oom-gate` | 便于接入既有告警链 |
| 现场快照 | `~/w6-kit/oom-gate/logs/site/<host>.<ts>.<why>/` | 见 §5 |

> ★**日志曾迁过一次**（2026-09-20 H5）：此前止损日志在 `/tmp`，**重启即丢**
> ⇒ "止损已发生"的证据链不可追溯；且 `docker stop` 之后单元会拉起新 monitor，
> 此前唯一痕迹在 `/tmp` 里 = **无声止损**。现行路径在 `$HOME` 下。

日志行的可读形态（真实样张，取自 `logs/oom-gate-monitor-dgxspark01.log`）：

```
2026-09-21T16:47:06+00:00 破地板 2.9GiB<3GiB (1/3)
2026-09-21T16:47:16+00:00 回到地板上方 3.0GiB（复位）
2026-09-21T17:14:31+00:00 ★★应急线击穿 0.9GiB<1GiB ⇒ 立即止损（不等 -n 确认）
2026-09-22T11:10:15+00:00 ★地板击穿 ⇒ 自动 docker stop 本机 v41 容器（ADR-004 止损）
2026-09-22T11:10:15+00:00 止损完成
```

**下游判据**：`v41_dose_ladder.sh` 的 `note="…,guard_stop(ADR-004)"` 判据就用「剂量后**新增行**里有没有『地板击穿』」判定
"这档是不是被守卫停的"（**行号会漂，按该 `note=` 文本与这句 `grep` 找**）——**必须能一眼看出，不能靠猜**。

---

## 8. 自检：`selftest_snapshot.sh`

```bash
bash ~/w6-kit/oom-gate/selftest_snapshot.sh
```

**全程用假 docker（`PATH` 前置）+ 临时目录，不碰真容器、不写真告警账、不写 syslog**
（`V41_GATE_NO_LOGGER=1`）。它要证明的不是"脚本没报错"，而是四条**能变红**的断言：

| 组 | 断言 | 判别性 |
|---|---|---|
| **T1** | 退出码 `4`（应急止损）；假 docker 收到 `stop`；**`stop` 那一刻快照已在盘上（`ORDER=yes`）**；快照目录已建；文件数 ≥8；`10-meminfo.txt` 含真数据；`00-trigger.txt` 记了 `why=emer-`；`20-ps-rss.txt` 有进程行；告警账已出声；日志含耗时 | **核心**：现场必须**早于** `docker stop` |
| **T1-对照** | `V41_GATE_SNAP=0` 时：同一断言**必须报红**（`ORDER=no`），且退出码仍 `4` | ★**证明 T1 测的是机制不是环境** |
| **T2** | 快照目录不可写时：退出码仍 `4`、假 docker 仍收到 `stop`、日志明说"跳过，不影响止损" | 保护动作失败**不得阻断**止损 |
| **T2b** | `-f 999999 -n 1` ⇒ 退出码 `3`、现场先于 `stop`、原因记为 `floor-` | 地板线与应急线**证据规格同款** |
| **T3** | 未击穿门槛时：退出码 `0`、**假 docker 无 `stop` 调用** | 不许顺手停容器 |
| **T3b** | 仅告警模式（无 `-a`）即使击穿也**绝不** `docker stop` | `-a` 是唯一动作开关 |
| **T4** | `snapshot` 子命令：退出码 `0`、stdout 打印现场路径、目录名带 `adhoc` 标记 | 运维手动抓现场可用 |
| **T5** | `30-docker.txt` 用了**全 64 位 id**、**真的读到了 cgroup 文件**（有 `## ` 路径行）、含 `memory.peak` | 钉住"12 位短 id 静默落空"这个实测缺陷 |
| **T5b** | id 退化为短 id + PID 不存在 ⇒ **必须显式打 ⚠**，且**不再有 `## ` 行** | 反例：确无数据时不许假绿 |

夹具的两个关键设计（`selftest_snapshot.sh` 的假 `docker` 夹具段：`ps)`/`inspect)` 分支与 `FAKE_CID_FULL`/`FAKE_CID_PID` 导出段
—— **行号会漂，按这些行名找**）：
假 `docker ps` **必须吐出一个名字**（否则 `for` 循环体永不执行，断言会"因为没有容器"而假绿
—— 这正是本项目头号病类：**测试环境而非测机制**）；假 `docker inspect` 回**全 64 位 id**，
PID 指向自检 shell 本身（其 `/proc/$PID/cgroup` 真实可读）。

退出码：全过 `0`；有断言未过 `1` 并打印 `⛔ 有断言未过 ⇒ 止损前保护**不可上线**`。

---

## 9. 部署形态（谁在什么时候跑它）

**在役**：`/etc/systemd/system/oom-gate-monitor.service`（**system 域**，不是 user 域）

```ini
[Service]
Type=simple
User=liux***ya
ExecStart=/bin/bash /home/liux***ya/w6-kit/oom-gate/oom_gate.sh monitor -w 6 -f 1.5 -n 3 --iv 10 -a -e 1
Restart=always
RestartSec=10
```

- `Restart=always` 是 2026-09-18 的**根治**：此前是 `setsid` **裸进程**，
  机器重启或被人 kill 后不会自愈——"不随整机重启自启"正是 2026-09-18 01 那次 OOM 未被预拦的根因。
- 单元文件随包交付件在本目录（`oom-gate-monitor.service`），**装到 `/etc/systemd/system/` 需要 root**。
- 停机演练：`systemctl stop oom-gate-monitor.service` → 演练 → `systemctl start`（**记得看它真的起来了**）。
- 注册表里对应两行：`guards.conf` 的 `oom-gate-monitor.service` 行（`GUARD|all|oom-gate-monitor.service`，必需=**yes**）
  与 `guards.conf` 的 `oom-gate-monitor` 行（`PRECOND|all|oom-gate-monitor`，必需=**yes**，开窗前必须确认在役）。

> **停泊语义注意**：`guardctl hold/release` 会按单元类型生成对应停泊桩。
> `oom-gate-monitor.service` 是 `simple` + `Restart=always` ⇒ 停泊桩必须**驻留不退出**；
> 写成 `exit 0` 会触发 systemd 重启风暴（见 `../guard/README.md` §4）。

---

## 10. 已知刀口（读之前先知道）

### 10.1 `/proc/meminfo` 读失败时 `GIB` 可能算成 `0.0`，从而在 `-e` 下直接止损

**静态阅读得出，未做故障注入验证。**（本节的行名锚点：`eff_idle_kb()` / `_eff_gib()` / `monitor` 循环 —— **行号会漂，按这些行名找**。）

`eff_idle_kb()`（`awk '…END{print f+c+s-m}'`）若四个字段一个都没匹配到，
`f/c/s/m` 全是未初始化变量，awk 按 **0** 处理 ⇒ 打印 `0`。
上层 `_eff_gib()` 与 `monitor` 循环里的 `GIB=` 采样行都用
`awk -v k=… 'BEGIN{printf "%.1f", k/1048576}'` ⇒ 得到 **`0.0`**。
而应急线判据是 `g < e`（`monitor` 循环最前那行的 `awk … 'BEGIN{exit !(g<e)}'`）⇒ `0.0 < 1` 成立 ⇒ **立即止损**。

即：**一次 `/proc/meminfo` 读取失败（或字段名意外变化）就可能被读成"内存耗尽"，
直接 `docker stop` 生产。**

- 现实概率低（`/proc/meminfo` 是内核合成文件，几乎不会部分失败），但**代价不可逆**。
- 最小加固方向（未实施）：在 `awk` 里断言 `f+c+s+m > 0` 才输出数值，
  否则输出哨兵并使该轮采样**跳过判决**（而不是当成 0）。
- 验证方式（未做）：故障注入 —— 把 `eff_idle_kb` 的输入换成空文件跑 `monitor -e 1 --once -a`，
  看是否真的落到 `exit 4`。**在未验证前，本条只能登记为风险项，不许当成"不会发生"。**

### 10.2 止损前保护**尚未在真实止损路径上落过盘**

`~/w6-kit/oom-gate/logs/site/` **目录不存在**（`test -d` 实测）。

时间线解释了原因：快照机制 **2026-09-22 15:17** 才进脚本，而四机最后一次真实地板击穿是
**2026-09-22 14:52:42**（`logs/oom-gate-monitor-dgxspark01.log` 里该时间戳那行；**日志是追加件，
行号会随新增行漂移 —— 按时间戳找，不要记行号**）。
⇒ **全部 6 次真实击穿（5 次 `-f` + 1 次 `-e`）都发生在快照机制上线之前。**

目前证明它按设计工作的**唯一**证据是 `selftest_snapshot.sh`（假 docker 夹具）。
**"有机制" ≠ "机制有效"** —— 这是本项目头号病类，故在此显式登记。

### 10.3 其余

| 项 | 说明 |
|---|---|
| 只有 01 的日志在本目录 | 日志路径含 `$(hostname)`；三台 worker 的止损事实在各自 home 下，跨机对账须逐机取 |
| `pre` 的门限未被注册表钉住 | `guards.conf` 的 `oom-gate-floor` 行只钉 `monitor` 的 argv；`pre -t 110` / `--strict-containers` 改动肉眼不可见 |
| 四机无免密 ssh ⇒ `pre` 在 worker 上须 `--local` | 机间无免密 ssh 时嵌套查询会假 `0.0`；**四机全检由 rank0/操作者在 01 侧承担**（`oom_gate.sh` 的 `pre)` 分支里 `--local` 那两行注释，**按行名找**） |
| `-e 1` 的取值无独立实测支撑 | 来自用户令（"剩余内存 ≤1G 及时 kill 推理"） |
| 停机 ≠ 恢复机器 | 若驱动已楔死不还内存，`docker stop` 不够，需要**冷断电**（见 `../WINDOW-RUNBOOK.md` §7） |

---

## 11. 文件清单

| 文件 | 作用 |
|---|---|
| `oom_gate.sh` | 主脚本（299 行，2026-09-23 实测 `wc -l`；**行数随版本变动，以 `wc -l` 为准**）：`pre` / `baseline` / `post` / `monitor` / `snapshot` |
| `oom-gate-monitor.service` | systemd 单元模板（命令行在 `ExecStart`，与 `guards.conf` 的 `oom-gate-floor` 行同源） |
| `selftest_snapshot.sh` | 判别式自检（T1/T1-对照/T2/T2b/T3/T3b/T4/T5/T5b） |
| `oom_gate.sh.pre-e-tier-20260918` | 历史副本：**加 `-e` 应急线之前的版本**（152 行）。`ADR-004` 引用在 `:133` |
| `logs/oom-gate-monitor-<host>.log` | 守护主日志 |
| `logs/site/` | 现场快照根（**当前不存在**，见 §10.2） |
| `logs/warm-cache-<host>.log` | 由 `../v41_warm_cache.sh` 写入（**不属本目录职责**，只是共用日志目录） |

---

## 12. 相关

- **`../adr/ADR-004-three-gib-floor-guard.md`** —— 为什么是 `eff_idle`、为什么止损线是 1.5 GiB、为什么必须先留现场
- `../guard/README.md` —— 守卫体系统览（`guardctl status/check/preflight/explain/doctor/hold/release/watch/snapshot`）
- `../guard/guards.conf` —— 注册表唯一事实来源（`oom-gate-monitor` / `oom-gate-floor` / `oom-gate-monitor.service` 三行与本目录相关）
- `../WINDOW-RUNBOOK.md` —— 开窗纪律；§5 停泊/放行、§7 时钟健康预检
- `../v41_memwatch.sh` + `../v41_memwatch_report.py` —— 同口径的瞬态量具（G1/G2 判决）
- `../FABRIC-GID-REPAIR-RUNBOOK.md` §7 —— 停机之后的下一步（PD 安全模式时钟楔死 / 冷断电）
