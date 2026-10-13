"""FL6 desk reproduction & fix verification (QA31-20261013 cp30 0/3 semantics).

Scales the production geometry (page=256, window=128, chunked prefill with
per-chunk SWA window publication) down to a CPU-runnable unit test:

  repro   : doc A is prefilled chunk-by-chunk (each chunk-boundary leaf gets an
            SWA window page committed to the tree), then enough fill traffic
            cycles the small SWA pool until A's tail window is tombstoned.
            The match then zeroes the whole FULL-resident prefix (cached=0)
            -> the FL6 cp30 red.
  fix B1  : interior chunk pages are retired at request finish, so the pool
            holds only final tails -> A's replay matches ~exactly.
  fix A   : even with the tail force-killed, the match retracts by
            window+page (page-aligned) instead of zeroing -> bounded reuse.

Run:
  PYTHONPATH=<stubs>:<sglang-src>/python python3 test_fl6_swa_recall.py
"""

import os
import unittest
from array import array

from sglang.srt.mem_cache.base_prefix_cache import EvictParams, InsertParams, MatchPrefixParams
from sglang.srt.mem_cache.cache_init_params import CacheInitParams
from sglang.srt.mem_cache.radix_cache import RadixKey
from sglang.srt.mem_cache.unified_cache.components.base import ComponentType
from sglang.srt.mem_cache.unified_radix_cache import UnifiedRadixCache
from sglang.srt.mem_cache.memory_pool import ReqToTokenPool
from sglang.srt.mem_cache.allocator.swa import SWATokenToKVPoolAllocator
from sglang.srt.mem_cache.swa_memory_pool import SWAKVPool

try:
    import fl6_fix
except ImportError:
    fl6_fix = None

# Fix arm (default) applies the patch before any cache is built; control arm
# (FL6_APPLY_FIX=0) reproduces the stock-engine bug. FL6_USE_ADAPTER=1 uses
# the production adapter artifact (fl6_recall.py, DSV41_FL6_RECALL_FIX gate)
# instead of the dev monkey-patch.
if os.getenv("FL6_APPLY_FIX", "1") == "1":
    if os.getenv("FL6_USE_ADAPTER", "0") == "1":
        os.environ["DSV41_FL6_RECALL_FIX"] = os.getenv("DSV41_FL6_RECALL_FIX", "1")
        from sglang.srt.mem_cache.unified_cache import unified_tree_core as _utc
        from sglang.srt.mem_cache.unified_cache.components import swa as _swa

        import fl6_recall

        fl6_recall.install(_utc)
        fl6_recall.install_swa(_swa)

        class _Shim:
            @staticmethod
            def applied():
                return True

        fl6_fix = _Shim()
    elif fl6_fix is not None:
        fl6_fix.apply()

PAGE = 256
WINDOW = 128
CHUNK = 1024  # 4 pages per prefill chunk
FULL_POOL = 131072
SWA_POOL = 16384  # 64 pages: with retirement, all tails fit; without it, fill traffic cycles the pool
HEAD_NUM, HEAD_DIM, LAYERS = 2, 16, 8
DTYPE = None  # resolved lazily (torch dtype)


def _full_attention_layer_ids():
    return list(range(3, LAYERS, 4))


def _non_full_layer_ids():
    return [i for i in range(LAYERS) if i not in _full_attention_layer_ids()]


