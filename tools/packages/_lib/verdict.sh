#!/bin/bash
# verdict.sh — T4 自反馈回路共享件（TOOLS31-PACKAGE-PLAN §四.1；五包 bin/<pkg> 共用 source）
#
# 【为什么存在】诊断→建议→（可自动项）执行回路需要统一的结构化出口：操作员/守护读
#   JSON 三字段族判读，读 suggest 执行建议命令，复跑诊断复绿，HEALED 三通道留痕
#   （FABRIC-SELFHEAL §2.2 先例：journal+alerts 文件+state JSON）。
#
# 【三字段族】
#   verdict   : 0=绿 / 1=红 / 2=无法判（ANCHOR-UNKNOWN 语义）
#   red_face  : 红面清单（逐项点名+量值；绿=空数组）
#   suggest   : {text, runbook, auto_ok} —— runbook 锚点=包名#节；auto_ok 布尔
#
# 【auto_ok 白名单（唯一自动项律）】auto_ok=true 仅限：
#   ①GID 洞环回重铺（fabric-gid-heal 四前置+单次尝试+熔断——FABRIC-SELFHEAL §二）；
#   ②logs 先存后删类取证动作（半自动：取证面不丢证据）。
#   禁自动面（U1 教训律：未验证绿的环境禁自动动作）：引擎重启（restore-gate Phase2
#   未晋档）/楔死处置（停手取证律）/boot 拉起（Phase1 只告警档）。本文件不提供任何
#   「执行」原语——suggest.auto_ok 只是声明位，动作执行归包内既有限频/熔断逻辑。
#
# 【用法】（各包 bin/<pkg> 内）：
#   source "$PKG_ROOT/../_lib/verdict.sh"   # 或经 VR_LIB 路径
#   vr_begin; vr_face "F-G5" "hole@rocep1s0f1"; vr_unknown "anchors" "形不在锚表"
#   vr_suggest "按 FABRIC-GID-REPAIR-RUNBOOK §2 环回重铺" "fabric-net#§2" auto
#   vr_emit                                   # stdout 打 JSON；退出码=verdict（0/1/2）
#
# 【退出码规范（§一五件套律）】0=绿 / 1=红 / 2=无法判。子命令面（help/selfcheck）
#   同律：selfcheck 红例判别力抽查≥1/件。
set -u

VR_FACES_FILE=""; VR_UNKNOWN=0; VR_SUGGEST_TEXT=""; VR_SUGGEST_RB=""; VR_SUGGEST_AUTO="false"

vr_begin() {  # 每次诊断前调用（幂等初始化）
  VR_FACES_FILE=$(mktemp /tmp/verdict-faces.XXXXXX)
  VR_UNKNOWN=0; VR_SUGGEST_TEXT=""; VR_SUGGEST_RB=""; VR_SUGGEST_AUTO="false"
}

vr_face() {  # vr_face <红面名> <量值/明细>   ——登记一个红面（verdict 贡献 1）
  { printf '%s\t%s\n' "$1" "$2"; } >>"$VR_FACES_FILE" 2>/dev/null || true
}

vr_unknown() {  # vr_unknown <面名> <明细>   ——登记无法判面（verdict 贡献 2，优先级低于红）
  vr_face "UNKNOWN:$1" "$2"
  VR_UNKNOWN=1
}

vr_suggest() {  # vr_suggest <文案> <runbook 锚（pkg#节）> [auto|manual]
  VR_SUGGEST_TEXT="$1"; VR_SUGGEST_RB="$2"
  case "${3:-manual}" in auto) VR_SUGGEST_AUTO="true" ;; *) VR_SUGGEST_AUTO="false" ;; esac
}

_vr_esc() {  # JSON 字符串净化（双引号/反斜杠/控制字符剥离——建议文案保持单行纯文本）
  printf '%s' "$1" | tr -d '\000-\037' | sed 's/["\\]/ /g'
}

