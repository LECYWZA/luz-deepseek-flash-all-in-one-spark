#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""refcheck.py — 「引用登记」的核验量具（文档 ←→ 事实源 的闭合检查）

═══ 为什么存在 ═══════════════════════════════════════════════════════════════
2026-09-23 QA 收尾轮实测：`ADR-004` / `WINDOW-RUNBOOK` / `REFERENCE.md` /
`GLOSSARY.md` 里指向 `guards.conf` 等文件的**行号引用有 23 处系统性过期**
（+5 / +14 / +24 漂移）。根因不是"登记员抄错了"，而是**登记动作完成之后，
目标文件又被改了** —— 两轮代理分别写文档（01:06–01:21）与补注释（01:31），
后者的行号位移让前者的全部行号引用同时失效。

逐条修一遍 = 下次再漂。所以这里把这四类引用做成**可重复执行的量具**：

  ① PATH   路径存在性      —— `~/x/y.sh` / `/opt/...` / `dir/f.py` 能否解析到
  ② LINE   行号在范围内    —— `path:NNN` / `path:NNN-MMM`，1 ≤ N ≤ 行数
  ③ ANCHOR 章节锚点存在    —— `WINDOW-RUNBOOK §7.5` 目标文档真有该标题
  ④ MD5    哈希与文件相符  —— 同行内"路径 + 哈希"配对（32/64 位或其 12-16 位前缀）
  ⑤ STALE  **引用已失效信号** —— 目标文件 mtime 晚于文档 mtime
                              （④⑤ 是"漂移"这一类病的特异指标；①②③ 是结构病）

═══ 判据纪律 ═════════════════════════════════════════════════════════════════
* **⑤ 不是 FAIL 而是 WARN**：目标文件比文档新**不代表**引用一定错了（可能改的是
  别处）。它是一条"必须人工复看的清单"——把 25 处隐性问题收敛成一份可审列表，
  这就是它在 QA 报告里抓出 93% 落空率的同一信号。
* **白名单必须显式且带理由**：`refcheck.allow` 每行 `<glob>|<理由>`。没有理由的
  白名单就是静默放过（本项目 ⑥ 号病：空真 ⇒ ALL-OK）。缺理由 ⇒ 量具自己报错。
* **⑤ 的不对称必须知道**：STALE 比较的是"目标比文档新"。于是一份**刚被编辑过的文档**
  反而是最"安全"的——它的 mtime 最新，指向任何文件都不会报 STALE，**包括那些行号真的错了的
  引用**（2026-09-23 实测：`guard/BASELINE.md:352` 里的 `guards.conf:97`、`guard/README.md:57`
  两条早已失效，只因为 BASELINE.md 当天被改过而从未出现在 STALE 清单里）。工具**看不见**这类；
  真正的兜底是"行号一律换行名锚点"（见 `guards.conf` 里那张 old→new 位移对照表的注释）。
* **自检先于实跑**：`--selftest` 用合成夹具把五类全部制造一遍，**每一类都必须
  被抓住**；抓不住就 exit≠0。夹具全绿而真产物全红，才说明量具在工作。

用法：
  python3 refcheck.py --selftest              # 合成自检（必须五类全抓）
  python3 refcheck.py                         # 默认核验 kit 文档集
  python3 refcheck.py --only STALE --json     # 只看某类 / 机器可读
退出码：0 = 无 FAIL（WARN 允许）；1 = 有 FAIL 或自检失败。
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import sys
import time
from typing import Iterable

# ── 常量：默认核验面 ────────────────────────────────────────────────────────
KIT = os.path.expanduser("~/w6-kit")
REPO = os.path.expanduser("~/dsv41-flash-dgxsparks")
DEFAULT_DOCS = [
    f"{KIT}/README.md",
    f"{KIT}/WINDOW-RUNBOOK.md",
    f"{KIT}/REFERENCE.md",
    f"{KIT}/GLOSSARY.md",
    f"{KIT}/adr/ADR-004-three-gib-floor-guard.md",
    f"{KIT}/guard/README.md",
    f"{KIT}/guard/BASELINE.md",
    f"{KIT}/oom-gate/README.md",
]
DEFAULT_ROOTS = [KIT, REPO, os.path.expanduser("~")]

# ── 排除规则 ────────────────────────────────────────────────────────────────
# 容器内路径 / URL / 远端主机路径：不是宿主事实源，解析不到属正常
CONTAINER_PREFIX = ("/opt/dsv41/", "/sgl-workspace/", "/usr/", "/etc/", "/var/",
                    "/opt/nvidia/", "/root/.", "/dev/", "/proc/", "/sys/", "/state/")
URL_RE = re.compile(r"https?://|git@|github\.com")
# vendored 上游树：第三方代码，行号会随上游漂移，本册不对其登记
VENDORED = ("fi-src/", "fi016-src/", "fi-main/", "fi18-wheels/", "cutlass", "cccl/")

# 一个"路径 token"：必须有已知扩展名，后可选行号（:N / :N-M / #LN）
EXTS = ("md", "sh", "py", "conf", "json", "txt", "service", "timer", "log",
        "csv", "tsv", "tar", "zst", "example", "cuh", "so", "whl", "yaml", "yml",
        "gz", "xz", "bz2", "jsonl")
