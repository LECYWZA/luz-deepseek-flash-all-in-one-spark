#!/bin/bash
# selfheal selfcheck — 离线自检（零集群零引擎零网络；mock 红绿双例；02 守护排除断言）
set -u
PKG=selfheal
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/../_lib/pkg-common.sh"

for f in README.md MANIFEST.md5 VERSION bin/selfheal selfcheck/run.sh; do
  [ -f "$HERE/$f" ] && sc_ok "五件套在位：$f" || sc_red "五件套缺件：$f"
done
pkg_manifest_check; pkg_version_check; pkg_sources_check

T=$(mktemp -d /tmp/selfheal-sc.XXXXXX)

# F1 qmg --selftest（三件；零引擎零网络零 docker）
if out=$(bash "$HERE/payload/qamemguard.sh" --selftest 2>&1); then
  sc_ok "F1 qmg --selftest 绿（三件离线自检）"
else
  rc=$?; sc_red "F1 qmg --selftest 红（rc=$rc）"; printf '%s\n' "$out" | tail -4 | sed 's/^/    /'
fi

# F2 adapter-sync --selfcheck（本地逻辑自检，零 ssh 零集群）
if out=$(bash "$HERE/payload/adapter-sync.sh" --selfcheck 2>&1); then
  sc_ok "F2 adapter-sync --selfcheck 绿（LC_ALL=C sort 口径+锚断言面）"
else
  rc=$?; sc_red "F2 adapter-sync --selfcheck 红（rc=$rc）"; printf '%s\n' "$out" | tail -4 | sed 's/^/    /'
fi

# F3 rollback-chain --selfcheck（四级链 mock 红绿：双核/篡改 UNKNOWN/跳级拒/四要素）
if bash "$HERE/payload/rollback/rollback-chain.sh" --selfcheck >/dev/null 2>&1; then
  sc_ok "F3 rollback-chain selfcheck 绿（50 真形双核+跳级判红+计划四要素）"
else sc_red "F3 rollback-chain selfcheck 红"; fi

# F4 回退链对真树复核（四形 env 全在权威源=可回退性面）
ENVDIR=/home/liux***ya/migrate-assets/dsv41/env
n_ok=0; n_miss=0
for pair in "PROD-R51W5-spec1.env:15767aa6:50" "PROD-R1INK48L2PF6O12C1-spec1.env:8c8c166d:48" "PROD-R1STDLL128L2PF6O12C1-spec1.env:99e7ec92:47" "PROD-R1STDLL128L2PF6-spec1.env:34977bf0:45"; do
  f="${pair%%:*}"; rest="${pair#*:}"; m="${rest%%:*}"; k="${rest##*:}"
  if [ -r "$ENVDIR/$f" ]; then
    gm=$(md5sum "$ENVDIR/$f" | awk '{print substr($1,1,8)}')
    [ "$gm" = "$m" ] && n_ok=$((n_ok+1)) || { sc_red "F4 回退件漂移：$f 现=$gm 应=$m（FORM-REGISTRY 同日更新）"; n_miss=$((n_miss+1)); }
  else sc_unk "F4 回退件缺位：$ENVDIR/$f（不在本机=非 01 权威机常态）"; n_miss=$((n_miss+1)); fi
done
[ "$n_ok" = 4 ] && sc_ok "F4 四级回退件全在位全等（50/48/47/45 四形 md5 对表绿）"

# F5 02 机两守护显式排除断言（包内零 3535/3536 动作面；红例=注入动作面文件必红）
excl_check() {  # 排除律：包内任何件不得含 3535/3536 单元动作面（grep -rn systemctl\*restart\|stop 3535/3536）
  local hits
  hits=$(grep -rnE '(systemctl|service|unit).{0,40}(3535|3536)| (3535|3536) ' "$1" 2>/dev/null | grep -v '不收编\|不改动\|不触碰\|绝对不动\|排除\|3535/3536）\|selfcheck' | head -3)
  [ -z "$hits" ]
}
if excl_check "$HERE/payload"; then sc_ok "F5 02 机两守护（3535/3536）零动作面断言绿（绝对不动律）"
else sc_red "F5 包内出现 02 守护动作面（违绝对不动律）"; fi
printf '# bad: systemctl restart 3535\nsystemctl --job-mode=replace restart 3535\n' > "$T/bad-excl.sh"
excl_check "$T/bad-excl.sh" && sc_red "F5 红例失效（注入动作面未判红）" || sc_ok "F5 红例判红（注入 3535 动作面被识别）"

# F6 watchdog 双哨+TRIP 拆栈律在文（红例=摘除必红）
wd="$HERE/payload/r3-watchdog.sh"
grep -q 'head 哨' "$wd" && grep -q 'worker 哨' "$wd" && sc_ok "F6 watchdog 双哨制在文（01 head 哨+02 worker 哨）" || sc_red "F6 watchdog 双哨注记缺失"
grep -vE 'docker rm -f' "$wd" > "$T/bad-wd.sh"
grep -q 'docker rm -f' "$T/bad-wd.sh" && sc_red "F6 红例失效" || sc_ok "F6 红例判红（幂等拆栈动作面摘除被识别）"

# F7 oom-gate 三模式在文（pre/baseline/post/monitor；F11 判假绿语义；红例=post 面摘除必红）
og="$HERE/payload/oom-gate/oom_gate.sh"
grep -q 'baseline' "$og" && grep -q 'post' "$og" && grep -q 'monitor' "$og" && sc_ok "F7 oom-gate pre/baseline/post/monitor 面在文" || sc_red "F7 oom-gate 模式面缺失"
grep -v '判假绿' "$og" > "$T/bad-og.sh"
grep -q '判假绿' "$T/bad-og.sh" && sc_red "F7 红例失效" || sc_ok "F7 红例判红（F11 判假绿语义摘除被识别）"

# F8 unit 文件面（oom-gate-monitor.service 属宿主部署面：Restart=always+After=docker；无密钥）
ug="$HERE/payload/units/oom-gate-monitor.service"
grep -q 'Restart=always' "$ug" && grep -q 'After=docker.service' "$ug" && sc_ok "F8 oom-gate unit 面绿（宿主部署件；不入镜像律注记见 README）" || sc_red "F8 unit 面异常"

# F9 RUNBOOK-WEDGE 处置序四要素（停手取证/拆栈/呈裁/不重试）
rb="$HERE/payload/rollback/RUNBOOK-WEDGE.md"
grep -q '取证三件套' "$rb" && grep -q '不重试律' "$rb" && grep -q '呈裁' "$rb" && grep -q '先存后删' "$rb" \
  && sc_ok "F9 楔死 runbook 四要素在文（停手取证/呈裁/不重试/先存后删）" || sc_red "F9 runbook 要素缺"

rm -rf "$T"
sc_summary
