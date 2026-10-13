# 守卫基线快照（guardctl snapshot）

<!-- refcheck:historical-md5:file —— 本文件通篇是**变更台账**：表内 md5 一律是'该次变更当时的值'，现值以 `MD5SUMS` 为准（`verify-governance.sh` 第 [4] 步用真 `md5sum -c` 校验）。声明让量具（`w6-kit/refcheck.py`）不拿现值去判历史值——但同表内的路径/行号/锚点仍然照查。 -->

> 🔴 **2026-09-23 注记（读之前必看）**：**下面这张快照表是 2026-09-16 的残留产物**（表头时间
> 也停在 `2026-09-16T05:19:17+00:00`）。其中 `concurrency-proxy-v2.service` 的 md5
> `0606e1e24926` **已过期** —— 该行的合法改动记录在本文件下半部的「2026-09-18 追记」
> （2026-09-23 修订前位于 :225），**权威值 = `d9aeaab640f7`**（= `guards.conf:31` 的钉版，
> 2026-09-23 对 `/opt/aicad-prod/scripts/concurrency_proxy_v2.py` 实测 `d9aeaab640f77145583b629939b314be`）。
> ⇒ **权威口径 = `guards.conf` + 本文件下半部的修订各节；头部快照只作历史留存。**
> ⚠ **不要跑 `guardctl.sh snapshot` 覆盖本文件** —— 那会**冲掉下半部的修订史**；本文件原有的
> 约定（快照表下方的两行引注："更新本文件即等于承认当前状态是新的正确基线"）在 2026-09-23
> 修订中据此放宽为 **"只追加注记、不覆盖"**（本次修订即按此办理：头部快照未改动一个字节）。
>
> 📇 **总登记处指针**（2026-09-23 落位，与本文件同级）：本文件里出现的**上游编号**归
> `~/w6-kit/REFERENCE.md`、**内部代号**归 `~/w6-kit/GLOSSARY.md`（两份 2026-09-23 均 `test -f` 实测存在）。
> 要溯源某个编号属哪个仓库、某个代号在哪定义，**先查那两个文件**，不要在本台账里就地猜。
> ⚠️ **行号漂移提醒**：本文件（尤其下半部各修订节）里指向 `guards.conf` 的行号是**当时**的值；
> 2026-09-23 对 `guards.conf` 做过注释级改动（新增 `nvmodule-guard.service` 行等），行号有位移
> （例：`gb10-clock-cap` `:97`→`:102`、`clock-sm-actual` `:105`→`:110`）。**引用请按行名定位。**

主机: dgxspark01   角色: head   时间: 2026-09-16T05:19:17+00:00

| 单元 | 角色 | Type | Restart | ExecStart | md5(12) | 状态 |
|---|---|---|---|---|---|---|
| vllm-logdump.service | head | simple | - | （见 guards.conf） | 3d3793d0244a | active |
| concurrency-proxy-v2.service | head | simple | - | （见 guards.conf） | 0606e1e24926 | active |
| vllm-logdump.service | worker | simple | - | （见 guards.conf） | 3d3793d0244a | active |
| gb10-clock-cap.service | all | oneshot | - | （见 guards.conf） | - | active |
| daily-smoke.timer | head | daily-smoke.service | - | （见 guards.conf） | - | active |

> 更新本文件即等于承认当前状态是新的正确基线。
> 若脚本被合法修改，请同时更新 guards.conf 里的期望 md5，否则 check 会持续报 DRIFT。

---

## 2026-09-16 台账更新（SGLang 时代对齐 · r9-ops 窗口）

| 对象 | 旧 | 新 | 说明 |
|---|---|---|---|
| guardctl.sh | 8d0f39b82980 | **525680493eb3** | 新增两个只读 kind：`proc`（守护进程在役/参数漂移）与 `envpin`（配置里的单个事实） |
| guards.conf | 061b4674037c | **9b3821b6909e** | vLLM 时代三条单元退役（`#RETIRED-20260916` 前缀，保留供回退）；新增 4 条 SGLang 前置 |
| /opt/aicad-prod/scripts/vllm_logdump.sh | b76d0c360bb7 | **3d3793d0244a** | 四机同改：第 167 行预过滤 `grep -E '^vllm'` → `'^(vllm|dsv41)'`；备份 `.bak-20260916-sglang` |

**为什么改 logdump**：`docker ps -a | grep -E '^vllm'` 把 SGLang 容器名（`dsv41-head`/`dsv41-worker`）
挡在 LOGDUMP_PATTERN 之外 ⇒ 2026-09-14 切栈后**两天零转储**（目录里最后一份是 09-14 02:55 的
vllm-v41-baked-rank0.log）。取证链在"正好要压内存边界"的时刻是瞎的。修后 `dsv41-head.log`
与 `dsv41-worker.log` 已在四机落盘。

**为什么新建 `proc`/`envpin`**：
- `proc`：守护的失效是无声的（进程没了不报错）。W4 事故根因就是"止损守护未在役"，
  而当时**没有任何检查项会说出这件事**。`proc` 的 pattern 直接写全 argv（含 `-f 6 -n 3
  --iv 10 -a`），因此"进程没了"与"参数被调松了"两种失效各有条目。
- `envpin`：`md5` 钉的是整份文件，改一个 pin 值就会让整条 md5 判定失效；`envpin` 钉
  `<file>::<substring>`，于是"改 pin = 改台账一行"，漂移可归因。

**退役口径**：vLLM 三个单元 `inactive + disabled` 是**有意退役**（2026-09-14 生产切到 SGLang），
不是失效。在册会让 `check` 永远报 WARN/FAIL —— 那正是 v0.4.1 修掉的"喊狼来了"。
回退 vLLM 栈时 uncomment 三行 + `systemctl enable --now`。

---

## 2026-09-16 二次更新（变更 #15：NSEQ 16 + pin 9.6M）

| 对象 | 旧 | 新 | 说明 |
|---|---|---|---|
| guards.conf | 9b3821b6909e | **4b206027f64a** | 止损守护地板 `-f 4`→**`-f 3`**；`sglang-pin` 改钉 `9600000`；新增 `sglang-nseq` 钉 `MAX_RUNNING_REQUESTS=16` |
| guardctl.sh | 525680493eb3 | **1b5aada4a426** | ★修缺口：`hold` 对 `oom_gate.sh monitor` **失明**（见下） |
| .env.tp4（生产） | `3b89e2734cae…` | **`d437de37713d…`** | `MAX_RUNNING_REQUESTS=12→16`、`MAX_TOTAL_TOKENS=8,000,000→9,600,000` = 16×600k |

**为什么把守护地板从 4 降到 3**：实测 16 路×245.7K 负载下 head eff_MIN=**3.18**、avail_MIN=2.20，
4 GiB 会在**合法重载**下 `docker stop` 生产。3 = 用户划定的安全地板，仍未破。
⚠⚠**余量只剩 0.18 GiB**：本守护已从"余量守卫"退化成"最后一道 OOM 断路器"。
NCCL pinned host RAM 回收（~4.5 GiB）兑现后**必须回到 6**。

