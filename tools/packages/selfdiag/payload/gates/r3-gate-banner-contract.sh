#!/usr/bin/env bash
# banner_contract_check.sh — 键面横幅合同比对器（GATE-MATRIX L5；QA-GATEHARDEN 20261005）
#
# 法源：boot_health_r1prime5.sh 查3（FACE-OK/RED 实践，FIRE-CARD §二预登记断言）+
#       go_verify_r1prime5.sh（GO 产面 arm decision 断言）+ prod_restore（v2 面）。
# 合同表（每形态=正面行 ≥1 / 反面模式 =0；arm decision 行按面区分）：
#   er-test  E′ 测试靴（admission 不 armed）：正面 kf/en/b29/slb/sc；反面全 0 含 armed/ad。
#   er-prod  GO 切产后产面（admission 在役）：正面含 arm r1 armed=True；反面=非 r1 形 arm 行 0。
#   c0       F″① CONSUME0 面：gate=(off)+ENGAGED any=0。
#   v2       stock 现形（prod-restore 验收面）：banner28+sparse_local=0+selfcheck。
# 用法: banner_contract_check.sh <er-test|er-prod|c0|v2> <logfile> [logfile2 …]
#   logfile=docker logs 落盘文本（多文件=逐文件判定，任一红=总红）。
#   输出=逐行判定（模式/计数/判）；出口 0=FACE-OK 5=FACE-RED 2=用法错（fail-closed）。
set -uo pipefail
PROG="$(basename "$0")"
red=0

usage() { echo "用法: $PROG <er-test|er-prod|c0|v2> <logfile> […]  出口 0=FACE-OK 5=FACE-RED 2=用法错" >&2; exit 2; }
[ $# -ge 2 ] || usage
FORM="$1"; shift
case "$FORM" in er-test|er-prod|c0|v2) ;; *) printf '[banner-contract][RED] 未知形态 %s（fail-closed）\n' "$FORM" >&2; exit 5 ;; esac

# 合同谓词：cnt FILE PAT -> 计数（grep -c 安全形：|| true 防 pipefail 污染——L1 正确形示范）
cnt() { local n; n=$(grep -c -- "$2" "$1" 2>/dev/null || true); printf '%s' "${n:-0}"; }
judge() { # name count op label
  local name="$1" c="$2"
  case "$3" in
    ge1) if [ "${c:-0}" -ge 1 ] 2>/dev/null; then printf '  [PASS] %-34s count=%s\n' "$name" "$c"; else printf '  [RED ] %-34s count=%s（期望 ≥1）\n' "$name" "$c"; red=1; fi ;;
    eq0) if [ "${c:-0}" -eq 0 ] 2>/dev/null; then printf '  [PASS] %-34s count=%s\n' "$name" "$c"; else printf '  [RED ] %-34s count=%s（期望 =0）\n' "$name" "$c"; red=1; fi ;;
    *)   printf '  [RED ] %s 未知判定子 %s（fail-closed）\n' "$name" "$3"; red=1 ;;
  esac
}

