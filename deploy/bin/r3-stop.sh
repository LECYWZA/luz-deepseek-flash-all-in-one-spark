#!/usr/bin/env bash
# r3-stop.sh — 拆 r3boot 栈（head 本机 + 三 worker），供臂间轮换
# PROD-RS-20261003 名隔离：CTN_PREFIX 可被环境覆盖（生产栈=r3prod-*，
# 缺省 r3boot =测试线行为逐字不变）。
set -u
CTN_PREFIX="${CTN_PREFIX:-r3boot}"
CTN="${CTN_PREFIX}-worker"
docker rm -f "${CTN_PREFIX}-head" >/dev/null 2>&1 && echo "[+] head removed" || echo "[.] head 无"
for h in dgxspark02 dgxspark04 dgxspark03; do
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$h" "docker rm -f $CTN" >/dev/null 2>&1 && echo "[+] $h worker removed" || echo "[.] $h worker 无"
done
sleep 3; echo "== 残留检查 =="
docker ps --format '{{.Names}}' | grep -E "${CTN_PREFIX}-|dsv41" || echo "本机无残留"

# ── [QA-GATES L14·D8] 停栈三查可选节（2026-10-05 QAVLW2 固化；追加式缺省 no-op）──
# R3_STOP_VERIFY=1 启用；缺省（未设/非 1）行为逐字节不变（本节不执行）。
# 三查（README-RELEASE §5 三同现陷阱）：①四机 r3 栈容器=0；②8899=000；③8898=000。
# 任一红=大声报+exit 4（禁下一步：栈未停净）。curl 全带 --max-time（L6 挂起族纪律）。
if [[ "${R3_STOP_VERIFY:-0}" = 1 ]]; then
  vfail=0
  echo "== [D8] 停栈三查（R3_STOP_VERIFY=1）=="
  for H in dgxspark01 dgxspark02 dgxspark03 dgxspark04; do
    if [[ "$H" == dgxspark01 ]]; then
      n=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -cE '^r3(prod|boot)-' || true)
    else
      n=$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$H" "docker ps -a --format '{{.Names}}' 2>/dev/null | grep -cE '^r3(prod|boot)-'" 2>/dev/null || true)
    fi
    [[ "$n" =~ ^[0-9]+$ ]] || n='?'
    echo "[D8] $H r3 栈容器 n=$n"
    [[ "$n" = 0 ]] || vfail=1
  done
  p9=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8899/health || true); p9=${p9:-000}
  p8=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8898/health || true); p8=${p8:-000}
  echo "[D8] 双端口 8899=$p9 8898=$p8"
  [[ "$p9" == 000 ]] || vfail=1
  [[ "$p8" == 000 ]] || vfail=1
  if [[ "$vfail" = 1 ]]; then
    echo "[D8][RED] 停栈未净（容器≠0 或端口≠000）——三同现陷阱：继续下一步=带病运行（L14）" >&2
    exit 4
  fi
  echo "[D8] 停栈三查 PASS（四机容器 0+双端口 000）"
fi
