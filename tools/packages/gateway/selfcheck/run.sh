#!/bin/bash
# gateway selfcheck — 离线自检（零网络零 systemd；mock 红绿双例）
set -u
PKG=gateway
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/../_lib/pkg-common.sh"

for f in README.md MANIFEST.md5 VERSION bin/gateway selfcheck/run.sh; do
  [ -f "$HERE/$f" ] && sc_ok "五件套在位：$f" || sc_red "五件套缺件：$f"
done
pkg_manifest_check; pkg_version_check; pkg_sources_check

# F1 gw-verify --selfcheck（五例：填值绿/占位红/坏 UPSTREAM 红/密钥入 unit 红/dropin 缺红）
if bash "$HERE/payload/gw-verify.sh" --selfcheck >/dev/null 2>&1; then
  sc_ok "F1 gw-verify selfcheck 绿（键面非空律+SMOK_KEY 执法五例）"
else sc_red "F1 gw-verify selfcheck 红"; fi

# F2 proxy 件语法+版本面（py_compile+rc3.8.2 谱系头注+五配置键在文）
python3 -m py_compile "$HERE/payload/concurrency_proxy_v2.py" && sc_ok "F2 proxy py_compile 绿" || sc_red "F2 proxy 语法红"
for key in UPSTREAM PORT MAX_CONCURRENCY GW_API_KEY TOTAL_STREAM_TIMEOUT; do
  grep -q "os.environ.get(\"$key\"" "$HERE/payload/concurrency_proxy_v2.py" || sc_red "F2 proxy 配置键缺面：$key"
done
grep -q 'rc3.8.2' "$HERE/payload/concurrency_proxy_v2.py" && sc_ok "F2 proxy rc3.8.2 谱系头注在文" || sc_unk "F2 proxy 谱系头注非 rc3.8.2 形（升级须注记）"

# F3 01 在役件对锚（e1a01162；漂移=在役升级未同步吸收）
for p in /opt/aicad-prod/scripts/concurrency_proxy_v2.py; do
  if [ -r "$p" ]; then
    m=$(md5sum "$p" | awk '{print substr($1,1,8)}')
    pm=$(md5sum "$HERE/payload/concurrency_proxy_v2.py" | awk '{print substr($1,1,8)}')
    if [ "$m" = "$pm" ]; then sc_ok "F3 01 在役 proxy 对锚绿（$m）"
    else sc_red "F3 在役件漂移（在役=$m 包内=$pm——同日再吸收律）"; fi
  else sc_unk "F3 在役位缺件（$p——非 01 机常态）"; fi
done

# F4 unit P0 死件闭合面（要件三键+密钥零携带；红例=要件摘除必红）
T=$(mktemp -d /tmp/gwpkg-sc.XXXXXX)
u="$HERE/payload/units/concurrency-proxy-v2.service"
grep -q '^ExecStart=' "$u" && grep -q '^EnvironmentFile=' "$u" && grep -q '^Restart=' "$u" \
  && sc_ok "F4 unit 要件三键绿（P0 死件闭合承载）" || sc_red "F4 unit 要件缺"
grep -v '^Restart=' "$u" > "$T/bad-unit.service"
grep -q '^Restart=' "$T/bad-unit.service" && sc_red "F4 红例失效" || sc_ok "F4 红例判红（Restart 摘除被识别）"

# F5 env 模板密钥面（值位空占位；红例=值入模板必红）
e="$HERE/payload/env/gateway.env.template"
if grep -q '^GW_API_KEY=<值位空' "$e" && ! grep -qE '^GW_API_KEY=[A-Za-z0-9]' "$e"; then
  sc_ok "F5 env 模板密钥值零携带绿"
else sc_red "F5 env 模板含密钥值面（SMOK_KEY 律违约）"; fi
sed 's|^GW_API_KEY=.*|GW_API_KEY=real-secret-here|' "$e" > "$T/bad-env.template"
if grep -qE '^GW_API_KEY=[A-Za-z0-9]' "$T/bad-env.template"; then sc_ok "F5 红例判别面在（注入值可检出）"; else sc_red "F5 红例失效"; fi

rm -rf "${T:-}"
sc_summary
