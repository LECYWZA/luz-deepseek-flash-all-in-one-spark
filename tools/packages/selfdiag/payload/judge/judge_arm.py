#!/usr/bin/env python3
"""judge_arm.py — E3A 判读真值源读取件（引擎 #cached-token + TTFT 差分双源）。

输入：rundir（rows.jsonl）+ engine log slice（docker logs --since 捕获段）。
输出：每 hot/cold/replay 行的引擎命中与 TTFT 比（API usage.cached_tokens 恒 0=已知缺陷不采）。

归属法（v3 顺序合并游走）：row.ts=请求起（blank_row 于 ask 前打点）；recall c=1 严格
串行 ⇒ 请求与引擎 Prefill 行按时间互嵌。游走：行按 t 排序，请求按 ts 排序；每请求
吞掉 [ts−0.5, 下一请求 ts−0.5) 内的行，其 cached=吞入首行（radix match 计数挂请求
首个 prefill batch 行）。引擎日志窗外的行（engine 空）标记 None=不判。
"""
import datetime
import json
import re
import sys

LINE = re.compile(r"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})[^\]]*\] Prefill batch, #new-seq: (\d+), #new-token: (\d+), #cached-token: (\d+)")


def parse_engine(path):
    evs = []
    try:
        with open(path, errors="replace") as f:
            for ln in f:
                m = LINE.search(ln)
                if m:
                    t = datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S").replace(
                        tzinfo=datetime.timezone.utc).timestamp()
                    evs.append((t, int(m.group(2)), int(m.group(3)), int(m.group(4))))
    except FileNotFoundError:
        pass
    evs.sort(key=lambda e: e[0])  # 仅按时间稳定序（元组整比会在同秒行上按 new_token 重排=错源）
    return evs


def main(rundir, engine_log):
    rows = []
    with open(f"{rundir}/rows.jsonl", encoding="utf-8") as f:
        for ln in f:
            try:
                rows.append(json.loads(ln))
            except ValueError:
                pass
    fill_first = {}
    for r in rows:
        if r.get("status") == "PASS" and str(r.get("tag")) == "fill" and r.get("doc_id") not in fill_first:
            fill_first[r["doc_id"]] = r
    evs = parse_engine(engine_log) if engine_log else []
    tlo = evs[0][0] - 1 if evs else None
    thi = evs[-1][0] + 1 if evs else None
    # 判读对象行（hot/cold/replay/newest），ts 升序
    cand = [r for r in rows
            if (str(r.get("tag", "")).startswith(("hot-", "cold-"))
                or "newest" in str(r.get("tag", "")) or "replay" in str(r.get("tag", "")))
            and r.get("ts")]
    cand.sort(key=lambda r: r["ts"])
    cur = 0
    cached_map = {}
    for i, r in enumerate(cand):
        ts = r["ts"]
        if tlo is not None and not (tlo <= ts <= thi):
            continue  # 引擎窗外（他 checkpoint 行）——不判
        # 闭包归属：请求串行 c=1 ⇒ 其 Prefill 行=自 cursor 起的连续段，
        # Σnew-token ≈ prompt − 首行 cached（分块 prefill 恒等式；亚秒请求亦可分）
        p = r.get("prompt_tokens") or 0
        if cur < len(evs):
            first = evs[cur]
            cached_map[(r["tag"], r["doc_id"], ts)] = first[3]
            need = max(0, p - first[3])
            got = first[2]
            cur += 1
            while cur < len(evs) and got < need:
                got += evs[cur][2]
                cur += 1
    out = []
    for r in cand:
        tag = str(r.get("tag", ""))
        if r.get("status") != "PASS" or not r.get("ttft_s"):
            out.append({"tag": tag, "doc_id": r.get("doc_id"), "status": r.get("status"),
                        "note": "非 PASS/无 ttft——如实记"})
            continue
        mcached = cached_map.get((tag, r.get("doc_id"), r["ts"]))
        p = r.get("prompt_tokens") or 0
        eng_hit = (mcached is not None and p and mcached >= p - 384)
        orig = fill_first.get(r.get("doc_id"))
        ratio = round(r["ttft_s"] / orig["ttft_s"], 4) if (orig and orig.get("ttft_s")) else None
        ttft_hit = (ratio is not None and ratio < 0.3)
        out.append({"tag": tag, "doc_id": r.get("doc_id"), "size": r.get("target_tokens"),
                    "prompt": p, "ttft_replay": r.get("ttft_s"),
                    "ttft_fill_orig": orig.get("ttft_s") if orig else None,
                    "ttft_ratio": ratio, "engine_first_cached": mcached,
                    "engine_cached_over_prompt": (round(mcached / p, 4) if (mcached is not None and p) else None),
                    "engine_hit": bool(eng_hit), "ttft_hit": bool(ttft_hit),
                    "cold_band_check": None,
                    "md5": r.get("md5"), "weak_ok": r.get("weak_ok"), "ts": r["ts"]})
    for o in out:
        print(json.dumps(o, ensure_ascii=False))
    with open(f"{rundir}/judge_rows.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")