**修掉的缺口（`hold` 对裸进程守卫失明）**：`oom_gate.sh monitor` 是 nohup 裸进程、不是 systemd
单元，所以 `cmd_hold` 那套"停泊桩"机制**看不见它**。2026-09-16 实测：hold 打印"守卫已全部停泊
（容错链为关闭状态）"，而 `-f 3 -a` 的 monitor 仍在跑。这不是"守卫在役"而是**自伤**：开窗时
内存本就该低（池子空出来才好启动），它会按**窗口内完全合法**的低内存去 `docker stop` 生产容器。
修法：`hold` 把 monitor 的 **cwd+原 argv** 存进 `state/hold-<tag>.oomgate` 再 TERM
（自动排除 `bash -c` 包装壳，否则 release 会起出两份 monitor = 两套 `-a` 同时 docker stop）；
`release` 按原样 nohup 起回，并用 guards.conf 的 `proc` 模式**断言**真的在役，断言不过即 CRIT
（"本次收工没有兜底"）。已用 `GUARD_CONF` 临时清单做**往返实测**：停泊后 0 进程、state 文件
内容正确、重挂后 1 进程且 argv 与台账逐字一致。


---

## 2026-09-16 三次更新（步骤 9 判决 NOGO + 步骤 0 定谳 + 新增 arch 体检）

> ⚠ **本表口径（2026-09-23 补）：表内 md5 = 该次变更「当时」的值**（`md5(12) 旧` = 改前、`md5(12) 新` = 改后），
> 是**变更记录**、**不是现值断言**。三行的「新」值**现在都已再次变过**（2026-09-23 实测：
> `guards.conf` = `b2cd3bfabf9d…`、`guardctl.sh` = `c37df058d0d0…`、`flashinfer-arch-guard.sh` = `3e6f1957ced2…`）。
> **文件现值以 `guard/MD5SUMS` 为准**（同目录，随包；`bash guard/verify-governance.sh` 的第 [4] 步就是
> `md5sum -c`），本表只用于回溯"那一次改了什么"。

| 文件 | md5(12) 旧 | md5(12) 新 | 变更 |
|---|---|---|---|
| guards.conf | 4b206027f64a | **c2fc89bd0d74** | 新增 `PRECOND\|head\|flashinfer-arch\|archscr\|…`（见下） |
| guardctl.sh | 1b5aada4a426 | **ca3f20601355** | 新增 `archscr` 前置 kind（执行外部体检脚本，0/1/2 ⇒ OK/FAIL/SKIP） |
| flashinfer-arch-guard.sh | （新增） | **dacd7afc7339** | SM121 上 flashinfer AOT 取件的 arch 体检 |

### ⚠️ 更正上一节的一句话：**"NCCL pinned host RAM 回收（~4.5 GiB）兑现后必须回到 6"不成立**

步骤 9 实测判决 **NOGO —— 无 4.5 GiB 可回收**（引擎在役、只读测量，四机一致）：

| 读数 | 四机实测 |
|---|---|
| `Mlocked` | **0.02 GiB**（容器内 23,428 kB） |
| `Shmem` | **0.67 GiB**（容器内 704,236 kB） |
| `/dev/shm` used | **66–68 MB** |
| `SUnreclaim` | 1.21–1.23 GiB |

原因：那个 "~4.5 GiB pinned host RAM" 是 **NCCL 未配置默认值**的画像，而**我方早已关掉它** ——
`.env.tp4` 与 `start.sh` 在役都带 `NCCL_SHM_DISABLE=1`（+ `NCCL_MAX_NCHANNELS=4`、
`NCCL_BUFFSIZE=8388608`、`NCCL_CUMEM_HOST_ENABLE=0`）。旧台账把 MIA 那份 SGLang 的默认形态
记成了"我方待回收"——**串了坐标**。

⇒ **守护地板维持 `-f 3`，不得因"将来能买回 4.5 GiB"而松劲**。当前余量 **0.18 GiB**。
⇒ 想加厚余量的可行杠杆只剩三条：**步骤 4**（削 indexer 瞬态谷，本窗执行）、**降 NSEQ**（−1.2 GiB 的主要代价项）、**降 pin**（0.850 GiB/M token）。
⇒ ⚠️ 不要再把 `Mlocked`/`Shmem` 当"待回收量"：它们现在就是**底线**。真身 `non-torch`
随机游走（3.47–6.50 GiB）是**启动期 host 堆高水位**，与 NCCL 无关，改 NCCL env 无用。

### 新增 `archscr` kind 与 `flashinfer-arch` 前置（步骤 0 的落地形态）

**步骤 0 定谳（原命题需改写）**：原计划是"让加载走 JIT 产物 + 断言 sm_120"，靶子是上游 **#5237**
（`flashinfer/jit/moe_utils.py` 的 `supported_major_versions=[10]` 拒掉了 major 12）。实测：

1. #5237 的靶子 `moe_utils` **不在我方路径上**——我方 MoE 走 **b12x**，`moe_utils` 从未被取件。
   AOT 包里它确实只有 `sm_100a/sm_103a`，但包内 839/907 个模块都不参与我方路径，旧不旧无关紧要。
2. **在役进程真正 mmap 进来的 AOT 模块只有 2 个**（`/proc/<scheduler pid>/maps` 实测）：
   `fp4_quantization_120f`（sm_120f）与 `sparse_mla_sm120`（sm_120）——**都是 12x 原生**，
   SM121 上合法。⇒ **不需要"改成走 JIT"**，当前取件形态本身就是对的。
3. 真正残留的隐患是**机制性**的：`JitSpec.try_load()` 在 `is_aot` 时
   **直接 `return self.load(self.aot_path)`，不做任何 arch 校验**
   （`is_aot = aot_path.exists()`）⇒ 哪天某条路径去取一个 100a/103a-only 的包，
   症状会**推迟到首次核启动**，报错点离病因很远。所以正确的动作不是改取件逻辑，
   而是**加一道体检**。

⇒ 落地 = 本节的 `flashinfer-arch-guard.sh` + `archscr` kind，接进 `preflight`。
**正负双向已验**：真脚本 ⇒ `PASS … OK (2 个取件全部 SM12x 可用: fp4_quantization_120f sparse_mla_sm120)`；
注入假脚本（打印 sm_100a 并 `exit 1`）⇒ `WARN … FAIL …`。
判据是**在役路径真正 mmap 的模块**，不是包内全量；引擎停泊时脚本退出 2 ⇒ `SKIP`（不误报）。
`必需=no`：这是一道**新**检查，按本套件"不许喊狼来了"的约定先观察，不阻断开窗；
但 **WARN 必须在开窗前查清**。

---

## 2026-09-16 四次更新（交付自检发现的三处真缺陷 · 四机对齐）

导火索：给四机拉常驻守护时，顺手核了一遍**治理套件自己**的版本 —— 才发现它**不在册**
（守卫清单只登记它检查的对象，不登记它本身）⇒ 各机各版，而巡检永远看不见。

| 对象 | 旧 | 新 | 变更 |
|---|---|---|---|
| `guardctl.sh` | `ca3f20601355` | **`2b695bfefc76`** | `watch` 把 `HELD` 由 CRIT 降为 **WARN**，与 `cmd_check` 口径一致 |
| `jit-header-refresh.sh` | `be6af515da35`（**早期版本**） | **`1602980626f4`** | 交付包错装早期版本：缓存挂 `/root`、无 `--overlay-map` |
| `start.sh` | `f5db9b0e1666` | **`bbcb1bbf4b5b`** | `cmd_serve` 接线 `guard-onstart.sh`（只读、`\|\| true`、`GUARD_ONSTART=0` 可跳过） |
| `verify-governance.sh` | （新增） | — | 装完自检：齐备性 + 语法 + **能力断言**（34 项），已证非空洞（4/4 变异被抓） |
| 02/03/04 的 `guardctl.sh` | `8d0f39b82980` | **`2b695bfefc76`** | 四机分叉消除：旧版缺 `proc`/`envpin`/`archscr` 与 hold 对裸进程守卫的处理 |
| 02/03/04 的 `guards.conf` | `061b4674037c` | **`69849d081516`** | 同上（旧版仍在册 vLLM 单元 ⇒ 天天 WARN/FAIL） |
| 02/03/04 缺 5 个文件 | — | — | `flashinfer-arch-guard.sh` / `jit-header-refresh.sh` / `jit_refresh_exec.py` / `probe_deps_closure.py` / `overlay-drift-check.sh` 原本只在 01 上有 |

