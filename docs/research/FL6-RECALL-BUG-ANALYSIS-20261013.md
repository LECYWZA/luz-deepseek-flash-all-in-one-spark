# FL6 KV 召回 bug 定谳与修复分析档（FL6-RECALL-BUG-ANALYSIS-20261013）

- 窗源：QA31-RESULT-20261013 §四 FL6 硬线红（cp30 0/3 vs 锚 3/3）+ 用户裁定 d36c1a5/4d10357（修复制：0.3.1 配置形零动，计算路径与缓存召回算法层深挖代码级 bug）
- 调查制：外部修复专家案头窗（纯案头：零集群、零 boot、零流量；写动作=本档+dev/fl6-recall/ 件）
- 源码锚基：`~/sglang-main-src`（79cafec0，与部署容器同基座）；部署面=stock 引擎+28 件 overlay o12c1-prod+adapter（mem_cache 层无 overlay=纯原生代码）

---

## 0. 结论摘要（一段版）

FL6 cp30 0/3 **不是 R1/W5 代码回归，是基座 radix 设计的结构性锐边在更深载态下的必然爆发**：DSV4.1 混合池里一条前缀能否复用由其尾窗 SWA KV 存活独门决定（swa.py `create_match_validator`：路径上尾窗节点 tombstone ⇒ best match 停在更浅处，整支死光则归零），而 chunked prefill 每 chunk 边界都会向树内提交 ~1 页（256 tok）SWA 窗值——SWA 需求 ∝ 总填充量。QA31 fill30 实灌 27.54%（264 万 tok）对锚窗 20.83%（水位哨兵提前截停），SWA 池（125,440）饱和（实测 evictable 121,344 / avail 3,072）→ LRU 循环把三档召回文档的终尾窗全部 tombstone → match 归零 → 27.8 万 FULL 驻留作废、全长重预填。cp12 绿（L0017 99.95%）与锚 cp30 绿（20.83% 时 SWA 需求带骑线存活）同为机理内落点。**修复=B1+A 双件（adapter 组件 fl6_recall.py，纯代码路径，serve/env 形零动）**：B1 完成时退休中间 chunk 页（SWA 树足迹从 ~1 页/chunk 降到 ~1 窗/文档）恢复精确召回；A 对 FULL 驻留/尾窗全灭的分支按「页对齐命中−(窗+页)」回缩而非归零，保障用户裁定的 100% 水位召回语义。桌面双臂 A/B 验证：同压力下对照 0% / 修复 100%。

## 1. 证据链（每条带锚）

| # | 事实 | 锚 |
|---|---|---|
| 1 | cp30 三档全 miss 双源互证（cached=0×3 + TTFT 比 1.0042 全长重预填）；cp12 L0017 命中 99.95%（与锚同值） | QA31-RESULT §四表；bench/QA31-P3/e3a-redo/{judge-cp30.jsonl,engine-cp30.log} |
| 2 | QA31 fill30 实灌 **27.54%**（2.64M net tok；stop_reason progress 27.5% 达带）vs 锚 E3A-T256 cp30 **20.83%**（水位哨兵 6,286MB 提前截停，续灌仅 797,898 tok） | e3a-redo/fill30.log 末行；E3A-DOSE-RECALL-RESULT §3.1 表 |
| 3 | SWA 池饱和：fill30 末 `swa_evictable=121,344 / swa_available=3,072`（池 125,440） | e3a-redo/metrics.jsonl 末样 |
| 4 | FULL 池无压力：evictable 1.20M→2.64M 单调增、池余 72.5%、water 最低 8,877MB 无 abort | QA31-RESULT §四排除面①② |
| 5 | 尾窗独门语义：SWA validator 遇 tombstone `state["len"]=0; return False`；`_all_valid` 全组件门禁推进 best match | `mem_cache/unified_cache/components/swa.py:320-343`；`unified_tree_core.py:877-894` |
| 6 | 每 chunk 窗页提交：cache_unfinished_req 每 chunk 走 insert，`_populate_range`→`_clip_to_window`（保留 max(窗,页)=256）发布当 chunk 窗值且**永不退休** | `unified_radix_cache.py:1134-1241`；`common.py:55-115`；KV-LIFE forensics §2.4（swa_evict/full≈0.045-0.13 实测带） |
| 7 | 量算：2.64M tok ÷ 4,096 chunk ≈ 645 窗页 × 256 ≈ 165k SWA 需求 ≫ 98,304 radix 可寻址 headroom（T256） | 本档算术；池构成 `pool_configurator.py:1198-1221` |
| 8 | 锚 cp30 绿的机理注记：cp12 召回 miss 重入树=MRU 刷新（二世代效应），锚 cp30 三档含此效应且续灌仅 ~36-104k SWA 需求骑线存活 | E3A-DOSE-RECALL §3.1 机理注记 |
| 9 | R1/W5 无涉：cp12 全绿证明 radix+SWA+FP4KV 复用路径正常；分型差唯一变量=载态深度（27.5% vs 20.8%） | 本档 §2 桌面判别 |
| 10 | 桌面复现（关键）：微缩几何（page=256/窗=128/chunk=1024）真实生产流程（admission match+加锁→逐 chunk cache_unfinished_req→insert_req finish）下，对照臂 SWA 池循环后重放 **hit=0**——QA31 cp30 语义逐位复刻 | dev/fl6-recall/test_fl6_swa_recall.py test_10 对照臂 |

