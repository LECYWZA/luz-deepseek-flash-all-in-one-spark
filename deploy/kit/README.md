# w6-kit —— 四机运维工具箱（DGX Spark GB10 × 4 / DeepSeek-V4.1-Flash TP4）

> 位置：**四机各自的** `~/w6-kit/`（dgxspark01..04）
> 规模：**281 个顶层文件 / 44 个顶层目录 / 1.8 GB**（2026-09-23 统计；本索引与
> `WINDOW-RUNBOOK.md` 即当日新增，故**实测已变为 283 文件 / 45 目录**——含新建的 `adr/`）
> 版本：本索引 2026-09-23 首版
> 烘入镜像落点：`/opt/dsv41/kit/`

---

## 0. 这个目录是什么

`w6-kit` 是**集群的运维工具与守卫目录**，不是应用仓库。它承载三类东西：

1. **守卫与止损**（`guard/`、`oom-gate/`）—— 唯一真正"在役且有单元保证"的部分；
2. **窗口量具**（`v41_*`）—— 开维护窗口时用来量内存瞬态、跑剂量阶梯、做 A/B 的仪器；
3. **发布/交付件与历史归档** —— 镜像 Dockerfile、wheels、vendored 源码树、历次窗口报告。

### 0.1 什么**不该**放在这里（重要）

| 不该放 | 应该放哪 | 为什么 |
|---|---|---|
| 生产配置文件与密钥（`.env.tp4` 及其变体） | `~/dsv41-flash-dgxsparks/` | 生产仓是唯一事实来源；`w6-kit` 里出现第二份 ⇒ **分叉**（本目录已有实证，见 §4） |
| 容器内代码 / overlay | `~/dsv41-flash-dgxsparks/sglang-overlay.*` | overlay 是**逐文件 bind-mount**，改动必须四机同步并做形态断言（`v41_win_mmprobe.sh:31-64` ③/③b 步） |
| 权重、checkpoint、镜像 tar | `/data/models/…`、registry | 权重**只读**挂载；未经完整 sha256 校验的权重目录禁止挂载（`guards.conf:63` 红线） |
| 新的 vendored 源码树 | 别拷 | 1.8 GB 里绝大多数就是历史源码树；再拷一份只增加"同名副本分叉"的概率 |
| 跨机同步用的"共享副本" | 别做 | 四机各有各的 `~/w6-kit/`，**同名副本分叉是真实发生过的失效**（§4、`…/DELIVERABLE-CHECKLIST-20260916.md` §2「多机时逐机跑一遍并比对输出（同名副本分叉是真实发生过的失效）」。2026-09-23 更正引用：原引作 `…/OUT-OF-BOX-DEPLOY.md` 的 7.1 子节，而该文档**只有 7 一节、无 7.1、也无此句**（实测该句在交付清单第 2 节第 8 条，即上面点名的那份）） |
| 一次性研究脚本（跑完就完） | 跑完即归档进 `.archive-*` | 否则一年后没人分得清哪些在服役（本索引 §3 就是为这件事写的） |

### 0.2 与生产仓 `~/dsv41-flash-dgxsparks/` 的关系

```
~/dsv41-flash-dgxsparks/     ← 生产仓：start.sh / stop.sh / .env.tp4 / boot.py / gate.sh /
                                sglang-overlay.* / scripts/ / state/  ← 唯一事实来源
~/w6-kit/                    ← 运维工具箱：守卫、量具、发布件、历史
      │
      ├─ guard/     ←─ 观测并开关生产守卫（guardctl preflight 会读生产仓的 .env.tp4 旋钮）
      ├─ oom-gate/  ←─ 止损：docker stop 生产容器（生产仓的 start.sh 是它保住的对象）
      └─ v41_*      ←─ 量具：在窗口里量生产栈的内存瞬态
```

三条硬边界（`guard/README.md` §11「明确不做」）：

1. `w6-kit` 的工具**不修改** `/etc/systemd/system/` 下的单元文件（需 root，属生产变更）；
2. `w6-kit` 的工具**不 `docker rm -f` / `docker stop` 生产容器**——**唯一例外是 `oom-gate`**
   （它的职责就是止损，见 `oom-gate/README.md`）；
3. `guardctl check` 里**不做任何写操作**、不自动"修复"守卫（只给修复命令，由人执行）。

---

## 1. 一级分类表

### 1.1 守卫治理 —— **在役**

