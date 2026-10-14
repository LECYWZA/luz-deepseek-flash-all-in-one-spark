# sd_bench_real_text.patch -- PR 模式真实文本口径（--pr-filler real）

工单：社区实锤 MiaAI-Lab issue #21 —— prefill filler 单 token 重复（" the"×N）×
Engram 行缓存命中 ⇒ PR tok/s 虚增 16-42%。我方 sd_bench 的 PR 默认口径正是
repeated filler；已有 `random` 档（P5）是均匀词汤，避免了重复但 token 分布仍非
真实。本补丁加第三档 `real`：真实文本分布、行级无重复。

## 应用

```
patch -p1 -d ~/dsv41-flash-dgxsparks < ~/luz030-opt-campaign/tools/patches/sd_bench_real_text.patch
```
（已验证对当前工作区干净应用。）基准树保持未改，补丁即修改稿。

## 改动内容（4 处）

1. `_real_filler(salt, units)` + `_REAL_N/_REAL_V/_REAL_A/_REAL_T` 词库与句模板：
   借 `~/luz030-opt-campaign/tools/ds_gate.py` 的语料生成器（PORT(3) 语法模板散文，
   同源逻辑内联、注明出处；sd_bench 独立不跨仓 import）。salt 播种可复现，字符量
   与 repeated/random 同基准（同 `fill`）。
2. `build_pr_prompt` 严格三档分发（repeated/random/real）；未知值显式 ValueError
   （原实现未知值静默落入 random——哑口径脚枪，改响）。
3. `--pr-filler` choices 加 `real`，**默认仍 repeated**（向后兼容，只在显式传参时启用）。
4. `--selfcheck` 增 7 条 real 断言（见下）。

## 自检断言（real 档）

同 salt 可复现；覆盖目标 token 同基准；无相邻重复单元（`" the the"` 计数=0 ——
" the" 自然高频不算重复，判别式是相邻性）；行级无重复（每行唯一，行缓存无可命中）；
词频非均匀（top 函数词占比>5%，近似自然分布）；具文档结构（章节标题+数字）；
跨 salt 不同文本。

## 单元功能测试结果（2026-09-30，本机，无 GPU/无服务）

- `python3 -m py_compile` 过；`python3 sd_bench.py --mode pr --selfcheck` **21/21 PASS**
  （含原有 14 条 + real 7 条；坏端点负对照照常红）。
- filler 输出抽查（target 4096, salt abcd1234）三口径对照：

| 口径 | 词数 | 不重复词率 | top 词频占比 | 行不重复率 | 相邻单元重复 |
|---|---|---|---|---|---|
| repeated | 4073 | 0.000 | 1.000 | —（单行） | 2036 |
| random | 2701 | 0.039 | 0.014 | 1.000 | 0 |
| real | 3016 | **0.154** | **0.130** | **1.000** | **0** |

  real 词表 464 型（random 均匀词汤 100 型饱和）、高频函数词 13% —— 自然词频形态
  （英文 "the" 天然 7% 量级），是三档中唯一同时满足"无重复可缓存结构 + 真实分布"。

- 长度分布：target 512/4096/16384/32768 → est_tokens 870/4363/16623/33115
  （估算口径 chars/4 对散文 ~5.5 chars/token 自然过冲，方向与 random 档一致，
  selfcheck 的"覆盖目标 token（同基准）"断言同尺）；行长 min/med/max
  9/221..278/585..724 —— 行长多样，无行级模板复读。

## 口径注意

- 三档数字互不可比（口径纪律同文件头声明）；`real` 档结果只与 `real` 档比。
- real 档散文模板与真实生产文本仍是"同分布形态"而非同一语料；若日后接入
  kld_long_texts.json 式真语料（ds_gate `--texts FILE` 机制），另起口径键，勿复用 real。
