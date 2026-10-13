# TOOLS31-PACKAGES-RESULT-20261013 — T4 五工具包整备窗·结果档（案头批）

> 任务卡=`docs/taskcards/TOOLS31-PACKAGE-PLAN-20261012.md`（W-A/W-B 案头段完成；W-C 内嵌
> 落格=呈裁预案承载〔§三表〕；W-D 烘焙=**PENDING-FINAL-GATE**〔FL6 修复绿+定型宣告后
> 后继窗〕）。零集群零 boot 零流量；~/migrate-assets 只读（快照/收编=读取）。
> 自检证据=`logs/TOOLS31-PKG-20261013/`（五包 selfcheck 全文+红绿判别力清单）。

## 一、五包就绪度（逐包五件套+自检红绿）

| 包 | 五件套 | 汇总指纹 | selfcheck | 判别力红例（每包≥1/件律抽样） |
|---|---|---|---|---|
| P1 fabric-net | 齐（MANIFEST 16 件/README/VERSION/bin/selfcheck） | 5e2a1fb9 | **绿 29 OK/exit 0** | F1 enP7s7 混入动作面判红/F2 RX 8192 旧值判红/F3 P4 摘除判红/F4 exit9 摘除判红/F5 坏 JSON 判红/F6 doctor carrier-flap mock 判红 |
| P2 selfdiag | 齐（21 件） | 5727bf05 | **绿 37 OK/exit 0** | F2 锚表 50 键行摘除判红/F3 banner29 反面命中 FACE-RED/F4 正名规则摘除判红/F6 登记器五例（含空表=2）/F8 WATER-RED 摘除判红 |
| P3 selfheal | 齐（13 件） | 627fef97 | **绿 26 OK/exit 0** | F3 篡改 env 判 UNKNOWN（不臆造）+跳级 50→47 判红/F5 注入 3535 动作面判红（02 两守护排除执法）/F6 幂等拆栈摘除判红/F7 判假绿语义摘除判红 |
| P4 gateway | 齐（9 件） | 282b9ad2 | **绿 16 OK/exit 0** | gw-verify 五例：占位键判红（键面非空律）/坏 UPSTREAM 判红/密钥入 unit 判红（SMOK_KEY 执法）/dropin 面缺判红+F4 Restart 摘除判红 |
| P5 cfgmgmt | 齐（52 件） | cec6920a | **绿 29 OK/exit 0** | F1 再摘一键差集=1 判别/F3 缺键逐键点名判红/F4 flock 摘除判红/F6 admregen 六例/F7 算式三性+漂移判红 |

**公共底座**（tools/packages/_lib/）：verdict.sh（诊断出口 JSON 三字段族
`verdict/red_face/suggest{text,runbook,auto_ok}`；五例自检绿）+pkg-common.sh（包面三态
退出码 0/1/2；红优先于无法判）+regen-manifest.sh（MANIFEST 同日再生成器）。
**auto_ok 白名单（§四.1 律）**：仅①GID 洞环回重铺（fabric-gid-heal 四前置+单次+熔断）
②logs 先存后删类取证；禁自动面=引擎重启/楔死处置/boot 拉起（U1 律）——verdict.sh 头注
原文位，五包 help 面同口径。

**在役源对表律**（selfcheck/sources.tsv 机器执法）：包件↔在役源 md5 漂移=selfcheck 红
（同日更新律）；源缺位=UNKNOWN（非 01 机常态）。**属地件两枚**（selfdiag F1 boot_sentinel
真仓律=F9 verify-governance BASH_SOURCE 属地法）跑在役原件复核，包内副本=烘焙锚定件。

## 二、CODE31 留点四项闭合状态

| 留点 | 闭合位 | 状态 |
|---|---|---|
| ①hook 面口径钉「29 活性/40 挂装」 | TOOL-ANCHORS 五包锚段口径钉行+cfgmgmt admregen 输出头行恒载+cfgmgmt README §关键口径-1 | **闭合**（CODE31 P1-③ 承载） |
| ②注释修订批 CA-1/CA-3/CA-4/CA-5 | CA-1/CA-4=dev/code31-comment-fixes/ 修订件（纯注释 diff 亲核在档；**部署面零触碰**，换入走部署窗同 md5 重钉律）+CA-REVISIONS-20261013.md；CA-3=TOOL-ANCHORS :25/:48 双行「已被上行更替」勘误+现役行 15767aa6+回退链三级；CA-5=tools/boot_sentinel_anchors.tsv 表头例值（50/48/47 键例+43 键历史例） | **闭合**（CA-2=QA31 卫生步②已消化；**勘误注记**：CA-4 的 :301 文本实锚 t_r1_equiv.py:84/:385 非 cuh 件——审计档行文勘误=下批注记位） |
| ③overlay 集合指纹算式入 TOOL-ANCHORS | TOOL-ANCHORS「集合指纹正典算式」行：`LC_ALL=C find -type f -print0 \| sort -z \| xargs -0 md5sum \| md5sum` 前 8 位（路径无关三性自检）+历史 20fa6a1d 不复现义务注记+首算值 overlay 73695876/env 0b8dcc8a | **闭合**（CODE31 P2-8 承载；重钉=下次对表窗四机两遍核） |
| ④sitecustomize 指纹变量位 | TOOL-ANCHORS「SITECUSTOMIZE_MD5 变量位」行+admregen 头行变量+restore-sequence S4 引用：当前 **d5dc42a4**（FL6 两行 elif 钩子接线后实测；fl6_recall.py b87cbb5e 2026-10-13 09:36Z 入位）；**FL6 窗终值=回填位**（窗终重跑 admregen 自动带出） | **闭合（设计位）**——终值回填=FL6 窗联动 |

