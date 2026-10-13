# guardctl — 守卫 / 自恢复 / 健康检查 统一管理套件

> 适用：4×DGX Spark(GB10) TP4 集群（dgxspark01..04）
> 版本：2026-09-11 首版
> 位置：四机 `~/w6-kit/guard/`
> 依赖：仅 bash + systemctl + docker + curl；**全程无需 root**

---

## 1. 为什么需要它

这套栈的容错部件分散在 systemd 单元、60 秒主动重建探针、自愈监视器、取证转储和
业务网关里。它们平时默默工作，**失效时不报警**。

2026-09-11 实测到一个真实的静默失效：head 的 P1 主动重建守卫被上一次维护窗口的
残留停泊进程冻结——单元永远停在 `activating`，定时器 `NextElapse` 变成 `infinity`，
**守卫从此永不触发**，而生产完全健康（网关 200、四 rank healthy），
所以没有任何信号暴露它。它已经"没人守"了 40 分钟。

`guardctl` 把"逐个检查守卫"压缩成一条命令，并把**开关、失效识别、告警、自解释**
统一到一处，避免每次靠人工翻 journal。

---

## 2. 快速上手（五条命令覆盖日常）

```bash
bash ~/w6-kit/guard/guardctl.sh status      # 现在到底谁在守？一眼看全
bash ~/w6-kit/guard/guardctl.sh check       # 机器判据：退出码 0=全好 1=有异常（并给出修复命令）
bash ~/w6-kit/guard/guardctl.sh doctor      # 深诊断：内核 OOM/看门狗/NV_ERR、定时器楔死、状态文件毒化、时钟闩锁
bash ~/w6-kit/guard/guardctl.sh explain vllm-healthcheck.service   # 这个守卫干嘛的？坏了怎么办？
bash ~/w6-kit/guard/guardctl.sh preflight   # 【开窗前必跑】断言启动前置 + 自恢复链；0=可启动 1=不许启动
```

维护窗口的**总开关**（两态，替代手工改脚本）：

```bash
bash ~/w6-kit/guard/guardctl.sh hold    20260912T0300Z-v41   # 关：停泊全部守卫
bash ~/w6-kit/guard/guardctl.sh release 20260912T0300Z-v41   # 开：还原 + 断言已重新武装
```

`preflight` 与 `check` 的差别只有一个：**它真的判定 PRECOND**。原因见 §5.3——
"池子空出来"这类条件在生产正常运行时本就不成立，放进例行 `check` 会每次都 FAIL。

---

## 3. 四机守卫清单（`guards.conf` 是唯一事实来源）

下表**从 `guards.conf` 生成**，不要手抄 —— 上一版就是手抄的，于是它一直在描述
vLLM 时代的三条单元，而生产早已切到 SGLang 栈（reviewer 2026-09-17 抓到）。
★2026-09-23 再生成一次：上一版的 `concurrency-proxy-v2.service` md5 写的是 `0606e1e24926`，
而 `guards.conf:31` 已钉 `d9aeaab640f7`（合法改动记录在 `BASELINE.md` 的「2026-09-18 追记」条）；且当时漏登了
`oom-gate-monitor.service`（`guards.conf:119` 新增）。**以 `guards.conf` 为单一事实源**重生成。

**下表由 `guards.conf` 生成于 2026-09-23**（生成命令见本节末尾；勿手改本表）：

| 主机 | 角色 | 单元 | Type | md5 钉版 | 作用 |
|---|---|---|---|---|---|
| 01 | head | `vllm-logdump.service` | simple | `3d3793d0244a` | 崩溃取证日志转储（容器被删后仍保留日志） |
| 01 | head | `concurrency-proxy-v2.service` | simple | `d9aeaab640f7` | 业务入口 0.0.0.0:8001（SSE 心跳/TTFT 预算/准入背压） |
| 01 | head | `daily-smoke.timer` | oneshot(TIMER→`daily-smoke.service`) | - | 每日冒烟测试的触发链（`NextElapse==infinity` 才算失效） |
| 02-04 | worker | `vllm-logdump.service` | simple | `3d3793d0244a` | 崩溃取证日志转储 |
| 全部 | all | `gb10-clock-cap.service` | oneshot | - | GPU 时钟上限钳制（nvidia-smi -lgc 0,2400） |
| 全部 | all | `oom-gate-monitor.service` | simple | - | OOM 止损守护的 systemd 单元（-w6/-f1.5/-e1 三层） |
| 全部 | all | `nvmodule-guard.service` | oneshot | `989c04d86368` | nvidia 内核模块 flavor 守卫：开机自检 /proc/driver/nvidia/version，见 open 模块则告警 + 停用 nvidia-*-open 目录 + depmod |

**生成规则（2026-09-23 补，便于复核）**：主机列由 `role` 映射（`head`→01、`worker`→02-04、
`all`→全部）；`Type`/`md5 钉版`/`作用` 逐字取自 `guards.conf` 的同名列；`作用` 列**截到第一个
`⚠` 或 `。`**（该列后半是历史注记，全文见 `guards.conf` 对应行）。生成命令：

```bash
cd ~/w6-kit/guard
awk -F'|' '
function host(r){return (r=="head")?"01":((r=="worker")?"02-04":"全部")}
function rank(r){return (r=="head")?1:((r=="worker")?2:3)}
/^GUARD\|/{d=$9; sub(/[⚠。].*/,"",d); printf "%d\t| %s | %s | `%s` | %s | `%s` | %s |\n", rank($2),host($2),$2,$3,$4,$7,d; next}
/^TIMER\|/{d=$6; sub(/[⚠。].*/,"",d); printf "%d\t| %s | %s | `%s` | oneshot(TIMER→%s) | - | %s |\n", rank($2),host($2),$2,$3,$4,d; next}
' guards.conf | sort -s -k1,1n | cut -f2-
```

⚠ 被截断的历史注记里含**判定相关**的三条，此处保留全文（同样是机械抽取，未手抄）：
`vllm-logdump.service`→"…⚠️2026-09-16 修：脚本第 167 行的预过滤是 `grep -E '^vllm'`，
SGLang 容器名 dsv41-* 进不来 ⇒ 切栈后两天零转储"；`concurrency-proxy-v2.service`→"…⚠️仅 head
部署，worker 上不探 8001。上游由 drop-in `99-upstream-v41.conf` 钉为 `127.0.0.1:8899`"；
`nvmodule-guard.service`→"…⚠️ 已知缺口（2026-09-23 登记未修）：判据「只要不是 Open Kernel Module
就报 OK」，**缺 `580.` 版本断言** ⇒ 595/610 等专有模块误载时同样打印绿字"。

除上表 7 行外，注册表还有 **19 条 `PRECOND`**（开窗前置）与 **2 条 `RECOVERY`**（自恢复链，
head/worker 各一条）—— 它们同样是"被守卫的对象"，只是判定时机不同（见 §3.1 与 §5.3）。
（2026-09-23 补：旧版此处写"5 行 / 14 条 PRECOND"——**计数已过期**，本次按 `guards.conf`
复算为 `GUARD=6 TIMER=1 PRECOND=19 RECOVERY=2`。⚠ 同日二次更正：首次重生成时 `nvmodule-guard`
尚未进表 ⇒ 当时复算成 `GUARD=5`；该 GUARD 行（`guards.conf` 行名 `nvmodule-guard`）补进本表后
`GUARD=6`，两处计数（本行与 `w6-kit/README.md` G7）已同步。）
`awk -F'|' '{print $1}' guards.conf | sort | uniq -c` 可以现场对齐口径。

已退役（注册表里 `#RETIRED-20260916`，勿再启用）：`vllm-tp4-head.service`、
`vllm-healthcheck.service`（+`.timer`）、`vllm-tp4-worker.service` —— 切到 SGLang 栈后由
`dsv41-head` / `dsv41-worker` 容器 + `start.sh` 承担。

**两个裸守护进程（没有 systemd 单元 ⇒ 机器重启或被人 kill 后不会自愈）**：
`oom_gate.sh monitor -w 6 -f 1.5 -n 3 --iv 10 -a`（止损）与 `guardctl.sh watch 60`（只读状态观察器）。
注册表用 `PRECOND|…|proc|…` 断言它们在役，重挂命令见 §5。★这是**已知缺口**：真正的修法要
给它们补单元并让 `hold/release` 认识它们，属于独立立项（见交付报告 §7）。
> ✅ **2026-09-23 部分更正（原文保留在上）**：`oom_gate.sh monitor` **已不再是裸进程** ——
> 2026-09-18 起由 systemd 单元 **`oom-gate-monitor.service`** 托管（`Restart=always`，
> `guards.conf:119` 有 `GUARD` 行；01 实测 `enabled + active/running`），这正是当天 01 OOM
> 未被预拦的整改（`BASELINE.md` 的「2026-09-18：oom_gate 应急层 + systemd 单元化（01 OOM 事故的整改）」节）。⇒ 上面这句的"两个"现在只剩 **`guardctl.sh watch`**
> 一个真裸进程（`guards.conf:124` 的 `guard-watch` 前置仍在断言它，缺口仍未闭合）。

**worker 上故意没有 healthcheck 单元。** `healthcheck-rebuild.sh` 四机现均为 **P3**
（`ab9a1954ce07`，含冷却窗自锁修复）。自恢复判定带**接线门槛**：本机没有任何单元调用该链时
判 `SKIP`（而不是每次巡检报一条无法清除的 WARN —— 那会训练人忽略告警通道）。

### 3.1 另外两类注册项（2026-09-11 扩展）

除 `GUARD` / `TIMER` 外，`guards.conf` 现在还注册两类，用于把**启动检查**与
**自恢复链**纳入同一套管理（v0.4，四条指令 #7）：

