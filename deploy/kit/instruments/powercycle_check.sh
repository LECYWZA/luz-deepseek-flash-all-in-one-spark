#!/bin/bash
# powercycle_check.sh — 断电/冷断电后的四机一键复核（2026-09-21 门禁统筹⑤）
#
# 为什么存在：2026-09-21 断电连环事故的教训——断电后遗症不是一个病是一窝
# （GID 洞→NCCL 61 死；PD 安全模式→某机时钟钉 513-728MHz→TP4 全体减半；
#  停泊容器被 restart 策略拉回→polkitd 风暴；内核候选漂移→NCCL/RoCE ENOMEM）。
# 逐项手查花了一整天；本脚本把它们压成一次 60 秒扫描。
#
# 用法（栈必须停着：burn 探针要独占 GPU；从 01 跑）：
#   bash ~/w6-kit/powercycle_check.sh
# 退出码 0=全绿可复栈；1=有 FAIL（照输出逐项修，修完重跑）。
#
# 各项修复手册：~/w6-kit/FABRIC-GID-REPAIR-RUNBOOK.md（§2 GID 修法/§5 清单/§7 时钟病）

set -uo pipefail
HOSTS=(dgxspark01 dgxspark02 dgxspark04 dgxspark03)   # ring 序
IMG=dsv41-sglang-optimized:0.2.7
# ssh 有界化（审计 P1：无 ConnectTimeout 时失联机每次命令都吃 TCP 重试超时）
SSHOPT=(-o ConnectTimeout=8 -o BatchMode=yes)
GID_IDX=3
declare -a RES=()
bad=0
# ⚠ rec 必须显式 return 0（审计 P0 实锤）：记 PASS/WARN 时末条 `[ ]` 测试为假，
# 函数返回 1——上游 `A && rec PASS … || rec FAIL …` 会跟着触发 || 分支，
# 健康项被双记录成 PASS+FAIL（四机 12 条假 FAIL，退出码恒 1，全绿不可达）。
rec() { RES+=("$1|$2|$3"); [ "$1" = FAIL ] && bad=$((bad+1)); return 0; }

# burn 探针（宿主侧跑不了 torch 时退化为纯时钟采样，判别力降级但零依赖）
burn_clock() {  # $1=host  输出 "<MHz> <W>" 或 ERR
  local h=$1 out
  if [ "$h" = dgxspark01 ]; then
    docker image inspect $IMG >/dev/null 2>&1 || { echo ERR; return; }
    nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | grep -q '[0-9]' && { echo BUSY; return; }
    docker run --rm --gpus all --entrypoint python $IMG -c "
import torch,time
a=torch.randn(8192,8192,device='cuda');b=torch.randn(8192,8192,device='cuda')
t0=time.time()
while time.time()-t0<6: c=a@b; torch.cuda.synchronize()
" >/dev/null 2>&1 & local p=$!; sleep 4
    out=$(nvidia-smi --query-gpu=clocks.sm,power.draw --format=csv,noheader,nounits | tr -d ' ')
    wait $p 2>/dev/null; echo "$out"
  else
    ssh "$h" "docker image inspect $IMG >/dev/null 2>&1 || { echo ERR; exit 0; }
nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | grep -q '[0-9]' && { echo BUSY; exit 0; }
docker run --rm --gpus all --entrypoint python $IMG -c \"
import torch,time
a=torch.randn(8192,8192,device='cuda');b=torch.randn(8192,8192,device='cuda')
t0=time.time()
while time.time()-t0<6: c=a@b; torch.cuda.synchronize()
\" >/dev/null 2>&1 & p=\$!; sleep 4
nvidia-smi --query-gpu=clocks.sm,power.draw --format=csv,noheader,nounits | tr -d ' '
wait \$p 2>/dev/null" 2>/dev/null
  fi
}

# 预检：栈必须停着（burn 探针独占 GPU 的前提）
if nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | grep -q '[0-9]'; then
  echo "[die] 本机 GPU 有计算进程（栈在跑？）——本扫描的 burn 探针须独占 GPU。先 ./stop.sh 再跑。" >&2
  exit 2
fi

echo "══ powercycle_check $(date -Is)（四机断电后遗症扫描；修复手册=FABRIC-GID-REPAIR-RUNBOOK.md）"

