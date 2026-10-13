# models.d · 多模型注册表（一页）— 2026-10-06

## 法源

1. **字段制**：`opt1-dev/model_compat_20261004/MULTIMODEL-GOV-CARD-20261004.md` §2.4（模型注册表
   草案；本目录=其定稿落地形，七字段 §a 指纹/§b 四机路径/§c env 模板指针/§d boot 形/§e 锚带/
   §f 开放项/§g 冷缓存注记）。
2. **闭案路径**：`docs/taskcards/CD3-LINED-CARDS-20261006.md` 卡二（现状盘点+四机拓扑证据+
   「真实缺口=注册卡文件本身未落」定谳；m4 出口判据「models.d 齐」）。

## 三卡索引

| 卡 | model_id | config 指纹（前 16） | 状态 |
|---|---|---|---|
| [v41-prod.md](v41-prod.md) | DeepSeek-V4.1-Flash（生产） | `8be45ce0476004a3` | 生产在役（r3prod/8899，R1 标准形 36 键） |
| [v4-0731.md](v4-0731.md) | deepseek-v4-flash-0731 | `6c8f3d2d3b487075` | 测试线在档；O13 后标准形=C12-600K+segment 65536 |
| [v4-vl-exp.md](v4-vl-exp.md) | DeepSeek-V4-Flash-Vision-Exp | `6cd841bdd6702f5e` | 测试线在档（VLW3B 形）；boot_mvl_600k.sh 待 O13B |

**nvfp4 留痕（不立卡）**：deepseek-v4-flash-0731-nvfp4 指纹 `3aad2e0caff41195` 已随 Q5 闭案
用户裁定弃用清理（31d0e9b，2026-10-05；四机 0 目录/0 挂载/0 aria2）——注册表收敛三卡
（CD3 卡二原文：「留痕不立卡」）。

## 更新纪律

- **形变即更新**：任一线 boot 形/env 模板/池指纹/锚带发生形变（O13/O13B/T17 等窗收卷后），
  由**主会话触发**对应卡 §c/§d/§e 行更新——本目录代理不自更（与判负卡制同律：判据预登记零事后改）。
- **数字零手誊**：入卡数字一律从源卡复制并逐数字 diff 自检（誊录行 vs 源行）；不确定/缺失如实
  标〔缺失〕〔未核〕。
- 身份门用法（GOV-CARD §2.2）：boot 指纹行 `MODEL=<model_id> CFG=<config sha256 前 16>
  PATH=<挂载路径> BYTES=<目录字节数>` 与本目录卡登记值逐字段相等方算靴成；不等=形面红。

——models.d 注册表 / 2026-10-06（CD3 卡二闭案件；案头零集群）