| 类型 | 格式 | 何时判定 |
|---|---|---|
| `PRECOND` | `PRECOND\|<role>\|<名称>\|<kind>\|<参数>\|<期望>\|<必需>\|<说明>` | **只在 `preflight`**（见 §5.3 第 3 条） |
| `RECOVERY` | `RECOVERY\|<role>\|<名称>\|<state文件>\|<链脚本>\|<冷却秒>\|<必需>\|<说明>` | `check` / `status` / `preflight` **始终判定** |

`PRECOND` 的 `kind`（**全 9 种**；2026-09-17 交叉审核 B4 指出旧清单漏了后三种，
而那三种恰好承载全部 SGLang 时代前置）：`proc`（守护真身在役，排除 `bash -c` 包装壳）、
`envpin`（`.env.tp4::KEY=VALUE` 旋钮钉值）、`archscr`（跑本套件自带的体检脚本）、
`file`（存在）、`md5`（版本钉住）、`memavail`（MiB 下限）、
`memfree`（"有效空闲"=MemFree+可回收文件页，MiB 下限——防 OOM）、`memfreeraw`
（裸 MemFree，MiB 下限——防 vLLM KV 池缩水：vLLM 池定尺寸读裸 MemFree，页缓存被当
已用，2026-09-13 V 轨新增）、`diskfree`（挂载点 MiB 下限）。全部**只读、无需 root**。
> ✅ **2026-09-23 补（计数已过期）**：`guardctl.sh` 实际实现了 **10 种** kind —— 上面 9 种之外还有
> **`unitprop`**（`:406-420`，2026-09-20 H3 新增；参数 = `<unit>::<prop>`，期望 = **数值上限**；
> 先试 `--user` 再试系统域）。**当前 `guards.conf` 里没有任何 PRECOND 行使用它**（首个用户按脚本
> 注释是"保活单元崩溃循环"：`Restart=always` 会把 38 连败掩盖成"一直 active"，故 `NRestarts` /
> `Result` 需要进判定面 —— 该断言目前由 `check` 的内联保活段承担，见 §15 行 #22）。
> 出处：`guardctl.sh:406-420`、`BASELINE.md` 的「2026-09-20 台账更新（批次 7 · H 车道）」节 → `guardctl.sh` 行（`H3:` 段）。

`RECOVERY` 判定优先级：链脚本缺失(DEGRADED) → 缺负值护栏(DEGRADED) → state 缺失(WARN)
→ state 非数字(DEGRADED) → **state 为未来时间戳(DEAD，自锁)** → 冷却窗内(OK) → 已过(OK)。

> `RECOVERY` 之所以在例行 `check` 里也判定：**它的失效与生产在不在跑无关，而且是无声的**。
> `PRECOND` 之所以不在例行 `check` 里判定：它在生产正常运行时**本就不成立**。

改守卫脚本后必须同步 `guards.conf` 的期望 md5 与 `BASELINE.md`，否则 `check` 会持续报 DRIFT。

---

## 4. 设计要点：为什么 `oneshot` 是最危险的类型

停泊桩必须**与单元类型匹配**，这是那次事故的直接教训：

| 类型 | 停泊桩写法 | 若写错会怎样 |
|---|---|---|
| `oneshot` | **立即 `exit 0`** | 写成 sleep 循环 → 单元永卡 `activating` → 定时器 `NextElapse=infinity` → **守卫静默永久失效**（2026-09-11 事故根因） |
| `simple` + `Restart=always` | **驻留不退出**（sleep 循环） | 写成 `exit 0` → systemd 立刻重启 → 重启风暴 |

由此推出两条硬规则，已固化进 `guardctl`：

1. `hold` 按类型生成对应桩（见脚本内 `STUB_ONESHOT` / `STUB_SIMPLE`）。
2. `release` **显式回收停泊的 oneshot**：取 `MainPID`，对它**及其子进程**都发 `SIGTERM`，
   然后断言定时器不再是 `infinity`。
   ⚠️ 必须连子进程一起信号——bash 会**推迟**处理信号直到当前前台子进程返回，
   只杀父进程最长要等桩的 sleep（3600s）才生效。
3. `check` 对 oneshot 用**类型相关的静息态**判定：`inactive` 是正常（跑完即退），
   真正的失效是"卡在 `activating`"或"上次 `Result != success`"或"最近一次成功距今过久"。
   只看 `is-active` 会把健康的 oneshot 误判为死亡。

---

## 5. 失效形态与判定口径（自解释摘要）

| 形态 | 判据 | 后果 | 修复 |
|---|---|---|---|
| oneshot 卡死 | `is-active` 为 `activating`/`active` **且持续 > `GUARD_ONESHOT_RUN_MAX`（默认 120s）** | 触发链死亡 | `kill -TERM $MainPID` + 其子进程 |
| oneshot 暂时在执行 | 同上但**持续 ≤ 120s** | **正常**（`OnUnitActiveSec=60s` 的探针每次跑数秒） | 无需动作——见 §5.3 |
| 定时器楔死 | `NextElapseUSecMonotonic = infinity` **且依赖单元不在执行** | **永不触发** | 同上（回收卡死进程后自动重算） |
| 定时器依赖在执行 | `infinity` 但依赖单元 `activating`/`active` 且 ≤ 120s | **正常** | 无需动作——见 §5.3 |
| **自恢复链自锁** | 冷却 state 为**未来时间戳**（`NOW−LAST < 0`） | **永不重建，且无任何日志** | `echo 0 > /opt/aicad-prod/state/healthcheck-rebuild.<role>` |
| **自恢复脚本缺护栏** | 链脚本不含 `NOW - LAST)) -ge 0` | 一旦 state 被毒化即再次自锁 | 同步到 p3（生产变更，需授权） |
| 停泊残留 | 守卫脚本内含 `WINDOW HOLD`/`REX-HOLD`/`guardctl HOLD` | 守卫被有意停用 | 不在窗口内 → `release <tag>` |
| md5 漂移 | 实际 md5 ≠ `guards.conf` 期望 | 守卫被改动，行为不再受控 | 合法改动 → `snapshot` 更新基线；否则 `release` |
| 监视器空转 | `MainPID` 的 cmdline 不指向脚本 | 单元在跑但不是那个守卫 | 排查 systemd 单元定义 |
| 失败态 | `is-active = failed` | 崩溃后未恢复 | 看 `Result=`；`release` 复位 |
| 重启策略缺失 | `Restart` ≠ 期望值 | 崩溃后不会自动回来 | 修单元 file（需 root） |

**配置项**：`GUARD_ONESHOT_MAX_AGE`（默认 900 秒）——oneshot 最近一次成功执行超过此值即报
DEGRADED，用于捕捉"定时器看着正常但实际没在跑"；`GUARD_ONESHOT_RUN_MAX`（默认 120 秒）——
上面两条"暂时在执行"的判据阈值。

### 5.3 两次修正：`infinity` 不总是故障，`activating` 不总是卡死

这是本套件**最容易误报**的地方，2026-09-11 各修过一次，读代码时请勿改回去：

1. **`activating` 是正常态。** 每 60s 触发一次的探针，执行本身要数秒。任何恰好落在这几秒
   内的检查，都会看到 `activating` + 空的 `ExecMainExitTimestampMonotonic`。旧逻辑把这两个
   **瞬时态**直接判成 `DEAD`/"从未执行过"，实测**约每 10 次检查误报 1 次**。现在按**持续
   时间**判：超过 `GUARD_ONESHOT_RUN_MAX` 才算卡死——既保留"卡 40 分钟"的检出能力，又消除
   瞬时误报。
2. **`NextElapse=infinity` 有两种含义**，必须分开：依赖单元**正在执行**时 systemd 给不出
   下次 elapse，报 `infinity` 属正常；依赖单元**卡死/不存在**时 `infinity` 才是真失效。
   判据是先看依赖单元状态，在执行中则再按持续时间决定。
3. **PRECOND 默认不在例行 `check` 里判定。** `pool-free`（MemAvailable ≥ 110 GiB）这类条件
   在生产正常运行时**本就不成立**（生产在跑，池子当然不空）。放进例行巡检就会变成"每次
   check 都 FAIL"的新一轮狼来了。它们是**开窗前置**，只在 `preflight` 里断言。

> ⚠️ 另一个坑：同一个 systemd 对**不同单元/属性**会给两种单调钟格式——服务属性多为
> **原始微秒**，定时器属性可能是 `3h 37min 28.166119s` 这样的**人类可读时长**。用
> `date -d` 解析在中文 locale 下会失败；本套件用 `mono_secs`/`mono_age` 手工换算，两种都吃。

---

## 6. 深诊断 `doctor` 会查什么（以及为什么）

| 检查 | 为什么 |
|---|---|
| 内核 `oom-kill:` 计数 | 设备内存不进 cgroup，`--memory` 挡不住；只有内核 OOM 计数能看见 |
| 看门狗 `panic/reset` | 社区实测：回收抖动常表现为**看门狗复位而不是干净 OOM**，**不留 oom-kill 行**，靠 OOM 计数的守卫看不见它 |
| `NV_ERR_NO_MEMORY` 计数 | 统一内存被超额分配的特征；可能硬锁死宿主机（SSH 断、需断电） |
| 守卫脚本正则里 `(X|X)` 同分支 | 改名遗留的死代码（本项目实测存在），语义等价单分支，易误读 |
| `bash -n` 语法 | 守卫脚本被改坏是最直接的失效 |
| `/opt/aicad-prod/state/healthcheck-rebuild.*` | 历史雷区：state 被写成**未来时间戳**会让 `NOW-LAST` 恒负 → 冷却判据恒真 → 永不重建（自锁）。p3 已加负值护栏 |
| SM 时钟 < 1GHz | GB10 已知"时钟闩锁"：`nvidia-smi` 看不出原因，**重启无效，只有拔适配器 30–60s 能清除** |
| `memory.total = N/A` | GB10 上属正常，**不是**故障（避免误判） |

---

## 7. 标准化操作流程（SOP）

