#!/bin/bash
# gw-verify — 并发网关验证器（五探针+离线配置 lint；TOOLS31 §二 P4-3）
#
# 【五探针（--live；执行窗面）】
#   P1 401 面：无 key 请求必拒（GW_API_KEY Bearer 鉴权工作）
#   P2 429 面：>MAX_CONCURRENCY 并发必限流（信号量工作）——窗口专用打点序（见 --live 输出）
#   P3 直连对照：绕网关直抵上游 health（8899 直达=基线对照，轻探零推理载荷）
#   P4 健康穿透：/health 经网关必 200（透传工作）
#   P5 上游失效面：上游停时网关 502/错误帧行为——演练窗专用（本件零执行）
# 【离线面（--offline；案头）】配置 lint：UPSTREAM 形合法/MAX_CONCURRENCY 域 [1,64]/
#   PORT 域 [1,65535]/GW_API_KEY 非空（键面非空律——空=裸奔面=红）+unit/drop-in 模板 lint
#   （要件在+密钥值零携带=SMOK_KEY 律执法）。
# 【出口】0=绿/1=红/2=无法判（--live 网关不可达=2，ANCHOR-UNKNOWN 语义）。
# 【红线】--live=执行窗面（产线在役时 P2/P5 先呈裁）；探针载荷=最小面（health/401 拒答零上游载）。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$HERE/../_lib/verdict.sh" ] && . "$HERE/../_lib/verdict.sh"

GW_URL="${GW_URL:-http://127.0.0.1:8001}"
UP_URL="${UP_URL:-http://127.0.0.1:8899}"

lint_env() {  # lint_env <env 文件> → 0/1（四键面全绿才 0）
  local f="$1" v
  [ -r "$f" ] || return 1
  v=$(grep -E '^UPSTREAM=' "$f" | head -1)
  printf '%s' "$v" | grep -qE '^UPSTREAM=http://[0-9a-zA-Z.:/-]+$' || return 1
  v=$(grep -E '^MAX_CONCURRENCY=' "$f" | head -1 | cut -d= -f2)
  [ "$v" -ge 1 ] 2>/dev/null && [ "$v" -le 64 ] 2>/dev/null || return 1
  v=$(grep -E '^PORT=' "$f" | head -1 | cut -d= -f2)
  [ "$v" -ge 1 ] 2>/dev/null && [ "$v" -le 65535 ] 2>/dev/null || return 1
  v=$(grep -E '^GW_API_KEY=' "$f" | head -1 | cut -d= -f2)
  [ -n "$v" ] && [ "$v" != '<值位空——部署窗填入，绝不入包>' ] || return 1
  return 0
}

lint_unit() {  # lint_unit <unit 文件> → 0/1（要件在+密钥值零携带）
  local f="$1"
  [ -r "$f" ] || return 1
  grep -q '^ExecStart=.*concurrency_proxy_v2.py' "$f" || return 1
  grep -q '^EnvironmentFile=' "$f" || return 1
  grep -q '^Restart=' "$f" || return 1
  grep -qE '(^Environment=.*GW_API_KEY=|^GW_API_KEY=).+' "$f" && return 1
  return 0
}

lint_dropin() {  # lint_dropin <conf> → 0/1
  local f="$1"
  [ -r "$f" ] || return 1
  grep -q '^\[Service\]' "$f" || return 1
  grep -qE '^(MemoryMax|NoNewPrivileges)=' "$f" || return 1
  return 0
}