**CODE31 P1-② ADAPTER-MANIFEST 陈旧**同步闭合：admregen 重生成 125 件活清单
（payload/out/ADAPTER-MANIFEST.regenerated；md5sum -c 直验+对活树 --check 全等+
六类分类+PENDING-FL6-FINAL 回填位）。

## 三、检查功能内嵌落格预案（§三；QA31 §八 8 项承接——**呈裁不落线**）

| # | QA31 §八候选项 | 内嵌方案（落格预案） | 落格包 | 成本注记 | 呈裁位 |
|---|---|---|---|---|---|
| 1 | boot 慢靴哨（F-9） | boot-with-slotlock 尾步挂接 boot_sentinel（3 发 32k 对 per-form 锚表；fail-visible 不 abort 律保持） | P2（件已在包） | ~3min/靴墙钟+锚表维护 | **呈裁**（若裁升格=slotlock 尾步一行接入，零新守护面） |
| 2 | warm 门探针（64k×3） | 复原链 restore-sequence S9 常采+台账字段（已编入检查单） | P5 | ~1min/靴 | 已在役（核证即可；零呈裁） |
| 3 | 水位哨兵两级（water+qmg） | **守护常驻=用户裁定面**（qmg 头注红线原文位=selfheal README §四）；裁定通过才 systemd 化（units/ 面已有 oom-gate-monitor 先例形态） | P2+P3 | ~10s 周期常驻进程 | **呈裁（用户裁定面）** |
| 4 | 键面横幅契约（banner29:4） | 不入包（引擎侧在役件；selfdiag gates 族=谱系收编，当前形合同新增走形态注册面零改） | adapter 面 | 零 | 已在役（§七-8 承载） |
| 5 | census 形状断言 | **不升格**（一靴一 census 定律互斥——TOOL-ANCHORS 规则 5/7） | — | — | 不升格注记（非呈裁） |
| 6 | spec_accept_length 伴读哨 | /metrics 常采+阈值报警（σ>0 活跃期直证已档） | P2（探针位预留） | 量轻（metrics 已开） | **呈裁** |
| 7 | fail-safe 双跑对拍 | 不入包（引擎侧在役；PASS rows=96×4 秩/靴已在役） | adapter 面 | ms 级/靴 | 已在役（零呈裁） |
| 8 | 四查+printenv 真键核 | boot 后自动一发（verify-governance 常设核+selfdiag gates+cfgmgmt keycheck 三件齐备=落格纯接线） | P2 | ~1min/靴 | **呈裁（QA31 推荐升格；本包面=接线零新件）** |

**落格红线（卡 §三）**：一切内嵌项 fail-visible 优先（不 abort 不自动重启——U1 律）；
常驻进程类=独立呈裁（禁随包默认携带常驻化）。落格序=呈裁→接线→烘焙随包入镜像。

## 四、烘焙段暂缓注记（W-D）

- **PENDING-FINAL-GATE**：FL6（E3A cp30 召回红）修复验证窗在飞+0.3.1 定型宣告未发——
  前置四项（卡 §5.1：T1 定谳/T2 收案/T3 文档集齐/T4 五包+selfcheck 绿+内嵌呈裁落格毕）
  未全绿，烘焙不启动。
- 案头可完成件已落：`tools/packages/_bake/`（BAKE-PENDING-FINAL-GATE.md+RECIPE.template.md+
  IMAGE-IDENTITY.template.md+ARGV-PAIR-REGISTRY.template.tsv——拍扁 argv 双登记规范案头落
  「RECIPE 载荷表+IMAGE-IDENTITY 各一行+外部注入面保持优先（SPEC_EXTRA_ARGS :396-398+
  ARM_ENV_FILE 尾部覆盖律）+双源漂移=红」）。
- 烘焙边界（承卡 §5.2/5.4+§七.5 悬裁维持）：镜像只载五包+文档集；adapter/overlay 走宿主
  bind mount 真源不烘焙；宿主守护件不入镜像不接线。

## 五、需裁点（汇总呈主会话/用户）

1. **内嵌 #1/#3/#6/#8 四项升格裁定**（§三表；#3 常驻化=用户裁定面）。
2. **拍扁 argv 成对律定义确认**（卡 §七.1 自拟定义已按其落 _bake 三模板——若用户另有
   定义以用户定义覆盖）。
3. **P4 部署位**（01 收编已按默认执行；Mac mini M6 迁移先行则 P4 重排——卡 §七.3）。
4. **P3 02 机两守护只读监测面**（默认排除已执行；纳入只读探针=加项呈裁——卡 §七.4）。
5. **烘焙携带面**（默认不携带 adapter/overlay——「全量烘焙交付」=边界反转呈裁——卡 §七.5）。
6. **P1 社区笔记口径**（默认摘译+链接已执行；逐字收编=改呈裁——卡 §七.6）。
7. **flashinfer-golden 版数注记**（树内自述 fi_version=0.6.18 vs 卡文「0.6.16 参照集」——
   以树内自述为准+卡文数勘误建议；2 件 root-0600 引擎写面未拷贝已登记 UNREADABLE-NOTE）。
8. **集合指纹重钉窗**（正典算式已钉+首算值在档；四机两遍核=下次对表窗动作）。

## 六、commits（单文件/单目录 add；号以 git log 为准）

〔提交序列见 git log——CA-5 锚表勘误/_lib 公共底座/五包逐包/_bake 模板/CA 修订件/
TOOL-ANCHORS 同日更新/本结果档〕

——TOOLS31 T4 案头批代理 / 2026-10-13（零集群零 boot 零流量；FL6 窗未触碰）。
