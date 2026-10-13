#!/bin/bash
# 2026-10-13 用户裁定修正：不新增配置文件 —— 移除 00- drop-in，仅保留 99-hardening.conf 就地修改。
# 须 root 运行；幂等。
set -u
D=/etc/ssh/sshd_config.d
H=$(hostname)

# 1) 移除 00- drop-in
rm -f "$D/00-enable-password-login.conf"

# 2) 清除 99-hardening.conf 的留痕注释（恢复原三行结构）
if [ -f "$D/99-hardening.conf" ] && grep -q '^# 2026-10-10 user-directed' "$D/99-hardening.conf"; then
    sed -i '/^# 2026-10-10 user-directed/d' "$D/99-hardening.conf"
    echo "[$H] comment line removed"
fi

# 3) 备份件移出配置目录（保持目录结构原样）
if [ -f "$D/99-hardening.conf.bak-enablepw-20261010" ]; then
    mkdir -p /var/backups
    mv -f "$D/99-hardening.conf.bak-enablepw-20261010" /var/backups/99-hardening.conf.bak-enablepw-20261010
    echo "[$H] backup moved to /var/backups/"
fi

echo "[$H] == config dir =="
ls -la "$D"
echo "[$H] == 99-hardening.conf =="
cat "$D/99-hardening.conf"

sshd -t || { echo "[$H] SSHD_TEST_FAIL"; exit 1; }
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
sleep 1
echo "[$H] == effective =="
sshd -T | grep -iE '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication)'
