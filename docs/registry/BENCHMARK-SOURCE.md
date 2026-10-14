# BENCHMARK-SOURCE — 性能读数量具与口径来源（正典档）

> 本仓 README §一 与 [docs/report/031-FINAL-PERF-REPORT-20261009.md](../report/031-FINAL-PERF-REPORT-20261009.md)
> 的全部性能读数（PR 四档/agg600k/DE c1/0731/VL）出自**自研 `sd_bench` 工具**，其测量
> 口径逐文件对齐社区基准 **sparkDash**（MiaAI-Lab）并经九项定义对表审计——本档说明
> 口径来源、工具谱系与使用纪律。

## 一、口径终源（上游引用）

**sparkDash**（MiaAI-Lab）——DGX Spark 社区 DGX 推理基准/仪表盘项目：

- 上游仓库：<https://github.com/MiaAI-Lab/sparkDash>
- **口径定义源件**（v1.8.6 归档源码，逐文件对齐锚；定义审计 md5 留痕）：

| 定义源件（sparkDash 内路径） | md5 | 定义面 |
|---|---|---|
| `server/collectors/PrefillBench.js` | `eb3f68f2…` | PR：串行/每尺寸单请求/fresh salt/`" the"`×N filler/GEN 8/512t 预热/tok/s=usage.prompt_tokens÷TTFT |
| `server/collectors/DecodeBench.js` | `37c1380f…` | DE：greedy（temp0/top_p1/thinking off）/max 400（warmup 32）/stream+include_usage/decode tok/s=(completion−1)/decode 时长 |
| `server/collectors/LlmStreaming.js` | `90554e60…` | TTFT=tFirst−t0（fetch 前）；estimateTokenCount=len/4；median 均二中位 |
| `src/shared/llmPrompts.js` | `4fd85699…` | prose/structured/json 原文；**code=clamp_00..49 单提示**；c>1 非 code 型 `(stream i/n)` 后缀 |

- 社区已知口径属性：PR filler=重复 `" the"` ⇒ Engram 行缓存命中致 **PR 虚增 16-42%**
  （上游 issue MiaAI-Lab#21 自认；knapcio v2.3 亦给 real-text 修正数）——**本口径数字
  只与同口径数字比**（跨栈对数须换步时或真文本口径）。

## 二、本仓工具实体（tools/bench/）

| 件 | 说明 |
|---|---|
| `tools/bench/sd_bench.py` | sparkDash 口径 headless 复刻基准（PR/DE；头注=逐文件对齐出处，勿凭记忆改） |
| `tools/bench/pr_ladder6.sh` | PR 六档阶梯调用面（3 独立调用取中位/fresh uuid4 salt/512t×2 预热——knapcio 口径自注） |
| `tools/bench/sd_bench_real_text.patch` | 第三 filler 档 `real`（真实文本分布填充；对照 repeated/random 臂隔离 Engram 行缓存膨胀） |
| `tools/bench/sd_bench_real_text.README.md` | 补丁说明（应用法/改动四处/判别力） |

判别力纪律：量具自检「喂坏输入、看它因正确理由变红」（sd_bench 内置；SPARKDASH-ALIGN
判别力自检 19/19）。

## 三、对表审计结论（口径可比性）

- **PR 面**：`pr_ladder6 type=sparkdash` 全列对 sparkDash 定义**九项对表全 PASS**
  （filler/salt/TTFT 公式/串行/预热全对齐）——见 SPARKDASH-ALIGN-20261006（战役仓
  `docs/verdicts/`）；DIFF 9 项中 2 项已修（opt-in flag，锚字节面零触碰）、7 项登记
  不修（锚可比性/退役面/量值无涉）、「定义两义」0 项。
- **量具可比性定谳**：定义层可比（≡社区 sparkDash PR 定义）；仪器层带 **±10% 单提示
  带**（W0 对桩「各自成系不作换算」）——跨读数比较须同口径+同档位+带仪器带
  （GAUGE-COMPARABILITY-20261006）。
- **DE c1 口径**：c1=prose/code 单提示精确原文（c1 即社区 89.76 同条提示口径）；
  0.3.1 读数 81.67=五点位中位（post 主分母）。
- **PR 表口径注记**：README §一 PR 四档/agg600k=**sparkDash repeated-filler 口径**
  （与社区横向可比）；`real` 臂工具在档（patch），0.3.1 定版窗未单列 real 读数——
  量具纪律：一切 prefill 数字附 cache 档位+hit_rate+filler 熵三件套解读。

## 四、致谢交叉引用

sparkDash 相关借鉴源（社区实测复测/real-text 修正数/filler 膨胀报告/上游基线表）已
收录于 [docs/ACKNOWLEDGEMENTS.md](../ACKNOWLEDGEMENTS.md) **B30/B31/B35/B46** 条
（含出处锚与使用状态）。上游 MiaAI-Lab/sparkDash 与其 issue 讨论对本仓量具口径的
奠基作用在此一并致谢。
