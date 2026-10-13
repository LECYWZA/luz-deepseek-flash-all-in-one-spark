# SPEC6 — 0.3.1 定型形 serve 参谱（六参）

> 法源：FORM-REGISTRY-031 §一（50 键行）+KV-LIFE desk/lib.sh:11+E3A §六。
> C0 定型臂 serve=SPEC6（COMBO 冻结窗卡 §三）；SPEC7（六参+`--chunked-prefill-size
> 8192`）已判负不进形（COMBO-STACK-RESULT 门 1）。

## 六参

| # | 参数 | 值 | 出处 |
|---|---|---|---|
| 1 | `--prefill-decode-interval` | 16 | 五参基座 |
| 2 | `--max-queued-requests` | 32 | 五参基座 |
| 3 | `--min-free-slots-delay` | 1 | 五参基座 |
| 4 | `--enable-decoder-swa-bounded-replay` | （flag） | 五参基座 |
| 5 | `--reasoning-parser` | deepseek-v41 | 五参基座 |
| 6 | `--swa-prefix-tails` | **256** | **E3-A 转正在役**（64→256；召回 N=256） |

## 注入面

- boot 链注入位=`deploy/bin/r3-boot-arm.sh` SERVER_ARGS（SPEC=1 时另加
  `--speculative-algorithm DSPARK`；SPEC_EXTRA_ARGS 空格分词追加面缺省 no-op）。
- QA31 定型窗 SPEC6 归一指纹=33d7161f（四靴一致）。
- 其余池面参数（池门 `--max-total-tokens 9600000`、
  `--json-model-override-args '{"candidate_topk_blocks": 2048}'`、
  `--fp8-gemm-backend flashinfer_cutlass`）为 boot 链固定面，不属 SPEC 参谱
  （r3-boot-arm.sh 内嵌，逐行注释在档）。

## 与 env 键面的配对律

一个形=**env 键面+SPEC 参+adapter/overlay 面**三元组齐一（README 快速上手）；
serve 参变体（如 SPEC7）必须与键面变体同窗冻结判读，禁跨形拼装。
