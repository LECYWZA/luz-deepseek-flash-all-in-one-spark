# WINDOW-RUNBOOK —— 维护窗口纪律（开窗 / 关窗）

> 适用：4×DGX Spark（GB10）TP4 集群 dgxspark01..04，生产 = SGLang 栈（`dsv41-head` / `dsv41-worker`）
> 版本：2026-09-23 首版（**本文件是 `guard/guards.conf` 的 `guard-watch` 行（含其上方注释块）引用的
> 「WINDOW-RUNBOOK §5/§7」的真身**，
> 此前该引用指向一个不存在的文件）
> 定位：**本册只管"窗口该怎么做"**。守卫是什么、坏了怎么修 → `guard/README.md`；
> 内存地板守卫 → `oom-gate/README.md` + `adr/ADR-004-three-gib-floor-guard.md`；
> 断电/楔死复核 → `FABRIC-GID-REPAIR-RUNBOOK.md`。

**读者**：要在窗口里动生产四机的人。**每一条都对应一次已经发生过的事故**——
不是风格建议。看不到出处的条目，本册一律标注「未核实」或不写。

---

## §0 开窗前必读：一条铁律清单

### 0.1 `ENV_FILE=` 必带（★本清单第一条）

```bash
ENV_FILE=.env.tp4 ./start.sh serve                 # 生产形态
ENV_FILE=.env.tp4-600k ./start.sh serve            # 窗口实验形态
```

**为什么**：不带 `ENV_FILE` 时 `start.sh` 会静默 source **过期的 dev `.env`**
（`CHUNKED_PREFILL_SIZE=1024` vs 生产已验证的 4096/8192），层级门只会在很晚才抓到。
出处：`start.sh` 的 `2026-09-21 (batch 7 lesson)` 注释块（注释里就写着"the tier gate catches it late"）。

**现行兜底（不要依赖它）**：`start.sh` 的 `有 .env.tp4 即默认生产形态` 注释块在检测到 `.env.tp4` 时会默认按生产四机形态加载并
在 stderr 打印一行说明；同时 `start.sh` 的 `_SHADOW_WATCH` 遮蔽快照表
（`IMAGE / API_KEY / EXTRA_DOCKER_ENV / EXTRA_SGLANG_ARGS / CHUNKED_PREFILL_SIZE / SKIP_SMOKE / SKIP_PREPARE / NFS_SHARE`）
——`source` 覆盖调用方已导出的同名变量时**拒绝起栈**。
⇒ 想改引擎参数请走 `EXTRA_SGLANG_ARGS_APPEND='…'`；想换整组实验请
`cp $ENV_FILE ${ENV_FILE}-xxx` 改行后 `ENV_FILE=${ENV_FILE}-xxx`。

> ⚠️ `- APPEND` 口是有教训的：`EXTRA_SGLANG_ARGS` 曾被 `source` 静默吞掉，而全部预检在
> **被吞后的值**上自洽通过、全绿放行。

### 0.2 开窗第一步＝停保活单元

```bash
systemctl --user stop dsv41-serve.service
```

**红线序列（W0）**：
`systemctl --user stop dsv41-serve.service` → `bash stop.sh`（残留复核 exit 0）→ `drop_caches` → 栈停态快照。
出处：`~/CTX600K-WINDOW-EXECUTION-PLAN-20260921.md:41`。

**为什么必须先停单元**：`dsv41-serve.service` 是 `Restart=always` 的 launcher-waiter
（`ExecStart=/bin/bash -c 'ENV_FILE=.env.tp4 ./start.sh serve; RC=$?; …; exec docker wait dsv41-head'`）。
**不停它就直接停容器 = 30 秒后它自己爬回来**，和你的窗口抢内存池和端口。

**这条已被固化进工具**：`v41_dose_ladder.sh` 里「`dsv41-serve.service` active ⇒ 拒跑」那个门槛块
（以 `say "⛔ dsv41-serve.service active …"` 那行为锚，**行号会漂，按行名找**）在起剂量前检查
`systemctl --user is-active dsv41-serve.service`，active 即 `exit 3` 拒跑，文案是
「开窗纪律要求先 systemctl --user stop（拒绝在保活单元下跑剂量）」。

### 0.3 serve 前必须 `drop_caches`

```bash
sync; echo 3 > /proc/sys/vm/drop_caches        # 需 sudo
```

