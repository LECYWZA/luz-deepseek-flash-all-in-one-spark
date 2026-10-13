#!/bin/bash
# target_verify_reg.sh — target_verify 哨兵 V1 登记器（QA31 §V1 承接；根因专项 2c9cc93 谱系）
#
# 【为什么存在】REDBAND-ROOTCAUSE-20261013：boot 期影子 target_verify 捕获 102.34s vs 健康
#   49.38s（2/2 分离）=**免费预测哨兵**（>75s=预测红带）——每靴一行登记即建预测线，零新增
#   探针成本。QA31 窗内 5 点全落 44.53-45.31s（健康带下沿同域）。
# 【登记源】docker logs <head 容器> 「Engine startup timings」行 target_verify 值（秒）。
# 【表格式（QA31 state/target_verify.tsv 逐字承接）】
#   # 注释头两行（线说明+列说明）；数据行 TSV：
#   靴<TAB>boot 时点(UTC)<TAB>target_verify(s)<TAB>当靴健康态<TAB>来源
# 【纯登记非判读红线】本件**只登记不判档不触发任何动作**（fail-visible 面=登记行本身；
#   >75s 的处置=呈裁面——U1 律：未验证绿的环境禁自动动作）。
#
# 用法：
#   target_verify_reg.sh --from-log <docker-logs 文件> --boot <靴名> [--health <态注>] [--ts <UTC>] <tsv>
#   target_verify_reg.sh --validate <tsv>          # 表健全性（格式+列数+数值域），退出 0/1/2
#   target_verify_reg.sh --selfcheck               # 离线红绿双例（零 docker 零集群）
set -u

extract_tv() {  # 从 docker logs 文本抽 target_verify 秒值（Engine startup timings 行）
  grep -oE 'Engine startup timings.*' "$1" 2>/dev/null \
    | grep -oE 'target_verify[=: ]+[0-9]+(\.[0-9]+)?' | head -1 \
    | grep -oE '[0-9]+(\.[0-9]+)?$'
}

case "${1:-}" in
  --from-log)
    LOG="${2:?--from-log 需文件}"; BOOT="${4:?--boot 需靴名}"
    # 参数序：--from-log <f> --boot <b> [--health h] [--ts t] <tsv>
    HEALTH="见当靴判读（warm 门/四查）"; TS=""; TSV=""
    args=("$@"); i=5
    while [ "$i" -le $# ]; do
      case "${args[$((i-1))]}" in
        --health) HEALTH="${args[$((i))]}"; i=$((i+2)) ;;
        --ts)     TS="${args[$((i))]}";     i=$((i+2)) ;;
        *)        TSV="${args[$((i-1))]}";  i=$((i+1)) ;;
      esac
    done
    [ -n "$TSV" ] || { echo "[tv-reg] 用法错：缺 tsv 位" >&2; exit 2; }
    TV=$(extract_tv "$LOG") || true
    [ -n "$TV" ] || { echo "[tv-reg] RED：日志无 target_verify 值（Engine startup timings 行缺=判据面缺位）" >&2; exit 1; }
    [ -n "$TS" ] || TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    SRC="docker logs $(basename "${LOG%.log}")「Engine startup timings」行"
    if [ ! -f "$TSV" ]; then
      printf '# target_verify 哨兵登记线（V1；根因专项 2c9cc93：健康靴 46-49s/红带靴 102.34s，>75s=预测红带；纯登记非判读线）\n' > "$TSV"
      printf '# 靴\tboot 时点(UTC)\ttarget_verify(s)\t当靴健康态\t来源\n' >> "$TSV"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$BOOT" "$TS" "$TV" "$HEALTH" "$SRC" >> "$TSV"
    echo "[tv-reg] 已登记：$BOOT $TS target_verify=${TV}s → $TSV"
    awk -F'\t' -v tv="$TV" 'BEGIN{exit !(tv+0>75)}' && echo "[tv-reg] WARN：${TV}s > 75s 预测红带（登记照常；处置=呈裁面）"
    ;;
  --validate)
    TSV="${2:?--validate 需 tsv}"; rc=0; unk=0; n=0
    [ -f "$TSV" ] || { echo "[tv-reg] RED：表缺件 $TSV"; exit 1; }
    while IFS=$'\t' read -r b t tv h s; do
      case "$b" in ''|'#'*) continue ;; esac
      n=$((n+1))
      if [ "$(printf '%s\t%s\t%s\t%s\t%s' "$b" "$t" "$tv" "$h" "$s" | awk -F'\t' '{print NF}')" != 5 ]; then
        echo "[tv-reg] RED：第 $n 数据行列数≠5（$b）"; rc=1; continue; fi
      printf '%s' "$tv" | grep -qE '^[0-9]+(\.[0-9]+)?$' || { echo "[tv-reg] RED：第 $n 行 target_verify 非数值（$tv）"; rc=1; }
      printf '%s' "$t" | grep -qE '^2026-[0-9]{2}-[0-9]{2}T' || { echo "[tv-reg] RED：第 $n 行时点非 UTC 形（$t）"; rc=1; }
      [ -n "$h" ] && [ -n "$s" ] || { echo "[tv-reg] RED：第 $n 行健康态/来源空列"; rc=1; }
    done <"$TSV"
    [ "$n" -gt 0 ] || { echo "[tv-reg] UNKNOWN：零数据行（无法判表质量）"; unk=1; }
    [ "$rc" = 0 ] && [ "$unk" = 0 ] && echo "[tv-reg] 表健全绿（$n 行）"
    [ "$rc" = 1 ] && exit 1; [ "$unk" = 1 ] && exit 2; exit 0 ;;
  --selfcheck)  # 离线红绿双例（零 docker 零集群）
    T=$(mktemp -d /tmp/tvreg-sc.XXXXXX); rc=0
    cat > "$T/good.log" <<'EOF'