cmd="${1:-}"; shift || true
case "$cmd" in
  --offline)
    ENVF="${1:-}"
    [ -z "$ENVF" ] && { echo "用法：$0 --offline <已填值 env 文件>（模板件=预期红，见 --selfcheck T2）" >&2; exit 2; }
    vr_begin
    lint_env "$ENVF" || vr_face "config-lint" "$ENVF 键面非空律/域违约（UPSTREAM 形/MAX_CONCURRENCY [1,64]/PORT/GW_API_KEY 非空）"
    lint_unit "$HERE/payload/units/concurrency-proxy-v2.service" || vr_face "unit-lint" "concurrency-proxy-v2.service 要件缺或密钥值入 unit"
    lint_dropin "$HERE/payload/units/10-gateway-hardening.conf" || vr_face "dropin-lint" "10-gateway-hardening.conf 面缺"
    vr_suggest "红面逐项按 payload/env 模板与 units 注记修；GW_API_KEY 值只入宿主 0600 件" "gateway#offline" manual
    vr_emit ;;
  --live)
    vr_begin; vr_suggest "探针红面处置见 GATEWAY-MIGRATION-PLAN-20261007 §〇/P0 面" "gateway#live" manual
    command -v curl >/dev/null 2>&1 || { vr_unknown "curl-missing" "无 curl"; vr_emit; }
    # P4 健康穿透（经网关）
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$GW_URL/health" 2>/dev/null)
    if [ "$code" = 200 ]; then echo "[gw-verify] P4 健康穿透绿（/health 经网关 200）"
    else vr_face "P4-health-passthrough" "code=${code:-unreachable}"; fi
    # P1 401 面（无 key；拒答零上游载）
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST "$GW_URL/v1/chat/completions" \
      -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"ping"}],"max_tokens":1,"stream":false}' 2>/dev/null)
    case "$code" in
      401|403) echo "[gw-verify] P1 401 面绿（无 key 拒 code=$code）" ;;
      000)     vr_unknown "P1-unreachable" "网关不可达（$GW_URL）" ;;
      *)       vr_face "P1-auth" "无 key 未拒 code=$code" ;;
    esac
    # P3 直连对照（上游 health 基线）
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$UP_URL/health" 2>/dev/null)
    if [ "$code" = 200 ]; then echo "[gw-verify] P3 直连对照绿（$UP_URL/health 200=基线在）"
    else vr_unknown "P3-upstream" "上游 health code=${code:-unreachable}（对照基线不可判）"; fi
    # P2 429 面=窗口专用打点序（产线在役先呈裁；本件不自动打）
    echo "[gw-verify] P2 429 面=窗口专用（序：停写流→17 并发 health 打点→期待 ≥1 发 429/限流帧→复绿确认）"
    # P5 上游失效面=演练窗专用（零执行）
    echo "[gw-verify] P5 上游失效面=演练窗专用（停 8899 观察 502/错误帧族；本面零执行）"
    vr_emit ;;
  --selfcheck)
    rc=0; T=$(mktemp -d /tmp/gw-sc.XXXXXX)
    cp "$HERE/payload/env/gateway.env.template" "$T/good.env"
    sed -i 's|^GW_API_KEY=.*|GW_API_KEY=test-key-not-a-secret|' "$T/good.env"
    # T1 已填值 env lint 绿
    bash "$0" --offline "$T/good.env" 2>/dev/null | grep -q '"verdict":0' \
      && echo "[gw-verify][OK] T1 已填值 env lint 绿（verdict=0）" || { echo "[gw-verify][RED] T1 FAIL"; rc=1; }
    # T2 模板件（占位值）必红——键面非空律判别力
    out=$(bash "$0" --offline "$HERE/payload/env/gateway.env.template" 2>/dev/null); r=$?
    [ "$r" = 1 ] && printf '%s' "$out" | grep -q 'config-lint' \
      && echo "[gw-verify][OK] T2 占位模板判红（GW_API_KEY 空值=键面非空律）" || { echo "[gw-verify][RED] T2 FAIL（rc=$r）"; rc=1; }
    # T3 坏 UPSTREAM 必红
    sed 's|^UPSTREAM=.*|UPSTREAM=not-a-url|' "$T/good.env" > "$T/bad.env"
    bash "$0" --offline "$T/bad.env" 2>/dev/null | grep -q '"verdict":1' \
      && echo "[gw-verify][OK] T3 坏 UPSTREAM 判红" || { echo "[gw-verify][RED] T3 FAIL"; rc=1; }
    # T4 unit 密钥面：Environment 带密钥值必红（SMOK_KEY 律执法）
    { cat "$HERE/payload/units/concurrency-proxy-v2.service"; echo 'Environment=GW_API_KEY=leaked'; } > "$T/leak-unit.service"
    if lint_unit "$T/leak-unit.service"; then echo "[gw-verify][RED] T4 FAIL（密钥值入 unit 未判红）"; rc=1
    else echo "[gw-verify][OK] T4 unit 密钥值携带判红（SMOK_KEY 律执法）"; fi
    # T5 drop-in 面缺必红
    printf '[Service]\nStandardOutput=journal\n' > "$T/bad-dropin.conf"
    if lint_dropin "$T/bad-dropin.conf"; then echo "[gw-verify][RED] T5 FAIL"; rc=1
    else echo "[gw-verify][OK] T5 dropin 面缺判红"; fi
    rm -rf "$T"; exit "$rc" ;;
  *) echo "用法：$0 --offline <env 文件> | --live | --selfcheck" >&2; exit 2 ;;
esac
