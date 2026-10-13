#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""closure_check — M0 闭合校验：census 族账对 DE 实测的预算-实现对账。

数学（任务书 doc102 M0(c)，闭合校验入验收门）：
  Σ(族级 Δms)  = Σ_families max(0, ms_per_step_A - ms_per_step_B)   # A→B 减少的 ms/步
                 （A 独有族 = 整族消亡，全额计入；B 独有族 = 新增成本，另列不计入）
  预期 DE 提升% = Σ(族级 Δms) / B 的 census 步墙 × 100
  实测 ΔDE%    = (per_B - per_A) / per_A × 100        # DE json 同(type,conc) 中位 per
  残差 = 预期 - 实测；|残差| > 3 个百分点 → 打印 UNCLOSED 警告（exit 3）

双口径纪律（M0(d)，DE 口径 ~55ms vs census wall 禁混）：
  报告同时列 census 步墙与 DE 隐含每 token 墙（1000/per），仅作标注，不互算。

口径告警（不同口径也要能出数，但必须标注）：
  - census 版本不一致（v2_host_accounting 等字段只在一侧）→ 打印 CALIBER-MISMATCH
  - 族名跨版本重命名（r11 "16o1_...te_1" vs r12 "MoE FC1 (w4a8 ph1)"）→ 匹配率<60%
    时打印 FAMILY-NAMING 警告，此时 ΣΔms 系统性低估，UNCLOSED 判读须人工复核
  - 步墙方向与 DE 方向相反 + B 出现 draft 族 → 提示投机接受长度贡献（token/步 变了，
    族账只算 ms，不算 token 产额——这正是 r11(SPEC=0)→r12(SPEC=1) 干跑演示的形态）

用法:
  python3 tools/closure_check.py <census_A.json> <census_B.json> <de_A.json> <de_B.json> \
      [--type prose --conc 1] [--pp 3.0]
  A=旧臂（对照），B=新臂（改动后）。DE json = sd_bench --mode de --json-out 产物。
