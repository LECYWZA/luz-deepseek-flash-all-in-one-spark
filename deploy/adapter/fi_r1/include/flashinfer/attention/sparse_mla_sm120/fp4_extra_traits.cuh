// Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//
// R1-FP4KV fork addition (LuZ-0.3.1 W3): 288B V41_FP4 extra-pool direct read.
//
// This header is NEW fork code (not upstream flashinfer). It carries:
//   1. V41_FP4 pool layout constants (256B payload + 32B page-separate scales).
//   2. E2M1/E4M3 decode + per-64-tile E4M3xUE8M0 requant primitives that
//      replicate the in-service repack arithmetic bit-for-bit
//      (kv_fp4_repack.py:293-349 Triton kernel, md5 060be993):
//        decode     : cvt.rn.f16x2.e2m1x2 (fp4_decode_2 type)  -> f16 exact
//        group scale: cvt.rn.f16x2.e4m3x2 -> f32 (cvt_e4m3_to_f32_via_f16 type)
//        amax       : f32 abs-max over the 64 decoded values (exact values, no rounding)
//        ue8m0      : bit-trick on __fdiv_rn(max(amax,1e-4f), 448.0f)
//                     (IEEE RN division == tl.fdiv ieee_rounding=True; NOT '/' which
//                      -use_fast_math would turn into div.approx and break bit equality)
//        inv        : ((254-ue8m0)<<23) bitcast, exact power of two
//        requant    : cvt.rn.satfinite.e4m3x2.f32 (== Triton .to(float8e4nv))
//   3. io_fp4_gather_tile: IO-warp producer replacing io_gather_scales +
//      io_bulk_gather_tile for fp4 extra tiles. Loads 256B row + 32B scale
//      footer with LDG, requantizes in registers, STS the SAME smem form the
//      stock kernel consumes (E4M3 bytes at KV_SMEM_STRIDE=464 + 7xUE8M0+pad
//      footer in kv_scale_buf) -> math warps are untouched (V-A shape).
//      mbar completion flips from hardware tx-count to: IO-thread-group named
//      barrier -> __threadfence_block -> single mbarrier_arrive.
//   4. Rope direct-decode helpers for the two math-warp consumption points
//      (QK-rope prefetch + XV-rope load): E2M1 x E4M3 -> bf16, exact
//      (6-significant-bit products are exactly representable in bf16; same
//      rounding as the repack path's fp32 -> .to(bfloat16), so bit-equal).
//
// Law (design card R1-FP4KV-DESIGN-20261011.md sec 4.1, row 8 as amended by
// R1-FP4KV-DIFFLOC-20261011 F1): outputs of the fork kernel are bit-equal to
// the in-service repack+stock-kernel path because the smem bytes and rope
// bf16 bits are bit-equal per row — INCLUDING idx<0 rows, which are written
// as repack gate=0 zero rows (clamped slot-0 read, group scales gated by 0:
// every decoded value is sign-carrying +-0, amax 0 -> floor ue8m0, requant
// emits the exact 0x00/0x80 bytes the repack scratch holds), so their score
// q·0 = 0 joins the softmax denominator as the in-service phantom unit mass
// (denominator +2^0 per row) instead of being masked to -1e30; rows past
// extra_topk_length stay masked by the runtime-length mask, which is
// stock-symmetric in both paths.

#pragma once

#include "arch/barrier.cuh"
#include "arch/common.cuh"
#include "common/q_rope.cuh"
#include "model/kv_cache_traits.cuh"

namespace fp4_pool {
static constexpr int PAYLOAD_BYTES_PER_TOKEN = 256;   // 224 nope + 32 rope
static constexpr int SCALE_BYTES_PER_TOKEN = 32;
static constexpr int NOPE_PAYLOAD_BYTES = 224;        // KVCacheTraits<DSV4>::D_NOPE / 2
static constexpr int ROPE_PAYLOAD_BYTES = 32;         // D_ROPE / 2
static constexpr int SCALE_GROUP_SIZE = 16;           // values per E4M3 scale byte
static constexpr int ROPE_SCALE_BASE = 28;            // first rope group index
}  // namespace fp4_pool

