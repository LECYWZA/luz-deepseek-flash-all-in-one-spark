"""FL6 recall fix (QA31-20261013 cp30 0/3): SWA interior retirement + match retract.

Root cause this addresses
-------------------------
The DSV4.1 hybrid radix tree keeps FULL+SWA components, and prefix reuse is
gated on the *tail sliding-window SWA KV staying alive* (one tombstone in the
tail window zeroes the match for the whole FULL-resident prefix).  Chunked
prefill commits one SWA window page per chunk boundary into the tree, so the
125,440-token SWA pool saturates at >=~21% fill load (QA31 fill30 measured
swa_evictable 121,344/125,440) and LRU-tombstones the recall-critical final
tails -> replay cached=0 with 278k of FULL KV resident (FL6 cp30 0/3).

Fix B1 (retire interior):  a finished request's branch keeps only its final
tail window live; interior chunk-boundary SWA pages are tombstoned and their
slots returned.  The owner request never reads them (bounded replay floors
the window at each chunk tail), so recall works at any load the FULL pool
supports.  SKA pool footprint drops from ~1 page/chunk to ~1 window/doc.

Fix A (match retract):  when a branch's SWA is dead all the way but FULL is
resident, the match returns prefix-(window+page, page-aligned) instead of
zero, so the replay re-prefills only the retracted tail on the normal extend
path (bounded replay semantics for that chunk are identical to any original
prefill chunk).  Guarantees recall whenever FULL KV is resident.

Both are pure code-path fixes; no serve/env form change.  apply() installs
them into the running modules; env kill-switches:
  SGLANG_FL6_RETIRE_INTERIOR=0   disable fix B1
  SGLANG_FL6_SWA_FULL_RETRACT=0  disable fix A
"""

import logging
import os

logger = logging.getLogger(__name__)

_APPLIED = False


def _flag(name):
    return os.getenv(name, "1") not in ("0", "false", "False", "")


def applied() -> bool:
    return _APPLIED


