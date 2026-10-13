# CHANGELOG — LuZ 0.3.0 → 0.3.1

> 提炼自战役仓 git log（`luz-0.3.0-r1`（2026-10-05，32c6acd）之后 632 commits）
> 与总卡/定稿报告。逐项档锚见 `docs/` 各分档。

## 0.3.1（2026-10-13 定型，tag v0.3.1）

1. **0.3.1 开线**：0.3.0-R1 检查点封存（36 键 b7e318e0/91adc83d 七件/池 9.6M
   横幅合同）→ LUZ-031-DEV-PLAN 立线（多模型扩展+M2 闭合+QA 基建）。
2. **LL128 三键采纳**：NCCL_BUFFSIZE 1MiB + LL128_BUFFSIZE 262144 +
   PROTO ^LL128（LL128-ADOPT 窗，45 键形；LL128 中性确认带内）。
3. **O12 主机间隙调度三键产线化**：SCHED_ASYNC=1 + RECV_INTERVAL=4 + 配套件
   scheduler 5b6fe2a3（47 键形 01:34Z 绿起；HOSTGAP 86.9ms 归因定谳法源）。
4. **R1 FP4-KV in-kernel 八件转正**：kv_fp4.py feaaadd4 + fi_r1/ 六件 +
   装载缝挂点（48 键 8c8c166d；面 4b40a123 四机全等；fail-safe 双跑
   t_r1_equiv 49 GREEN；FULLGATE/REWORK2/PROMO2 三窗直证）。
5. **E3-A SWA 召回 N=256 + L2PF6**：`--swa-prefix-tails` 64→256 转正在役
   （SPEC6 六参定谱=五参基座+swa256）；L2 prefetch 6MB 单键域。
6. **W5 stage2 MXFP8+出口直聚两键单独转正**：DSV41_PREFILL_SP_FP8=1 +
   TAIL_GATHER=1（50 键定型形 15767aa6；W5 件 prefill_sp.py 32cf9abf
   2026-10-13 00:02:23Z 换入产线；MXFP8 byte AG ON 三重对拍）。
7. **T1 组合窗裁定**：chunk8192 判负不进形（16384 永禁维持）；TPsplit D1-block
   留库不转正（6498aa39 在库）；组合账 C0 步墙 648.6 对 866 基线 −25.1%。
8. **质量链收口**：CODE31 交叉审查 P0=0/P1=3（镜像件零分叉：23 件 cmp 逐字节
   等上游 main-79cafec0）；白盒矩阵 13 绿/1 注记红回填；QA31 定型窗四靴全
   电池——步墙 626.1 服务口径（866→626，−27.8%）、128k PR 5880、GSM8K 0.97、
   needle 3/3、断言门禁 10/10 逐靴直证。
9. **FL6 召回修复（呈裁在飞）**：QA31 cp30 召回 0/3 红位 → 根因定谳（SWA
   interior 未退休+match retract 缺位，swa_evictable −64.1% 机理直证）→
   fl6_recall.py b87cbb5e + 第 51 键门控验证窗=部分绿呈裁位（cp30 未复现；
   严格冻结双门 2/3）→ 产线复原 50 键原形（sitecustomize 2c4baad3）；
   ENV51 转正即用形在库（本仓 deploy/env/ 收录）。
10. **运维工具五包 T4 就绪**：fabric-net / selfdiag / selfheal / gateway /
    cfgmgmt + _lib（每包五件套+MANIFEST 指纹+selfcheck 三态退出码；
    TOOLS31-PACKAGES-RESULT 档；GIT 锚=各自整备提交）。
