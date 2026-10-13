#!/usr/bin/env bash
# env_lint_boot.sh — boot 前置 env lint 拒绝门（GATE-MATRIX L8/L10-A4；QA-GATEHARDEN 20261005）
#
# 法源：RE-CERT-CARD-4 §八三禁令 + R1BISECT-ADJUDICATION §五（E′ 键面 PREFILL 缺位断言）+
#       BOOT-TEMPLATE-REVIEW-20261004 §3-A4（0731 键黑名单）。
# 检查面（fail-closed：文件不可读/形态未注册/解析失败=拒绝启动）：
#   ① 全形态禁键：SGLANG_ENABLE_DETERMINISTIC_INFERENCE（任何值）；
#      PYTORCH_CUDA_ALLOC_CONF 含 expandable_segments:True（False=合法在役值，勿一刀切）；
#      任何值含 kernel_census_v2。
#   ② 形态键黑名单（--form v40731）：DSV41_SKIP_NONFINAL_DECODER / DSV41_ENGRAM_* 族 /
#      DSV41_FP4KV_PORT / DSV41_MOE_B12X_NEXT / DSV41_DG_SPARSE_SM121（BOOT-TEMPLATE A4）。
#   ③ 期望键面合同：--form r1prime = R1′ 五键精确值（CONSUME=1/TIER=triton/ADMISSION=1/
#      CTX_CAP=600000/MRR=16）且 DSV41_SPARSE_LOCAL_PREFILL 必须缺位（防误带）；
#      --form v2 = DSV41_SPARSE_LOCAL_* 族全缺位。
# 用法: env_lint_boot.sh --form <v2|r1prime|v40731> <envfile> [envfile2 …]
#   envfile=KEY=VAL 行式（# 注释/空行跳过）；ARM_ENV_FILE 与产 env 均适用。
#   出口 0=过门 1=REFUSE（拒绝启动）2=用法错。
set -uo pipefail
PROG="$(basename "$0")"
FORM=""
FILES=()

usage() { echo "用法: $PROG --form <v2|r1prime|v40731> <envfile> […]  出口 0=过门 1=REFUSE 2=用法错" >&2; exit 2; }

while [ $# -ge 1 ]; do
  case "$1" in
    --form) [ $# -ge 2 ] || usage; FORM="$2"; shift 2 ;;
    --) shift; while [ $# -ge 1 ]; do FILES+=("$1"); shift; done ;;
    -*) usage ;;
    *) FILES+=("$1"); shift ;;
  esac
done
[ -n "$FORM" ] || usage
[ "${#FILES[@]}" -ge 1 ] || usage
case "$FORM" in
  v2|r1prime|v40731) ;;
  *) printf '[env-lint][REFUSE] 未知形态 --form %s（fail-closed：不认识=拒绝，勿猜）\n' "$FORM" >&2; exit 1 ;;
esac

refuse=0
kv_count=0
declare -A SEEN   # KEY -> VAL（后行覆盖前行=生效行语义；重复键大声记）

