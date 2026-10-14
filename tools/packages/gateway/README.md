# gateway（P4 网关工具包）

> TOOLS31-PACKAGE-PLAN-20261012 §二 P4 承载。整备位=`tools/packages/gateway/`；烘焙位=
> `/opt/dsv41/packages/gateway/`（**units/=宿主部署面分发件，不入镜像**——00-BAKED 律）。

## 为什么存在

01 机 concurrency-proxy-v2（:8001→8899，MAX_CONCURRENCY=16）是产线流式网关，但
GATEWAY-MIGRATION-PLAN §1.4 点名 **P0 死件：单元文件缺失，进程裸奔重启即失守**。
本包闭合该死件（unit+drop-in 入包+分发注记），收编网关本尊载荷副本，并提供
验证器 gw-verify（管理面/业务面/模型门三族探针）。

## 用法

`bin/gateway help`；`bin/gateway selfcheck`；`bin/gateway verify --offline <已填值 env>`
（配置 lint）；`bin/gateway verify --live`（探针族——执行窗面）；`bin/gateway proxy`
（在役位+md5 锚打印）；`python3 payload/tests/test_rc385.py`（**rc3.8.5 桌面测试台**，
零流量自跑，全绿才准部署）。

## 构成（详=MANIFEST.md5；在役源对表=selfcheck/sources.tsv）