| 路径 | 作用（一句话） | 在役/历史 | systemd 常驻 | 宿主/容器 | 文档指针 |
|---|---|---|---|---|---|
| `guard/` | 守卫注册表 + 统一管理器（`guardctl` status/check/**preflight**/explain/doctor/hold/release/watch/snapshot） | **在役** | 否（`guard-check.timer` 15 min 跑 `check`，user 域） | 宿主 | `guard/README.md` |
| `guard/guards.conf` | **注册表唯一事实来源**：`GUARD` **6** 条（2026-09-23 新增 `nvmodule-guard`，见 §4 G5）/ `PRECOND` 19 条 / `RECOVERY` 2 条 / `TIMER` 1 条 / `RETIRED` 4 条 | **在役** | — | 宿主 | `guard/README.md` §3 |
| `guard/guardctl.sh` | 唯一入口（80 987 B） | **在役** | — | 宿主 | `guard/README.md` §2 |
| `guard/BASELINE.md` | `snapshot` 生成的状态基线（下半部是历次修订表，**别拿 `snapshot` 刷**） | **在役** | — | 宿主 | `guards.conf:89`（`engine-pin` 前置） |
| `guard/clock-sm-guard.sh` | SM 时钟**实际值**体检（带 `[2250,2400]`，引擎停泊时 `SKIP` 退出码 2） | **在役** | 被 `archscr` 前置调用 | 宿主 | `WINDOW-RUNBOOK.md` §7.3 |
| `guard/flashinfer-arch-guard.sh` | SM121 上 flashinfer AOT 取件的 arch 体检（跑一次 ~秒级） | **在役** | 被 `archscr` 前置调用 | 宿主 | `guards.conf:146` |
| `guard/gate_archive.sh` | gate 快档节拍化 + 存档（`logs/gate-history.jsonl`），FAIL 走告警链 | **在役** | 是（`gate-archive.timer` 每 6 h，user 域） | 宿主 | 脚本头注释 |
| `guard/journal_watch.sh` | journal/kernel 增量守望（NV_ERR / OOM-kill / watchdog / 保活失败行） | **在役** | 是（`guard-journal-watch.timer` 每 10 min，user 域） | 宿主 | 脚本头注释 |
| `guard/wedge-watch.sh` | **跨机楔死探测**（ping 通 + TCP 可连 + 无 banner = 宿主用户态冻结） | **在役** | 是（`guard-wedge-watch.timer` 每 5 min，user 域） | 宿主（跨机 ssh） | 脚本头注释 |
| `guard/gen_probe.sh` | 补偿探针：抓「`/v1/models` 200 但生成坏」（引擎停泊时静默） | **在役** | 是（`gen-probe.timer` 每 30 min，user 域） | 宿主 | 脚本头注释 |
| `guard/guard-onstart.sh` | 启动路径钩子，**永远 `exit 0`**，绝不阻塞启动 | **在役**（接线在 `start.sh` 的 `cmd_serve()`） | 否 | 宿主 | `guard/README.md` §9 |
| `guard/overlay-drift-check.sh` | 容器视角 ↔ 盘上 overlay ↔ 镜像 三者是否同一份字节（形态感知） | 在役（手动） | 否 | 宿主 | `guard/README.md` §10 |
| `guard/jit-header-refresh.sh` + `jit_refresh_exec.py` | JIT 头文件依赖的**预发布**（只发布、绝不删除） | 在役（手动） | 否 | 宿主（驱动容器） | `guard/README.md` §10 |
| `guard/verify-governance.sh` | 装完/改动后自检：齐备性 + 语法 + **能力断言** + B1/B2/B3 行为断言 | 在役（手动） | 否 | 宿主 | `guard/README.md` §10、`guard/BASELINE.md` |
| `guard/probe_deps_closure.py` | 复算依赖闭包（独立验证"自失效"结论） | 在役（手动） | 否 | 宿主 | `guard/README.md` §10 |
| `guard/state/` | `journal-watch.cursor`、`journal-watch.log`（timer 自审计：有没有真跑） | **在役** | — | 宿主 | — |
| `guard/guard-alerts.log` | **告警总账**（`guardctl` / `oom-gate` / `journal_watch` / `gen_probe` / `gate_archive` / `daily_smoke` 共用同一格式、同一采集面） | **在役** | — | 宿主 | `guard/README.md` §8 |

### 1.2 OOM 止损 —— **在役（唯一会 `docker stop` 的守卫）**

| 路径 | 作用 | 在役/历史 | systemd 常驻 | 宿主/容器 | 文档指针 |
|---|---|---|---|---|---|
| `oom-gate/` | 内存地板守卫：`pre` 冷启动准入 / `monitor` 常驻止损 / `baseline`+`post` 窗口对账 / `snapshot` 现场 | **在役** | 是（`oom-gate-monitor.service`，system 域，`Restart=always`） | 宿主 | **`oom-gate/README.md`** |
| `oom-gate/oom_gate.sh` | 主脚本（297 行）；判据 `eff_idle = MemFree+Cached+SReclaimable−Shmem` | **在役** | — | 宿主 | `adr/ADR-004-three-gib-floor-guard.md` |
| `oom-gate/selftest_snapshot.sh` | 判别式自检：T1 顺序 / T1-对照 / T2 不阻断 / T3 不误伤 / T5 cgroup 全 id | **在役**（手动） | 否 | 宿主（假 docker 夹具） | `oom-gate/README.md` §8 |
| `oom-gate/oom-gate-monitor.service` | 单元模板（`ExecStart` 与 `guards.conf:117` 同源） | **在役** | — | 宿主 | `oom-gate/README.md` §9 |
| `oom-gate/oom_gate.sh.pre-e-tier-20260918` | 历史副本：**加 `-e` 应急线之前**的版本（152 行，`ADR-004` 引用在 `:133`） | 历史 | 否 | 宿主 | `adr/ADR-004…` §9 |
| `oom-gate/logs/` | `oom-gate-monitor-<host>.log`（**只在越线时落行**）、`site/`（现场快照根，**当前不存在**）、`warm-cache-<host>.log` | **在役** | — | 宿主 | `oom-gate/README.md` §7/§10.2 |

### 1.3 窗口量具 `v41_*` —— **在役（手动，窗口内用）**

