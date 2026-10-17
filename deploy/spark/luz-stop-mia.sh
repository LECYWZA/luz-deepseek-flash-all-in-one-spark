#!/usr/bin/env bash
# 阶段1：停 mia 栈 + 权重 NFS 切到 1017（LuZ 部署前置）
# 依据：OPS-MANUAL「沉降 600s 律」+「容器删除前必存 docker logs」
set -euo pipefail
SSHO="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8"
TS=$(date +%Y%m%d-%H%M%S); L=/root/luz-logs/stop-$TS; mkdir -p "$L"
H=192.168.123.103; W2=192.168.123.109; W3=192.168.123.232; W4=192.168.123.65
echo "=== 阶段1 开始 $(date +%F' '%T) ==="

echo "[1/4] 停前存 docker logs（文档硬规）"
docker logs dsv41-mia-head > "$L/spark-1-head.log" 2>&1 || true
i=1; for ip in $W2 $W3 $W4; do i=$((i+1)); $SSHO root@$ip "docker logs dsv41-mia-worker" > "$L/spark-$i-worker.log" 2>&1 || true; done
ls -lh "$L" | tail -4

echo "[2/4] 停 mia 容器（四机）"
docker rm -f dsv41-mia-head >/dev/null 2>&1 || true
for ip in $W2 $W3 $W4; do $SSHO root@$ip "docker rm -f dsv41-mia-worker >/dev/null 2>&1 || true"; done
for ip in $H $W2 $W3 $W4; do
  if [ "$ip" = "$H" ]; then n=$(docker ps -q | wc -l); else n=$($SSHO root@$ip "docker ps -q | wc -l"); fi
  echo "  $ip 运行中容器数: $n"
done

echo "[3/4] 权重 NFS 切换：dsv41-nfs(Abliterated) → luz-nfs(1017)"
docker rm -f dsv41-nfs >/dev/null 2>&1 || true
docker run -d --name luz-nfs --restart unless-stopped --network host --privileged \
  -e TZ=Asia/Shanghai \
  -e NFS_CLIENTS=192.168.100.0/24,192.168.101.0/24,192.168.102.0/24,192.168.103.0/24,192.168.123.0/24 \
  -v /etc/localtime:/etc/localtime:ro \
  -v /root/NewModels/DeepSeek-V4.1-Flash-1017:/export:ro \
  dsv41-nfs:local >/dev/null
sleep 6
docker ps --filter name=luz-nfs --format "  {{.Names}} {{.Status}}"
showmount -e 127.0.0.1 2>/dev/null | head -2 || echo "  (showmount 未装，跳过)"

echo "[4/4] worker 只读挂载 /mnt/luz-weights"
$SSHO root@$W2 "mkdir -p /mnt/luz-weights; (mountpoint -q /mnt/luz-weights && umount -l /mnt/luz-weights) || true; mount -t nfs -o ro,vers=4.2,nconnect=8,timeo=600,retrans=2 192.168.100.1:/ /mnt/luz-weights"
$SSHO root@$W3 "mkdir -p /mnt/luz-weights; (mountpoint -q /mnt/luz-weights && umount -l /mnt/luz-weights) || true; mount -t nfs -o ro,vers=4.2,nconnect=8,timeo=600,retrans=2 192.168.101.1:/ /mnt/luz-weights"
$SSHO root@$W4 "mkdir -p /mnt/luz-weights; (mountpoint -q /mnt/luz-weights && umount -l /mnt/luz-weights) || true; mount -t nfs -o ro,vers=4.2,nconnect=8,timeo=600,retrans=2 192.168.101.1:/ /mnt/luz-weights"
for ip in $W2 $W3 $W4; do $SSHO root@$ip "test -f /mnt/luz-weights/config.json && echo '  $ip 权重可见 ✓'"; done

date +%s > /root/luz-logs/.stop_ts
echo "=== 阶段1 完成 $(date +%F' '%T)；沉降起点已记录，600s 后（约 $(date -d '+600 seconds' +%T)）可点火 ==="