# ⚠ 交替按**长度降序**排：`json` 排在 `jsonl` 前面时 `x.jsonl` 会被截成 `x.json`
#   （正则交替是"先匹配者胜"，不是"最长者胜"）。这类 bug 只有把 `jsonl` 写进自检
#   夹具才抓得住 —— 所以自检里必须有一个**多级扩展名**样本。
_EXTS_ORD = "|".join(sorted(EXTS, key=len, reverse=True))
PATH_RE = re.compile(
    r"(?<![\w/.-])((?:~|\.{0,2}/)?[\w./~-]*[\w-]+\.(?:" + _EXTS_ORD + r"))"
    r"(?::(\d+)(?:-(\d+))?|#L(\d+))?"
)
# 省略号/通配：`…/OUT-OF-BOX-DEPLOY.md`、`sglang-overlay*/deepseek_v4_backend.py`、
# `b12x/**/__init__.py` 都是**尾段简写**——写的是"某个交付目录下的这个文件"，
# 不是可解析路径。硬查必然假红，且这类写法在册里到处都是（REFERENCE 尤其多）。
# 判据：token 内含 `*`/省略号，或紧前一个字符是它们 ⇒ 不是路径引用，跳过并计数。
ELISION_RE = re.compile(r"[*…{}]|\.\.\.")
SKIP_PREFIX = ("/tmp/",)          # 瞬态：证据临时件，清掉即消失，不是"登记错误"
HEX_RE = re.compile(r"(?<![\w:])([0-9a-f]{12,64})(?![\w])")
# 同行出现这些标记 ⇒ 该 hex 是「镜像内容身份/摘要」而非「文件 md5」，④ 必须放过
IDENT_MARKERS = ("内容身份", "content_id", "content-id", "镜像身份", "镜像 ID",
                 "manifest", "sha256:", "digest", "层身份")
ANCHOR_RE = re.compile(r"§\s*(\d+(?:\.\d+)*)")
HEAD_RE = re.compile(r"^#{1,6}\s*§?\s*(\d+(?:\.\d+)*)")
HEAD_ANY_RE = re.compile(r"^#{1,6}\s+(.*)$")
# 目录引用（QA-B 抓到的那类真缺陷：`~/w6-kit/w9-evidence/w9r4/` 不存在）
# —— 必须独立成一条规则：它没有扩展名，PATH_RE 看不见它（"正则只认自家格式"那类病）
DIR_RE = re.compile(r"(?<![\w/])((?:~|/)[\w./-]*?/)(?=[\s，。、）)：:；;」』\"'`|>\]）]|$)")

ALLOW_FILE = f"{KIT}/refcheck.allow"

# systemd **单元名**不是文件路径：`dsv41-serve.service` / `guard-check.timer` 描述的是
# 注册单元，其存在性由 guards.conf 自己的 kind 列负责断言（`GUARD|...|unit`）。
# 把它们当路径查 ⇒ 110 条恒假 FAIL ⇒ 闸门被无视。故显式豁免（这是量具的判据统计，
# 不是"放过"：单元的真实性在 guards.conf 的 verify-governance 里另有硬断言）。
UNIT_RE = re.compile(r"^[\w@.-]+\.(?:service|timer|socket|target|mount)$")


def is_container_path(p: str) -> bool:
    return any(p.startswith(x) for x in CONTAINER_PREFIX)


def is_vendored(p: str) -> bool:
    return any(v in p for v in VENDORED)


HIST_MD5_MARK = "refcheck:historical-md5"


def hist_md5_lines(text: list[str]) -> set[int]:
    """解析「本表是历史记录」的声明，返回受声明覆盖的行号集合。

    为什么需要它：变更台账（如 `guard/BASELINE.md`）里的 md5 是**当时的快照**——事后再改
    文件，台账里的数字当然不再等于现值。拿现值去判它是**判据用错**，不是缺陷；但反过来
    无条件放过又会让"台账里写错一个哈希"永远看不见。所以让**文档自己声明**语义：

        <!-- refcheck:historical-md5 -->
        | 文件 | md5 旧 | md5 新 | 变更 |

    两种粒度：
      · `<!-- refcheck:historical-md5 -->`        —— 紧随其后的**第一张表**；
      · `<!-- refcheck:historical-md5:file -->`   —— **全篇**（用于整篇都是台账的文档，
        如 `guard/BASELINE.md`："通篇历史"才是对该文件的真实陈述，逐表插标记只是热闹）。
    没有声明的表里写错哈希仍然 FAIL —— 声明是载荷，不是消音器（自检里两条对照断言
    就是钉这个：同内容加声明 ⇒ 只 WARN，去声明 ⇒ FAIL）。
    """
    lines: set[int] = set()
    n = len(text)
    if any(HIST_MD5_MARK + ":file" in ln for ln in text[:8]):
        return set(range(1, n + 2))          # 全篇声明（只看文首 8 行，避免被正文提及误触发）
    for i, raw in enumerate(text):
        if HIST_MD5_MARK not in raw:
            continue
        j = i + 1
        while j < n and not text[j].lstrip().startswith("|"):
            if text[j].strip() and not text[j].lstrip().startswith("#"):
                break          # 撞到正文/标题 ⇒ 后面没有紧邻的表，声明落空
            j += 1
        while j < n and text[j].lstrip().startswith("|"):
            lines.add(j + 1)
            j += 1
    return lines