| 路径 | 作用 | 在役/历史 | systemd 常驻 | 宿主/容器 | 文档指针 |
|---|---|---|---|---|---|
| `v41_memwatch.sh` | 四机内存瞬态**高频量具**（250 ms/发，与 oom_gate 逐字节同款公式） | **在役** | 否（窗口内 `setsid` 起停） | 宿主（跨机 ssh） | 脚本头注释；`adr/ADR-004-three-gib-floor-guard.md` §6.3 |
| `v41_memwatch_report.py` | 把采样算成 `dip/persist/transient` + **G1/G2 两闸判决** | **在役** | 否 | 宿主 | 脚本 docstring |
| `v41_dose_ladder.sh` | 单流长上下文**剂量阶梯**（硬闸 G1 地板 / 主闸 G2 瞬态）；**撤 NVRM 判决**后的 v2 | **在役** | 否 | 宿主驱动 + 容器内 PRv3 采集器 | 脚本头注释；`adr/ADR-004-three-gib-floor-guard.md` §3.2 |
| `v41_win_mmprobe.sh` | **现役窗口剧本**（① 四机 drop_caches → ⑧ 收栈留停泊态，含形态断言/金丝雀/日志断言/剂量） | **在役** | 否 | 宿主驱动 | 脚本头注释（可作 `WINDOW-RUNBOOK.md` 的可执行样例） |
| `v41_devfree_host.sh` | **设备可见空闲**的宿主侧零容器量具（libcuda `cuMemGetInfo`）；附 `dev_free ≡ MemFree` 恒等断言 | **在役** | 否 | 宿主（**不起容器、不装 torch**） | 脚本头注释 |
| `v41_hostattr.sh` | 宿主侧归因采样器 v1（docker scope / user.slice / dsv41 逐 cgroup + slab + 磁盘） | **在役**（有 v2 可选） | 否 | 宿主 | 脚本头注释 |
| `v41_hostattr.v2.sh` | v1 的三个缺口修复：加 swap/pswp 口径、**未命中落 `-1` 哨兵**（不再"沉默即 0"）、`#FIELDS` 自描述 | **在役（但当前无调用者，见 §4）** | 否 | 宿主 | 脚本头注释 |
| `v41_warm_cache.sh` | 主动预热页缓存（预算硬上限 24 GiB / `MemFree` 地板 20 GiB / 空闲 I/O）；**实测打印 Δeff_idle 证伪**"预热不伤判据" | **在役** | 否 | 宿主 | 脚本头注释 |
| `v41_kfix_ab.sh` | K gather 修复的**同靴单变量**端到端 A/B（old/new 差一个文件） | **在役** | 否 | 宿主驱动 | 脚本头注释 |
| `wait_kfix_ab.sh` | A/B 第二腿的等待者（**专为"等待者自身 argv 不许出现目标脚本名"而单独立项**） | 在役（辅助） | 否 | 宿主 | 脚本头注释 |
| `v41-kv-V-TRACK.md` | V 轨协议（KV 扩容 + GMU 阶梯）操作件 | 历史文档（2026-09-13） | — | — | 文件头 |
| `v41_window_hold.sh` / `v41_window_rollback.sh` | 窗口停泊/回滚原语（**vLLM 时代**：`REX-HOLD` 换 ExecStart 目标 + kill MainPID） | 历史（**仅作参照**） | 否 | 宿主 | `WINDOW-RUNBOOK.md` §5.4 |
| `v41_launch.sh` | V4.1 首启 smoke / 切换（**刻意不是生产启动器**：不同容器名/端口 8012/独立缓存卷） | 历史（vLLM 时代） | 否 | 宿主 | 脚本头注释 |
| `v41_post_boot_check.sh` | 起栈后只读体检（核心断言 = Engram 表必须是 **mapped** 而非 allocated） | 历史（vLLM 时代） | 否 | 宿主 | 脚本头注释 |

### 1.4 生产启动 / 监视链

> ⚠️ **时代分界（务必先读）**：生产已于 **2026-09-14** 从 vLLM 切到 **SGLang**。
> 本节绝大多数条目是 **vLLM 时代遗留**，`guards.conf:23-29` 与 `:39` 已把它们标为
> `#RETIRED-20260916`。**在役的生产启动链是 `~/dsv41-flash-dgxsparks/` 的
> `start.sh` + `dsv41-serve.service`，不是这里的任何一个。**

| 路径 | 作用 | 在役/历史 | systemd 常驻 | 宿主/容器 | 文档指针 |
|---|---|---|---|---|---|
| `monitor_tp4_head_v043.sh` | **当前是停泊桩**（`guardctl HOLD(simple 安全桩)`，驻留不退出） | **停泊中** | 曾是 `vllm-tp4-head.service` 的 ExecStart（该单元 `disabled`） | 宿主 | `guard/README.md` §4 |
| `monitor_tp4_worker_v043.sh` | worker 自愈监视器：head TCPStore 门禁 + 本 rank 缺失触发 head 全链重建 | 历史（vLLM 时代） | 同上（`vllm-tp4-worker.service`，`disabled`） | 宿主 | 脚本头注释 |
| `start_tp4_head_v043.sh` / `start_tp4_worker_v043.sh` | vLLM 时代生产启动器（`v044-r1`） | 历史 | 由上面两个 monitor 单元调用 | 宿主 | 脚本头注释 |
| `start_tp4_head_bench_luz031.sh` | 采分用 head 启动器 | 历史 | 否 | 宿主 | — |
| `w9r4_window_restart.sh` | **W9-R4 全链受控重启原语**（head→workers + 等 `/health=200`） | 历史（vLLM 时代） | 否 | 宿主 | 脚本头注释 |
| `w9r4_restart_guard.sh` | 重启前置守卫 | 历史 | 否 | 宿主 | — |
| `_startup_log_capture.sh` | 早期启动日志采集（`nohup` 起，随 ssh SIGHUP 被杀 → 已被 `vllm_logdump.sh` 取代） | 历史 | 否 | 宿主 | `vllm_logdump.sh:7-11` |
| `daily_smoke.py` | **日级真实性 smoke**：双端点分层（L1 引擎 8899 / L2 代理 8001），失败写 `guard-alerts.log` | **在役** | 是（`daily-smoke.timer` 每日 09:30，**system 域**，`/etc/systemd/system/`） | 宿主 | 脚本 docstring；`guards.conf:111` |
| `vllm_logdump.sh`（本目录副本） | 崩溃取证日志转储 daemon（容器被删后日志仍在） | **本副本 = 历史**（权威副本在 `/opt/aicad-prod/scripts/`，见 §4） | 单元 `vllm-logdump.service` 在役（system 域） | 宿主 | `guards.conf:30`、`oom-gate/README.md` |
| `FABRIC-GID-REPAIR-RUNBOOK.md` | 断电后 RoCE GID 洞修复（§1 审计 / §2 环回修复 / **§7 PD 安全模式时钟楔死**） | **在役** | — | — | 本文件自身 |
| `powercycle_check.sh` | **断电/冷断电后四机一键复核**（60 秒扫描：GID 洞 / 时钟楔死 / 停泊容器被拉回 / 内核候选漂移） | **在役** | 否（手动，栈须停着跑） | 宿主（跨机 ssh） | 脚本头注释 |
| `s4_bench.sh` | NCCL allreduce 四机 bench（`timed` / `verify` 两轮） | 在役（fabric 验证用） | 否 | 宿主 | 脚本头注释 |

### 1.5 发布 / 交付件（**全部历史，留档用**）

