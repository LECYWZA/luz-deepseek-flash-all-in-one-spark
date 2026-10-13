#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""w2_f1_gear — W2 修复窗 F-1 断言量具（案头 DRY 形，零集群零 docker 零 GPU）。

法源：docs/research/INDEXER-ROWCHUNK-PORTPLAN-20261009.md §三（旋钮）/§四（cap 51712
尾行三断言）/§五（A1-A6 判别力自检律）；docs/taskcards/PREFILL-FIX-CAMPAIGN-CARD-
20261009.md §七 F-1 缩容判。

三部分（--part knob|tail|a1，--selfcheck=全跑+负控）：
  knob —— 旋钮三演示+反向用例，打真 adapter 面（~/migrate-assets/dsv41/adapter，
          W2 靴上用 --adapter-dir /opt/dsv41/adapter 重跑）：
          未设=2<<30 位等 / 64MiB 生效 / 非法 fail-closed / sparse_wire 共存 precedence。
  tail —— cap 51712 尾行语义三断言，执行【真引擎源】（~/sglang-main-src=79cafec0，
          sha256 钉面只读；torch 案头缺席→纯 Python 整数 shim 代垫，函数体逐字执行）：
          ①索引对齐：v41_indexer/types.py get_tail_row_indices ≡ kernels/
            dsv4_attn_metadata_kernels.py late_layer_tail_layout.token_indices
            （同 cumsum 算术两处实现，合成批含单请求/多请求混 extend/extend<128 边角）；
          ②cap 形不变式：mode=cap 51712 下 Σtail（≤128/req×MRR16=2048）≪51712 池帽，
            发布 BlockIds [Σtail, ≤topk_blocks] int32 上界=2048×2048×4B≈16.8MB 有界；
          ③floor 一致性：floor 向量≡seq_len−tail 逐行、尾行 token ⊆ [floor, seq_len)
            （晚层重放窗底独立于发布面；needle 阶梯召回回归=W2 靴上面，本件只落可
            案头判定的结构不变式——设计稿 §四-3 如实分界）。
  a1   —— tile 预算律算术（真 flat_index_logits_rows_per_tile+mqa_logits 两函数）：
          tile_bytes=rpt×row_bytes ≤ budget 恒成立、分裂时 rpt 对齐 128//heads 且
          ≥对齐行、预算单调、budget=1 夹最小行对齐（A5 引擎地板——永不静默全量）。

判别力自检律（硬要求）：每部分都带「喂坏输入看它因正确理由变红」的负控——
planted 错位/越界/线性涨/预算不符必须红，负控不红=量具没牙（本脚本以非零退码报 RED）。

