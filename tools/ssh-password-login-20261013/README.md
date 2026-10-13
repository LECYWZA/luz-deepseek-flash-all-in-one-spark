# 四机 SSH 密码登录启用（2026-10-13，用户指令：网络配置优化前置）

## 最终形态（用户裁定后：不新增配置文件，仅就地修改既有文件）
- `/etc/ssh/sshd_config.d/99-hardening.conf` 两值 no→yes，**结构不变（仍为原 3 行）**：
  ```
  PasswordAuthentication yes
  KbdInteractiveAuthentication yes
  PermitRootLogin prohibit-password   ← 未动
  ```
- 原始件备份（内容=8月13 原版）：`/var/backups/99-hardening.conf.bak-enablepw-20261013`（四机）
- 初版曾新增 `00-enable-password-login.conf` 作双保险；2026-10-13 用户裁定**不允许新增配置文件** ⇒ 四机已撤除。最终机制=就地修改单一路径，配置目录仅剩 99-hardening.conf 一件。

## 改前状态（四机一致）
阻断源=99-hardening.conf（8月13 建立）：`PasswordAuthentication no` + `KbdInteractiveAuthentication no`；主 `sshd_config` 71 行另有活跃 `KbdInteractiveAuthentication no`；Include 在头部（12 行）。账户 liux***ya 口令正常（P 态）。

## 生效原理（已实测核验）
sshd「首值生效」语义 + Include 位于主配置头部 ⇒ drop-in 先解析 ⇒ 99-hardening 的 yes 压过主文件 71 行 no。`sshd -T` 四机复核：passwordauthentication yes / kbdinteractiveauthentication yes / pubkeyauthentication yes。

## 验证证据（撤 00- 后全套重跑，全绿）
- 判别力基线（改前）：纯密码登录 FAIL `Permission denied (publickey)`
- 改后四机在线实测：01→127.0.0.1 与 01→187/188/189 全 OK（PWLOGIN_OK_dgxspark01..04）
- 密钥回归：四机 BatchMode 密钥登录全绿
- 一致性：99-hardening.conf 改后 md5 `2c9c15fccd6949e5ceb4f74c9ac8932b` 四机全等

## 回退（每机，任一法）
```
# 法一：值改回
sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/; s/^KbdInteractiveAuthentication yes/KbdInteractiveAuthentication no/' /etc/ssh/sshd_config.d/99-hardening.conf
# 法二：从备份恢复原件
sudo cp /var/backups/99-hardening.conf.bak-enablepw-20261013 /etc/ssh/sshd_config.d/99-hardening.conf
sudo sshd -t && sudo systemctl reload ssh
```

## 脚本
- `ssh-recon.sh`：只读勘察（配置现状/有效口径/账户/服务形态）
- `enable-pw-login.sh`：就地式应用（幂等；仅动 99-hardening.conf；备份落 /var/backups；不新增文件）
- `remove-00-file.sh`：撤除初版 00- 件/注释、备份归位（一次性修正脚本，留档）
- `pw-login-test.py`：pty 驱动纯密码登录在线验证（禁公钥/禁复用；口令从 ~/.sudopw 读且绝不打印）

## 日期勘误
初版记录误标 2026-10-10；实际操作=2026-10-13（mtime 三证；归档目录/备份文件名已更正为 20261013）。