> 一句话：这些是"当时那一版镜像/那一版补丁"的**可复现输入**。
> **不要再往里加新的** —— 新的构建产物请进 registry / `docker save` 的 tar。
> **不要 `docker commit` 在役容器**存镜像：overlay 是逐文件 bind-mount，commit 只快照可写层 ⇒ overlay 全丢
> （`…/OUT-OF-BOX-DEPLOY.md` §7「常见坑」第 1 条。2026-09-23 更正引用：原引作 7.1 子节，该文档只有 7 一节、无子节）。

| 路径 | 内容 | 大小 | 备注 |
|---|---|---|---|
| `Dockerfile.LuZ-*`（11 个） | 历次镜像构建输入（`0.4.4` → `0.4.5-VL`，G1/G1r3..G1r6/routea/toolfix1/UP28） | ~30 KB | 2026-08-29 → 09-02 |
| `Dockerfile`（无，本目录不计） | 生产 Dockerfile 在 `~/dsv41-flash-dgxsparks/Dockerfile` | — | — |
| `ringonly-v5/` | 定制 **RING-only NCCL 2.30.7** + 核绑定 shim 的源码树与产物 | **631 MB**（本目录最大） | 两个库**已烘进镜像**（`/opt/nccl-ringonly`、`/opt/libncclpin.so`） |
| `s4_build/` | `s4_bench.sh` 用的 `all_reduce_perf` 等产物 | 258 MB | — |
| `s4/`、`s4_evidence/`、`s4_hostfile`、`s4_verify_*.log`、`s4_result_*.csv` | S4 窗口的证据与读数 | ~10 MB | — |
| `fi-src/`、`fi016-src/`、`fi-main/` | flashinfer 源码树（多版本并列） | 220 / 120 / 82 MB | 同名副本分叉的高风险区 |
| `fi-wheels/`、`fi18-wheels/`、`fi18-jitcache-wheel/` | flashinfer wheels | 15 / 25 MB | — |
| `cutlass462-wheels/`、`cutlass463-wheels/` | CUTLASS wheels（462 / 463） | 各 170 MB | — |
| `w6-kit_flashinfer-main.tar.gz` | flashinfer main 快照 | 13 MB | 文件头注释记录过它的用途 |
| `fa4-4.0.0b3-py3-none-any.whl` | flash-attn wheel | 256 KB | — |
| `libncclpin.so` | 核绑定 shim（**交付件**，镜像内另有一份） | 70 KB | `start.sh` 生产模式**不再挂载**它（已烘进镜像） |
| `patches/`、`patches028/`、`patches-w4a4/`、`nvfp4-plugin-a1/` | 历次补丁集 | 36 K / 8.7 M / 76 K / 96 K | — |
| `l3fix/` + `l3fix_*.sh` | L3 修复的调查产物与脚本 | 12 MB | 历史 |
| `g1r3-build/` … `g1r7-build/`、`toolfix1-build/`、`g1r3-d/`、`g1r3-e/`、`g1r6-ctx/`、`toolfix1-ctx/` | G1r3–G1r7 各轮构建/上下文目录 | 合计 ~20 MB | 历史 |
| `reference/` | 参考件 | 2.4 MB | — |
| `g4-20260910/`、`s0-dspark-diff-20260910/`、`s1-image-20260910/`、`s1-patch-20260910/`、`v3-variants/`、`a-item-preshard/` | 2026-09-10 前后的调查包 | ~3.6 MB | 历史 |
| `bench3/`、`bench3-results/`、`w8-evidence/`、`w9-evidence/` | 基准与窗口证据 | ~2 MB | 历史 |
| `S1-G4-tokenids-*.jsonl`（3 个） | G4 token id 对照数据 | 各 ~330 KB | 历史 |
| `concurrency_proxy_v2.py.bak-rc3.3-20260907` | 业务入口代理的历史副本 | 26 KB | 生产件在别处 |
| `flashinfer_sparse_l3_002.py` | L3 sparse 调查件 | 39 KB | 历史 |

### 1.6 历史归档

| 路径 / 模式 | 内容 | 备注 |
|---|---|---|
| `.archive-scripts-20260910/` | 2026-09-10 批量归档的脚本副本（`start_tp4_*.sh` 的几十个 `.bak-*` 变体） | 每个文件还有一个 `.bak-decred-20260911` 孪生副本（09-11 的一次批量改权限/改名动作留下） |
| `.archive-20260916/` | `dead-files-dgxspark01.tar.gz`（860 B） | 2026-09-16 清理 |
| `G1R7VL-*.md`（14 个） | G1R7 **VL** 线的窗口报告/调查/交付文档（2026-09-02 → 09-08） | ★**唯一一处"项目级结论"的载体**；`G1R7VL-BASELINE-DELIVERY-20260908.md` 是部署/回退/验收门 |
| `*.bak-*` / `*.orig-*` / `*.a6-fail` | 就地备份（命名约定不一致，见 §4） | 约 40 个 |
| 若干 `.log` / `.csv` / `.txt` | 一次性读数（`bat8192-restart-20260909.log`、`w8_s4_*.csv`…） | 历史 |

---

## 2. 在役清单（2026-09-23 01:0x UTC 取证）

**取证命令（全部只读）**：

```bash
systemctl --user list-timers --all
systemctl list-timers --all
pgrep -af 'guardctl|oom_gate|logdump'
systemctl list-unit-files | grep -E 'vllm|dsv41|oom-gate|gb10|daily-smoke|concurrency|guard|nvmodule'
```

### 2.1 systemd **user** 域（`~/.config/systemd/user/`）