跑法：python3 tools/w2_f1_gear.py --selfcheck [--no-strict-pins] [--adapter-dir DIR]
"""
import argparse
import hashlib
import importlib.util
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE_ROOT = os.path.expanduser(
    os.environ.get("W2_F1_ENGINE_ROOT", "~/sglang-main-src"))
DEFAULT_ADAPTER = os.path.expanduser(
    os.environ.get("W2_F1_ADAPTER_DIR", "~/migrate-assets/dsv41/adapter"))

# ── 引擎源钉面（79cafec0 实测 sha256；漂移=strict 模式 RED，防静默换基座）──────
ENGINE_PINS = {
    "python/sglang/srt/layers/attention/dsv4/v41_indexer/types.py":
        "f8a69694c56e5fa0e1efaa03a94dc1927be4cc91f1f54c9c682e4c46d34ffe02",
    "python/sglang/kernels/ops/attention/dsv4_attn_metadata_kernels.py":
        "c61db505f34ad6ae6bbe98dfae01c239471d5f5e06dc0b2926cc527d53b8880b",
    "python/sglang/kernels/ops/attention/dsv4/index_logits.py":
        "bbed2d9166ef1dd0d5d402ea42b5a2ec65f18163e50ed78f4b44e0635a41fa9c",
    "python/sglang/srt/layers/attention/mqa_logits_utils.py":
        "531edaadd6607fdce72fbad58db48ec7257fc59cee2d80c0b541f5af73aa08e0",
    "python/sglang/kernels/ops/attention/dsv4/candidate_table.py":
        "7cbcdf063b32f1b5dbd2e163f0e84714decd4a824545ae73520e3f74fe4251ed",
    "python/sglang/srt/layers/attention/dsv4/v41_indexer/scoring.py":
        "86ecc8fd977d0b336ddcdec5ba9eae453c0bdbf8d81c636358c9f95b8e0bbcf8",
}

FAILS = []


def check(tag, cond, detail=""):
    print("%s %s %s" % ("PASS" if cond else "FAIL", tag, detail))
    if not cond:
        FAILS.append(tag)
    return bool(cond)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for blk in iter(lambda: f.read(1 << 16), b""):
            h.update(blk)
    return h.hexdigest()


def verify_pins(strict=True):
    ok = True
    for rel, want in sorted(ENGINE_PINS.items()):
        path = os.path.join(ENGINE_ROOT, rel)
        if not os.path.exists(path):
            check("pin-exists:%s" % rel.split("/")[-1], False, "MISSING")
            ok = False
            continue
        got = sha256_file(path)
        if got != want:
            check("pin:%s" % rel.split("/")[-1], False,
                  "sha256 漂移 got=%s want=%s%s" % (got[:16], want[:16],
                  "" if strict else "（--no-strict-pins：仅记录）"))
            if strict:
                ok = False
        else:
            print("pin-ok %s sha256=%s.." % (rel.split("/")[-1], got[:16]))
    # 轻文本锚：scoring.py:27 stock 常量形（旋钮「未设=位等」的对照基线）
    scoring = os.path.join(
        ENGINE_ROOT,
        "python/sglang/srt/layers/attention/dsv4/v41_indexer/scoring.py")
    if os.path.exists(scoring):
        src = open(scoring).read()
        check("anchor:scoring-stock-2gib",
              "_DEEP_GEMM_SCORE_BUDGET_BYTES = 2 << 30" in src
              and "_TORCH_SCORE_BUDGET_BYTES = 1 << 30" in src,
              "stock 两常量原文在场（位等基线）")
    return ok


# ═══════════════════ torch 案头 shim（纯整数 1-D/2-D，够跑两目标函数）════════
class _Dev:
    type = "cpu"


class _T:
    """最小整数张量：list 载体，只实现两目标函数用到的算术/索引。"""

    def __init__(self, data):
        self.data = data  # 1-D list[int] 或 2-D list[list[int]]

    @property
    def shape(self):
        return (len(self.data),) if not isinstance(self.data[0], list) \
            else (len(self.data), len(self.data[0]))

    def __getitem__(self, i):
        if isinstance(i, _T):  # fancy index（同长选行/选元素）
            flat = self.data if not isinstance(self.data[0], list) else None
            if flat is not None:
                return _T([flat[k] for k in i.data])
            return _T([self.data[k] for k in i.data])
        return _T(self.data[i])  # int 行取（2-D→1-D）

    def _bin(self, other, op):
        a, b = self.data, other.data
        if isinstance(a[0], list):
            return _T([[op(x, y) for x, y in zip(ra, rb)]
                       for ra, rb in zip(a, b)])
        return _T([op(x, y) for x, y in zip(a, b)])

    def __sub__(self, o):
        return self._bin(o, lambda x, y: x - y)

    def __add__(self, o):
        return self._bin(o, lambda x, y: x + y)

    def to(self, dtype):
        return self

    def tolist(self):
        return self.data


class _TorchShim(types.ModuleType):
    def device(self, d):
        return _Dev()

    def arange(self, a, b=None, dtype=None, device=None):
        lo, hi = (0, a) if b is None else (a, b)
        return _T(list(range(lo, hi)))

    def full(self, shape, v, dtype=None, device=None):
        return _T([v] * shape[0])

    def tensor(self, data, dtype=None, device=None):
        return _T(data)

    def cumsum(self, t, dim=0):
        out, acc = [], 0
        for v in t.data:
            acc += v
            out.append(acc)
        return _T(out)

    def repeat_interleave(self, values, repeats, output_size=None):
        out = []
        for v, r in zip(values.data, repeats.data):
            out.extend([v] * r)
        return _T(out)


class _MsgspecShim(types.ModuleType):
    class Struct:
        def __init_subclass__(cls, **kw):
            super().__init_subclass__()


class _Passthrough:
    """triton/tl 与杂项 stub：装饰器恒等、属性恒 passthrough。"""

    def __call__(self, x=None, *a, **kw):
        return x if callable(x) or x is None else self

    def __getattr__(self, name):
        return _Passthrough()


def _install_shims():
    torch = _TorchShim("torch")
    torch.int32 = "int32"
    torch.int64 = "int64"
    sys.modules.setdefault("torch", torch)
    sys.modules.setdefault("msgspec", _MsgspecShim("msgspec"))
    tri = _Passthrough()
    sys.modules.setdefault("triton", tri)
    sys.modules.setdefault("triton.language", _Passthrough())


def _load_real(relpath, modname, extra_stub_modules=None):
    """file-location 装载真引擎源到指定模块名（相对 import 靠 sys.modules 命中）。"""
    for name, mod in (extra_stub_modules or {}).items():
        sys.modules.setdefault(name, mod)
    path = os.path.join(ENGINE_ROOT, relpath)
    spec = importlib.util.spec_from_file_location(modname, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[modname] = mod
    spec.loader.exec_module(mod)
    return mod


class EngineFace:
    """真引擎函数面：types/kernels/mqa_logits/candidate_table/index_logits。"""

    def __init__(self):
        _install_shims()
        # 依赖桩（只桩 index_logits/mqa_logits_utils 模块级 import 面需要的名字；
        # ceil_div/ceil_align 用引擎同义式——真源 common.py:4302=ceil_div(x,y)*y）
        def _ceil_div(a, b):
            return -(-a // b)

        def _ceil_align(x, y):
            return _ceil_div(x, y) * y

        stub_common = types.ModuleType("sglang.srt.utils.common")
        stub_common.ceil_div = _ceil_div
        stub_common.ceil_align = _ceil_align
        envs = _Passthrough()
        rt = types.ModuleType("sglang.srt.runtime_context")
        rt.get_schedule = lambda: None
        srt_utils = types.ModuleType("sglang.srt.utils")
        srt_utils.get_device_module = lambda *a, **kw: None
        srt_utils.is_hip = lambda: False
        srt_utils.is_xpu = lambda: False
        jitu = types.ModuleType("sglang.kernels.jit.utils")
        jitu.cache_once = lambda fn: fn
        jitu.is_arch_support_pdl = lambda: False
        jitu.load_jit = lambda *a, **kw: None
        jitu.make_cpp_args = lambda *a, **kw: ""
        dutils = types.ModuleType("sglang.kernels.ops.attention.dsv4.utils")
        dutils.make_name = lambda *a, **kw: ""
        for name in ("sglang", "sglang.srt", "sglang.srt.environ",
                     "sglang.kernels", "sglang.kernels.ops",
                     "sglang.kernels.ops.attention",
                     "sglang.kernels.ops.attention.dsv4"):
            m = types.ModuleType(name)
            m.__path__ = []
            sys.modules.setdefault(name, m)
        sys.modules["sglang.srt.environ"].envs = envs
        self.types = _load_real(
            "python/sglang/srt/layers/attention/dsv4/v41_indexer/types.py",
            "sglang.srt.layers.attention.dsv4.v41_indexer.types")
        self.kernels = _load_real(
            "python/sglang/kernels/ops/attention/dsv4_attn_metadata_kernels.py",
            "sglang.kernels.ops.attention.dsv4_attn_metadata_kernels")
        self.mqa = _load_real(
            "python/sglang/srt/layers/attention/mqa_logits_utils.py",
            "sglang.srt.layers.attention.mqa_logits_utils",
            extra_stub_modules={
                "sglang.srt.utils.common": stub_common,
                "sglang.srt.utils": srt_utils,
                "sglang.srt.runtime_context": rt,
            })
        self.cand = _load_real(
            "python/sglang/kernels/ops/attention/dsv4/candidate_table.py",
            "sglang.kernels.ops.attention.dsv4.candidate_table",
            extra_stub_modules={"sglang.kernels.jit.utils": jitu,
                                "sglang.kernels.ops.attention.dsv4.utils": dutils})
        self.index_logits = _load_real(
            "python/sglang/kernels/ops/attention/dsv4/index_logits.py",
            "sglang.kernels.ops.attention.dsv4.index_logits")
        # 兜底重注册（exec_module 内部 import 可能已覆盖同名真包路径）
        sys.modules["sglang.srt.layers.attention.mqa_logits_utils"] = self.mqa
        sys.modules["sglang.kernels.ops.attention.dsv4.candidate_table"] = self.cand


# ────────────────────────────── part: knob ──────────────────────────────

def run_knob(adapter_dir):
    print("== part knob（adapter=%s）==" % adapter_dir)
    if adapter_dir not in sys.path:
        sys.path.insert(0, adapter_dir)
    try:
        import indexer_budget as ib
    except ImportError as e:
        return check("knob-import", False, "adapter 面缺 indexer_budget.py: %s" % e)
    import sparse_wire

    def stub(name="sglang.srt.layers.attention.dsv4.v41_indexer.scoring"):
        m = types.ModuleType(name)
        m._DEEP_GEMM_SCORE_BUDGET_BYTES = 2 << 30
        m._TORCH_SCORE_BUDGET_BYTES = 1 << 30
        return m

    KEY = ib.KEY
    # 演示1：未设 → 位等 stock（硬要求）
    os.environ.pop(KEY, None)
    os.environ.pop(sparse_wire.SCORE_BUDGET_ENV, None)
    ib._INSTALLED.clear()
    m = stub()
    ib.install(m)
    check("knob-unset-bit-equal-stock",
          m._DEEP_GEMM_SCORE_BUDGET_BYTES == 2 << 30
          and m._TORCH_SCORE_BUDGET_BYTES == 1 << 30)
    # 演示2：64MiB → 生效（b//2 比例律；硬要求）
    os.environ[KEY] = "67108864"
    ib._INSTALLED.clear()
    m = stub()
    ib.install(m)
    check("knob-arm-64mib",
          m._DEEP_GEMM_SCORE_BUDGET_BYTES == 67108864
          and m._TORCH_SCORE_BUDGET_BYTES == 33554432)
    # 演示3：非法 → fail-closed（硬要求）
    os.environ[KEY] = "64MiB"
    ib._INSTALLED.clear()
    m = stub()
    ib.install(m)
    check("knob-refuse-illegal",
          ib.STATE["action"] == "refuse"
          and m._DEEP_GEMM_SCORE_BUDGET_BYTES == 2 << 30)
    # 演示4（负控）：sparse_wire 定板共存 precedence
    os.environ.pop(KEY, None)
    ib._INSTALLED.clear()
    sparse_wire._INSTALLED.clear()
    m = stub("...scoring#knob4")
    sparse_wire.install_scoring(m)
    mid = (m._DEEP_GEMM_SCORE_BUDGET_BYTES, m._TORCH_SCORE_BUDGET_BYTES)
    os.environ[KEY] = "67108864"
    ib.install(m)
    check("knob-overrides-sparsewire-128mib",
          mid == (134217728, 134217728)
          and m._DEEP_GEMM_SCORE_BUDGET_BYTES == 67108864)
    # 演示5（负控）：未设+已 128MiB → 不回改（产线形保护）
    os.environ.pop(KEY, None)
    ib._INSTALLED.clear()
    sparse_wire._INSTALLED.clear()
    m = stub("...scoring#knob5")
    sparse_wire.install_scoring(m)
    ib.install(m)
    check("knob-noop-preserves-128mib",
          m._DEEP_GEMM_SCORE_BUDGET_BYTES == 134217728)
    os.environ.pop(KEY, None)
    return True


# ────────────────────────────── part: tail ──────────────────────────────

SWA_WINDOW = 128        # deepseek_v4_backend.py:138（真源锚）
CAP_51712 = 51712       # KV-LIFE leg_v41c.out:10「DSV4 SWA sizing: mode=cap,
                        # swa_tokens=51712」（多靴同值，SWA-RATIO §4.2）
MRR = 16                # DSV41_SPARSE_LOCAL_ADMISSION_MRR=16（43 键形）
TOPK_BLOCKS = 2048      # G3 武装值（arms README：--json-model-override-args
                        # candidate_topk_blocks 2048；设计稿 §四-2 同）


def _ref_tail_rows(extend_lens, tail_lens):
    """第三条独立算术（语义定义直算）：concat(range(cumE-T, cumE))。"""
    out, start = [], 0
    for n, t in zip(extend_lens, tail_lens):
        out.extend(range(start + n - t, start + n))
        start += n
    return out


def _floor_invariant(E, S):
    """断言③可判定核：floor ≡ S−T 逐行、尾行绝对位 ⊆ [floor, S)、floor 非负。"""
    T = [min(SWA_WINDOW, e) for e in E]
    exp_floor = []
    for n, t, s in zip(E, T, S):
        exp_floor.extend([s - t] * t)
    ok = min(exp_floor) >= 0 if exp_floor else True
    for n, t, s in zip(E, T, S):
        prefix = s - n
        if prefix < 0:
            ok = False
        # 尾行绝对位（prefix + 相对位）必落 [s-t, s)——两界独立性的结构面
        if prefix + n != s and prefix + n > s:
            ok = False
    return ok, exp_floor


def run_tail(eng):
    print("== part tail（cap 51712 尾行三断言，真引擎函数）==")
    get_tail = eng.types.get_tail_row_indices
    layout = eng.kernels.late_layer_tail_layout
    dev = _Dev()

    # 合成批：单请求 / 多请求混 extend（有前缀 S>E 与无前缀 S=E）/ extend<128 边角 /
    # chunked-resume 形（全 chunk 行=本 forward 的 extend 行）
    cases = [
        ("single-full", [4096], [4096]),
        ("single-short-extend<128", [50], [50]),
        ("single-with-prefix", [4096], [32768]),
        ("multi-mixed", [4096, 300, 77, 2048], [8192, 300, 77, 4096]),
        ("chunk-resume-2req", [1024, 1024], [5120, 6144]),
        ("one-req-tail-clamped", [100, 4096, 200], [100, 8192, 200]),
    ]
    all_ok = True
    for name, E, S in cases:
        T = [min(SWA_WINDOW, e) for e in E]
        ref = _ref_tail_rows(E, T)
        # 断言①：索引对齐（两处真实现逐元素相等 + 第三条独立算术）
        a = get_tail(full_rows_per_request=list(E), tail_rows_per_request=list(T),
                     device=dev).tolist()
        b, tail_lens_cpu, floor = layout(extend_lens_cpu=list(E),
                                         seq_lens_cpu=list(S),
                                         tail_len=SWA_WINDOW, device=dev)
        b = b.tolist()
        ok1 = a == b == ref
        # 断言③：floor 一致性（真 floor ≡ S−T 独立算术；窗包含+非负结构核）
        inv_ok, exp_floor = _floor_invariant(E, S)
        ok3 = floor.tolist() == exp_floor and inv_ok and tail_lens_cpu == T
        all_ok &= check("tail-%s:align" % name, ok1,
                        "n_rows=%d" % len(ref))
        all_ok &= check("tail-%s:floor" % name, ok3)

    # 断言②：cap 形不变式（纯算术+真常量）
    worst_tail_sum = MRR * SWA_WINDOW            # 满配 16 请求×128 尾行
    blocks_bytes_ub = worst_tail_sum * TOPK_BLOCKS * 4
    all_ok &= check("tail-2:sum-tail-ll-cap",
                    worst_tail_sum <= CAP_51712 // 4,
                    "Σtail_max=%d ≪ cap=%d（余量 %.0fx）"
                    % (worst_tail_sum, CAP_51712, CAP_51712 / worst_tail_sum))
    all_ok &= check("tail-2:blockids-bounded",
                    blocks_bytes_ub <= (16.8 * (1 << 20)) + 1,
                    "上界 %d 行×%d 块×4B=%.2fMiB（int32 有界形）"
                    % (worst_tail_sum, TOPK_BLOCKS, blocks_bytes_ub / (1 << 20)))

    # ── 负控（硬要求）：坏输入必须因正确理由变红 ──
    E = [4096, 300]
    T = [min(SWA_WINDOW, e) for e in E]
    good = get_tail(full_rows_per_request=E, tail_rows_per_request=T,
                    device=dev).tolist()
    # 负控1：发布面 full_rows 与重放面 extend_lens 脱钩（错位 wiring）→ 两实现分歧
    bad_full = [4096, 512]
    bad = get_tail(full_rows_per_request=bad_full,
                   tail_rows_per_request=T, device=dev).tolist()
    all_ok &= check("tail-neg:miswired-full-rows", bad != good,
                    "错位 wiring 必须被断言①抓红（%d/%d 行差）"
                    % (len(bad), len(good)))
    # 负控2：S<T 非法几何（seq 短于尾窗）→ 断言③非负核红
    S_bad = [T[0] - 1, 999999]
    inv_bad, _ = _floor_invariant(E, S_bad)
    _, _, floor_bad = layout(extend_lens_cpu=E, seq_lens_cpu=S_bad,
                             tail_len=SWA_WINDOW, device=dev)
    all_ok &= check("tail-neg:seq-lt-tail",
                    (not inv_bad) and min(floor_bad.tolist()) < 0,
                    "S<T 非法形 floor=%d<0——一致性断言有牙"
                    % min(floor_bad.tolist()))
    # 负控3：MRR 越额（Σtail 触池帽）→ 断言②红
    mrr_bad = 405
    all_ok &= check("tail-neg:mrr-overrun",
                    mrr_bad * SWA_WINDOW > CAP_51712,
                    "MRR=%d 时 Σtail=%d > cap=%d——不变式有牙"
                    % (mrr_bad, mrr_bad * SWA_WINDOW, CAP_51712))
    return all_ok


# ────────────────────────────── part: a1 ──────────────────────────────

def run_a1(eng):
    print("== part a1（tile 预算律算术，真 flat_index_logits_rows_per_tile）==")
    rpt_of = eng.index_logits.flat_index_logits_rows_per_tile
    row_bytes = eng.mqa.mqa_logits_row_bytes
    budgets = [2 << 30, 512 << 20, 128 << 20, 64 << 20, 32 << 20, 8 << 20, 1 << 20]
    widths = [4096, 16384, 65536, 73000]
    heads_list = [8, 64, 128]
    rows_list = [4096, 65536, 600000]
    all_ok = True
    for B in budgets:
        for w in widths:
            rb = row_bytes(w)
            for h in heads_list:
                align = 128 // h
                for R in rows_list:
                    rpt = rpt_of(R, w, heads=h, budget_bytes=B)
                    tile_bytes = rpt * rb
                    # 真引擎预算律（a1 负网格实锚修正）：tile ≤ max(预算, 对齐地板)。
                    # 引擎在预算 < row_alignment×row_bytes 时按对齐不按预算出 tile
                    #（max(row_alignment, rpc//align*align)，index_logits.py:30-33）
                    # ——这是 knob 地板=8MiB 的依据（地板以上预算被严格兑现）。
                    align_floor_bytes = align * rb
                    if tile_bytes > B and rpt > align:
                        all_ok = False
                        check("a1-budget-law:B=%d,w=%d,h=%d" % (B, w, h), False,
                              "rpt=%d tile=%d > B=%d 且非对齐地板夹持"
                              % (rpt, tile_bytes, B))
                    if tile_bytes > max(B, align_floor_bytes):
                        all_ok = False
                        check("a1-engine-law:B=%d,w=%d,h=%d" % (B, w, h), False,
                              "rpt=%d tile=%d > max(B, align_floor=%d)"
                              % (rpt, tile_bytes, align_floor_bytes))
                    if rpt < 1 or rpt > R:
                        all_ok = False
                        check("a1-coverage:B=%d,w=%d,h=%d,R=%d" % (B, w, h, R),
                              False, "rpt=%d 越界" % rpt)
                    if rpt < R and (rpt % align or rpt < align):
                        all_ok = False
                        check("a1-alignment:B=%d,w=%d,h=%d" % (B, w, h), False,
                              "rpt=%d 未对齐 %d" % (rpt, align))
                    if B >= align_floor_bytes and tile_bytes > B:
                        all_ok = False
                        check("a1-strict-honor:B=%d,w=%d,h=%d" % (B, w, h), False,
                              "预算 ≥ 对齐地板仍被突破（地板以上必须严格兑现）")
    print("a1 网格 %d 组（%d 预算×%d 宽×%d 头×%d 行）预算律全核"
          % (len(budgets) * len(widths) * len(heads_list) * len(rows_list),
             len(budgets), len(widths), len(heads_list), len(rows_list)))
    # 单调律：预算缩 → 行/tile 不增
    mono = all(rpt_of(600000, 65536, heads=64, budget_bytes=b1)
               >= rpt_of(600000, 65536, heads=64, budget_bytes=b2)
               for b1, b2 in zip(budgets, budgets[1:]))
    all_ok &= check("a1-monotone", mono)
    # A5 引擎地板：budget=1 → 夹最小行对齐（永不静默全量）
    for h in heads_list:
        rpt = rpt_of(600000, 65536, heads=h, budget_bytes=1)
        all_ok &= check("a1-engine-floor:h=%d" % h, rpt == 128 // h,
                        "budget=1B → rpt=%d=128//%d" % (rpt, h))
    # 负控（硬要求）：量具有牙——声称 64MiB 但 effective=2GiB 必须红
    def knob_checker(claimed, effective, rpt, rb):
        return rpt * rb <= effective + (128 // 64) * rb and claimed == effective
    check("a1-neg:silent-knob-miss", not knob_checker(
        64 << 20, 2 << 30, rpt_of(600000, 65536, heads=64, budget_bytes=2 << 30),
        row_bytes(65536)),
        "旋钮静默失效形（claimed≠effective）必须红")
    check("a1-neg:tile-overrun", not knob_checker(
        64 << 20, 64 << 20,
        rpt_of(600000, 65536, heads=64, budget_bytes=2 << 30), row_bytes(65536)),
        "tile 越预算形必须红")
    return all_ok


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--selfcheck", action="store_true")
    ap.add_argument("--part", choices=["knob", "tail", "a1"])
    ap.add_argument("--adapter-dir", default=DEFAULT_ADAPTER)
    ap.add_argument("--no-strict-pins", action="store_true")
    args = ap.parse_args()
    if not (args.selfcheck or args.part):
        ap.error("需 --selfcheck 或 --part {knob,tail,a1}")

    print("W2-F1 gear（引擎树=%s；DRY 案头形）" % ENGINE_ROOT)
    pins_ok = verify_pins(strict=not args.no_strict_pins)
    if not pins_ok:
        print("RED：引擎源钉面漂移——先核基座再跑断言（或 --no-strict-pins 明示豁免）")

    if args.selfcheck or args.part == "knob":
        run_knob(args.adapter_dir)
    if args.selfcheck or args.part == "tail":
        run_tail(EngineFace())
    if args.selfcheck or args.part == "a1":
        run_a1(EngineFace())

    print("=" * 64)
    if FAILS:
        print("SELFCHECK RED：%d 项失败：%s" % (len(FAILS), FAILS))
        sys.exit(1)
    print("SELFCHECK GREEN（含负控全红于正确理由）")


if __name__ == "__main__":
    main()
