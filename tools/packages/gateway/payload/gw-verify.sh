#!/bin/bash
# gw-verify — 并发网关验证器（五探针+离线配置 lint；TOOLS31 §二 P4-3）
#
# 【五探针（--live；执行窗面）】
#   P1 401 面：无 key 打 /gw/* 必拒（GW_API_KEY Bearer 鉴权工作）。A5 修正：业务路径
#     不代理鉴权（proxy :105-106 契约——鉴权归上游 VLLM_API_KEY），故无 key 业务 POST
#     的 401 断言为误断言已撤（其反而会真触发一次上游推理且必然 200）；401 断言收敛 /gw/*。
#   P2 429 面：>MAX_CONCURRENCY 并发 POST 必限流（信号量工作）。A4 修正：GET/HEAD 在
#     dispatch 免并发槽（proxy :759-766，信号量之前返回）——health 打点永不 429，
#     信号量验证必须 POST 面（窗口专用打点序见 --live 输出）。
#   P3 直连对照：绕网关直抵上游 health（8899 直达=基线对照，轻探零推理载荷）
#   P4 健康穿透：/health 经网关必 200（透传工作）
#   P5 上游失效面：上游停时网关 502/错误帧行为——演练窗专用（本件零执行）
# 【离线面（--offline；案头）】配置 lint：UPSTREAM 形合法/MAX_CONCURRENCY 域 [1,64]/
#   PORT 域 [1,65535]/GW_API_KEY 非空（键面非空律——空=裸奔面=红）+B4 域检查
#   （QUEUE_TIMEOUT [1,300]/DEDUP_ENABLE {0,1}/INJECT_ENABLE_THINKING {0,1}，键在才查）
#   +unit/drop-in 模板 lint（v2+vl 双 unit——要件在+密钥值零携带=SMOK_KEY 律执法；
#   vl env 文件可作第二实参同面 lint）。
# 【出口】0=绿/1=红/2=无法判（--live 网关不可达=2，ANCHOR-UNKNOWN 语义）。
# 【红线】--live=执行窗面（产线在役时 P2/P5 先呈裁）；探针载荷=最小面（/gw/* 401 拒答
#   与 health 探测零上游推理载——P1 收敛后成立；业务路径 POST 探测=误断言已撤，零执行）。
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
  # B4 域检查（键在才查——缺键=脚本默认继承非红面；A2/A3 补键后的 typo/越域执法面）
  v=$(grep -E '^QUEUE_TIMEOUT=' "$f" | head -1 | cut -d= -f2)
  if [ -n "$v" ]; then { [ "$v" -ge 1 ] && [ "$v" -le 300 ]; } 2>/dev/null || return 1; fi
  v=$(grep -E '^DEDUP_ENABLE=' "$f" | head -1 | cut -d= -f2)
  if [ -n "$v" ]; then [ "$v" = 0 ] || [ "$v" = 1 ] || return 1; fi
  v=$(grep -E '^INJECT_ENABLE_THINKING=' "$f" | head -1 | cut -d= -f2)
  if [ -n "$v" ]; then [ "$v" = 0 ] || [ "$v" = 1 ] || return 1; fi
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
    ENVF="${1:-}"; VLENVF="${2:-}"
    [ -z "$ENVF" ] && { echo "用法：$0 --offline <已填值 env 文件> [已填值 vl env 文件]（模板件=预期红，见 --selfcheck T2/T6）" >&2; exit 2; }
    vr_begin
    lint_env "$ENVF" || vr_face "config-lint" "$ENVF 键面非空律/域违约（UPSTREAM 形/MAX_CONCURRENCY [1,64]/PORT/GW_API_KEY 非空/QUEUE_TIMEOUT [1,300]/DEDUP·INJECT {0,1}）"
    if [ -n "$VLENVF" ]; then   # B4：VL 车道 env 双件 lint 面（缺省=只 lint 主车道）
      lint_env "$VLENVF" || vr_face "vl-config-lint" "$VLENVF 键面非空律/域违约（同主车道四键+域检查）"
    fi
    lint_unit "$HERE/payload/units/concurrency-proxy-v2.service" || vr_face "unit-lint" "concurrency-proxy-v2.service 要件缺或密钥值入 unit"
    lint_unit "$HERE/payload/units/concurrency-proxy-vl.service" || vr_face "vl-unit-lint" "concurrency-proxy-vl.service 要件缺或密钥值入 unit"
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
    # P1 401 面（A5 修正：收敛到管理面 /gw/*——本地应答零上游载。业务路径不代理鉴权
    # （proxy :105-106 契约，鉴权归上游 VLLM_API_KEY）：无 key 业务 POST 反而会真触发
    # 一次上游推理且必然 200，原「必 401」断言=误断言已撤（S6 P1-auth 红在案）。
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$GW_URL/gw/health" 2>/dev/null)
    case "$code" in
      401) echo "[gw-verify] P1 401 面绿（/gw/health 无 key 拒 401=GW_API_KEY Bearer 鉴权工作）" ;;
      000) vr_unknown "P1-unreachable" "网关不可达（$GW_URL）" ;;
      200) vr_face "P1-auth" "/gw/health 无 key 得 200=GW_API_KEY 未设（管理面裸奔——键面非空律红）" ;;
      *)   vr_face "P1-auth" "/gw/health 无 key code=$code（预期 401）" ;;
    esac
    # P3 直连对照（上游 health 基线）
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$UP_URL/health" 2>/dev/null)
    if [ "$code" = 200 ]; then echo "[gw-verify] P3 直连对照绿（$UP_URL/health 200=基线在）"
    else vr_unknown "P3-upstream" "上游 health code=${code:-unreachable}（对照基线不可判）"; fi
    # P2 429 面=窗口专用打点序（A4 修正：GET/HEAD 在 dispatch 免并发槽（proxy :759-766，
    # 信号量之前返回）——health 打点永不 429，信号量验证必须 POST 面）
    echo "[gw-verify] P2 429 面=窗口专用（序：停写流→并发 POST /v1/chat/completions 打点"
    echo "[gw-verify]   〔stream 假 body max_tokens=1；8001 梯 8→16→17 / 8002 梯 4→8→9〕"
    echo "[gw-verify]   →期待 N+1 发 429+Retry-After→/gw/metrics queue_wait/active_streams 收尾=0→复绿）"
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
    # T6 VL 车道双件 lint 面（B4 补面）：vl unit 要件绿 + vl env 模板占位判红
    if lint_unit "$HERE/payload/units/concurrency-proxy-vl.service"; then
      echo "[gw-verify][OK] T6 vl unit lint 绿（要件在+密钥零携带）"
    else echo "[gw-verify][RED] T6 FAIL（vl unit 要件缺）"; rc=1; fi
    if lint_env "$HERE/payload/env/gateway-vl.env.template"; then
      echo "[gw-verify][RED] T6 FAIL（vl 模板占位未判红）"; rc=1
    else echo "[gw-verify][OK] T6 vl env 占位模板判红（GW_API_KEY 空值=键面非空律）"; fi
    # T7 域检查判别力（B4）：QUEUE_TIMEOUT 越域必红
    sed 's|^QUEUE_TIMEOUT=.*|QUEUE_TIMEOUT=9999|' "$T/good.env" > "$T/badq.env"
    if lint_env "$T/badq.env"; then echo "[gw-verify][RED] T7 FAIL（QUEUE_TIMEOUT 越域未判红）"; rc=1
    else echo "[gw-verify][OK] T7 QUEUE_TIMEOUT 越域判红（域 [1,300]）"; fi
    rm -rf "$T"; exit "$rc" ;;
  *) echo "用法：$0 --offline <env 文件> [vl env 文件] | --live | --selfcheck" >&2; exit 2 ;;
esac
