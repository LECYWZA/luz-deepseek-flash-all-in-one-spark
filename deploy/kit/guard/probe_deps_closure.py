#!/usr/bin/env python3
"""Does a header edit invalidate the SGLang JIT cache?  (corrects probe_jit_cache_key.py)

The first probe measured `compute_build_key`, the name of the `build-<key>/`
*directory*, and concluded a header edit was invisible.  That was the wrong
object: `find_prebuilt` does not trust the directory name, it re-reads each
leaf's recorded dependency list (`sgl_deps.json`), re-hashes every file in it,
and requires `leaf.name == "deps-" + _deps_key(current)` -- the leaf name is
derived from the *current* contents of the whole `#include` closure.

So the question to ask is: does the recorded closure include the header, and
does editing it stop the leaf from reproducing its own name?  This script
answers that against a real cache tree, read-only:

  usage: probe_deps_closure.py <cache-root> <module-variant-name>
  e.g.:  probe_deps_closure.py /root/.cache/sglang/jit sm121a/sgl_kernel_jit_dpsk_v4_c2_512_64_128_V41_FP4_true
"""
import pathlib
import sys

from sglang.kernels.jit.utils.compile import cache


def main():
    cache_root = pathlib.Path(sys.argv[1])
    variant = sys.argv[2]
    module_dir = cache_root / variant
    if not module_dir.is_dir():
        print(f"FAIL: no such variant dir: {module_dir}")
        return 2
    # The cache root is <target>/<module>; the *scope* that find_prebuilt scans is
    # the per-build-key directory inside it (build-<key>/deps-<hash>/<module>.so).
    module_name = module_dir.name
    scopes = sorted(p for p in module_dir.iterdir() if p.is_dir() and p.name.startswith("build-"))
    if not scopes:
        print(f"FAIL: no build-* directory under {module_dir}")
        return 2
    hit_any = False
    for scope in scopes:
        print(f"scope   : {module_name}/{scope.name}")
        leaves = sorted(
            (p for p in scope.iterdir() if p.name.startswith(cache._DEPS_KEY_PREFIX)),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        print(f"  leaves: {len(leaves)}")
        for leaf in leaves:
            entries = cache._read_deps(leaf)
            if entries is None:
                print(f"    {leaf.name}: no readable deps json")
                continue
            current, changed = cache._refresh(entries)
            reproduced = (
                current is not None
                and f"{cache._DEPS_KEY_PREFIX}{cache._deps_key(current)}" == leaf.name
            )
            print(f"    {leaf.name}: {len(entries)} deps, reproduces its own name: {reproduced}")
            if changed:
                print(f"      CHANGED since it was built: {changed}")
            kv = [e for e in entries if "kv_layout" in e.relpath or "fp4_utils" in e.relpath]
            for e in kv:
                print(f"      recorded: {e.relpath}  digest={e.digest[:16]}")
            if not kv:
                print("      NOTE: no kv_layout/fp4_utils entry recorded")
        hit = cache.find_prebuilt(scope=scope, module_name=module_name)
        hit_any = hit_any or bool(hit)
        print(f"  find_prebuilt -> {'HIT  ' + hit.parent.name if hit else 'MISS (would rebuild)'}")
    print()
    print(f"VERDICT: {'cache is usable (a leaf reproduces its name)' if hit_any else 'every leaf is stale -> the module WILL be rebuilt'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
