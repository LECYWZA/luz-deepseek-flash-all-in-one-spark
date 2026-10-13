#!/usr/bin/env python3
"""memguard_r1 —— 水位主动 abort 常备件（三参考可移植高优项 #1 的工具化落地）。

出处：mia scripts/verify/memguard.py（MIA-LONGCTX-RECON-20260930 P3；STDFORM
可行性案头 §5.3 #1）；机制=1s 采样 MemAvailable，跌破阈值 POST /abort_request
{abort_all}——**保靴不拆靴**（防 head 楔死后 workers 继续盘读的连锁；把长档
测试从「哨兵拆靴」变「熔断请求」）。标准形态 600k×16 满驻冒烟的前置安全件。

本件离线可测：--once 单采样模式（不发请求）；--selftest 用假水位序列走全状态机
（零网络零请求）。生产用法（认证火窗内、head 机）：

    python3 memguard_r1.py --base http://127.0.0.1:8898 --threshold-mb 9216 &

纪律：阈值起步 9G=对齐 C16 驱动器中止线与 watchdog 预警（STDFORM §一-6）；
oom-gate 地板 1.5G=禁区与本件无关（本件在水位跌破 9G 时先熔断请求，永远到不了
地板）；abort 后**不重试不复活**——留现场给链的 tripwire 段处置。
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request


def read_watermark_mb() -> int:
    with open("/proc/meminfo") as fh:
        for line in fh:
            if line.startswith("MemAvailable:"):
                return int(line.split()[1]) // 1024
    raise RuntimeError("MemAvailable unreadable")


def abort_all(base: str, timeout: float = 5.0) -> dict:
    """POST /abort_request {abort_all: true}（sglang http_server 已有端点）。"""
    req = urllib.request.Request(
        base.rstrip("/") + "/abort_request",
        data=json.dumps({"abort_all": True}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return {"status": resp.status, "body": resp.read(200).decode(errors="replace")}


class Memguard:
    """状态机：sample → (低于阈值) → abort_all → latched（一次熔断，永不重试）。"""

    def __init__(self, threshold_mb: int, on_abort=None):
        self.threshold_mb = threshold_mb
        self.on_abort = on_abort or abort_all
        self.latched = False
        self.log: list[dict] = []

    def observe(self, water_mb: int) -> str:
        """一次观测（水位值由调用方喂——生产=read_watermark_mb，自测=假序列）。"""
        state = ("ABORT" if water_mb < self.threshold_mb and not self.latched
                 else "LATCHED" if self.latched
                 else "OK")
        entry = {"water_mb": water_mb, "state": state, "ts": round(time.time(), 3)}
        if state == "ABORT":
            try:
                entry["abort"] = self.on_abort()
                self.latched = True
            except Exception as exc:  # abort 失败也要 latched？否——可重试但记错
                entry["abort_error"] = f"{type(exc).__name__}: {exc}"
        self.log.append(entry)
        return state


def selftest() -> int:
    """零网络状态机自测：假 abort + 三段水位序列（高→破线→latched 后回高）。"""
    calls = []

    def fake_abort():
        calls.append(1)
        return {"status": 200, "body": "ok"}

    mg = Memguard(threshold_mb=9216, on_abort=fake_abort)
    seq = [(20000, "OK"), (10000, "OK"), (9000, "ABORT"), (8500, "LATCHED"),
           (20000, "LATCHED")]
    ok = True
    for water, want in seq:
        got = mg.observe(water)
        good = got == want
        ok &= good
        print(f"  {'PASS' if good else 'FAIL'}  water={water} → {got}（期望 {want}）")
    ok &= len(calls) == 1
    print(f"  {'PASS' if len(calls) == 1 else 'FAIL'}  abort 恰一次（latched 不重复）")
    bad = Memguard(threshold_mb=9216, on_abort=fake_abort)
    got = bad.observe(9216)  # 边界：恰等于阈值不熔断（严格 < 才熔）
    ok &= got == "OK"
    print(f"  {'PASS' if got == 'OK' else 'FAIL'}  边界：water==threshold 不熔断")
    print("ALL PASS" if ok else "FAIL")
    return 0 if ok else 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--base", default="http://127.0.0.1:8898")
    ap.add_argument("--threshold-mb", type=int, default=9216,
                    help="水位阈值（MiB；缺省 9G=C16 驱动器中止线）")
    ap.add_argument("--interval", type=float, default=1.0)
    ap.add_argument("--once", action="store_true", help="单采样即退（不发请求）")
    ap.add_argument("--selftest", action="store_true", help="零网络状态机自测")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()
    water = read_watermark_mb()
    print(f"[memguard_r1] water={water}MiB threshold={args.threshold_mb}MiB "
          f"base={args.base}", flush=True)
    if args.once:
        return 0 if water >= args.threshold_mb else 3

    mg = Memguard(args.threshold_mb)
    while True:
        state = mg.observe(read_watermark_mb())
        if state != "OK":
            print(f"[memguard_r1] {state} water={mg.log[-1]['water_mb']}MiB — "
                  f"熔断后退出（不重试不复活；现场归链处置）", flush=True)
            return 3
        time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main())