**三处缺陷为什么值得记**：

1. **`HELD` 记成 CRIT**：HELD = 脚本是停泊桩 = **有意**的维护态（`cmd_check` 本来就按 WARN 处理、
   不计入 `bad_n`）。而 `README §8` 让外部监控直接 `grep CRIT` ⇒ 每次开窗都会往告警通道灌假警报，
   与 v0.4.1 修掉的"喊狼来了"同类。已用**同机、同 conf、间隔数秒**的 A/B 证过（04 机，
   唯一变量 = 脚本）：前臂 `[CRIT] … -> HELD`，后臂 `[WARN] … -> HELD`。
2. **交付包里的 `jit-header-refresh.sh` 是早期版本**：它的缓存挂在容器 `/root/.cache/sglang/jit`，
   而镜像 `/root` 是 0700、容器以 uid 1000 跑 ⇒ 不仅写不进，`--check` 会对**所有**变体
   **静默报 MISS**（永远不能 PASS 的闸门 = 没有闸门）；且该版不支持 `--overlay-map`，
   会让驱动容器对着**基座镜像**的源码树编译（实测症状：`identifier "V41_FP4" is undefined`）。
   ★注意它**不是**被 md5 表挡住的 —— 表上的 md5 与那份错文件**恰好自洽**。这正是新增
   `verify-governance.sh` 的动机：断言**能力**，而不是抄数字。
3. **启动路径上没有守卫体检**：同名钩子只挂在 vLLM 时代的 `start_tp4_*.sh` 上，而生产已切到
   SGLang 的 `start-tp4.sh` → `start.sh`。文档里"`start-tp4.sh` 里已有可选钩子"当时是**错的**。
   已接线并实测：`rc=0`、四机 `ALL-OK`、`GUARD_ONSTART=0` 确实跳过。

**仍未做（如实登记）**：`start.sh` 只挂"体检"不挂"止损" —— `oom_gate.sh monitor` 与
`guardctl.sh watch` 两个常驻**仍是手工拉起**（`nohup`/`setsid`），没有任何单元或定时器保证它们
活着；而它们**恰恰**是 2026-09-15 W4 事故的缺失项。当前靠 `guards.conf` 的 `proc` 前置在
**开窗前**（`preflight`）断言 + 本次新接的启动路径体检兜着。要做成"永不失效"需 systemd
user 单元或 timer（无 root 可用 `systemd --user`），留待运维决策。

## 2026-09-17 四次更新（交付前治理清查 · 三份交叉审核的修复）

| 文件 | md5(12) 旧 | md5(12) 新 | 变更 |
|---|---|---|---|
| guardctl.sh | ca3f20601355 → 2b695bfefc76 | **9151336e49dd** | ①`explain` 里 PRECOND 循环用 `want` 接行内字段 ⇒ 覆盖了过滤器变量，**一条前置都显示不出来**（开窗前要读的正是它）②`u_script` 只认 `.sh` ⇒ 业务入口（python）的"MainPID 跑的是不是它"断言恒真 ③`proc` 前置未排除 `bash -c` 包装壳 ⇒ 真身死了也能凑够期望数 ④`status` 容器模式只认 `vllm-tp4-rank*` ⇒ 每次报恒假 WARN ⑤`doctor` 的 NV_ERR 无近期性门槛 ⇒ 16 小时前已结束的旧事故持续报 CRIT ⑥oneshot 分支未识别 `RemainAfterExit` ⇒ 登记这类单元会得到永久假 DEAD ⑦自恢复判定新增**接线门槛**（本机没单元调用该链 → SKIP，修掉 worker 上的永久 WARN）⑧SKIP 升为一等结论 |
| guards.conf | c2fc89bd0d74（再历 69849d08…） | **264b16b0d97a** | ①三条 PRECOND（pin/NSEQ/KV 布局）少一个字段 ⇒ 解释文本整段丢失 ②md5 列全是 `-` ⇒ `DRIFT` 永不触发，而文档要求同步 md5（现钉在役真值：logdump `3d3793d0244a`、proxy `0606e1e24926`）③登记此前无人管的 `gb10-clock-cap.service`（四机）与 `daily-smoke.timer`（01）④新增两条生产旋钮前置：`sglang-image`（镜像 tag）、`sglang-cache-gib`（缓存档=1）⑤`guard-watch` 行的描述里粘着 `oom-gate-floor` 的尾巴（早先"截断再恢复"事故的残渣），已裁 |
| overlay-drift-check.sh | （旧版） | **64414cd61885** | 改为**模式感知**：形态由容器实际挂载判定（不看配置）。bind 模式 → 处置=重建容器；image 模式 → 处置=**重建镜像并分发**（旧版在 image 模式下给的"重建容器"是错建议，照做会白开一个窗） |
| jit-header-refresh.sh | （旧版） | **3fec0c89f24e** | 驱动镜像默认值不再钉死 `v3`：改为 `DSV41_IMAGE` → `.env.tp4` 的 `IMAGE` → 本机最新 `dsv41-sglang-optimized:*`，并断言镜像在场（钉死版本号 = 会骗人的默认值） |
| verify-governance.sh | 93af1be4cf89 | **c758826dd77f** | ①`py_compile` 会往**被检查目录**写 `__pycache__`（装完自检把交付仓弄脏）⇒ 改 `compile()` 不落字节码 ②`--overlay-map` 断言未剥注释（删实现留注释也能过）③清单缺 `HOW-TO-INSTALL.md`/`MD5SUMS` ⇒ 两者皆缺也 PASS；现按布局区分（交付包必须带、在役布局为 WARN）④新增三条回归断言：接线门槛 / SKIP 一等结论 / proc 排除包装壳 / 至少一行钉真实 md5 |
| README.md | 92bc2484729f | 见下 | §3 四机清单**由 guards.conf 重新生成**（此前一直描述 vLLM 时代三条已退役单元） |
| /opt/aicad-prod/scripts/healthcheck-rebuild.sh | p2 `23d02854da50` | **ab9a1954ce07**（02/03/04，本次之前已升级） | README 里"worker 仍是 p2"的表述作废 |

> 生成方式：README §3 与本节顶部快照均**由 `guards.conf` 生成**。手抄一份必然漂移 ——
> 这条教训本轮被 reviewer 独立复现了两次（README 的单元清单、BASELINE 的 md5 表）。

## 2026-09-17 五次更新（部署窗口 + 三份交叉审核的修复）

审核来源：`~/r4-ops-work/r9-ops-20260914/evidence/crossreview-20260917/REVIEW-GOVERNANCE.md`
（治理套件）与 `REVIEW-IMAGE-DEPLOY.md`（镜像/部署形态）。(2026-09-23 补：路径补全 `~/r4-ops-work/`
前缀——旧版写成裸 `r4-ops-work/…`，从 `guard/` 下无法解析；实测该文件存在，37836 B。)
两条结论：**闸门整体不是瞎的**
（18/19 条变异被抓），但有三处"判定会沉默"的缺陷 + 一批文档与实现互相矛盾。