**为什么**：GB10 上 **device free 跟踪的是 `MemFree` 而非 `MemAvailable`**，
而 device free ≈ MemFree 是**逐位实测的恒等**（`v41_devfree_host.sh` 头部注释的**恒等断言**段：
`dev_free=93.06GiB / MemFree=93.06GiB / MemAvailable=114.30GiB / Cached=21.46GiB`；
**行号会漂，按「恒等断言」那两行找**）。
⇒ 任何"把 MemFree 变成 Cached"的操作（读权重预热、大文件拷贝、镜像拉取）
都在 **1:1 挖走设备可用内存**，不清缓存会在权重加载阶段 OOM。
出处：`r4-ops-work/r9-ops-20260914/evidence/delivery-20260916/DELIVERABLE-CHECKLIST-20260916.md` §3「必须知道的坑（都真实发生过）」第 1 条。
（该文只有六节、节内是编号清单，**没有子节号** —— 引用一律按「§N 第 M 条」写。）

**四机都要做**（`v41_win_mmprobe.sh` 的「① 四机 `drop_caches`」那一步就是四机 `drop_caches` + 打印空闲；
**行号会漂，按行名找**）。

> ⚠️ **`drop_caches` 是必要但不充分的**：注册表里另有一条**裸 MemFree** 前置
> （`guards.conf` 的 `memfree-raw-vllm` 行：裸 MemFree ≥ 96 GiB），因为干净页缓存虽可回收，
> 但**设备侧的分配路径不会优雅回收它**。停栈后应见裸 `MemFree ≈100+ GiB`；
> 低于 96 GiB 说明卫生没做。
>
> ⚠️ **`eff_idle` 看不见这件事**：`Cached` 本就在 `eff_idle` 公式里 ⇒ 页缓存预热
> 对 `eff_idle` 近乎零影响（实测预热 8 GiB ⇒ device free **−7.98** 而 `eff_idle` **+0.01**），
> 但设备侧已经少了 8 GiB。**判内存要同时看「设备可见空闲」和 `eff_idle` 两路。**

### 0.4 生产在跑时禁做 GPU / 显存测试

> 「**服务在跑时不要做显存/基准测试；永不发大额 fill/commit 探针**（曾把内核逼到 OOM killer，
> 打死过节点与 registry）。」
> 出处：`…/delivery-20260916/DELIVERABLE-CHECKLIST-20260916.md` §3「必须知道的坑（都真实发生过）」第 4 条；同文 `OUT-OF-BOX-DEPLOY.md` §7「常见坑（都踩过）」第 3 条。

### 0.5 探针请求必须 `≤ free − 4 GiB`，且**每次换 nonce**

- **`≤ free − 4 GiB` 是红线**。0211 事故：请求距 free 仅 ~1.3 GiB 时（118 GiB 请求 @ free 116.7），
  驱动向内核施压 ⇒ swap off 下 **OOM killer 扫射**，且**击杀的是最大 RSS 进程而非探针**——
  02 上 registry/aicad 容器/dbus/avahi 被连杀，`sshd` 饿死 35+ 分钟，02/04 被打到**重启**
  （sysctl/swap/NFS 挂载全丢，`docker restart=always` 把 15 个已停泊 aicad 容器全部拉回）。
  出处：`V41-SGLANG-MOE-DENSE-REPORT-AND-PLANS-20260915.md:383`、`V41-OPTIMIZATION-MASTER-TASKPLAN-20260915.md:330`。
- **nonce 逐请求唯一**：同文会命中 radix 前缀缓存 ⇒ **2 秒返回的假 TTFT**。
  出处：`DELIVERABLE-CHECKLIST-20260916.md` §3「必须知道的坑（都真实发生过）」第 5 条。
- 工具侧的等价护栏：`v41_devfree_host.sh` 的 `--min4` 在 `MemFree<4GiB` 时**拒绝建上下文**。

### 0.6 `pkill` / `pgrep` 用方括号形式，且**杀与起拆开执行**

```bash
pgrep -af 'oom_gate[.]sh monitor'      # ✓ 不会匹配到自己
pkill    'oom_gate[.]sh monitor'       # ✗ 经 ssh 在本机跑会匹配到自己的 argv
```

