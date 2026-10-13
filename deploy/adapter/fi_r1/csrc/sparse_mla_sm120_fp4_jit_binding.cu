// Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//
// R1-FP4KV fork: TVM-FFI binding for the fp4-extra sparse-MLA SM120 prefill.
// Self-contained entry (the stock jit binding file it replaces carried the
// decode-dsv4/dsv3_2 wrappers, whose objects are not part of this module).
//
// Differences from the stock SparseMlaSm120PagedAttention face
// (sparse_mla_sm120.cu:145, flashinfer 0.6.16):
//   - prefill-only: calls sparse_mla_prefill_dispatch (fork copy) directly.
//   - extra_kv_cache is REQUIRED and must be a 288B V41_FP4 pool view
//     [num_pages, pbs, 1, 288] (NHD) / [num_pages, pbs, 288] (3D);
//     pbs in {128, 256}; page stride must be 4B aligned (u32 LDG producer).
//   - extra_is_fp4=true is passed to the dispatcher (fp4 dual arm).

#include <cuda_bf16.h>
#include <cuda_runtime.h>
#include <flashinfer/attention/sparse_mla_sm120/model/model_type.h>

#include "tvm_ffi_utils.h"

using tvm::ffi::Optional;

namespace flashinfer::sparse_mla_sm120 {

using bf16 = __nv_bfloat16;

// Defined in sparse_mla_sm120_prefill_fp4.cu (this module's second TU).
bool sparse_mla_prefill_dispatch(ModelType mt, int num_heads, int topk, int page_block_size,
                                 int topk_extra, int extra_page_block_size, bool extra_is_fp4,
                                 const bf16* Q, const uint8_t* KV_cache, const int32_t* indices,
                                 const uint8_t* extra_KV_cache, const int32_t* extra_indices,
                                 bf16* output, float* out_lse, float sm_scale, int num_tokens,
                                 size_t stride_kv_block, size_t stride_kv_block_extra,
                                 const float* attn_sink, const int* topk_length,
                                 const int* extra_topk_length, cudaStream_t stream);

namespace {

struct PagedKVLayout {
  int page_block_size;
  size_t stride_kv_block;
};

// Byte-identical helper to sparse_mla_sm120.cu:97 parse_paged_kv_layout.
inline PagedKVLayout parse_paged_kv_layout(const TensorView& kv, int bpt, const char* name) {
  const size_t elem_bytes = static_cast<size_t>(kv.dtype().bits / 8);
  if (kv.ndim() == 2) {
    const size_t block_bytes = static_cast<size_t>(kv.size(1)) * elem_bytes;
    TVM_FFI_ICHECK_EQ(block_bytes % static_cast<size_t>(bpt), 0)
        << name << " 2D block width " << block_bytes
        << " is not divisible by bytes_per_token=" << bpt;
    return {static_cast<int>(block_bytes / static_cast<size_t>(bpt)), block_bytes};
  }
  if (kv.ndim() == 3) {
    TVM_FFI_ICHECK_EQ(kv.size(-1), bpt)
        << name << " 3D form must be [num_pages, page_block_size, " << bpt << "]";
    return {static_cast<int>(kv.size(1)), static_cast<size_t>(kv.stride(0)) * elem_bytes};
  }
  TVM_FFI_ICHECK_EQ(kv.ndim(), 4) << name << " must be 2D [num_pages, page_bytes], 3D "
                                  << "[num_pages, page_block_size, bytes_per_token], HND "
                                  << "[num_pages, 1, page_block_size, bytes_per_token], or NHD "
                                  << "[num_pages, page_block_size, 1, bytes_per_token]";
  TVM_FFI_ICHECK_EQ(kv.size(-1), bpt)
      << name << " last dim must be bytes_per_token=" << bpt << ", got " << kv.size(-1);
  if (kv.size(1) == 1) {
    return {static_cast<int>(kv.size(2)), static_cast<size_t>(kv.stride(0)) * elem_bytes};
  }
  if (kv.size(2) == 1) {
    return {static_cast<int>(kv.size(1)), static_cast<size_t>(kv.stride(0)) * elem_bytes};
  }
  TVM_FFI_ICHECK(false) << name << " 4D form must have singleton KV-head axis at dim 1 "
                        << "(HND) or dim 2 (NHD)";
  return {0, 0};
}

// Byte-identical helper to sparse_mla_sm120.cu:128 check_dense_indices_2d_or_s_q_3d.
inline int check_dense_indices_2d_or_s_q_3d(const TensorView& idx, const char* name,
                                            int num_tokens) {
  TVM_FFI_ICHECK(idx.ndim() == 2 || idx.ndim() == 3)
      << name << " must be [num_tokens, topk] or [num_tokens, 1, topk]; got ndim=" << idx.ndim();
  const int width = static_cast<int>(idx.size(-1));
  TVM_FFI_ICHECK_EQ(idx.size(0), num_tokens) << name << " leading dimension must match num_tokens";
  if (idx.ndim() == 3) {
    TVM_FFI_ICHECK_EQ(idx.size(1), 1) << name << " middle dimension must be singleton";
  }
  TVM_FFI_ICHECK_EQ(idx.stride(-1), 1) << name << " last dimension must be contiguous";
  TVM_FFI_ICHECK_EQ(idx.stride(0), width)
      << name << " must be dense row-major over the token dimension";
  return width;
}

}  // namespace

void SparseMlaSm120Fp4PagedAttention(
    TensorView q,         // [num_tokens, num_heads, d_qk=512] bf16
    TensorView kv_cache,  // main V4 (584B) paged FP8 cache; pbs=64 form
    TensorView indices,   // [num_tokens, topk] or [num_tokens, 1, topk] int32 (-1 = skip)
    TensorView output,    // [num_tokens, num_heads, 512] bf16 — in-place
    TensorView out_lse,   // [num_tokens, num_heads] f32 — in-place
    double sm_scale,
    Optional<TensorView> topk_length,        // [num_tokens] int32, optional
    Optional<TensorView> attn_sink,          // [num_heads] f32, optional
    TensorView extra_kv_cache,               // REQUIRED: 288B V41_FP4 pool
    TensorView extra_indices,                // REQUIRED: [num_tokens, extra_topk] int32
    Optional<TensorView> extra_topk_length)  // [num_tokens] int32, optional
{
  CHECK_INPUT_AND_TYPE(q, dl_bfloat16);
  CHECK_CUDA(kv_cache);
  CHECK_LAST_DIM_CONTIGUOUS(kv_cache);
  CHECK_INPUT_TYPE(kv_cache, dl_uint8);
  CHECK_INPUT_AND_TYPE(indices, dl_int32);
  CHECK_INPUT_AND_TYPE(output, dl_bfloat16);
  CHECK_INPUT_AND_TYPE(out_lse, dl_float32);

  CHECK_DIM(3, q);

  const int num_tokens = static_cast<int>(q.size(0));
  const int num_heads = static_cast<int>(q.size(1));
  const int d_qk = static_cast<int>(q.size(2));
  const int topk = check_dense_indices_2d_or_s_q_3d(indices, "indices", num_tokens);
  TVM_FFI_ICHECK_EQ(d_qk, 512) << "R1 fp4-extra prefill is DSV4 (d_qk=512) only";
  const ModelType mt = ModelType::DSV4;

  // Main cache: stock 584B footer-form parse (sglang always feeds the pbs=64
  // re-paged main view on this path).
  const PagedKVLayout kv_layout = parse_paged_kv_layout(kv_cache, 584, "kv_cache");
  const int page_block_size = kv_layout.page_block_size;

  TVM_FFI_ICHECK_GT(num_heads, 0);
  TVM_FFI_ICHECK_LE(num_heads, 128);
  TVM_FFI_ICHECK_GT(topk, 0);
  TVM_FFI_ICHECK_GT(page_block_size, 0);
  TVM_FFI_ICHECK_EQ(output.ndim(), 3) << "output must be [num_tokens, num_heads, 512]";
  TVM_FFI_ICHECK_EQ(output.size(0), num_tokens);
  TVM_FFI_ICHECK_EQ(output.size(1), num_heads);
  TVM_FFI_ICHECK_EQ(output.size(2), 512) << "SM120 sparse-MLA requires d_v == 512";
  TVM_FFI_ICHECK_EQ(out_lse.ndim(), 2) << "out_lse must be [num_tokens, num_heads]";
  TVM_FFI_ICHECK_EQ(out_lse.size(0), num_tokens);
  TVM_FFI_ICHECK_EQ(out_lse.size(1), num_heads);

  if (topk_length.has_value()) {
    const auto& tl = topk_length.value();
    CHECK_INPUT_AND_TYPE(tl, dl_int32);
    TVM_FFI_ICHECK_EQ(tl.ndim(), 1) << "topk_length must be [num_tokens]";
    TVM_FFI_ICHECK_EQ(tl.size(0), num_tokens);
  }

  const float* attn_sink_ptr = nullptr;
  if (attn_sink.has_value()) {
    const auto& s = attn_sink.value();
    CHECK_INPUT_AND_TYPE(s, dl_float32);
    TVM_FFI_ICHECK_EQ(s.ndim(), 1);
    TVM_FFI_ICHECK_EQ(s.size(0), num_heads) << "attn_sink must be [num_heads]";
    attn_sink_ptr = static_cast<const float*>(s.data_ptr());
  }

  // Extra fp4 pool: REQUIRED, 288B rows, native pool pages {128, 256}.
  CHECK_CUDA(extra_kv_cache);
  CHECK_LAST_DIM_CONTIGUOUS(extra_kv_cache);
  CHECK_INPUT_TYPE(extra_kv_cache, dl_uint8);
  CHECK_INPUT_AND_TYPE(extra_indices, dl_int32);
  constexpr int kFp4BytesPerToken = 288;
  const PagedKVLayout extra_layout =
      parse_paged_kv_layout(extra_kv_cache, kFp4BytesPerToken, "extra_kv_cache");
  const int extra_topk =
      check_dense_indices_2d_or_s_q_3d(extra_indices, "extra_indices", num_tokens);
  TVM_FFI_ICHECK(extra_layout.page_block_size == 128 || extra_layout.page_block_size == 256)
      << "R1 fp4 extra pool page_block_size must be 128 or 256, got "
      << extra_layout.page_block_size;
  TVM_FFI_ICHECK_EQ(extra_layout.stride_kv_block % 4, 0)
      << "R1 fp4 extra pool page stride must be 4B aligned for the u32 LDG producer, got "
      << extra_layout.stride_kv_block;
  TVM_FFI_ICHECK_GT(extra_topk, 0);

  if (extra_topk_length.has_value()) {
    const auto& etl = extra_topk_length.value();
    CHECK_INPUT_AND_TYPE(etl, dl_int32);
    TVM_FFI_ICHECK_EQ(etl.ndim(), 1) << "extra_topk_length must be [num_tokens]";
    TVM_FFI_ICHECK_EQ(etl.size(0), num_tokens);
  }

  const int* tl_ptr =
      topk_length.has_value() ? static_cast<const int*>(topk_length.value().data_ptr()) : nullptr;
  const int* etl_ptr = extra_topk_length.has_value()
                           ? static_cast<const int*>(extra_topk_length.value().data_ptr())
                           : nullptr;

  ffi::CUDADeviceGuard device_guard(q.device().device_id);
  const cudaStream_t stream = get_stream(q.device());

  const bool ok = sparse_mla_prefill_dispatch(
      mt, num_heads, topk, page_block_size, extra_topk, extra_layout.page_block_size,
      /*extra_is_fp4=*/true, static_cast<const bf16*>(q.data_ptr()),
      static_cast<const uint8_t*>(kv_cache.data_ptr()),
      static_cast<const int32_t*>(indices.data_ptr()),
      static_cast<const uint8_t*>(extra_kv_cache.data_ptr()),
      static_cast<const int32_t*>(extra_indices.data_ptr()),
      static_cast<bf16*>(output.data_ptr()), static_cast<float*>(out_lse.data_ptr()),
      static_cast<float>(sm_scale), num_tokens, kv_layout.stride_kv_block,
      extra_layout.stride_kv_block, attn_sink_ptr, tl_ptr, etl_ptr, stream);
  TVM_FFI_ICHECK(ok) << "R1 fp4-extra prefill dispatch failed (unsupported shape: heads="
                     << num_heads << ", topk=" << topk
                     << ", extra_pbs=" << extra_layout.page_block_size << ")";
}

}  // namespace flashinfer::sparse_mla_sm120

TVM_FFI_DLL_EXPORT_TYPED_FUNC(sparse_mla_sm120_fp4_paged_attention,
                              flashinfer::sparse_mla_sm120::SparseMlaSm120Fp4PagedAttention);