// ---------------------------------------------------------------------------
// 2. Decode / requant primitives (instruction-level mirrors of the community
//    in-service primitives; intrinsics.py:4792 fp4_decode_2, :4541
//    cvt_e4m3_to_f32_via_f16, math.cuh:93-110 fp32_vec_to_e4m3 pack order).
// ---------------------------------------------------------------------------

// 1 fp4 byte -> f16x2 (low nibble -> low half). Exact (<=3 significant bits).
// PTX source must be a .b8 register (intrinsics.py:4792 fp4_decode_2 idiom:
// cvt.u8.u32 into a .b8 reg first; an "h"-constraint b16 mismatches ptxas).
__device__ __forceinline__ __half2 fp4_byte_to_f16x2(uint32_t byte) {
  uint32_t h2;
  asm("{\n"
      " .reg .b8 q;\n"
      " cvt.u8.u32 q, %1;\n"
      " cvt.rn.f16x2.e2m1x2 %0, q;\n"
      "}\n"
      : "=r"(h2)
      : "r"(byte));
  return *reinterpret_cast<__half2*>(&h2);
}

// 1 E4M3 byte -> f32 via the hw-native f16x2 round trip (exact: every finite
// e4m3fn value is exactly representable in f16). intrinsics.py:4541
// cvt_e4m3_to_f32_via_f16 idiom (.b16 reg from cvt.u16.u32).
__device__ __forceinline__ float fp4_e4m3_byte_to_f32(uint32_t byte) {
  uint32_t h2;
  asm("{\n"
      " .reg .b16 sf;\n"
      " cvt.u16.u32 sf, %1;\n"
      " cvt.rn.f16x2.e4m3x2 %0, sf;\n"
      "}\n"
      : "=r"(h2)
      : "r"(byte));
  __half2 h = *reinterpret_cast<__half2*>(&h2);
  return __low2float(h);  // the byte sits in the low half of the b16 source
}

// 2 f32 -> packed e4m3x2 pair (b16: v_lo -> low byte, v_hi -> high byte).
// math.cuh:101 operand order ("cvt ... lo, %2, %1", %1 = first f32 = low
// byte): first source -> high byte, second source -> low byte.
__device__ __forceinline__ uint16_t fp4_f32x2_to_e4m3x2(float v_lo, float v_hi) {
  uint16_t out;
  asm("{\n"
      " .reg .b16 p;\n"
      " cvt.rn.satfinite.e4m3x2.f32 p, %2, %1;\n"
      " mov.b16 %0, p;\n"
      "}\n"
      : "=h"(out)
      : "f"(v_lo), "f"(v_hi));
  return out;
}

// One fp4 payload byte -> one e4m3 byte pair after x scale and x inv.
// decode(lo,hi) -> f32 exact -> x inv (power of two, exact) -> satfinite RN.
__device__ __forceinline__ uint16_t fp4_requant_byte(uint32_t payload_byte, float sf,
                                                     float inv) {
  __half2 h2 = fp4_byte_to_f16x2(payload_byte);
  float lo = __low2float(h2) * sf;   // exact: <=6 significant bits
  float hi = __high2float(h2) * sf;  // exact
  return fp4_f32x2_to_e4m3x2(lo * inv, hi * inv);  // x inv exact (2^k)
}

