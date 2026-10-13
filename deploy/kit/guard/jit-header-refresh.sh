#!/usr/bin/env bash
# jit-header-refresh.sh -- pre-empt the recompile after a jit/include header change.
#
# The mechanism (measured, both directions -- see probe_deps_closure.py)
# ---------------------------------------------------------------------
# `load_jit` names the build *directory* `build-<key>/` from the listed csrc
# sources only, so that name does not move when a header changes -- measuring it
# is what produced the (wrong) folklore that headers are outside the cache key.
# The name that matters is the **leaf**: `cache.find_prebuilt` reads the leaf's
# recorded dependency list (432 entries for these modules), re-hashes every file
# in it by content, and requires `leaf.name == "deps-" + _deps_key(current)`.
# Headers are in that list, so editing one renames the expected leaf and the stale
# leaf becomes a MISS.  The cache self-invalidates; the module is rebuilt.
#
# Observed: a leaf built before the edit reports
#   CHANGED: kernels:include/sgl_kernel/deepseek_v4/kv_layout.cuh -> MISS
# and a leaf built after it -> HIT.
#
# So correctness needs no manual step.  What this script buys is the *cost* of
# that rebuild: it compiles the affected variants offline (throwaway container,
# CUDA target forced to sm_121a, memory capped, no GPU, no nvcc competing with a
# live server) and **publishes** the resulting leaves.  Old and new leaves coexist
# under the same `build-<key>/`; `find_prebuilt` picks the one that reproduces, so
# a server still on the old header keeps working and a server on the new header
# starts without compiling.
#
# It therefore NEVER deletes a leaf.  An earlier revision did (`rm -rf build-*`),
# which would have removed exactly what the running server is hitting -- the fast
# path takes no lock, so a miss there compiles inside the server, outside any
# memory cap this script sets.
#
# Usage:
#   jit-header-refresh.sh --check            # is there a usable leaf for the header on disk?
#   jit-header-refresh.sh --apply            # build + publish the affected variants
#   jit-header-refresh.sh --apply --cache /path/to/staging/cache   # e.g. an image build context
# Options: --header <path> --image <tag> --cache <dir> --overlay <dir>
#
# The driver image needs the sglang tree but not the overlay: the four Python
# modules that name the variants are bind-mounted in from --overlay (default
# ~/dsv41-flash-dgxsparks/sglang-overlay), which is also what makes `--image`
# usable with a plain upstream base image. Without them `kv_layout` is missing
# and the run dies with ImportError.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 驱动镜像：优先 DSV41_IMAGE，其次生产台账（~/dsv41-flash-dgxsparks/.env.tp4 的 IMAGE），
# 再退到本机最新的 dsv41-sglang-optimized:*。
# ★不要在这里钉死版本号：曾经钉的是 v3，而生产早已 v5/v6/v7 —— "脚本里的默认值"
#   于是变成会骗人的东西（用它 --apply 会把叶子发布进错误的树）。
IMAGE="${DSV41_IMAGE:-}"
[ -n "$IMAGE" ] || IMAGE="$(sed -n 's/^IMAGE=//p' "$HOME/dsv41-flash-dgxsparks/.env.tp4" 2>/dev/null | tail -1)"
[ -n "$IMAGE" ] || IMAGE="$(docker images --format '{{.Repository}}:{{.Tag}}' dsv41-sglang-optimized 2>/dev/null | head -1)"
HOST_CACHE="${DSV41_JIT_CACHE:-$HOME/.cache/sglang/jit}"
CONTAINER_CACHE="/jit-cache"                     # where the host cache is mounted
# NOT under /root: the containers run as the invoking uid (never root), and the
# image's /root is mode 0700, so a cache mounted there is unreachable -- every
# mkdir inside it fails with EACCES and, worse, --check silently reports MISS
# for every variant because the probe cannot read the leaves either.
TARGET="${DSV41_JIT_TARGET:-sm121a}"
HEADER=""
MODE=""
OVERLAY="${DSV41_OVERLAY:-$HOME/dsv41-flash-dgxsparks/sglang-overlay}"
MEMCAP="${DSV41_JIT_REFRESH_MEM:-12g}"
CPUS="${DSV41_JIT_REFRESH_CPUS:-6}"
# The driver image only has to supply the sglang *tree*; the four Python modules
# that name the variants are overlay files (patched, and `kv_layout.py` does not
# exist upstream at all -- importing it from a plain base image fails with
# "cannot import name 'kv_layout'"). Mount them so the driver's Python is the
# same Python the built image will have. The compiled sources are unaffected:
# the only compiled file this tool changes is the mounted header.
DSV4_PY="/sgl-workspace/sglang/python/sglang/kernels/ops/attention/dsv4"
PY_MODULES=(kv_layout.py elementwise.py c2.py attn.py)
MOUNTS=()
MAP=""
MAP_HEADER_COVERED=0
OVERLAY_NOTE=""
prepare_overlay_mounts() {  # after arg parsing: --overlay/--overlay-map may have moved
  MOUNTS=(); MAP_HEADER_COVERED=0
  if [ -n "$MAP" ] && [ -f "$MAP" ]; then
    # Full-tree mode: the map is the same `src<TAB>container-path` list the image
    # build and start.sh use, so the compile sees the tree the image will ship.
    # Without this the driver compiles against the *base* image's csrc -- which for
    # the fp4 work is a different kernel (its store.cuh has no V41_FP4 and a 4-arg
    # FusedStoreCacheFlashMLAKernel), so the build fails on "identifier V41_FP4 is
    # undefined" and, if it did not, the leaf's recorded dependency digests would
    # describe files the runtime container does not have -> the published leaf is
    # a MISS forever.
    while IFS=$'\t' read -r src dst; do
      [ -n "$src" ] && [ -f "$src" ] && [ -n "$dst" ] || continue
      # The header is mounted separately (HEADER_MOUNT, below) so that --header
      # always wins -- the map's own copy is skipped to avoid two binds on one
      # destination. Mounting the map's copy instead made the container silently
      # ignore --header, which turned --check into a gate that passes for a header
      # the cache was *not* built from.
      if [ "$dst" = "$CONTAINER_HEADER" ]; then MAP_HEADER_COVERED=1; continue; fi
      MOUNTS+=(-v "$src:$dst:ro")
    done < "$MAP"
    OVERLAY_NOTE="overlay: $(( ${#MOUNTS[@]} / 2 )) file(s) from $MAP + the header (tree = image + overlay)"
  else
    for m in "${PY_MODULES[@]}"; do
      [ -f "$OVERLAY/$m" ] && MOUNTS+=(-v "$OVERLAY/$m:$DSV4_PY/$m:ro")
    done
    if [ -f "$OVERLAY/kv_layout.py" ]; then
      OVERLAY_NOTE="overlay: ${#MOUNTS[@]} python module(s) from $OVERLAY (only the python
         side is mounted -- a C++ header not in this list will compile against the
         image's copy; pass --overlay-map for a full tree)"
    else
      OVERLAY_NOTE="overlay: WARNING -- $OVERLAY/kv_layout.py not found. It exists only in
         the overlay (never upstream), so the driver image must already contain it
         (pass --image <an image built with the overlay> or --overlay-map) or --apply
         fails with ImportError: cannot import name 'kv_layout'."
    fi
  fi
}
# Every variant whose translation unit includes kv_layout.cuh, as production maps
# it (see jit_refresh_exec.py for the arg tuples and why c1 is absent).
VARIANTS=(
  "sm121a/sgl_kernel_jit_dpsk_v4_store_flashmla_bf16_t_int64_t_128_V41_FP4_true"
  "sm121a/sgl_kernel_jit_dpsk_v4_store_flashmla_bf16_t_int64_t_256_V41_FP4_true"
  "sm121a/sgl_kernel_jit_dpsk_v4_c2_512_64_128_V41_FP4_true"
  "sm121a/sgl_kernel_jit_dpsk_v4_main_k_norm_rope_flashmla_bf16_t_512_64_256_V4_true"
)

