# SCAN-REPORT — 密钥与敏感信息扫描报告（推送前硬门）

> 扫描时点：2026-10-13（首 commit 前，全仓 175 件 / 2.4MB）。
> 工具：`grep -rEn` 多模式（P1-P11）+ 逐命中人工复核。
> 判据：**任何红命中=该件不入仓或脱敏后入（零容忍）**。

## 扫描模式与结果总表

| # | 模式 | 命中数 | 判定 |
|---|---|---|---|
| P1 | key 字面量：`sk-[A-Za-z0-9]{16,}` / `AKIA[0-9A-Z]{16}` / `ghp_·gho_·github_pat_` / `-----BEGIN … PRIVATE KEY` / `Bearer <20+字符>` | **0** | 绿 |
| P2 | 赋值型凭据：`(api[_-]?key|passwd|password|passphrase|secret|auth[_-]?token|access[_-]?token|client[_-]?secret) [:=] <8+字符值>` | 1（见处置①） | 绿 |
| P3 | `GW_API_KEY` 全出现位值位核（政策=值位必须空） | 全空/占位（处置①②） | 绿 |
| P4 | 集群口令面：`sshpass` / `-pw` / `PasswordAuthentication` / 集群密码值 | **0**（仅「口令零接触」陈述句） | 绿 |
| P5 | `password/passwd` 显式词 | **0** | 绿 |
| P6 | `secret(s)` 词面（排除测试假值/律文陈述） | 0 余量 | 绿 |
| P7 | URL 内嵌凭据 `scheme://user:pass@` | **0** | 绿 |
| P8 | env 件/模板非注释赋值行值域复核 | 全为开关/数值/协议/占位（处置②） | 绿 |
| P9 | 高熵 base64 块（>40 连续字符） | 0（命中皆为路径/文件名串） | 绿 |
| P10 | `token` 词面（人工复核） | 全为 KV/tokenizer 域名词（SGLang 语义），无凭据赋值 | 绿 |
| P11 | 内网 IP/主机名（`dgxspark01-04`/RFC1918 段） | 26 件含 | **政策保留**（处置③） |

## 命中项处置清单（人工复核逐项）

**① `tools/packages/gateway/payload/concurrency_proxy_v2.py:162`**
`GW_API_KEY = os.environ.get("GW_API_KEY", "")` —— 运行期环境读取，缺省空串，
**非凭据值**。同件 :136 文档串 `GW_API_KEY=`（空）。处置=**保留**（代码语义件）。

**② gateway 包 selfcheck/gw-verify 测试假值三处（判别力红例 fixture）**
- `gw-verify.sh:92`：`GW_API_KEY=test-key-not-a-secret`（临时文件注入）
- `gw-verify.sh:105`：`Environment=GW_API_KEY=leaked`（泄漏检测红例）
- `selfcheck/run.sh:48`：`GW_API_KEY=real-secret-here`（占位模板判红例）

均为**显式假值测试夹具**（自检判别力=能检出真值注入的负例），不指向任何真实
凭据；T4 五包 selfcheck 设计在档（TOOLS31-PACKAGES-RESULT）。处置=**保留**
（缺件则自检红例失效）；命名自明（not-a-secret/leaked/here）。

**③ 内网 IP/主机名 26 件**——内网部署文档性质（boot 链主机表/HCA 端口映射/
回退链 md5 表等），按本仓策略**保留**；`deploy/README.md` 已注记对外发布脱敏
预案。涉及件：deploy/bin/ 链、docs/research/ 各档、gateway/cfgmgmt 包 README。

**④ env 件值域**：`deploy/env/` 两件 50/51 键全为功能开关/数值/表值
（HCA 表/对端映射表），无凭据类键；gateway.env.template `GW_API_KEY=<值位空>
`占位（政策态）。

## 集群口令专项

零出现。全部「口令」字样=纪律陈述句（「sudo 零使用口令零接触」等窗档合规行）；
`selfdiag/payload/probes/memsnap.sh:13` 提及 `~/.sudopw` 为**机制路径引用**
（stdin 喂入不落日志），非口令值。

## 结论

**硬门通过：红命中 0；全仓无任何真实凭据值。** 可推送（remote 待用户供）。
重扫触发律：任何后续 commit 前重跑 P1-P7；新增 gateway/env 类件必过 P3。
