#!/usr/bin/env python3
"""f4_attr.py — F4 census 归因扩展（census_stream.py 之上的 record-only 分析器）

法源：F4-CENSUS-WINCARD-20261006 §〇.1/§1.5。红线：解析器=census_stream.py（本文件
import 其 family() 分类法与 MemGuard；kernel_census_v2.py 永禁——本工具零引用）。

新增面（相对 census_stream.py，均保持 O(1) 事件内存不变量——只有 Counter，无 list[dict]）：
  1. 归因键=核全名(截160)+grid+block+smem（z 键退化教训：禁 gridDim.z 单键〔doc34 §6〕）。
     kineto pretty json 中 grid/block/"shared memory" 位于 args 子树行（≥6 空格缩进），
     census_stream 的 4 缩进状态机天然跳过——本文件在同型逐行状态机上增补三个目标 regex。
  2. 五桶族账（W25a taxonomy）：MoE/dense/NCCL-RoCE(RoCE 与 nccl.* 分列)/hc/wo_a + other。
  3. 宽度扫描族识别：族键=核名（归一）+形状语义；成员资格=grid 任一维 == ceil(W/tile)
     （W=MAX_SEQ_LEN_FOR_CAPTURE 派生捕获宽，本形 600000；tile 集合=常用 tile 先验；
     g>=4 防简并碰撞）。600k 形与 128k 形（备选法一语境）同核名⇒同族（族键非 grid 数值）。
  4. 双口径：发射数/步（cat==kernel 事件数÷步，W25a 5381 口径）与键数并报；
     闭合=族账 Σ ÷ gpu_busy（cat∈{kernel,gpu_memcpy,gpu_memset}，M12F 口径）。

用法：
  python3 f4_attr.py <trace.json[.gz]> --json OUT.json [--width-w 600000] [--top 60]
      [--mem-limit-mb 512] [--census-stream PATH/census_stream.py]
"""
import argparse, gzip, importlib.util, json, math, os, re, sys