// store.cuh replica of the per-64-tile scale (kv_fp4_repack.py:311-318).
// Returns (ue8m0 byte, reciprocal as f32).
__device__ __forceinline__ void fp4_tile_scale(float amax, uint8_t& ue8m0, float& inv) {
  // IEEE RN division on purpose: Triton's tl.fdiv(..., ieee_rounding=True) is
  // the oracle; plain '/' under -use_fast_math would be div.approx.
  const float scale_raw = __fdiv_rn(fmaxf(amax, 1e-4f), 448.0f);
  const uint32_t u = __float_as_uint(scale_raw);
  ue8m0 = (uint8_t)(((u >> 23) & 0xFF) + (((u & 0x7FFFFF) != 0) ? 1u : 0u));
  inv = __uint_as_float((254u - ue8m0) << 23);  // exact power of two
}

// ---------------------------------------------------------------------------
// 3. IO producer: fp4 extra pool -> stock-form KV smem + footer scale buf.
//    Job granularity: (row bi in [0,BI), nope tile t in [0,NUM_SCALES)) —
//    64*7 = 448 jobs over IO_THREADS = 128 threads (3.5 jobs/thread avg).
// ---------------------------------------------------------------------------
template <ModelType MT, int PAGE_BLOCK_SIZE>
__device__ __forceinline__ void io_fp4_gather_tile(
    uint8_t* kv_dst, uint8_t* scale_dst, const int32_t* indices,
    const uint8_t* __restrict__ pool, uint64_t* mbar, int io_tid, size_t stride_page) {
  using KV = KVCacheTraits<MT>;
  static_assert(!KV::SCALE_IN_KV_SMEM, "fp4 extra producer is DSV4-footer-form only");
  constexpr int PBS = PAGE_BLOCK_SIZE;

  for (int job = io_tid; job < BI * KV::NUM_SCALES; job += IO_THREADS) {
    const int bi = job / KV::NUM_SCALES;
    const int t = job % KV::NUM_SCALES;

    // R1-FP4KV F1 (DIFFLOC-20261011): idx<0 rows are written as repack
    // gate=0 zero rows (kv_fp4_repack.py:282-302 semantics): clamp the read
    // to slot 0 (repack :295 parity) and gate the group scale by 0 — code x
    // (sf x gate) is sign-carrying +-0 exactly like the repack value-level
    // (code x sf) x gate, amax -> 0 -> floor ue8m0, and requant emits the
    // same 0x00/0x80 payload bytes the repack scratch holds, so the score
    // q·0 = 0 joins the softmax denominator (unit phantom mass) for ANY -1
    // placement. gate=1.0 is an exact no-op (x·1 == x bitwise, finite sf).
    const int idx_raw = indices[bi];
    const float gate = (idx_raw >= 0) ? 1.0f : 0.0f;
    const int idx = (idx_raw >= 0) ? idx_raw : 0;
    const int page = idx / PBS;
    const int slot = idx % PBS;
    const uint8_t* prow =
        pool + (size_t)page * stride_page + (size_t)slot * fp4_pool::PAYLOAD_BYTES_PER_TOKEN;
    const uint8_t* srow = pool + (size_t)page * stride_page +
                          (size_t)(PBS * fp4_pool::PAYLOAD_BYTES_PER_TOKEN) +
                          (size_t)slot * fp4_pool::SCALE_BYTES_PER_TOKEN;
    const uint32_t* pw32 = reinterpret_cast<const uint32_t*>(prow + t * 32);
    const uint32_t sw = __ldg(reinterpret_cast<const uint32_t*>(srow + t * 4));

    // Pass 1: amax over the 64 exact values (fp max is order-independent).
    // Two-pass decode per the design card (sec 3.5): pass 1 keeps only ONE
    // accumulator register; the payload words are re-loaded in pass 2 (the
    // 32B line is L1-resident after pass 1, so DRAM traffic stays 288B/row)
    // instead of being held live, which is what keeps IO-warp reg pressure
    // inside the setmaxnreg.dec(32) budget (holding 8 live u32s spills 368B
    // to local memory).
    float amax = 0.f;
#pragma unroll
    for (int i = 0; i < 8; i++) {
      // u32 i holds payload bytes 4i..4i+3 == values 8i..8i+7 -> group i/2
      // (16 values per group = 2 words per group).
      const float sf = fp4_e4m3_byte_to_f32((sw >> (8 * (i >> 1))) & 0xFF) * gate;
      const uint32_t w = __ldg(pw32 + i);
#pragma unroll
      for (int j = 0; j < 4; j++) {
        const __half2 h2 = fp4_byte_to_f16x2((w >> (8 * j)) & 0xFF);
        amax = fmaxf(amax, fabsf(__low2float(h2) * sf));
        amax = fmaxf(amax, fabsf(__high2float(h2) * sf));
      }
    }
    uint8_t ue8m0;
    float inv;
    fp4_tile_scale(amax, ue8m0, inv);

    // Pass 2: requant and STS into the exact smem form the math warps read
    // (E4M3 bytes at KV_SMEM_STRIDE; tile t covers bytes [t*64, t*64+64)).
    uint8_t* dst = kv_dst + (size_t)bi * KV::KV_SMEM_STRIDE + t * 64;
#pragma unroll
    for (int i = 0; i < 8; i++) {
      const float sf = fp4_e4m3_byte_to_f32((sw >> (8 * (i >> 1))) & 0xFF) * gate;
      const uint32_t w = __ldg(pw32 + i);
      const uint16_t p0 = fp4_requant_byte(w & 0xFF, sf, inv);
      const uint16_t p1 = fp4_requant_byte((w >> 8) & 0xFF, sf, inv);
      const uint16_t p2 = fp4_requant_byte((w >> 16) & 0xFF, sf, inv);
      const uint16_t p3 = fp4_requant_byte(w >> 24, sf, inv);
      reinterpret_cast<uint32_t*>(dst + i * 8)[0] =
          (uint32_t)p0 | ((uint32_t)p1 << 16);
      reinterpret_cast<uint32_t*>(dst + i * 8)[1] =
          (uint32_t)p2 | ((uint32_t)p3 << 16);
    }
    // Footer: one UE8M0 per tile; byte 7 pad written by the t==0 job so the
    // smem scale row matches the repack scratch footer byte-for-byte.
    scale_dst[bi * KV::SCALE_BYTES_PER_TOKEN + t] = ue8m0;
    if (t == 0) scale_dst[bi * KV::SCALE_BYTES_PER_TOKEN + 7] = 0;
  }

  // Completion: the stock path's mbar phase flips on cp.async.bulk tx count;
  // this register path flips it with an IO-group barrier + fence + one arrive.
  // Barrier id 4 is unused by the stock kernel (1 = IO/math rendezvous,
  // 2 = math, 3 = init).
  bar_sync_t<4, IO_THREADS>();
  __threadfence_block();
  if (io_tid == 0) mbarrier_arrive(mbar);
}

