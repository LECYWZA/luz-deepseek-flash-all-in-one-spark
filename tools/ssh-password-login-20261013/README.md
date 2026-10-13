# 四机 SSH 密码登录运维件（2026-10-13 生效）

> 用途：DGX Spark 四机（dgxspark01..04）开启 SSH 密码登录（用户指令：网络配置
> 优化前置）。**凭据绝不入仓**——口令恒从宿主 `~/.sudopw` 文件读入，绝不打印。

## 机制（最终形）

sshd「首值生效」语义 + Include 位于主配置头部 ⇒ drop-in
`/etc/ssh/sshd_config.d/99-hardening.conf` 两值 no→yes（**结构不变，仍为原 3 行**；
`PermitRootLogin prohibit-password` 未动）压过主 `sshd_config` 71 行 no。
不新增任何配置文件（初版 00- 双保险件已按用户裁定撤除）。改后
99-hardening.conf md5 `2c9c15fccd6949e5ceb4f74c9ac8932b` 四机全等；
`sshd -T` 复核 passwordauthentication/kbdinteractiveauthentication/pubkeyauthentication
均 yes。原始件（8月13 原版）备份=
`/var/backups/99-hardening.conf.bak-enablepw-20261013`（四机）。

## 脚本与用法

| 件 | 用法 | 说明 |
|---|---|---|
| `ssh-recon.sh` | `bash ssh-recon.sh [<host>]` | 只读勘察：配置现状/有效口径/账户/服务形态 |
| `enable-pw-login.sh` | `bash enable-pw-login.sh` | 就地式应用（幂等；仅动 99-hardening.conf；备份落 /var/backups；不新增文件） |
| `pw-login-test.py` | `python3 pw-login-test.py liux***ya@<host>` | pty 驱动纯密码登录在线验证（禁公钥/禁复用；口令从 ~/.sudopw 读且绝不打印） |

## 验证基线（改后全套实测，全绿）

- 判别力基线（改前）：纯密码登录 FAIL `Permission denied (publickey)`；
- 改后四机在线实测：01→127.0.0.1 与 01→187/188/189 全 OK（PWLOGIN_OK_dgxspark01..04）；
- 密钥回归：四机 BatchMode 密钥登录全绿。

## 回退（每机，任一法）

```bash
# 法一：值改回
sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/; s/^KbdInteractiveAuthentication yes/KbdInteractiveAuthentication no/' /etc/ssh/sshd_config.d/99-hardening.conf
# 法二：从备份恢复原件
sudo cp /var/backups/99-hardening.conf.bak-enablepw-20261013 /etc/ssh/sshd_config.d/99-hardening.conf
sudo sshd -t && sudo systemctl reload ssh
```