def load_allow() -> list[tuple[str, str]]:
    """白名单：<glob>|<理由>。缺理由 ⇒ 立刻 die（不许静默放过）。"""
    out = []
    if not os.path.exists(ALLOW_FILE):
        return out
    for i, ln in enumerate(open(ALLOW_FILE, encoding="utf-8"), 1):
        ln = ln.strip()
        if not ln or ln.startswith("#"):
            continue
        if "|" not in ln:
            die(f"{ALLOW_FILE}:{i} 白名单行缺「|理由」：{ln}")
        g, why = ln.split("|", 1)
        if not why.strip():
            die(f"{ALLOW_FILE}:{i} 白名单理由为空：{ln}")
        out.append((g.strip(), why.strip()))
    return out


def allowed(tok: str, allow: list[tuple[str, str]]) -> str | None:
    for g, why in allow:
        if fnmatch.fnmatch(tok, g) or tok == g:
            return why
    return None


def inline_target(raw: str, anchor_pos: int, docdir: str, roots: list[str],
                  gap: int = 40) -> str | None:
    """锚点**行内点名**的目标文档：`§` 之前 `gap` 字符内最近的一个文档名。

    这是 FAIL 的门槛。判据理由：本册大量散文引用写作"事故报告 §6.4 F1/G1-G4"或
    "CED 优化报告 §1.3"——**没有点名文档名**。这种引用无法机械归属（谁都能是它的
    目标），对它判 FAIL 等于产出无法复核的判决（本项目"工具异常⇒走假"那类病）。
    只有"`OUT-OF-BOX-DEPLOY.md` §7.1"这种**行内点死**的，才当作可判定的登记。

    ⚠ 排序必须按**距离**，且 `.md` 全名优于裸词干。首版先收集全名再无条件用词干
    循环覆写，于是 `` `oom-gate/README.md` §10.2 `` 被判去 `guard/README.md`（那里
    没有 §10.2）⇒ 3 条真·正确引用被误判成 FAIL。**判据错会毁掉正确的内容**，
    这比漏判严重，所以距离优先、同类才比优先级。
    """
    cands: list[tuple[int, int, str]] = []      # (距离, 优先级, 路径)

    def push(end_pos: int, prio: int, p: str | None):
        d = anchor_pos - end_pos
        if p and 0 <= d <= gap:
            cands.append((d, prio, p))

    for m in MDNAME_RE.finditer(raw[:anchor_pos]):
        if ELISION_RE.search(m.group(1)):
            continue
        push(m.end(), 0, resolve(m.group(1), docdir, roots))
    for st in STEMS:
        for m in re.finditer(r"(?<![\w-])" + re.escape(st) + r"(?![\w-])", raw[:anchor_pos]):
            for c in (os.path.join(docdir, st + ".md"), f"{KIT}/{st}.md",
                      f"{KIT}/guard/{st}.md"):
                if os.path.exists(c):
                    push(m.end(), 1, os.path.realpath(c))
                    break
    if not cands:
        return None
    return min(cands)[2]


def die(msg: str) -> None:
    print(f"refcheck: {msg}", file=sys.stderr)
    sys.exit(2)


# ── 锚点归属：`§7` 到底指哪份文档 ───────────────────────────────────────────
# 三级（按可信度降序），并**回报用的是哪一级**（判据必须可审计，不能黑箱）：
#   same-line  同行就点名的 .md（最可信）
#   window     ±2 行窗口内点名的 .md（本册大量"续行描述上一行的文档分节"的写法）
#   self       都没点名 ⇒ 视为本文档自身
#   None       **无法归属**：不猜，跳过并计数（宁可不判，也不产出无法复核的判决）
# ⚠ 名字里的 `~` 必须进字符类：首版写 `[\w./-]*\.md`，于是 `~/w6-kit/X.md` 被截成
#   `/w6-kit/X.md` —— 带前导 `/` 即被当**绝对路径**，恒解析失败 ⇒ 60 条锚点假红。
MDNAME_RE = re.compile(r"([~\w][\w./-]*\.md)")
# 不带 .md 的引用（`README §8`、`WINDOW-RUNBOOK §7.5`）——本册最常见的引用写法
STEMS = ("WINDOW-RUNBOOK", "REFERENCE", "GLOSSARY", "BASELINE", "README", "ADR-004")
HEAD_CACHE: dict[str, set[str]] = {}


def headings_of(p: str) -> set[str]:
    if p not in HEAD_CACHE:
        hs = set()
        for l in open(p, encoding="utf-8", errors="replace").read().splitlines():
            m = HEAD_RE.match(l)
            if m:
                hs.add(m.group(1))
        HEAD_CACHE[p] = hs
    return HEAD_CACHE[p]


def attribute_target(text: list[str], ln_no: int, doc: str, docdir: str,
                     roots: list[str]) -> list[tuple[str, str]]:
    """给出**有序候选**目标（可信度降序），由调用方按"谁能满足全部锚点"挑。

    为什么是候选而不是单选：一行引两份文档是常态（`WINDOW-RUNBOOK.md:84` 同时引
    `DELIVERABLE-CHECKLIST §3.4` 与 `OUT-OF-BOX-DEPLOY §7.3`）。首版按"同行第一个
    .md"单选 ⇒ 第二个锚点必然对错文档求值 ⇒ 假红。

    候选层级：① 同行点名的 .md ② 同行**裸词干**（`README §8` 这种不带扩展名的
    引用极其常见）③ ±2 行窗口内点名的 .md ④ 本文档自身。
    """
    cands: list[tuple[str, str]] = []

    def add(p, tag):
        if p and all(p != q for q, _ in cands):
            cands.append((p, tag))

    raw = text[ln_no - 1]
    for nm in MDNAME_RE.findall(raw):
        if not ELISION_RE.search(nm):
            add(resolve(nm, docdir, roots), "same-line")
    for st in STEMS:
        if re.search(r"(?<![\w-])" + re.escape(st) + r"(?![\w-])", raw):
            # **不要 break**：`docdir/README.md` 可能就是本文档，而引用其实指
            # `guard/README.md`。全部列出，让 best-match 按"谁能解释全部锚点"挑。
            for c in (os.path.join(docdir, st + ".md"), f"{KIT}/{st}.md",
                      f"{KIT}/guard/{st}.md"):
                if os.path.exists(c):
                    add(os.path.realpath(c), f"same-line:{st}")
    lo, hi = max(0, ln_no - 3), min(len(text), ln_no + 2)
    for i2, l2 in enumerate(text[lo:hi], start=lo + 1):
        if i2 == ln_no:
            continue
        for nm in MDNAME_RE.findall(l2):
            if not ELISION_RE.search(nm):
                add(resolve(nm, docdir, roots), f"window(L{i2})")
    add(doc, "self")
    return cands


