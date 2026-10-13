# gateway（P4 网关工具包）

> TOOLS31-PACKAGE-PLAN-20261012 §二 P4 承载。整备位=`tools/packages/gateway/`；烘焙位=
> `/opt/dsv41/packages/gateway/`（**units/=宿主部署面分发件，不入镜像**——00-BAKED 律）。

## 为什么存在

01 机 concurrency-proxy-v2（:8001→8899，MAX_CONCURRENCY=16）是产线流式网关，但
GATEWAY-MIGRATION-PLAN §1.4 点名 **P0 死件：单元文件缺失，进程裸奔重启即失守**。
本包闭合该死件（unit+drop-in 入包+分发注记），收编 01 现役 proxy 本尊副本，并提供
五探针验证器 gw-verify。

## 用法

`bin/gateway help`；`bin/gateway selfcheck`；`bin/gateway verify --offline <已填值 env>`
（配置 lint）；`bin/gateway verify --live`（五探针——执行窗面）；`bin/gateway proxy`
（在役位+md5 锚打印）。

## 构成（详=MANIFEST.md5；在役源对表=selfcheck/sources.tsv）

| 件 | 来源/在役位 |
|---|---|
| concurrency_proxy_v2.py（v2.0-rc3.8.2；信号量限流/GW_API_KEY Bearer[hmac.compare_digest]/错误帧骨架/chunk-idle 可观测/图像占位净化） | 01 /opt/aicad-prod/scripts/（e1a01162 三拷贝同 md5 亲核：在役=~/gateway-migration-staging/proxy/） |
| units/concurrency-proxy-v2.service（**P0 死件闭合**；EnvironmentFile 承载键面） | 本包新件（部署面分发：01 原位+迁移窗网关机） |
| units/10-gateway-hardening.conf（drop-in：journal/MemoryMax 2G/非特权/ProtectSystem） | 本包新件（落位 /etc/systemd/system/concurrency-proxy-v2.service.d/） |
| env/gateway.env.template（UPSTREAM/PORT/MAX_CONCURRENCY=16/GW_API_KEY 值位空） | 本包新件（宿主 0600 落位 /opt/aicad-prod/secrets/gateway.env） |
| units/concurrency-proxy-vl.service（**VL 车道第二实例**；同 v2 模板仅 Description/EnvironmentFile 两处差=车道制零代码改动） | VL-NATIVE S6 新件（落位 /etc/systemd/system/；01 :8002→UPSTREAM 8898〔认证期〕/8899〔转正后〕） |
| env/gateway-vl.env.template（UPSTREAM 8898/PORT=8002/MAX_CONCURRENCY=8/DEDUP_ENABLE=0 图像大 body 前缀哈希伪碰撞规避/GW_API_KEY 值位空） | VL-NATIVE S6 新件（宿主 0600 落位 /opt/aicad-prod/secrets/gateway-vl.env） |
| gw-verify.sh（五探针+离线 lint） | TOOLS31 §二 P4-3 新件 |

## 部署面分发注记（P0 闭合的执行面）

1. unit→`/etc/systemd/system/concurrency-proxy-v2.service`；drop-in→`…service.d/10-gateway-hardening.conf`。
2. env 填值→`/opt/aicad-prod/secrets/gateway.env`（0600；GW_API_KEY 值**只**在此）。
3. `systemctl daemon-reload && systemctl enable --now concurrency-proxy-v2`（执行窗动作）。
4. 四机/网关机分发位随 Mac mini M6 迁移窗重排（本包只收编 01 面——任务卡 §七.3 悬裁位）。
5. VL 车道：vl unit 同位落位+`gateway-vl.env` 填值 0600→`daemon-reload`+`enable --now concurrency-proxy-vl`（8002 车道=客户端按端口分流；启用窗=VL 形转正呈裁后，详=docs/research/VL-NATIVE-RESULT-20261013.md §八）。

## 排除了什么

- **GW_API_KEY 值绝不入包/入 unit/入镜像/入日志**（SMOK_KEY 前科律；selfcheck T4/F5
  执法红例在）。
- **在役进程零触碰**：本包零 systemctl/restart 动作（bin/gateway run 恒拒——产线在役
  件不 exec 转发）。
- **Mac mini M6 迁移栈不收编**（sparkDash/nginx/grafana/prometheus 五容器面=迁移窗承接）。
- **P2 429/P5 上游失效探针不自动执行**（产线在役时先呈裁——验证器内注记）。

## 红线注记

1. --live 探针=执行窗面；探针载荷最小面（health/401 拒答零上游推理载）。
2. unit/drop-in 落机后首验=四探针（P1/P3/P4+journal 尾段）；P2/P5=演练窗。
3. proxy 件 md5 漂移（在役升级）→同日再吸收+TOOL-ANCHORS 行更新（selfcheck F3 执法）。

——TOOLS31 T4 P4 / 2026-10-13 案头整备。
