/* DSV4.1 fp4-KV -> V4 repack bridge, CUDA C++ port of the Triton kernel
 * _repack_fp4_to_v4_kernel in kv_fp4_repack.py (bit-exact by construction;
 * pinned byte-for-byte against the Triton reference by tests/test_repack_cuda.py).
 *
 * Per output row (grid rows = N = tokens*topk):
 *   idx = idx_i32[row]; idx < 0 -> zero row (gate=0, footer = amax floor path).
 *   src paging: page = loc >> page_bits, slot = loc & (2^page_bits - 1);
 *     data   at page*src_page_bytes + slot*256           (224+32 bytes used)
 *     scales at page*src_page_bytes + 2^page_bits*256 + slot*32 (e4m3 bytes)
 *   nope: 224 packed e2m1 bytes -> 448 values (7 V4 tiles of 64), dequant with
 *     per-16 e4m3 scales (byte/8), amax per 64-value tile, ue8m0 footer =
 *     biased exp of max(amax,1e-4)/448 (+1 if mantissa!=0), payload
 *     cvt.rn.satfinite.e4m3(value * 2^(127-ue8m0)), interleaved lo/hi bytes.
 *   rope: 32 packed bytes -> 64 values, scale group 28 + byte/8, bf16 RN,
 *     stored as interleaved bf16 pairs at row offset 448.
 *   footer: 7 ue8m0 + 1 zero pad byte at page 37440-byte grid, offset 36864.
 *
 * Bit-exactness notes (each pinned by the gate):
 *   - fp8 e4m3 -> f32 scale loads are exact (manual bit decode, no rounding).
 *   - e2m1 LUT keeps -0.0 for code 0x8 (sign bit preserved through multiplies).
 *   - scale_raw uses IEEE f32 division (nvcc default -prec-div=true; this file
 *     MUST be built without --use_fast_math).
 *   - e4m3 store is cvt.rn.satfinite via __nv_cvt_float_to_fp8, rope is bf16 RN
 *     via __float2bfloat16_rn; both round-nearest-even like the Triton casts.
 *   - all src/dst offsets are int64 (pools can exceed 2 GiB).
 *
 * Target: SM121 (GB10), CUDA 13.0, torch 2.13 extension ABI.
 */

#include <torch/extension.h>
#include <ATen/cuda/CUDAContext.h>
#include <cuda_fp8.h>
#include <cuda_bf16.h>

#include <cstdint>