出处：`DELIVERABLE-CHECKLIST-20260916.md` §3「必须知道的坑（都真实发生过）」第 6 条、`OUT-OF-BOX-DEPLOY.md` §7「常见坑（都踩过）」第 5 条 ——
「经 ssh 在本机跑会匹配到自己的 argv，**曾连杀三次**」。
`~/w6-kit/wait_kfix_ab.sh` 的头部注释也把这条写成了它存在的理由。

### 0.7 永不 `apt dist-upgrade`；永不 unhold 内核元包

- **永不执行 `apt dist-upgrade`**：干跑已证它会把 `linux-tools-nvidia-hwe-24.04` 抬到
  **7.0.0-1019.19**（= 已知打瘫 NCCL/RoCE 的那个内核），并引入
  `nvidia-spark-grub-kho` / `dgx-spark-ota-update-meta`。
- **永不 unhold** 已在册的两个 hwe 元包：
  `linux-image-nvidia-hwe-24.04`、`linux-nvidia-hwe-24.04` —— 放开即会拉到 7.0.0-1019。
- 原文与 `apt-mark` 清单（含"哪些故意**不** hold 及为什么"）：
  `~/drv-flavor-window/apply-holds.sh:7-20`；结论另见 `~/V41-DRIVER-VERIFY-VERDICT-20260922.md:163`。
- 每次 `apt upgrade` 后查 `/var/log/nvidia-module-guard.log`（应恒为 `[OK] … 580.173.02`）。

### 0.8 权限与凭据

- **无免密 sudo**：口令外部化在 `~/.sudopw`（600），**只经 stdin**（`printf '%s\n' "$PW" | sudo -S -p ''`），
  **绝不回显、绝不进 argv/日志**。
- ⚠️ **不要用 `sudo -S bash -s <<'EOS'`**：heredoc 会成为 sudo 的 stdin，`-S` 把脚本文本当密码读
  （2026-09-23 四机整齐报"3 次错误密码尝试"）。
- ⚠️ ssh 侧**不要加 `-n`** 当管道里有密码时：`-n` = stdin 重定向自 `/dev/null`，会把密码顶掉
  （同一台机有 `-n` FAIL / 无 `-n` OK，唯一差别就是 `-n`）。出处：`apply-holds.sh:60-66`。

---

## §5 停泊与放行顺序（hold / release）

### 5.1 总开关：`guardctl hold` / `release`

```bash
TAG=$(date -u +%Y%m%dT%H%MZ)-v41
bash ~/w6-kit/guard/guardctl.sh hold    "$TAG"     # 开窗：停泊全部守卫
bash ~/w6-kit/guard/guardctl.sh status             # 确认全部 HELD
#   … 窗口内的操作 …
bash ~/w6-kit/guard/guardctl.sh release "$TAG"     # 关窗：还原 + 断言已重新武装
bash ~/w6-kit/guard/guardctl.sh check              # 必须 ALL-OK 才能宣布收工
```

**正确次序**：`hold` → `status`（确认）→ 停生产 → **`preflight`（必须 READY 才许启动）**
→ 窗口内操作 → `release` → `check`。

- `release` 的**最后一步是断言定时器不再是 `infinity`**——这是"回退完成"的唯一可信证据。
  **脚本还原成功 ≠ 守卫已经恢复工作。**
- `preflight` 在生产**运行时必然报 `BLOCKED`**（池子当然不空）——**那是正确的，不是故障**。
- 细节与原理：`guard/README.md` §7.2、§4（**`oneshot` 是最危险的类型**：
  停泊桩必须与单元类型匹配，写错 = 守卫静默永久失效）。

### 5.2 生产栈的停泊态：恢复生产必须**手动 enable + 带 `ENV_FILE`**

四机 `dsv41-serve.service` 在窗口结束时是 **`stop` + `disable`** 状态
（实测：`Loaded: … disabled; preset: enabled` / `Active: inactive (dead)`）。
**这不会自愈**，原因有二：

1. 单元本身是 `disabled` —— 开机不自启；
2. 即使 enable，**它自己不带 `ENV_FILE`**（`ExecStart` 里内联了 `ENV_FILE=.env.tp4`，
   所以恢复生产 = 恢复这个单元，**不要**手工裸跑 `./start.sh serve`）。

```bash
# 恢复生产的正确形态（四机；head 与 worker 的单元/容器名不同）
systemctl --user enable --now dsv41-serve.service
systemctl --user status dsv41-serve.service        # 必须 active (running)，MainPID = docker wait …
```