### 7.1 日常巡检（建议每日 / 每班）
```bash
bash ~/w6-kit/guard/guardctl.sh check || notify-someone "守卫异常"
```

### 7.2 开维护窗口（停生产 / 起测试栈）
```bash
TAG=20260912T0300Z-v41
bash ~/w6-kit/guard/guardctl.sh hold "$TAG"
bash ~/w6-kit/guard/guardctl.sh status          # 确认全部 HELD
# --- 停生产、确认池子真的空出来 ---
bash ~/w6-kit/guard/guardctl.sh preflight       # ★ 必须 READY 才启动；BLOCKED 一律不许启动
# ... 窗口内的操作 ...
bash ~/w6-kit/guard/guardctl.sh release "$TAG"
bash ~/w6-kit/guard/guardctl.sh check           # 必须 ALL-OK 才能宣布收工
```
> `release` 的最后一步是**断言定时器不再是 infinity**。这是"回退完成"的唯一可信证据——
> 脚本还原成功 **不等于** 守卫已经恢复工作。
>
> `preflight` 的两类判据（`前置:` 与 `自恢复:`）覆盖了窗口 2 那次四机 OOM 的直接教训
> （池子没空出来就启动）。它在生产**运行时**必然报 `BLOCKED`（因为池子当然不空）——
> 那是**正确**的，不是故障。

### 7.3 发现守卫失效
```bash
bash ~/w6-kit/guard/guardctl.sh explain <单元名>   # 先看它是什么、怎么修
bash ~/w6-kit/guard/guardctl.sh check              # 拿修复命令
# oneshot 卡死：kill -TERM MainPID 及其子进程
# 自恢复链自锁：echo 0 > /opt/aicad-prod/state/healthcheck-rebuild.<role>
# 停泊残留：release <tag>
```

### 7.4 改过守卫脚本之后
```bash
bash ~/w6-kit/guard/guardctl.sh snapshot        # 记下新基线
# 同步更新 guards.conf 里该单元的期望 md5，否则 check 一直报 DRIFT
```

### 7.5 持续性监视（可选，前台）
```bash
bash ~/w6-kit/guard/guardctl.sh watch 60        # 状态翻转才告警，静默期不刷屏
```

---

## 8. 告警通道

- **stdout**：`FAIL`(红) / `WARN`(黄) / `OK`(绿)，非 tty 自动去色，便于管道与日志。
- **`guard-alerts.log`**：本目录下追加，含 ISO 时间戳与主机名。外部监控可直接 tail/grep `CRIT`。
- **syslog**：`logger -t guardctl -p daemon.err|daemon.warning`，便于接入既有告警链。
- **退出码**：`check` 用 0/1，可直接作为 cron / systemd / 监控探针的判据。

---

## 9. 与启动脚本的集成

**真实接线（2026-09-17 核对）**：`~/dsv41-flash-dgxsparks/start.sh` 的 `cmd_serve()`
（约第 812 行）在**拉起容器之前**调用一次 `guard-onstart.sh`；
`start-tp4.sh` 与 `start.sh` 的其它子命令都**不**引用它。

> ⚠ 本节此前写的是 `start_tp4_head_v043.sh` / `start_tp4_worker_v043.sh` / `v41_launch.sh`
> —— **这三个脚本已不在生产启动路径上**（生产走 `~/dsv41-flash-dgxsparks/start.sh cmd_serve`，
> 2026-09-17 起），**但文件仍在 `~/w6-kit/` 留档**（2026-09-23 实测：6728 / 3945 / 14748 B）。
> HOW-TO-INSTALL.md 与 BASELINE.md 早已撤回那个说法，只有 README 这处漏改（2026-09-17 交叉审核 B4）。
>
> ✅ **2026-09-23 修订**：上一版这句写的是"**这三个脚本已不存在**"——**该表述是错的**（`ls -l
> ~/w6-kit/start_tp4_{head,worker}_v043.sh ~/w6-kit/v41_launch.sh` 三份都在，大小如上）。正确
> 口径 = **"已不在启动路径上、但仍在 `~/w6-kit/` 留档"**。`BASELINE.md` 的「2026-09-17 五次更新（部署窗口 + 三份交叉审核的修复）」节 → `README.md` 行（`✅2026-09-23 订正` 段）的同一句已同步改。

`guard-onstart.sh` 的行为：

- **永远 `exit 0`**，绝不阻塞启动（启不起来的代价大于守卫缺失）；
- 只读，不动容器；
- 有异常时打印醒目横幅并写告警日志，把"起了一个没人守的栈"这件事变得可见。

关闭集成（应急）：`GUARD_ONSTART=0`，或直接在启动脚本里注释掉那两行。

---

## 10. 文件

| 文件 | 作用 |
|---|---|
| `guardctl.sh` | 唯一入口：status/check/**preflight**/explain/doctor/hold/release/watch/snapshot |
| `guards.conf` | 声明式守卫清单（单元、类型、期望 md5、是否必需、说明） |
| `guard-onstart.sh` | 启动路径钩子，只读、永不阻塞 |
| `BASELINE.md` | `snapshot` 生成的状态基线 |
| `verify-governance.sh` | **装完/改动后自检**：齐备性 + 语法 + 能力断言 + B1/B2/B3 行为断言（见 HOW-TO-INSTALL） |
| `overlay-drift-check.sh` | 容器视角 ↔ 盘上 overlay ↔ 镜像 三者是否同一份字节（形态感知） |
| `jit-header-refresh.sh` + `jit_refresh_exec.py` | JIT 头文件依赖的**预发布**（只发布、绝不删除） |
| `probe_deps_closure.py` | 复算 432 项依赖闭包，独立验证上面的"自失效"结论 |
| `flashinfer-arch-guard.sh` | SM121 上 flashinfer AOT 取件的 arch 体检（被 `archscr` 前置调用） |
| `journal_watch.sh` | 【2026-09-23 补】journal/kernel 增量守望（timer 10min；游标在 `state/journal-watch.cursor`，每轮摘要 `state/journal-watch.log`） |
| `wedge-watch.sh` | 【2026-09-23 补】跨机楔死探测（timer 5min；ping/TCP/ssh-banner 四态，sweep 四机） |
| `gen_probe.sh` | 【2026-09-23 补】30min 低频真生成补偿探针（"19+23" 期望含 42；停泊期静默 exit 0） |
| `gate_archive.sh` | 【2026-09-23 补】gate 快档 6h 节拍 + 落 `~/dsv41-flash-dgxsparks/logs/gate-history.jsonl` |
| `clock-sm-guard.sh` | 【2026-09-23 补】锁频**实际值**体检（clocks.sm ∈[2250,2400]；被 `archscr` 前置调用；rc 2=判不了） |
| `HOW-TO-INSTALL.md` | 安装、路径改写与判据说明（**随包交付**，在役目录通常没有它） |
| `MD5SUMS` | 传输完整性清单（**交付布局**生成；清单**可能**含只有交付布局才有的 `HOW-TO-INSTALL.md`/`oom_gate.sh` —— 那是**防御性容忍**的形态（`verify-governance.sh` 用 `--ignore-missing`），不是对现状的描述；2026-09-23 实测：在役清单 17 项、归档清单 16 项，两布局均无此二项） |
| `guard-alerts.log` | 告警流水 |
| `state/` | 预留 |

---

## 11. 明确不做（边界）

- 不修改 `/etc/systemd/system/` 下任何单元文件（需 root，且属生产变更）；
- 不 `docker rm -f` / `docker stop` 任何容器——**守卫的职责由守卫脚本自己做，本工具只观测与开关**；
- 不在 `check` 里做任何写操作；
- 不自动"修复"守卫：`check` 只给修复命令，由人执行（自动修复在守卫本身失效时风险最高）。

---

## 12. 起栈后必跑：`boot-signature.sh`（2026-09-16 慢靴事故后新增）

**位置**：`~/dsv41-flash-dgxsparks/scripts/boot-signature.sh`（只读；`--bench` 才起流量）

**为什么单独立项**：2026-09-16 出现一次**慢靴**——解码吞吐塌 **10-25×**（c1 2.4 t/s vs 56.8；
40 步间隔 70 s vs 6 s），而 **`gate.sh` 4/4、code 12/12、corruption 0、0 Traceback 全部绿灯**。
⇒ **质量门与吞吐门是正交的两维，缺一就会出现"门全绿但生产慢 25×"**。

**判据（★2026-09-16 晚**被实测推翻并修订**过一次 —— 下面是修订版）**：

★**主判据 = warmup 块的 per-batch `input throughput (token/s)` 中位数**
（warmup 块 = `The server is fired up and ready to roll!` 之后、`Warm-up done in ...` 之前）

| 读数 | 正常 | 慢靴 |
|---|---|---|
| **warmup 吞吐中位（主判据）** | **≥ 400**（13:10 靴 **663**，n=8；报告另见 388/542/709） | **< 200**（09:55 慢靴 **55**，n=17） |
| `Capture target verify CUDA graph end. elapsed=`（**仅供参考**） | 5.7-6.7 s | 23.6 s |
| decode 40 步**最快**间隔（最近 12 个） | **2-6 s** | **~70 s** |
| bench c1（`bench/bench_tp.py --conc 1`） | 232 ms / 55-65 t/s | 个位数 t/s |

🔴**为什么把 capture 从主判据降级**（这是本节的第一次自我推翻，值得记）：
旧版把 `capture > 20 s` 当主判据，**已证伪（不充分）**——
**2026-09-14 04:14 靴 capture=30.00 s**（2.90 s/层，与慢靴同族）**却是健康的**
（warmup 12 s、探针 57-67 t/s）⇒ 单靠 capture 会把好靴重启掉。
**新主判据零流量、每次起栈必有**（warmup 块自带），分离度也大（663 vs 55，12×）。
（依据：`~/r4-ops-work/r9-ops-20260914/evidence/slowboot-forensics-20260916/SLOWBOOT-FORENSICS.md`；
本文件作者用两个日志的 warmup 切片独立复算了中位数，非转述。）
★2026-09-23 修订：旧版写的是裸相对路径 `r9-ops-20260914/evidence/…`，从 `guard/` 下**无法解析**；
真身在 `~/r4-ops-work/` 下（实测该文件存在，40515 B）。