while [ $# -gt 0 ]; do
  case "$1" in
    --check)  MODE=check; shift ;;
    --apply)  MODE=apply; shift ;;
    --header) HEADER="${2:?}"; shift 2 ;;
    --cache)  HOST_CACHE="${2:?}"; shift 2 ;;
    --image)  IMAGE="${2:?}"; shift 2 ;;
    --overlay) OVERLAY="${2:?}"; shift 2 ;;
    --overlay-map) MAP="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { echo "FAIL: pass --check or --apply" >&2; exit 2; }
[ -n "$IMAGE" ] || { echo "FAIL: 无法确定驱动镜像（DSV41_IMAGE / .env.tp4 的 IMAGE / 本机 dsv41-sglang-optimized:* 都取不到）；用 --image <tag> 指定" >&2; exit 2; }
docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "FAIL: 驱动镜像 $IMAGE 不在本机（--image 指定或用 DSV41_IMAGE 覆盖）" >&2; exit 2; }

if [ -z "$HEADER" ]; then
  for cand in \
    "$HOME/dsv41-flash-dgxsparks/sglang-overlay/kv_layout.cuh" \
    "/sgl-workspace/sglang/python/sglang/kernels/jit/include/sgl_kernel/deepseek_v4/kv_layout.cuh"
  do
    [ -f "$cand" ] && { HEADER="$cand"; break; }
  done