**自愈链挂载态的判据**（注册表已固化，`guards.conf` 的 `dsv41-serve-waiter` 行 —— head/worker 各一条）：
`dsv41-serve` 单元的 **MainPID 必须是 `docker wait dsv41-head`**（worker 侧 = `docker wait dsv41-worker`）。
⚠️ **单元名不会出现在进程表里**——2026-09-20 修正：MainPID 的 argv 实为 `docker wait dsv41-head`。
判错这一条会让你以为自愈链在役，其实容器退出后**无人重启**（09-19 曾 38 连败）。

### 5.3 两个**裸进程**守卫的重挂（★`guards.conf` 的 `guard-watch` 行点名的已知缺口）

| 守卫 | 单元保证 | 现行状态 |
|---|---|---|
| `oom_gate.sh monitor -w 6 -f 1.5 -n 3 --iv 10 -a -e 1` | **有**（`oom-gate-monitor.service`，2026-09-18 起） | 在役 |
| `guardctl.sh watch 60`（只读状态观察器） | **无——`setsid` 裸进程** | **当前未运行** |

**缺口内容**（原文即 `guards.conf` 的 `guard-watch` 行**上方那段注释**）：观察器**不在生产路径上**（不碰容器、不写状态），
所以缺失不阻塞开窗（必需=`no`），但它是"状态变化才出声"的告警面。
**它没有任何单元保证 —— 机器重启或被人 kill 后不会自愈。**

```bash
# 重挂（四机；与 guards.conf 的 guard-watch 行描述逐字一致）
setsid --fork bash -c 'exec bash ~/w6-kit/guard/guardctl.sh watch 60'
```

**开窗/关窗时都要确认它在**（`guardctl preflight` 会断言 `proc`）：

```bash
pgrep -af 'guardctl[.]sh watch'     # 方括号形式，见 §0.6
```

> 更完整的替代（无裸进程）：本机已装 `guard-check.timer`（`OnUnitActiveSec=15min`，跑
> `guardctl check`）与 `guard-journal-watch.timer`（10min），
> 但它们**不是**"状态翻转才告警"的等价物。

### 5.4 窗口内的回滚顺序（vLLM 时代的原语，**仅作参照**）

`v41_window_rollback.sh` 头部记录的次序（2026-09-11 窗口验证过）：
①（驱动做）删测试容器 → ②（驱动做）`docker start` 生产容器 → ③ 还原 monitor + healthcheck 脚本
→ ④ kill 停泊的 MainPID 让 systemd 重 exec 真监视器 → ⑤ healthcheck **最后**重建。

**用 `docker start` 而不是重跑启动脚本**是刻意的：它秒级还原**上一次的容器 spec**，保住回滚锚点。

> ⚠️ 这套原语面向的是 **vLLM 时代的 `vllm-tp4-*` 单元**（`start_tp4_head_v043.sh` 等，
> 这些脚本**仍在盘上**）。SGLang 时代的等价物是 `dsv41-serve.service` + `start.sh serve`。
> 开窗时**不要**照抄旧原语去操作新栈。

---

## §7 时钟健康预检（开窗前必做）

> **编号对账（先读这一段，避免"找不到 §7 说的东西"）**
> `guards.conf` 的 `guard-watch` 行（及其上方注释块）点名本册 §7 时的语境是**裸进程缺口**（原文：「它们都是 `setsid` 裸进程、
> 没有任何单元保证（已知缺口，见 WINDOW-RUNBOOK §7）：机器重启或被人 kill 后不会自愈」）。
> 本节按**现行要求**写的是**时钟健康预检**（开窗前必做），
> 裸进程缺口移入 **§7.5**（并已在 §5.3 给出重挂命令）。
>
> ⚠️ **两处引用的对账（2026-09-23）**：`guards.conf` 那段注释是按**旧版 §5.3 标题**逐字引用的，旧标题里带
> 一个**行号**；该行号已随 `guards.conf` 的注释改动失效 ⇒ 本册 §5.3 标题已改为**行名锚点**（`guard-watch` 行），
> 本册内指向 `guards.conf` 的引用**一律按行名写**（不写行号）。§5.3 标题与 `guards.conf` 里那份逐字引用
> 因此有措辞差异，**以本册标题 + `guards.conf` 的行名为准**。
>
> **历史先例**：该目录下此前存在一份**窗口专用**的同名册子 ——
> `~/r4-ops-work/r9-ops-20260914/evidence/delivery-20260916/WINDOW-RUNBOOK-20260917.md`（9507 B，
> 2026-09-17，标题「切换窗口 runbook：容器改由镜像供码」），其 §5 = 治理复位、
> §7 = 已知缺口。**它是那一次切换窗的专用件，不是通用册**；
> 本文件是通用册，两者并存，不要混引。

