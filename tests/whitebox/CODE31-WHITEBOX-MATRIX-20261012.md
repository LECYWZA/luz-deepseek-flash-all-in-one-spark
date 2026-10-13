# CODE31-WHITEBOX-MATRIX-20261012 — T3 白盒验证矩阵（14 件红绿复跑+判别力反例抽查）

> **法源**：`docs/taskcards/CODE31-REVIEW-PLAN-20261012.md` §二（场位按窗指令落
> docs/release/，卡原定 docs/audits/——落位差异呈主会话）。
> **环境**：host 案头（dgxspark01 本机；CUDA_VISIBLE_DEVICES=""；torch 2.14.1+cu130
> 仅 CPU 面；零集群零 boot 零流量）。逐件记录：实跑命令+件 md5+输出原文摘要。
> **期望基线**=各窗在档锚（卡 §2.1 表逐行）。

## 一、红绿复跑矩阵（14 件）

| # | 件 | 件 md5（本窗核） | 实跑命令 | 期望 | 实跑结果 | 判 |
|---|---|---|---|---|---|---|
| 1 | ~/migrate-assets/dsv41/adapter/fi_r1/t_r1_equiv.py | 2fe0c0c3 ✓卡 | `CUDA_VISIBLE_DEVICES="" python3 fi_r1/t_r1_equiv.py`（部署面原位） | 49 GREEN/0 RED | `===== 49 GREEN / 0 RED =====` RC=0（D 设备端 e2e 按【SKIP】设计跳过=禁伪造律） | **绿** |
| 2 | dev/r1-fp4kv/sanity_host.py | 08ca1d4c | `python3 sanity_host.py` | 12 断言全绿 | 4 行×（C)requant逐位=True B)rope位等=True 零行不变量=True）+sat/subnorm 细节+`ALL SANITY DONE` RC=0 | **绿** |
| 3 | dev/r1-fp4kv/t_difflocal_inject.py | 30013acf ✓卡 | `python3 t_difflocal_inject.py` | 18 GREEN | `===== 18 GREEN / 0 RED =====` RC=0（E0-E5 含 -1 摆位扫描全表闭合） | **绿** |
| 4 | dev/stage2-agin/test_stage2_agin_host.py | 47b405ab | `python3 test_stage2_agin_host.py` | 27 GREEN/0 RED | `==== 27 GREEN / 0 RED ====` RC=0+WINDOW-PENDING 设备面四条如实列（flashinfer 不可 import=禁伪造） | **绿** |
| 5 | dev/a23beta/test_a23beta_redgreen.py | 35be9102 | `python3 test_a23beta_redgreen.py` | 16/16 | `A23BETA RED/GREEN 16/16 ALL-GREEN` RC=0（含 self_check 15/15+C-2 卫生源码钉） | **绿** |
| 6 | dev/a23beta/test_c1_gather.py | 4377a15f | `python3 test_c1_gather.py` | 13/13 | `C1-GATHER RED/GREEN 13/13 ALL-GREEN` RC=0 | **绿** |
| 7 | dev/r1-fp4kv/prof/trace_verdict.py | e3d002a9 | `python3 trace_verdict.py --selfcheck` | 9/9 GREEN | 9×[PASS]/0×[FAIL]+`SELFCHECK GREEN` RC=0 | **绿** |
| 8 | dev/r1-fp4kv/prof/hostpath_microbench.py | 06ff03f0 | `python3 hostpath_microbench.py` | 6/6 GREEN | 6×[PASS]/0×[FAIL]+`SELFCHECK GREEN` RC=0 | **绿** |
| 9 | dev/ll128-gate/ll128_gate.py | 4b7f8b6b | `python3 ll128_gate.py --selftest`（**py 件，误 bash 首跑注记见 §三**） | 18/18 ALL-GREEN | `[selftest] ALL-GREEN：18/18 用例（G0 绿路径可达性+E 系喂坏输入因正确理由红）` RC=0 | **绿** |
| 10 | tools/adapter-sync.sh | （git 工作树件） | `bash tools/adapter-sync.sh --selfcheck` | 绿 | T3 内容漂移+多件检出/T4 pycache 排除/T5 expect 形态=`5/5 ALL-GREEN` RC=0 | **绿** |
| 11 | tools/qamemguard.sh | （git 工作树件） | `bash tools/qamemguard.sh --selftest` | 绿 | 三件自检（冷却放行/stop 文件优雅退/…）`SELFTEST PASS` RC=0 | **绿** |
| 12 | opt1-dev/census_v3_20261004/tests/test_offline_aggregate.py | （git 工作树件） | `python3 tests/test_offline_aggregate.py --trace logs/R1RECERT-20261004/R1RECERT_census_c1.trace.json.gz --legacy-json …c1.json --workdir /tmp/census_v31_code31 --steps-per-window 30`（TEST-REPORT-20261004 同款命令在档 trace 重放） | 全绿（档锚 26/0） | `===== TEST SUMMARY: PASS=26 RED=0 =====` RC=0 | **绿** |
| 13 | tools/boot_sentinel_anchors.tsv | —（表核非跑件） | 逐行对定型三形键面核 | 形在表/参指纹匹配 | **定型形三键面（15767aa6/8c8c166d/99e7ec92）均不在锚表**——表=初始表（2026-10-10 建档）4 具体行（2de48070 43 键时代×2/bdfd9590/17a9a199）+通配行；遇未知形=ANCHOR-UNKNOWN 横幅不判快慢（建表纪律=不臆造，UNKNOWN 态设计安全） | **注记红**（见发现 W-1） |
| 14 | tools/boot-with-slotlock.sh | （git 工作树件） | 无参跑=usage 守卫；`--help` 作为点火命令=rc 127 传播+锁释放横幅（只读核） | 守卫分支在位 | 无参→`用法: ARM_TAG=<tag> …`；点火失败→`[slotlock] boot 命令退出 rc=127（锁释放中）`+EXIT trap flock -u（fd9 内核语义自动释放，:15-17 注记）；BOOT_SENTINEL 后置步缺省关 | **绿** |

