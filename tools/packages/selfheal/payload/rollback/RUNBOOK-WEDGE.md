# RUNBOOK-WEDGE — 楔死/事故处置序（INCIDENT 家族索引件；案头登记非逐字收编）

> TOOLS31-PACKAGE-PLAN §二 P3-2 承载。法源=INCIDENT 家族档（docs/incidents/ + docs/
> research/INCIDENT-DUMPWIPE-20261011.md + E3A-T384 靴档 + INCIDENT-2218 翻转事件谱系）。
> 本件=**索引+序**：每家族给「停手点/取证面/处置面/先例档」；细节以档为准。

## 一、楔死处置总序（停手取证三件套 → 拆栈三查 → 呈裁；**不重试律**）

1. **停手**：任何异常先停手（连发重试=放大损失；U1 律家族）。
2. **取证三件套**（先存后动，零证据损失）：
   - watermark/水位面（water-10s 采样档+当刻 free/meminfo）；
   - qmg 面记录（qamemguard 窗档；**qmg 拆线=按序先存后删**——INCIDENT-DUMPWIPE/
     E3A-T384 先例：按序先存后删=零证据损失；无序清空=取证断链）；
   - 引擎尾日志（docker logs 尾段×4 机先存）。
3. **拆栈**：r3-stop（幂等；D8 三查=容器净/槽释放/水位回位）；watchdog 面按
   r3-watchdog.sh TRIP 拆栈律（双哨幂等 docker rm -f，双触发无害）。
4. **呈裁**：处置选项呈主会话/用户；**不重试律**=未判明根因前禁同形重掷（红带族
   d 类多稳态例外=沉降 ≥30min 后同形重掷可愈，2c9cc93——判明后才可用）。

## 二、家族索引（档：停手点 → 处置面）

| 家族 | 先例档 | 要点 |
|---|---|---|
| OOM 双联（A0H 期） | docs/incidents/INCIDENT-20260930-1327/-1517；docs/verdicts/OOM-INCIDENT-DEEPDIVE-20261004 | UMA 超卖先兆=MemAvailable 跌穿线即拆（watchdog WATER_M）；post 增量>0=判假绿作废（oom-gate F11） |
| 楔死无联动（head 活而不响应） | INCIDENT-2026-09-30-13:26 F-2（r3-watchdog 蓝本） | 双哨制：01=head 哨+02=worker 哨（head 楔死时哨兵不同亡） |
| 取证断链（dump 误报消失） | docs/research/INCIDENT-DUMPWIPE-20261011.md（**降级定谳=零删除，判读件路径笔误**） | 先存后删序=制度位；判读件路径双核（笔误族防御） |
| qmg 拆线（测试窗看护件下线） | E3A-T384 靴档（qamemguard 拆线序） | 按序先存后删；qmg=窗驱动启停件，窗终收束律 |
| GID 出洞/链路翻转 | INCIDENT-2218（2026-10-08 22:18；BOOT-LOWSPEED-ROOTCAUSE Fam-D） | 复原序=环回重铺→verify→静默观察 ≥15min 无新翻转→slotlock bump boot→四查绿（FABRIC-SELFHEAL Phase1 语义蓝本）；工具面=fabric-net 包 gid-heal |
| MM staging 崩/NVML 调度楔 | docs/incidents/INCIDENT-20261006-C24VL-OPEN26 / -T17VL-OPEN23 | 各档处置序以档为准（本索引不复制细节） |

## 三、02 机两守护绝对不动律（本包红线）

02 机在役两守护（unit 3535/3536）**不收编、不改动、不触碰**——本包全部件的默认
动作面不含 02 机守护面；selfcheck 有专项断言（F6：包内件零 3535/3536 动作面）。
若需只读监测面=独立呈裁项（任务卡 §七.4 悬裁位）。

## 四、qamemguard 红线原文位（qmg 头注律）

qmg=测试窗看护件：**保持窗驱动启停语义不常驻**；绝不进生产 boot 链；守护常驻化=
用户裁定面（QA31 §八-3 呈裁项）。原文见 payload/qamemguard.sh 头注（判读语义零改律）。

——TOOLS31 T4 P3 / 2026-10-13 案头整备。