| 文件 | md5(12) 旧 | md5(12) 新 | 变更 |
|---|---|---|---|
| guardctl.sh | 9151336e49dd | **b1d849b47ee4** | **B1** 渲染成 `FAIL` 就必须计入问题数：旧版对 `required=no` 的守卫一边打印 `FAIL` 一边报 `ALL-OK`/`rc=0`（四机在册的 `vllm-logdump.service` 正是 `required=no` ⇒ 它再坏也没人被告知）；现在 `required=no` 渲染成 WARN 但**照样计数**。**B2** `role=all` 的行永不被判定：根因不止一处 —— `read_guards/read_timers` 只认 `$2==$ROLE`，**18 处显示循环又各过滤了一遍**；现统一走 `role_match`（`gb10-clock-cap.service` 因此**第一次**被判定，`guard_verdict` 里专为 `oneshot+RemainAfterExit` 写的分支也从不可达变成在跑）。**B3** 停泊的 RECOVERY 链脚本升为一等结论 `HELD`（旧版"翻译"成评估前像 ⇒ 渲染成 PASS；01 上那枚桩因此挂了 6 天无人知）；`release` 覆盖 RECOVERY 链脚本（GUARD 循环碰不到它，这正是桩回不来的原因）；`release` 只重启**本次真被 hold 过**的 simple 单元（旧版顺手 TERM 了生产 8001 网关）。**I1** `watch` 纳入 RECOVERY（链被关掉没有任何日志）。**I5** `proc` 期望值非整数 → 可读 SKIP（旧版是 `[: -: 需要整数表达式` + 永久假 FAIL）。**I8** 引擎加载期 `/health` 5xx → SKIP（旧版每次起栈/换班都灌一条假 CRIT） |
| guards.conf | 264b16b0d97a | **5c2be7e72484** | **I3** `oom-gate-monitor`/`oom-gate-floor` 改 `role=all`（worker 三机的止损守护**原本不在册**，而 `oom_gate monitor -a` 是每机运行、`docker stop` **本机**容器的）；五条 `sglang-*` 旋钮前置同样改 `all`（`.env.tp4` 四机各一份、rsync 分发，本次实测三机曾与 head 分叉 2 天 ⇒ 现在分叉当天就会在 preflight 现形）。文档更正：`role` 列新增 `all`；`Type` 列注明**只给人读**（判定读 systemd 真值）；`required` 语义改为"渲染分级但都计数"；`TIMER` 行注明只有 6 列、口径=非阻塞但计入；worker 段"仍是 v1.0-p2"作废（实测四机均 `ab9a1954ce07`） |
| verify-governance.sh | c758826dd77f | **f8bedd1d1ce6** | ①清单布局感知：`--ignore-missing` 判在位项 + 缺席项点名 + `oom_gate.sh` 按**真位置**对哈希（此前四机装完**同时**报"校验不过"而文件全对 —— 判据用了交付布局的清单去量在役目录）②新增三条**行为**断言（跑副本，不污染在役日志）：B1 退出码、B2 `explain` 找得到 `role=all` 行、B3 停泊=HELD。**已做变异验证**：对修复前的 guardctl 三条全报 FAIL |
| README.md | 92bc2484729f | **230793d36156** | **B4** §9 接线改指真实位置（`start.sh` 的 `cmd_serve`，约 812 行）——旧版指的 `start_tp4_head_v043.sh`/`start_tp4_worker_v043.sh`/`v41_launch.sh` **已不在生产启动路径上**（✅2026-09-23 订正：原文写"三个都不存在"是**错的**——三个文件一直在 `~/w6-kit/` 留档，2026-09-23 实测 6728 / 3945 / 14748 B；正确口径=离开启动路径、未删除）；§3 表补 `daily-smoke.timer` 与四类注册项计数；§3.1 `kind` 补齐 9 种（旧清单漏的 `proc/envpin/archscr` 恰好承载全部 SGLang 时代前置）；§10 文件表 6→14 项并补 `preflight`；§11"无跑脚本类"更正（`archscr` 就是） |
| scripts/gate.sh（dsv41） | — | **4ec694a5cff8** | 深档三处补 `--key`；`gates_suite.py` **自动落位**到 `state-tp4/`（原先 `/state` 里从来没有这个工件 ⇒ corruption/code/终止性/needle **四档静默跳过**，而 gate 照报"4 项通过"）；落位失败改为**判失败**（"判据跑不起来"不等于"跳过"）；`needle` 判据改"≥2 档 PASS"（470K 档超本栈 `max_model_len=262144`，结构性不适用） |
| start.sh（dsv41） | b12bec823b9b | **982b1295f6cd** | 四机同步（窗口前 02–04 与 01 分叉）；生产模式镜像前置（存在性 + 四机内容身份 + 资产断言 + 禁自动 build） |
| `/opt/aicad-prod/scripts/healthcheck-rebuild.sh`（01） | 停泊桩 `f5ac1d4b4eed` | **ab9a1954ce07**（= 四机一致） | 2026-09-11 窗口的 guardctl HOLD 桩在 01 上**挂了 6 天**，本次 `release` 还原；期间套件把它报成 PASS（B3） |
| guards.conf | 5c2be7e72484 | **23cfacadd870** | 收尾补注：`memfree-raw-vllm` 行加 SGLang 侧说明（同一台机器的统一内存池，“有效空闲”口径会掩盖池缩水；SGLang 起栈前的 `drop_caches` 就是这条前置在人工侧的等价动作）。行名里的 vllm 是历史遗留，判据对两条栈同样成立 |

**本次窗口（2026-09-17）落地的生产变更**：容器改由自足镜像 `dsv41-sglang-optimized:v7` 供码，
`docker inspect` 挂载数 **51 → 3**（只剩 `/engram`、`/models`、`/state` 三个数据挂载）；
`swap.max=0`（旧 head 曾 `swap.max=max` + 2.24 GB 换出）；池 pin 9,600,000（自算 18,712,320 ⇒ 取 51.3%）；
`.cache` 新增仅 9 个文件（镜像预烘缓存盖住了 JIT 补编）；全档质量门 **8/8**；
靴态签名 **758 t/s**（健康靴，非慢靴）。

### 2026-09-17 终态读数（窗口收口后实测）

| 项 | 读数 |
|---|---|
| 镜像 | `dsv41-sglang-optimized:v7`，内容身份 `4ebef21b6aedbd70`（四机相同；`.Id` 因快照驱动不同不可比） |
| 容器挂载 | **3**（`/engram`、`/models/DeepSeek-V4.1-Flash`、`/state`）——生产模式代码只来自镜像 |
| 内存 | head `memory.current` 12 G / `memory.max` 24 GiB；`swap.max=0`；`swap.current=0`；`oom_kill 0` |
| 池 | `DSV4 pool sizes` 两行：自算 `full=19611648` ⇒ 实际 `full=9600000`（pin，51.3%） |
| 质量门 | `scripts/gate.sh --full` ⇒ **8/8 PASSED** |
| 靴态签名 | warmup 中位 **787.4 t/s**（n=8，min 56.1）、capture 7.91 s ⇒ 正常靴 |
| 探针 | 8001 网关 `http=200`，TTFT 0.25 s（带 nonce） |
| 资产 | 定制 NCCL **2.30.7** ring-only 在镜像内（非基座 2.28.3）；b12x 1.3.0 |
| 四机一致性 | `guardctl.sh` `b1d849b47ee4` / `guards.conf` `23cfacadd870` / `verify-governance.sh` `f8bedd1d1ce6` / `README.md` `230793d36156` / `start.sh` `5472c8c1a29c` / `.env.tp4` `fd83036a7b8e` / `gate.sh` `4ec694a5cff8` —— 全部四机同值。（本文件不列自身 md5：写进正文就会立刻失效；上面这几行 md5 才是判定对象） |
| 自检 | 在役布局 **PASS 44/44**；`guardctl.sh check` 四机 **ALL-OK**（01 计 19 项） |
| preflight | **BLOCKED**，未满足项恰为在产期的两条（`pool-free`、`memfree-raw-vllm`）——此为预期，非异常 |