⚠**`Warm-up done in Ns` 已从判据中删除**：健康靴也有 **141 s / 250 s** 的，
那是 **prompt 工作量驱动**（257K/474K token），不是靴态。它现在只作为 info 打印。

⚠**步时维必须看「最快」而不是「中位」**：解码行每 40 步打一行，但**空闲期不打**
⇒ 大间隔既可能是慢靴、也可能是"引擎空转"，中位数会把空转误判成慢靴。
**2026-09-16 实测踩到**：引擎空闲 2 h 后中位间隔 **1244 s**，而最快间隔仍 **2.0 s**（健康）
⇒ 已改为判 **min（最近 12 个间隔的最快值）**：空闲间隔只会更大，永不误伤；
中位偏大而 min 正常时，脚本会显式标注「判空闲/低流量，非慢靴」。
（延迟维度同理：`boot-signature.sh` 只依赖已有日志，**不产生流量**；要确证吞吐须 `--bench`。）

**处置**：判慢靴 ⇒ **配置不动，直接重启**（2026-09-16 实测单调重启即恢复：capture 5.84 s、c1 232 ms/56.8 t/s）。
⚠**重启前先抓现场**（GPU 时钟/温度、`nvidia-smi -q`、全量 stderr）——该故障成因未定，现场是唯一线索。
⚠**取证提醒（2026-09-14 事故的取证缺口）**：那次事故的 NCCL per-rank 日志**四机全无**、
`argv-slow.txt` 是 **0 字节**、GPU 时钟**从未采到** ⇒ 事后完全无法归因。
预采脚本见 `~/r4-ops-work/r9-ops-20260914/evidence/slowboot-forensics-20260916/preboot-capture.sh`
（⚠其 ssh 扇出用 `bash -s < $SELF` 会**递归**，用前须改 scp+ssh）。(2026-09-23 补：同样补全 `~/r4-ops-work/`
前缀；实测该脚本存在。)
⚠GB10 **不可读字段**（别在它们上面浪费时间）：`clocks.memory`、`supported_clocks`、
`power.limit` 均为 **N/A**；DCGM 在 GB10 无 DRAM 计数器。

**用法**：
```bash
~/dsv41-flash-dgxsparks/scripts/boot-signature.sh          # 读日志，零成本
~/dsv41-flash-dgxsparks/scripts/boot-signature.sh --bench  # 再跑一次 canonical 吞吐
```

**边界**：本守卫**不自动重启**——与第 11 节一致，慢靴判定后人执行；且它是独立脚本，
**不并入 `guards.conf`** 的理由：它是一个**跨机**判定（要 ssh 四台比对靴态），而现有 kind 都是
**本机**判据；把跨机语义塞进 `preflight` 会让"启动前置"依赖网络，属于生产变更，需单独评审。
（更正 2026-09-17：旧版这里写"无跑脚本类"——**不成立**，`archscr` 就是跑脚本的 kind；
列举也不全，见 §3.1。）

---

## 13. 非注册表守卫（timer / 手工驱动）—— 2026-09-23 补

为什么单列：§3 的表只覆盖 `guards.conf` 里登记的四类对象（`GUARD`/`TIMER`/`PRECOND`/`RECOVERY`）。
下面这 7 个**在注册表里没有对应行**，但都在真守东西 —— 它们的判据 / 阈值 / 动作 / fail-closed
性质此前**没有一处成文**，只能靠读脚本。本节把它们逐个落文。

**在役状态取证口径**：下面的 `enabled/active` 与周期取自 `systemctl --user list-timers --all`、
`systemctl --user is-enabled/-is-active <timer>`、`systemctl --user show <timer> -p OnBootSec -p OnUnitActiveSec`
（2026-09-23 00:45–01:05 UTC，**本机 dgxspark01**）。
⚠ **四机一致性未核实**（本次修订禁 ssh），故下表只声明 01 的实测值。

| 守卫 | 驱动 | 周期 | 01 上在役状态（2026-09-23 实测） |
|---|---|---|---|
| `journal_watch.sh` | 用户级 `guard-journal-watch.timer` → `.service` | `OnUnitActiveSec=10min`（`OnBootSec=5min`） | **enabled + active**（最近触发 00:58:03） |
| `wedge-watch.sh` | 用户级 `guard-wedge-watch.timer` → `.service`（argv = `sweep dgxspark01..04`） | 5min（`OnBootSec=3min`） | **enabled + active**（最近 00:58:49） |
| `gen_probe.sh` | 用户级 `gen-probe.timer` → `.service` | 30min（`OnBootSec=10min`） | **enabled + active**（最近 00:52:24） |
| `gate_archive.sh` | 用户级 `gate-archive.timer` → `.service` | 6h（`OnBootSec=10min`，`TimeoutStartSec=600`） | **enabled + active**（最近 23:50:49） |
| `clock-sm-guard.sh` | `guards.conf:105` 的 `archscr` 前置（**只在 `preflight`**） | 无 timer，按需 | 脚本在位（`MD5SUMS` 有钉） |
| `overlay-drift-check.sh` | **手工**（无 timer、无单元；`verify-governance.sh` 的 [3] 能力断言段 → `overlay-drift-check.sh 从 start.sh 解析 overlay 映射` 那条只断言其能力） | 无 | 脚本在位 |
| `flashinfer-arch-guard.sh` | `guards.conf:146` 的 `archscr` 前置（**只在 `preflight`**） | 无 timer，按需 | 脚本在位 |
| （驱动本身）`guardctl.sh check` | 用户级 `guard-check.timer` → `guard-check.service`（`ExecStart=…/guardctl.sh check`） | **15min**（`OnBootSec=3min`，`AccuracySec=30s`，`Persistent=true`） | timer **enabled + active**；⚠ **service 当前 `failed`**（`status=1/FAILURE`，01:00:55）—— 原因是 §15 行 #21 的 `gateway 8001 /health HTTP 502`（停泊态），**不是 timer 坏了** |

> **2026-09-23 补注（上表最后一行的实测噪声）**：停泊期 `check` 每 15min 判一次
> `gateway 8001 /health`（`guardctl.sh:643-662`：只有"容器 health=starting"才 SKIP，**容器整个不在时
> 走 FAIL 分支**）⇒ `guard-alerts.log` 里累计 **115 条** `[CRIT] … 1 guard problem(s)`
> （2026-09-11→09-23 全史计数，按日：**09-22 65 条、09-23 3 条**；2026-09-23 01:00 实测）。
> 抽验两条（`journalctl --user -u guard-check.service`，09-22T19:34:31 与 09-23T00:45:19）：
> **FAIL 项都只有一条** = `gateway 8001 /health HTTP 502`。**这是"停泊态未被判定为合法静息态"的
> 缺口**，与 v0.4.1 修掉的"喊狼来了"同类；本节**只登记事实，不在本次修订中改判据**（判定口径变更
> 需单独评审）。

### 13.1 `journal_watch.sh` — journal/kernel 增量守望

- **读什么量**：`journalctl -k --since @<游标>`（游标 = `state/journal-watch.cursor`；首跑取 `now-600`
  只看将来、不翻旧账 —— `journal_watch.sh:14-18`）
- **判据 / 阈值 / 动作**（命中即写告警面，**不阻断任何东西**）：
  | 判据 | 阈值 | 级别 | 出处 |
  |---|---|---|---|
  | `NV_ERR_NO_MEMORY` | ≥1 条 | **WARN**（驱动侧内存分配失败） | `journal_watch.sh:35-36` |
  | `invoked oom-killer` / `Killed process` | ≥1 条 | **CRIT** | `journal_watch.sh:41-42` |
  | `watchdog.*(timeout\|panic)` / `BUG: soft lockup` | ≥1 条 | **CRIT** | `journal_watch.sh:43-44` |
  | `dsv41-serve.service` 的 `Failed with result` / `Start request repeated too quickly` | ≥1 条 | **CRIT** | `journal_watch.sh:51-52` |
  | `journalctl -k` **不可读** | — | **WARN「勿当零事件」** | `journal_watch.sh:46` |
- **动作**：追加 `guard-alerts.log` + `logger -t guard-jwatch`（`journal_watch.sh:20-29`）；CRIT 且
  `GUARD_ALERT_HOOK` 有 URL 时 POST
- **fail-closed**：**是** —— "读不到"渲染成 WARN 而不是零事件（H9 同源教训）；每轮摘要写
  `state/journal-watch.log`，**自审计 timer 有没有真跑**（`journal_watch.sh:59-60`）
- **实证出处**：`guard-alerts.log` 2026-09-22T23:31:30 `[WARN] … kernel NV_ERR_NO_MEMORY ×7`；
  `state/journal-watch.log` 最近 5 轮 `kern_hits=0`（00:16→00:58）
- ⚠ **已修过的坑（勿改回去）**：旧正则 `Out of memory|oom-kill` 会命中 NVRM 的
  `Check failed: Out of memory [NV_ERR_NO_MEMORY]`，把**图捕获瞬态**误报成"内核击杀进程"级 CRIT
  （`journal_watch.sh:37-40` 记有 2026-09-21 交叉审计实锤）

### 13.2 `wedge-watch.sh` — 跨机楔死探测

- **读什么量**：三路顺序探测 —— `ping -c1 -W2` → `/dev/tcp/<host>/22` 可连性 → `ssh -o BatchMode=yes … true`
  的 banner 行为（`wedge-watch.sh:26-44`）