for h in "${HOSTS[@]}"; do
  if [ "$h" = dgxspark01 ]; then RUN=eval; else RUN="ssh ${SSHOPT[*]} $h"; fi
  # ⚠ RUN=eval 不是 local：`local` 是 bash 内建（仅函数内可用），`$RUN 'cmd'` 会执行
  # `local 'cmd'` 报错→空输出——01 的本地检查曾整体假 PASS/假 FAIL（复验实锤）。

  # ⓪ 探活（审计 P1：失联机的 MTU/GID/停泊三项会假 PASS、burn 假 FAIL 误导拔电——
  #    失联是一等故障，先出声再跳过，不拿空输出当「一切正常」）
  if [ "$h" != dgxspark01 ] && ! ssh "${SSHOPT[@]}" "$h" true 2>/dev/null; then
    rec FAIL "host unreachable（ssh 探活失败：未开机完/网络/sshd——本机其余各项未检）" "$h"
    continue
  fi

  # ① 内核（毒=精确串 7.0.0-1019：打瘫 NCCL/RoCE ibv_reg_mr_iova2 ENOMEM；
  #    7.0.0-103x 已确认可用勿误伤——审计 P1 修：旧 7.0* 模式会错杀 -1032；在役=6.17.0-103x）
  kv=$($RUN 'uname -r' 2>/dev/null)
  case "$kv" in
    6.17.0-10*) rec PASS "kernel=$kv" "$h" ;;
    7.0.0-1019*) rec FAIL "kernel=$kv（毒内核！apt-mark hold 是否失效？）" "$h" ;;
    7.0.0-10*)  rec PASS "kernel=$kv（7.0.0-103x=论坛确认可用）" "$h" ;;
    *)          rec WARN "kernel=$kv（非预期版本，人工确认 hold 状态）" "$h" ;;
  esac

  # ② isolcpus
  $RUN 'grep -q "isolcpus=8-9" /proc/cmdline' 2>/dev/null \
    && rec PASS "isolcpus=8-9 在" "$h" || rec FAIL "isolcpus 丢失（GRUB 坏？）" "$h"

  # ③ MTU（fabric 十六口 9000）
  mtu_bad=$($RUN 'for n in enp1s0f0np0 enp1s0f1np1 enP2p1s0f0np0 enP2p1s0f1np1; do ip link show $n 2>/dev/null | grep -q mtu\ 9000 || echo $n; done' 2>/dev/null)
  [ -z "$mtu_bad" ] && rec PASS "MTU 4×9000" "$h" || rec FAIL "MTU 非9000: $mtu_bad" "$h"

  # ④ GID 洞（idx3 RoCE v2；修法=runbook §2 IP 环回）
  holes=$($RUN "for c in rocep1s0f0 rocep1s0f1 roceP2p1s0f0 roceP2p1s0f1; do [ -d /sys/class/infiniband/\$c ] || continue; [ \"\$(cat /sys/class/infiniband/\$c/ports/1/gid_attrs/types/$GID_IDX 2>/dev/null)\" = 'RoCE v2' ] || echo \$c; done" 2>/dev/null)
  [ -z "${holes// /}" ] && rec PASS "GID idx$GID_IDX 无洞" "$h" || rec FAIL "GID 洞: ${holes// /}（runbook §2 修复）" "$h"

  # ⑤ GPU 时钟 burn 探针（PD 安全模式；修法=runbook §7 冷断电）
  bc=$(burn_clock "$h")
  bmhz=$(printf '%s' "$bc" | cut -d',' -f1 | grep -oE '^[0-9]+' || echo 0)
  bw=$(printf '%s' "$bc" | cut -d',' -f2 | grep -oE '^[0-9]+' || echo '?')
  case "$bc" in
    ERR)  rec WARN "burn 探针跑不了（缺镜像/依赖）——人工 nvidia-smi 负载态判" "$h" ;;
    BUSY) rec WARN "GPU 被占（这台栈没停？）——burn 跳过" "$h" ;;
    *) if ! [[ "${bmhz:-}" =~ ^[1-9][0-9]*$ ]]; then
         rec WARN "burn 无有效读数（bc='$bc'）=UNKNOWN——勿当健康勿当楔死，人工复核" "$h"
       elif [ "${bmhz}" -ge 1500 ]; then
         rec PASS "GPU burn=${bmhz}MHz/${bw}W（健康）" "$h"
       else
         rec FAIL "GPU burn=${bmhz}MHz/${bw}W —— PD 安全模式楔死（关机拔墙上AC 1-2分钟；warm reboot 无效；runbook §7）" "$h"
       fi ;;
  esac

  # ⑥ 停泊容器复活（sparkDash 系=polkitd 风暴源）
  zomb=$($RUN 'docker ps --format "{{.Names}}" 2>/dev/null | grep -iE "^sparkdash" | tr "\n" " "' 2>/dev/null)
  [ -z "$zomb" ] && rec PASS "无停泊容器复活" "$h" || rec WARN "停泊复活: $zomb（docker update --restart=no 后 stop）" "$h"

  # ⑦ autotune golden 树一致性（对齐 01 基准）
  gmd5=$($RUN 'md5sum ~/dsv41-flash-dgxsparks/autotune-golden/MANIFEST.json 2>/dev/null | cut -d" " -f1' 2>/dev/null)
  [ -z "$gmd5" ] && rec WARN "无 autotune-golden 树（未启用形态）" "$h" || rec PASS "golden MANIFEST=${gmd5:0:8}" "$h"
