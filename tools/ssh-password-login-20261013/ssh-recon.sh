#!/bin/bash
# 四机 sshd 密码登录现状勘察（只读）
H=$(hostname); echo "===== $H ====="
echo "-- main sshd_config: Include / auth 相关行 --"
grep -nE '^[[:space:]]*Include|PasswordAuthentication|KbdInteractive|ChallengeResponse|AuthenticationMethods|UsePAM|AllowUsers|DenyUsers|^[[:space:]]*Match' /etc/ssh/sshd_config 2>/dev/null || true
echo "-- drop-ins --"
ls /etc/ssh/sshd_config.d/ 2>/dev/null || true
grep -rnE 'PasswordAuthentication|KbdInteractive|AuthenticationMethods|ChallengeResponse' /etc/ssh/sshd_config.d/ 2>/dev/null || true
echo "-- effective (root 视角) --"
cat ~/.sudopw | sudo -S sshd -T 2>/dev/null | grep -iE '^(passwordauthentication|kbdinteractiveauthentication|usepam|authenticationmethods|pubkeyauthentication|permitrootlogin|challengeresponseauthentication)'
echo "-- account (passwd -S) --"
passwd -S liux***ya 2>/dev/null || true
echo "-- units --"
systemctl is-active ssh 2>&1
systemctl is-active ssh.socket 2>&1