| 件 | 来源/在役位 |
|---|---|
| concurrency_proxy_v2.py（v2.0-**rc3.8.5**=AUTH-DEPLOY-20261014 鉴权窗形：**GW_REQUIRE_AUTH 全局鉴权门**〔缺省 0=休眠；=1 时 /health 外一切路径一切方法收 Bearer GW_API_KEY，/metrics 含内——prometheus 配 bearer_token；流式/非流式/GET 名录面同门〕+**GW_ALLOWED_MODELS 模型名白名单**〔缺省 deepseek-v4.1-flash；假名 404 OpenAI 形 model_not_found；b'"model"' 字节预检；auth_rejected/models_rejected 计数〕+rc3.8.4 全谱〔V2b 413 透传/A6 relay_get 留痕/B1 全量哈希/信号量限流/错误帧骨架/chunk-idle 可观测/图像占位净化〕） | 源=Mac mac-stack proxy-docker（**在役本尊**；三体同 md5 `3e714a0b…`=Mac 容器/本包/01 /opt 副本） |
| payload/tests/test_rc385.py（**桌面测试台**，零流量：a 无钥 401 五面/b 假模型 404 零上游载/c 带钥放行 stub 验转发头/d **休眠门=rc3.8.4 逐字节等价十元电池**/e 流式三态+新计数键执法；本窗实跑 13/13 全绿） | 本包新件（AUTH-DEPLOY-20261014） |
| units/concurrency-proxy-v2.service（**P0 死件闭合**；EnvironmentFile 承载键面+A7 部署序注记） | 本包新件（部署面分发件） |
| units/concurrency-proxy-vl.service + env/gateway-vl.env.template（VL 车道 8002——**2026-10-14 AUTH-DEPLOY 起 Mac:8002 已撤除**〔零消费者实证〕；unit/模板留档=01 RETIRED 回退面） | VL-NATIVE-WINCARD-20261013 §4.3 承载 |
| units/10-gateway-hardening.conf（drop-in：journal/MemoryMax 2G/非特权/ProtectSystem；B6 双实例通用件） | 本包新件 |
| env/gateway.env.template（UPSTREAM/PORT/MAX_CONCURRENCY=16/QUEUE_TIMEOUT=5/CHUNK_IDLE_TIMEOUT=600/INJECT_ENABLE_THINKING=1/GW_API_KEY 值位空） | 本包新件（宿主 0600 落位） |
| gw-verify.sh（探针族+离线 lint；P1 401 双面〔/gw/* 管理+**P1b 业务面**——rc3.8.5 全局门后无钥业务 POST 本地应答 401 零上游载〕+**P6 模型门**〔GW_KEY 在时带钥假模型 404〕+P2 POST 打点序+vl 双件 lint 与域检查） | TOOLS31 §二 P4-3 新件 |

## 部署面分发注记（01 systemd 形历史面；Mac 容器形见下节）

1. **先建 env 再落 unit**（序倒=启动失败）：env 填值→`/opt/aicad-prod/secrets/gateway.env`
   （0600；GW_API_KEY 值**只**在此）。unit 的 EnvironmentFile **故意不带 `-` 容缺前缀**
   =env 缺即启动快败（GW-AUDIT D4）。
2. env 落位后先验：`bin/gateway verify --offline <已填值 env>` 全绿再继续。
3. unit/drop-in 落位→daemon-reload→enable（执行窗动作）。01 双实例 2026-10-14 起
   RETIRED（网关本尊迁 Mac，unit 留盘=回退线）。

## Mac M6 部署节（在役本尊；AUTH-DEPLOY-20261014 鉴权收紧后形态）

**网关本尊=Mac mini M6（192.168.5.71 管理 /192.168.0.1 专线）OrbStack 容器**；
01 systemd 双实例 RETIRED。详档=战役仓 luz030-opt-campaign
docs/ops/GW-MAC-MIGRATION-PLAN/RESULT-20261014.md 与 docs/ops/AUTH-DEPLOY-RESULT-20261014.md。

1. **形态**：`mac-stack/docker-compose.yml`：`concurrency-proxy`（:8001 内部键控车道，
   容器名 concurrency-proxy-v2-mac，rc3.8.5）+`responses-gateway`（:8003 **鉴权公共
   入口**，容器名 responses-gateway-mac：python:3.12-slim+固化 requirements+main.py
   v2.2.1〔hmac 恒时比较〕，env 0600 rg.env）；**concurrency-proxy-vl（:8002）已撤除**
   （零消费者；compose .bak 留服务定义=回退线）。`restart: always`；脚本烧镜像，
   升级必 compose build。
2. **配置**：proxy.env 十六键=原十四键+**GW_REQUIRE_AUTH=1**+**GW_ALLOWED_MODELS=
   deepseek-v4.1-flash**；rg.env（8003）=API_KEY 客户端钥同值平移（28ch，客户端只换
   URL 不换钥）/UPSTREAM_API_KEY=8001 GW 钥（47ch）/VLLM_URL=compose 网内名
   http://concurrency-proxy:8001/SERVED_MODEL=引擎真名+别名面；均宿主 **0600**。
3. **UPSTREAM 隧道形**：`http://192.168.0.1:24001`＝01 侧 ssh -R 反向隧道→01:8899
   （隧道断=网关 502，Restart=always 自愈，断窗≈1min）。
4. **升级序**：scp 新载荷→`md5 -q` 对锚（**rc3.8.5=3e714a0b…**）→改 env（如需）→
   `docker compose build concurrency-proxy && docker compose up -d --force-recreate
   concurrency-proxy`→探针族（gw-verify 头注 Mac 变体口径；rc3.8.5 后 P1b/P6 可用）。
5. **鉴权键面表**：8003 公共入口=API_KEY（sk-dgxspark-*，Bearer+hmac）；8001 内部车道
   =GW_API_KEY（/v1/* 与 /metrics 一切方法收 Bearer，/health 豁免=探针面）；
   8001 /gw/* 管理面=同钥原门；模型门=8001 POST 白名单外 404（别名归一=8003 层职责）；
   ~~8002~~ 已撤除。
6. **观察面消费（全带钥）**：Mac prometheus vllm-paths job bearer_token；01 guardctl
   /health 豁免零改；01 daily-smoke unit SMOKE_KEY；02 responses-gateway 过渡期保留
   （UPSTREAM_API_KEY=GW 钥+SERVED_MODEL=引擎真名；待客户端切 Mac:8003 后退役）。

## 排除了什么

- **GW_API_KEY/API_KEY 值绝不入包/入 unit/入镜像/入日志**（SMOK_KEY 前科律；selfcheck
  T4/F5 执法红例在）。
- **在役进程零触碰**：本包零 systemctl/restart 动作（bin/gateway run 恒拒）。
- **Mac mini M6 监控栈不收编**（sparkDash/nginx/grafana/prometheus=迁移窗承接；
  **网关本尊与 8003 鉴权入口除外**——2026-10-14 起以容器形在 Mac 在役，见 Mac 节）。
- **P2 429/P5 上游失效探针不自动执行**（产线在役时先呈裁——验证器内注记）。

## 红线注记

1. --live 探针=执行窗面；探针载荷最小面（P1=/gw/health 本地应答 401 拒答零上游推理载；
   **rc3.8.5 起 P1b 业务面无钥 POST 同为本地应答 401 零上游载**——全局门在统一分流层、
   body/上游之前；带钥真模型一发=定谳面不自动跑）。
2. unit/drop-in 落机后首验=四探针（P1/P3/P4+journal 尾段）；P2/P5=演练窗。
3. proxy 件 md5 漂移（在役升级）→同日再吸收+锚表更新（selfcheck F3 执法）；
   AUTH-DEPLOY-20261014 后包=在役同体（3e714a0b 三处同 md5）。
4. RETRY_CONNECT=1 语义注记（B5）：上游建连失败**或**响应 5xx 时整 body 重发一次——
   POST 面若引擎已耗 prefill 后 5xx，重试=重复推理计费面；429 无自动重试。

——TOOLS31 T4 P4 / 2026-10-13 案头整备；2026-10-14 GW-INFRAS-AUDIT 修复窗+GW-MAC-MIGRATION
迁 Mac+AUTH-DEPLOY-20261014 鉴权窗（rc3.8.5 全局门+模型门+桌面测试台+Mac 8003 上线/
8002 撤除+键面表）逐窗更新。