// ---------------------------------------------------------------------------
// 4. Rope direct decode (math-warp consumption points).
// ---------------------------------------------------------------------------

// 1 fp4 byte x group scale -> packed bf16x2 (lo value -> low half).
// Round-trip exact: decode f16 exact, x sf exact (<=6 sig bits), RN into bf16
// of an exactly representable value == the repack path's .to(bfloat16).
__device__ __forceinline__ uint32_t fp4_rope_pair_to_bf16x2(uint32_t payload_byte, float sf) {
  const __half2 h2 = fp4_byte_to_f16x2(payload_byte);
  float lo = __low2float(h2) * sf;
  float hi = __high2float(h2) * sf;
  uint32_t out;
  asm("cvt.rn.bf16x2.f32 %0, %1, %2;" : "=r"(out) : "f"(hi), "f"(lo));
  return out;
}

// QK-rope prefetch: fp4-pool counterpart of q_rope.cuh prefetch_kv_rope.
// Thread/lane mapping is the stock one (tid = lane&3): pf.b[ks][0] covers
// elements ko+2*tid, ko+2*tid+1 (payload byte 224+ks*8+tid) and pf.b[ks][1]
// covers elements ko+8+2*tid, +1 (byte 224+ks*8+4+tid); both nibble pairs of
// a byte share the group 28+ks (repack :330-333 comment).
template <int PAGE_BLOCK_SIZE>
__device__ __forceinline__ KVRopePrefetch prefetch_kv_rope_fp4(
    const uint8_t* __restrict__ pool, int idx, size_t stride_page, int lane) {
  constexpr int PBS = PAGE_BLOCK_SIZE;
  // R1-FP4KV F1: idx<0 -> gated decode. The rope bf16 bits are the sign-
  // carrying +-0 image of the repack scratch gate=0 rope row ((code x rscale)
  // x gate, kv_fp4_repack.py:334-335), so the rope score term is exactly 0
  // (phantom unit mass) — NOT a clamped real read, NOT masked. gate=1.0 is a
  // bitwise no-op.
  const float gate = (idx >= 0) ? 1.0f : 0.0f;
  idx = (idx >= 0) ? idx : 0;  // clamp read (repack :295 parity)
  const int page = idx / PBS;
  const int slot = idx % PBS;
  const uint8_t* prow =
      pool + (size_t)page * stride_page + (size_t)slot * fp4_pool::PAYLOAD_BYTES_PER_TOKEN;
  const uint8_t* srow = pool + (size_t)page * stride_page +
                        (size_t)(PBS * fp4_pool::PAYLOAD_BYTES_PER_TOKEN) +
                        (size_t)slot * fp4_pool::SCALE_BYTES_PER_TOKEN;
  const int tid = lane & 3;
  KVRopePrefetch pf;
#pragma unroll
  for (int ks = 0; ks < N_ROPE_CHUNKS; ks++) {
    const float sf = fp4_e4m3_byte_to_f32(__ldg(srow + fp4_pool::ROPE_SCALE_BASE + ks)) * gate;
    pf.b[ks][0] = fp4_rope_pair_to_bf16x2(__ldg(prow + fp4_pool::NOPE_PAYLOAD_BYTES +
                                                ks * 8 + tid),
                                          sf);
    pf.b[ks][1] = fp4_rope_pair_to_bf16x2(__ldg(prow + fp4_pool::NOPE_PAYLOAD_BYTES +
                                                ks * 8 + 4 + tid),
                                          sf);
  }
  return pf;
}

