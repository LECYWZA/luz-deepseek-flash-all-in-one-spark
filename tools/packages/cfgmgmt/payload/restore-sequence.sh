#!/bin/bash
# restore-sequence.sh — 双复原义务序脚本（测试窗终→产线复原；TOOLS31 §二 P5-3）
#
# 【为什么存在】QA31/W5 等窗的「窗终复原」是义务序非单动作：撤测试件→面核→沉降→产线
#   boot→四查+七参直读+printenv+smoke。漏步=复原假绿（先例：复绿宣告早于 printenv 核）。
#   本件=序的检查单（--plan 打印序+核对面；--selfcheck 案头红绿）——**零执行面**：
#   每步动作由窗内既有件承载（r3-stop/adapter-sync/boot-with-slotlock/四查族），本件只钉序。
# 【双复原义务】①测试面复原（撤测试件/键/挂载，adapter-sync --check 复核）
#               ②产线面复原（50 键形 boot 在役：ENV50 15767aa6+SPEC6+W5 件面+overlay o12c1-prod）
# 用法：restore-sequence.sh --plan | --selfcheck
set -u
PLAN_TEXT='双复原义务序（窗终检查单——每步绿才进下一步；任一步红=停手呈裁不连发）：
  【段一 测试面复原】
  S1 停手取证：logs×4 先存（run.log/bench/state 尾段；INCIDENT 家族序）
  S2 拆测试栈：r3-stop（幂等）+qmg 收束（测试窗看护件窗终收束律）
  S3 撤测试件：测试键/件/挂载逐件撤（先存后删序；adapter 测试件撤=adapter-sync --prune 前置备份）
  S4 面核：adapter-sync.sh --check --expect sitecustomize.py=<当值>（面指纹四机全等；
     sitecustomize=变量位 SITECUSTOMIZE_MD5，FL6 接线后随窗重钉）
  【段二 产线面复原】
  S5 沉降：≥30min（双靴切换沉降律④ a105103——双栈生命周期二次重载红带族防御）
  S6 产线 boot：ARM_TAG=<窗名>RESTORE 经 tools/boot-with-slotlock.sh（P0 治理 wrapper；
     ENV50=PROD-R51W5-spec1.env〔15767aa6〕+SPEC6 六参+overlay o12c1-prod SGLANG_OVERLAY_DIR）
  S7 四查：health 200×4+banner29:4（逐形口径）+池 9,600,000+O12 四秩+fail-safe PASS×4+MISMATCH=0
  S8 七参直读：FP8=1/TG=1/R1INK=1/printenv 真键核（printenv-keycheck.sh --dump … --env ENV50）
  S9 warm 门+smoke：warm 64k×3 med ≥5000（台账登记）+smoke 3/3 正靶+8898 收净 000
  S10 复原宣告+台账：窗档全件归档（run.log/bench/state/四查件）+git 单件提交
  【判读红线】S7-S9 任一红=复原未达，产线宣告禁发；呈裁面不含自动重试（U1 律）。'

case "${1:-}" in
  --plan) echo "$PLAN_TEXT" ;;
  --selfcheck)
    rc=0
    # T1 序十步完备（S1..S10 每步在文；双段头在文）
    n=$(printf '%s\n' "$PLAN_TEXT" | grep -cE '^  S[0-9]+ ')
    [ "$n" = 10 ] && echo "[restore-seq][OK] T1 十步序完备（$n 步）" || { echo "[restore-seq][RED] T1 步数=$n（应 10）"; rc=1; }
    printf '%s\n' "$PLAN_TEXT" | grep -q '【段一 测试面复原】' && printf '%s\n' "$PLAN_TEXT" | grep -q '【段二 产线面复原】' \
      && echo "[restore-seq][OK] T1 双复原义务双段在文" || { echo "[restore-seq][RED] T1 双段缺"; rc=1; }
    # T2 关键律面（沉降 30min/slotlock/四查/printenv/smoke/先存后删）
    for pat in '≥30min' 'boot-with-slotlock' 'fail-safe PASS×4' 'printenv' 'smoke 3/3' '先存后删'; do
      printf '%s\n' "$PLAN_TEXT" | grep -q "$pat" || { echo "[restore-seq][RED] T2 律面缺：$pat"; rc=1; }
    done
    [ "$rc" = 0 ] && echo "[restore-seq][OK] T2 六律面全在文（沉降/slotlock/四查/printenv/smoke/先存后删）"
    # T3 红例：缺步序文本必被识别（判别力=步数计数器）
    bad=$(printf '%s\n' "$PLAN_TEXT" | grep -vE '^  S5 |^  S6 ')
    nb=$(printf '%s\n' "$bad" | grep -cE '^  S[0-9]+ ')
    [ "$nb" = 8 ] && echo "[restore-seq][OK] T3 红例判红（摘两步→计数 8≠10 被识别）" || { echo "[restore-seq][RED] T3 判别力失效"; rc=1; }
    exit "$rc" ;;
  *) echo "用法：$0 --plan | --selfcheck" >&2; exit 2 ;;
esac