| 单元 | 节拍 | 谁在什么时候跑它 | 作用 |
|---|---|---|---|
| `guard-check.timer` → `.service` | `OnBootSec=3min` + `OnUnitActiveSec=15min` | 开机后 / 每 15 min | `guardctl.sh check`（**替代空缺的常驻 `watch`，无裸进程**） |
| `guard-wedge-watch.timer` → `.service` | `OnBootSec=3min` + `OnUnitActiveSec=5min` | 开机后 / 每 5 min | `wedge-watch.sh sweep dgxspark01..04` 跨机楔死探测 |
| `guard-journal-watch.timer` → `.service` | `OnBootSec=5min` + `OnUnitActiveSec=10min` | 开机后 / 每 10 min | `journal_watch.sh` journal/kernel 增量守望 |
| `gen-probe.timer` → `.service` | `OnBootSec=10min` + `OnUnitActiveSec=30min` | 开机后 / 每 30 min | `gen_probe.sh` 生成能力补偿探针 |
| `gate-archive.timer` → `.service` | `OnBootSec=10min` + `OnUnitActiveSec=6h` | 开机后 / 每 6 h | `gate_archive.sh` gate 快档节拍 + 存档；**采分窗期间应 `stop` 本 timer** |
| `dsv41-serve.service` | `Restart=always`（30 s） | **停机中**：`disabled` + `inactive (dead)` | 生产 head 的 launcher-waiter；**恢复生产 = `enable --now`（§见 `WINDOW-RUNBOOK.md` §5.2）** |

### 2.2 systemd **system** 域（`/etc/systemd/system/`）

| 单元 | 状态（实测） | 谁在什么时候跑它 | 作用 |
|---|---|---|---|
| `oom-gate-monitor.service` | `enabled` / **`active (running)`**，MainPID 846274（2026-09-23 实测，随重启变） | 开机自启；`Restart=always`（10 s） | **内存地板守卫**：`monitor -w 6 -f 1.5 -n 3 --iv 10 -a -e 1` |
| `vllm-logdump.service` | `enabled` / **`active (running)`**，PID 30282 | 开机自启；`Restart=always`（3 s） | 崩溃取证日志转储，`ExecStart=/opt/aicad-prod/scripts/vllm_logdump.sh`（**不是本目录那份**） |
| `concurrency-proxy-v2.service` | `enabled` / **`active (running)`**，PID 30280 正监听 `0.0.0.0:8001` | 开机自启 | 业务入口（SSE 心跳 / TTFT 预算 / 准入背压）；**仅 head 部署** |
| `gb10-clock-cap.service` | `enabled` / **`active (exited)`** | 开机一次（`oneshot` + `RemainAfterExit=yes`） | `nvidia-smi -lgc 0,2400` |
| `daily-smoke.timer` → `.service` | `enabled` / active；`OnCalendar=*-*-* 09:30:00`（`RandomizedDelaySec=300`） | **每日 09:30**（head 独有） | `daily_smoke.py` 日级真实性 smoke |
| `nvmodule-guard.service` | `enabled` / **`active (exited)`** | 开机一次（`oneshot` + `RemainAfterExit=yes`） | NVIDIA 内核模块 flavor 守卫（open 模块在 GB10 上已知致命）。**已登记**（2026-09-23：`guards.conf` 的 `nvmodule-guard` 行 = 当日在位 `:133`，`md5 钉版 989c04d86368`；已进 `guard/README.md` §3 表。原记「不在 `guards.conf` 里」已作废，见 §4 G5）。⚠ 判据**缺 `580.` 版本断言**（同 `guards.conf` 该行的已知缺口） |
| `vllm-healthcheck.service` / `.timer`、`vllm-tp4-head.service`、`vllm-cluster.service` | `disabled` | — | **有意退役**（`guards.conf:23-29`）；`vllm028-tp4-head.service` 为 `masked` |

### 2.3 运行中的进程（`pgrep -af` 实测）

| PID | argv | 由来 |
|---|---|---|
| `846274` | `/bin/bash …/oom-gate/oom_gate.sh monitor -w 6 -f 1.5 -n 3 --iv 10 -a -e 1` | `oom-gate-monitor.service` |
| `30282` / `30294` | `/bin/bash /opt/aicad-prod/scripts/vllm_logdump.sh` | `vllm-logdump.service`（跟随进程） |
| `30280` | `python3`（监听 `0.0.0.0:8001`） | `concurrency-proxy-v2.service` |

**不在跑的（★重要）**：`guardctl.sh watch` —— 见 §4。

---

## 3. 历史脚本（不在服役路径）

**统一免责声明**：以下均为 **2026-09 之前（或窗口期）的一次性研究脚本**，
**保留留档，勿在窗口引用**。它们没有接口承诺、没有 md5 台账、
参数与路径可能指向已不存在的对象（例如 vLLM 时代的容器名 `vllm-v41-*` / `vllm-tp4-rank*`）。
要用其中的**思路**可以，用**脚本**必须先复核。

| 家族 | 数量 | 例 | 当时干什么 |
|---|---|---|---|
| `0NN_*.sh`（数字前缀） | 26 | `001_env_baseline.sh`、`027_w2_memref.sh` | 2026-08-31 的一轮编号化调查（环境基线 → 几何对比 → 边界扫描 → 探针） |
| `a0*` / `a*_*.sh` | 4 | `a5_commits.sh`、`a2_src_grep.sh`、`a4_aot_env.sh`、`a016_contrast.sh` | A 线（AOT / 源码 grep / 对照臂）调查。**`a5_commits.sh` 无头部说明**（首行 shebang、次行即代码） |
| `c1..c5_*.sh` | 5 | `c5_call_site.sh`、`c2_read_wrapper.sh` | C 线调用点/包装器调查 |
| `moe_*.py` | 14 | `moe_boundary_scan{,2..9}.py`、`moe_wrapper_*.py` | MoE 边界扫描与 graph 探针 |
| `rex_*` | 13 | `rex_g4_handoff{,_v2}.sh`、`rex_g4_tokenids.py`、`rex_de3_med.py` | G4/T5 回归与定谳（多数只有一行中文注释，**无用法说明**） |
| `w6_*` | 27 | `w6_fi_diff*.sh`、`w6_attn_probe{,2..9}.py`、`w6_w2_patch.sh` | W6 阶段：flashinfer 源码定位/对比、attention 探针 |
| `w2_commit_r4.sh`、`w1_precheck.sh`、`w1_shutdown.sh` | 3 | — | W1/W2 窗口的提交与开关机小工具 |
| `w3_run*.sh` | 3（含 `.a6-fail`） | `w3_run_head.sh` | W3 窗口的 rank 启动（**次行即 `[ -z "$3" ] && …`，无说明**） |
| `w8_*` / `w9_*` / `w9r2_*` / `w9r8_*` | ~30 | `w9r2_s4a_repro_v2.sh`、`w9r8_full_suite.sh`、`w9_s3_orch.sh` | W8/W9 基准与 MTP 复现驱动 |
| `sre10_*` | 8 | `sre10_evidence_fix{2,3}.sh`、`sre10_s8a_smoke.sh` | SRE-10 证据/冒烟小工具 |
| `l3fix_*.sh` | 7 | `l3fix_img_inspect.sh`、`l3fix_wheel18.sh` | L3 修复的镜像/轮子核查 |
| `gsm8k_full_g1r{5,6}.sh`、`stop_g1r5_full.sh` | 3 | — | G1r5/G1r6 的 GSM8K 全量与收尾 |
| `install_and_probe.sh`、`pull001.sh`、`run_probe192.sh`、`probe192.py`、`bisect30.py`、`topk_correctness.py`、`kread_ab.py`、`bench_short_suite.sh`、`fw_*.sh` | ~12 | — | 起栈/拉取/探针/二分/正确性/框架启停等零散工具 |
| `moe_boundary_scan*.py` 之外的一次性 `.py` | — | `l3002_patch_sim.py`、`flashinfer_sparse_l3_002.py` | 补丁模拟与源码改造 |
| `*.bak-*` / `*.orig-*` / `*.a6-fail` / `*.log` / `*.csv` | ~60 | `w3_run.sh.a6-fail`、`bat8192-restart-20260909.log` | 就地备份与一次性读数 |