# ── census_stream.py 装载（解析器世系红线：分类法与 MemGuard 必须来自它）────────
def load_census_stream(path):
    spec = importlib.util.spec_from_file_location("census_stream_f4", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

FIELD = re.compile(r'^    "(ph|cat|name|ts|dur)": (.*?),?\s*$')
GRID_RE = re.compile(r'"grid":\s*\[(\d+),\s*(\d+),\s*(\d+)\]')
BLOCK_RE = re.compile(r'"block":\s*\[(\d+),\s*(\d+),\s*(\d+)\]')
SMEM_RE = re.compile(r'"shared memory":\s*(\d+)')
NAME_NORM = re.compile(r"[^A-Za-z0-9_]+")

# ── tile 先验集（宽度派生 grid 判定用；幂二 64..65536+常用十进制 tile）──────────
TILES = sorted(set(
    [64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048, 3072, 4096, 6144,
     8192, 12288, 16384, 24576, 32768, 49152, 65536]
    + [100, 200, 250, 300, 400, 480, 500, 600, 750, 800, 960, 1000, 1200, 1250,
       1500, 1600, 1875, 2000, 2400, 2500, 3000, 3750, 4000, 5000, 6000, 7500,
       8000, 10000, 12000, 15000, 20000, 24000, 25000, 30000, 40000, 50000, 60000,
       100000, 120000, 150000]))
_GCACHE = {}
def width_tile(g, W, W2=131072):
    """g 是否捕获宽派生（=ceil(Wc/t) 某 t∈TILES，Wc∈{主形 W, 参照形 128k}）。

    双 W 形（卡 §0.3 法三+§1.5 自证④）：族语义=「grid 由捕获宽派生」——600k 冻结形与
    128k 参照形（备选法一语境/长度阶梯 128k 档）同派生语义；族键=核名+形状语义非数值。
    g<4 简并（ceil 碰撞密集带）不判。返回 (Wc, t) 或 None。"""
    if g < 4:
        return None
    key = (g, W, W2)
    if key in _GCACHE:
        return _GCACHE[key]
    hit = None
    for Wc in (W, W2):
        for t in TILES:
            if math.ceil(Wc / t) == g:
                hit = (Wc, t)
                break
        if hit:
            break
    _GCACHE[key] = hit
    return hit

# ── 五桶规则（W25a taxonomy；NCCL 桶内 RoCE 与 nccl.* 分列）────────────────────
def bucket_of(name):
    low = name.lower()
    if ("roce" in low and ("launch" in low or "kernel" in low or "oneshot" in low
                           or "allgather" in low or "reduce" in low or "ar_" in low)):
        return "nccl_roce.roce"
    if "nccldevkernel" in low:
        return "nccl_roce.nccl"
    if ("w4a8_phase1w4a8materializedphase1kernel" in low
            or "w4a8_phase2w4a8materializedphase2kernel" in low
            or "moe_sharedkernelssilu" in low or "silumoedynamic" in low
            or "b12x_next" in low or "b12xmoe" in low):
        return "moe"
    if "dense_blockscaled" in low or "b12xdense" in low or "devicegemmmxfp8gemmsm120" in low:
        return "dense"
    if ("_hc_mix_stats" in low or "_hc_mix_reduce" in low or "_hc_combine" in low
            or "sinkhorn" in low):
        # W25a taxonomy：hc=stats+reduce(sinkhorn)+combine（自证③ 实证 1.579+1.015+0.235=2.829
        # 逐位吻合；_mhc_post_split_h 不入 hc 桶，落 other——W25a 在档账同款）
        return "hc"
    if "_wo_a_" in low:
        return "wo_a"
    return "other"

def width_family_label(name):
    """宽度扫描族键=核名（归一）+形状语义（widthscan 标签）。非 grid 数值。

    成员资格双门（防假阳/假阴，卡 §0.3 法三）：
      ① grid 门：任一维 == ceil(W/tile)（W=捕获宽派生；本形 600000）；
      ② 名字义门：核名含扫描/索引语义 token（index/scan/gather/topk/select/
         position/req_to_token/lookup/argmax/sort/compact/nonzero/tile）——
         同 grid 数值的 MoE GEMM 等（自证④ 阴性）不得混入。
    仅过①未过②的键另列 width_grid_all_keys 诊断面（防 CUTLASS 混名假阴），阶梯平坦性终裁。
    """
    low = name.lower()
    if not any(t in low for t in ("index", "scan", "gather", "topk", "top_k", "select",
                                  "position", "req_to_token", "lookup", "argmax", "sort",
                                  "compact", "nonzero", "tile")):
        return None
    n = NAME_NORM.sub("_", low)[-64:]
    return "widthscan::" + n

def stream(path):
    """逐行状态机（census_stream 同型）+args 行 grid/block/smem 增补。yield 事件 dict。"""
    op = gzip.open if path.endswith(".gz") else open
    cur = {}
    with op(path, "rt", errors="replace") as f:
        for line in f:
            if line.startswith('    "'):
                m = FIELD.match(line)
                if m:
                    k = m.group(1)
                    if k == "ph":
                        if cur:
                            yield cur
                        cur = {"ph": json.loads(m.group(2))}
                    elif cur is not None and cur != {}:
                        try:
                            cur[k] = json.loads(m.group(2))
                        except Exception:
                            pass
                continue
            if line.startswith("  }"):
                if cur:
                    yield cur
                cur = {}
                continue
            # args 子树行（≥6 空格）：仅核目标三键（不落整个 args，保 O(1)）
            # 注：grid/block/smem 常同处一行（kineto 单行 args 形态），逐 regex 并取禁 continue 跳行
            if cur and cur.get("cat") == "kernel":
                g = GRID_RE.search(line)
                if g:
                    cur["grid"] = (int(g.group(1)), int(g.group(2)), int(g.group(3)))
                b = BLOCK_RE.search(line)
                if b:
                    cur["block"] = (int(b.group(1)), int(b.group(2)), int(b.group(3)))
                s = SMEM_RE.search(line)
                if s:
                    cur["smem"] = int(s.group(1))
    if cur:
        yield cur

def analyze(path, census, W=600000, top=60):
    per = {}          # key -> [us, cnt]  归因键=名+grid+block+smem
    bucket_us = {}; bucket_cnt = {}
    wfam_us = {}; wfam_cnt = {}; wfam_keys = {}
    wfam2_us = {}; wfam2_cnt = {}; wfam2_keys = {}   # W2(128k) 参照形诊断面（非主读数）
    wgrid_us = {}; wgrid_cnt = {}   # 仅过 grid 门的诊断面（含名字义门外键，防假阴复核）
    prb = []
    n_kernel = 0; n_launch_ev = 0; gpu_busy_us = 0; runtime_sync_us = 0.0; prb_ann_us = 0.0
    for ev in stream(path):
        if ev.get("ph") != "X":
            continue
        cat = ev.get("cat"); name = ev.get("name", "?"); d = ev.get("dur", 0) or 0
        if cat == "cuda_runtime":
            if "Synchronize" in name:
                runtime_sync_us += d
            continue
        if cat in ("user_annotation", "gpu_user_annotation"):
            # W25a 世系步锚：decode 步=两 cat 合计（a1-b1 实测 29 user + 1 gpu_user = 30 步，
            # 161438 核÷30=5381.3 发射/步、kernel 墙 56.36ms/步——与在档账逐位吻合）
            if name == "scheduler.process_batch_result":
                prb.append((ev.get("ts", 0) or 0, d)); prb_ann_us += d
            continue
        if cat in ("gpu_memcpy", "gpu_memset"):
            gpu_busy_us += d
            continue
        if cat != "kernel":
            continue
        n_launch_ev += 1; n_kernel += 1
        gpu_busy_us += d
        grid = ev.get("grid"); block = ev.get("block"); smem = ev.get("smem")
        nm = name[:160]
        key = "%s|g=%s|b=%s|s=%s" % (nm, grid, block, smem)
        r = per.setdefault(key, [0.0, 0])
        r[0] += d; r[1] += 1
        bk = bucket_of(nm)
        bucket_us[bk] = bucket_us.get(bk, 0.0) + d
        bucket_cnt[bk] = bucket_cnt.get(bk, 0) + 1
        if grid and not bucket_of(nm).startswith("nccl_roce"):
            # 名字义门+非集合通信核（RoCE/nccl 自有桶；bucket_of 返回 nccl_roce.{roce,nccl} 两子形，
            # 须 startswith 判——实盘 w8k 实证 nccldevkernel_allgather_ring_ll（含 gather token、
            # grid=10=ceil(600k/60000) 撞宽度派生带）曾被误入宽度族 27.3ms/步=61% wall 假阳）
            lab = width_family_label(nm)
            for gdim in grid:
                wt = width_tile(gdim, W)
                if wt is not None:
                    wgrid_us[key] = wgrid_us.get(key, 0.0) + d
                    wgrid_cnt[key] = wgrid_cnt.get(key, 0) + 1
                    if lab is not None:
                        # 主读数=W1(600k 冻结形)单形门；W2(128k 参照形)只入 alt 诊断
                        # （1024/512 网格与常核碰撞假阳——f4b1 probe 实证，record-only 收口）
                        if wt[0] == W:
                            wfam_us[lab] = wfam_us.get(lab, 0.0) + d
                            wfam_cnt[lab] = wfam_cnt.get(lab, 0) + 1
                            wfam_keys.setdefault(lab, set()).add(key)
                        else:
                            wfam2_us[lab] = wfam2_us.get(lab, 0.0) + d
                            wfam2_cnt[lab] = wfam2_cnt.get(lab, 0) + 1
                            wfam2_keys.setdefault(lab, set()).add(key)
                    break
    if len(prb) < 3:
        raise SystemExit("f4_attr: process_batch_result <3, refusing（trace 非稳态 decode 窗）")
    prb.sort()
    ts_l = [p[0] for p in prb]
    diffs = sorted(b - a for a, b in zip(ts_l, ts_l[1:]))
    med = diffs[len(diffs) // 2]
    nsteps = len(prb)
    span_ms = (ts_l[-1] + med - ts_l[0]) / 1000.0
    wall_ms = med / 1000.0
    busy_ms = gpu_busy_us / nsteps / 1000.0
    fam_total_us = sum(v[0] for v in per.values())
    closure = fam_total_us / gpu_busy_us * 100.0 if gpu_busy_us else 0.0
    out = {"trace": os.path.basename(path), "width_w": W, "steps": nsteps,
           "decode_span_ms": round(span_ms, 1), "wall_ms_per_step": round(wall_ms, 2),
           "gpu_busy_ms_per_step": round(busy_ms, 2),
           "gpu_busy_pct_of_span": round(gpu_busy_us / (span_ms * 1000) * 100, 1),
           "launches_per_step": round(n_launch_ev / nsteps, 1),
           "n_attribution_keys": len(per),
           "closure_pct_vs_gpu_busy": round(closure, 1),
           "v2_host_accounting": {
               "prb_annotation_avg_us": round(prb_ann_us / nsteps, 1),
               "sync_wait_avg_us": round(runtime_sync_us / nsteps, 1),
               "net_bookkeeping_avg_us": round((prb_ann_us - runtime_sync_us) / nsteps, 1)},
           "buckets": {}, "width_family": {}, "keys_top": []}
    for bk in sorted(bucket_us, key=lambda k: -bucket_us[k]):
        ms = bucket_us[bk] / nsteps / 1000.0
        out["buckets"][bk] = {"ms_per_step": round(ms, 3),
                              "share_wall_pct": round(ms / wall_ms * 100, 2),
                              "share_busy_pct": round(ms / busy_ms * 100, 2),
                              "calls_per_step": round(bucket_cnt[bk] / nsteps, 1)}
    roce = out["buckets"].pop("nccl_roce.roce", None); nccl = out["buckets"].pop("nccl_roce.nccl", None)
    if roce or nccl:
        rms = (roce or {}).get("ms_per_step", 0.0); nms = (nccl or {}).get("ms_per_step", 0.0)
        rc = (roce or {}).get("calls_per_step", 0); nc = (nccl or {}).get("calls_per_step", 0)
        out["buckets"]["nccl_roce"] = {
            "ms_per_step": round(rms + nms, 3),
            "share_wall_pct": round((rms + nms) / wall_ms * 100, 2),
            "calls_per_step": round(rc + nc, 1),
            "sub_roce": roce or {"ms_per_step": 0.0},
            "sub_nccl": nccl or {"ms_per_step": 0.0}}
    wtot = sum(wfam_us.values())
    out["width_family_alt128_only"] = {
        "families": [{"label": lab, "ms_per_step": round(wfam2_us[lab] / nsteps / 1000.0, 4),
                      "calls_per_step": round(wfam2_cnt[lab] / nsteps, 1)}
                     for lab in sorted(wfam2_us, key=lambda k: -wfam2_us[k])]}
    out["width_grid_all_keys"] = [
        {"key": k, "ms_per_step": round(wgrid_us[k] / nsteps / 1000.0, 4),
         "calls_per_step": round(wgrid_cnt[k] / nsteps, 1),
         "name_gate": width_family_label(k.split("|")[0]) is not None}
        for k in sorted(wgrid_us, key=lambda k: -wgrid_us[k])[:40]]
    out["width_family"] = {
        "total_ms_per_step": round(wtot / nsteps / 1000.0, 3),
        "share_wall_pct": round(wtot / nsteps / 1000.0 / wall_ms * 100, 2),
        "share_busy_pct": round(wtot / nsteps / 1000.0 / busy_ms * 100, 2),
        "families": [{"label": lab, "ms_per_step": round(wfam_us[lab] / nsteps / 1000.0, 4),
                      "calls_per_step": round(wfam_cnt[lab] / nsteps, 1),
                      "n_keys": len(wfam_keys[lab]),
                      "keys": sorted(wfam_keys[lab])}
                     for lab in sorted(wfam_us, key=lambda k: -wfam_us[k])]}
    for key, (us, cnt) in sorted(per.items(), key=lambda kv: -kv[1][0])[:top]:
        out["keys_top"].append({"key": key, "ms_per_step": round(us / nsteps / 1000.0, 4),
                                "calls_per_step": round(cnt / nsteps, 1),
                                "bucket": bucket_of(key.split("|")[0])})
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace")
    ap.add_argument("--json", default="")
    ap.add_argument("--width-w", type=int, default=600000)
    ap.add_argument("--top", type=int, default=60)
    ap.add_argument("--census-stream", default=os.path.join(os.path.dirname(
        os.path.abspath(__file__)), "census_stream.py"))
    a = ap.parse_args()
    census = load_census_stream(a.census_stream)
    out = analyze(a.trace, census, W=a.width_w, top=a.top)
    if a.json:
        json.dump(out, open(a.json, "w"), indent=1, ensure_ascii=False)
    print("steps %s  wall %.2f ms/step  busy %.2f  launches/step %s  keys %d  closure %.1f%%  widthΣ %.3f ms/step (%.2f%% wall)"
          % (out["steps"], out["wall_ms_per_step"], out["gpu_busy_ms_per_step"],
             out["launches_per_step"], out["n_attribution_keys"],
             out["closure_pct_vs_gpu_busy"],
             out["width_family"]["total_ms_per_step"], out["width_family"]["share_wall_pct"]))
    print("%-14s%10s%9s%10s" % ("bucket", "ms/step", "share%", "calls/step"))
    for bk, r in out["buckets"].items():
        print("%-14s%10.3f%9.2f%10.1f" % (bk, r["ms_per_step"], r["share_wall_pct"], r["calls_per_step"]))
    if "nccl_roce" in out["buckets"]:
        b = out["buckets"]["nccl_roce"]
        print("  nccl 分列: roce %.3f (%.1f 次) | nccl.* %.3f (%.1f 次)"
              % (b["sub_roce"]["ms_per_step"], b["sub_roce"].get("calls_per_step", 0),
                 b["sub_nccl"]["ms_per_step"], b["sub_nccl"].get("calls_per_step", 0)))
    for f in out["width_family"]["families"][:8]:
        print("WIDTH %-70s %8.4f ms/step %6.1f 次/step keys=%d" % (
            f["label"][:70], f["ms_per_step"], f["calls_per_step"], f["n_keys"]))
    if a.json:
        print("json -> %s" % a.json)
    return 0

if __name__ == "__main__":
    sys.exit(main())