for f in "${FILES[@]}"; do
  if [ ! -r "$f" ]; then
    printf '[env-lint][REFUSE] %s 不可读（fail-closed：不可读=在场=拒绝启动）\n' "$f" >&2
    refuse=1
    continue
  fi
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in
      *"="*) ;;
      *) printf '[env-lint][REFUSE] %s:%d 非 KEY=VAL 行且非注释（解析失败=拒绝）：%.60s\n' "$f" "$lineno" "$line" >&2; refuse=1; continue ;;
    esac
    key="${line%%=*}"; val="${line#*=}"
    kv_count=$((kv_count + 1))
    if [ -n "${SEEN[$key]+x}" ]; then
      printf '[env-lint][WARN] %s:%d 键 %s 重复定义（生效=后值；先值=%s）\n' "$f" "$lineno" "$key" "${SEEN[$key]}" >&2
    fi
    SEEN["$key"]="$val"

    # ① 全形态禁键（值级判定：expandable_segments 禁 True 不禁 False）
    case "$key" in
      SGLANG_ENABLE_DETERMINISTIC_INFERENCE)
        printf '[env-lint][REFUSE] %s:%d 禁键 SGLANG_ENABLE_DETERMINISTIC_INFERENCE=%s（RE-CERT-CARD-4 §八禁令）\n' "$f" "$lineno" "$val" >&2; refuse=1 ;;
    esac
    case "$key" in
      PYTORCH_CUDA_ALLOC_CONF)
        if printf '%s' "$val" | grep -q 'expandable_segments:True'; then
          printf '[env-lint][REFUSE] %s:%d 禁值 expandable_segments:True（False=合法在役；RE-CERT-CARD-4 §八）\n' "$f" "$lineno" >&2; refuse=1
        fi ;;
    esac
    if printf '%s' "$val" | grep -q 'kernel_census_v2'; then
      printf '[env-lint][REFUSE] %s:%d 值引用禁件 kernel_census_v2（RE-CERT-CARD-4 §八禁令）\n' "$f" "$lineno" >&2; refuse=1
    fi

    # ② 形态键黑名单
    if [ "$FORM" = v40731 ]; then
      case "$key" in
        DSV41_SKIP_NONFINAL_DECODER|DSV41_FP4KV_PORT|DSV41_MOE_B12X_NEXT|DSV41_DG_SPARSE_SM121|DSV41_ENGRAM_*)
          printf '[env-lint][REFUSE] %s:%d v40731 形黑名单键 %s（BOOT-TEMPLATE-REVIEW §3-A4：v41 专属机制 0731 无对象）\n' "$f" "$lineno" "$key" >&2; refuse=1 ;;
      esac
    fi
  done < "$f"
done

# ③ 期望键面合同（形态注册面内判定；缺位/错值/带禁键都红）
contract_red=0
if [ "$FORM" = r1prime ]; then
  declare -A WANT=( [DSV41_SPARSE_LOCAL_CONSUME]=1
                    [DSV41_SPARSE_LOCAL_CONSUME_TIER]=triton
                    [DSV41_SPARSE_LOCAL_ADMISSION]=1
                    [DSV41_SPARSE_LOCAL_ADMISSION_CTX_CAP]=600000
                    [DSV41_SPARSE_LOCAL_ADMISSION_MRR]=16 )
  for k in "${!WANT[@]}"; do
    got="${SEEN[$k]:-}"
    if [ "$got" != "${WANT[$k]}" ]; then
      printf '[env-lint][REFUSE] 合同(r1prime)：键 %s 期望=%s 实际=%s（FIRE-CARD-R1PRIME5 §一 R1′ 五键）\n' "$k" "${WANT[$k]}" "${got:-<缺位>}" >&2
      contract_red=1
    fi
  done
  if [ -n "${SEEN[DSV41_SPARSE_LOCAL_PREFILL]+x}" ]; then
    printf '[env-lint][REFUSE] 合同(r1prime)：DSV41_SPARSE_LOCAL_PREFILL 必须缺位（R1BISECT 裁定①防误带，实测 -4.87%%）实际=%s\n' "${SEEN[DSV41_SPARSE_LOCAL_PREFILL]}" >&2
    contract_red=1
  fi
elif [ "$FORM" = v2 ]; then
  bad=$(printf '%s\n' "${!SEEN[@]}" | grep -c '^DSV41_SPARSE_LOCAL' || true)
  if [ "$bad" != 0 ]; then
    printf '[env-lint][REFUSE] 合同(v2)：DSV41_SPARSE_LOCAL_* 族应全缺位，实际 %s 键在（v2=stock 现形，prod-restore 键面）\n' "$bad" >&2
    contract_red=1
  fi
fi
[ "$contract_red" = 0 ] || refuse=1

if [ "$refuse" = 0 ]; then
  echo "[env-lint] PASS form=$FORM 生效行=$kv_count（禁键零命中+键面合同符合；boot 可继续）" >&2
  exit 0
fi
echo "[env-lint] REFUSE：拒绝启动（GATE-MATRIX L8——生效行命中即拒，fail-closed）" >&2
exit 1