for f in "$@"; do
  if [ ! -r "$f" ]; then
    printf '[banner-contract][RED] %s 不可读（fail-closed：不可读=在场=拒绝）\n' "$f" >&2
    red=1
    continue
  fi
  echo "== $f 合同 form=$FORM =="
  case "$FORM" in
    er-test)
      judge "banner30_31"              "$(cnt "$f" 'banner complete: 3[01] gates')"                     ge1  # 30=R1STD 五参形史档兼容；31=+indexer_budget(W2 F-1 案 A,2026-10-09)
      judge "sparse_local_banner"     "$(cnt "$f" '\[sparse_local\] consume=')"                        ge1
      judge "selfcheck_10_10"         "$(cnt "$f" 'SELF-CHECK PASS (10/10')"                          ge1
      judge "keyface_g1_triton_preoff" "$(cnt "$f" 'consume=gate=1 tier=triton prefill=(off)')"       ge1
      judge "engaged_triton_pre_stock" "$(cnt "$f" 'gather consumer ENGAGED (tier=triton; prefill_consume=stock')" ge1
      judge "anti_prefill_consume_gather" "$(cnt "$f" 'prefill_consume=gather')"                      eq0
      judge "anti_tier_torch"         "$(cnt "$f" 'ENGAGED (tier=torch')"                             eq0
      judge "anti_prefill1_banner"    "$(cnt "$f" '\[sparse_local\] consume=.*prefill=1')"            eq0
      judge "anti_admission_armed"    "$(cnt "$f" 'form-aware admission ARMED')"                      eq0
      judge "anti_arm_decision_any"   "$(cnt "$f" 'arm decision: AdmissionDecision')"                 eq0
      judge "anti_refused_non_benign" "$(grep 'REFUSED' "$f" 2>/dev/null | grep -vc 'DenseBlocks' || true)" eq0
      ;;
    er-prod)
      judge "banner30_31"              "$(cnt "$f" 'banner complete: 3[01] gates')"                     ge1  # 30=R1STD 五参形史档兼容；31=+indexer_budget(W2 F-1 案 A,2026-10-09)
      judge "sparse_local_banner"     "$(cnt "$f" '\[sparse_local\] consume=')"                        ge1
      judge "selfcheck_10_10"         "$(cnt "$f" 'SELF-CHECK PASS (10/10')"                          ge1
      judge "keyface_g1_triton_preoff" "$(cnt "$f" 'consume=gate=1 tier=triton prefill=(off)')"       ge1
      judge "engaged_triton_pre_stock" "$(cnt "$f" 'gather consumer ENGAGED (tier=triton; prefill_consume=stock')" ge1
      judge "arm_r1_600k_armed_true"  "$(cnt "$f" 'arm decision: AdmissionDecision(form=r1 limit=600,000 armed=True')" ge1
      judge "anti_prefill_consume_gather" "$(cnt "$f" 'prefill_consume=gather')"                      eq0
      judge "anti_tier_torch"         "$(cnt "$f" 'ENGAGED (tier=torch')"                             eq0
      judge "anti_prefill1_banner"    "$(cnt "$f" '\[sparse_local\] consume=.*prefill=1')"            eq0
      judge "anti_arm_non_r1_form"    "$(grep 'arm decision: AdmissionDecision' "$f" 2>/dev/null | grep -vc 'form=r1 limit=600,000 armed=True' || true)" eq0
      judge "anti_refused_non_benign" "$(grep 'REFUSED' "$f" 2>/dev/null | grep -vc 'DenseBlocks' || true)" eq0
      ;;
    c0)
      judge "banner29"                "$(cnt "$f" 'banner complete: 29 gates')"                       ge1
      judge "selfcheck_10_10"         "$(cnt "$f" 'SELF-CHECK PASS (10/10')"                          ge1
      judge "keyface_gate_off"        "$(cnt "$f" 'consume=gate=(off)')"                              ge1
      judge "anti_engaged_any"        "$(cnt "$f" 'gather consumer ENGAGED')"                         eq0
      judge "anti_arm_decision_any"   "$(cnt "$f" 'arm decision: AdmissionDecision')"                 eq0
      ;;
    v2)
      judge "banner28"                "$(cnt "$f" 'banner complete: 28 gates')"                       ge1
      judge "selfcheck_ok"            "$(cnt "$f" 'SELF-CHECK')"                                      ge1
      judge "anti_sparse_local_any"   "$(cnt "$f" 'sparse_local')"                                    eq0
      judge "anti_banner29"           "$(cnt "$f" 'banner complete: 29 gates')"                       eq0
      ;;
  esac
done

if [ "$red" = 0 ]; then
  echo "[banner-contract] FACE-OK（form=$FORM 全文件合同符合）"
  exit 0
fi
echo "[banner-contract] FACE-RED（form=$FORM 合同破——停火取证；GATE-MATRIX L5）" >&2
exit 5