done

# golden 四机一致性（审计 P2 修：全树对比而非仅 MANIFEST——表被改而 MANIFEST 未动时
# 旧法照 PASS；⚠ sort 必须钉 LC_ALL=C：locale 差异会让同内容树打出不同聚合 md5
# ——且 `LC_ALL=C find…| sort` 的前缀只作用 find 不作用 sort，必须前置于 sort）
_tree_md5() { find "$HOME/dsv41-flash-dgxsparks/autotune-golden" -type f -name '*.json' | LC_ALL=C sort | xargs md5sum 2>/dev/null | md5sum | cut -d' ' -f1; }
base_md5=$(_tree_md5)
if [ -z "$base_md5" ]; then
  rec FAIL "golden 树缺失（在役形态被破坏？锁定被绕过——重建见 AUTOTUNE-GOLDEN-RUNBOOK.md）" dgxspark01
else
  rec PASS "golden 全树 md5=${base_md5:0:8}（LC_ALL=C）" dgxspark01
  for h in dgxspark02 dgxspark04 dgxspark03; do
    m=$(ssh "${SSHOPT[@]}" "$h" 'find "$HOME/dsv41-flash-dgxsparks/autotune-golden" -type f -name "*.json" | LC_ALL=C sort | xargs md5sum 2>/dev/null | md5sum | cut -d" " -f1')
    [ "$m" = "$base_md5" ] && rec PASS "golden 全树=01" "$h" || rec FAIL "golden 全树 md5 与 01 不一致（rsync 未跑？runbook 步骤 6）" "$h"
  done
fi

# NCCL ringonly 库四机一致性（锚定 01）
_head_nccl=$(docker run --rm --entrypoint md5sum $IMG /opt/nccl-ringonly/libnccl.so.2 2>/dev/null | cut -d' ' -f1)
if [ -z "$_head_nccl" ]; then
  rec WARN "NCCL 基准取不到（01 侧 docker run 失败：镜像不在/daemon 死？）——四机均一性未检" dgxspark01
else
  for h in dgxspark02 dgxspark04 dgxspark03; do
    m=$(ssh "${SSHOPT[@]}" "$h" "docker run --rm --entrypoint md5sum $IMG /opt/nccl-ringonly/libnccl.so.2 2>/dev/null | cut -d' ' -f1")
    if [ -z "$m" ]; then rec WARN "NCCL md5 取不到（ssh/docker 失败——未检，勿当一致）" "$h"
    elif [ "$m" != "$_head_nccl" ]; then rec FAIL "NCCL ringonly md5 与 01 不一致（镜像漂移？）" "$h"
    else rec PASS "NCCL ringonly=01" "$h"; fi
  done
fi

echo
printf '%-5s %-58s %s\n' 判定 项 主机
printf '%s\n' "----------------------------------------------------------------"
for r in "${RES[@]}"; do IFS='|' read -r v item host <<<"$r"; printf '%-5s %-58s %s\n' "$v" "$item" "$host"; done
echo "----------------------------------------------------------------"
if [ "$bad" = 0 ]; then
  echo "VERDICT: PASS —— 断电后遗症全清，可复栈（ENV_FILE=.env.tp4 ./start.sh serve）"
  exit 0
fi
echo "VERDICT: $bad FAIL —— 逐项修复（每条 FAIL 自带修复指针）后重跑本扫描；全绿再复栈"
exit 1
