# V 轨协议：KV 扩容 + GMU 阶梯（R4-Master §3 的操作件）

> 总计划：`~/V41-R4-OPS-MASTER-PLAN-20260913.md` §3。本件只记操作序列与门。
> 部署日期 2026-09-13。相关 md5：guardctl=8d0f39b82980 / guards.conf=061b4674037c /
> v41_kv_hygiene.sh=c39f15c57b14（四机一致，.bak-r4v0-20260913 留档于各 worker）。

## 机理（2026-09-13 V1 实测后改写）

**旧说（部分成立）**：GB10 统一内存上 vLLM 读裸 MemFree，页缓存被当"已用"——这解释 boot 期 OOM
与"权重加载 populate 缓存"现象，启动前 drop 依旧是**必要**条件（V1 实测 startup device free
109.75/121.63GiB，干净开局+装载不 OOM）。

**V1 实测改写**：**池尺寸不是页缓存卡死的，是 GMU 预算算术卡死的**。收账行（gpu_worker.py:857）：
`KV = GMU×121.63 − 权重 91.32 − 激活 1.22 − non-torch(4.0-6.2 抖动) − 图(0.65-0.78)`。
V1 靴（GMU 0.82）：四 rank KV=1.03/3.16/3.63/2.33GiB，全局 113,591 tok=跨 rank 最小（rank0 non-torch
6.16 拖垮）；rank1-3 已在族高端。引擎自证 rank0 尚有 10.25GiB、rank1 有 13.47GiB 可用
（"fully utilize"建议值）。**⇒ 真杠杆=GMU 阶梯（+0.02=+2.43GiB）或绝对值 `--kv-cache-memory`
flag（绕开 non-torch 抖动，launcher 须加 env 通路=V5 候选）；历史"池锚不可复现"真身=non-torch 项抖动**。

boot 后 MemFree 4-5GiB（Cached 10-13GiB 可回收）⇒ V2 起 healthy 后**补一次 drop_caches** 满足
裸 MemFree≥8GiB 地板门（只清 clean 页缓存，不碰 anon/设备驻留）。

## V1 轮（零参数变化，纯卫生）—— **已执行判 FAIL（2026-09-13）**

1. 停测试栈（worker 先 rank0 后，按名，rm 前取日志；logdump 在录）。
2. `bash ~/v41-runtime/v41_kv_hygiene.sh`（四机 drop_caches + 裸 MemFree ≥96GiB 门 + 预算表）。
3. 逐机 `bash ~/w6-kit/guard/guardctl.sh preflight`（新门 `memfree-raw-vllm` 必过）。
4. 起栈（launcher 母本 GMU=0.82 不动，GRAPHS=1 形态）。
5. **门**：rank0 日志 `GPU KV cache size`/`Maximum concurrency` ≥330k tokens（族高端）；
   四机 boot 后裸 MemFree ≥8GiB；healthy。
6. 证据落 `~/v41-runtime/vtrack-evidence/`（hygiene 报告 + 池读数截图/日志行）。

**V1 结果**：池 113,591 tok/1.03GiB **FAIL**（<330k 门；亦低于停栈锚 168,729）；机理改写见上节。
证据=`~/r4-ops-work/window-20260913/evidence/v1-round/v1-verdict.txt`。吞吐锚=33.6 冷/23.4/20.0 暖 ms/tok。

## V2 轮（单变量：GMU 0.82→0.84）—— **已执行 PASS（2026-09-13）**

- 施加物：launcher 变体 `GMU=0.84`（变体只存轮次目录，母本不动）。
- 门：V1 门 + 浸泡无 global_oom（doctor 查 oom-kill/NV_ERR）+ 吞吐 A/B 不退（<5% 效应须 3 启动）。
- 预算：desired 102.17GiB ⇒ KV ~5.4-6.7GiB（并发 ~12-15× 上限口径）。

**V2 结果（07:47-08:05 UTC）**：池 344,401 tok/7.01×（straggler=rank1 KV 3.13GiB/non-torch 6.50；
rank0/2/3=5.68/5.98/6.15）；healthy 后补 drop 裸 MemFree 12.4-14.7GiB ✓；吞吐 19.8/21.2/21.1
ms/tok 不退 ✓；6 并发压测+浸泡无 oom-kill ✓（NVRM 瞬态仅 sizing 时刻）。证据=
`~/r4-ops-work/window-20260913/evidence/v2-round/v2-verdict.txt`。**规程增补：V2 起 healthy 后
补一次 drop_caches 再判地板门。**

## V3 轮（条件项：GMU 0.86）—— **已执行五门全过 PASS（2026-09-13）**

- 预算：KV ~7.9-9.2GiB；按 non-torch 抖动上限 6.5 推 straggler ~4.8-5.5GiB ⇒ 全局池估 ~480-560k tok。
- 门：同 V2（含补 drop 地板+吞吐不退+浸泡）。

**V3 结果（08:13-08:35 UTC）**：池 **753,298 tok/15.33×**（straggler=rank0 6.84GiB/non-torch 5.22；
rank1/2/3=8.32/7.99/8.39）；地板 8.03/8.79/10.21/10.10GiB（01 薄）；吞吐引擎侧 24.1 ms/tok≈基线
23.90 ✓；12 并发全过；**boot 窗零 NV_ERR/零 oom-kill（三靴最干净）**。证据=
`~/r4-ops-work/window-20260913/evidence/v3-round/v3-verdict.txt`（md5 2b7d90b8）。

## V 轨终态（2026-09-13 收口）

- 三靴池演进 113,591→344,401→753,298 tok（3.03×/7.01×/15.33× 并发）；停栈锚 168,729/3.43×。
- **常备推荐 GMU=0.84**（地板 12-14GiB 余量，7.01× 覆盖 6 并发业务线）；**0.86 验证可用但 01 地板
  8.0GiB 薄**——业务 >12× 并发再启用并盯 01 MemFree。
- 锁池尺寸（消除 non-torch 逐靴随机）⇒ `--kv-cache-memory` 绝对值 flag，launcher 须加 env 通路（V5 候选）。
- 窗口报告=`~/r4-ops-work/window-20260913/WINDOW-REPORT-20260913.md`。

## V4 轮（研究，质量门）：main KV MXFP4

- 官方 §3.2 口径（RoPE 后量化、SWA KV 保持 FP8）；运行态 `sm120_fp4_paged_mqa_logits` 在。
- 门：接受率 Δ<2% + 质量抽检 + 池计数核验（换算常数改按 MXFP4 重算）。
- 前科：NVFP4 KV 质量红旗——不过门即回 `fp8_ds_mla`。

## 红线（不动）

block_kv=64（DeepGEMM 断言）；MBT=2048（speculator max_num_tokens=4608 硬顶）；
`--memory 116g` cgroup 不防设备 OOM，一切以裸 MemFree 地板为准；探针 ≤free−4GiB；
生产 8001 不碰；FP4 indexer 仅 +1.6% 池不做。

## 换算与核对

- 9,749.35 B/token/rank（fp8_ds_mla 口径）；每池块 273,984 B。
- 起栈后核对：`docker logs <rank0容器> 2>&1 | grep -E "GPU KV cache size|Maximum concurrency|blocks"`
- 池锚换算：tokens = KV_bytes / 9749.35；并发@49152 = tokens / 49152。
