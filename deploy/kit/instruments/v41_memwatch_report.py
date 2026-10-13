#!/usr/bin/env python3
"""v41_memwatch_report.py — 由 v41_memwatch.sh 的 TSV 算每档内存瞬态账

语义（与 Boot6 drain 台账同构，逐项可复核）：
  窗口  base    = [mark_start-30s, mark_start) 的中位数   ← 剂量前站定水位
        dose    = [mark_start, mark_end]                  ← 剂量执行窗
        settled = [mark_end+SETTLE, mark_end+SETTLE+30s)   ← 静置回落后水位
  指标  dip      = base - min(dose)          剂量期总跌幅（含持久 KV first-touch）
        persist  = base - settled            没回来的部分（KV first-touch = 持久）
        transient= settled - min(dose)       回来的部分（真·瞬态峰值）
        min_free = min(MemFree, dose)        驱动侧可见空闲最低点
  闸门  硬闸 G1: min(eff_idle) >= FLOOR_G      （独立于守卫止损线 1.5；G1 默认 3）
        主闸 G2: transient      <= TRANSIENT_G （用户判据：瞬态峰值增量 ≤3G）
  参考  d_transient / d_dip = 与前一档的差（增量趋势；不参与判决）

用法：
  v41_memwatch_report.py <memwatch_dir> [--floor 3] [--transient 3] [--settle 60] [--json out.json]
  memwatch_dir 内文件名形如 memwatch.<host>.tsv
"""
import json
import statistics
import sys
from pathlib import Path

BASE_S = 30.0        # 剂量前基线窗（秒）
SETTLE_S = 60.0      # 剂量后静置（等 idle-release 落地）
SETTLED_WIN_S = 30.0
GIB = 1024 * 1024.0  # KiB → GiB


def parse(path):
    rows, marks, host = [], {}, None
    for line in Path(path).read_text().splitlines():
        if not line or line.startswith("#HOST"):
            if line.startswith("#HOST"):
                host = line.split()[1]
            continue
        if line.startswith("#END"):
            continue
        p = line.split()
        if p[0] == "S":
            rows.append((int(p[1]) / 1000.0, int(p[2]), int(p[3]),
                         int(p[7]) if len(p) > 7 else None))
        elif p[0] == "M":
            marks[int(p[1]) / 1000.0] = p[2]
    return host or Path(path).stem, rows, marks


def med(vals):
    return statistics.median(vals) if vals else None