## 2026-09-18：oom_gate 应急层 + systemd 单元化（01 OOM 事故的整改）

| 文件 | md5(12) 旧 | md5(12) 新 | 变更 |
|---|---|---|---|
| oom_gate.sh（~/w6-kit/oom-gate/） | c418d4d948fd | **859639a38dc8** | 新增 **-e 应急线**：有效空闲 < 1 GiB ⇒ 单采样零等待立即 `docker stop -t 15`（-f 的 3×10s 在滑向 host-OOM 的最后 1 GiB 里太慢；2026-09-18 用户令）。退出码 4 区分于 -f 的 3。双极性干跑验证过（-e 50 立即打行仅告警、-e 0 不触发） |
| oom-gate-monitor.service（新） | — | — | systemd 单元（User=liux***ya，ExecStart=-w 6 -f 3 -n 3 --iv 10 -a -e 1，Restart=always）。四机 enabled+active。**根治"裸进程不随整机重启自启"**——2026-09-18 01 OOM 时四机 monitor 全部不在役（与 09-17 07:18 重启后 automon 未自启同款缺口），此后不再依赖手工 setsid |
| guards.conf | 23cfacadd870 | **466757662e8b** | oom-gate-floor 的 proc argv 钉加 `-e 1`；新增 GUARD 行 oom-gate-monitor.service（单元失效在例行 check 现形） |

**守卫参数核实结论（2026-09-18）**：-f 3 **无需下修**——W9 后实测最坏合法负载地板 16×245.7K eff_MIN=6.58，-f 3 仍在包络之下留 3.5+ GiB；-w 6 维持"只记日志"形态。新增 -e 1 为最后断路器。若日后 chunk 8192/6144 落地后实测满载地板 <3 GiB，再议 -f 上下修（届时 -e 1 兜底不至于裸奔）。

**2026-09-18 追记**：`concurrency-proxy-v2.service` 的 md5 钉 0606e1e24926 → **d9aeaab640f7**（DRIFT 裁定=合法改动：
SD-1 会话 00:29 的 rc4 流式转发修复——非流式路径整包驻留改随读随写+背压，修 +156% 劣化；备份
`concurrency_proxy_v2.py.bak-prerel-20260918` 在位可回退；服务 HTTP 200）。guards.conf 最终 md5 见 MD5SUMS。

## 2026-09-19：v8 上线（b12x 上游回补）+ MoE on/off A/B 定谳

| 文件 | 变更 |
|---|---|
| b12x-site intrinsics.py | `24b1049ac800` → `2302dd1ec28b`（02407f65 E4M3 subnormal 原生解码；GPU 256 编码回归全过） |
| b12x-site dense_gemm.py | `e2c5233f6a4b` → `75f774c2ef4d`（ff36d2d1 MXFP8 swizzle 越界读防护） |
| 镜像 | v7（4ebef21b6aedbd70）→ **v8（e3ba5cc812eda003）** 四机同值；自证 76/76；gate 8/8；GSM8K 0.985 |
| guards.conf | sglang-image 钉 v8；记录 MoE A/B 结论 |

**MoE on/off A/B（v8 同镜像两靴，单变量 DSV41_MOE_B12X）**：prefill 32768-c1 **ON +14.9%**（3369 vs 2932 t/s）；decode c1 持平、**c8 ON −10.5%**（204.2 vs 228.1）、c12 ON −3.7%；**ON 启动显存代价 ~5.2 GB**（15.22 vs 20.45 avail）= raw-scale 快照 ~4.5 GB + 梯级 scratch 0.674 GB；op 级 bakeoff b12x 反快 6-12% ⇒ c8 劣势在集成层（a8 残差 scale 逐 step kernel 嫌疑）。GSM8K：ON 0.985 / OFF 0.975。**生产取向=ON**（长上下文 prefill 优先）；OFF=一行 env 的内存释压杠杆；快照双持优化（可回收 ~4.4 GB）列为代码窗口第一候选。

### 2026-09-19 v9 事故与回滚（快照单持优化判缓）

v9（59683cbb633c4aa5，adapter 单持补丁）起栈读数兑现 avail 15.22→19.55 GB 且 gate 8/8，但基准**慢而正确**（c1 2.4 vs 62 t/s、prefill 1892 vs 3369）⇒ 当日回滚 v8 并复验（c12 286 t/s 恢复）。**生产维持 v8**；guards.conf sglang-image 钉保持 v8（部署 v9 时未及改钉，回滚后天然一致）。v9 镜像四机在位但未在役；根因二分计划见 `~/V41-PRDE-SCHEDULING-OPTIONS-20260919.md` 附录（kill-switch `DSV41_MOE_B12X_DUAL_HOLD=1` 使二分只需 env 翻转）。adapter/moe_b12x.py 宿主树仍含单持补丁（md5 28b951e81439）——**下次烘镜像前必须先裁决**（烘前回退备份 `~/v8-window-20260919/` 或加 DUAL_HOLD 默认）。

## 2026-09-19（下午）：v10 上线（单持回收 4.3 GB）+ v9 误判翻案 + 调度默认 S1 + 8192 复测定谳

| 项 | 内容 |
|---|---|
| **v9 事故翻案** | v9「慢而正确」（c1 2.4 t/s）= **R9 档案已知的偶发慢靴（~4%）**，非单持补丁回归。证据：v10（同单持+DIAG）靴 c12=302（历史最佳）、签名 796 t/s OK、DIAG 证明张量物理等价（contig/独占存储/256B 对齐）。**教训入规程：慢靴先重启一次再判（R9 旧规，本窗重犯）** |
| **v10 上线** | 单持（interleave 调用窗恒等化 + 活张量别名）+ DIAG 首层日志。`available_gpu_mem` **15.2→19.45-19.67 GB（+4.3 GB 回收）**；GSM8K 0.97、gate 8/8。镜像身份见 verify 表；kill-switch `DSV41_MOE_B12X_DUAL_HOLD=1` |
| **调度默认 S1** | `--enable-mixed-chunk` 入 EXTRA_SGLANG_ARGS：锤下 ITL p99 **10758→2290ms（−79%）**、p50 +6ms、锤墙钟无损、gate/GSM8K 过。备选 S2 `--prefill-decode-interval 1`：p99 **1875ms**（更优尾）但 c12 267（−7%）。三臂数据：`~/v8-window-20260919/itl-v10-{plain,mixed,pdi1}.txt` |
| **8192 复测（v10）** | 硬门全过（1×245.7K 144.2s≤150；**4×245.7K 482.2s 优于 4096 时代 490s**）；地板 eff 6.98/avail 5.45（安全）；prefill 32K 格 2636 vs 4096 的 2620（**打平**）；decode 同段。**判定=与 4096 基本平局**：W5 风险已消（回收+预算），收益也未兑现（收益带 (4096,8192] 单 chunk 工具提示词档未测）。生产维持 4096，切换功能在位一行可换 |
| guards.conf | sglang-image 钉 v10；新增 sglang-mixed-chunk envpin |