def apply() -> bool:
    global _APPLIED
    if _APPLIED:
        return True

    from sglang.srt.mem_cache.unified_cache import unified_tree_core as utc_mod
    from sglang.srt.mem_cache.unified_cache.components import swa as swa_mod
    from sglang.srt.mem_cache.unified_cache.components.base import (
        BASE_COMPONENT_TYPE,
        ComponentType,
    )

    retire_on = _flag("SGLANG_FL6_RETIRE_INTERIOR")
    retract_on = _flag("SGLANG_FL6_SWA_FULL_RETRACT")

    # ------------------------------------------------------------------
    # Fix B1: retire interior SWA window pages when a request finishes.
    # ------------------------------------------------------------------
    _orig_cleanup_after_caching_req = swa_mod.SWAComponent.cleanup_after_caching_req

    def _retire_interior_windows(comp, leaf):
        """Tombstone+free SWA values on `leaf`'s ancestor chain beyond the
        final tail window (keep = 2 page-ceil(window) tokens).  Skips nodes
        locked by concurrent requests; never touches FULL values."""
        tc = comp.tree_core
        ct = comp.component_type
        root = tc.root_node
        page = tc.page_size
        keep = 2 * ((comp.sliding_window_size + page - 1) // page) * page

        node = leaf
        if isinstance(node, int):
            node = tc.node_by_id(node)
        if node is None or node is root:
            return

        # distance of each ancestor's top from the leaf end
        cum_from_end = 0
        cur = node
        while cur is not root and cur is not None:
            seg = len(cur.key)
            top_from_end = cum_from_end + seg
            cd = cur.component_data[ct]
            if top_from_end > keep:
                if cd.value is not None and cd.lock_ref == 0:
                    freed = len(cd.value)
                    # Mirror evict_component: free SWA peers via the node's
                    # FULL indices (allocator skips slots with no SWA pair),
                    # keep the FULL value itself untouched.
                    full_value = cur.component_data[BASE_COMPONENT_TYPE].value
                    if full_value is not None:
                        tc.component_evictable_size_[ct] -= freed
                        lru = tc.lru_lists.get(ct)
                        if lru is not None and lru.in_list(cur):
                            lru.remove_node(cur)
                        cd.value = None
                        cd.metadata.pop("uuid", None)
                        comp.cache.token_to_kv_pool_allocator.free_swa(full_value)
            cum_from_end = top_from_end
            cur = cur.parent

    def cleanup_after_caching_req(
        self, req, is_finished, insert_result=None, insert_params=None
    ):
        _orig_cleanup_after_caching_req(
            self, req, is_finished, insert_result=insert_result, insert_params=insert_params
        )
        if not retire_on:
            return
        if not is_finished or insert_result is None:
            return
        leaf = getattr(insert_result, "last_device_node", None)
        if leaf is None:
            return
        try:
            _retire_interior_windows(self, leaf)
        except Exception:
            logger.exception("FL6 fix B1 retire_interior failed (continuing)")

    # ------------------------------------------------------------------
    # Fix A: match-side retract for FULL-resident/SWA-dead branches.
    # ------------------------------------------------------------------
    def _fl6_full_retract_tokens(self):
        if not retract_on or not self.sliding_window_size:
            return 0
        alloc = self.cache.token_to_kv_pool_allocator
        if getattr(alloc, "swa_req_ring", False):
            return 0  # per-request-ring layout never stores SWA in the tree
        page = self.tree_core.page_size
        # window + page, page-aligned: the re-prefilled stretch covers the
        # window context the tail rows need, on node (page) boundaries.
        return ((self.sliding_window_size + 2 * page - 1) // page) * page

    _match_prefix_helper_src = utc_mod.UnifiedTreeCore._match_prefix_helper

    def _match_prefix_helper(self, key):
        # Non-HiCache mode has only device-resident matches, so the scheduler
        # device anchor follows the best match. In HiCache mode, host-backed
        # nodes can also match, so we separately track the best device-resident
        # match for scheduler prefix indices and locking.
        node = self.root_node
        key_offset = 0
        child_key = key.child_key_at(key_offset, self.page_size)
        value = []
        trail = []  # FL6 fix A: node per value chunk, for the retract cut
        best_match_node = node
        best_match_device_node = node
        best_match_device_value_len = 0
        full_kv_hit_length = 0
        action = None
        separate_device_match = self.enable_hicache
        if separate_device_match:
            validators = tuple(comp.create_match_validator() for comp in self.components)
            device_validators = tuple(
                comp.create_match_validator(match_device_only=True)
                for comp in self.components
            )
        else:
            validators = tuple(
                comp.create_match_validator(match_device_only=True)
                for comp in self.components
            )

        def _all_valid(validators, node):
            return all([v(node) for v in validators])

        def _update_best_if_valid(node):
            nonlocal best_match_node
            nonlocal best_match_device_value_len, best_match_device_node
            matched = _all_valid(validators, node)
            if matched:
                best_match_node = node

            if not separate_device_match:
                if matched:
                    best_match_device_value_len = len(value)
                    best_match_device_node = node
                return
            if _all_valid(device_validators, node):
                best_match_device_value_len = len(value)
                best_match_device_node = node

        while key_offset < len(key) and child_key in node.children:
            child = node.children[child_key]

            # HiCache: dead node (evicted + not backuped) — stop traversal
            if child.evicted and not child.backuped:
                break

            prefix_len = child.key.match_at(key, key_offset, page_size=self.page_size)
            full_kv_hit_length += prefix_len
            if prefix_len < len(child.key):
                node, action = self._split_node(child.key, child, prefix_len)
                if not node.evicted:
                    value.append(node.component_data[BASE_COMPONENT_TYPE].value)
                    trail.append(node)
                _update_best_if_valid(node)
                break

            if not child.evicted:
                value.append(child.component_data[BASE_COMPONENT_TYPE].value)
                trail.append(child)
            node = child
            _update_best_if_valid(node)
            key_offset += prefix_len
            if key_offset < len(key):
                child_key = key.child_key_at(key_offset, self.page_size)

        # ---- FL6 fix A: FULL-resident retract when the SWA tail is dead. ----
        if not separate_device_match and not self.is_eagle:
            swa_comp = None
            for comp in self.components:
                if (
                    comp.component_type == ComponentType.SWA
                    and getattr(comp, "_fl6_full_retract_tokens", None) is not None
                ):
                    swa_comp = comp
                    break
            if swa_comp is not None:
                retract = swa_comp._fl6_full_retract_tokens()
                cut = (full_kv_hit_length // self.page_size) * self.page_size - retract
                if retract and cut > 0:
                    boundary = 0
                    for t in value[:best_match_device_value_len]:
                        boundary += len(t)
                    if cut > boundary:
                        k = 0
                        cum = 0
                        for i, t in enumerate(value):
                            if cum + len(t) > cut:
                                break
                            cum += len(t)
                            k = i + 1
                        if k > 0:
                            best_match_device_value_len = k
                            best_match_device_node = trail[k - 1]
                            best_match_node = trail[k - 1]

        return (
            value,
            best_match_node,
            best_match_device_node,
            best_match_device_value_len,
            full_kv_hit_length,
            action,
        )

    swa_mod.SWAComponent.cleanup_after_caching_req = cleanup_after_caching_req
    swa_mod.SWAComponent._fl6_full_retract_tokens = _fl6_full_retract_tokens
    utc_mod.UnifiedTreeCore._match_prefix_helper = _match_prefix_helper

    _APPLIED = True
    logger.info(
        "FL6 fix applied (retire_interior=%s, full_retract=%s)", retire_on, retract_on
    )
    return True