**矩阵判语**：14 件中 13 绿 1 注记红（W-1 锚表缺行，量具面非量具缺陷）；0 假绿
（期望基线逐件精确复现：49/12/18/27/16/13/9/6/18/绿/绿/26）。

## 二、判别力反例抽查（喂坏必须因正确理由变红；注入后复绿）

| # | 靶件 | 注入法 | 红输出（原文摘录） | 红理由核对（对表预期机制） | 复绿 |
|---|---|---|---|---|---|
| D-1 | prefill_sp.py 32cf9abf（键值域） | `DSV41_PREFILL_SP_TAIL_GATHER=b0gus python3 -c import` | `RuntimeError: DSV41_PREFILL_SP_TAIL_GATHER='b0gus' is not a boolean (legal domain: unset\|1\|on\|true\|0\|o…` | ✅ 严格布尔族 fail-closed 拒 boot，消息与 _parse_tail_gather 设计文案逐字 | ✅ unset 重导 TAIL_GATHER=False |
| D-2 | kv_fp4.py feaaadd4（R1 键值域，PORT 武装态） | `DSV41_FP4KV_PORT=1 DSV41_FP4KV_R1_INKERNEL=b0gus`→`kv_fp4.r1_inkernel()` | `RuntimeError: DSV41_FP4KV_R1_INKERNEL='b0gus': strict boolean (1\|on\|true\|yes\|\|0\|off\|false\|…`；summary() 同态 `r1_inkernel=INVALID(…)` | ✅ 拒 boot 律+横幅 INVALID 态（P2-6 两态注记实测证实） | ✅ =1 重跑 r1_inkernel=True |
| D-3 | t_r1_equiv.py（篡改副本，md5 往返律） | 副本改 A7 地板期望 105→104（源树不动；md5 2fe0c0c3→a9ce0c20→复原 2fe0c0c3 双核） | 3×`[RED] A7 …（±0+地板105）— … ue8m0=[105,105,…]` | ✅ 红因=实际地板恒 105 而篡改期望 104——断言具判别力（错误码/数值点名与零行律机制对表一致） | ✅ 复原件+伴件齐备复跑 `49 GREEN / 0 RED` |
| D-4 | census test_offline_aggregate.py（坏输入） | `--trace /nonexistent.trace.json.gz` | `FileNotFoundError: [Errno 2] No such file or directory`+`split 失败` RC=1 | ✅ fail-loud 拒跑（不产半档）；内置 N3 naive≠判别（`naive(须≠)=300.0`）另在绿跑中直证 | ✅（真 trace 跑即 §一 12 号绿） |
| D-5 | trace_verdict.py（坏 CLI 面） | 杂参/位置参乱喂 | `argparse error: unrecognized arguments` RC=2 | ✅ 参数面 fail-loud；空/残 trace 拒收由 docstring :17 声明+selfcheck E 面承载 | ✅（--selfcheck 即 9/9 绿） |

