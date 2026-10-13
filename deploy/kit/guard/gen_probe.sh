#!/bin/bash
# gen_probe.sh — 审计 P1-2 补偿探针（2026-09-22）
#
# 为什么存在：SGLANG_ENABLE_HEALTH_ENDPOINT_GENERATION=0（healthcheck lite，
# 修 9/21 30s 真补全磨死四机事故）后，「引擎进程在位但真生成能力已坏」再无
# 低频哨兵——gate 6h 一班是唯一生成类检查，盲窗内坏生成=0 感知。本探针
# 30min 一发、单次极小补全（19+23），只抓「/v1/models 200 但生成坏」：
#   * 栈停泊（/v1/models 不通）→ 静默退出 0（栈在位性归 guardctl check 管，
#     本探针不与它抢域、不在停泊期刷警报）
#   * 引擎在位但生成失败/答非所问/超时 → CRIT 出声（guard-alerts.log 与
#     guardctl alert() 同格式同一采集面 + syslog + 可选 GUARD_ALERT_HOOK）
# 单请求成本：~10 token 补全，30min 一发，对可用内存压力可忽略（红线教训
# 的反面：高频真补全才是 9/21 的磨机手，本探针刻意 30min+单发）。
set -u
PORT="${PORT:-8899}"
BASE="http://127.0.0.1:${PORT}"
LOGF="$HOME/w6-kit/guard/gen-probe-$(hostname).log"

shout() {  # 同 guardctl alert()/oom_gate shout() 格式，同一采集面
  local sev="${1:-CRIT}"; shift
  printf '%s [%s] %s gen-probe %s\n' "$(date -Is)" "$sev" "$(hostname)" "$*" \
    >> "$HOME/w6-kit/guard/guard-alerts.log" 2>/dev/null || true
  command -v logger >/dev/null 2>&1 && logger -t gen-probe -p daemon.err "$*" 2>/dev/null || true
  if [ -n "${GUARD_ALERT_HOOK:-}" ]; then
    curl -sS --max-time 10 -H 'Content-Type: application/json' \
      -d "{\"severity\":\"$sev\",\"host\":\"$(hostname)\",\"src\":\"gen-probe\",\"text\":\"$*\",\"ts\":\"$(date -Is)\"}" \
      "$GUARD_ALERT_HOOK" >/dev/null 2>&1 || true
  fi
}

# 0) 密钥（与 gate 同源；引擎开着 API key，无 auth 的探活会被 401 误判停泊）
KEY=""
for ln in "$HOME"/dsv41-flash-dgxsparks/.env.tp4 "$HOME"/dsv41-flash-dgxsparks/.env; do
  [ -f "$ln" ] && key=$(sed -n 's/^API_KEY="*\(.*\)"*$/\1/p' "$ln" | head -1) && [ -n "$key" ] && KEY="$key" && break
done
AUTH=(); [ -n "$KEY" ] && AUTH=(-H "Authorization: Bearer $KEY")

# 0.5) 栈在位性：带 auth 探 /v1/models 不通=停泊/宕，静默让位（guardctl check 的域）
if ! curl -fsS --max-time 5 "$BASE/v1/models" "${AUTH[@]}" >/dev/null 2>&1; then
  echo "$(date -Is) stack-not-serving (quiet exit)" >> "$LOGF"
  exit 0
fi

# 1) 自适应模型名（栈切变体不改探针）
MODEL=$(curl -fsS --max-time 5 "$BASE/v1/models" "${AUTH[@]}" 2>/dev/null \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null)
[ -z "$MODEL" ] && { shout CRIT "/v1/models 200 但模型名解析失败（生成面异常的前兆）"; exit 1; }

# 2) 单发极小真生成（thinking off）
RESP=$(curl -fsS --max-time 120 "$BASE/v1/chat/completions" "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"temperature\":0,\"max_tokens\":16,\"chat_template_kwargs\":{\"thinking\":false},\"messages\":[{\"role\":\"user\",\"content\":\"What is 19 + 23? Reply only with the number.\"}]}" 2>&1)
RC=$?
if [ "$RC" -ne 0 ]; then
  shout CRIT "真生成探针失败 rc=$RC（引擎在位但生成面坏）：$(printf '%s' "$RESP" | tr '\n' ' ' | cut -c1-160)"
  echo "$(date -Is) FAIL rc=$RC" >> "$LOGF"
  exit 1
fi
ANS=$(printf '%s' "$RESP" | python3 -c 'import json,sys;print(json.load(sys.stdin)["choices"][0]["message"]["content"])' 2>/dev/null)
if printf '%s' "$ANS" | grep -q '42'; then
  echo "$(date -Is) OK (${MODEL})" >> "$LOGF"
  exit 0
else
  shout CRIT "真生成探针答非所问（模型=$MODEL）：$(printf '%s' "$ANS" | tr '\n' ' ' | cut -c1-120)"
  echo "$(date -Is) FAIL wrong-answer: $ANS" >> "$LOGF"
  exit 1
fi