### 7.1 为什么要查

**GB10「PD 安全模式」时钟楔死**：断电（或 **OOM 事件**）后 USB-C 电源 PD 协商进安全模式，
**SM 时钟钉死在 513-728 MHz 家族**，而**系统层面几乎零标志**。

**2026-09-21 实锤**：`dgxspark02` 断电后钉 **721 MHz**（96 % util / 15 W），
导致 **TP4 全体 collective 等它 ⇒ prefill 均匀减半**（0.2.7 全臂 2210-2821 t/s vs
V4B 锚 4992-5461）。

> 这条病曾**伪装成「0.2.7 版本回归」查了一整天**——排除链走完镜像/env/ctx/autotune 表/fabric
> 全部无差，才落到负载态时钟采样。**负载态时钟是直达确诊的探针。**
> 出处：`FABRIC-GID-REPAIR-RUNBOOK.md` §7、`V41-027-INCIDENT-AND-WINDOW-REPORT-20260921.md:27`。

> ⚠️ **日期更正（如实登记）**：口头传述曾把这起断电记作 2026-09-02。可查证的实锤日期是
> **2026-09-21**（`V41-027-INCIDENT-AND-WINDOW-REPORT-20260921.md:27,32`、
> `FABRIC-GID-REPAIR-RUNBOOK.md:102,116`）。全项目未见 09-02 的 721 MHz 记录。

### 7.2 判据：**必须在负载态复判**

| 读数 | 健康（负载态） | 楔死（负载态） |
|---|---|---|
| `clocks.sm` | **实测 2359–2392 MHz**（判据带 **2350-2400 MHz**） | **~721 MHz**（513-728 家族） |
| `utilization.gpu` | **~96 %** | **96 %**（一样高！） |
| `power.draw` | **56-68 W** | **10-20 W**（健康负载 40 W+） |
| throttle 标志 | — | **零标志** |
| `nvidia-smi -lgc` | — | **静默无效**（`SUPPORTED_CLOCKS=N/A`） |

出处：`~/V41-DRIVER-VERIFY-VERDICT-20260922.md:59-60`（触发窗内四机实测
`clocks.sm 2359–2392 MHz / util 96 % / 56–68 W`，"无 721 MHz 楔死指纹"）。

采集命令：

```bash
nvidia-smi --query-gpu=clocks.sm,utilization.gpu,power.draw --format=csv,noheader
```

⚠️ **解析陷阱（已修过一次）**：旧代码 `tr -d ' %,W'` 会把 CSV `0, 2385, 13.08`
**连成一串** `0238513.08`（bash 八进制非法 ⇒ 每采样窗喷「需要整数表达式」）。
现在按字段拆。出处：`V41-027-INCIDENT-AND-WINDOW-REPORT-20260921.md:88`、`~/ops-handoff-20260921/01-CODE-CHANGES.md:93-94`。

### 7.3 `clock-sm-guard.sh` 的 `[2250,2400]` 是**静态**口径，开窗前必须在**负载态**复判

`guard/clock-sm-guard.sh`：`CAP=2400`、`TOL=150` ⇒ 判据带 **`[2250, 2400] MHz`**；
退出码 `0`=OK / `1`=FAIL / `2`=SKIP（`nvidia-smi` 不可用或无 GPU 可见）。
它在注册表里对应 `guards.conf` 的 `clock-sm-actual` 行（`PRECOND|all|clock-sm-actual|archscr|…`）。

**为什么它不够**（两条已实测的盲区）：

1. **它是"静息态"读法**：引擎停泊时 `clocks.sm` 走低（实测停泊基线 **208 MHz**），
   脚本靠退出码 `2` 表示 SKIP。但那意味着**开窗前如果机器没在跑任何负载，
   这条前置根本判不出 721** —— 208 是停泊基线的假阴坑。
   出处：`V41-DRIVER-FLAVOR-WINDOW-20260922.md:82`。