namespace {

constexpr int64_t kSrcDataBytes = 256;   // e2m1 payload bytes per src slot
constexpr int64_t kSrcScaleBytes = 32;   // per-16 e4m3 scale bytes per src slot
constexpr int kNopeBytes = 224;          // packed nope bytes read per row
constexpr int kNopeValues = 448;         // dst byte offset of the rope region
constexpr int64_t kDstPageBytes = 37440; // 64 rows * (576 + 8) padded to 576
constexpr int64_t kDstDataStride = 576;  // 448 fp8 nope + 128 B bf16 rope
constexpr int64_t kDstScaleOff = 36864;  // 64 * 576: per-page footer block
constexpr int64_t kDstScaleStride = 8;   // 7 ue8m0 + 1 pad
constexpr int kLanesPerRow = 4;         // 8 rows per warp, one u64 load/lane/tile
constexpr int kWarpsPerBlock = 4;       // 128 threads, 32 rows per block

// Mirror of sglang _e2m1_code_to_fp32: bit 3 is the sign (a negated zero stays
// -0.0), bits 0-2 index {0, 0.5, 1, 1.5, 2, 3, 4, 6}. Exact bit construction,
// no rounding, no tables.
__device__ __forceinline__ float e2m1_to_f32(uint32_t code) {
  const uint32_t m = code & 7u;
  uint32_t mag;
  if (m <= 1u) {
    // e2m1 subnormals: 0 and 0.5 (no implicit leading 1).
    mag = (m == 0u) ? 0u : 0x3F000000u;
  } else {
    mag = ((((m >> 1) + 126u) << 23) | ((m & 1u) << 22));
  }
  return __uint_as_float(mag | ((code & 8u) << 28));
}

// Exact e4m3fn -> f32 (matches tl.load(fp8).to(tl.float32), which is exact):
// subnormals are m * 2^-9, max finite is 448, 0x7F/0xFF are NaN.
__device__ __forceinline__ float e4m3_to_f32(uint32_t b) {
  const uint32_t sign = (b & 0x80u) << 24;
  const uint32_t e = (b >> 3) & 0xFu;
  const uint32_t m = b & 0x7u;
  if (e == 0u) {
    // m * 2^-9 for m in [1,7] is exact in f32.
    return __uint_as_float(sign | (m ? __float_as_uint((float)m * 0x1p-9f) : 0u));
  }
  if ((e == 15u) && (m == 7u)) {  // e4m3fn NaN
    return __uint_as_float(sign | 0x7FC00000u);
  }
  return __uint_as_float(sign | ((e + 120u) << 23) | (m << 20));
}

__global__ void repack_fp4_to_v4_kernel(
    const uint8_t* __restrict__ src,      // flat uint8 pool base
    const int32_t* __restrict__ idx_ptr,  // (n,) slot ids, -1 -> zero row
    uint8_t* __restrict__ dst,            // (ceil(n/64), 37440) V4 scratch
    const int64_t src_page_bytes,
    const int src_page_bits,
    const int64_t n_rows) {
  constexpr int kRowsPerBlock = kWarpsPerBlock * 32 / kLanesPerRow;
  const int64_t row =
      (int64_t)blockIdx.x * kRowsPerBlock + (int64_t)(threadIdx.x / kLanesPerRow);
  if (row >= n_rows) return;
  const int lane = threadIdx.x % kLanesPerRow;  // lane within the 8-lane row group

  const int32_t idx = __ldg(idx_ptr + row);
  const bool valid = idx >= 0;
  const int64_t loc = valid ? (int64_t)idx : (int64_t)0;
  const int64_t src_page = loc >> src_page_bits;
  const int64_t src_slot = loc & ((int64_t(1) << src_page_bits) - 1);
  const int64_t src_base = src_page * src_page_bytes;  // int64 page stride
  const uint8_t* data_ptr =
      src + (src_base + src_slot * kSrcDataBytes);
  const uint8_t* scale_ptr =
      src + (src_base + ((int64_t(1) << src_page_bits) * kSrcDataBytes) +
             src_slot * kSrcScaleBytes);
  const float gate = valid ? 1.0f : 0.0f;

  const int64_t dst_page = row >> 6;
  const int dst_slot = (int)(row & 63);
  const int64_t dst_base =
      dst_page * kDstPageBytes + (int64_t)dst_slot * kDstDataStride;
  // This lane's 8 packed bytes start at byte 8*lane of every region; the 8
  // bytes lie in exactly one 8-byte source scale group (group = byte/8).
  uint4* dst128 = reinterpret_cast<uint4*>(dst + dst_base);

  // The row's 32 scale bytes are loaded once (words lane and 4+lane); tile t
  // needs word t, byte lane -> one group shfl + byte_perm instead of a
  // scattered byte load per tile (keeps the scale read to one sector).
  const uint32_t* scw32 = reinterpret_cast<const uint32_t*>(scale_ptr);
  const uint32_t scl0 = scw32[lane];
  const uint32_t scl1 = scw32[4 + lane];

  // Issue ALL of the row's 8 x 8-byte loads (7 nope tiles + rope) up front so
  // the warp has 8 loads in flight per lane (the long-scoreboard stall from a
  // tile-at-a-time chain cannot be hidden at 48 SMs); the compute passes then
  // run from registers. Decoded values are NOT kept live (re-decoded in the
  // second pass) to stay under 42 regs/thread = full SM121 occupancy.
  uint2 P[8];
#pragma unroll
  for (int t = 0; t < 8; ++t) {
    P[t] = reinterpret_cast<const uint2*>(data_ptr + 32 * t)[lane];
  }
  uint8_t foot[7];
#pragma unroll
  for (int t = 0; t < 7; ++t) {
    const uint2 p = P[t];
    const uint32_t scw = (t < 4)
        ? __shfl_sync(0xFFFFFFFFu, scl0, t, kLanesPerRow)
        : __shfl_sync(0xFFFFFFFFu, scl1, t - 4, kLanesPerRow);
    const float scale = e4m3_to_f32(__byte_perm(scw, 0, lane));
    float a = 0.0f;
#pragma unroll
    for (int k = 0; k < 8; ++k) {
      const uint32_t byte = ((k < 4 ? p.x : p.y) >> (8 * (k & 3))) & 0xFFu;
      a = fmaxf(a, fmaxf(fabsf(e2m1_to_f32(byte & 0xFu) * scale * gate),
                         fabsf(e2m1_to_f32(byte >> 4) * scale * gate)));
    }
#pragma unroll
    for (int off = kLanesPerRow / 2; off > 0; off >>= 1) {  // group amax, all lanes
      a = fmaxf(a, __shfl_xor_sync(0xFFFFFFFFu, a, off, kLanesPerRow));
    }
    // store.cuh arithmetic: IEEE f32 division (no fast-math, no reciprocal).
    const float scale_raw = fmaxf(a, 1e-4f) / 448.0f;
    const int32_t u = __float_as_int(scale_raw);
    const int32_t ue8m0 =
        ((u >> 23) & 0xFF) + (((u & 0x7FFFFF) != 0) ? 1 : 0);
    foot[t] = (uint8_t)ue8m0;
    const float inv = __int_as_float((254 - ue8m0) << 23);  // exact 2^k
    uint32_t w[4] = {0u, 0u, 0u, 0u};
#pragma unroll
    for (int k = 0; k < 8; ++k) {
      const uint32_t byte = ((k < 4 ? p.x : p.y) >> (8 * (k & 3))) & 0xFFu;
      const uint32_t plo = (uint8_t)__nv_cvt_float_to_fp8(
          e2m1_to_f32(byte & 0xFu) * scale * gate * inv, __NV_SATFINITE, __NV_E4M3);
      const uint32_t phi = (uint8_t)__nv_cvt_float_to_fp8(
          e2m1_to_f32(byte >> 4) * scale * gate * inv, __NV_SATFINITE, __NV_E4M3);
      w[k >> 1] |= (plo << (16 * (k & 1))) | (phi << (16 * (k & 1) + 8));
    }
    dst128[4 * t + lane] = make_uint4(w[0], w[1], w[2], w[3]);
  }

  // ---- rope: 32 packed bytes (P[7]) -> 64 bf16, 2 x uint4 per lane ----
  {
    const uint2 p = P[7];
    const float rscale = e4m3_to_f32(__byte_perm(
        __shfl_sync(0xFFFFFFFFu, scl1, 3, kLanesPerRow), 0, lane));
    uint4 w0, w1;
    uint16_t* bits0 = reinterpret_cast<uint16_t*>(&w0);
    uint16_t* bits1 = reinterpret_cast<uint16_t*>(&w1);
#pragma unroll
    for (int k = 0; k < 8; ++k) {
      const uint32_t byte = ((k < 4 ? p.x : p.y) >> (8 * (k & 3))) & 0xFFu;
      const float rlo = e2m1_to_f32(byte & 0xFu) * rscale * gate;
      const float rhi = e2m1_to_f32(byte >> 4) * rscale * gate;
      const uint16_t blo = __bfloat16_as_ushort(__float2bfloat16_rn(rlo));
      const uint16_t bhi = __bfloat16_as_ushort(__float2bfloat16_rn(rhi));
      if (k < 4) {
        bits0[2 * k] = blo;
        bits0[2 * k + 1] = bhi;
      } else {
        bits1[2 * (k - 4)] = blo;
        bits1[2 * (k - 4) + 1] = bhi;
      }
    }
    uint4* rp = reinterpret_cast<uint4*>(dst + dst_base + kNopeValues + 32 * lane);
    rp[0] = w0;
    rp[1] = w1;
  }

  // ---- footer: 7 ue8m0 + 1 zero pad (2 bytes per lane), per-page block ----
  {
    const uint16_t w = (uint16_t)(
        foot[2 * lane] |
        (uint16_t)((2 * lane + 1 < 7 ? foot[2 * lane + 1] : (uint8_t)0) << 8));
    *reinterpret_cast<uint16_t*>(
        dst + dst_page * kDstPageBytes + kDstScaleOff +
        dst_slot * kDstScaleStride + 2 * lane) = w;
  }
}

}  // namespace