# ── 解析：把一个路径 token 解析成宿主上的真实文件 ───────────────────────────
# 裸文件名（`guards.conf` / `gen_probe.sh` / `concurrency_proxy_v2.py`）在本册里是
# **简写**——文档默认读者知道它在 kit 或仓库里。所以除"文档同目录/根目录"外，还要
# 能按 basename 在搜索面里找到它；否则 199 条简写会全部变假 FAIL。
# 索引只建一次（KIT 全树 + REPO 全树，排除 .git/__pycache__），有总量上限。
_INDEX: dict[str, list[str]] = {}
_INDEX_BUILT: set[tuple] = set()
INDEX_CAP = 400_000
# 索引遍历面 = 整个 HOME（实测 10.0 万文件 / 0.29s ⇒ 便宜到没必要让文档迁就量具）。
# 剪掉的都是"绝不会被引用成事实源"的重型/机器生成树。
SKIP_DIRS = {".git", "__pycache__", "node_modules", ".venv", "site-packages",
             "NewModels", ".zcode", ".cache", ".local", ".npm", ".rustup", ".cargo",
             ".oh-my-zsh", ".vscode-server", ".cursor-server", ".nvidia", ".triton",
             ".nv", ".conda", "state-tp4", "w6-logs", ".mimosa", ".claude"}


def build_index(roots: list[str]) -> None:
    key = tuple(sorted(roots))
    if key in _INDEX_BUILT:
        return
    _INDEX_BUILT.add(key)
    n = 0
    for r in roots:
        if not os.path.isdir(r):
            continue
        for dp, dn, fn in os.walk(r):
            dn[:] = [d for d in dn if d not in SKIP_DIRS]
            for f in fn:
                _INDEX.setdefault(f, []).append(os.path.join(dp, f))
                n += 1
                if n > INDEX_CAP:
                    return


def resolve(tok: str, docdir: str, roots: Iterable[str]) -> str | None:
    if tok.startswith("~"):
        p = os.path.expanduser(tok)
        return p if os.path.exists(p) else None
    cands = []
    if tok.startswith("/"):
        cands.append(tok)
    else:
        cands.append(os.path.join(docdir, tok))          # 文档同目录相对
        for r in roots:
            cands.append(os.path.join(r, tok))            # 根目录相对
    for c in cands:
        if os.path.exists(c):
            return os.path.realpath(c)
    # basename 兜底：简写引用（仅对非绝对路径生效 —— 绝对路径写错了就是写错了）
    if not tok.startswith("/"):
        hits = _INDEX.get(os.path.basename(tok))
        if hits:
            return os.path.realpath(hits[0])
    return None