- **四态判据**（`wedge-watch.sh:9-13`）：`OK`（握手成功）/ `NET-DOWN`（ping 不通）/
  **`WEDGE`（ping 通 + TCP 可连 + ssh 无 banner ⇒ 宿主用户态冻结）** / `SSHD-DOWN`（ping 通 + 端口拒绝）
- **阈值**：`CT=6s`（TCP/ssh 超时）、`PINGW=2s`（`wedge-watch.sh:20-21`）
- **动作**：`sweep` 里 `WEDGE` ⇒ **CRIT + 返回 2**；`NET-DOWN` ⇒ **CRIT + 返回 1**；`SSHD-DOWN` ⇒
  **WARN**（`wedge-watch.sh:52-54`）；CRIT 落 `guard-alerts.log`
- **fail-closed**：**是**（非 OK 即返回非 0，oneshot 失败进 journal）
- ⚠⚠ **已知局限（必须与判据一起读）**：**本脚本无法区分"用户态冻结"与"内核级楔死"**。
  2026-09-22 dgxspark02 的 19.3 min 停顿**三向表现与历史楔死完全无法区分**（ping 0% 丢包、
  TCP 22 能建连、banner 永不出现），据此先判"内核级楔死、唯控制台复位"，**随后被两条证据推翻**
  （该机自行恢复）。⇒ **判据须补"采样断档"这一项**：`/tmp/v41_hostattr_a1.tsv` 的 S 行在
  **16:13:28 → 16:32:47 断档 1158.7 s 后自行续写**，而 `uptime` 证明该机自 14:58 UTC 起从未重启。
  ⚠ **该 `/tmp` 证据源已于 2026-09-23 清理**（`test -e /tmp/v41_hostattr_a1.tsv` ⇒ **不存在**；
  同族残留只剩 `/tmp/v41_hostattr_r.tsv` / `/tmp/v41_hostattr_t4_t4.tsv`）—— **原始 TSV 不再可取**，
  结论已落入下一行的规划文件，**不要按 `/tmp` 路径去找原件**。
  （出处：`~/V41-ABCD-SCOPED-PLAN-20260922.md` §11.3，2026-09-23 实测该文件 318-333 行；其
  "待补量具"第②条原话 = 判据必须含 **S 行 ms 间隔断档**）。
  **本脚本当前没有这一项**（已通读全脚本，只有 ping/TCP/banner 三路）⇒ 现行 `WEDGE` 判决的准确
  读法是 **"remote 用户态已不可操作"**，**不等于"必须断电"**。这是**本套件最该补的一条判据**。
- **实证出处**：`guard-alerts.log` 2026-09-22T16:14:37 / 16:20:07 / 16:25:23 / 16:30:37 / 16:36:07
  连续 5 条 `[CRIT] dgxspark02 楔死：宿主用户态冻结`；同一机器随后自愈（见上）

### 13.3 `gen_probe.sh` — 30min 低频真生成探针

- **读什么量**：`http://127.0.0.1:8899/v1/models`（**带 API_KEY**，KEY 从 `.env.tp4` 读；无 auth 的探活
  会被 401 误判停泊 —— `gen_probe.sh:31-36`）→ 单发 `/v1/chat/completions`：
  `What is 19 + 23? Reply only with the number.`，`temperature=0`、`max_tokens=16`、`thinking=false`
  （`gen_probe.sh:50-52`）
- **判据 / 阈值**：`curl --max-time 120`；**答案必须含 `42`**（`gen_probe.sh:60`）
- **动作**：`/v1/models` 200 但模型名解析失败 ⇒ **CRIT**；curl rc≠0（超时/连接失败）⇒ **CRIT**；
  答非所问 ⇒ **CRIT**（`gen_probe.sh:47,54-58,63-67`）
- **fail-closed**：**停泊期有意 fail-open** —— 栈不服务（`/v1/models` 不通）⇒ **静默 `exit 0`**
  （`gen_probe.sh:38-42`：栈在位性归 `guardctl check` 管，本探针不与它抢域、不在停泊期刷警报）。
  这是设计不是缺口，**但意味着停泊期本探针不提供任何保护**
- **设计取舍**：刻意 30min + 单发（~10 token 补全）—— 高频真补全才是 2026-09-21 磨死四机的凶手
- **实证出处**：`gen-probe-dgxspark01.log` —— 2026-09-22T23:50:49 `OK (deepseek-v4.1-flash)`；
  停泊期若干条 `stack-not-serving (quiet exit)`

### 13.4 `gate_archive.sh` — 6h gate 快档存档

- **读什么量**：`~/dsv41-flash-dgxsparks/scripts/gate.sh --json` 的 rc 与末行 JSON
- **动作**：**无条件**把 `{ts,host,rc,gate}` 追加进 `~/dsv41-flash-dgxsparks/logs/gate-history.jsonl`
  （`gate_archive.sh:13-16`，滚动留 2000 轮≈16 个月）；`rc≠0` ⇒ **CRIT** 落 `guard-alerts.log` +
  `logger -t guard-gate` + 可选 hook（`gate_archive.sh:18-26`）
- **fail-closed**：**否（有意）** —— 脚本自身**永远 `exit 0`**；它只存档与告警、不阻断任何东西。
  "gate 跑不起来"会体现为 rc≠0 的存档行 + CRIT，而不是脚本失败
- **实证出处**：`logs/gate-history.jsonl` 三行 —— 2026-09-22T11:41:10 `rc=0`（14 项 PASS）、
  **17:41:40 `rc=1`（3 PASS / 9 FAIL）**、23:51:20 `rc=0`（17 项 PASS）；`guard-alerts.log`
  2026-09-22T17:41:40 `[CRIT] periodic-gate FAILED rc=1`。中间那行正是"gate 结果此前只进 stdout、
  没人跑就没人知"的反面教材
- ⚠ **采分窗纪律**：`systemctl --user stop gate-archive.timer`（测量纪律，见脚本头注 `gate_archive.sh:6`）

### 13.5 `clock-sm-guard.sh` — 锁频**实际值**体检

- **读什么量**：`nvidia-smi --query-gpu=clocks.sm` 的最高值（`clock-sm-guard.sh:11`）
- **阈值**：`CAP=2400`、`TOL=150` ⇒ 判据 = **`clocks.sm ∈ [2250,2400]`**（`clock-sm-guard.sh:8-9,13-14`）
- **动作**：>2400 ⇒ rc 1（单元没在管 / 值漂移）；<2250 ⇒ rc 1；`nvidia-smi` 缺失或无读数 ⇒ **rc 2**
- **fail-closed**：**部分** —— **`rc 2` 是"判不了"，不是"判过了"**；`archscr` 把它渲染成 **SKIP**
  （`guardctl.sh:383-400`：约定 `0=OK / 1=FAIL / 2=SKIP`）。引擎停泊时 `clocks.sm` 走低 ⇒ 靠 rc 2
  承担"合法 SKIP"语义（`guards.conf:105` 明文）
- **为什么需要它（不要删）**：`gb10-clock-cap.service` 的 GUARD 行只判**单元状态**，看不出 `-lgc`
  值漂移 —— 这种盲区真实存在（`guards.conf:105` 记的 2026-09-19「2418 假失效」排查即撞在此；
  那次最终定性为字段语义误读，见 `BASELINE.md` 的「2026-09-20 GPU 时钟基线 2200→2400（用户指令，四机同步）」节 → `顺带修正` 行，**但盲区本身成立**）
- **在役状态**：被 `guards.conf:105`（`PRECOND|all|clock-sm-actual|archscr`）消费，**只在 `preflight`**
- ⚠ **未核实**：本机当前 `clocks.sm` 真值未采（本次修订不执行采样类命令）。**旁证**：`check` 在
  00:45:19 的排查面防线里打了 `PASS gpu:时钟 采样窗全空转（util<50 不判楔死=防假阳；clock=208MHz 温=49°C）`
  ⇒ 停泊态下本脚本会走 rc 2 ⇒ SKIP（与 `guards.conf:105` 的声明一致）

### 13.6 `overlay-drift-check.sh` — 容器实挂 ↔ 盘上 overlay ↔ 镜像 的字节身份

- **读什么量**：三份 sha256 —— 宿主 `sglang-overlay/<f>` / 容器内 `/sgl-workspace/sglang/<dst>` /
  镜像内同路径（`overlay-drift-check.sh:74-78`）；overlay 映射**从 `start.sh` 的
  `declare -A SGLANG_OVERLAY_MAP` 现场解析**，不抄第二份（`:49-57`）
- **判据**：逐文件三项比对（`:85-106`）；**形态由容器实挂判定**（`docker inspect .Mounts` 里
  `/sgl-workspace/sglang/` 的 bind 数 >0 ⇒ `bind`，否则 `image` —— `:60-63`，**不看配置**）
- **动作**：任一 `DRIFT`/`MISSING` ⇒ **rc 1**，并按形态给**不同**处置 —— `bind` ⇒ **重建容器**；
  `image` ⇒ **重建镜像并分发**（`overlay-drift-check.sh:110-121`）；判不了（无仓库/无容器/解析 0 条）
  ⇒ **rc 2**
- **fail-closed**：**否**（只读报告，不自动修）；判不了 rc 2
- **在役状态**：**手工驱动** —— 无 timer、无单元调用它；`verify-governance.sh` 的 [3] 能力断言段 → `overlay-drift-check.sh 从 start.sh 解析 overlay 映射` 只是"断言它
  能从 `start.sh` 解析 overlay 映射"的能力自检
- **为什么需要它**：本项目每一次"我明明修了，怎么还这样"都是这个形状（fp4 KV scale、bridge-id 保留
  都只在盘上，直到容器重建才生效 —— `overlay-drift-check.sh:15-16`）

### 13.7 `flashinfer-arch-guard.sh` — AOT 取件 arch 体检

- **读什么量**：**在役 scheduler 进程真正 mmap 进来的** AOT 模块（`/proc/<pid>/maps` 里的
  `flashinfer_jit_cache/jit_cache/*`），逐模块 `cuobjdump -lelf`（cubin）/ `-lptx`（PTX）
  （`flashinfer-arch-guard.sh:73-99`）
