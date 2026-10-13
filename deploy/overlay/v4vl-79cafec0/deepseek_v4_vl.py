# Copyright 2023-2024 SGLang Team
# Licensed under the Apache License, Version 2.0
"""DeepSeek-V4 vision wrapper; text checkpoints use the same registry entry.

The processor supplies sentinel types and the aligner permutation for each image.

MM-TRANSIENT 件2a（deepseek_v4_vl.py:108 锚）：`torch.cat(features)` 改逐图
流式写入。法源 docs/taskcards/MM-TRANSIENT-WINCARD-20261006.md §二.件2(2b)：
cat 版峰值持有「features 列表全量+cat 输出」（2×）→流式版仅输出（1×）。
cat 语义=分配 [sum,hidden] 连续缓冲+逐源拷贝（零算术）；预分配+逐块 slice
赋值=同一批拷贝、同一目标形状与字节内容（Σblock_len=sum 无重叠铺满）⇒
**字节恒等**，torch.equal 可验。env DSV41_MM_STREAM_CAT：缺省 on；
off/0/false=回退 stock cat 形（逐字节零扰动）。
注记：深因卡 §6.1 建议的 `:95 H2D 后 item.feature=None 释宿主引用` **未随本件
落地**——retract 重排/stock 跨 chunk 图 span 分裂时同图二次 encode 再访
item.feature（enable_mm_global_cache=False 缺省，mm_schedule.py:525 面无跨
chunk 缓存），释放宿主引用会破该语义；待件3（图边界切 chunk）读数立住后另案。
"""

import logging
import os
from typing import Iterable, List, Optional, Tuple

import torch
from torch import nn

from sglang.srt.managers.mm_utils import (
    MultiModalityDataPaddingPatternMultimodalTokens,
    general_mm_embed_routine,
)
from sglang.srt.managers.schedule_batch import (
    Modality,
    MultimodalDataItem,
    MultimodalInputs,
)
from sglang.srt.model_executor.forward_batch_info import ForwardBatch, PPProxyTensors
from sglang.srt.model_loader.weight_utils import default_weight_loader
from sglang.srt.models.deepseek_v4 import DeepseekV4ForCausalLM as _DeepseekV4TextLM
from sglang.srt.models.deepseek_v4_vit import (
    DeepseekV4VisionAligner,
    DeepseekV4VisionTower,
)
from sglang.srt.utils import add_prefix

# Sentinel type ids, matching the reference image_processor.py and
# multimodal/processors/deepseek_v4_vl.py.
IMAGE_START, IMAGE_PAD, IMAGE, IMAGE_NEW_LINE, IMAGE_END = range(5)

# ── MM-TRANSIENT 件2a 键面 ────────────────────────────────────────────────────
MM_STREAM_CAT_ENV = "DSV41_MM_STREAM_CAT"
_MM_STREAM_CAT_OFF = ("off", "0", "", "false")
_mm_stream_cat_logged = [False]
MM_STREAM_CAT_STATS = {
    "calls": 0,            # get_image_feature 调用数
    "streamed_calls": 0,   # 走流式写入的调用数
    "rows_peak": 0,        # 见过的最大 sum(block_len)
}


def mm_stream_cat_enabled() -> bool:
    """缺省 on（卡定）；off/0/false=回退 stock cat。现读 env 无缓存。"""
    raw = os.environ.get(MM_STREAM_CAT_ENV)
    if raw is None:
        return True
    return raw.strip().lower() not in _MM_STREAM_CAT_OFF