// XV-rope loader: fp4-pool counterpart of the load_rope_v lambda in
// xv_rope_mma_mg (uint16 bf16 bits). R1-FP4KV F1: idx<0 -> gated decode —
// the bf16 bits are the sign-carrying +-0 image of the repack scratch
// gate=0 rope row (sign of the clamped slot-0 nibble), replacing the old
// constant +0 return so the B operand is byte-identical to the oracle leg.
template <int PAGE_BLOCK_SIZE>
__device__ __forceinline__ uint16_t load_rope_v_fp4(const uint8_t* __restrict__ pool, int idx,
                                                    size_t stride_page, int dim_n) {
  constexpr int PBS = PAGE_BLOCK_SIZE;
  const float gate = (idx >= 0) ? 1.0f : 0.0f;
  if (idx < 0) idx = 0;  // clamp read (repack :295 parity)
  const int page = idx / PBS;
  const int slot = idx % PBS;
  const uint8_t* prow =
      pool + (size_t)page * stride_page + (size_t)slot * fp4_pool::PAYLOAD_BYTES_PER_TOKEN;
  const uint8_t* srow = pool + (size_t)page * stride_page +
                        (size_t)(PBS * fp4_pool::PAYLOAD_BYTES_PER_TOKEN) +
                        (size_t)slot * fp4_pool::SCALE_BYTES_PER_TOKEN;
  const uint32_t byte =
      __ldg(prow + fp4_pool::NOPE_PAYLOAD_BYTES + (dim_n >> 1));
  const __half2 h2 = fp4_byte_to_f16x2(byte);
  const float nib = ((dim_n & 1) == 0) ? __low2float(h2) : __high2float(h2);
  const float sf =
      fp4_e4m3_byte_to_f32(__ldg(srow + fp4_pool::ROPE_SCALE_BASE + (dim_n >> 4))) * gate;
  const __nv_bfloat16 v = __float2bfloat16_rn(nib * sf);
  return *reinterpret_cast<const uint16_t*>(&v);
}

