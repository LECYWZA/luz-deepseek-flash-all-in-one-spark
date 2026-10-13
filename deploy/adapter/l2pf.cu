// L2 bulk-prefetch launcher for DSV41_L2_PREFETCH (see adapter/l2_prefetch.py).
//
// Single source of truth: the Dockerfile bakes libdsv41_l2pf.so from this file at
// image-build time; if the .so is absent (dev/bind-mount path) the adapter compiles
// this same file on first use. No duplicated copy lives in the .py.
//
// A prefetch is only a cache hint -- it never changes a result -- so the only
// correctness obligation here is that the launch does not fault.
#include <cuda_runtime.h>
#include <stdint.h>

// segs: [n][2] int64 {address, bytes}; one bulk prefetch per <=chunk piece.
__global__ void l2pf(const long long* __restrict__ segs, int n, long long chunk) {
  for (int s = blockIdx.x; s < n; s += gridDim.x) {
    long long a = segs[2 * s], b = segs[2 * s + 1];
    for (long long off = threadIdx.x * chunk; off < b; off += (long long)blockDim.x * chunk) {
      long long sz = b - off < chunk ? b - off : chunk;
      sz &= ~15LL;
      if (sz > 0)
        asm volatile("cp.async.bulk.prefetch.L2.global [%0], %1;" :: "l"(a + off), "r"((unsigned)sz) : "memory");
    }
  }
}

extern "C" int dsv41_l2pf(const void* segs, int n, long long chunk, uintptr_t stream) {
  l2pf<<<n < 8 ? n : 8, 64, 0, (cudaStream_t)stream>>>((const long long*)segs, n, chunk);
  return (int)cudaGetLastError();
}