void repack_fp4_to_v4(torch::Tensor src_u8,      // flat uint8 view of the pool
                      torch::Tensor src_fp8,     // same storage as e4m3 (parity)
                      torch::Tensor idx_i32,     // (n,) int32 contiguous
                      torch::Tensor dst_u8,      // (ceil(n/64), 37440) uint8
                      int64_t src_page_bytes,    // pool page byte stride
                      int64_t src_page_bits) {   // log2(tokens per pool page)
  TORCH_CHECK(src_u8.is_cuda() && src_fp8.is_cuda() && idx_i32.is_cuda() &&
                  dst_u8.is_cuda(),
              "repack_fp4_to_v4: all tensors must be CUDA");
  TORCH_CHECK(src_u8.scalar_type() == torch::kUInt8 && src_u8.is_contiguous(),
              "repack_fp4_to_v4: src_u8 must be contiguous uint8");
  TORCH_CHECK(src_fp8.element_size() == 1,
              "repack_fp4_to_v4: src_fp8 must be a 1-byte fp8 view of the pool");
  TORCH_CHECK(idx_i32.scalar_type() == torch::kInt32 && idx_i32.is_contiguous(),
              "repack_fp4_to_v4: idx must be contiguous int32");
  TORCH_CHECK(dst_u8.scalar_type() == torch::kUInt8 && dst_u8.is_contiguous(),
              "repack_fp4_to_v4: dst must be contiguous uint8");
  TORCH_CHECK(src_u8.device() == src_fp8.device() &&
                  src_u8.device() == idx_i32.device() &&
                  src_u8.device() == dst_u8.device(),
              "repack_fp4_to_v4: tensor devices must match");
  TORCH_CHECK(src_page_bits >= 1 && src_page_bits <= 16,
              "repack_fp4_to_v4: src_page_bits out of range");
  TORCH_CHECK(
      src_page_bytes >=
          ((int64_t)1 << src_page_bits) * (kSrcDataBytes + kSrcScaleBytes),
      "repack_fp4_to_v4: src_page_bytes smaller than the pool page payload");
  const int64_t n = idx_i32.numel();
  TORCH_CHECK(n > 0, "repack_fp4_to_v4: empty idx");
  const int64_t num_dst_pages = (n + 63) / 64;
  TORCH_CHECK(dst_u8.numel() >= num_dst_pages * kDstPageBytes,
              "repack_fp4_to_v4: dst smaller than ceil(n/64)*37440 bytes");

  constexpr int64_t kRowsPerBlock = kWarpsPerBlock * 32 / kLanesPerRow;
  const int64_t blocks = (n + kRowsPerBlock - 1) / kRowsPerBlock;
  repack_fp4_to_v4_kernel<<<(unsigned int)blocks, kWarpsPerBlock * 32, 0,
                            at::cuda::getCurrentCUDAStream()>>>(
      src_u8.data_ptr<uint8_t>(), idx_i32.data_ptr<int32_t>(),
      dst_u8.data_ptr<uint8_t>(), src_page_bytes, (int)src_page_bits, n);
}

PYBIND11_MODULE(TORCH_EXTENSION_NAME, m) {
  m.def("repack_fp4_to_v4", &repack_fp4_to_v4,
        "DSV4.1 fp4-KV -> V4 repack (bit-exact CUDA port of the Triton kernel)");
}
