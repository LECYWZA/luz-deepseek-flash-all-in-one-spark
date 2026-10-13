from __future__ import annotations

import logging
import os
from typing import Optional, Tuple

import torch
from torch import nn

from sglang.srt.environ import envs
from sglang.srt.eplb.expert_distribution import (
    get_global_expert_distribution_recorder,
)
from sglang.srt.eplb.expert_location_dispatch import (
    ExpertLocationDispatchInfo,
    topk_ids_logical_to_physical,
)
from sglang.srt.layers.moe.topk import (
    _RENORMALIZE_SUM_EPSILON,
    StandardTopKOutput,
    TopKConfig,
    _mask_topk_ids_padded_region,
    _zero_topk_weights_padded_region,
    remap_topk_for_per_rank_shared_slots,
)
from sglang.srt.layers.moe.utils import has_per_rank_fused_shared_slots
from sglang.srt.managers.schedule_batch import MM_PAD_SHIFT_VALUE
from sglang.srt.runtime_context import get_exec
from sglang.srt.utils import is_hip, is_npu, is_xpu

logger = logging.getLogger(__name__)

_bias_vl_route_logged = [False]

_is_hip = is_hip()
_is_npu = is_npu()
_is_xpu = is_xpu()

# ── MM-TRANSIENT 件1：bias_vl torch 回退路径的 mm 批行分块预算 =================
# 法源 docs/taskcards/MM-TRANSIENT-WINCARD-20261006.md §二.件1（OPEN-23 裁定二
# 引擎侧落点；overlay 28 件影子挂载形态，本文件=hash_topk.py 的件1 补丁形）。
#
# 新族键（行数形；卡原文字节形 DSV41_MM_TOPK_ROW_BUDGET_BYTES=4MiB —— 按
# [rows,256]×4B 换算即 4096 行，本件直接以行数入键，语义同卡定值）。禁复用
# sparse_wire 的 DSV41_DENSE_INDEXER_LOGITS_BUDGET_BYTES（128MiB 宽度=150k 级
# indexer 打分面；对 [rows,256] 面换算 131,072 行>任何批（max_prefill 16,384）
# ⇒ 永不触发，故同族另立新键）。
#
# 取值：正整数=每块最大行数（缺省 4096，与 chunked_prefill_size 同数）；
# off/0/false/未设负数=整批 stock 逐字节；坏值=启动后首次调用即 ValueError
# （fail-closed，tl_segment FC 律同法）。
#
# 门控（防扩散律，卡 §二.件1.4）：仅 image_mask is not None（mm 批）且
# num_token>块行数时走分块；文本批路径零触碰。off 时与 stock 逐字节等。
#
# 位等（卡 §二.件1 等价性论证）：softplus/sqrt 逐元素；topk(dim=-1) 行内全宽
# （块划分不改变任何一行的 256 候选集与并列序）；tid2eid 查表、where/gather/
# renorm sum(dim=-1) 皆行内 ⇒ 每行输出逐位相等 ⇒ torch.equal by construction。
# 唯一位等破坏点=设备侧 counter-based RNG（torch.randint 的 offset 按 numel
# 取整进位，逐块调用跳值）⇒ randint 在分块循环之前整批单次预生成（hoist，
# [num_token] int32≈64KB@16k 行不可观；softplus/topk/gather 均不耗 RNG，故
# hoist 调用与 stock 调用处于同一 RNG 流位置 ⇒ 同值）。
MM_HASH_ROW_BUDGET_ENV = "DSV41_MM_HASH_ROW_BUDGET_ROWS"
DEFAULT_MM_HASH_ROW_BUDGET_ROWS = 4096   # 卡定 4MiB=4096 行×256×4B
_MM_ROW_BUDGET_OFF = ("off", "0", "", "false")