class DeskEnv:
    def __init__(self):
        import torch

        self.torch = torch
        self.pool = SWAKVPool(
            size=FULL_POOL,
            size_swa=SWA_POOL,
            page_size=PAGE,
            dtype=torch.bfloat16,
            head_num=HEAD_NUM,
            head_dim=HEAD_DIM,
            swa_attention_layer_ids=_non_full_layer_ids(),
            full_attention_layer_ids=_full_attention_layer_ids(),
            device="cpu",
        )
        self.alloc = SWATokenToKVPoolAllocator(
            size=FULL_POOL,
            size_swa=SWA_POOL,
            page_size=PAGE,
            dtype=torch.bfloat16,
            device="cpu",
            kvcache=self.pool,
            need_sort=False,
        )
        self.rtp = ReqToTokenPool(
            size=64, max_context_len=FULL_POOL, device="cpu", enable_memory_saver=False
        )
        self.tree = UnifiedRadixCache(
            params=CacheInitParams(
                req_to_token_pool=self.rtp,
                token_to_kv_pool_allocator=self.alloc,
                page_size=PAGE,
                disable=False,
                tree_components=(ComponentType.FULL, ComponentType.SWA),
                sliding_window_size=WINDOW,
            )
        )
        self._rid = 0

    def make_req(self, tokens):
        from sglang.srt.managers.schedule_batch import Req
        from sglang.srt.sampling.sampling_params import SamplingParams

        req = Req(
            rid=self._rid,
            origin_input_text="",
            origin_input_ids=array("q", tokens),
            sampling_params=SamplingParams(temperature=0, max_new_tokens=1),
        )
        self._rid += 1
        self.rtp.alloc([req])
        req.full_untruncated_fill_ids = array("q", tokens)
        return req

    def alloc_pages(self, n_tokens):
        """Allocate n_tokens (page-aligned up) of FULL+SWA and set the mapping."""
        aligned = ((n_tokens + PAGE - 1) // PAGE) * PAGE
        if aligned > self.alloc.full_attn_allocator.available_size():
            return None
        if aligned > self.alloc.swa_attn_allocator.available_size():
            return None
        full = self.alloc.full_attn_allocator.alloc(aligned)
        swa = self.alloc.swa_attn_allocator.alloc(aligned)
        assert full is not None and swa is not None
        self.alloc.full_to_swa_index_mapping[full] = swa
        return full[:n_tokens]

    def alloc_with_swa_evict(self, n_tokens):
        v = self.alloc_pages(n_tokens)
        if v is None:
            self.tree.evict(EvictParams(num_tokens=0, swa_num_tokens=n_tokens + PAGE))
            v = self.alloc_pages(n_tokens)
        return v

    def admit(self, req, tokens):
        """Admission match + lock, as prepare_for_extend/_req_inc_lock_ref do."""
        res = self.tree.match_prefix(
            MatchPrefixParams(key=RadixKey(array("q", tokens)), req=req)
        )
        req.prefix_indices = res.device_indices
        req.last_node = res.last_device_node
        req.best_match_node = res.best_match_node
        req.swa_branching_seqlen = res.swa_branching_seqlen
        req.lock_receipt = self.tree.inc_lock_ref(req.last_node).to_dec_params()
        req.kv.cache_protected_len = len(res.device_indices)

    def prefill_doc(self, tokens, evict=True):
        """Chunked prefill one doc through the production cache flow."""
        req = self.make_req(tokens)
        self.admit(req, tokens)
        alloc = self.alloc_with_swa_evict if evict else self.alloc_pages
        pos = 0
        while pos < len(tokens):
            end = min(pos + CHUNK, len(tokens))
            slots = alloc(end - pos)
            assert slots is not None, "alloc failed despite eviction"
            self.rtp.write(
                (req.kv.req_pool_idx, slice(pos, end)),
                slots.to(self.rtp.req_to_token.dtype),
            )
            req.set_extend_range(0, end)
            if end < len(tokens):
                self.tree.cache_unfinished_req(req, chunked=True)
            pos = end
        self.finish(req, len(tokens))
        return req

    def finish(self, req, up_to):
        """insert_req, then what release_kv_cache does after it."""
        self.tree.insert_req(req, up_to=up_to)
        self.tree.free_kv_row(req.kv, [(req.kv.cache_protected_len, up_to)])
        self.tree.unpin(req)

    def replay(self, tokens):
        return self.tree.match_prefix(
            MatchPrefixParams(key=RadixKey(array("q", tokens)))
        )

    def replay_full(self, tokens):
        """Admission match (retract-aware) then extend only past the match."""
        req = self.make_req(tokens)
        self.admit(req, tokens)
        prefix = len(req.prefix_indices)
        pos = prefix
        while pos < len(tokens):
            end = min(pos + CHUNK, len(tokens))
            slots = self.alloc_with_swa_evict(end - pos)
            assert slots is not None
            self.rtp.write(
                (req.kv.req_pool_idx, slice(pos, end)),
                slots.to(self.rtp.req_to_token.dtype),
            )
            req.set_extend_range(0, end)
            if end < len(tokens):
                self.tree.cache_unfinished_req(req, chunked=True)
            pos = end
        self.finish(req, len(tokens))
        return prefix


def _doc(seed, n_tokens):
    import random

    rng = random.Random(seed)
    return [rng.randrange(100000, 999999) for _ in range(n_tokens)]


class TestFL6SWARecall(unittest.TestCase):
    def setUp(self):
        self.env = DeskEnv()

    def _repro_doc(self):
        # 8-chunk doc (8192 tokens): every chunk boundary commits an SWA page.
        return _doc(17, CHUNK * 8)

    def _fill_traffic(self, count):
        for i in range(count):
            self.env.prefill_doc(_doc(1000 + i, CHUNK * 2))

    def test_00_sanity_exact_replay_low_pressure(self):
        """Control: replay right after finish (no pressure) must hit ~exactly."""
        doc = self._repro_doc()
        self.env.prefill_doc(doc)
        res = self.env.replay(doc)
        hit = len(res.device_indices)
        self.assertGreaterEqual(hit, (len(doc) // PAGE) * PAGE - PAGE)

    def test_10_repro_cp30_semantics(self):
        """FL6 cp30 red: SWA pool cycled by interior pages -> replay miss.

        This is the desk reproduction of QA31 cp30 0/3 (cached=0 while FULL is
        resident). Runs against the UNPATCHED tree first (control arm), then
        applies the fix and expects the green behaviour.
        """
        doc = self._repro_doc()
        self.env.prefill_doc(doc)
        # Enough 2-chunk docs to cycle the 32-page SWA pool well past doc A's
        # tail (each doc keeps ~3 SWA pages: two interior + final tail).
        self._fill_traffic(16)
        res = self.env.replay(doc)
        if fl6_fix is None or not fl6_fix.applied():
            self.assertEqual(
                len(res.device_indices), 0,
                "expected the FL6 bug (whole-prefix zero match); "
                "if this fails the engine already fixed it",
            )
            return
        hit = len(res.device_indices)
        self.assertGreaterEqual(
            hit / len(doc), 0.98, "fix B1 must keep the tail alive for exact recall"
        )

    def test_11_retire_interior_after_finish(self):
        """Fix B1 invariant: a finished long doc keeps only its tail window."""
        if fl6_fix is None or not fl6_fix.applied():
            self.skipTest("fix not applied")
        doc = self._repro_doc()
        self.env.prefill_doc(doc)
        evictable = self.env.tree.swa_evictable_size()
        self.assertLessEqual(
            evictable, 2 * PAGE, f"finished doc must retire interior pages ({evictable=})"
        )

    def test_20_retract_when_tail_force_killed(self):
        """Fix A: FULL-resident prefix with a dead tail still retracts, not zeroes."""
        if fl6_fix is None or not fl6_fix.applied():
            self.skipTest("fix not applied")
        doc = self._repro_doc()
        self.env.prefill_doc(doc)
        # Kill every evictable SWA page (simulates worst-case LRU circulation).
        self.env.tree.evict(EvictParams(num_tokens=0, swa_num_tokens=SWA_POOL * 10))
        self.assertEqual(self.env.tree.swa_evictable_size(), 0)
        res = self.env.replay(doc)
        hit = len(res.device_indices)
        # node granularity quantizes the cut down to the enclosing node boundary
        expect_min = (len(doc) // PAGE) * PAGE - 2 * PAGE - CHUNK
        self.assertGreaterEqual(
            hit, expect_min,
            f"match must retract by ~window+page ({hit=} < {expect_min})",
        )

    def test_21_retract_then_heal_on_second_replay(self):
        """Retracted replay re-stamps the branch; the next replay hits deeper."""
        if fl6_fix is None or not fl6_fix.applied():
            self.skipTest("fix not applied")
        doc = self._repro_doc()
        self.env.prefill_doc(doc)
        self.env.tree.evict(EvictParams(num_tokens=0, swa_num_tokens=SWA_POOL * 10))
        first = self.env.replay_full(doc)
        second = self.env.replay(doc)
        self.assertGreaterEqual(
            len(second.device_indices),
            first,
            f"second replay must not be shallower ({first=} {len(second.device_indices)=})",
        )

    def test_22_pool_conservation_after_stress(self):
        """Accounting invariant: no leak / double-free across stress."""
        import random

        rng = random.Random(7)
        docs = [_doc(500 + i, CHUNK * rng.choice([1, 2, 4])) for i in range(24)]
        for d in docs:
            self.env.prefill_doc(d)
            if rng.random() < 0.4:
                self.env.replay_full(d)
        evictable = self.env.tree.swa_evictable_size()
        available = self.env.alloc.swa_attn_allocator.available_size()
        self.assertGreaterEqual(evictable, 0)
        self.assertGreaterEqual(available, 0)
        self.assertLessEqual(evictable + available, SWA_POOL)


if __name__ == "__main__":
    unittest.main(verbosity=2)