### 2026-09-19（晚）：出货配置落地（用户批准的优选方案）

`.env.tp4` 新 md5 `1c6393d58a08`：**摘除 `--enable-deepseek-v4-fp4-indexer`**（测试侧 A/B 判净亏：长档 −12%+6.4GB）；
其余=4096 + `--enable-mixed-chunk`（PDI=0）+ v10 + b12x ON（预填优先默认；decode 重业务一行切 OFF）。
验证：gate --full 8/8、boot-signature 763 t/s、bench c1 62.2/c8 207.5/c12 285.8、avail 19.51 GB、四机 ALL-OK。
另：boot-signature 以进程替换传 DSV41_LOG 时首个调用会消费 fd（复跑即真值）——工具性假象已记。

**NCCL 跨站对比登记**（测试侧 vs 作者站，纯 prefill 口径）：>16K 档（19 格）本站全面快 12-57% ⇒
站点 NCCL 适配（定制 ring-only 2.30.7 + RING + IB 调参 + PEER_HCA + GID=-1）**无损耗且有优势**；
DE 表「prefill 混测偏慢 5-13%」被推翻=decode 波内排队的口径效应。作者站 16K 档塌陷（~2000，比其 8K 还低 25%）
判其环境波动（单格 122s 墙钟），本站 2900-3050 平滑衔接符合物理预期。≤8K 短档慢 1-52%：短格 1-10s 墙钟对
启动/唤醒开销极敏感 + 2048/4096 的 C2/C4 双站都 serialized（准入律 min(并发,floor(chunk/输入))，策略非 fabric）。

## 2026-09-19（深夜终窗）：v11 上线 + chunk 8192 落地 + 调度限份开关

| 项 | 内容 |
|---|---|
| **v11**（a3caa8a24f0a5c8a 四机） | overlay 42 条：新增 `schedule_policy.py`——**prefill 限份补丁**（L1186 思想，外部报告/#34554 借鉴）：首个分块请求不再独占整 chunk 预算，`DSV41_PREFILL_SHARE_TOKENS`（默认 0=关，零行为变化）设定每请求每步上限；`__init__` 读 env |
| **chunk 8192 落地** | 终比（v11 同日两臂）：硬门全绿（1×245.7K **134.1s**、4× **489.6s**、**新增 8×=1049.0s 全过**；地板 eff_min 6.66/avail_min 5.12）；**工具带格 8192-c1=3295 vs 4096 侧 2632（+25.2%）**；32K 格在历史靴方差带（3124.8 vs 3315.7）；decode c12 297 同段。生产=**v11+8192+mixed-chunk+fp4idx OFF**，gate 8/8+签名 730+探针 200 |
| gate.sh | 探活 `/health`→`/v1/models`（引擎 /health 写死 1s，外部报告借鉴；md5 41f10e902359） |
| 掩码 bound（#40217 思想） | **未落**：两案（非末批空发布/块粒度 publish+consume shim）均需消费方不变量证明（publish 尾行化与 consume 行域交互、候选源层数量），验证步骤已入 `~/V41-EXTERNAL-AUDIT-40217-VERDICT-20260919.md`；本窗不盲上（needle 静默错答案风险） |
| 8001 长档两道闸 | 待办（外部借鉴清单已记：token 估量 体长/2.8+max_tokens≥32768 归长档+独立并发上限） |

## 2026-09-19（终）：慢路径根因定谳与根治（v13）—— R9 慢靴结案

**根因链（日志自白+代码实证）**：FlashInfer autotune 每 rank 独立 tactic 表，digest=文件内容+环境元数据；任一 rank 分歧（head 结构性不落盘自己的表）⇒ `_drop_diverged_autotune_cache` **删全部缓存重抽** ⇒ 每靴重抽 tactic 彩票 ⇒ ~4% 概率抽中慢 tactic ⇒ 全栈慢 10-25×（=R9 慢靴/warmup 55 vs 663 真身；v9 误判事件同源）。
**修复（v13，overlay 43 条）**：`flashinfer_autotune.py` 弃抽改**多数表决采纳**——分歧时少数派 rank 写入多数派（确定性 tie-break：最小 digest）的钉住表，四 rank 加载同一份 tactic，不再重抽；无任何缓存才退回冷启动重签（此时日志显式告警）。实测：`majority-vote adopted the pinned tactic table (digest ebf68191...) -- no re-tune lottery`；warmup 745 t/s、gate 过、bench 在段。
**boot 门**：boot-signature 新增无抽签断言（`tuning from scratch`=FAIL 提示重启再判；`majority-vote adopted`=钉住确认；直读 docker logs 规避进程替换 fd 消费坑）。md5 c6db84a4a48c。
**注意**：缓存键=模型路径/dtype/quant/moe backend/tp/pp/dp/ep/hf 类名/skip_ops——**任一配置变更=新键=首靴冷签**（属预期，重签一次后钉住）；钉住表是"那一次抽到的签"，不保证每区间最优（470K 档验证留给业务）；四份 rank 文件必须各自完整（head 不落盘的奇癖由多数表决兜底）。

## 2026-09-19（终终窗）：并发多路调度终比定稿 + 负载均衡落地

**三臂终比**（33.6K×N 路，v13 同日单变量）：S1(mixed) gap_max=4.9s / S2(PDI=4) gap=0.06s / **S1+S2 组合 gap=0.05s+8 路墙钟最短=胜者**。外部 D 的「S1 源码级否决」被推翻（单独不够但组合最优）。
**生产定稿**：v13+8192+mixed+PDI4+max-queued-32；gate 8/8、4 路 gap=0.06s。
**负载均衡**：8001 QUEUE_TIMEOUT 20→**5s**（drop-in zz 序覆盖，进程 env 确认）；备选 priority-scheduling/SHARE_TOKENS 记录在案未启用。
**交叉审查**（~/crossreview-{gateway,scheduler}-20260919.md）：read(n) 攒批不命中（aiohttp 语义不同）/两档相加不命中/max_prefill 惰性硬顶部分命中（接受）。

## 2026-09-19（收官）：v0.2.3 正式检查点 + 客户坑审计 + V3 矩阵 + git 提交

| 项 | 内容 |
|---|---|
| **镜像定版** | `dsv41-sglang-optimized:0.2.3`（=v14 内容身份同 v13 + 审计修复）：b12x 回补 E4M3+越界 / 单持回收 4.3GB / autotune 多数表决 / prefill 限份 overlay / chunk 8192+mixed+PDI4+max-queued32。gate 8/8、tactic 钉住确认 |
| **导出** | `~/dsv41-sglang-optimized-0.2.3.tar.zst` 14,463,426,869B，zstd -t 通过，md5 `b238c0e368abfddc` |
| **客户坑审计** | 10 项不命中 7 项/需补 5 项全部落地（P1 内核 hold 四机+自愈链决策/P2 PEER_HCA 勘误+内核守卫/P3 NCCL lint+mv -T 规约）。报告=`~/audit-pitfalls-20260919.md` |
| **V3 矩阵** | 8 长度×5=40 格（≤131072）在 v14 上完成 39 格（131072-c16 超时>7200s 属预期）。TABLE=`state/bench-results/prv3-v14-final/` |
| **git** | **7 commits**（`6027504..9d4e311`：不含起点 `6027504`、含末端 `9d4e311`；含两端点共 **8** 个）。2026-09-23 复算更正：原写"9 commits（6027504→9d4e311）"——`git rev-list --count 6027504..9d4e311` = **7**（逐条可列：`a0696e3`/`8774ad1`/`62fba41`/`9975dab`/`a6ca073`/`a94013a`/`9d4e311`；仓库 = `~/dsv41-flash-dgxsparks/`）。conventional 格式含证据数字；gsm8k 路径参数化（脱敏阻断项已修）；RoCE 独立提交；bench-results 入 .gitignore |
| **中间镜像清理** | v1-v12 四机全清（含 v7-pre600k 保留在 01 备用）；在役=0.2.3+v13+v14 |
- chunk8192-handover-20260918.tar.gz md5=9ae5d0410b612c58a65a026e7160bdb4 size=55061B members=19（台账补录 2026-09-19，审计发现原包 md5 零记载）