def check_doc(doc: str, roots: list[str], allow: list[tuple[str, str]],
              kinds: set[str]) -> tuple[list[dict], dict]:
    """核验一份文档。返回 (findings, stats)。"""
    findings: list[dict] = []
    stats = {"refs": 0, "paths": 0, "lines": 0, "anchors": 0, "md5": 0, "allow": 0,
             "units": 0, "dirs": 0, "md5_ambig": 0, "elided": 0, "transient": 0,
             "path_weak": 0, "anchor_unattributed": 0, "md5_hist": 0}
    if not os.path.exists(doc):
        findings.append({"kind": "PATH", "sev": "FAIL", "doc": doc, "line": 0,
                         "tok": doc, "msg": "被核验的文档本身不存在"})
        return findings, stats
    doc_mtime = os.path.getmtime(doc)
    docdir = os.path.dirname(doc)
    text = open(doc, encoding="utf-8", errors="replace").read().splitlines()
    hist = hist_md5_lines(text)      # 文档自己声明为"历史记录"的表（见该函数注）

    for ln_no, raw in enumerate(text, 1):
        if URL_RE.search(raw):
            # 整行含 URL ⇒ 其中的路径片段多半是外站路径，跳过（避免假红）
            pass
        # ① ② 路径与行号
        for m in PATH_RE.finditer(raw):
            tok, a, b, h = m.group(1), m.group(2), m.group(3), m.group(4)
            if URL_RE.search(raw[max(0, m.start() - 20):m.end() + 20]):
                continue
            if ELISION_RE.search(tok) or (m.start() > 0 and raw[m.start() - 1] in "*…{}"):
                stats["elided"] += 1
                continue
            if tok.startswith(SKIP_PREFIX):
                stats["transient"] += 1
                continue
            if is_vendored(tok):
                continue
            if UNIT_RE.match(tok):          # systemd 单元名，不是路径（见 UNIT_RE 注）
                stats["units"] += 1
                continue
            stats["refs"] += 1
            wl = allowed(tok, allow)
            real = resolve(tok, docdir, roots)
            if real is None:
                if is_container_path(tok):
                    continue
                if wl:
                    stats["allow"] += 1
                    continue
                # 弱悬空：写的位置没有，但 basename 在搜索面里存在 ⇒ 多半是镜像内路径
                # 或"尾段简写"。它与"真悬空"（basename 也查无此物）是两种病，混在一
                # 起报会让真信号淹掉 —— 所以分档，且只有真悬空判 FAIL。
                weakb = _INDEX.get(os.path.basename(tok)) if tok.startswith(("/", "~")) else None
                if weakb:
                    stats["path_weak"] += 1
                    findings.append({"kind": "PATH-WEAK", "sev": "WARN", "doc": doc,
                                     "line": ln_no, "tok": tok,
                                     "msg": f"按写法解析不到，但同名文件在 {weakb[0]}（"
                                            f"共 {len(weakb)} 处）⇒ 疑似镜像内/尾段简写，需人工定性",
                                     "src": raw.strip()[:150]})
                    continue
                findings.append({"kind": "PATH", "sev": "FAIL", "doc": doc, "line": ln_no,
                                 "tok": tok, "msg": "路径解析不到（写处与 basename 兜底均无）",
                                 "src": raw.strip()[:150]})
                continue
            stats["paths"] += 1
            line_no = int(a or h) if (a or h) else None
            if line_no is None:
                continue
            end_no = int(b) if b else line_no
            n = sum(1 for _ in open(real, "rb"))
            if not (1 <= line_no <= n) or not (1 <= end_no <= n):
                findings.append({"kind": "LINE", "sev": "FAIL", "doc": doc, "line": ln_no,
                                 "tok": f"{tok}:{line_no}{'-' + b if b else ''}",
                                 "msg": f"行号越界（目标共 {n} 行）", "src": raw.strip()[:150]})
                continue
            stats["lines"] += 1
            # ⑤ 漂移信号：目标文件在文档之后被改过
            if "STALE" in kinds and os.path.getmtime(real) > doc_mtime + 1:
                dt = os.path.getmtime(real) - doc_mtime
                findings.append({"kind": "STALE", "sev": "WARN", "doc": doc, "line": ln_no,
                                 "tok": f"{tok}:{line_no}", "real": real, "tgt": line_no,
                                 "msg": f"目标比文档新 {dt:.0f}s ⇒ 行号可能已位移（复看该行内容）",
                                 "src": raw.strip()[:150]})
                stats["refs"] -= 0
        # ③ 章节锚点
        if "ANCHOR" in kinds:
            for am in ANCHOR_RE.finditer(raw):
                a = am.group(1)
                if a.startswith("0"):
                    continue
                stats["anchors"] += 1
                tgt = inline_target(raw, am.start(), docdir, roots)
                if tgt:
                    hs = headings_of(tgt)
                    if a not in hs:
                        order = sorted(hs, key=lambda x: [int(y) for y in x.split(".")])
                        findings.append({"kind": "ANCHOR", "sev": "FAIL", "doc": doc,
                                         "line": ln_no,
                                         "tok": f"§{a} → {os.path.basename(tgt)}",
                                         "msg": f"行内点名了 {os.path.basename(tgt)} 但无该章节"
                                                f"（实有 {order[:16]}）",
                                         "src": raw.strip()[:150]})
                    continue
                cands = attribute_target(text, ln_no, doc, docdir, roots)
                if any(a in headings_of(cp) for cp, _ in cands
                       if not (cp == doc and not headings_of(cp))):
                    continue
                stats["anchor_unattributed"] += 1
                findings.append({"kind": "ANCHOR-PROSE", "sev": "WARN", "doc": doc,
                                 "line": ln_no, "tok": f"§{a}（未点名文档）",
                                 "msg": "散文引用、无法机械归属 ⇒ 需人工确认目标文档"
                                        f"（候选 " + "、".join(os.path.basename(q) for q, _ in cands[:3]) + "）",
                                 "src": raw.strip()[:150]})
        # ④ 哈希配对 —— **只在该行恰好「一个路径 + 一个 hex」时判定**。
        # 首版用"第一个可解析路径"，结果把 `guards.conf` 与紧邻的
        # `concurrency_proxy_v2.py` 的 md5 配了对 ⇒ 2 条假 FAIL。配对歧义时
        # 宁可记账跳过，也不产出无法复核的判决。
        if "MD5" in kinds and not any(k in raw for k in IDENT_MARKERS):
            hexes = [(x.group(1), x.start()) for x in HEX_RE.finditer(raw)
                     if len(x.group(1)) in (12, 16, 32, 64)]
            pms = [(m2.group(1), m2.start(), m2.end()) for m2 in PATH_RE.finditer(raw)
                   if not UNIT_RE.match(m2.group(1)) and not is_vendored(m2.group(1))
                   and not ELISION_RE.search(m2.group(1))]
            resolvable = [(p, resolve(p, docdir, roots), e, st)
                          for p, st, e in pms]
            # `（见 guards.conf）` 这类是**指针**：它只说"去哪查"，其后列的哈希属于
            # 别的东西（该 unit 的脚本）。指针行不参与配对 —— 否则台账快照表的每一行
            # 都会拿 guards.conf 的 md5 去比别人的值（3 条恒假 FAIL）。
            resolvable = [(p, r, e, st) for p, r, e, st in resolvable
                          if r and "见 " not in raw[max(0, st - 6):st]]
            # **邻接约束**：hex 必须紧跟在路径 token 之后（≤40 字符）。
            # 没有它，表格行（`| vllm-logdump.service | ... | 3d3793d0244a |`）与
            # "（= `guards.conf:31` 的钉版，权威值 = `d9aeaab640f7`）"这类句子会把
            # 路径与**别处**的哈希配成对 ⇒ 假红。
            pair = None
            if len(resolvable) == 1 and len(hexes) == 1:
                h, hp = hexes[0]
                p, real, pend, _ = resolvable[0]
                if 0 <= hp - pend <= 40:
                    pair = (h, real, p)
            if pair:
                h, real, p = pair
                if len(h) == 64:
                    want = hashlib.sha256(open(real, "rb").read()).hexdigest()
                else:
                    want = hashlib.md5(open(real, "rb").read()).hexdigest()
                stats["md5"] += 1
                if not want.startswith(h):
                    if ln_no in hist:
                        # 该表已被文档显式声明为历史记录（如变更台账）⇒ 这里的数字本来就是
                        # "当时的值"，拿现值去判它是**判据用错**，不是缺陷。降为 WARN 并说明，
                        # 但它仍然出现在复看清单里（不许静默）。
                        stats["md5_hist"] = stats.get("md5_hist", 0) + 1
                        findings.append({"kind": "MD5-HIST", "sev": "WARN", "doc": doc,
                                         "line": ln_no, "tok": f"{p} {h}",
                                         "msg": f"历史值（该表已声明为变更记录；现值见 "
                                                f"guard/MD5SUMS。实测现今 {want[:len(h)]}）",
                                         "src": raw.strip()[:150]})
                    else:
                        findings.append({"kind": "MD5", "sev": "FAIL", "doc": doc, "line": ln_no,
                                         "tok": f"{p} {h}",
                                         "msg": f"哈希不符（实测 {want[:len(h)]}）",
                                         "src": raw.strip()[:150]})
            elif hexes:
                stats["md5_ambig"] += 1
        # ③b 目录引用（无扩展名 ⇒ PATH_RE 看不见）
        for m2 in DIR_RE.finditer(raw):
            tok = m2.group(1)
            if is_vendored(tok) or is_container_path(tok) or URL_RE.search(raw):
                continue
            stats["dirs"] += 1
            p = os.path.expanduser(tok)
            if not os.path.isdir(p):
                wl = allowed(tok, allow)
                if wl:
                    stats["allow"] += 1
                    continue
                findings.append({"kind": "DIR", "sev": "FAIL", "doc": doc, "line": ln_no,
                                 "tok": tok, "msg": "目录不存在（真缺陷类：路径写错位置）",
                                 "src": raw.strip()[:150]})
    return findings, stats