## 2. 根因定谳（含判别实验）

**定谳：SWA 尾窗容量门禁 + 中间 chunk 页永久驻留的复合结构性缺陷。**

判别矩阵（桌面，test_10 同压力场景）：

| 臂 | cp30 等效重放 hit | 判读 |
|---|---|---|
| 原版（对照） | **0%** | bug 复现 ✓ |
| 仅 A（回缩） | 87.5%（8192−1024 节点粒度） | 兜底有效但小档 <98% 门 → A 单独不绿 |
| 仅 B1（退休） | **100%** | B1 是 FL6 门的必要充分修复 |
| B1+A | **100%** + 尾窗全灭兜底 87.5% | 转正形态 |

排除项：radix 关闭/实现不同（cp12 绿直证）；FP4KV repack 桥（cp12 全绿）；量具（双源互证+修复后桌面全绿）；FULL 逐出（无压力）；水位/water（无 abort）。

## 3. 修复设计（adapter 组件 `fl6_recall.py`，0.3.1 配置形零动）

**B1 完成退休（fix 主件）**：SWA 组件 `cleanup_after_caching_req(is_finished=True)` 后，自 `insert_result.last_device_node` 沿祖先链上行，凡「距终端 > 2×页对齐窗（=512 tok）」且 `lock_ref==0` 的节点，镜像 `evict_component` 原语 tombstone 其 SWA 值（经 FULL 索引走 `free_swa` 释放对端、清 LRU 挂载、核减 evictable 账），FULL 值不动。依据：bounded replay 下请求自身从不读跨 chunk SWA（晚层窗口 floor 在各 chunk 尾起点，`deepseek_v4_backend.py:1511-1525`），中间页仅服务罕见的在途并发去重匹配。
**A match 回缩（保障件）**：`_match_prefix_helper` 原版走查 + 节点轨迹；当「SWA 有效边界 < 页对齐 FULL 命中 − 回缩量（窗+2 页页对齐）」时改用回缩切点（节点边界下取整），`swa_branching_seqlen`（既有机制）在 insert 侧重盖分支尾窗 → 二发重放自愈（桌面 test_21 直证）。回缩段走标准 extend 路径，晚层尾排布与原生 chunk 逐位同构，不引入新数值近似。
**门控与护栏**：`DSV41_FL6_RECALL_FIX`（未设=休眠=原版行为逐字不变；1=双修；retire/retract=单臂判别）；79cafec0 漂移指纹哨兵缺失即拒起（fail-closed）；HiCache/EAGLE/req-ring 布局旁路。

## 4. 桌面验证（dev/fl6-recall/，6/6 绿）

test_00 低压精确重放 ✓｜test_10 cp30 语义（对照 0%/修复 100%）✓｜test_11 退休不变量（完成后 SWA 驻留 ≤512 tok/文档）✓｜test_20 尾窗全灭兜底（87.5% vs 0%）✓｜test_21 回缩后二发自愈 ✓｜test_22 压力后池守恒（17 文档×512=8,704 精确对账）✓。守恒算术：生产几何下完成文档 SWA 足迹 ~384-512 tok/篇，50 篇 ≈ 19k ≪ 98,304 headroom，9.6M FULL 池内召回不再受 SWA 池约束（用户裁定 100% 水位语义的承载面）。

## 5. 生产部署面（呈裁，本窗未落线）

adapter 组件 `fl6_recall.py` + `sitecustomize.py` 两行 elif 钩子（`unified_tree_core`/`components.swa` 各一）；adapter 指纹 2c4baad3 → 新值（adapter-sync --expect 随窗更新）；boot 时 `DSV41_FL6_RECALL_FIX=1`（窗内第 51 键，E3A 试点同款机制；转正呈裁）。验证窗卡=`docs/taskcards/FL6-FIX-WINCARD-20261013.md`。

## 6. 档案指针

- 修复件：`dev/fl6-recall/fl6_recall.py`（生产 adapter 件）+ `fl6_fix.py`（案头 monkey-patch 同源）+ `test_fl6_swa_recall.py`（双臂 6 测）
- 环境件（案头）：/tmp/fl6venv（venv）+ /tmp/fl6stubs/sitecustomize.py（flashinfer/sgl_kernel/gguf 桩）
- 上游锚：swa.py:320-343/481-580/650-692/959-1029；unified_tree_core.py:839-1011；unified_radix_cache.py:553-672/979-1241；allocator/swa.py:456-567；dsv4_attn_metadata_kernels.py:469-505
