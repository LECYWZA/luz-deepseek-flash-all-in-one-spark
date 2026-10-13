#!/usr/bin/env python3
"""replay_doc.py — E3A 满载延迟重放·次新主力档补射件（卡 §二步 6 后半）。

driver cmd_recall 的热集恒=最旧三档（pick_hot 固定式）；「次新主力档（最后 2-3 发
入池者）」不在其列。本件 import tools/kvlife_driver.py 复用 Runner.fire——doc_text
构造器逐字同源 ⇒ md5 全同重放语义与 driver 完全一致（零驱动文件改动）。

用法:
  python3 replay_doc.py --rundir <dir> [--doc-id L0031 L0032] [--last-fill-k 2] [--tag hot-full-newest]
    --last-fill-k: 取 rows.jsonl 中最后 k 发 PASS fill 行的 doc_id（LRU 最新端必在树）
"""
import argparse
import importlib.util
import json
import os
import sys

spec = importlib.util.spec_from_file_location(
    "kvlife_driver", os.path.expanduser("~/luz030-opt-campaign/tools/kvlife_driver.py"))
kv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kv)

ap = argparse.ArgumentParser()
ap.add_argument("--plan", default=os.path.expanduser(
    "~/luz030-opt-campaign/logs/KV-LIFE-20261009/plan_v41b.json"))
ap.add_argument("--rundir", required=True)
ap.add_argument("--base", default="http://127.0.0.1:8898")
ap.add_argument("--model", default="deepseek-v4.1-flash")
ap.add_argument("--gen-tokens", type=int, default=24)
ap.add_argument("--water-abort-m", type=int, default=6300)
ap.add_argument("--http-timeout", type=int, default=5400)
ap.add_argument("--doc-id", nargs="*", default=None)
ap.add_argument("--last-fill-k", type=int, default=0)
ap.add_argument("--tag", default="hot-full-newest")
args = ap.parse_args()


class NS:
    pass


ns = NS()
for k, v in vars(args).items():
    setattr(ns, k, v)
ns.tl_budget = 2478000000
ns.snap_every = 10
ns.rows_name = "rows.jsonl"

r = kv.Runner(ns, args.plan)
doc_ids = list(args.doc_id or [])
rows_path = r.rows_path
if args.last_fill_k > 0:
    passed_fill = []
    if os.path.exists(rows_path):
        with open(rows_path, encoding="utf-8") as f:
            for ln in f:
                try:
                    rr = json.loads(ln)
                except ValueError:
                    continue
                if rr.get("status") == "PASS" and str(rr.get("tag")) == "fill":
                    passed_fill.append(rr)
    for rr in passed_fill[-args.last_fill_k:]:
        if rr.get("doc_id") not in doc_ids:
            doc_ids.append(rr["doc_id"])
by_id = {d["doc_id"]: d for d in r.plan["docs"] + r.plan.get("salt", [])}
out = []
for did in doc_ids:
    d = by_id.get(did)
    if d is None:
        print(f"[replay] {did} 不在 plan docs/salt——跳过", flush=True)
        continue
    row = r.fire(d, args.gen_tokens, tag=args.tag)
    out.append(row)
    print(f"[{args.tag}] {did} size={d['target_tokens']} ttft={row.get('ttft_s')} "
          f"status={row.get('status')} md5={row.get('md5','')[:8]}", flush=True)
with open(os.path.join(args.rundir, "replay_newest.json"), "w", encoding="utf-8") as f:
    json.dump({"tag": args.tag, "rows": out}, f, ensure_ascii=False, indent=1)
sys.exit(0 if out else 9)