# ── 合成自检：五类全部制造，每一类都必须被抓 ────────────────────────────────
def selftest(tmp: str) -> int:
    os.makedirs(tmp, exist_ok=True)
    tgt = os.path.join(tmp, "target.md")
    open(tgt, "w").write("# §1 A\n# §2 B\n# §7.5 fine\n")          # 3 行，有 §7.5
    good = os.path.join(tmp, "good.txt")
    open(good, "w").write("hello\n")                                # md5 5d41402abc4b2a76b9719d911017c592
    doc = os.path.join(tmp, "doc.md")
    open(doc, "w").write(
        f"clean: `{good}` md5 `5d41402abc4b2a76b9719d911017c592`\n"      # 全对
        f"plain-path: `{good}`\n"                     # 纯路径引用**不该**报 STALE
        f"line-ref: `{good}:1`\n"                     # ⑤ 这条要被抓
        f"anchor-ok: target.md §7.5\n"                                    # 对
        f"missing: `{tmp}/nope.md`\n"                                     # ① 路径不存在
        f"oob: `{good}:99`\n"                                             # ② 行号越界
        f"anchor-bad: target.md §3\n"                                     # ③ 无该章节
        f"hash-bad: `{good}` md5 `deadbeefdeadbeefdeadbeefdeadbeef`\n"    # ④ 哈希不符
        f"two-path-ambig: `{good}` 与 `{tgt}` md5 `deadbeefdeadbeefdeadbeefdeadbeef`\n"  # 配对歧义⇒跳过
        f"dir-bad: `{tmp}/nodir-xyz/`\n"                                 # ⑥a 目录不存在（真缺陷类）
        f"unit: dsv41-serve.service 与 guard-check.timer\n"              # ⑥b 单元名⇒豁免，不许报
        f"elided: `…/OUT-OF-BOX-DEPLOY.md:12` 与 `overlay*/f.py`\n"       # ⑥c 省略号/通配⇒豁免
        f"transient: `/tmp/v41_hostattr_a1.tsv:3`\n"                      # ⑥d /tmp 瞬态⇒豁免
        f"weak: `/nonexistent/deep/twin.py:1`\n"                          # ⑥e 弱悬空⇒WARN 非 FAIL
        f"unit-ok-end\n"
    )
    # ⑤ STALE：把目标改新
    time.sleep(1.1)
    open(good, "a").write("x\n")
    # 弱悬空夹具：造一个同名文件，然后引用一个**不存在的绝对路径**指向它
    sub = os.path.join(tmp, "sub")
    os.makedirs(sub, exist_ok=True)
    twin = os.path.join(sub, "twin.py")
    open(twin, "w").write("t\n")
    global _INDEX
    _INDEX = {"twin.py": [twin]}          # 夹具注入：模拟 HOME 索引里已有同名文件

    allow: list = []
    findings, _ = check_doc(doc, [tmp], allow, {"PATH", "LINE", "ANCHOR", "MD5", "STALE"})
    got = {}
    for f in findings:
        got.setdefault(f["kind"], 0)
        got[f["kind"]] += 1
    # 判据全绿时必须出现这些 kind（缺一即"该类病量具是聋的"）
    need = ["PATH", "LINE", "ANCHOR", "MD5", "STALE", "DIR", "PATH-WEAK"]
    bad = [k for k in need if not got.get(k)]
    print(f"  selftest 命中：{ {k: got.get(k, 0) for k in need} }")
    if bad:
        print(f"  \033[31m自检失败：{bad} 类未被抓住 ⇒ 量具对这类病是聋的\033[0m",
              file=sys.stderr)
        return 1
    # 判据必须**不**触发这些假阳性
    fp = [f for f in findings
          if (f["kind"] == "PATH" and UNIT_RE.match(f["tok"]))
          or (f["kind"] == "MD5" and "two-path-ambig" in f.get("src", ""))
          or (ELISION_RE.search(f["tok"]) and f["sev"] == "FAIL")
          or (f["sev"] == "FAIL" and f["tok"].startswith("/tmp/"))
          or (f["kind"] == "PATH" and f["tok"].endswith("twin.py"))]
    if fp:
        print(f"  \033[31m自检失败：假阳回归 {len(fp)} 条\033[0m", file=sys.stderr)
        for f in fp:
            print(f"    {f['kind']} {f['tok']} {f['msg']}", file=sys.stderr)
        return 1
    # 干净件不得报红（否则量具只会天天喊狼来了）
    clean = os.path.join(tmp, "clean.md")
    open(clean, "w").write(
        f"ok: `{good}`\n"
        f"md5-ok: `{good}` md5 `{hashlib.md5(open(good, 'rb').read()).hexdigest()}`\n"
        f"anchor-ok: target.md §7.5\n"
        f"dir-ok: `{tmp}/`\n"
        f"unit-ok: dsv41-head.service\n")
    f2, _ = check_doc(clean, [tmp], [], {"PATH", "LINE", "ANCHOR", "MD5", "STALE"})
    hard = [f for f in f2 if f["sev"] == "FAIL"]
    if hard:
        print(f"  \033[31m自检失败：干净夹具报了 {len(hard)} 条 FAIL（假阳性）\033[0m",
              file=sys.stderr)
        for f in hard:
            print(f"    {f['kind']} {f['tok']} {f['msg']}", file=sys.stderr)
        return 1
    # ⑧⑨ 历史表声明：**对照断言**。声明是"载荷"不是"消音器"——同一条错哈希，
    #      加声明只 WARN、去声明必须 FAIL。少了后一半，这个特性就是一条万能静音键。
    # ⚠ 夹具必须是**真文件**：第一版写的是 `| x.txt | … |`，而 x.txt 不存在 ⇒ 配对不成立、
    #   判定根本没跑 ⇒ "没报 FAIL"通过得毫无意义（本项目⑥号病：空真 ⇒ ALL-OK）。
    #   自检里那条 `md5_hist` 计数断言就是为此设的：生效必须**有痕迹**。
    hist_tgt = os.path.join(tmp, "hist-target.txt")
    open(hist_tgt, "w").write("h\n")
    row = f"| `{hist_tgt}` | （新增） | deadbeefdeadbeefdeadbeefdeadbeef | 变更 |\n"
    hdoc = os.path.join(tmp, "hist.md")
    open(hdoc, "w").write("<!-- refcheck:historical-md5 -->\n" + row)
    f3, s3 = check_doc(hdoc, [tmp], [], {"MD5"})
    if [f for f in f3 if f["kind"] == "MD5" and f["sev"] == "FAIL"]:
        print("  \033[31m自检失败：声明为历史记录的表仍报 MD5 FAIL\033[0m", file=sys.stderr)
        return 1
    if not s3.get("md5_hist"):
        print("  \033[31m自检失败：历史表声明生效得无声无息（既无 FAIL 也无 WARN）\033[0m",
              file=sys.stderr)
        return 1
    # `:file` 形式：标记写错一个字符就会静默退化（本类病的靶心），所以单独钉一条
    hfile = os.path.join(tmp, "hist-file.md")
    open(hfile, "w").write("<!-- refcheck:historical-md5:file -->\n\n" + row)
    f5, s5 = check_doc(hfile, [tmp], [], {"MD5"})
    if [f for f in f5 if f["kind"] == "MD5" and f["sev"] == "FAIL"] or not s5.get("md5_hist"):
        print("  \033[31m自检失败：`:file` 全篇声明未生效（标记形态变了却不报）\033[0m",
              file=sys.stderr)
        return 1
    hdoc2 = os.path.join(tmp, "hist-off.md")
    open(hdoc2, "w").write(row)          # 同一张表，**去掉声明**
    f4, _ = check_doc(hdoc2, [tmp], [], {"MD5"})
    if not [f for f in f4 if f["kind"] == "MD5" and f["sev"] == "FAIL"]:
        print("  \033[31m自检失败：没有声明的表写错哈希却不报 FAIL（声明成了万能静音键）\033[0m",
              file=sys.stderr)
        return 1
    print("  selftest 通过：七类全抓 + 单元名豁免 + 歧义配对跳过 + 干净夹具 0 假阳"
          " + 历史表声明（加声明⇒WARN／无声明⇒FAIL）")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--docs", nargs="*", default=None)
    ap.add_argument("--root", action="append", default=None)
    ap.add_argument("--only", default=None, help="只跑某类：PATH/LINE/ANCHOR/MD5/STALE")
    ap.add_argument("--only-stale", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--review", action="store_true",
                    help="WARN 逐条给出「文档行 vs 目标行」原文（配 --only STALE 用）")
    a = ap.parse_args()

    if a.selftest:
        # ⚠ 夹具**不能**建在 /tmp 下：`/tmp/` 是被 `SKIP_PREFIX` 豁免的瞬态前缀，
        #   夹具自己就会踩这条豁免 ⇒ 五类全哑、自检却"通过"。第一版正是如此。
        import shutil
        t = os.path.expanduser("~/.cache/refcheck-selftest")
        shutil.rmtree(t, ignore_errors=True)
        try:
            return selftest(t)
        finally:
            shutil.rmtree(t, ignore_errors=True)

    kinds = {"PATH", "LINE", "ANCHOR", "MD5", "STALE"}
    if a.only:
        kinds = {k.strip().upper() for k in a.only.split(",")}
    if a.only_stale:
        kinds = {"STALE"}

    docs = a.docs or DEFAULT_DOCS
    roots = a.root or DEFAULT_ROOTS
    allow = load_allow()
    build_index([os.path.expanduser("~")])

    all_f: list[dict] = []
    tot = {"refs": 0, "paths": 0, "lines": 0, "anchors": 0, "md5": 0, "allow": 0,
           "units": 0, "dirs": 0, "md5_ambig": 0, "elided": 0, "transient": 0,
           "path_weak": 0, "anchor_unattributed": 0, "md5_hist": 0, "docs": 0}
    for d in docs:
        f, s = check_doc(os.path.expanduser(d), roots, allow, kinds)
        all_f += f
        tot["docs"] += 1
        for k in ("refs", "paths", "lines", "anchors", "md5", "allow", "units", "dirs",
                  "md5_ambig", "elided", "transient", "path_weak",
                  "anchor_unattributed", "md5_hist"):
            tot[k] += s[k]

    fails = [f for f in all_f if f["sev"] == "FAIL"]
    warns = [f for f in all_f if f["sev"] == "WARN"]
    by = {}
    for f in all_f:
        by[f["kind"]] = by.get(f["kind"], 0) + 1

    if a.review:
        # STALE 的判据是"目标文件在文档之后被改过"——这是**信号**而不是判决（可能改的是别处）。
        # 要让人能在 30 秒内复看一条，就必须把两侧原文并排给出：只报坐标的清单没人会看第二遍，
        # 而一份不被复看的 WARN 清单等于没有。
        def _line(path: str, n: int) -> str:
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    for i, ln in enumerate(fh, 1):
                        if i == n:
                            return ln.strip()[:170]
            except OSError as e:
                return f"<读不到：{e}>"
            return "<该行不存在>"
        print("\n\033[36m══ 复看视图（WARN 逐条：文档行 vs 目标行）══\033[0m")
        for f in warns:
            real, tgt = f.get("real"), f.get("tgt")
            print(f"\n[{f['kind']}] {f['doc']}:{f['line']}  →  {f['tok']}")
            print(f"   文档 │ {_line(f['doc'], f['line'])}")
            if real and tgt:
                print(f"   目标 │ {os.path.basename(real)}:{tgt}  {_line(real, tgt)}")
            elif f['kind'] == 'PATH-WEAK':
                print(f"   说明 │ {f['msg']}")

    if a.json:
        print(json.dumps({"totals": tot, "by_kind": by,
                          "fail": len(fails), "warn": len(warns),
                          "findings": all_f}, ensure_ascii=False, indent=1))
    else:
        for f in fails:
            print(f"\033[31mFAIL {f['kind']}\033[0m {f['doc']}:{f['line']}  {f['tok']}\n       {f['msg']}")
        if warns:
            tiers = {}
            for f in warns:
                tiers.setdefault(f["kind"], []).append(f)
            for k, ws in sorted(tiers.items()):
                print(f"\n\033[33m{k} {len(ws)} 条（WARN，非 FAIL —— 见工具头部判据）\033[0m")
                for f in ws[:200]:
                    print(f"  {f['doc'].split('/')[-1]}:{f['line']}  {f['tok']}")
                    if k == "PATH-WEAK":
                        print(f"        {f['msg']}")
        print(f"\n核验 {tot['docs']} 份文档：引用 {tot['refs']} 处 ｜ 路径命中 {tot['paths']} "
              f"｜ 行号在界 {tot['lines']} ｜ 锚点 {tot['anchors']} ｜ 哈希 {tot['md5']}"
              f"（歧义跳过 {tot['md5_ambig']}）｜ 目录 {tot['dirs']}")
        print(f"  已按判据豁免：单元名 {tot['units']} ｜ 省略号/通配 {tot['elided']} "
              f"｜ /tmp 瞬态 {tot['transient']} ｜ 白名单 {tot['allow']} ｜ 弱悬空 {tot['path_weak']}"
              f" ｜ 锚点无法归属 {tot['anchor_unattributed']}")
        print(f"分类计数：{by or '{}'}  ⇒  FAIL {len(fails)} / WARN {len(warns)}")

    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
