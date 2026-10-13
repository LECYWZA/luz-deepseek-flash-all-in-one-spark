# Copyright 2023-2024 SGLang Team
# Licensed under the Apache License, Version 2.0
"""Replicated DeepSeek-V4 ViT and aligner, matching inference/vision.py in
deepseek-ai/DeepSeek-V4-Flash-Vision-Exp. The wrapper applies the processor's
permutation and inserts sentinel embeddings after alignment.

MM-TRANSIENT 件2b（deepseek_v4_vit.py:98 锚）：SDPA 查询分块。法源
docs/taskcards/MM-TRANSIENT-WINCARD-20261006.md §二.件2(2a)——math 后端时
单图 3.4k patch 的 score 物化 [16 头,n_vit,n_vit]≈764MB/层，q 按块后上界
[16,C,n_vit]≈113MB（C=512）；k/v 保持全量（双向注意力语义，key 集合不变）。
查询行独立 ⇒ 数学等价必真；位级对拍分档（不等→数学等价声明+质量门接管，
两面分记，禁以 cat 面放行 SDPA 面）。env DSV41_MM_SDPA_QUERY_CHUNK：
正整数=每块查询行数（缺省 512）；0/off=整图 stock 逐字节。
"""

import logging
import os
from functools import lru_cache
from typing import Optional

import torch
import torch.nn.functional as F
from torch import nn
from transformers import PretrainedConfig

from sglang.srt.layers.linear import ReplicatedLinear
from sglang.srt.utils import add_prefix

# ── MM-TRANSIENT 件2b 键面 ────────────────────────────────────────────────────
MM_SDPA_QUERY_CHUNK_ENV = "DSV41_MM_SDPA_QUERY_CHUNK"
DEFAULT_MM_SDPA_QUERY_CHUNK = 512    # 卡定缺省：16×512×3456×4B≈113MB/层上界
_MM_SDPA_OFF = ("off", "0", "", "false")

# 横幅/观测面（harness 断言与 worker 日志核对用）
_mm_sdpa_chunk_logged = [False]
MM_SDPA_CHUNK_STATS = {
    "calls": 0,           # 进入 _mm_sdpa_attention 的调用数
    "chunked_calls": 0,   # 走分块路径的调用数
    "sdpa_launches": 0,   # 实际 F.scaled_dot_product_attention 次数（分块后累计）
    "n_peak": 0,          # 见过的最大 n（查询行数）
}


def mm_sdpa_query_chunk() -> Optional[int]:
    """每块查询行数；None=整图（stock）。现读 env 无缓存（键控 A/B 便于对拍）。"""
    raw = os.environ.get(MM_SDPA_QUERY_CHUNK_ENV)
    if raw is None:
        return DEFAULT_MM_SDPA_QUERY_CHUNK
    r = raw.strip().lower()
    if r in _MM_SDPA_OFF:
        return None
    try:
        val = int(float(r))
    except ValueError as e:
        raise ValueError(
            f"{MM_SDPA_QUERY_CHUNK_ENV}={raw!r} 无法解析为行数；"
            f"合法值=正整数或 off/0（缺省 {DEFAULT_MM_SDPA_QUERY_CHUNK}）"
        ) from e
    if val < 0:
        raise ValueError(
            f"{MM_SDPA_QUERY_CHUNK_ENV}={raw!r} 为负；合法值=正整数或 off/0"
        )
    return val


def _mm_sdpa_attention(
    q: torch.Tensor, k: torch.Tensor, v: torch.Tensor, n_heads: int, head_dim: int
) -> torch.Tensor:
    """stock：单次全量 SDPA；件2b：q 行分块循环，块写预分配 o=[n_heads,n,d]。

    q/k/v 形 [n, n_heads, head_dim]（stock forward 逐字约定）；
    返回 [n_heads, n, head_dim]（与 stock F.scaled_dot_product_attention
    (q.transpose(0,1), k.transpose(0,1), v.transpose(0,1)) 输出同构）。"""
    n = q.size(0)
    chunk = mm_sdpa_query_chunk()
    MM_SDPA_CHUNK_STATS["calls"] += 1
    if n > MM_SDPA_CHUNK_STATS["n_peak"]:
        MM_SDPA_CHUNK_STATS["n_peak"] = n

    if chunk is None or n <= chunk:
        MM_SDPA_CHUNK_STATS["sdpa_launches"] += 1
        return F.scaled_dot_product_attention(
            q.transpose(0, 1), k.transpose(0, 1), v.transpose(0, 1)
        )

    if not _mm_sdpa_chunk_logged[0]:
        _mm_sdpa_chunk_logged[0] = True
        logger = logging.getLogger(__name__)
        logger.info(
            "MM-TRANSIENT 件2b: 视觉塔 SDPA 查询分块激活 "
            "(%s=%d 行/块, 本图 n=%d, %d 块); off/0=整图 stock",
            MM_SDPA_QUERY_CHUNK_ENV,
            chunk,
            n,
            (n + chunk - 1) // chunk,
        )
    MM_SDPA_CHUNK_STATS["chunked_calls"] += 1
    MM_SDPA_CHUNK_STATS["sdpa_launches"] += (n + chunk - 1) // chunk

    kt = k.transpose(0, 1)
    vt = v.transpose(0, 1)
    o = torch.empty(
        (n_heads, n, head_dim), dtype=q.dtype, device=q.device
    )
    for s in range(0, n, chunk):
        e = min(s + chunk, n)
        o[:, s:e] = F.scaled_dot_product_attention(
            q[s:e].transpose(0, 1), kt, vt
        )
    return o