> **命名约定不一致（如实登记）**：备份后缀至少并存 6 种风格 ——
> `.bak-<tag>-<date>`、`.bak-<tag>-<date>.bak-decred-<date>`（孪生）、
> `.orig-<tag>`、`.<date>-<tag>`、`.<tag>`、`.<tag>.a6-fail`。
> 其中 **`.bak-decred-20260911`** 是 2026-09-11 一次批量动作留下的**孪生副本**（每个原文件一个），
> 数量级 ~40 个，**不是独立版本**。

---

## 4. 已知缺口（诚实登记）

| # | 缺口 | 证据（实测） | 影响 |
|---|---|---|---|
| **G1** | **`guardctl.sh watch` 是无单元裸进程，且当前未运行** | `pgrep -af 'guardctl[.]sh watch'` **无输出**（2026-09-23 01:0x）。`guards.conf:120-124` 自述：「它俩都是 **setsid 裸进程、没有任何单元保证**（已知缺口，见 WINDOW-RUNBOOK §7）：机器重启或被人 kill 后不会自愈」 | 失去"状态翻转才告警"的告警面。**不阻塞开窗**（该前置 `必需=no`）。已在 2026-09-20 用 `guard-check.timer`（15 min）作**替代而非等价物**——节拍巡检 ≠ 状态翻转告警。重挂命令见 `WINDOW-RUNBOOK.md` §5.3 |
| **G2** | **`vllm_logdump.sh` 双副本分叉** | `/opt/aicad-prod/scripts/vllm_logdump.sh` md5 **`3d3793d0244a**d3ead0ea1bd94e1e7d60`（**权威=在役**，`vllm-logdump.service` 的 ExecStart 指向它，且 `guards.conf:30` 钉的就是这个值）vs `~/w6-kit/vllm_logdump.sh` md5 **`f8c394713fe6**bcfed21696f39a04576d`（**历史**；= 2026-09-23 复算的**现值**）。旧登记值 `ad93d8e2ad15**54ecbfb301ee4cf59d86` 与脚本头注里的同名自述**都是过期值**（该副本被改过、自述未同步），本次已两处同改，顺序 = **先改脚本头注 → `md5sum` 复算 → 回写本行**（头注改动前实测 `e540913d91053178853e19e49f0d3170`；改后本行即为现值。脚本头注**不能自证** md5 —— 自指值会被下一次编辑同时改掉 ⇒ **以本行登记为准**，见 `vllm_logdump.sh:11-16`）。`diff` 输出**恰 3 处变更**（6 行 ±；`:41` / `:105` / `:167`），其中 `:167` 的预过滤：`~/w6-kit` 那份仍是 **旧字节** `grep -E '^vllm'`，`/opt` 那份已修为 `grep -E '^(vllm\|dsv41)'`（2026-09-16 修：SGLang 容器名 `dsv41-*` 进不来 ⇒ 切栈后两天零转储） | **照 `~/w6-kit` 那份部署会静默失去 SGLang 的崩溃取证**（两天的零转储就是这么来的）。两副本的 `LOGDUMP_PATTERN` **默认值**也不同（`^vllm028-tp4-rank[0-9]+$` vs `^(vllm-tp4-rank…\|vllm-v41-pread…\|vllm-v41-baked…)$`），在役实例靠 drop-in `99-sglang-pattern.conf` 覆盖为 `^(dsv41-head\|dsv41-worker\|vllm-.*-rank[0-9]+)$` |
| **G3** | **`vlcold-md5-20260909.txt` 同名两 md5、且已全部过期** | 文件 6 行：`start_tp4_head_v043.sh` 出现**两次**（`:1` = `a62aa1ed70f5…`，`:5` = `b0b3561ae8f4…`）；`start_tp4_worker_v043.sh` 同样两次（`:2` = `cf5ddd5a92fb…`，`:6` = `31d60685dd9a…`）。**行内没有任何时点/版本字段**（只能从 `:3`/`:4` 的 `.bak-vlcold-20260909` 同名值反推，那两行与其孪生行**逐字节同值**）。**且四组值都不再匹配当前文件**：现役 `start_tp4_head_v043.sh` = `9b00f9df29a1…`、`start_tp4_worker_v043.sh` = `a56eb7a7e24b…`；两个 `.bak-vlcold-20260909` 文件已从顶层移入 `.archive-scripts-20260910/` | 台账**已失效**：既无法用它校验，也无法用它回溯"改前/改后"到底哪个是哪个。**需要重做或明确废弃** |
| **G4** | **`v41_hostattr.v2.sh` 无调用者（已在 `guard/README.md` §14「缺口①」登记）** | 全目录 `grep -rn 'v41_hostattr'` 只命中 `v41_hostattr.sh` 自身与 `v41_hostattr.v2.sh` 自身；`v41_win_mmprobe.sh:123/215/218` 的 ⑤c/⑦b 步调的是 **v1** | v2 修掉的三个缺口（缺 swap 口径 / "沉默即 0" / 列不自描述）**在当前窗口剧本里没有被用上**。2026-09-22 的 02 冻结 19 min 那次，缺的正是 swap/pswap 口径。**切换规则未文档化**（该用 v1 还是 v2 无成文）|
| **G5** | ~~`nvmodule-guard.service` 在役但不在 `guards.conf`~~ **已闭合（2026-09-23）** | **2026-09-23 已登记**，行名锚点见 `guards.conf` 的 `nvmodule-guard` 行（当日在位 `:133`；**引用请按行名定位**，勿死记行号）；`grep -c nvmodule guard/guards.conf` = **1**（原记 0 已作废）。该行全列已机械生成进 `guard/README.md` §3 表（`GUARD\|all\|nvmodule-guard.service\|oneshot\|-\|/usr/local/sbin/nvmodule-guard.sh\|989c04d86368\|yes`） | 原缺口（"它失效没有人会知道"）**已由注册项 + §3 表覆盖**：`guardctl check` 从此会判它。⚠ **但判据缺口仍在**（沿注册表的原文登记）：判据 = "非 Open Kernel Module 即 OK"，**缺 `580.` 版本断言** ⇒ 595/610 等专有模块被误载时同样打印绿字 |
| **G6** | ~~`guard/README.md` §9 声称三个脚本"已不存在"~~ **已修** | 2026-09-23 01:05 的并行修订已把口径改成「**已不在生产启动路径上、但文件仍在 `~/w6-kit/` 留档**」，并给出实测大小（6728 / 3945 / 14748 B）。本索引核过：三份**均在盘上** | 无（保留此行作为"文档会漂移、以文件系统为准"的示例） |
| **G7** | ~~`guard/README.md` §3 的条数过期（写 14 条 `PRECOND`）~~ **已修** | 同一次并行修订已按 `guards.conf` 复算 `PRECOND=19`，并注明"旧版此处写 5 行 / 14 条 PRECOND——计数已过期"。⚠ **本行自身曾把过期计数当已修事实传播，2026-09-23 更正**：原写 `GUARD=5`（那是 `nvmodule-guard` 尚未登记时的值，见 G5）；现按 `awk -F'\|' '{print $1}' guard/guards.conf \| sort \| uniq -c` 复算 = **`GUARD=6 TIMER=1 PRECOND=19 RECOVERY=2`** | 无（同上；保留此行作为"计数随注册表变动、改一处要回头核另一处"的示例） |
| **G8** | **`guards.conf:78` 引用的两个脚本在本目录不存在** | `guards.conf:78` 写「先跑 `v41_kv_hygiene.sh` / `v41_window_prep.sh`」；`test -e` 两者均 **MISSING** | 按注册表描述去找会找不到。这两个脚本或在别处、或已随 vLLM 退役（**未核实**） |
| **G9** | **`oom-gate/README.md` §10.2：止损前保护从未在真实止损路径上落过盘** | `test -d oom-gate/logs/site` ⇒ **不存在**。机制 2026-09-22 15:17 才上线，最后一次真实击穿是 14:52:42 | 目前证明它工作的唯一证据是 `selftest_snapshot.sh`（假 docker 夹具）。**"有机制" ≠ "机制有效"** |
| **G10** | **`oom-gate/README.md` §10.1：`/proc/meminfo` 读失败可能被读成 0 ⇒ 直接止损** | 静态阅读 `oom_gate.sh:53-55,155,222,225` 得出 | **未做故障注入验证**。代价不可逆（会真的 `docker stop` 生产） |
| **G11** | **窗口变体 env 有 9 份散在生产仓根目录**（1 基线 + 8 变体） | 实测 `~/dsv41-flash-dgxsparks/`：`.env.tp4`、`-600k`、`-600k-AB`、`-600k-mmban`、`-600k-oldpool`、`-600k-probe`、`-026test`、`-ctx262k`、`-diag`，另加 4 个 `.bak-*` | 不是 `w6-kit` 的问题，但**窗口里选错 env 是静默的**（见 `WINDOW-RUNBOOK.md` §0.1）。其中含 `API_KEY` ⇒ 权限须 600（`v41_kfix_ab.sh:31` 的 `umask 077` 就是为此） |
| **G12** | **只有 01 的 oom-gate 日志在本目录** | `oom-gate/logs/` 只有 `oom-gate-monitor-dgxspark01.log`（253 行）+ `warm-cache-dgxspark01.log` | 三台 worker 的止损事实在各自 home 下，**跨机对账须逐机取**，无统一归档 |
| **G13** | **本文档与 `guard/README.md` 是并行修订的，须交叉对账** | 2026-09-23 01:05：`guard/README.md` 从 347 行涨到 **654 行**（新增 §13 非注册表守卫 / §14 量具 / §15 判据式总表 / §16 引用与出处），并已在 §16 把 `ADR-004` 与 `WINDOW-RUNBOOK §5/§7` 标为**"待生效指针"**（该表落笔时两个路径尚未落位）。本索引落盘后，这两个指针**已生效**：`adr/ADR-004-three-gib-floor-guard.md`、`WINDOW-RUNBOOK.md` | **改任一侧都要回头对另一侧**——两份文档描述同一批对象 |