- **判据 / 阈值**：模块 `PASS` ⇔ cubin 含 **sm_12x**（`sm_120/sm_120a/sm_120f/sm_121/sm_121a`）
  **或**含任意 `compute_*` PTX（可由驱动 JIT 到 SM121）；两者皆无 ⇒ **FAIL**
  （`flashinfer-arch-guard.sh:21-22,48-51`）
- **动作**：rc 1（FAIL，逐条列模块）；**无在役对象 ⇒ rc 2 ⇒ SKIP**（`:103-105`，引擎停泊时不误报）；
  `--audit` 全包扫描只"列出"无 12x 的模块，**本身不是故障**（`:70-72`）
- **fail-closed**：**部分**（rc 2 = 判不了）
- **在役状态**：`guards.conf:146` 的 `PRECOND|head|flashinfer-arch|archscr|… --quiet`，**`必需=no`**
  （新检查先观察、不阻断开窗；但 WARN 必须在开窗前查清）；只在 `preflight` 判定
- **实证出处**：`BASELINE.md` 的「2026-09-16 三次更新（步骤 9 判决 NOGO + 步骤 0 定谳 + 新增 arch 体检）」节之「步骤 0 定谳（原命题需改写）」条（判据是"在役路径真 mmap 的模块"而非包内全量，
  在役只 2 个 —— `fp4_quantization_120f`、`sparse_mla_sm120`）；正负双向已验（真脚本 PASS、
  注入假脚本 WARN）

### 13.8 顺带登记：`dsv41-serve-alert.service`（用户级 OnFailure 告警）

不在上表（它不是探测/判定，而是**失败钩子**），但同属"非注册表"面：
`~/.config/systemd/user/dsv41-serve.service.d/90-onfailure.conf` 里 `OnFailure=dsv41-serve-alert.service`，
后者写 `[CRIT] dsv41-serve.service 进入 failed` 进 `guard-alerts.log`。单元 = `static`（不可 enable），
`dsv41-serve.service` 当前 `disabled + inactive`（**停泊态，与本节背景一致**；这是 `check` 里
`保活:dsv41-serve.service` 判 SKIP 的原因）。已核实：`~/.config/systemd/user/dsv41-serve-alert.service:1-4`、
`~/.config/systemd/user/dsv41-serve.service.d/90-onfailure.conf:3`（= `OnFailure=` 那一行）。

---

## 14. 量具（instrument）与会话工具 —— 2026-09-23 补

**它们不是守卫**：**没有阈值、没有判定、没有动作** —— 只采集与呈现（个别带自检/门禁开关，
但判决仍由人或守卫做）。单列的理由有两条：① 它们与守卫混在同一目录，容易被当成"注册表漏登的守卫"；
② 其中两处**已知缺口**必须点名，否则"量具坏了"会被当成"全过"。

| 工具 | 体量（**2026-09-23 `stat -c%s` 复算**） | 干什么 | 判据/闸门 | 调用者（2026-09-23 实测） |
|---|---|---|---|---|
| `v41_memwatch.sh` | 5845 B | 宿主侧**高频内存采样**（默认 250ms/发），四机逐机 TSV；口径与 `oom_gate.sh` **逐字节同款**（`eff_idle = MemFree + Cached + SReclaimable − Shmem`），另留 `MemFree`/`MemAvailable` 两列 | 无阈值（量具） | `v41_dose_ladder.sh:33`（`SELF=$HOME/w6-kit/v41_memwatch.sh`）、`drv-flavor-window/t4-replay.sh:37` |
| `v41_memwatch_report.py` | 9374 B | 由上面的 TSV 算**每档内存账**：三窗（`base`/`dose`/`settled`）→ `dip`/`persist`/`transient`/`min_free` | **闸门**：`G1` `min(eff_idle) ≥ FLOOR_G`（默认 3 GiB，**独立于守卫止损线**：G1 是实验硬停，必须高于守卫止损线 1.5，否则实验会一路开到守卫那条不可逆的 `docker stop`；`FLOOR_G=` 可显式覆写）、`G2` `transient ≤ TRANSIENT_G`（默认 3 GiB）；**`rc=2` 空真防线**（见缺口②） | `v41_dose_ladder.sh:34`（`MWREPORT=…`） |
| `v41_hostattr.sh`（**v1**） | 5440 B | 宿主侧**归因采样器**：全部 `docker-*.scope` 合计 + `dsv41` 单容器 + `user.slice` 的 file/anon/kernel 分项 + slab + 磁盘累计扇区（补 memwatch 缺的"容器外残差"那一半） | 无阈值 | **`v41_win_mmprobe.sh:123/215/218`**、`drv-flavor-window/win-drvverify.sh:127/252/255`、`drv-flavor-window/t4-replay.sh:39/127/241` |
| `v41_hostattr.v2.sh` | 6082 B | v1 + `swap_used`/`pswpin`/`pswpout`、未命中落 **`-1` 哨兵**（≠0）、文件头 `#FIELDS` 自描述列 | 无阈值 | **⚠ 无任何调用者（缺口①）** |
| `v41_devfree_host.sh` | 7523 B | **不起容器**读"设备可见空闲"：libcuda `cuDevicePrimaryCtxRetain` + `cuMemGetInfo_v2`；锚定"GB10 上 CUDA 报的 free ≡ `MemFree`（不是 MemAvailable）" | `--check N`：`dev_free ≥ N GiB` ⇒ rc 0；`--min4` 护栏（MemFree<4 GiB 时拒绝建上下文）；`drop` = `sync`+`drop_caches` | 无脚本调用者（会话/窗口手工用） |
| `v41_warm_cache.sh` | 11787 B | 起栈**前**主动预热只读权重/Engram 的页缓存（把 MemFree 变 Cached，而两项都在 `eff_idle` 公式里 ⇒ 理论不损判据；脚本每次实测 before/after 以**证伪**这一点） | 预算硬上限默认 **24 GiB**、`MemFree` 地板默认 **20 GiB**、`--ttl 900`、`ionice -c3 -n7 + nice -n 19` | 无脚本调用者（手工；`v41_warm_cache.sh run`） |
| `v41_dose_ladder.sh` | 19262 B | 单流长上下文**剂量阶梯**（16384…524288，可带 `8192-c1` 锚） | `G1`：四机 `min eff_idle ≥ FLOOR_G`（默认 3）；`G2`：`transient ≤ 3`；**已撤 NVRM 判决**（0x51 行只记录，见脚本头注 `:5-8`） | `v41_win_mmprobe.sh:168`、`v41_kfix_ab.sh:111`、`drv-flavor-window/win-drvverify.sh:183/197` |
| `v41_win_mmprobe.sh` | 16705 B | 窗口剧本：① mm-ban 靴验 ② 斜坡归因剂量 65536/131072/262144 | **形态断言**：运行时从 env 指到的 overlay 目录取源文件 md5，与容器内实挂文件比对（**不写死 md5** —— `:8-12` 记有"写死 md5 去断言 probe 变体 ⇒ 必然假告警"的事故） | 手工（`OUTD=… bash v41_win_mmprobe.sh`） |
| `v41_kfix_ab.sh` | 7766 B | K gather 修复的**同靴单变量**端到端 A/B（两臂只差**一个文件**：old=镜像原版 `deepseek_v4_memory_pool.py` `d9ec3730228a3feaecb9a480b462d5ef`，new=现役 overlay 版 `f8f1fbe197d5872f563690461d7f98b3`；**两值取自脚本头注**） | 每靴**断言**容器里挂的确实是本臂那份 pool（形态=判据前提，缺了断言这实验就是自证） | 手工（`bash v41_kfix_ab.sh`）；`wait_kfix_ab.sh:6-8` 是它的等待器 |

### ⚠ 缺口①：`v41_hostattr.v2.sh` 目前**无任何调用者**

- 实测（2026-09-23）：`grep -rn "v41_hostattr.v2" /home/liux***ya --include='*.sh' --include='*.py'`
  **只命中它自己**（另有一处出现在规划文档 `~/V41-ABCD-SCOPED-PLAN-20260922.md`；其余命中是
  zcode 会话日志/工件，不是调用者）。
- 而 **v1 仍在被引用**：`v41_win_mmprobe.sh:123/215/218`（以及 `drv-flavor-window/` 两个窗口脚本）。
- ⇒ **切换规则未文档化**：窗口脚本该用 v1 还是 v2、什么时候切、切之前要不要重测，**全无成文**。
- v2 修的是 v1 的三个**真缺陷**（v2 头注 `:10-31`）：① **缺 swap 口径** —— 2026-09-22 02 机
  冻结 19 min 时"抖动/回收"是候选机制，而当时的量具**完全看不见**；② `dsv_*` 在 worker 上**恒 0**，
  "scope 未命中"与"真的 0"不可区分（根因是 `docker inspect` 失败时空行混进 id，见 v2 头注 `:22-30`）；
  ③ 列不自描述，字段数一变整行被丢且只报一个计数。**修好了没人用** —— 这正是本节要留痕的原因。

### ⚠ 缺口②：`v41_memwatch_report.py` 的"空真假绿"防线（**必须保留**）

`dose_order` 为空时**不能**打印"全过"，必须 `return 2`（`v41_memwatch_report.py:93-100`）。注释里
记着 2026-09-22 T4 事故：剂量段被 flush 中止、**一行数据都没采到**，而 `bad = [...]` 在空列表上
恒为空 ⇒ 报告给了绿字。**判据必须是"有数据"，不是"没有坏数据"**。同族教训还有
`v41_memwatch.sh:29-30` 记的"`mark`/`stop` 只有本地实现 ⇒ 四机只有 head 有标记，报告对 3/4 台
机器**沉默通过** —— 量具自己必须先被量"。

---