class DeepseekV4ForCausalLM(nn.Module):
    """Vision-capable DeepseekV4, registered for arch "DeepseekV4ForCausalLM"."""

    def __init__(
        self,
        config,
        quant_config=None,
        prefix: str = "",
    ) -> None:
        super().__init__()
        self.config = config
        self._vision_weights_loaded = False
        self.is_multimodal = getattr(config, "vision_n_layers", 0) > 0

        self.language_model = _DeepseekV4TextLM(
            config, quant_config, prefix=add_prefix("language_model", prefix)
        )

        if self.is_multimodal:
            self.vision = DeepseekV4VisionTower(
                config, prefix=add_prefix("vision", prefix)
            )
            self.aligner = DeepseekV4VisionAligner(
                config, prefix=add_prefix("aligner", prefix)
            )
            self.image_start = nn.Parameter(torch.empty(config.hidden_size))
            self.image_end = nn.Parameter(torch.empty(config.hidden_size))
            self.image_newline = nn.Parameter(torch.empty(config.hidden_size))
            self.image_pad = nn.Parameter(torch.empty(config.hidden_size))

    def pad_input_ids(self, input_ids: List[int], mm_inputs: MultimodalInputs):
        pattern = MultiModalityDataPaddingPatternMultimodalTokens()
        return pattern.pad_input_tokens(input_ids, mm_inputs)

    def get_image_feature(self, items: List[MultimodalDataItem]) -> torch.Tensor:
        """ViT + aligner + sentinel block assembly, one block per image item.

        Returns [sum(block_len), hidden] concatenated in item order, matching
        the placeholder spans the scheduler padded into input_ids.

        MM-TRANSIENT 件2a：mm_stream_cat_enabled() 时预分配
        [sum(len(types_i)), hidden] 逐图 slice 赋值（消 cat 第二副本，字节
        恒等）；off 时 stock features 列表+末尾 torch.cat（逐字保留）。"""
        assert self.is_multimodal
        device = self.image_start.device
        dtype = self.image_start.dtype
        # Order matters: index i of this stack is sentinel type id i; the IMAGE
        # slot (id 2) maps to image_pad and gets overwritten below.
        sentinel = torch.stack(
            [
                self.image_start,
                self.image_pad,
                self.image_pad,
                self.image_newline,
                self.image_end,
            ]
        )

        stream = mm_stream_cat_enabled() and len(items) > 0
        MM_STREAM_CAT_STATS["calls"] += 1
        if stream:
            MM_STREAM_CAT_STATS["streamed_calls"] += 1
            if not _mm_stream_cat_logged[0]:
                _mm_stream_cat_logged[0] = True
                logging.getLogger(__name__).info(
                    "MM-TRANSIENT 件2a: get_image_feature 逐图流式写入激活 "
                    "(%s=off 回退 stock cat); 本批 %d 图",
                    MM_STREAM_CAT_ENV,
                    len(items),
                )
            total = sum(len(it.model_specific_data["types"]) for it in items)
            if total > MM_STREAM_CAT_STATS["rows_peak"]:
                MM_STREAM_CAT_STATS["rows_peak"] = total
            out = torch.empty(
                (total, self.image_start.numel()), dtype=dtype, device=device
            )
            off = 0
        else:
            features = []

        for item in items:
            data = item.model_specific_data
            n_vit_h, n_vit_w = data["n_vit_h"], data["n_vit_w"]
            types = torch.tensor(data["types"], dtype=torch.int64, device=device)
            perm = torch.tensor(data["perm"], dtype=torch.int64, device=device)
            patches = item.feature.to(device=device, dtype=dtype)

            embeds = self.aligner(
                self.vision(patches, n_vit_h, n_vit_w), n_vit_h, n_vit_w
            )[perm]
            block = sentinel[types]
            image_mask = types == IMAGE
            assert embeds.size(0) == int(image_mask.sum()), (
                f"aligner produced {embeds.size(0)} tokens but the block has "
                f"{int(image_mask.sum())} IMAGE slots"
            )
            block[image_mask] = embeds
            if stream:
                # 逐图流式写入：块恰无重叠铺满 [sum,hidden]（Σblock_len=total）
                out[off : off + block.shape[0]] = block
                off += block.shape[0]
            else:
                features.append(block)

        if stream:
            assert off == total, (
                f"streamed {off} rows but预分配 {total}（types 账本与写入不一致）"
            )
            return out
        return torch.cat(features, dim=0)

    def forward(
        self,
        input_ids: torch.Tensor,
        positions: torch.Tensor,
        forward_batch: ForwardBatch,
        pp_proxy_tensors: Optional[PPProxyTensors] = None,
        **kwargs,
    ) -> torch.Tensor:
        if forward_batch.contains_mm_inputs():
            # Preserve pad IDs for MoE routing before embedding clamps them.
            forward_batch.dsv4_routing_input_ids = forward_batch.input_ids.clone()
        hidden_states = general_mm_embed_routine(
            input_ids=input_ids,
            forward_batch=forward_batch,
            language_model=self.language_model,
            data_embedding_funcs={
                Modality.IMAGE: self.get_image_feature,
            },
            positions=positions,
            pp_proxy_tensors=pp_proxy_tensors,
        )
        return hidden_states

    _SENTINEL_NAMES = ("image_start", "image_end", "image_newline", "image_pad")

    def load_weights(self, weights: Iterable[Tuple[str, torch.Tensor]]):
        params_dict = dict(self.named_parameters())
        loaded_vision_names = set()

        def llm_weights():
            for name, loaded_weight in weights:
                if (
                    name.startswith(("vision.", "aligner."))
                    or name in self._SENTINEL_NAMES
                ):
                    default_weight_loader(params_dict[name], loaded_weight)
                    loaded_vision_names.add(name)
                else:
                    yield name, loaded_weight

        self.language_model.load_weights(llm_weights())
        if self.is_multimodal and not self._vision_weights_loaded:
            # Check the complete checkpoint iterator, which can span many shards.
            # Later updates may contain only language-model weights.
            expected_vision = {
                name
                for name in params_dict
                if name.startswith(("vision.", "aligner."))
                or name in self._SENTINEL_NAMES
            }
            missing = sorted(expected_vision - loaded_vision_names)
            if missing:
                raise ValueError(
                    f"DeepSeek-V4-Vision checkpoint is missing {len(missing)} "
                    f"required vision weights: {missing}"
                )
            self._vision_weights_loaded = True

    def get_input_embeddings(self) -> nn.Module:
        return self.language_model.get_input_embeddings()

    @property
    def pp_group(self):
        return self.language_model.pp_group

    @property
    def lm_head(self):
        # DSpark's draft worker attaches the target's lm_head to the draft.
        return self.language_model.lm_head

    def set_dspark_layers_to_capture(self, layer_ids) -> None:
        # DSPARK aux-hidden capture is configured on the text model.
        self.language_model.set_dspark_layers_to_capture(layer_ids)

    # Class-level probes (hasattr(model_class, ...)) bypass instance
    # __getattr__, so these must exist on the wrapper class itself.
    @classmethod
    def shared_experts_fusion_disable_reason(cls, hf_config, quant_config):
        return _DeepseekV4TextLM.shared_experts_fusion_disable_reason(
            hf_config, quant_config
        )

    @classmethod
    def get_model_config_for_expert_location(cls, config):
        return _DeepseekV4TextLM.get_model_config_for_expert_location(config)

    def __getattr__(self, name: str):
        # Resolve registered modules first; delegate the text model's remaining API.
        try:
            return super().__getattr__(name)
        except AttributeError:
            language_model = super().__getattr__("language_model")
            return getattr(language_model, name)


EntryClass = [DeepseekV4ForCausalLM]
