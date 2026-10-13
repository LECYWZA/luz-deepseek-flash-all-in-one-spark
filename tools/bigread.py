#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""bigread — 大文件只读探针护栏（QA-TOOLS 20261006 任务 2）。

事故源（A24DDCOFF 2026-10-05 16:32）：离线探针 json.load 整读 159MB census trace →
head RSS 数 GB → MemAvailable 1.4GiB 破 oom-gate 地板 1.5G → ADR-004 自动止损
（防线对、探针错；logs/A24DDCOFF-20261005/READINGS.md §九/OPEN-4）。
本件=工具树统一护栏，规约件 docs/governance/BIGFILE-READ-PROBE-SPEC-20261006.md：

  - capped_json_load(path)：本地 JSON 整读唯一入口。>50MB → BigFileError
    （fail-closed，指向流式路径）；≤50MB 才整读。
  - iter_chunks / stream_count：分块流式迭代与字段抽样范式（O(1) 内存）。
  - rss_mb()：自省峰值 RSS（自检用，Linux ru_maxrss 单位 KB）。
  - selftest()：离线构造 >50MB 合成 trace → ①整读被拒且理由正确 ②流式扫描计数
    精确且峰值 RSS 增量 <50MB（整读必超）③小件正常读。

用法:
  python3 tools/bigread.py --selftest
"""
from __future__ import annotations

import argparse
import json
import os
import resource
import sys

BIG_FILE_BYTES = 50 * 1024 * 1024  # 规约阈值：>50MB 必流式


class BigFileError(RuntimeError):
    """超限整读拒绝（fail-closed）。"""


def capped_json_load(path: str, cap_bytes: int = BIG_FILE_BYTES, label: str = ""):
    """带 size 预检的本地 JSON 读入：>cap 拒绝（指路流式），≤cap 才整读。"""
    size = os.path.getsize(path)
    if size > cap_bytes:
        raise BigFileError(
            f"{label or path}: {size} bytes > 预检上限 {cap_bytes}（>50MB 必流式）——"
            f"禁整读；trace/census 原始件走 tools/census_stream.py 状态机，"
            f"字段抽样用 bigread.iter_chunks/stream_count")
    with open(path, "rb") as fh:
        return json.loads(fh.read())


def iter_chunks(path: str, chunk_bytes: int = 1 << 20):
    """分块流式读（字节块迭代，常量内存）。"""
    with open(path, "rb") as fh:
        while True:
            blk = fh.read(chunk_bytes)
            if not blk:
                return
            yield blk


def stream_count(path: str, token: bytes, chunk_bytes: int = 1 << 20) -> int:
    """字段抽样范式：分块扫描计数 token 出现次数（跨块边界拼接，O(1) 内存）。"""
    n, tail = 0, b""
    keep = max(1, len(token) - 1)
    for blk in iter_chunks(path, chunk_bytes):
        buf = tail + blk
        n += buf.count(token)
        tail = buf[-keep:]
    return n


def rss_mb() -> float:
    """进程峰值 RSS（MiB）。ru_maxrss 在 Linux 为 KB。"""
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024.0


def _make_synth_trace(path: str, target_mb: int = 60) -> int:
    """构造 >50MB 合成 trace（pretty JSON 行式，埋固定次数魔码）。"""
    magic = b'"ph": "synthetic_magic_20261006"'
    line = (b'{"ph": "kernel", "cat": "kernel", "name": "synth_fill_kernel_v1", '
            b'"ts": 123456789, "dur": 12, "args": {"stream": 7}}\n')
    magic_line = (b'{"ph": "synthetic_magic_20261006", "cat": "marker", '
                  b'"name": "marker_row", "ts": 1, "dur": 1}\n')
    planted = 0
    size = 0
    target = target_mb * 1024 * 1024
    with open(path, "wb") as fh:
        fh.write(b'{"traceEvents": [\n')
        size += 17
        while size < target:
            if planted < 7 and size > (planted + 1) * target // 8:
                fh.write(magic_line)
                planted += 1
            else:
                fh.write(line)
            size += len(line)
        fh.write(b']}\n')
    return planted


def selftest() -> int:
    """离线三断言：拒得对、流得平、小件可读。零网络零引擎。"""
    import tempfile
    ok = True

    def need(cond, why):
        nonlocal ok
        print(("PASS" if cond else "FAIL"), why)
        ok = ok and cond

    td = tempfile.mkdtemp(prefix="bigread-selftest-")
    try:
        big = os.path.join(td, "synth_trace.json")
        planted = _make_synth_trace(big, target_mb=60)
        size = os.path.getsize(big)
        need(size > BIG_FILE_BYTES, f"合成 trace {size // 1024 // 1024}MB > 50MB 阈值")
        # ① 整读必须拒，且理由正确（>50MB 必流式）
        try:
            capped_json_load(big, label="synth")
            need(False, "超限整读必须红")
        except BigFileError as e:
            need("必流式" in str(e) and str(size) in str(e),
                 f"超限整读拒且理由正确（{str(e)[:60]}…）")
        # ② 流式扫描：计数精确 + 峰值 RSS 增量 <50MB（60MB 文件若整读必超）
        rss0 = rss_mb()
        got = stream_count(big, b'"ph": "synthetic_magic_20261006"')
        rss1 = rss_mb()
        need(got == planted, f"流式计数精确（{got}/{planted}）")
        need(rss1 - rss0 < 50.0, f"流式峰值 RSS 增量 {rss1 - rss0:.1f}MiB < 50MiB"
                                 f"（60MB 文件整读必超=判别力）")
        # ③ 小件正常读
        small = os.path.join(td, "small.json")
        with open(small, "w") as fh:
            json.dump({"steps": 750, "ok": True}, fh)
        d = capped_json_load(small, label="small")
        need(d.get("steps") == 750, "≤50MB 小件正常整读")
    finally:
        for f in os.listdir(td):
            os.unlink(os.path.join(td, f))
        os.rmdir(td)
    print("SELFTEST", "PASS" if ok else "FAIL")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