**内置喂坏族随绿跑直证**（不需另注入，红例在绿跑内逐件点名）：1 号件 A 部喂坏
孪生必红×7 行+A7 −0 位喂坏+C2 四例+C3 bogus；3 号件 E0-E5 注入族；9 号件 E1-E11
（40 键形三键缺位红+容器 24 处逐键点名在档）；10 号件 T3 内容漂移检出；11 号件
stop/冷却三例；4 号件 M11-M14（属主表坏 plan 拒绝/roundtrip 禁令/弃用不可达）。

**抽查律达标核对**：外注红例 5 发（≥3 ✓）覆盖键值域三类重点面之两类（R1 键值
域+TAIL_GATHER 键值域）+篡改副本地板断言（FI 布局零行律族）；「红错理由=判别力
缺陷」零例（五发红消息逐字与预期机制对表一致）；每发注入后复绿 ✓（含 D-3 的
md5 前后对表闭环）。GID 断言类 fail-closed 面：本窗 14 件无 GID 断言件（属
FABRIC-GID runbook 面），如实注记不虚报覆盖。

## 三、执行注记与发现

- **W-1（P1·量具面）**：`tools/boot_sentinel_anchors.tsv` 无定型三形行
  （50/48/47 键）——定型形 boot 哨兵将恒 ANCHOR-UNKNOWN（安全态：横幅不判快慢）。
  处置建议：QA31/产线健康靴以哨兵同口径 3 发中位回填（建表纪律禁案头臆造，
  本窗不补假锚）。
- **W-2（P2·量具操作注记）**：9 号件首跑误以 bash 执行 py 件（shebang
  `#!/usr/bin/env python3` 在位，`bash x.py` 语法红无害）；正确用法=直接执行或
  python3。TOOLS31 打包时可在自检清单注明调用式。
- **W-3（P2·纪律注记，如实呈报）**：14 号件首验时 `bash boot-with-slotlock.sh
  --help` 被 wrapper 当作点火命令——实际效果=持锁（flock fd9）+四机 `docker ps`
  只读核+`--help` rc=127+EXIT trap 即释锁。零 boot 零流量零容器写动作；锁为
  排他语义本窗占用数秒已释（.slot-lock 残文本=设计内取证面）。教训已入矩阵
  （14 号正确核法=无参 usage 面+只读读码）。**与在飞 W5-PROMO 转正窗无冲突
  痕迹**（锁已释、无容器动作）。
- **W-4（档锚注记）**：1 号件 D 部（设备端 e2e 两断言+fail-safe 首块对拍）按
  设计【SKIP】（无 sm120 设备）——与卡 §2.1 注记一致，**留 QA31 窗**承接
  （G0/G1 在档绿为现有锚）；4 号件 WINDOW-PENDING 设备面四条同理。
- **复核对表律**：本窗实核件 md5——t_r1_equiv 2fe0c0c3（=卡 A7 基线）、
  sanity_host 08ca1d4c（=卡 §六.2 注记基线）、t_difflocal 30013acf（=卡）、
  stage2 prefill_sp 32cf9abf（=卡 B1）、现役 prefill_sp 0497e566（=卡 B1）；
  其余 git 工作树件以 git 干净面为锚（本窗未改动任何自检件源）。

——CODE31 T3 白盒验证代理 / 2026-10-12（host 面；设备端两件留 QA31 如实注记）。