## 2026-09-19 v0.2.4（=dsv41-sglang-optimized:v18, content-id=e4fe9dc13017e5d7, 125 层）
- ✅ **内容身份裁定（2026-09-23 冻结人）**：原记 `690a2b589eb6d988` 是**孤值**，已更正为 `e4fe9dc13017e5d7`。
  裁定依据（就地实算，2026-09-23；0.2.4 镜像**仍在本机**）：
  ```
  docker image inspect dsv41-sglang-optimized:0.2.4 -f '{{join .RootFS.Layers " "}}' | sha256sum | cut -c1-16
  ⇒ e4fe9dc13017e5d7        # 同口径对 0.2.7 ⇒ b00ea2f8da530bd9、对 0.2.8pre ⇒ 806e0526a8221f7e，均与文档登记吻合
  ```
  四方旁证同记后者：`~/dsv41-flash-dgxsparks/BUILD-IDENTITY.md`（`Previous（历史，被 0.2.7 取代）` 行）、
  `~/dsv41-flash-dgxsparks/README.md`（`Historical release (0.2.4)` 行）、`~/w6-kit/GLOSSARY.md`、
  `r9-ops-20260914/evidence/delivery-20260916/checker-dsv41-sglang-optimized_v18.meta`（`CONTENT_ID=`）。
  ⇒ **引用 0.2.4 内容身份时一律用 `e4fe9dc13017e5d7`**；原 `690a2b589eb6d988` 作废（成因未考，量级上像
  另一次构建/另一记法的残留，无证据不追认）。
- 工具调用截断三保证（vLLM #52645 回移）+ finish() 桩测 13/13
- MoE W4A8 默认（a8）+ MMAX 回退 dual-hold 门控（single-hold 下 FI 布局不兼容=大 M KV 污染，当日判负修复）
- gates_suite needle 唯一前缀（防缓存假 FAIL）
- gate 9/9（needle 30K/229K/470K 全过）
- guards.conf sglang-image pin → 0.2.4（四机同步）

## 2026-09-20 GPU 时钟基线 2200→2400（用户指令，四机同步）
- /etc/systemd/system/gb10-clock-cap.service ExecStart: -lgc 0,2200 → **-lgc 0,2400**；daemon-reload + restart 四机完成
- 生效证据: 四机 journal "gpuClkMin 0, gpuClkMax 2400"；生产负载下 clocks.sm 2366–2379 MHz（2200 时代最高 2190）
- 回滚点: /etc/systemd/system/gb10-clock-cap.service.bak-2200-20260920（四机）
- 治理面同步: `guards.conf` 的 `gb10-clock-cap.service` 行（当时 :97、位移后 :102，见 `guards.conf` 里那张 old→new 位移对照表）、`guard/README.md` 的「四机守卫清单」表 → `gb10-clock-cap.service` 行（当时 :57）+ MD5SUMS 重钉
- 顺带修正: 09-19 排查报告的「锁频失效 P1-2」系 clocks.applications.graphics 字段语义误读（该字段=上限显示 2418=默认），实际 clocks.sm 一直 ≤2200 受控——2200 cap 从未失效

## 2026-09-20 台账更新（批次 7 · H 车道）

| 对象 | 旧 | 新 | 说明 |
|---|---|---|---|
| guardctl.sh | b1d849b47ee4 | **bcbea66ae881** | H1: alert() 增 GUARD_ALERT_HOOK（CRIT 外呼，默认关）；H3: check 增保活内联断言（head: NRestarts>3 FAIL/Result≠success WARN；worker waiter: 只断言 active，>500 WARN——02 实测停泊期累积 120 次属预期）+ precond 增 unitprop kind |
| journal_watch.sh | — | 新增 | H2: journal 游标增量盯防（NV_ERR/oom-kill/watchdog/serve Failed），10min 用户 timer |
| gate_archive.sh | — | 新增 | H2: gate --json 六小时存档 logs/gate-history.jsonl，FAIL 走 alert |
| MD5SUMS | — | 重算 | 剔除 guard-alerts.log（易变文件不应锚定）；纳入两个新脚本 |

## 2026-09-23 luz0.2.8pre（冻结中间版本；content-id=`b177409e539ea38e`，3 层，四机全等）

> 镜像 `dsv41-sglang-optimized:0.2.8pre`，基座 = 生产 pin `0.2.7`（content-id `b00ea2f8da530bd9`，1 层）。
> 层[0]`be60d09edf9d…`（= 0.2.7 层）/ 层[1]`7acd3d5e32530…`（COPY rootfs）/ 层[2]`5f70bf18a0860…`（**空层**）。
> **未晋升生产**：`.env.tp4:106` 与 `guards.conf` 的 envpin 仍同为 `0.2.7`；晋升前置 = 512K 剂量阶梯跑完
> 且瞬态峰值增量 ≤3 GiB（ADR-004 地板守卫未动）。
> ⚠ 首版登记值 `806e0526a8221f7e` 已作废（晚修补掉两处构建侧缺陷后重建），权威值 = `b177409e539ea38e`。

| 对象 | 旧 | 新 | 说明 |
|---|---|---|---|
| refresh-md5sums.sh | — | **新增** | `guard/MD5SUMS` 的唯一生成器/检查器：排除表带理由（`MD5SUMS`/`*.bak-*`/`*.log`）、扩展名白名单、未分类件写时报错、写后立即回读、`--check`/`--selftest`（7 断言，含"追加日志不得使清单失效"）。起因：手打清单把 `*.log` 扫进去 ⇒ **清单自我失效**（自己变红 ⇒ 人们学会无视它） |
| guard/MD5SUMS | 16 项（含 log） | **17 项** | 由生成器重出；剔 log |
| refcheck.py / refcheck.allow | — | **新增** | 文档引用核验量具：查路径/行号/章节锚点/md5/STALE 五类 + 目录 + 弱悬空；`--review` 打印文档与目标两行；`refcheck:historical-md5`（`:file` 与表级）声明让台账不被按现值判；`--selftest` 断言六类全抓 + 干净夹具 0 假阳 + 夹具必须是真文件（防空真）。真产物终态 **1690 引用 / FAIL 0 / WARN 1**（WARN = 镜像内路径 `/opt/libncclpin.so`，已在 allow 具名） |
| 文档锚点 | 行号（`guards.conf:97`） | **行名锚点**（`gb10-clock-cap` 行） | 39 处 STALE 引用按 `guards.conf` 的 old→new 位移表改为可 grep 复核的行名锚点；**行号漂移是一类病**，不是个别笔误 |
| instruments/（4 件） | — | **新增入载荷** | `v41_launch.sh` / `v41_post_boot_check.sh` / `v41_window_hold.sh` / `v41_window_rollback.sh`（此前只在宿主，镜像内点名却缺件） |
| 载荷清单 | — | **46 项** | KIT_LIST 双向断言①（`guard/MD5SUMS` ↔ KIT_LIST，`LC_ALL=C comm`，排除 `MD5SUMS` 自引用）+ 断言②（文档点名的根目录量具必须"烘进去"或"具名排除"） |
| 可复现构建 | 归一化 mtime（反噬） | **一次性 context 目录 + 零写入 AST 语法门** | 首版把 mtime 全压成常量 ⇒ 与**同尺寸**内容改动组合后骗过 BuildKit 的 (mtime,size) 过期检测 ⇒ **静默装进旧字节**（被构建自带 6/6 逐文件校验拦下，未分发）。RUN 由 `py_compile`（写 `__pycache__`）改为 `ast.parse` 只读 ⇒ 层[2] 为空层。**验法**：`NOCACHE=1 FORCE=1` **同名**重构建比内容身份（`~/v41-028-build-20260923/build-repro-sametag.log`）——⚠ 换标签重建**必不同**（tag 被写进镜像内自述），拿 `.Id` 比也会"必不同"（config 含构建墙钟） |

