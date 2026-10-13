#!/usr/bin/env bash
# gate0_sitecustomize_anchor.sh — 门0d 通用节（F8, PROD-RS-WHITEBOX-QA-20261003）
#
# 用途：t62 族链（及任何以 ~/migrate-assets/dsv41/adapter 为部署源的火链）在
# 门0c（prefill_sp.py md5 三查）之后 source 本件并调用
#     gate0_sitecustomize_anchor [adapter_dir]
# 即得「切产双件」的第二件锚：sitecustomize.py 的 md5 锚 + 挂载面内容查。
#
# 机理（F8 登记册原文）：误推工作树版 sitecustomize（或某次 adapter 重组丢
# 挂载行）⇒ 键照设、prefill_sp 零执行、boot 全绿——只能靠链后置横幅断言在
# 点火后才发现，门0 阶段零拦截；本节把「键在≠件在」变体拦在点火前。
#
# 三查（任一红即 ABORT）：
#   0d-1  md5 锚：sitecustomize.py == 8c2c8b14...（含 prefill_sp 双挂载的
#         现役版=K1-F1 回滚后 28-gates 形；换版时随链模板同 git 提交
#         更新本锚；GATE0D_EXPECTED_SITECUSTOMIZE_MD5 环境变量可覆盖）
#   0d-2  挂载面内容查：`from prefill_sp import install_model as
#         install_psp_model`（模型侧挂载行）在场 ≥1 次
#   0d-3  通信侧挂载面内容查：`from prefill_sp import
#         install_communication_op as install_psp_comm` 在场 ≥1 次
# 判别力红例（拔挂载行必红）：见 test_gate0d_anchor_red.sh（离线，不触
# ~/migrate-assets，拷贝到 /tmp 后拔行验证 0d-2/0d-3 必红；md5 篡改验证
# 0d-1 必红）。
#
# 红线：本件只读 $1（缺省 ~/migrate-assets/dsv41/adapter）；零写。

# 现役锚=8c2c8b14（28 gates，K1-F1 回滚后现役；含 prefill_sp 双挂载）。
# 7936496a=K1 火窗 29-gates 形（已随 K1 abort 回滚）；换版时随链模板同
# git 提交更新本锚。环境变量可覆盖（红例测试用）。
: "${GATE0D_EXPECTED_SITECUSTOMIZE_MD5:=8c2c8b143c3d670f5784c6aaa55dd53f}"
GATE0D_MOUNT_MODEL_NEEDLE="from prefill_sp import install_model as install_psp_model"
GATE0D_MOUNT_COMM_NEEDLE="from prefill_sp import install_communication_op as install_psp_comm"

gate0_sitecustomize_anchor() {
    local adp="${1:-$HOME/migrate-assets/dsv41/adapter}"
    local sc="$adp/sitecustomize.py"
    if [ ! -f "$sc" ]; then
        echo "ABORT 门0d：$sc 不在位——部署源缺 sitecustomize（键在≠件在变体：键照设而 prefill_sp 零挂载）"
        return 1
    fi
    local md n1 n2
    md=$(md5sum "$sc" | awk '{print $1}')
    if [ "$md" != "$GATE0D_EXPECTED_SITECUSTOMIZE_MD5" ]; then
        echo "ABORT 门0d：sitecustomize.py md5=$md ≠ 锚 $GATE0D_EXPECTED_SITECUSTOMIZE_MD5（误推工作树版/重组版——先核 sitecustomize 版本来源再点火）"
        return 1
    fi
    n1=$(grep -c "$GATE0D_MOUNT_MODEL_NEEDLE" "$sc" 2>/dev/null || true)
    n2=$(grep -c "$GATE0D_MOUNT_COMM_NEEDLE" "$sc" 2>/dev/null || true)
    if [ "${n1:-0}" -lt 1 ] || [ "${n2:-0}" -lt 1 ]; then
        echo "ABORT 门0d：sitecustomize 挂载面缺（model 挂载行=${n1:-0}/comm 挂载行=${n2:-0}，应各≥1）——拔行/丢挂载即键死件，boot 全绿零拦截的门0 前置红"
        return 1
    fi
    echo "门0d 绿：sitecustomize md5=$md + prefill_sp 双挂载面（model=${n1}/comm=${n2}）在位"
    return 0
}