## 15. 判据式总表（一眼可查）—— 2026-09-23 补

把本套件**全部守卫的判据式**集中成一张表。前 5 列是判据本体，最后一列是 **fail-closed** 性质
（"判不了"时是**当成故障**还是**当成通过/SKIP**）—— 这一列是本次文档化的重点：**同一套件里两种
设计都有，混着读会误判风险**。

| # | 守卫（判定入口） | 读什么量 | 阈值 / 判据 | 越界动作 | fail-closed |
|---|---|---|---|---|---|
| 1 | `GUARD` 行（`check`） | `systemctl show` 真值（Type/ActiveState/Result/Restart）+ 脚本 md5 前 12 | 与 `guards.conf` 期望不符 | 渲染 FAIL/WARN，**两者都计入问题数** ⇒ `check` rc≠0 + `guard-alerts.log` | **是** |
| 2 | oneshot 卡死/停摆（`check`） | `ActiveEnterTimestampMonotonic` / `ExecMainExitTimestampMonotonic` | 卡在 `activating`/`active` > **120s**（`GUARD_ONESHOT_RUN_MAX`）；最近成功 > **900s**（`GUARD_ONESHOT_MAX_AGE`） | DEGRADED/DEAD ⇒ rc≠0 | **是**（但瞬时态按持续时间判，防每 10 次误报 1 次） |
| 3 | 定时器楔死（`check`） | `NextElapseUSecMonotonic` | `infinity` **且**依赖单元不在执行 | FAIL | **是**（依赖单元正在执行 ⇒ 归 #2 判，不误报） |
| 4 | `RECOVERY` 自锁（`check`/`status`/`preflight`） | 冷却 state 文件的时间戳 | 未来时间戳（`NOW−LAST<0`）⇒ **DEAD**；链脚本缺 `NOW - LAST)) -ge 0` 护栏 ⇒ **DEGRADED**；state 缺失 ⇒ WARN；冷却 = 1800s | FAIL/DEGRADED；修复 = `echo 0 > /opt/aicad-prod/state/healthcheck-rebuild.<role>` | **是** |
| 5 | 接线门槛（`check`，RECOVERY 用） | 本机有没有单元调用该自恢复链 | 无调用者 ⇒ **SKIP**（不是 WARN） | 不计数 | **是**（区分"坏了"与"没接线"，修掉 worker 上的永久假 WARN） |
| 6 | `PRECOND kind=proc`（`preflight`） | `pgrep -af` 的**真 argv**（排除 `bash -c` 包装壳） | 命中数 ≥ 期望（例：`oom_gate.sh monitor -w 6 -f 1.5 -n 3 --iv 10 -a -e 1` 期望 1） | FAIL（`必需=yes` 时**阻断开窗**） | **是** |
| 7 | `PRECOND kind=envpin`（`preflight`） | `.env.tp4` 里的单个子串 | 子串必须出现：`MAX_TOTAL_TOKENS=9600000` / `MAX_RUNNING_REQUESTS=16` / `SGLANG_DSV4_KV_LAYOUT=fork-v4-fp4` / `IMAGE=dsv41-sglang-optimized:0.2.8` / `DSV41_CACHE_GIB=1` / `--enable-mixed-chunk` | FAIL | **是** |
| 8 | `PRECOND kind=memfree`（`preflight`） | `eff_idle = MemFree+Cached+SReclaimable−Shmem` | ≥ **110000 MiB**（`pool-free`） | FAIL ⇒ **不许启动**（窗口 2 四机 OOM 的直接教训） | **是** |
| 9 | `PRECOND kind=memfreeraw`（`preflight`） | **裸** `MemFree` | ≥ **98304 MiB**（96 GiB，`memfree-raw-vllm`） | FAIL | **是**（"有效空闲"口径会掩盖池缩水） |
| 10 | `PRECOND kind=memavail/diskfree/file/md5`（`preflight`） | MemAvailable / 挂载点可用 / 存在性 / md5 前 12 | 在役：`disk-free-data` ≥ **20480 MiB**；`healthcheck-rebuild-P3` md5 = `ab9a1954ce07`；`weights-sha256`、`engine-pin` 判存在性 | FAIL | **是** |
| 10a | `PRECOND kind=unitprop`（`preflight`） | `systemctl [--user] show -p <prop>` 的数值 | 参数 `<unit>::<prop>`，期望 = **数值上限**（读不到/非数值 ⇒ SKIP） | FAIL | **是**（读不到 = SKIP 而非 PASS）——**2026-09-23 备注：`guards.conf` 里暂无行使用它**（`guardctl.sh:406-420`） |
| 11 | `PRECOND kind=archscr`（`preflight`） | 外部体检脚本的 rc | **`0=OK / 1=FAIL / 2=SKIP`**（现役两个：`clock-sm-actual`、`flashinfer-arch`） | rc1 ⇒ FAIL（两者 `必需=no` ⇒ WARN 级，**但仍计数**） | **部分**（rc 2 = 判不了 ⇒ SKIP） |
| 12 | **`oom_gate.sh monitor`**（独立 systemd 单元，不经 guardctl） | `eff_idle`（`/proc/meminfo`，KiB） | `-w 6 GiB` 警戒（**只记日志**）／`-f 1.5 GiB` **连续 3 次**（`-n 3`，`--iv 10`）／`-e 1 GiB` 单采样零等待 | `-a` ⇒ **`docker stop -t 15` 本机 `dsv41-*`/`vllm-v41-*`**；`-e` 退出码 4、`-f` 退出码 3；止损前落现场快照（`V41_GATE_SNAP=1`） | **是**（动作侧；报警侧见 #12a） |
| 12a | `oom-gate-monitor.service`（`GUARD` 行，`check`） | 单元 `Type/ActiveState/Restart` | 与 `guards.conf:119` 期望不符 | FAIL（`必需=yes`） | **是** |
| 13 | `gb10-clock-cap.service`（`GUARD` 行，`check`） | 单元状态（oneshot + `RemainAfterExit`） | `Result≠success` 或单元消失 | FAIL | **是**（**但只看状态、不看值** ⇒ 见 #14） |
| 14 | `clock-sm-guard.sh`（= #11 的 `archscr`） | `clocks.sm` | ∈ **[2250,2400]**（`CAP=2400`/`TOL=150`） | rc1 ⇒ FAIL；**rc2 ⇒ SKIP** | **部分** |
| 15 | `journal_watch.sh`（timer 10min） | `journalctl -k` 增量游标 | `NV_ERR_NO_MEMORY` ≥1 ⇒ **WARN**；`invoked oom-killer`/`Killed process` ≥1 ⇒ **CRIT**；watchdog/lockup ≥1 ⇒ **CRIT**；`dsv41-serve` 失败行 ≥1 ⇒ **CRIT**；**journalctl 不可读 ⇒ WARN** | 告警面（`guard-alerts.log` + syslog + 可选 hook） | **是**（读不到 ≠ 零事件） |
| 16 | `wedge-watch.sh`（timer 5min） | ping / TCP 22 / ssh banner | `WEDGE`（ping 通+TCP 可连+无 banner）⇒ **CRIT + rc2**；`NET-DOWN` ⇒ **CRIT + rc1**；`SSHD-DOWN` ⇒ WARN | 告警面 | **是**，**但无法区分用户态冻结 vs 内核级楔死**（须补"采样断档"判据，见 §13.2） |
| 17 | `gen_probe.sh`（timer 30min） | 8899 的 `/v1/models` + 单发生成 | 答案必须含 **`42`**；`--max-time 120` | 失败 ⇒ **CRIT**；**栈不服务 ⇒ 静默 `exit 0`** | **停泊期有意 fail-open** |
| 18 | `gate_archive.sh`（timer 6h） | `gate.sh --json` 的 rc | rc≠0 ⇒ **CRIT**；存档 `logs/gate-history.jsonl`（留 2000 轮） | 告警面（脚本自身**恒 `exit 0`**） | **否**（有意：只存档/告警，不阻断） |
| 19 | `overlay-drift-check.sh`（**手工**） | 宿主/容器/镜像三份 sha256 + `docker inspect .Mounts` 形态 | 任一 `DRIFT`/`MISSING` ⇒ rc1；判不了 ⇒ rc2 | 只读报告 + **按形态**给处置（bind⇒重建容器；image⇒重建镜像） | **否**（不自动修） |
| 20 | `flashinfer-arch-guard.sh`（= #11 的 `archscr`） | 在役 mmap 的 AOT 模块 cubin/PTX | 必须含 `sm_12x` **或** `compute_*` | rc1 ⇒ FAIL；无在役对象 ⇒ **rc2 ⇒ SKIP** | **部分** |
| 21 | `check` 内联：gateway 8001 | `curl 127.0.0.1:8001/health`（5s） | 200 ⇒ PASS；容器 `health=starting` ⇒ **SKIP**；`role≠head` ⇒ **SKIP**；`GUARD_CHECK_GATEWAY=0` ⇒ **SKIP** | 其他码 ⇒ **FAIL**（计数） | **部分**（停泊/维护态会 FAIL：2026-09-23 实测 `guard-check.service` 因 `HTTP 502` 每 15min 记一条 CRIT，见 §13 表下方注记） |
| 22 | `check` 内联：保活断言 | `NRestarts` / `Result` / `ActiveState` | head：`NRestarts>3` ⇒ **FAIL**、`Result≠success` ⇒ **WARN**；worker waiter：`ActiveState=failed` ⇒ **FAIL**、`NRestarts>500` ⇒ WARN（停泊期累积属预期） | FAIL/WARN 计数 | **是**（2026-09-21 补：failed 必 FAIL，此前会打"PASS waiter active"） |
| 23 | `check` 内联：`fabric:GID` | `/sys/class/infiniband/<hca>/ports/1/gid_attrs/types/3` | 四口齐全且全 `RoCE v2`；**缺 HCA ⇒ FAIL**（"驱动塌≠无洞"）；有洞 ⇒ FAIL | FAIL 计数 | **是** |
| 24 | `check` 内联：`gpu:时钟` | 3×`nvidia-smi`（util / clocks.sm / temp） | 撞上 `util≥50%` **且** `clocks.sm<1200MHz` ⇒ **FAIL**（PD 安全模式嫌疑）；采样窗全空转（util<50）⇒ PASS **不判**；NVML 不可读/字段 N.A ⇒ **SKIP**；温峰 ≥85°C ⇒ WARN | FAIL/WARN 计数（修复=拔墙 AC，warm reboot 无效） | **是**（空转不判=防假阳；但 NVML 不可读 ≠ 健康） |
| 25 | `check` 内联：`docker:停泊复活` | `docker ps` 名字 | 出现 `sparkDash*` ⇒ WARN（附停法） | WARN | **是** |