fi
[ -n "$HEADER" ] && [ -f "$HEADER" ] || { echo "FAIL: cannot find the header; pass --header" >&2; exit 2; }
# A *fixed* destination: where the translation units #include the header from, which
# is a property of the tree, not of the file's name on the host. Deriving it from
# `basename "$HEADER"` meant `--header /tmp/kv_layout_probe.cuh` was mounted as
# `kv_layout_probe.cuh` *beside* the overlay map's `kv_layout.cuh` -- so the probe
# read the map's file and the gate passed for a header the cache was not built from.
CONTAINER_HEADER="${DSV41_JIT_HEADER_PATH:-/sgl-workspace/sglang/python/sglang/kernels/jit/include/sgl_kernel/deepseek_v4/kv_layout.cuh}"

prepare_overlay_mounts
# Always mount the header explicitly: it is the file whose variants are being
# (re)built, and --header must be able to point at a version other than the one
# the overlay map carries (that is what makes --check a real gate).
HEADER_MOUNT=(-v "$HEADER:$CONTAINER_HEADER:ro")

echo "header : $HEADER"
echo "cache  : $HOST_CACHE"
echo "image  : $IMAGE"
echo "mode   : $MODE"
echo "$OVERLAY_NOTE"
echo

# The probe runs in the image, with the header mounted, over the cache: it asks
# the loader itself whether a leaf still reproduces its name for the header the
# *container* sees.  Nothing is written.
probe_one() { # probe_one <variant-path>
  local v="$1"
  docker run --rm --memory 4g --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -e SGLANG_JIT_CACHE_DIR="$CONTAINER_CACHE" \
    -v "$HERE/probe_deps_closure.py:/p.py:ro" \
    "${HEADER_MOUNT[@]}" \
    "${MOUNTS[@]}" \
    -v "$HOST_CACHE:$CONTAINER_CACHE" \
    --entrypoint python3 "$IMAGE" /p.py "$CONTAINER_CACHE" "$v" 2>/dev/null
}

if [ "$MODE" = check ]; then
  rc=0
  for v in "${VARIANTS[@]}"; do
    [ -d "$HOST_CACHE/$v" ] || { echo "SKIP|$v|not in the cache (nothing published yet)"; continue; }
    out=$(probe_one "$v")
    if echo "$out" | grep -q 'find_prebuilt -> HIT'; then
      echo "OK  |$(basename "$v")|a leaf reproduces its name for the header on disk"
    else
      echo "MISS|$(basename "$v")|no usable leaf -> it will be rebuilt at first use"
      echo "$out" | grep -E 'CHANGED|reproduces' | sed 's/^/      /'
      rc=1
    fi
  done
  echo
  [ "$rc" = 0 ] && echo "PASS: every cached variant matches the header on disk." \
               || echo "NOTE: a MISS is not an error -- the cache self-invalidates by design. Run --apply to pay the compile offline instead of inside the server."
  exit "$rc"
fi

echo "== building + publishing (offline: no GPU, mem capped $MEMCAP, arch forced to $TARGET) =="
docker run --rm --memory "$MEMCAP" --cpus "$CPUS" --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -e SGLANG_JIT_CACHE_DIR="$CONTAINER_CACHE" \
  -v "$HERE/jit_refresh_exec.py:/jit_refresh_exec.py:ro" \
  "${HEADER_MOUNT[@]}" \
  "${MOUNTS[@]}" \
  -v "$HOST_CACHE:$CONTAINER_CACHE" \
  --entrypoint python3 "$IMAGE" /jit_refresh_exec.py --build
rc=$?
echo
if [ "$rc" = 0 ]; then
  echo "done. Existing leaves were left in place (a server on the old header keeps its hit)."
  echo "Re-run --check to confirm the new leaves resolve."
else
  echo "FAILED (rc=$rc). Nothing was deleted: a server on the old header still hits its own leaf,"
  echo "and a server on the new header will simply compile at first use."
fi
exit "$rc"
