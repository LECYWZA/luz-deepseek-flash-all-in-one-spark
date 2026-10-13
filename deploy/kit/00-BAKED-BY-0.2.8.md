# 本目录 = 宿主 ~/w6-kit/ 在 luz0.2.8 冻结点的**原样快照**

- 冻结点：2026-09-23，`/home/liux***ya/dsv41-flash-dgxsparks @ b87d5d9`，镜像 `dsv41-sglang-optimized:0.2.8`
- 清单：`MANIFEST.md5`（46 项，在**本目录内**校验：`cd /opt/dsv41/kit && md5sum -c MANIFEST.md5`）
- 载荷指纹：`kit_manifest_md5=382ad018a099946d2fd8a87dbd77d977`
  （= 镜像 LABEL `org.dsv41.kit_manifest_md5`；归档副本比对这个值即可判断是否同代）

## 本镜像装了什么 / 没装什么

**装进的载荷**分三类（构建脚本 `image-patches/0.2.8/build-0.2.8.sh` 的载荷表是唯一事实源）：
运行期源码 8 项（overlay 谱系 + v14 autotune）、仓库↔镜像同步 3 项、工具载荷 46 项（本目录）。

**明确排除**（"排除了什么"和"装了什么"一样重要 —— QA-A F7）：
- **`instruments/daily_smoke.py`** —— 第 19 行含**硬编码探测密钥**（`SMOKE_KEY` 兜底值）——密钥绝不进镜像；该件是宿主侧日级 smoke，容器内无判据
- **`sglang-overlay/configurer.py`** —— A/B 臂（回退 #39482）。回退条件「本臂恢复 ~5000 t/s」**未成立**——2026-09-22 定谳 prefill 回归真凶是 02 时钟楔死（PD 安全模式），与 #39482 无关 ⇒ 保留 0.2.7 的 (120,121) 原版
- **`*.bak-* / 日志 / state/ / __pycache__`** —— 历史与运行态，不进镜像

## 可复现性

- **运行期载荷源全部受 git 管辖且构建时工作树干净**（构建脚本 2.5/6 步的硬断言）。
  所以 `git checkout b87d5d9` 能拿到与本镜像逐字节相同的载荷 ⇒ 自述里的 provenance
  是可复现的、不是事后追认。（首版没有这条断言，`state/prv3_collector.py` 曾被
  `.gitignore` 挡住 —— 那次是"镜像→git"的事后补登，QA-A 判为 F1/F3。）
- **工具载荷（本目录）不在 git 内**：`~/w6-kit/` 不是仓库。它的可复现性由
  `MANIFEST.md5` + 上面的`载荷指纹`保证；归档副本（`w6-archive-repo`）必须与它同值。
- 冷构建可复现：`NOCACHE=1 TAG=<临时标签> bash <本脚本>` 连跑两次，内容身份必须相等。

## 它是载荷，不是运行时守卫

这里的守卫/量具判据全部来自**宿主**接口——`/proc/meminfo`、`/sys/fs/cgroup`、
`dmesg`/`journalctl`、`systemd`、`docker` CLI、`ssh` 扇出、`nvidia-smi`、libcuda。
在容器内**跑不出结论**，因此镜像内**不接线、不自启**。它们的在役运行方式是宿主侧
（systemd 用户单元 + 手工窗口驱动），文档见 `README.md` 与 `guard/README.md`。

反过来说，**文件里出现的 `~/w6-kit/...` 路径指宿主机的部署布局**，不是本镜像内的路径。

## 随镜像同行的理由

1. **镜像自描述**：拿到一个镜像就能读到它的守卫口径、量具口径、判据出处与已知缺口。
2. **交付完整**：镜像与治理包一起交付时，守卫套件不会因为"忘了拷"而缺席。
3. **可审计**：文档与守卫同源同版本，避免"手册说 A、守卫做 B"。