# 横幅/观测面（worker 日志可核；harness 断言用）
_mm_hash_rowchunk_logged = [False]
MM_HASH_ROWCHUNK_STATS = {
    "batch_calls": 0,      # _forward_torch 总调用
    "chunked_calls": 0,    # 走分块路径的调用
    "chunks": 0,           # 累计块数
    "rows_peak": 0,        # 见过的最大批行数
}


def mm_hash_row_budget_rows() -> Optional[int]:
    """每块最大行数；None=整批（stock）。每次调用现读 env（无缓存，便于键控
    A/B；getenv 开销相对 topk 路径不可观）。"""
    raw = os.environ.get(MM_HASH_ROW_BUDGET_ENV)
    if raw is None:
        return DEFAULT_MM_HASH_ROW_BUDGET_ROWS
    r = raw.strip().lower()
    if r in _MM_ROW_BUDGET_OFF:
        return None
    try:
        val = int(float(r))
    except ValueError as e:
        raise ValueError(
            f"{MM_HASH_ROW_BUDGET_ENV}={raw!r} 无法解析为行数；"
            f"合法值=正整数或 off/0（缺省 {DEFAULT_MM_HASH_ROW_BUDGET_ROWS}）"
        ) from e
    if val < 0:
        raise ValueError(
            f"{MM_HASH_ROW_BUDGET_ENV}={raw!r} 为负；合法值=正整数或 off/0"
        )
    return val