2. **它只判"当前值在不在带内"**，不判"带上限有没有真的生效"——
   `gb10-clock-cap.service` 的单元检查只看状态不看值，而 `-lgc` 参数漂移在单元层面看不出来。
   （注册表把这两者分开登记：`guards.conf` 的 `gb10-clock-cap` 行判单元状态、`clock-sm-actual` 行判**实际值**。）

⇒ **开窗前的正式判据（负载态复判）**：

1. 确认 `gb10-clock-cap.service` 在役：`systemctl is-active gb10-clock-cap.service`
   （`oneshot` + `RemainAfterExit=yes` ⇒ 成功即常驻 `active`；失效应表现为 `Result≠success` 或单元消失）；
2. 起一个**探针负载**（`powercycle_check.sh` 的 burn 探针即为此设，`util` 需抬到 ≥50 %）；
3. 在负载态同时看三个量：`clocks.sm ∈ [2350,2400] MHz`、`util ≈96 %`、`power ∈ [56,68] W`；
4. **任何一项落入 513-728 MHz / 10-20 W / util 高 → 判楔死**，不要继续开窗。

> **`gate.sh` 的在役门禁等价物**：载荷下 `util≥50 %` 而 `clock<1200 MHz` 即 **FAIL**
> （`FABRIC-GID-REPAIR-RUNBOOK.md` §7「防线」；`V41-027-INCIDENT-AND-WINDOW-REPORT-20260921.md:72`）。

### 7.4 唯一修复：**拔墙上 AC 冷断电 1-2 分钟**

1. 关机 → **拔墙上 AC 插座 1-2 分钟**（**不是机箱端 USB-C！**；有帖建议按住电源键 10 s 放残电）
   → 回插 → 开机。
2. 验证：负载态 `clocks.sm ≥ 2300 MHz` / `power ≥ 40 W`。
3. ⚠️ **warm reboot（`systemctl reboot`）不修复** —— 2026-09-21 在 02 实测无效。
4. 冷断电后**必须**再跑一遍断电复核（GID 可能再出洞）：
   `bash ~/w6-kit/powercycle_check.sh`（栈必须停着：burn 探针要独占 GPU；从 01 跑）
   → `0`=全绿可复栈 / `1`=有 FAIL 照输出逐项修。
5. **根治向** = `fwupdmgr` 固件更新（官方称直接修 PD）。⚠️ 但一帖报其引入 **ConnectX-7 网络
   性能回归** —— 对本集群 ring fabric 是高危项，**升级须专窗 + fabric 全档重测，勿顺手升**。

### 7.5 本病与本册的接线

`guards.conf` 的 `guard-watch` 行点名本册 §7 的原因是**同一个结构性事实**：
`guardctl.sh watch` 与（曾经的）`oom_gate.sh monitor` 都是**没有单元保证的裸进程**，
**机器重启后不会自愈**——因此"重启过"这件事本身就是一次**守卫缺失事件**。
⇒ **每次冷断电/重启之后，除了查时钟（本节），还要重挂 §5.3 的观察器并确认
`oom-gate-monitor.service` 已 active。**

---

## §8 测量纪律

### 8.1 测量窗内**不得触碰被测机器**（采分期停外探）

**规矩**：测量窗口内**禁** sparkDash / 指标采样 / 并发 `grep` / 自己 ssh 上去看进度等
**任何外部轮询**。它们会真实污染读数。

**代价实录**：`V41-CTX600K-READINESS-20260922.md:172` ——
8192 / 16384 两档的 tps **被我方并发 `grep` 污染**（违反"采分期停外探"），
同靴干净锚应为 5131 / 4903。
第三方侧的同款事故：他们的 `DE_RC=143` 污染轮。
出处：`V41-THIRDPARTY-PKG3-CROSS-20260920.md` §四第 3 条、`V41-OPTIMIZATION-MASTER-PLAN-V4-20260920.md:77`。

**配套两条**（同章第 2、4 条）：

- **开测前 `pgrep` 残留门**（已固化进采集器，残留即 `exit 3` 拒测）；
- **nonce 逐 run 唯一** + 同格二连跑 ±5 % 一致性检查。
- **journal 假零**：任何"`=0` 事件"结论必须有**可读性探针**背书（H9 教训）。

### 8.2 跨 harness / 通道数字**禁比**