[2026-10-13 03:04:59] Engine startup timings: model_load=158.2, target_verify=45.31, total=204.5
EOF
    TSV="$T/tv.tsv"; bash "$0" --from-log "$T/good.log" --boot SC-GOOD --ts 2026-10-13T03:05:02Z --health 自检绿例 "$TSV" >/dev/null 2>&1
    v=$(awk -F'\t' 'NR>2{print $3}' "$TSV" | tail -1)
    [ "$v" = "45.31" ] && echo "[tv-reg][OK] T1 抽值绿（45.31）" || { echo "[tv-reg][RED] T1 抽值 FAIL（$v）"; rc=1; }
    bash "$0" --validate "$TSV" >/dev/null 2>&1 && echo "[tv-reg][OK] T2 表健全绿" || { echo "[tv-reg][RED] T2 表健全 FAIL"; rc=1; }
    printf 'BADROW\tnotatime\txyz\t\t\n' >> "$TSV"
    bash "$0" --validate "$TSV" >/dev/null 2>&1 && { echo "[tv-reg][RED] T3 红例失效（坏行未判红）"; rc=1; } || echo "[tv-reg][OK] T3 红例判红（非数值/坏时点=红）"
    echo "[no timing line]" > "$T/bad.log"
    bash "$0" --from-log "$T/bad.log" --boot SC-BAD "$TSV" >/dev/null 2>&1; r=$?
    [ "$r" = 1 ] && echo "[tv-reg][OK] T4 无判据红例判红（exit 1）" || { echo "[tv-reg][RED] T4 FAIL（rc=$r）"; rc=1; }
    printf '# only header\n# cols\n' > "$T/empty.tsv"
    bash "$0" --validate "$T/empty.tsv" >/dev/null 2>&1; r=$?
    [ "$r" = 2 ] && echo "[tv-reg][OK] T5 空表=无法判（exit 2）" || { echo "[tv-reg][RED] T5 FAIL（rc=$r）"; rc=1; }
    rm -rf "$T"; exit "$rc" ;;
  *) echo "用法：$0 --from-log <f> --boot <b> [--health h] [--ts t] <tsv> | --validate <tsv> | --selfcheck" >&2; exit 2 ;;
esac