"""
import argparse
import json
import statistics
import sys

import bigread  # 大文件只读探针护栏（>50MB 必流式，QA-TOOLS 20261006）

FAMILY_SUM_FLOOR = 0.60          # 族名匹配率低于此值 → FAMILY-NAMING 警告
DRAFT_FAMILY_HINTS = ("fc1", "draft", "lm_head")   # 投机臂指示族（小写包含）


def load_census(path):
    d = bigread.capped_json_load(path, label="census")
    for k in ("steps", "wall_ms_per_step", "rows"):
        if k not in d:
            raise ValueError(f"{path}: 缺字段 {k}（census 格式见 state/r11_census_c1.json）")
    fams = {r["family"]: r["ms_per_step"] for r in d["rows"]}
    fam_sum = sum(fams.values())
    return {"path": path, "steps": d["steps"], "wall": d["wall_ms_per_step"],
            "fams": fams, "fam_sum": fam_sum,
            "v2": "v2_host_accounting" in d, "keys": set(d.keys())}


def load_de(path, type_, conc):
    d = bigread.capped_json_load(path, label="de")
    rows = d.get("de") or []
    if not rows:
        raise ValueError(f"{path}: 无 de 数组")
    if type_ or conc is not None:
        rows = [r for r in rows
                if (type_ is None or r.get("type") == type_)
                and (conc is None or r.get("conc") == conc)]
    if not rows:
        raise ValueError(f"{path}: 无 type={type_} conc={conc} 的 de 行")
    pers = [r["per"] for r in rows if r.get("per") is not None]
    return {"path": path, "per": statistics.median(pers), "n_runs": len(pers),
            "type": rows[0].get("type"), "conc": rows[0].get("conc")}


def main():
    ap = argparse.ArgumentParser(description="census 族账 vs DE 实测闭合校验")
    ap.add_argument("census_a"); ap.add_argument("census_b")
    ap.add_argument("de_a"); ap.add_argument("de_b")
    ap.add_argument("--type", default=None, help="DE 过滤（默认不过滤，取文件全部行的中位）")
    ap.add_argument("--conc", type=int, default=None)
    ap.add_argument("--pp", type=float, default=3.0, help="UNCLOSED 阈值（百分点，默认 3）")
    a = ap.parse_args()

    try:
        ca, cb = load_census(a.census_a), load_census(a.census_b)
        da, db = load_de(a.de_a, a.type, a.conc), load_de(a.de_b, a.type, a.conc)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as e:
        print(f"PARSE-ERROR {e}")
        return 2

    # ── 族账：A→B ────────────────────────────────────────────────────────
    union = set(ca["fams"]) | set(cb["fams"])
    matched = set(ca["fams"]) & set(cb["fams"])
    match_rate = len(matched) / max(1, len(union))
    reduced = [(f, ca["fams"][f] - cb["fams"][f])
               for f in matched if ca["fams"][f] > cb["fams"][f]]
    eliminated = [(f, ms) for f, ms in ca["fams"].items() if f not in cb["fams"]]
    added = [(f, ms) for f, ms in cb["fams"].items() if f not in ca["fams"]]
    grew = [(f, cb["fams"][f] - ca["fams"][f])
            for f in matched if cb["fams"][f] > ca["fams"][f]]
    sum_reduced = sum(m for _, m in reduced) + sum(m for _, m in eliminated)
    sum_added = sum(m for _, m in added) + sum(m for _, m in grew)

    # ── 预期 vs 实测 ─────────────────────────────────────────────────────
    expected_pp = sum_reduced / cb["wall"] * 100.0
    measured_pp = (db["per"] - da["per"]) / da["per"] * 100.0
    residual_pp = expected_pp - measured_pp
    unclosed = abs(residual_pp) > a.pp

    # ── 报告 ─────────────────────────────────────────────────────────────
    W = print
    W(f"== closure_check  A={ca['path']}  B={cb['path']}")
    W(f"   census A: steps={ca['steps']} wall={ca['wall']}ms/步 "
      f"族Σ={ca['fam_sum']:.2f}ms 覆盖率={ca['fam_sum'] / ca['wall'] * 100:.0f}%")
    W(f"   census B: steps={cb['steps']} wall={cb['wall']}ms/步 "
      f"族Σ={cb['fam_sum']:.2f}ms 覆盖率={cb['fam_sum'] / cb['wall'] * 100:.0f}%")
    W(f"   DE A: per={da['per']} tok/s (type={da['type']} conc={da['conc']} n={da['n_runs']})"
      f"  → DE 隐含 {1000 / da['per']:.1f} ms/token【DE 口径，勿与 census 步墙混用】")
    W(f"   DE B: per={db['per']} tok/s (type={db['type']} conc={db['conc']} n={db['n_runs']})"
      f"  → DE 隐含 {1000 / db['per']:.1f} ms/token【DE 口径】")
    W(f"   Σ(族级 Δms 减少方向) = {sum_reduced:.2f} ms/步 "
      f"(缩减 {sum(m for _, m in reduced):.2f} + 消亡 {sum(m for _, m in eliminated):.2f})")
    W(f"   新增/增长方向        = {sum_added:.2f} ms/步 "
      f"(新增族 {sum(m for _, m in added):.2f} + 增长 {sum(m for _, m in grew):.2f})")
    W(f"   预期 DE 提升 = {sum_reduced:.2f}/{cb['wall']:.1f} = {expected_pp:+.2f} 个百分点")
    W(f"   实测 ΔDE     = ({db['per']}-{da['per']})/{da['per']} = {measured_pp:+.2f} 个百分点")
    W(f"   残差 = {residual_pp:+.2f} pp (阈 {a.pp} pp)")

    # ── 口径告警 ─────────────────────────────────────────────────────────
    caliber_notes = []
    if ca["v2"] != cb["v2"]:
        W("⚠ CALIBER-MISMATCH: census 两侧版本/口径不一致"
          f"（v2_host_accounting: A={ca['v2']} B={cb['v2']}）——数字仍出，判读须人工标注口径")
        caliber_notes.append("census_v2_mismatch")
    if match_rate < FAMILY_SUM_FLOOR:
        W(f"⚠ FAMILY-NAMING: 族名匹配率 {match_rate:.0%} < {FAMILY_SUM_FLOOR:.0%}"
          "（跨版本族名重命名/分类规则变化）→ ΣΔms 系统性低估，残差判读不可机械采信")
        caliber_notes.append("family_naming_mismatch")
    if len(eliminated):
        W(f"   消亡族(前5): {sorted(eliminated, key=lambda x: -x[1])[:5]}")
    if len(added):
        W(f"   新增族(前5): {sorted(added, key=lambda x: -x[1])[:5]}")
    drafty = any(h in f.lower() for f in cb["fams"] for h in DRAFT_FAMILY_HINTS)
    if measured_pp > 0 and cb["wall"] > ca["wall"] and drafty:
        W("⚠ 步墙升而 DE 升 → 投机形态：族账只记 ms/步，DE 还含 token/步（接受长度）变化，"
          "预算-实现天然不闭合于此口径——用 accept_len（eval 三件套③）补记账，勿当 kernel 回归")
        caliber_notes.append("spec_token_yield_dominant")

    if unclosed:
        W(f"UNCLOSED  |残差|={abs(residual_pp):.2f}pp > {a.pp}pp —— 预算与实测未闭合，"
          "禁入验收门；排查序=口径标注→接受长度贡献→族名错配→重测")
    else:
        W(f"CLOSED    |残差|={abs(residual_pp):.2f}pp ≤ {a.pp}pp —— 预算-实现闭合")
    if caliber_notes:
        W(f"caliber_notes={caliber_notes}（判词卡须原样抄录）")
    return 3 if unclosed else 0


if __name__ == "__main__":
    sys.exit(main())