- **通道差实测 ×1.62-2.16（中位 1.75）**：`chat` 通道 vs `native` 通道。
- ⇒ **任何对外比对数字必须同 harness、同通道**；引用他方数字须**标注通道**。
- 出处：`V41-THIRDPARTY-PKG3-CROSS-20260920.md` §四第 1 条；
  `~/ops-handoff-20260921/04-ARCHITECTURE-OPTIMIZATION.md:120`
  （"每臂 ≥2 靴；同 harness 同锚才可比（跨 harness/通道/尺寸禁比）"）。
- 同族纪律：**"复刻"本身会引入口径漂移 ⇒ 锚必须由采集器量**（`V41-027-INCIDENT-AND-WINDOW-REPORT-20260921.md:82`）。

### 8.3 量具缺机 ⇒ 本档判「**不可用**」，不是「全过」

**这条是本项目当前最明确的一条反假绿纪律。**

- 生效例（工具侧）：`v41_memwatch_report.py` 的**空真防线**段（`if not dose_order: … return 2`）——
  `dose_order` 为空时下游 `results` 也为空，而 `bad = [...]` 在空列表上恒空
  ⇒ 会打印「全部档位过闸」并返回 `0`。**判据必须是「有数据」而非「没有坏数据」**
  ⇒ 此处先断非空，否则 `return 2`（原文注释：「判决不可用（不是"全过"）」）。
- 生效例（阶梯侧）：`v41_dose_ladder.sh` 的「量具不完整 ⇒ 本档内存列全部写 `NA`」段 ——
  **量具不完整（缺机/无数字）⇒ 本档内存列全部写 `NA`**：
  「宁可空着，也不许把诊断句子当数据写进账本」。
- 生效例（采样器侧）：`v41_memwatch.sh` 的 `start` 子命令（从 `start)` 分支到 `exit 4`）——
  `start` 等采样**真的落盘**才返 `0`
  （最多 6 s），否则 `exit 4`：
  「静默失败的 `start` 会让该机 0 采样，而报告只按有数据的机器算 ⇒
  **"部分通过" = 缺机裸奔**」。
- 生效例（取回侧）：`v41_dose_ladder.sh` 的 `mw_fetch()`（原子取回）——
  取回**原子**
  （先写 `.tmp`、核点数、再 `mv`）。2026-09-22 事故：旧版 `> 目标文件`
  在 ssh 失败时会把该机**已有**的整轮采样截成 0 字节（**机器没坏，是量具把自己的证据抹了**）。
  取回失败一律**保留旧文件 + 出声**，绝不留 0 字节假文件。

### 8.4 判决口径：**不再对新增 NVRM 计数做判决**

- 用户 2026-09-22 明令：**该门禁无效**。
  实证：`NV_ERR_NO_MEMORY`（`_memdescAllocInternal`）与剂量**不相关**——每档必出、静置不增长；
  发生时 `MemAvailable` 仍有 ≥12.27 GiB；09-14/09-15 早有同量级。
  拿它当停手条件 ⇒ **阶梯永远走不动**。
- **NVRM 行数只记录**（`v41_dose_ladder.sh` 的 `NVNOW=`/`nvrm_remote` 采集行与「NVRM 仅记录」那句闸门说明
  —— **行号会漂，按行名找**）。
- **唯一验收判据 = 形态修复后内存瞬态峰值增量 ≤ 3 GiB**
  （`transient = dip + persist ≤ 3G`），且 `eff_idle = MemFree + Cached + SReclaimable − Shmem`
  与生产地板守卫**逐字节同款**。详见 `adr/ADR-004-three-gib-floor-guard.md`。

---

## 开窗 / 关窗检查表

### 开窗前（全部 `[x]` 才动手）