class HashTopK(nn.Module):
    def __init__(
        self,
        topk,
        num_experts,
        num_fused_shared_experts,
        vocab_size,
        scoring_func="sqrtsoftplus",
        routed_scaling_factor=1.5,
        apply_routed_scaling_factor_on_output=False,
        layer_id: Optional[int] = None,
        bias_vl: Optional[torch.Tensor] = None,
    ):
        super().__init__()
        self.layer_id = layer_id
        # DeepSeek-V4-Vision only: image tokens bypass the tid2eid hash table
        # and are selected by (scores + bias_vl). Reference to the gate's
        # parameter (not a submodule); None keeps text-only behavior exact.
        # object.__setattr__ because plain assignment would auto-register the
        # shared tensor as mlp.topk.bias_vl, duplicating mlp.gate.bias_vl in
        # named_parameters and tripping name-based weight audits.
        object.__setattr__(self, "bias_vl", bias_vl)

        self.enable_waterfill = (
            num_fused_shared_experts > 0 and get_exec().moe.enable_waterfill
        )
        self.waterfill_balancer = None

        if self.enable_waterfill:
            # Waterfill appends the shared expert after EPLB maps routed IDs.
            topk -= num_fused_shared_experts
            num_fused_shared_experts = 0

        self.num_experts = num_experts
        self.topk = topk
        self.routed_scaling_factor = routed_scaling_factor
        self.num_fused_shared_experts = num_fused_shared_experts
        self.score_func = scoring_func
        self.tid2eid = nn.Parameter(
            torch.empty(vocab_size, topk - num_fused_shared_experts, dtype=torch.int32),
            requires_grad=False,
        )
        self._init_default_tid2eid()

        self.apply_routed_scaling_factor_on_output = (
            apply_routed_scaling_factor_on_output
        )
        if apply_routed_scaling_factor_on_output and num_fused_shared_experts > 0:
            raise NotImplementedError(
                "HashTopK + apply_routed_scaling_factor_on_output is not supported "
                "with fused shared experts; pass --disable-shared-experts-fusion."
            )

    def _init_default_tid2eid(self) -> None:
        topk = self.tid2eid.shape[1]
        if topk == 0:
            return

        # DummyModelLoader only initializes floating tensors, so keep this int
        # lookup table valid until real checkpoints overwrite it.
        token_ids = torch.arange(
            self.tid2eid.shape[0], dtype=self.tid2eid.dtype, device=self.tid2eid.device
        ).unsqueeze(1)
        expert_offsets = torch.arange(
            topk, dtype=self.tid2eid.dtype, device=self.tid2eid.device
        ).unsqueeze(0)
        tid2eid = (token_ids + expert_offsets) % self.num_experts
        with torch.no_grad():
            self.tid2eid.copy_(tid2eid.to(self.tid2eid.dtype))

    def empty_topk_output(
        self, device: torch.device, *, layer_id: Optional[int] = None
    ):
        topk = self.topk - self.num_fused_shared_experts
        if layer_id is not None:
            from sglang.srt.eplb.lplb_solver import get_global_lplb_solver

            lplb_solver = get_global_lplb_solver(layer_id)
            if lplb_solver is not None:
                lplb_solver.solve(
                    torch.empty((0, topk), dtype=torch.int32, device=device)
                )
        topk_weights = torch.empty((0, topk), dtype=torch.float32, device=device)
        topk_ids = torch.full((0, topk), -1, dtype=torch.int32, device=device)
        router_logits = torch.empty((0, topk), dtype=torch.float32, device=device)
        topk_output = StandardTopKOutput(topk_weights, topk_ids, router_logits)
        if has_per_rank_fused_shared_slots(self.num_fused_shared_experts):
            n = self.num_fused_shared_experts
            topk_output = topk_output._replace(
                topk_ids=topk_output.topk_ids.new_empty(
                    (0, topk_output.topk_ids.shape[-1] + n)
                ),
                topk_weights=topk_output.topk_weights.new_empty(
                    (0, topk_output.topk_weights.shape[-1] + n)
                ),
            )
        return self._apply_waterfill(topk_output, num_tokens=0)

    def _apply_waterfill(
        self, topk_output: StandardTopKOutput, num_tokens: int
    ) -> StandardTopKOutput:
        if self.enable_waterfill and self.waterfill_balancer is None:
            raise RuntimeError(
                "Waterfill HashTopK must be prepared by ModelRunner before forward."
            )
        if self.waterfill_balancer is None:
            return topk_output
        return self.waterfill_balancer.expand_topk(topk_output, num_tokens)

    def _forward_torch(
        self,
        router_logits: torch.Tensor,
        input_ids: torch.Tensor,
        image_mask: Optional[torch.Tensor] = None,
    ) -> Tuple[torch.Tensor, torch.Tensor]:
        # MM-TRANSIENT 件1门：仅 mm 批（image_mask）且批行数超预算时行分块；
        # 其余（文本批/键 off/批不超）走下方 stock 全批体（逐字节零扰动）。
        chunk_rows = mm_hash_row_budget_rows()
        num_token_all = router_logits.shape[0]
        MM_HASH_ROWCHUNK_STATS["batch_calls"] += 1
        if num_token_all > MM_HASH_ROWCHUNK_STATS["rows_peak"]:
            MM_HASH_ROWCHUNK_STATS["rows_peak"] = num_token_all
        if (
            image_mask is not None
            and chunk_rows is not None
            and num_token_all > chunk_rows
        ):
            return self._forward_torch_rowchunk(
                router_logits, input_ids, image_mask, chunk_rows
            )

        if self.score_func == "softmax":
            scores = router_logits.softmax(dim=-1)
        elif self.score_func == "sigmoid":
            scores = router_logits.sigmoid()
        else:
            scores = torch.nn.functional.softplus(router_logits).sqrt()

        num_token = scores.shape[0]

        topk_ids = torch.zeros(
            (num_token, self.topk), dtype=torch.int32, device=scores.device
        )
        topk_weights = torch.zeros(
            (num_token, self.topk), dtype=scores.dtype, device=scores.device
        )

        n_routed = self.tid2eid.shape[1]
        vl_topk_ids = None
        if image_mask is not None:
            # Multimodal pad sentinels sit far out of vocab; clamp them to 0
            # before the tid2eid gather. Image rows are overwritten below with
            # the (scores + bias_vl) top-k, matching the reference gate.
            input_ids = torch.where(image_mask, 0, input_ids)
            vl_topk_ids = (
                (scores + self.bias_vl).topk(n_routed, dim=-1).indices.to(torch.int32)
            )
        routed_ids = self.tid2eid[input_ids]
        if vl_topk_ids is not None:
            routed_ids = torch.where(image_mask.unsqueeze(1), vl_topk_ids, routed_ids)

        if self.num_fused_shared_experts == 1:
            topk_ids[:, :-1] = routed_ids
            topk_weights[:, :-1] = scores.gather(1, topk_ids[:, :-1])

            if self.score_func != "softmax":
                topk_weights[:, :-1] /= (
                    topk_weights[:, :-1].sum(dim=-1, keepdim=True)
                    + _RENORMALIZE_SUM_EPSILON
                )

            topk_ids[:, -1] = torch.randint(
                low=self.num_experts,
                high=self.num_experts + self.num_fused_shared_experts,
                size=(num_token,),
                dtype=topk_ids.dtype,
                device=topk_ids.device,
            )

            topk_weights[:, -1] = (
                topk_weights[:, :-1].sum(dim=-1) / self.routed_scaling_factor
            )
        else:
            topk_ids[:, :] = routed_ids
            topk_weights[:, :] = scores.gather(1, topk_ids[:, :])
            if self.score_func != "softmax":
                topk_weights[:, :] /= (
                    topk_weights[:, :].sum(dim=-1, keepdim=True)
                    + _RENORMALIZE_SUM_EPSILON
                )

        return topk_weights, topk_ids

    def _forward_torch_rowchunk(
        self,
        router_logits: torch.Tensor,
        input_ids: torch.Tensor,
        image_mask: torch.Tensor,
        chunk_rows: int,
    ) -> Tuple[torch.Tensor, torch.Tensor]:
        """MM-TRANSIENT 件1：bias_vl mm 批的行分块流水（位等 by construction）。

        与 stock 全批体逐算子同构，仅行维切窗：块内瞬态=[C,256]×4B；输出预分配
        [num_token,topk] 同形。randint 在循环前整批单次预生成（hoist）——设备侧
        counter-based RNG 的 offset 按 numel 取整进位、逐块调用跳值（唯一位等
        破坏点），hoist 后与 stock 的单次 [num_token] 调用同流同值。"""
        num_token = router_logits.shape[0]
        device = router_logits.device

        if not _mm_hash_rowchunk_logged[0]:
            _mm_hash_rowchunk_logged[0] = True
            logger.info(
                "MM-TRANSIENT 件1: hash bias_vl torch 路径行分块激活 "
                "(%s=%d 行/块, 本批 %d 行, %d 块); off/0=整批 stock",
                MM_HASH_ROW_BUDGET_ENV,
                chunk_rows,
                num_token,
                (num_token + chunk_rows - 1) // chunk_rows,
            )
        MM_HASH_ROWCHUNK_STATS["chunked_calls"] += 1
        MM_HASH_ROWCHUNK_STATS["chunks"] += (num_token + chunk_rows - 1) // chunk_rows

        # RNG hoist：整批单次预生成（==1 分支专用；else 分支无 RNG）。
        # softplus/topk/gather/where 均不消耗 RNG ⇒ 此调用与 stock 路径中
        # randint 调用处于同一流位置 ⇒ 逐值相同。
        shared_rand = None
        if self.num_fused_shared_experts == 1:
            shared_rand = torch.randint(
                low=self.num_experts,
                high=self.num_experts + self.num_fused_shared_experts,
                size=(num_token,),
                dtype=torch.int32,
                device=device,
            )

        # 输出预分配（形状/dtype/device 与 stock 全批体一致）
        topk_ids = torch.zeros((num_token, self.topk), dtype=torch.int32, device=device)
        topk_weights = torch.zeros(
            (num_token, self.topk), dtype=router_logits.dtype, device=device
        )

        n_routed = self.tid2eid.shape[1]
        for s in range(0, num_token, chunk_rows):
            e = min(s + chunk_rows, num_token)
            logits = router_logits[s:e]
            if self.score_func == "softmax":
                scores = logits.softmax(dim=-1)
            elif self.score_func == "sigmoid":
                scores = logits.sigmoid()
            else:
                scores = torch.nn.functional.softplus(logits).sqrt()

            ids = torch.where(image_mask[s:e], 0, input_ids[s:e])
            vl_topk_ids = (
                (scores + self.bias_vl).topk(n_routed, dim=-1).indices.to(torch.int32)
            )
            routed_ids = self.tid2eid[ids]
            routed_ids = torch.where(
                image_mask[s:e].unsqueeze(1), vl_topk_ids, routed_ids
            )

            c_ids = topk_ids[s:e]
            c_weights = topk_weights[s:e]
            if self.num_fused_shared_experts == 1:
                c_ids[:, :-1] = routed_ids
                c_weights[:, :-1] = scores.gather(1, c_ids[:, :-1])

                if self.score_func != "softmax":
                    c_weights[:, :-1] /= (
                        c_weights[:, :-1].sum(dim=-1, keepdim=True)
                        + _RENORMALIZE_SUM_EPSILON
                    )

                c_ids[:, -1] = shared_rand[s:e]

                c_weights[:, -1] = (
                    c_weights[:, :-1].sum(dim=-1) / self.routed_scaling_factor
                )
            else:
                c_ids[:, :] = routed_ids
                c_weights[:, :] = scores.gather(1, c_ids[:, :])
                if self.score_func != "softmax":
                    c_weights[:, :] /= (
                        c_weights[:, :].sum(dim=-1, keepdim=True)
                        + _RENORMALIZE_SUM_EPSILON
                    )

        return topk_weights, topk_ids

    def _forward_xpu(
        self, router_logits: torch.Tensor, input_ids: torch.Tensor
    ) -> Tuple[torch.Tensor, torch.Tensor]:
        # The XPU 'hash_topk' kernel currently supports the 'sqrtsoftplus' score func only.
        # Other score funcs fall back to the torch implementation; more will be supported in the future.
        if self.score_func == "sqrtsoftplus":
            from sgl_kernel import hash_topk

            num_tokens = router_logits.size(0)
            topk_routed = self.tid2eid.size(1)
            topk_fused = topk_routed + self.num_fused_shared_experts
            topk_ids = torch.empty(
                (num_tokens, topk_fused), dtype=torch.int32, device=router_logits.device
            )
            topk_weights = torch.empty(
                (num_tokens, topk_fused),
                dtype=torch.float32,
                device=router_logits.device,
            )
            hash_topk(
                router_logits,
                input_ids,
                self.tid2eid,
                topk_weights,
                topk_ids,
                self.routed_scaling_factor,
                self.score_func,
            )
            return topk_weights, topk_ids
        else:
            return self._forward_torch(router_logits, input_ids)

    def forward(
        self,
        hidden_states: torch.Tensor,
        router_logits: torch.Tensor,
        input_ids: torch.Tensor,
        num_token_non_padded: Optional[torch.Tensor] = None,
        expert_location_dispatch_info: Optional[ExpertLocationDispatchInfo] = None,
        image_mask: Optional[torch.Tensor] = None,
        skip_image_check: bool = False,
    ):
        assert input_ids.shape[0] == hidden_states.shape[0] == router_logits.shape[0], (
            f"{input_ids.shape=} {hidden_states.shape=} {router_logits.shape=}"
        )

        if (
            image_mask is None
            and self.bias_vl is not None
            and not skip_image_check
            and not torch.cuda.is_current_stream_capturing()
        ):
            # CUDA graph capture uses pad-free inputs and cannot synchronize .any().
            image_mask = input_ids >= MM_PAD_SHIFT_VALUE
            if not image_mask.any():
                image_mask = None

        if image_mask is not None:
            # The fused kernels know nothing about bias_vl and their tid2eid
            # gather would index out of vocab on pad sentinels.
            if not _bias_vl_route_logged[0]:
                _bias_vl_route_logged[0] = True
                logger.info(
                    "DSV4-Vision: routing image tokens with gate bias_vl (hash layer)."
                )
            topk_weights, topk_ids = self._forward_torch(
                router_logits, input_ids, image_mask=image_mask
            )
        elif _is_xpu:
            topk_weights, topk_ids = self._forward_xpu(router_logits, input_ids)
        elif envs.SGLANG_OPT_USE_FUSED_HASH_TOPK.get():
            from sglang.kernels.ops.moe.dsv4 import hash_topk

            topk_weights, topk_ids = hash_topk(
                router_logits=router_logits,
                input_ids=input_ids,
                tid2eid=self.tid2eid,
                num_fused_shared_experts=self.num_fused_shared_experts,
                routed_scaling_factor=self.routed_scaling_factor,
                scoring_func=self.score_func,
            )
        else:
            topk_weights, topk_ids = self._forward_torch(router_logits, input_ids)
        if _is_hip or _is_npu:
            topk_weights = topk_weights.to(torch.float32)

        if self.apply_routed_scaling_factor_on_output:
            topk_weights = topk_weights * self.routed_scaling_factor

        num_fused_shared_experts = self.num_fused_shared_experts
        log2phy_prob = None
        if (
            expert_location_dispatch_info is not None
            and expert_location_dispatch_info.ep_dispatch_algorithm == "lp"
        ):
            if self.layer_id is None:
                raise RuntimeError("HashTopK LP dispatch requires layer_id.")
            from sglang.srt.eplb.lplb_solver import get_global_lplb_solver

            lplb_solver = get_global_lplb_solver(self.layer_id)
            if lplb_solver is not None:
                log2phy_prob = lplb_solver.solve(topk_ids)

        recorder_topk_ids = None
        if has_per_rank_fused_shared_slots(num_fused_shared_experts):
            shared_cols = topk_ids[:, -num_fused_shared_experts:]
            routed_cols = topk_ids[:, :-num_fused_shared_experts]
            routed_cols = topk_ids_logical_to_physical(
                routed_cols, expert_location_dispatch_info, log2phy_prob
            )
            topk_ids = torch.cat([routed_cols, shared_cols], dim=-1)
            recorder_topk_ids = routed_cols

            num_physical_routed_experts = (
                expert_location_dispatch_info.num_physical_experts
                if expert_location_dispatch_info is not None
                else self.num_experts
            )
            topk_ids, topk_weights = remap_topk_for_per_rank_shared_slots(
                topk_ids,
                topk_weights,
                num_fused_shared_experts,
                num_physical_routed_experts,
                TopKConfig(
                    top_k=self.topk,
                    num_fused_shared_experts=num_fused_shared_experts,
                    routed_scaling_factor=self.routed_scaling_factor,
                ),
            )
        else:
            topk_ids = topk_ids_logical_to_physical(
                topk_ids, expert_location_dispatch_info, log2phy_prob
            )
        if is_hip():
            _zero_topk_weights_padded_region(topk_weights, num_token_non_padded)
        else:
            _mask_topk_ids_padded_region(topk_ids, num_token_non_padded)
            if recorder_topk_ids is not None:
                _mask_topk_ids_padded_region(recorder_topk_ids, num_token_non_padded)
        if recorder_topk_ids is None:
            recorder_topk_ids = topk_ids
        get_global_expert_distribution_recorder().on_select_experts(
            topk_ids=recorder_topk_ids
        )
        topk_output = StandardTopKOutput(
            topk_weights=topk_weights, topk_ids=topk_ids, router_logits=router_logits
        )
        topk_output = self._apply_waterfill(topk_output, hidden_states.shape[0])
        if is_hip():
            _zero_topk_weights_padded_region(
                topk_output.topk_weights, num_token_non_padded
            )
        return topk_output