---

## 5. 阅读顺序建议

**第一次拿到这个目录的人，按这个顺序读**：

```
① 本文件（README.md）                         ← 你在看的这份：目录是什么 / 哪些在役 / 哪些别碰
② WINDOW-RUNBOOK.md                          ← 要开窗？先读它 §0 的铁律清单（8 条，每一条都对应一次事故）
③ guard/README.md                            ← 守卫体系怎么用：guardctl status / check / preflight / hold / release
④ guard/guards.conf                          ← 注册表【唯一事实来源】。README 与它冲突时，以它为准
⑤ oom-gate/README.md                         ← 唯一会 docker stop 的守卫：四条线、动作顺序、退出码、自检
⑥ adr/ADR-004-three-gib-floor-guard.md       ← 为什么是 eff_idle、为什么止损线是 1.5 GiB
⑦ FABRIC-GID-REPAIR-RUNBOOK.md               ← 断电/楔死之后：§1 GID 审计 / §5 断电复核 / §7 时钟病
⑧ guard/BASELINE.md                          ← 状态基线 + 历次修订表（放最后，因为它最长）
```

> `guard/README.md` 在 2026-09-23 扩写过一轮，额外有 **§13 非注册表守卫（timer / 手工驱动）**、
> **§14 量具与会话工具（含两处已知缺口）**、**§15 判据式总表（含 fail-closed 性质）**、
> **§16 引用与出处（外部编号登记，无 URL 的不编 URL）** —— 查具体判据时优先看 §15。

