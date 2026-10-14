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
| concurrency_proxy_v2.py（v2.0-**rc3.8.4**=G2-RESTORE-20261014 S5 验证窗 V2b 413 透传修复〔沿袭 rc3.8.3=A6 relay_get 502 补留痕+body_key 全量哈希治本〕；信号量限流/GW_API_KEY Bearer[hmac.compare_digest]/错误帧骨架/chunk-idle 可观测/图像占位净化） | 源=01 /opt/aicad-prod/scripts/（**在役已吸收 rc3.8.4 f0a47b17**——V1-V5 生产验证全绿〔并发阶梯 429+Retry-After/大 body 四档 200/61.4MiB RSS 峰/断路 <10s〕；guards.conf 网关锚已随吸收同日重钉 89dfecba） |
| units/concurrency-proxy-v2.service（**P0 死件闭合**；EnvironmentFile 承载键面+A7 部署序注记） | 本包新件（部署面分发：01 原位+迁移窗网关机） |
| units/concurrency-proxy-vl.service + env/gateway-vl.env.template（VL 车道 8002；UPSTREAM=**8899 转正态**〔A9，认证期 8898 已拆线〕+INJECT=0 显式〔A2〕） | VL-NATIVE-WINCARD-20261013 §4.3 承载 |
| units/10-gateway-hardening.conf（drop-in：journal/MemoryMax 2G/非特权/ProtectSystem；B6 双实例通用件——v2/vl 各自 .d 目录同件落位） | 本包新件（落位 /etc/systemd/system/concurrency-proxy-{v2,vl}.service.d/） |
| env/gateway.env.template（UPSTREAM/PORT/MAX_CONCURRENCY=16/**QUEUE_TIMEOUT=5〔A3〕/CHUNK_IDLE_TIMEOUT=600〔A1〕/INJECT_ENABLE_THINKING=1〔A2〕**/GW_API_KEY 值位空） | 本包新件（宿主 0600 落位 /opt/aicad-prod/secrets/gateway.env） |
| gw-verify.sh（五探针+离线 lint；P1 401 收敛 /gw/*〔A5〕+P2 POST 打点序〔A4〕+vl 双件 lint 与域检查〔B4〕） | TOOLS31 §二 P4-3 新件 |

## 部署面分发注记（P0 闭合的执行面；GW-AUDIT A7 部署序修正）

1. **先建 env 再落 unit**（序倒=启动失败）：env 填值→`/opt/aicad-prod/secrets/gateway.env`
   （0600；GW_API_KEY 值**只**在此；VL 车道同序先建 `gateway-vl.env`）。unit 的
   EnvironmentFile **故意不带 `-` 容缺前缀**=env 缺即启动快败——快败优于裸默认值
   静默误指 8002 旧上游的错配形（GW-AUDIT D4）。
2. env 落位后先验：`bin/gateway verify --offline <已填值 env> [已填值 vl env]` 全绿再继续。
3. unit→`/etc/systemd/system/concurrency-proxy-v2.service`（vl 同形）；drop-in→
   `…concurrency-proxy-v2.service.d/10-gateway-hardening.conf`（vl=…vl.service.d/ 同件）。
4. `systemctl daemon-reload && systemctl enable --now concurrency-proxy-v2`（执行窗动作）。
5. 四机/网关机分发位随 Mac mini M6 迁移窗重排（本包只收编 01 面——任务卡 §七.3 悬裁位）。

## 排除了什么

- **GW_API_KEY 值绝不入包/入 unit/入镜像/入日志**（SMOK_KEY 前科律；selfcheck T4/F5
  执法红例在）。
- **在役进程零触碰**：本包零 systemctl/restart 动作（bin/gateway run 恒拒——产线在役
  件不 exec 转发）。rc3.8.4 包内=在役同形（G2 收官窗已吸收；镜像 0.3.1-r3 烘焙时点=rc3.8.3，下一烘焙窗吸收差面）。
- **Mac mini M6 迁移栈不收编**（sparkDash/nginx/grafana/prometheus 五容器面=迁移窗承接）。
- **P2 429/P5 上游失效探针不自动执行**（产线在役时先呈裁——验证器内注记）。

## 红线注记

1. --live 探针=执行窗面；探针载荷最小面（P1=/gw/health 本地应答 401 拒答零上游推理载
   ——A5 收敛后成立；业务路径不代理鉴权〔proxy :105-106，鉴权归上游 VLLM_API_KEY〕，
   无 key 业务 POST 探针已撤=其会真触发推理且必然 200）。
2. unit/drop-in 落机后首验=四探针（P1/P3/P4+journal 尾段）；P2/P5=演练窗（P2 须并发
   POST 面——GET/HEAD 在 dispatch 免并发槽，health 打点永不 429，A4）。
3. proxy 件 md5 漂移（在役升级）→同日再吸收+TOOL-ANCHORS 行更新（selfcheck F3 执法）；
   反向（包领先在役）=F3 预期绿注记态——本件现=在役同形态（rc3.8.4 双侧一致）。
4. RETRY_CONNECT=1 语义注记（B5）：上游建连失败**或响应 5xx** 时整 body 重发一次——
   POST 面若引擎已耗 prefill 后 5xx，重试=重复推理计费面（图像 prefill 重则代价放大）；
   429 无自动重试（Retry-After 语义归客户端）。VL 车道可选 RETRY_CONNECT=0
   （行为变化=验证窗 V2 承载裁定，模板暂保持与在役同面不设键）。

——TOOLS31 T4 P4 / 2026-10-13 案头整备；2026-10-14 GW-INFRAS-AUDIT 修复窗
（A1-A7/A9 案头+B1/B4/B5/B6/B7 顺带）同日更新。