- [ ] `guardctl.sh check` 全绿（或已知异常已登记）
- [ ] **§7 时钟健康**：起探针负载 → `clocks.sm ∈ [2350,2400] MHz` / `util ≈96 %` / `power ∈ [56,68] W`
- [ ] `systemctl is-active gb10-clock-cap.service` = active
- [ ] **§5.3**：`pgrep -af 'guardctl[.]sh watch'` 有输出（否则按 §5.3 重挂）
- [ ] `systemctl is-active oom-gate-monitor.service` = active；`pgrep -af 'oom_gate[.]sh monitor'` 的 argv **逐字**等于 `-w 6 -f 1.5 -n 3 --iv 10 -a -e 1`
- [ ] 本次窗口要用的 `ENV_FILE` **已显式导出**（§0.1）
- [ ] 记录 TAG：`TAG=$(date -u +%Y%m%dT%H%MZ)-v41`
- [ ] `guardctl.sh hold "$TAG"` → `guardctl.sh status` 确认全 HELD
- [ ] `systemctl --user stop dsv41-serve.service`（§0.2）
- [ ] `bash stop.sh`，残留复核 `exit 0`
- [ ] 四机 `drop_caches`（§0.3）并**验证**裸 `MemFree ≈100+ GiB`
- [ ] `guardctl.sh preflight` = READY（`BLOCKED` 一律不许启动）
- [ ] 栈停态快照已落（含时钟探针顺手跑）

### 窗口内

- [ ] **§8.1** 采分期停外探：不 ssh 上去看进度、不并发 `grep`、不跑指标采样
- [ ] 若起剂量：`FLOOR_G=3` / `TRANSIENT_G=3`（**G1 独立于守卫止损线**：守卫 2026-09-23 起 `-f 1.5`，G1 仍取 3——实验硬停必须高于守卫，理由见 `v41_dose_ladder.sh` 头部），`G2_STOP` 的取值已写明在账本里
- [ ] 每次 `docker cp` 取证据都走 `.tmp` + 核行数 + `mv`（§8.3）
- [ ] 发现 `地板击穿` 行 ⇒ 记 `guard_stop(ADR-004)`，**不要**当成"又崩了"（见 `adr/ADR-004-three-gib-floor-guard.md` §6.1）

### 关窗前

- [ ] `bash stop.sh` 收栈，确认四机无 `dsv41-*` / `vllm-v41-*` 残留容器
- [ ] `guardctl.sh release "$TAG"`
- [ ] `guardctl.sh check` = **ALL-OK**（★`release` 的最后一步是断言定时器不再是 `infinity`；
      脚本还原成功 **≠** 守卫已恢复工作）
- [ ] `pgrep -af 'guardctl[.]sh watch'` 与 `pgrep -af 'oom_gate[.]sh monitor'` 均在役（§5.3）
- [ ] **恢复生产**：`systemctl --user enable --now dsv41-serve.service`（§5.2），
      确认 `MainPID` = `docker wait dsv41-head`（worker = `docker wait dsv41-worker`）
- [ ] `bash ~/w6-kit/powercycle_check.sh`（若本窗发生过断电/冷断电；必须栈停着跑）
- [ ] 已排除的证书/凭据未回显（sudo 口令、API_KEY、治理 key）
- [ ] 窗口报告落盘，账本与快照路径写进报告

---

## 参考

| 文档 | 用途 |
|---|---|
| `guard/README.md` | 守卫体系、`guardctl` 全部子命令、`oneshot` 危险类型、失效形态表 |
| `guard/guards.conf` | 注册表**唯一事实来源**（`GUARD`/`PRECOND`/`RECOVERY`/`TIMER`） |
| `guard/BASELINE.md` | 状态基线（`snapshot` 生成；下半部是历次修订表，**别拿 `snapshot` 刷**） |
| `oom-gate/README.md` | 内存地板守卫手册（四条线、动作顺序、退出码、自检） |
| `adr/ADR-004-three-gib-floor-guard.md` | 为什么是 `eff_idle`、为什么止损线是 1.5 GiB |
| `FABRIC-GID-REPAIR-RUNBOOK.md` | §1 GID 审计 / §5 断电复核 / **§7 时钟楔死** |
| `powercycle_check.sh` | 断电/冷断电后四机一键复核（60 秒扫描，栈停着跑） |
| `v41_dose_ladder.sh` + `v41_memwatch{,_report}.*` | 剂量阶梯 + 同口径瞬态量具（G1/G2） |
| `v41_win_mmprobe.sh` | 现役窗口剧本（①-⑧ 步），可当作本册的一份**可执行样例** |
| `~/drv-flavor-window/apply-holds.sh` | `apt-mark` hold 的不对称设计与"永不 `dist-upgrade`"原文 |
| `~/CTX600K-WINDOW-EXECUTION-PLAN-20260921.md` | W0 红线序列的原始出处 |
| `…/delivery-20260916/OUT-OF-BOX-DEPLOY.md`、`DELIVERABLE-CHECKLIST-20260916.md` | §0 各条铁律的原始出处 |