**按任务跳读**：

| 你要做… | 读 |
|---|---|
| 开维护窗口 | `WINDOW-RUNBOOK.md` §0（铁律）→ §5（hold/release）→ §7（时钟预检）→ 末尾检查表 |
| 查守卫现在谁在守 | `guardctl.sh status`；坏了怎么修 → `guardctl.sh check` 给出的修复命令 |
| 开窗前放行判断 | `guardctl.sh preflight`（0=可启动 / 1=不许启动）；原理 → `guard/README.md` §5.3 |
| 内存告急 / 栈被停了 | `oom-gate/README.md`（先看 §3 动作顺序，再看日志 §7）；谁停的 → 找「地板击穿」行 |
| 机器整体变慢 | `FABRIC-GID-REPAIR-RUNBOOK.md` §7（负载态时钟）→ `WINDOW-RUNBOOK.md` §7 |
| 断电/冷断电之后 | `powercycle_check.sh`（栈停着跑）→ 有洞修洞 → 起栈 |
| 量内存瞬态 / 跑剂量 | `v41_memwatch.sh` + `v41_memwatch_report.py` + `v41_dose_ladder.sh`；现成剧本 = `v41_win_mmprobe.sh` |
| 追历史结论 | `G1R7VL-*.md`（14 个）；更早的在 `.archive-scripts-20260910/` |

---

## 6. 维护约定

1. **改守卫脚本后**必须同步三处，否则 `guardctl check` 会持续报 DRIFT：
   ① `guard/guards.conf` 的期望 md5 ② `guard/BASELINE.md` ③（如涉及）本索引的在役清单。
   改脚本前先跑 `bash guard/guardctl.sh snapshot` 留档。
2. **`guardctl snapshot` 会覆盖 `BASELINE.md`**，而该文件下半部分是历次修订表 ⇒ **手工追加，别拿 `snapshot` 刷**。
3. **本索引的"在役清单"（§2）必须现场取证再写，不许手抄** ——
   `guard/README.md` §3 手抄过一次，于是它一直在描述 vLLM 时代的三条单元而生产早已切 SGLang。
4. **一次性脚本跑完就归档进 `.archive-*`**，并在文件名里留下日期与窗口 tag。
5. **交付/在役两套布局的差异是正常的**：交付包带 `HOW-TO-INSTALL.md` 与 `MD5SUMS`，
   在役目录缺它们是**正常**（`guard/README.md` §10）。本目录当前**没有** `HOW-TO-INSTALL.md`
   （`test -e` 实测）。
6. **1.8 GB 里绝大多数是历史** —— 新增 vendored 源码树/镜像 tar 之前先问自己：
   它为什么不能进 registry 或 `/data`？

---

## 7. 文档地图

| 文档 | 位置 | 管什么 |
|---|---|---|
| 本文件 | `README.md` | 目录总索引、在役清单、已知缺口 |
| 窗口纪律 | `WINDOW-RUNBOOK.md` | 开窗/关窗全流程；§0 铁律 / §5 停泊放行 / §7 时钟预检 / §8 测量纪律 / 末尾检查表 |
| 守卫体系 | `guard/README.md` | `guardctl` 全部子命令、`oneshot` 危险类型、失效形态表、SOP；§13 非注册表守卫 / §14 量具 / §15 判据式总表 / §16 引用与出处 |
| 守卫注册表 | `guard/guards.conf` | **唯一事实来源** |
| 状态基线 | `guard/BASELINE.md` | `snapshot` 基线 + 历次修订表 |
| 内存地板守卫 | `oom-gate/README.md` | 判据量、四条线、动作顺序、退出码、snapshot 内容、自检、已知刀口 |
| **ADR-004** | `adr/ADR-004-three-gib-floor-guard.md` | 内存地板守卫（止损线 2026-09-23 起 1.5 GiB）的架构决策记录（背景/决策/理由/替代方案/后果/证据/复审） |
| 断电与楔死 | `FABRIC-GID-REPAIR-RUNBOOK.md` | GID 洞修复、断电复核清单、PD 安全模式时钟楔死 |
| 历史结论 | `G1R7VL-*.md`（14 个） | G1R7 VL 线的窗口报告与交付文档 |
| 历史窗口册（**专用件，勿当通用册**） | `~/r4-ops-work/r9-ops-20260914/evidence/delivery-20260916/WINDOW-RUNBOOK-20260917.md` | 2026-09-17「容器改由镜像供码」那一次切换窗的 runbook；其 §5=治理复位、§7=已知缺口 |

> **`ADR-004` 与 `WINDOW-RUNBOOK §5/§7` 两个"待生效指针"已落位**：
> `guard/README.md` §16 在 2026-09-23 落笔时把这两者标为"路径尚未落位、待生效"。
> 本索引落盘后：
> - `ADR-004` → `adr/ADR-004-three-gib-floor-guard.md`（本索引同日创建）
> - `WINDOW-RUNBOOK §5/§7` → `WINDOW-RUNBOOK.md` §5（停泊与放行 + 裸进程重挂）、§7（时钟健康预检 + §7.5 裸进程缺口）
> 两者此后可直接引用。