> **怎么用这张表**：`check` 是"能自动判的都判"（1-5、12a、13、21-25）；`preflight` 是"开窗前的地板"
> （6-11、14、20，其中 `memfree`/`memfreeraw` 在产期**必然 FAIL** 属设计）；timer 面（15-18）是
> "持续的、便宜的、能出声的"；手工面（19）是"开窗前后按需"。
> ⚠ 唯一的"有意 fail-open"是 #17 停泊期让位；唯一的"恒 exit 0"是 #18。

---

## 16. 引用与出处 —— 2026-09-23 补

**说明**：本套件文档里出现的**外部编号/外部指针**此前**没有任何一处集中登记**（README 本体一处
都没收，全部散落在 `BASELINE.md`、`guards.conf` 的注释与脚本头注里）。本节按下表格式统一登记：
**编号 | 仓库 | 一句话 | 本地回指**。行号是 **2026-09-23 修订后**的行号。
⚠ 没有 URL 的一律写"**仓库+编号，未附链接**"——**不编 URL**。

| 编号 | 仓库 | 一句话 | 本地回指 |
|---|---|---|---|
| `#5237` | flashinfer（上游） | Python 层 arch 过滤器 `supported_major_versions=[10]` 拒掉 major 12；**靶子 `moe_utils` 不在我方路径上**（我方 MoE 走 b12x，从未取件） | `guards.conf:137-146`、`flashinfer-arch-guard.sh:12-14`、`BASELINE.md` 的「步骤 0 定谳（原命题需改写）」条；**仓库+编号，未附链接** |
| `ADR-004` | 本项目 ADR（决策记录） | **内存地板守卫**（止损线 2026-09-23 起 `oom_gate -f 1.5`，原 3）的决策依据 | ✅ **已生效指针**（2026-09-23 复核：`test -f ~/w6-kit/adr/ADR-004-three-gib-floor-guard.md` **通过**，路径已落位）⇒ 定义见 `~/w6-kit/adr/ADR-004-three-gib-floor-guard.md`。（本行原记「全树无定义、无 `~/w6-kit/adr/` 目录 ⇒ **待生效指针**」——那是本表落笔当时的实测状态，**已被该文件的落位取代**。）使用点（行号为 **2026-09-23 就地补注释后**实测）：`~/w6-kit/oom-gate/oom_gate.sh:263`、`~/w6-kit/v41_dose_ladder.sh:76` 与 `:330`、`~/w6-kit/v41_win_mmprobe.sh:169`（四处均已就地补上本指针注释；新增注释行分别在 `:261-262`、`v41_dose_ladder.sh:77-78` 与 `:328-329`、`:167-168`） |
| `WINDOW-RUNBOOK §5 / §7` | 本项目运维 runbook | §5 = 停泊与放行（**裸进程重挂命令在 §5.3**）；§7 = 时钟健康预检（**裸进程缺口在 §7.5**） | ✅ **已生效指针**（2026-09-23 复核：`test -f ~/w6-kit/WINDOW-RUNBOOK.md` **通过**）。**引用点**：`guards.conf:137`（原文 `:123`；该处已同步把 §7/§5 校准为 **§7.5 / §5.3**——依据是本册 §7 的「编号对账」段）。★另一份 `~/r4-ops-work/r9-ops-20260914/evidence/delivery-20260916/WINDOW-RUNBOOK-20260917.md` **已核实不是同一份**：它是 2026-09-17 那次切换窗的**专用册**（本通用册 §7「编号对账」明写"两者并存，不要混引"；其 §5=治理复位、§7=已知缺口） |
| vLLM `#52645` | vLLM（上游） | 工具调用截断三保证的**回移**来源（v0.2.4） | `BASELINE.md` 的「2026-09-19（收官）：v0.2.3 正式检查点 + 客户坑审计 + V3 矩阵 + git 提交」节 → `工具调用截断三保证（vLLM #52645 回移）` 条；**仓库+编号，未附链接** |
| b12x `02407f65` | b12x（上游 commit，短号） | E4M3 subnormal 原生解码 | `BASELINE.md` 的「2026-09-19：v8 上线（b12x 上游回补）+ MoE on/off A/B 定谳」节 → `b12x-site intrinsics.py` 行（对应 `intrinsics.py` `24b1049ac800 → 2302dd1ec28b`）、`guards.conf:125`；**仓库+短号，未附链接** |
| b12x `ff36d2d1` | b12x（上游 commit，短号） | MXFP8 swizzle 越界读防护 | `BASELINE.md` 的「2026-09-19：v8 上线（b12x 上游回补）+ MoE on/off A/B 定谳」节 → `b12x-site dense_gemm.py` 行（对应 `dense_gemm.py` `e2c5233f6a4b → 75f774c2ef4d`）；同上 |
| `#34554` | **外部报告**（未注仓库） | prefill 限份补丁（"L1186 思想"）的借鉴来源 ⇒ 落地为 `schedule_policy.py` + `DSV41_PREFILL_SHARE_TOKENS`（v11，overlay 42 条） | `BASELINE.md` 的「2026-09-19（深夜终窗）：v11 上线 + chunk 8192 落地 + 调度限份开关」节 → `v11` 行（`L1186 思想，外部报告/#34554 借鉴`）；**仓库未注+编号，未附链接**（原文只写"#34554"） |
| `#40217` | **外部报告**（未注仓库） | 掩码 bound 的两个候选案（非末批空发布 / 块粒度 publish+consume shim） | `BASELINE.md` 的「2026-09-19（深夜终窗）：v11 上线 + chunk 8192 落地 + 调度限份开关」节 → `掩码 bound（#40217 思想）` 行（判定 = **未落**）＋ 实证文件 `~/V41-EXTERNAL-AUDIT-40217-VERDICT-20260919.md`（2026-09-23 实测存在，6914 B）；**仓库未注+编号，未附链接** |
| （旁证）`~/V41-ABCD-SCOPED-PLAN-20260922.md` | 本项目窗口规划 | §11.3 记有"冻结 vs 楔死"的两条翻案证据与"待补量具"两条 | §13.2 引用（该文件 318-333 行，2026-09-23 实测存在） |
| （旁证）`~/r4-ops-work/r9-ops-20260914/evidence/` | 本项目 r9 窗口证据树 | `slowboot-forensics-20260916/SLOWBOOT-FORENSICS.md`（**本文件第 12 节**「慢靴判据」的依据）、`crossreview-20260917/REVIEW-GOVERNANCE.md`（治理交叉审核）、`delivery-20260916/WINDOW-RUNBOOK-20260917.md` | **本文件第 12 节**、`BASELINE.md` 的「2026-09-17 五次更新（部署窗口 + 三份交叉审核的修复）」节 → 审核来源注（`crossreview-20260917/REVIEW-GOVERNANCE.md`）；三份 2026-09-23 均实测存在（`SLOWBOOT-FORENSICS.md` 40515 B、`REVIEW-GOVERNANCE.md` 37836 B、`WINDOW-RUNBOOK-20260917.md` 9507 B）。⚠ 回指列写的「本文件第 12 节」= **本文件**（`guard/README.md`）的 §12，**不是**上列两份报告的章节号：`SLOWBOOT-FORENSICS.md` 只到第 7 节、`WINDOW-RUNBOOK-20260917.md` 只到第 7 节（含 4.x 子节），**两份都没有第 12 节**（原写法是一个不带文档名的节号（`§` + 12），曾被读成上列两份报告的章节号 ⇒ 2026-09-23 改成不冒充章节号的写法） |

> ★**两个总登记处**（2026-09-23 落位，与本文件同级）：`~/w6-kit/REFERENCE.md`（**上游编号**总登记）、
> `~/w6-kit/GLOSSARY.md`（**内部代号**总登记）。本节登记的是"本套件文档里出现的"引用；要查全项目口径
> （某编号属哪个仓库、某代号在哪定义）请直接查那两个文件。
>
> ⚠️ **行号漂移提醒**：本表引用 `guards.conf` 的行号是 **2026-09-23 注释改动前**的值；同日对
> `guards.conf` 做过注释级改动（新增 `nvmodule-guard.service` GUARD 行等），行号有位移。
> **完整 old → new 对照（2026-09-23 实测）**：memfree-raw-vllm `78→83`、gb10-clock-cap `97→102`、
> clock-sm-actual `105→110`、oom-gate-monitor.service `119→124`、裸进程缺口（原 `:123`）`→137`、
> guard-watch `124→148`、`#5237` 两处 `140/144→164/168`、flashinfer-arch `146→170`。
> 本文件它处（§10/§11/§13/§15 各表）沿用旧行号的引用**同理**——**引用请优先按行名定位**。
>
> ★**登记缺口（如实登记）**：`#5237`/`#52645`/`#34554`/`#40217` 四个编号**在本套件里从来没有 URL**，
> 只有编号 —— 想溯源必须回到当时的交接文档（`~/r4-ops-work/…` 与 `~/V41-*.md`）。本节**不补**没有
> 证据的链接（"没有 URL 的不要编 URL"）。
