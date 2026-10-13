#!/usr/bin/env python3
"""纯密码登录在线验证（pty 驱动 ssh，判死型测试架）。

用法: pw-login-test.py liux***ya@<host>
- 禁用公钥、关闭连接复用/跳板，只走 password / keyboard-interactive
- 口令从 ~/.sudopw 读取；绝不打印口令（输出前一律替换为 ***）
- 成功判据: 远端执行 `echo PWLOGIN_OK_$(hostname)` 返回唯一标记
"""
import os
import pty
import select
import sys
import time

MARK = "PWLOGIN_OK"


def main():
    target = sys.argv[1]
    with open(os.path.expanduser("~/.sudopw")) as f:
        password = f.read().strip()

    args = [
        "ssh",
        "-o", "PubkeyAuthentication=no",
        "-o", "PreferredAuthentications=password,keyboard-interactive",
        "-o", "NumberOfPasswordPrompts=1",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "ControlMaster=no",
        "-o", "ControlPath=none",
        "-o", "ProxyJump=none",
        "-o", "ConnectTimeout=8",
        target,
        "echo " + MARK + "_$(hostname)",
    ]

    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("ssh", args)
        os._exit(127)

    buf = b""
    sent = False
    deadline = time.time() + 25
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.5)
        if r:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            if not sent and b"assword" in buf.lower():
                os.write(fd, (password + "\n").encode())
                sent = True
        done, _ = os.waitpid(pid, os.WNOHANG)
        if done == pid:
            break

    # 残余输出排空
    for _ in range(10):
        r, _, _ = select.select([fd], [], [], 0.1)
        if not r:
            break
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
    try:
        os.waitpid(pid, os.WNOHANG)
    except OSError:
        pass

    ok = MARK in buf.decode(errors="replace")
    text = buf.decode(errors="replace").replace(password, "***")
    print("RESULT:", "OK" if ok else "FAIL", "target=" + target)
    for line in [l for l in text.splitlines() if l.strip()][-6:]:
        print("  |", line[:180])
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