def window(rows, t0, t1, idx=1):
    return [r[idx] for r in rows if t0 <= r[0] < t1 and r[idx] is not None]


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    d = Path(args[0])
    floor_g, trans_g, settle = 3.0, 3.0, SETTLE_S
    json_out = None
    i = 1
    while i < len(args):
        if args[i] == "--floor":
            floor_g = float(args[i + 1]); i += 2
        elif args[i] == "--transient":
            trans_g = float(args[i + 1]); i += 2
        elif args[i] == "--settle":
            settle = float(args[i + 1]); i += 2
        elif args[i] == "--json":
            json_out = args[i + 1]; i += 2
        else:
            i += 1

    files = sorted(d.glob("memwatch.*.tsv"))
    if not files:
        print(f"[report] {d} 下没有 memwatch.*.tsv")
        return 2

    per_host = {}
    dose_order = []
    for f in files:
        host, rows, marks = parse(f)
        per_host[host] = (rows, marks)
        for tag in marks.values():
            name = tag.replace("START:", "").replace("END:", "")
            if name not in dose_order:
                dose_order.append(name)

    # 空真防线（2026-09-22 T4 事故）：dose_order 为空时下游 results 也为空，
    # 而 `bad = [...]` 在空列表上恒为空 ⇒ 打印「全部档位过闸」并返回 0。
    # 实测后果：T4 剂量段被 flush 中止、一行数据都没采到，报告却给了绿字。
    # 判据必须是「有数据」而非「没有坏数据」——故此处先断非空。
    if not dose_order:
        print(f"[report] ⛔ 采样里一个剂量标记都没有（files={len(files)}）"
              f"⇒ 判决不可用（不是“全过”）")
        return 2

    results = []
    skipped = []
    for dose in dose_order:
        rec = {"dose": dose, "hosts": {}}
        for host, (rows, marks) in sorted(per_host.items()):
            t0 = t1 = None
            for t, tag in marks.items():
                if tag == f"START:{dose}":
                    t0 = t
                if tag == f"END:{dose}":
                    t1 = t
            if t0 is None or t1 is None:
                continue
            base = med(window(rows, t0 - BASE_S, t0))
            dose_min = min(window(rows, t0, t1)) if window(rows, t0, t1) else None
            settled = med(window(rows, t1 + settle, t1 + settle + SETTLED_WIN_S))
            min_free = min(window(rows, t0, t1, idx=2)) if window(rows, t0, t1, idx=2) else None
            min_avail = min(window(rows, t0, t1, idx=3)) if window(rows, t0, t1, idx=3) else None
            if None in (base, dose_min, settled, min_free):
                continue
            rec["hosts"][host] = {
                "samples": len(window(rows, t0, t1)),
                "base_gib": round(base / GIB, 2),
                "min_gib": round(dose_min / GIB, 2),
                "settled_gib": round(settled / GIB, 2),
                "min_free_gib": round(min_free / GIB, 2),
                "min_avail_gib": round(min_avail / GIB, 2) if min_avail is not None else None,
                "dip_gib": round((base - dose_min) / GIB, 2),
                "persist_gib": round((base - settled) / GIB, 2),
                "transient_gib": round((settled - dose_min) / GIB, 2),
            }
        if not rec["hosts"]:
            # 有标记却采不到任何主机数据（ssh 掉档 / 机器已楔死 / 采样器没起）
            # ⇒ 这一档**没有判决**，不能当作"没有坏消息"。必须出声。
            skipped.append(dose)
            continue
        h = rec["hosts"]
        rec["min_eff_idle_gib"] = min(v["min_gib"] for v in h.values())
        rec["max_transient_gib"] = max(v["transient_gib"] for v in h.values())
        rec["max_dip_gib"] = max(v["dip_gib"] for v in h.values())
        rec["min_free_gib"] = min(v["min_free_gib"] for v in h.values())
        av = [v["min_avail_gib"] for v in h.values() if v["min_avail_gib"] is not None]
        rec["min_avail_gib"] = min(av) if av else None
        rec["worst_host"] = max(h, key=lambda k: h[k]["transient_gib"])
        rec["G1_floor_ok"] = rec["min_eff_idle_gib"] >= floor_g
        rec["G2_transient_ok"] = rec["max_transient_gib"] <= trans_g
        results.append(rec)

    prev_t = prev_d = None
    for r in results:
        r["d_transient_gib"] = round(r["max_transient_gib"] - prev_t, 2) if prev_t is not None else None
        r["d_dip_gib"] = round(r["max_dip_gib"] - prev_d, 2) if prev_d is not None else None
        prev_t, prev_d = r["max_transient_gib"], r["max_dip_gib"]

    hdr = (f"{'dose':>8} {'min_eff_idle':>12} {'min_free':>9} {'min_avail*':>10} {'dip':>7} {'persist':>8} "
           f"{'transient':>9} {'Δtrans':>7} {'Δdip':>6}  {'G1':>3} {'G2':>3}  worst_host")
    print(hdr)
    print("-" * len(hdr))
    for r in results:
        print(f"{r['dose']:>8} {r['min_eff_idle_gib']:>12.2f} {r['min_free_gib']:>9.2f} "
              f"{(r['min_avail_gib'] if r['min_avail_gib'] is not None else float('nan')):>10.2f} "
              f"{r['max_dip_gib']:>7.2f} {'':>8} {r['max_transient_gib']:>9.2f} "
              f"{(r['d_transient_gib'] if r['d_transient_gib'] is not None else 0):>7.2f} "
              f"{(r['d_dip_gib'] if r['d_dip_gib'] is not None else 0):>6.2f}  "
              f"{'OK' if r['G1_floor_ok'] else 'FAIL':>3} "
              f"{'OK' if r['G2_transient_ok'] else 'FAIL':>3}  {r['worst_host']}")
    print("(* min_avail = 历史口径 MemAvailable，仅供跨靴对照；判据一律用 eff_idle)")
    print()
    for r in results:
        print(f"[{r['dose']}] 逐机（GiB）：")
        for host, v in sorted(r["hosts"].items()):
            va = v.get("min_avail_gib")
            print(f"    {host:<12} base={v['base_gib']:>6.2f} min={v['min_gib']:>6.2f} "
                  f"settled={v['settled_gib']:>6.2f} minFree={v['min_free_gib']:>6.2f} "
                  f"minAvail={(va if va is not None else float('nan')):>6.2f} "
                  f"dip={v['dip_gib']:>5.2f} persist={v['persist_gib']:>5.2f} transient={v['transient_gib']:>5.2f} "
                  f"(n={v['samples']})")
    if json_out:
        Path(json_out).write_text(json.dumps(
            {"floor_gib": floor_g, "transient_gib": trans_g, "settle_s": settle, "doses": results},
            ensure_ascii=False, indent=1))
    bad = [r["dose"] for r in results if not (r["G1_floor_ok"] and r["G2_transient_ok"])]
    if bad:
        print(f"\n[gate] 越闸档：{', '.join(bad)} —— 停手判据已触发")
        if skipped:
            print(f"[gate] ⚠ 另有 {len(skipped)} 档无数据（未判决）：{', '.join(skipped)}")
        return 1
    # 空真防线（2026-09-22）：results 为空时上面的 bad 恒空 ⇒ 会打印"全过"。
    # 走到这里意味着"一档都没判决"，结论只能是"不可用"。
    if not results:
        print(f"\n[gate] ⛔ 0 档有判决数据 ⇒ 不可用（不是“全部过闸”）；无数据档：{', '.join(skipped)}")
        return 2
    print("\n[gate] 全部档位过闸", end="")
    print(f"（{len(results)} 档已判）" + (f"；⚠ {len(skipped)} 档无数据：{', '.join(skipped)}" if skipped else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