// XV rope via BF16 MMA, fp4-pool B operand: structural copy of
// xv_rope_mma_mg (xv_rope_mma.cuh:125-196) with the load_rope_v lambda swapped
// for load_rope_v_fp4. Weight staging (A operand) and the MMA loop are
// unchanged; the decoded rope bits equal the repack scratch's bf16 bytes
// (design card sec 4.1 #7), so outputs are bit-equal to the stock path.
template <int PAGE_BLOCK_SIZE, int N_HG>
__device__ __forceinline__ void xv_rope_mma_mg_fp4(float acc_rope[N_HG][4],
                                                   const float w_grp[N_HG][4],
                                                   const int32_t* __restrict__ tile_indices,
                                                   const uint8_t* __restrict__ pool, int mwarp,
                                                   int lane, size_t stride_page,
                                                   bf16* weight_smem) {
  const int gid = lane >> 2;
  const int tid = lane & 3;
  const int qk_nb = mwarp * ENTRIES_PER_WARP;
  constexpr int GROUP_STRIDE = HPB * BI;

#pragma unroll
  for (int g = 0; g < N_HG; g++) {
    bf16* group_weight = weight_smem + g * GROUP_STRIDE;
    group_weight[gid * BI + qk_nb + tid * 2] = __float2bfloat16(w_grp[g][0]);
    group_weight[gid * BI + qk_nb + tid * 2 + 1] = __float2bfloat16(w_grp[g][1]);
    group_weight[(gid + 8) * BI + qk_nb + tid * 2] = __float2bfloat16(w_grp[g][2]);
    group_weight[(gid + 8) * BI + qk_nb + tid * 2 + 1] = __float2bfloat16(w_grp[g][3]);
  }
  bar_sync_t<2, MATH_THREADS>();

  int n_start = mwarp * 8;
  int dim_n = n_start + gid;

  for (int ks = 0; ks < BI / 16; ks++) {
    int k_base = ks * 16;

    auto load_rope_v = [&](int entry_offset) -> uint16_t {
      int idx = tile_indices[entry_offset];
      return load_rope_v_fp4<PAGE_BLOCK_SIZE>(pool, idx, stride_page, dim_n);
    };

    uint16_t v0 = load_rope_v(k_base + tid * 2);
    uint16_t v1 = load_rope_v(k_base + tid * 2 + 1);
    uint16_t v8 = load_rope_v(k_base + tid * 2 + 8);
    uint16_t v9 = load_rope_v(k_base + tid * 2 + 9);

    uint32_t b0 = (uint32_t)v0 | ((uint32_t)v1 << 16);
    uint32_t b1 = (uint32_t)v8 | ((uint32_t)v9 << 16);

#pragma unroll
    for (int g = 0; g < N_HG; g++) {
      uint32_t a0, a1, a2, a3;
      ldmatrix_load_A_bf16(a0, a1, a2, a3, weight_smem + g * GROUP_STRIDE + k_base, BI, lane);
      MmaBf16Result r = mma_bf16_m16n8k16(a0, a1, a2, a3, b0, b1, acc_rope[g][0], acc_rope[g][1],
                                          acc_rope[g][2], acc_rope[g][3]);
      acc_rope[g][0] = r.d0;
      acc_rope[g][1] = r.d1;
      acc_rope[g][2] = r.d2;
      acc_rope[g][3] = r.d3;
    }
  }
}

