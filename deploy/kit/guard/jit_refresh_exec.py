#!/usr/bin/env python3
"""Build-and-publish the SGLang JIT modules that include a given header.

`load_jit` keys the `build-<key>/` directory on the listed csrc sources only, but
`cache.find_prebuilt` gates the *leaf* on a re-hash of its recorded dependency
closure (432 entries for these modules; headers included).  So a header edit makes
the old leaf a MISS and the module is rebuilt at first use -- correct, but it
costs a compile inside the server, at whatever RAM the pool has left.

This tool pre-empts that cost: it runs the *real* builders for the affected module
variants so the cache already holds a leaf compiled from the edited header, under
the same `build-<key>/` the server will look in.  It **only publishes** -- it never
deletes a leaf, because the running server is hitting the existing ones and
`find_prebuilt` picks the one that reproduces.

`_load` is stubbed because the point is compile + publish, and dlopen would need
the GPU driver -- which this tool deliberately does not require.  Nothing here
touches the GPU, so it is safe to run outside a window.

Module map (declared, not guessed -- it mirrors what production actually maps,
per `/proc/<rank>/maps`): the four variants whose translation units include
`kv_layout.cuh`.  c1 is absent because no rank loads it with the ratio-1 pool
size (the pooled variant is page 256); the V4-layout variants of store/c2 are
absent from the cache because nothing instantiates them on this deployment.
Add a line here if a new variant starts appearing in `/proc/<rank>/maps`.

Usage:
  jit_refresh_exec.py --list
  jit_refresh_exec.py --build [--only <substring>]
The cache root comes from $SGLANG_JIT_CACHE_DIR (the container's mount of the
host cache is /root/.cache/sglang/jit).
"""
import argparse
import os
import sys
import traceback

import torch

import sglang.kernels.jit.utils.compile.loader as loader
from sglang.kernels.jit.utils.arch import override_jit_cuda_arch
from sglang.kernels.ops.attention.dsv4 import attn as attn_mod
from sglang.kernels.ops.attention.dsv4 import elementwise as el_mod
from sglang.kernels.ops.attention.dsv4 import c2 as c2_mod
from sglang.kernels.ops.attention.dsv4 import kv_layout as kvl_mod

# Compile without loading: no driver in this container, by design.
loader._load = lambda library: {"library": str(library)}
# Wrapper selection is name-driven and identical either way; this only keeps the
# published module name faithful to production (`..._true`).
for _mod in (attn_mod, c2_mod):
    _mod.is_arch_support_pdl = lambda: True


def variants():
    """(label, callable) for every module variant that includes kv_layout.cuh.

    Mirrors production's actual mappings -- `store_flashmla` with the fp4 pool's
    two page sizes, `c2` for the decode fusion, and `main_norm_rope` with the V4
    layout (it calls `store_row_fp4` through the same header).
    """
    V41 = kvl_mod.KVLayout.V41_FP4
    V4 = kvl_mod.KVLayout.V4
    return [
        ("store_flashmla_p128_V41_FP4",
         lambda: attn_mod._jit_fused_store_module("flashmla", torch.bfloat16, torch.int64, 128, V41)),
        ("store_flashmla_p256_V41_FP4",
         lambda: attn_mod._jit_fused_store_module("flashmla", torch.bfloat16, torch.int64, 256, V41)),
        ("c2_512_64_p128_V41_FP4", lambda: c2_mod._jit_c2_module(512, 64, 128, V41)),
        # main_norm_rope is instantiated with the V4 layout here, so its fp4 store
        # branch is not instantiated -- but the header is still in its recorded
        # dependency closure, so editing it makes this leaf a MISS too, and
        # publishing it keeps the first use from compiling inside the server.
        ("main_k_norm_rope_p256_V4",
         lambda: el_mod._jit_main_k_norm_rope_flashmla_module(torch.bfloat16, 512, 64, 256, V4)),
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--only", default="")
    args = ap.parse_args()

    items = variants()
    if args.only:
        items = [it for it in items if args.only in it[0]]

    if args.list or not args.build:
        print(f"cache root: {os.environ.get('SGLANG_JIT_CACHE_DIR', '<default>')}")
        for label, _ in variants():
            print(f"  {label}")
        return 0

    failures = 0
    with override_jit_cuda_arch(12, 1):          # sm_121a: same target as the server
        for label, fn in items:
            try:
                lib = fn().get("library", "?")
                print(f"OK   {label}: published {lib}")
            except Exception:
                failures += 1
                print(f"FAIL {label}:")
                traceback.print_exc()
    print()
    print(f"{'FAIL' if failures else 'PASS'}: {len(items) - failures}/{len(items)} variants "
          f"rebuilt and published")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