# torch logging 兼容（_mm_sdpa_attention 横幅用；模块顶层避免多余 handler）
import logging  # noqa: E402


@lru_cache(16)
def get_vision_cos_sin(
    n_h: int, n_w: int, dim: int, theta: float, device: torch.device
):
    """2D RoPE cos/sin tables for an n_h x n_w patch grid, fp32."""
    inv_freq = 1.0 / (theta ** (torch.arange(0, dim, 2, dtype=torch.float32) / dim))
    hpos = torch.arange(n_h).unsqueeze(1).expand(n_h, n_w)
    wpos = torch.arange(n_w).unsqueeze(0).expand(n_h, n_w)
    freqs = torch.stack([hpos, wpos], dim=-1).reshape(-1, 2, 1).float() * inv_freq
    freqs = freqs.flatten(1)
    return freqs.cos().unsqueeze(1).to(device), freqs.sin().unsqueeze(1).to(device)


def apply_vision_rotary(
    x: torch.Tensor, cos: torch.Tensor, sin: torch.Tensor
) -> torch.Tensor:
    dtype = x.dtype
    x1, x2 = x.float().chunk(2, dim=-1)
    return torch.cat([x1 * cos - x2 * sin, x2 * cos + x1 * sin], dim=-1).to(dtype)


class DeepseekV4VisionRMSNorm(nn.Module):
    """RMSNorm computed in fp32 with an fp32 weight, matching the reference."""

    def __init__(self, dim: int, eps: float = 1e-6):
        super().__init__()
        self.eps = eps
        self.weight = nn.Parameter(torch.ones(dim, dtype=torch.float32))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        dtype = x.dtype
        x = x.float()
        x = x * torch.rsqrt(x.square().mean(-1, keepdim=True) + self.eps)
        return (self.weight * x).to(dtype)