vr_emit() {  # 打 JSON + 以 verdict 为退出码退出
  local red=0 name detail out="["
  if [ -s "${VR_FACES_FILE:-}" ]; then
    local first=1
    while IFS=$'\t' read -r name detail; do
      [ -n "$name" ] || continue
      [ "$first" = 1 ] || out+=", "
      out+="{\"name\":\"$(_vr_esc "$name")\",\"detail\":\"$(_vr_esc "$detail")\"}"
      first=0
      case "$name" in UNKNOWN:*) ;; *) red=1 ;; esac
    done <"$VR_FACES_FILE"
  fi
  out+="]"
  local v=0
  if [ "$red" = 1 ]; then v=1; elif [ "${VR_UNKNOWN:-0}" = 1 ]; then v=2; fi
  printf '{"verdict":%d,"red_face":%s,"suggest":{"text":"%s","runbook":"%s","auto_ok":%s}}\n' \
    "$v" "$out" "$(_vr_esc "${VR_SUGGEST_TEXT:-}")" "$(_vr_esc "${VR_SUGGEST_RB:-}")" "${VR_SUGGEST_AUTO:-false}"
  rm -f "${VR_FACES_FILE:-}" 2>/dev/null || true
  exit "$v"
}

# ── selfcheck（离线红绿双例；被各包 selfcheck 与 packages 级自检复用）──
verdict_selfcheck() {
  local rc=0 T out v
  T=$(mktemp -d /tmp/verdict-selftest.XXXXXX) || return 1
  # T1 绿：零红面零未知 → verdict 0
  out=$( ( vr_begin; vr_suggest "一切正常" "pkg#§0" manual; vr_emit ) 2>/dev/null ); v=$?
  [ "$v" = 0 ] && echo "$out" | grep -q '"verdict":0' && echo "$out" | grep -q '"red_face":\[\]' \
    && echo "[verdict][OK] T1 绿例（verdict=0/red_face 空）" \
    || { echo "[verdict][RED] T1 绿例 FAIL（rc=$v out=$out）"; rc=1; }
  # T2 红：vr_face → verdict 1 + red_face 点名
  out=$( ( vr_begin; vr_face "F-G5" "hole@rocep1s0f1"; vr_suggest "环回重铺" "fabric-net#§2" auto; vr_emit ) 2>/dev/null ); v=$?
  [ "$v" = 1 ] && echo "$out" | grep -q '"verdict":1' && echo "$out" | grep -q 'F-G5' && echo "$out" | grep -q '"auto_ok":true' \
    && echo "[verdict][OK] T2 红例（verdict=1/红面点名/auto_ok 白名单透传）" \
    || { echo "[verdict][RED] T2 红例 FAIL（rc=$v out=$out）"; rc=1; }
  # T3 无法判：仅 unknown → verdict 2
  out=$( ( vr_begin; vr_unknown "anchors" "形不在锚表"; vr_suggest "补锚" "selfdiag#§1" manual; vr_emit ) 2>/dev/null ); v=$?
  [ "$v" = 2 ] && echo "$out" | grep -q '"verdict":2' && echo "$out" | grep -q 'UNKNOWN:anchors' \
    && echo "[verdict][OK] T3 无法判例（verdict=2/ANCHOR-UNKNOWN 语义）" \
    || { echo "[verdict][RED] T3 无法判例 FAIL（rc=$v out=$out）"; rc=1; }
  # T4 红优先于无法判：face+unknown 并存 → verdict 1
  out=$( ( vr_begin; vr_face "X" "y"; vr_unknown "z" "w"; vr_emit ) 2>/dev/null ); v=$?
  [ "$v" = 1 ] && echo "[verdict][OK] T4 红优先例（face+unknown→1）" \
    || { echo "[verdict][RED] T4 红优先例 FAIL（rc=$v out=$out）"; rc=1; }
  # T5 JSON 可解析（python3 -c json.loads）
  out=$( ( vr_begin; vr_face '含"引号"面' "detail\\x"; vr_suggest "文案" "pkg#§1" manual; vr_emit ) 2>/dev/null )
  printf '%s\n' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert set(d)== {"verdict","red_face","suggest"}; assert set(d["suggest"])=={"text","runbook","auto_ok"}' 2>/dev/null \
    && echo "[verdict][OK] T5 JSON 结构三字段族（python3 json.loads 通过+净化）" \
    || { echo "[verdict][RED] T5 JSON 结构 FAIL（out=$out）"; rc=1; }
  rm -rf "$T"
  return "$rc"
}
