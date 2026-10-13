#!/bin/bash
# 2026-10-13 四机启用 SSH 密码登录（用户指令：网络配置优化前置）
# 形态（用户裁定）：不新增配置文件，仅就地修改既有 99-hardening.conf。须 root；幂等。
set -u
D=/etc/ssh/sshd_config.d
F="$D/99-hardening.conf"
H=$(hostname)

echo "[$H] == before =="
cat "$F"

# 备份到 /var/backups（不落配置目录；已有备份则不重复备份，避免用改后版覆盖原版）
if ! ls /var/backups/99-hardening.conf.bak-enablepw-* >/dev/null 2>&1; then
    mkdir -p /var/backups
    cp "$F" "/var/backups/99-hardening.conf.bak-enablepw-$(date +%Y%m%d)"
    echo "[$H] backup created"
fi

# 就地修改两个 no -> yes
sed -i -E 's/^[[:space:]]*(PasswordAuthentication|KbdInteractiveAuthentication)[[:space:]]+no/\1 yes/' "$F"

sshd -t || { echo "[$H] SSHD_TEST_FAIL"; exit 1; }
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
sleep 1
echo "[$H] == after =="
cat "$F"
echo "[$H] == effective =="
sshd -T | grep -iE '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication)'