class DeepseekV4VisionPatchEmbed(nn.Module):
    def __init__(self, config: PretrainedConfig, prefix: str = ""):
        super().__init__()
        patch_size = config.vision_patch_size
        self.proj = ReplicatedLinear(
            3 * patch_size**2,
            config.vision_dim,
            bias=True,
            quant_config=None,
            prefix=add_prefix("proj", prefix),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: [n_patches, 3, p, p] -> [n_patches, vision_dim]
        out, _ = self.proj(x.flatten(1))
        return out


class DeepseekV4VisionAttention(nn.Module):
    def __init__(self, config: PretrainedConfig, prefix: str = ""):
        super().__init__()
        dim = config.vision_dim
        self.n_heads = config.vision_n_heads
        self.head_dim = dim // self.n_heads
        self.wqkv = ReplicatedLinear(
            dim,
            3 * dim,
            bias=True,
            quant_config=None,
            prefix=add_prefix("wqkv", prefix),
        )
        self.wo = ReplicatedLinear(
            dim, dim, bias=True, quant_config=None, prefix=add_prefix("wo", prefix)
        )

    def forward(
        self, x: torch.Tensor, cos: torch.Tensor, sin: torch.Tensor
    ) -> torch.Tensor:
        n = x.size(0)
        qkv, _ = self.wqkv(x)
        q, k, v = (t.view(n, self.n_heads, self.head_dim) for t in qkv.chunk(3, dim=-1))
        q = apply_vision_rotary(q, cos, sin)
        k = apply_vision_rotary(k, cos, sin)
        # MM-TRANSIENT 件2b：q 行分块过 SDPA（k/v 全量；0/off 或 n<=块=stock
        # 单次调用逐字节）。RMSNorm/wqkv/MLP 逐行算子工作区线性于 n，不分块。
        o = _mm_sdpa_attention(q, k, v, self.n_heads, self.head_dim)
        out, _ = self.wo(o.transpose(0, 1).reshape(n, -1))
        return out


class DeepseekV4VisionMLP(nn.Module):
    def __init__(self, config: PretrainedConfig, prefix: str = ""):
        super().__init__()
        self.w1 = ReplicatedLinear(
            config.vision_dim,
            2 * config.vision_inter_dim,
            bias=False,
            quant_config=None,
            prefix=add_prefix("w1", prefix),
        )
        self.w2 = ReplicatedLinear(
            config.vision_inter_dim,
            config.vision_dim,
            bias=False,
            quant_config=None,
            prefix=add_prefix("w2", prefix),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        gate_up, _ = self.w1(x)
        gate, up = gate_up.chunk(2, dim=-1)
        out, _ = self.w2(F.silu(gate) * up)
        return out


class DeepseekV4VisionBlock(nn.Module):
    def __init__(self, config: PretrainedConfig, prefix: str = ""):
        super().__init__()
        dim = config.vision_dim
        self.norm1 = DeepseekV4VisionRMSNorm(dim)
        self.attn = DeepseekV4VisionAttention(config, prefix=add_prefix("attn", prefix))
        self.norm2 = DeepseekV4VisionRMSNorm(dim)
        self.mlp = DeepseekV4VisionMLP(config, prefix=add_prefix("mlp", prefix))

    def forward(
        self, x: torch.Tensor, cos: torch.Tensor, sin: torch.Tensor
    ) -> torch.Tensor:
        x = x + self.attn(self.norm1(x), cos, sin)
        return x + self.mlp(self.norm2(x))


class DeepseekV4VisionTower(nn.Module):
    """DeepSeek-V4 ViT: full bidirectional attention over one image with 2D RoPE.

    Maps to the `vision.*` weights in the HF checkpoint.
    """

    def __init__(self, config: PretrainedConfig, prefix: str = ""):
        super().__init__()
        self.n_heads = config.vision_n_heads
        self.rope_dim = config.vision_dim // config.vision_n_heads // 2
        self.rope_theta = config.vision_rope_theta
        self.patch_embed = DeepseekV4VisionPatchEmbed(
            config, prefix=add_prefix("patch_embed", prefix)
        )
        self.blocks = nn.ModuleList(
            DeepseekV4VisionBlock(config, prefix=add_prefix(f"blocks.{i}", prefix))
            for i in range(config.vision_n_layers)
        )
        self.norm = DeepseekV4VisionRMSNorm(config.vision_dim)

    def forward(self, patches: torch.Tensor, n_h: int, n_w: int) -> torch.Tensor:
        x = self.patch_embed(patches)
        cos, sin = get_vision_cos_sin(
            n_h, n_w, self.rope_dim, self.rope_theta, x.device
        )
        for block in self.blocks:
            x = block(x, cos, sin)
        return self.norm(x)


class DeepseekV4VisionAligner(nn.Module):
    """Pixel-unshuffle (3x3) + 2-layer GELU projector to the LLM hidden size.

    Maps to the `aligner.*` weights in the HF checkpoint.
    """

    def __init__(self, config: PretrainedConfig, prefix: str = ""):
        super().__init__()
        self.downsample_ratio = config.vision_downsample_ratio
        in_dim = config.vision_dim * self.downsample_ratio**2
        self.w1 = ReplicatedLinear(
            in_dim,
            config.hidden_size,
            bias=True,
            quant_config=None,
            prefix=add_prefix("w1", prefix),
        )
        self.w2 = ReplicatedLinear(
            config.hidden_size,
            config.hidden_size,
            bias=True,
            quant_config=None,
            prefix=add_prefix("w2", prefix),
        )

    def forward(self, x: torch.Tensor, n_h: int, n_w: int) -> torch.Tensor:
        r = self.downsample_ratio
        x = x.view(n_h, n_w, -1).permute(2, 0, 1)
        x = F.pad(x, (0, -n_w % r, 0, -n_h % r))
        x = F.unfold(x.unsqueeze(0), r, stride=r).squeeze(0).transpose(0, 1)
        h, _ = self.w1(x)
        out, _ = self.w2(F.gelu(h))
        return out


class DeepseekV4VisionEncoder(nn.Module):
    """Convenience wrapper: ViT + aligner, one call per image.

    Returns aligner outputs in row-major grid order ([n_llm_tokens, hidden]).
    The caller applies the `perm` reordering and merges with the learned
    image sentinel embeddings on the language-model side.
    """

    def __init__(self, config: PretrainedConfig, prefix: str = ""):
        super().__init__()
        self.vision = DeepseekV4VisionTower(config, prefix=add_prefix("vision", prefix))
        self.aligner = DeepseekV4VisionAligner(
            config, prefix=add_prefix("aligner", prefix)
        )

    def forward(
        self, patches: torch.Tensor, n_vit_h: int, n_vit_w: int
    ) -> torch.Tensor:
        return self.aligner(self.vision(patches, n_vit_h, n_vit_w), n_vit_h, n_vit_w)

    # alias matching the reference model's naming
    def encode_image(
        self, patches: torch.Tensor, n_vit_h: int, n_vit_w: int
    ) -> torch.Tensor:
        return self.forward(patches, n_vit_h, n_vit_w)