**排除项（写进镜像自述，防"看起来缺件"）**：`instruments/daily_smoke.py`（第 19 行硬编码探测密钥兜底值 ⇒
密钥绝不进镜像）、`sglang-overlay/configurer.py`（#39482 回退臂，回退条件未成立 ⇒ 保留 0.2.7 原版）、
`*.bak-* / 日志 / state/ / __pycache__`。

**归档**：`w6-archive-repo/current/w6-kit/luz0.2.8pre-kit/`（48 件，MANIFEST **46 项 46/46**；
其 md5 `bbdb6a70059643252a678df8272de214` **== 镜像 LABEL `org.dsv41.kit_manifest_md5`** ⇒ 归档 == 镜像的互证）。
归档源**直接自冻结镜像抽出**（`docker create` + `docker cp`，不启动容器），不是从源树二次拷贝。

**磁盘**：清理旧测试构建镜像 —— 03 `128G→189G` 可用、04 `130G→171G`（删除对象见 `docs/ARCHIVE-INDEX.md`
本轮记录；01/02 空间充裕，保留全部历史标签作为归档面）。

**本轮遗留（已登记，未闭合）**：`guards.conf:141` 引注需同步到新的 §5.3 标题；`guard/README.md:83` 省略号式引用；
`WINDOW-RUNBOOK` 的"3/4 票"描述的是新表决机制而生产仍在旧机制；kit T3 ≥3 靴复测；
`vllm_logdump.sh` 双副本分叉；`guardctl.sh watch` 的裸进程缺口。

**⚠ 冻结后宿主 kit 的前移（设计内，勿判为漂移）**：镜像 `b177409e539ea38e` 内的 kit = 本节的
`bc7462f` 时状态。冻结**之后**宿主 `~/w6-kit/` 又动了四件，属台账纪律的必然结果：
(a) 本 `BASELINE.md` 追加本节；(b) `MD5SUMS` 随 (a)+(c)+(d) 由生成器重出（17 项，回读 17/17）；
(c) `GLOSSARY.md` 把 10 处**指向 `BUILD-IDENTITY.md` 的行号引用**改为行名/节名锚点
（同日 `BUILD-IDENTITY.md` 因身份重钉增行 ⇒ 行号位移暴露了这批引用的既有隐患）；
(d) `REFERENCE.md` + `GLOSSARY.md` 再把 6 处**指向 `deepseek_v4_backend.py` 的行号引用**
改为可 grep 证的行名锚点（`# DSV41 #40217 native port` / `# Port of upstream PR #39187` /
`#56457` / `DSV41_MASK_B_EMPTY_NONFINAL` / `window A1 (2026-09-22) proved it never` /
`A-1 (2026-09-22)`），起因是 #40352 回移编辑使该文件行号位移 ⇒ refcheck 由基线
`FAIL 0/WARN 1` 一度退化为 `WARN 7`，转锚点后回到基线。
⇒ **镜像内 kit 与被抽出归档（`luz0.2.8pre-kit/`）仍是冻结态**；宿主 kit 是活文档，
下次构建自然纳入。要判定"镜像 vs 宿主"差异，看这四件即可，其余 44 件应逐字节相同。

**⚠ 宿主 overlay 前移于 `0.2.8pre`（2026-09-23，设计内，勿判为漂移）**：#40352 语义级回移
（提交 `ee907b5` + `aebc6a3`）使 `sglang-overlay.ctx600k-probe/` 相对该镜像**多 3 件**
（`candidate_indexer.py` / `dense_prefill_indexer.py` / `mqa_logits_utils.py`）、并改了
`deepseek_v4_backend.py` 与 `indexer.py`；`start.sh` 映射表 **49 → 52 条**
（`map_md5=58db45c37269bf12`，`overlay_files="52"`）。**对生产零影响**：新模块在 backend 里
是**惰性导入**（模块级 import 面不含 `candidate_indexer`，机械验证 0 次），尾部切行走鸭子类型，
故 `DSV41_IDX_PROTOCOL=0`（默认）与冻结时逐字同行为。**本轮有意不重烘**：`0.2.8pre` 的身份已登记
且已四机分发，构建脚本自身即警告勿静默覆盖 ⇒ 下次构建取**新标签**。详见
`~/V41-40352-BACKPORT-AND-FREEZE-PLAN-20260923.md` §七（执行回执）。

**⚠⚠ 2026-09-23 窗口后追加（两条，读上面那条前先读这条）**

1. **`sglang-overlay.ctx600k-probe/deepseek_v4_backend.py` 已在窗口内再改一次**（md5 `c12dca7dd07aaf` → **`610eb75c6f12d9ac`**，
   四机同步）：p1 臂首启 `UnboundLocalError: _mask_w`（协议分支自带账本、旧 bool 账本 74 行留在
   `if/else` 之外）⇒ 这 74 行整体移入 `else:`；顺带修掉该块**谎报宽度**（日志打 `w_bucket` 而实际
   分配宽度是 `_mask_w`）。**对 `DSV41_IDX_PROTOCOL=0` 仍是行为惰等**（同序同句，仅缩进 + 日志文本），
   已在 p0 二轮实测复现一轮基线（32K 2.94/2.96 vs 一轮 2.75，靴间 ~0.2 G）。
   ⇒ **注意**：上面"逐字同行为"的措辞针对**冻结时**成立；对当前宿主树应读作"行为等价、文本不同"。
2. **`DSV41_IDX_PROTOCOL` 默认仍为 0（未翻）** —— 依据用户验收判据「瞬态增量 ≤3 G」：
   512K 单流实测三靴为 01(head) 3.10–3.29 / 02 2.88–3.03 / 03–04 2.63–2.79 G，
   **两安静 worker 达标、head 与 02 超线**；超线与协议无关（p0 在 32K 即已 2.94 G，残差**恒定不随 lc 增长**）。
   协议本身在每一档都严格更优（32K −0.19、128K −1.33 G，256K 把"守卫止停+引擎死亡"变成干净通过）。
   完整表格与论证见 `V41-40352-BACKPORT-AND-FREEZE-PLAN-20260923.md` §8.5/§8.8，
   以及本窗口的独立对照报告 `V41-40352-AB-COMPARISON-REPORT-20260923.md`。
   **下一步是"是否翻默认"的决策项，不是已决项。**
