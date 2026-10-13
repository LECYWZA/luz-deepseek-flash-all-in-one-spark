# selfheal（P3 修复自愈工具包）

> TOOLS31-PACKAGE-PLAN-20261012 §二 P3 承载。整备位=`tools/packages/selfheal/`；烘焙位=
> `/opt/dsv41/packages/selfheal/`（**units/ 与守护件=宿主部署面，不入镜像**——00-BAKED 律）。

## 为什么存在

0.3.1 的「出事怎么办」知识散在 ~/migrate-assets/dsv41/kit/oom-gate、~/migrate-assets/bin/
r3-watchdog.sh、INCIDENT 家族档三处。本包收编 oom-gate/watchdog/楔死 runbook/回退链
四处为一个可自检的工具面，并把 FORM-REGISTRY-031 的四级回退链（50→48→47→45）脚本化。

## 用法

`bin/selfheal help`；`bin/selfheal selfcheck`；`bin/selfheal rollback --plan 50 48`
（相邻级强制+每级四查）；`bin/selfheal rollback --check <env>`（md5+键数双核）；
`bin/selfheal run <件名>`（转发在役件，判读语义零改）。

## 构成（详=MANIFEST.md5；在役源对表=selfcheck/sources.tsv）

| 件 | 来源/在役位 |
|---|---|
| oom-gate/（oom_gate.sh+selftest_snapshot.sh+README） | ~/migrate-assets/dsv41/kit/oom-gate/（0.2.8 谱系蓝本） |
| units/oom-gate-monitor.service | 同上（宿主 systemd unit=部署面分发件） |
| r3-watchdog.sh（双哨制：01 head 哨+02 worker 哨；TRIP 拆栈律） | ~/migrate-assets/bin/ |
| rollback/rollback-chain.sh（**四级链**：50→48→47→45；相邻级强制+每级四查+沉降 ≥30min+slotlock 治理+adapter-sync --expect；--apply=执行窗面） | TOOLS31 §二 P3-3 新件（FORM-REGISTRY-031 §一 权威承接） |
| rollback/RUNBOOK-WEDGE.md（INCIDENT 家族索引：停手取证三件套→r3-stop 拆栈→呈裁；**不重试律**；DUMPWIPE/E3A-T384 qmg 先存后删先例；INCIDENT-2218 翻转复原序） | docs/incidents/+docs/research 家族索引（案头登记非逐字收编） |
| adapter-sync.sh（--check/--apply/--prune 先存后删/--expect 锚断言/--selfcheck） | tools/（ENV-GOVERNANCE 20261010 落实件） |
| qamemguard.sh（qmg 测试窗看护件） | tools/（**窗驱动启停语义保持不常驻**） |

## 排除了什么

- **02 机在役两守护（unit 3535/3536）不收编、不改动、不触碰**（绝对不动律；selfcheck
  F5 断言包内零其动作面；只读监测面=任务卡 §七.4 悬裁位）。
- **watchdog/oom-gate monitor 常驻面=宿主部署面不随镜像**（容器内无 /proc//sys/cgroup
  判据；00-BAKED「载荷非守卫」律）。
- **自动拉起/自动重启类动作零携带**（U1 教训律：未验证绿环境自动动作放大问题——
  FABRIC-SELFHEAL §〇.6；已 disable 的 start.sh 自动拉起先例在档）。
- **密钥零携带**（~/.sudopw 类路径只出现在取证件文档说明里，值不进包）。

## 红线注记

1. **qmg 头注律原文位**：qmg=测试窗看护件，窗驱动启停不常驻；绝不进生产 boot 链；
   常驻化=用户裁定面（QA31 §八-3 呈裁项）。
2. **回退链相邻级强制**：每级四查全绿才降下一级；跳级=红（rollback-chain T3 判别力）。
3. **取证先存后删序**（INCIDENT-DUMPWIPE/E3A-T384）：任何清理动作前 dump/日志先存。
4. **--apply/boot=执行窗面**（OUTAGE 制）：本包案头件零 boot 零流量；boot 恒经
   tools/boot-with-slotlock.sh（P0 治理 wrapper）。

——TOOLS31 T4 P3 / 2026-10-13 案头整备。
