#!/usr/bin/env python3
"""DeepSeek-V4.1-Flash gate helpers for SGLang (port of the GLM final_bench kldlong / tscan). Stdlib only.

PROVENANCE: ported 2026-10-01 from knapcio/DeepSeek-V4.1-Flash-4x-DGX-Spark-TP4 v2.3, commit 5f11a97
(scripts/ds_gate.py, 494 lines). See docs/taskcards/DSGATE-PREFIXSCAN-PORT-20261001.md for the runbook.

OUR CHANGES vs the source (marked "# PORT:" inline):
 1. Endpoint/model: --url default http://127.0.0.1:8898 (our TEST engine; :8899 is production and this
    script REFUSES to target it), --model default DeepSeek-V4.1-Flash. Confirm the served name once per
    boot with GET /get_model_info and pass --model if it differs.
 2. --tf promoted to a first-class default (argparse.BooleanOptionalAction: --tf/--no-tf, default ON).
    Our campaign boot does NOT enable decoder SWA bounded replay, so prompt logprobs are servable and the
    teacher-forced panel is fully usable -- an upgrade over knapcio's stack, where his replay_guard
    answers prompt-logprob requests with HTTP 400 and only the greedy continuation is comparable.
    --no-tf reproduces his continuation-only behavior.
 3. Panel corpus: knapcio's kld_long_texts.json (628 KB of his real docs) is NOT carried over (taskcard
    C3). A seeded built-in generator synthesizes the four long texts (grammar-template prose, synthetic
    Python modules, a mixed prose/code/JSON doc); the exact token cuts 16500/18000/24003/40001 are kept
    because collect slices the tokenized text to the panel target (generator builds ~1.4-1.9x token
    margin; collect warns if a text comes up short). `kld gen-panel` dumps the corpus; `--texts FILE`
    accepts any kld_long_texts.json-format corpus (id/kind/text/tokens) for the day a real bilingual
    panel lands. Origin of every panel text is recorded in the collect output.
 4. `selfcheck` subcommand: fully offline dry-run (no network): panel magnitude/determinism checks,
    the full compare metric pipeline on constructed collect JSONs, and a discriminative two-state test
    (identical pair => KL ~0 / PASS, deliberately diverged pair => high KL / FAIL).
 5. No behavioral change to the KL math (top-k support + tail bucket), gate lines, thresholds or tscan.

  kld collect --panel long|short --out F.json [--texts kld_long_texts.json] [--k 10] [--gen 256] [--no-tf]
      Fidelity panel scored on identical input_ids in every arm (no chat template, no special tokens).
      long:  the four panel texts cut to exact token counts (16500 / 18000 / 24003 / 40001: several
             full prefill chunks, a short final chunk, row counts that are not a multiple of TP = 4).
      short: 12 texts of ~1-3k tokens: 10 token slices of the long texts at offsets > 0 (prose, code,
             mixed docs) plus an embedded Polish text (whole, ~1k tokens) and a seeded generated JSON
             document.
      Per text, via SGLang native POST /generate:
        1. continuation: greedy, --gen tokens, top-k output logprobs only, a fresh cache_salt (cold prefill);
        2. with --tf (default on our stack), teacher-forced: max_new_tokens 1, logprob_start_len 0,
           top_logprobs_num k -- every prompt position scored on identical input_ids.
      Cold prefill assumption: SGLang caps a request's radix prefix match at its logprob_start_len when
      return_logprob is set, so the teacher-forced request recomputes every prompt position even though
      the continuation just cached them. meta_info.cached_tokens is recorded per request (tf_cached /
      cont_cached); collect and compare print a WARN when the teacher-forced request reports cached
      tokens > 0, which would mean the assumption does not hold on this build.
  kld compare REF.json CAND.json [--max-kl X]
      KL(ref || cand) over ref's top-k support plus one tail bucket, per text and pooled; top-1 agreement;
      the same numbers on the positions where ref and cand agree on top-1; mean NLL of the actual prompt
      tokens; last-2048 positions (long panel); continuation KL up to and including the first divergence.
      Prints
        GATE kld_<panel> <mean> <PASS|FAIL> <positions>
        GATE kld_<panel>_agree <mean> info <positions>
        GATE kld_<panel>_cont <mean> info <positions>
      --max-kl defaults to 0.035 (both panels). Method note from v2.3: cold prefill is not bitwise
      reproducible, so always read the candidate KL against an A/A self-compare floor collected on the
      same boot. Exit code 0 on PASS.
  kld gen-panel --out F.json [--seed S]
      Write the built-in generated long-panel corpus (kld_long_texts.json format) for inspection.
  tscan LABEL [--max-tokens 768] [--thinking on|off] [--out-dir DIR]
      T > 0 correctness scan on /v1/chat/completions: 11 prompts (prose / think / code / json / Polish /
      story / json_schema) at (T 1.0, top-p 0.95, seeded) and (T 0.6, top-p 0.95, unseeded) at c=1, then
      one c=4 pass mixing T=1 and T=0 requests. Flags: SALAD (>= 5 CJK characters or >= 3 U+FFFD), LOOP
      (tail is one unit of <= 200 chars repeated >= 6 times, or the server loop abort: finish "stop" with
      matched_stop "repetition"), BADJSON (json tasks, warning only). Prints "TSCAN: <n> salad of <m>
      outputs ..."; rows go to DIR/tscan.jsonl (default ~/ds-gate/LABEL/).
  selfcheck
      Offline dry-run; exits 0 when every check passes. Sends no requests.
"""
import argparse
import concurrent.futures as cf
import contextlib
import bigread  # 大文件只读探针护栏（>50MB 必流式，QA-TOOLS 20261006）
import io
import json
import math
import os
import random
import re
import sys
import tempfile
import time
import urllib.request

BASE = "http://127.0.0.1:8898"          # PORT(1): test engine only; :8899 (production) is refused below
MODEL = "DeepSeek-V4.1-Flash"           # PORT(1): confirm with GET /get_model_info, override with --model
FORBIDDEN_PORT = 8899                   # PORT(1): production engine - this script must never target it
HERE = os.path.dirname(os.path.abspath(__file__))
MAX_KL = {"long": 0.035, "short": 0.035}
GEN_SEED = 20261001                     # PORT(3): default seed of the built-in panel generator


def check_base(url):
    """PORT(1): refuse the production port before any request goes out."""
    m = re.search(r":(\d+)(?:/|$)", url)
    if url.startswith("http://127.0.0.1:%d" % FORBIDDEN_PORT) or (m and int(m.group(1)) == FORBIDDEN_PORT):
        sys.exit("REFUSED: %s is the production engine; this gate only ever targets the test engine (:8898)" % url)
    return url.rstrip("/")


def post(path, body, timeout=1800):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def tokenize(text):
    err = None
    for body in ({"model": MODEL, "prompt": text, "add_special_tokens": False}, {"model": MODEL, "prompt": text}):
        try:
            r = post("/tokenize", body, timeout=300)
            if r.get("tokens"):
                return [int(x) for x in r["tokens"]]
        except Exception as exc:  # noqa: BLE001
            err = exc
    raise RuntimeError(f"/tokenize failed: {err!r}")


def generate(ids, max_new, k, start, salt=None):
    body = {"input_ids": ids, "sampling_params": {"max_new_tokens": max_new, "temperature": 0},
            "return_logprob": True, "top_logprobs_num": k}
    if start is not None:
        body["logprob_start_len"] = start
    if salt:
        body["cache_salt"] = salt
    r = post("/generate", body)
    return r[0] if isinstance(r, list) else r


# ------------------------------------------------------------------------------------------------ logprob parsing
def entry(e):
    """(logprob, token_id) from one SGLang logprob entry: [logprob, token_id, text] or {"logprob", "token_id"}."""
    if isinstance(e, dict):
        return e.get("logprob"), e.get("token_id", e.get("id"))
    if isinstance(e, (list, tuple)) and len(e) >= 2:
        return e[0], e[1]
    return None, None


def top_dict(x):
    """{token_id: logprob} for one position (list of entries or a {token_id: logprob} map); None when empty."""
    if not x:
        return None
    if isinstance(x, dict):
        pairs = ((k, v["logprob"] if isinstance(v, dict) else v) for k, v in x.items())
    else:
        pairs = ((tid, lp) for lp, tid in map(entry, x))
    d = {int(t): float(lp) for t, lp in pairs if t is not None and lp is not None}
    return d or None


# ------------------------------------------------------------------------------------------------ panel
# PORT(3): seeded corpus generator replacing knapcio's kld_long_texts.json (taskcard C3: rebuild the
# panel from our own material instead of carrying his texts). Word soup with light grammar templates,
# synthetic Python and JSON. Deterministic per seed; realistic token variety, no long repeats.
_N = ("system server record cluster session packet worker queue index cache request handler table "
      "config message batch checkpoint shard ledger policy cursor buffer window stream license "
      "tenant metric trace span journal vector matrix kernel bridge gateway router beacon pilot "
      "harbor vessel cargo raft signal lantern compass anchor deck cabin sail tide storm").split()
_V = ("holds writes reads locks merges splits joins retries fails recovers mirrors strips rebalances "
      "validates compacts snapshots restores archives replays rotates seals verifies signs drains "
      "leases releases scans folds sorts packs ships tracks reports schedules collects").split()
_A = ("stable stale warm cold dense sparse exact rough smooth quiet loud fast slow tight loose fresh "
      "aged bold calm dry plain fancy broad narrow deep shallow").split()
_T = [
    "The {a} {n} {v} the {n2} before the {a2} {n3} {v2}.",
    "After the {n} {v}, the crew {v2} every {a} {n2} on the {n3}.",
    "Each {n} holds {d} {a} {n2} records, and the {n3} {v} them at {d2} second intervals.",
    "When the {a} {n} goes {a2}, the pilot {v} the {n2} and {v2} a {n3}.",
    "The harbor log notes that raft {d} {v} {d2} crates while the tide {v2} the eastern anchor.",
    "No {n} may {v} a sealed {n2} unless the {a} {n3} also {v2} it.",
    "Between {d} and {d2} checks the {a} {n} {v} quietly, then {v2} the {n2}.",
    "A {a} {n}, a {a2} {n2} and three {n3}s {v} the same ledger before dawn.",
    "Records {d} through {d2} show the {a} {n} {v} while the {n2} {v2} nothing at all.",
]
_CODE_NAMES = ("parse_header resolve_lease drain_shard pack_window seal_ledger fold_traces "
               "scan_states rotate_keys check_quorum mirror_blocks compact_journal issue_token "
               "verify_beacon strip_manifest bind_router spill_cursor").split()


def _sentence(rnd):
    return rnd.choice(_T).format(a=rnd.choice(_A), a2=rnd.choice(_A), n=rnd.choice(_N), n2=rnd.choice(_N),
                                 n3=rnd.choice(_N), v=rnd.choice(_V), v2=rnd.choice(_V),
                                 d=rnd.randint(3, 977), d2=rnd.randint(3, 977))


def _para(rnd):
    return " ".join(_sentence(rnd) for _ in range(rnd.randint(3, 8)))


def _prose(rnd, chars, title):
    parts, n, sec = ["# " + title, ""], 0, 0
    while n < chars:
        sec += 1
        parts.append("## Part %d: the %s and the %s" % (sec, rnd.choice(_N), rnd.choice(_N)))
        n += len(parts[-1]) + 1
        for _ in range(rnd.randint(3, 6)):
            parts.append(_para(rnd))
            n += len(parts[-1]) + 1
        if rnd.random() < 0.5:
            li = "\n".join("- %s the %s %s (%d units)" % (rnd.choice(_V), rnd.choice(_A), rnd.choice(_N),
                                                           rnd.randint(1, 500)) for _ in range(rnd.randint(2, 5)))
            parts.append(li)
            n += len(li) + 1
        parts.append("")
    return "\n".join(parts)


def _code_module(rnd, chars, title, seed):
    parts = ['"""%s -- synthetic module for the ds_gate panel (seed %d). Not real project code."""' % (title, seed),
             ""]
    n = len(parts[0])
    for i in range(9999):
        if n >= chars:
            break
        fn = "%s_v%d" % (rnd.choice(_CODE_NAMES), i)
        args = ", ".join(rnd.choice(_N) + str(rnd.randint(1, 9)) for _ in range(rnd.randint(1, 3)))
        body = ["def %s(%s):" % (fn, args),
                '    """%s the %s %s."""' % (rnd.choice(_V), rnd.choice(_A), rnd.choice(_N)),
                "    out = []"]
        for _ in range(rnd.randint(3, 8)):
            body.append("    for i in range(%d):" % rnd.randint(2, 64))
            body.append("        %s = (%s * %d + i) %% %d" % (rnd.choice(_N), rnd.choice(_N),
                                                              rnd.randint(2, 97), rnd.randint(7, 997)))
            body.append("        if %s %% %d == 0:" % (rnd.choice(_N), rnd.randint(2, 13)))
            body.append('            out.append((i, "%s", %s))' % (rnd.choice(_N), rnd.choice(_N)))
        body.append("    # %s the %s records before the next window" % (rnd.choice(_V), rnd.choice(_N)))
        body.append("    return sorted(out)[:%d]" % rnd.randint(8, 256))
        body.append("")
        blk = "\n".join(body)
        parts.append(blk)
        n += len(blk) + 1
    return "\n".join(parts)


def _mixed(rnd, chars, title, seed):
    parts, n, sec = ["# " + title + " (mixed corpus)", ""], 0, 0
    while n < chars:
        sec += 1
        parts.append("## Section %d" % sec)
        n += 14
        for _ in range(rnd.randint(1, 3)):
            parts.append(_para(rnd))
            n += len(parts[-1]) + 1
        code = _code_module(rnd, 1400 + rnd.randint(0, 2200), "%s-s%d" % (title, sec), seed + sec)
        parts.append("```python\n" + code + "\n```")
        n += len(parts[-1]) + 1
        rows = "\n".join("| %s | %s | %d |" % (rnd.choice(_N), rnd.choice(_A), rnd.randint(1, 9999))
                         for _ in range(rnd.randint(3, 9)))
        parts.append("| item | state | count |\n|---|---|---|\n" + rows)
        n += len(parts[-1]) + 1
        if rnd.random() < 0.4:
            parts.append("```json\n" + json_doc(n=rnd.randint(3, 8), seed=rnd.randint(1, 10 ** 6))[:1800] + "\n```")
            n += len(parts[-1]) + 1
        parts.append("")
    return "\n".join(parts)


LONG_TARGETS = [("prose-docs", "prose", 16500), ("code-runner", "code", 18000),
                ("code-sched", "code", 24003), ("mixed-long", "mixed", 40001)]
CHARS_PER_TOKEN = 8.0   # ~1.4-1.9x token margin over the target at 4.5-5.8 real chars/token


def gen_long_texts(seed=GEN_SEED):
    """PORT(3): the four long-panel texts in kld_long_texts.json format (synthetic, seeded)."""
    out = []
    for i, (tid, kind, target) in enumerate(LONG_TARGETS):
        rnd = random.Random(seed * 1000 + i)
        want = int(target * CHARS_PER_TOKEN)
        if tid == "prose-docs":
            text = _prose(rnd, want, "Ledger and Harbor Notes (ds_gate panel %d)" % seed)
        elif tid == "code-runner":
            text = _code_module(rnd, want, "runner_window", seed)
        elif tid == "code-sched":
            text = _code_module(rnd, want, "sched_ledger", seed + 1)
        else:
            text = _mixed(rnd, want, "Field Journal", seed)
        out.append({"id": tid, "kind": kind, "text": text, "tokens": target})
    return out


SHORT = [  # id, kind, source, token offset, tokens (None: the whole text)
    ("docs-a", "prose", "prose-docs", 1500, 1531), ("docs-b", "prose", "prose-docs", 9000, 2049),
    ("docs-c", "prose", "prose-docs", 14000, 1203), ("runner-a", "code", "code-runner", 2500, 2555),
    ("runner-b", "code", "code-runner", 12000, 1777), ("sched-a", "code", "code-sched", 5000, 3001),
    ("sched-b", "code", "code-sched", 18000, 1409), ("mixed-a", "mixed", "mixed-long", 8000, 2311),
    ("mixed-b", "prose", "mixed-long", 31000, 1027), ("mixed-c", "mixed", "mixed-long", 37000, 2803),
    ("polish", "polish", "polish", 0, None), ("json", "json", "json", 0, 2500),
]

POLISH = """Stare miasteczko nad rzeką przez wieki żyło z handlu drewnem. Tratwy spływały wiosną do Gdańska, a flisacy wracali pieszo, niosąc sól, sukno i wiadomości ze świata. Kiedy w dziewiętnastym wieku poprowadzono kolej inną doliną, rynek opustoszał w ciągu jednego pokolenia. Zostały kamienice z podcieniami, kościół z drewnianą dzwonnicą i przekonanie mieszkańców, że historia kiedyś o nich przypomni.

Przypomniała sobie w latach dziewięćdziesiątych, gdy młody burmistrz postanowił odnowić nabrzeże. Nie miał pieniędzy na wielkie inwestycje, więc zaczął od drobiazgów: ławek, latarni, ścieżki rowerowej wzdłuż wału. Po trzech latach do miasteczka zaczęli przyjeżdżać kajakarze, a za nimi właściciele pensjonatów. Dziś w sezonie trudno znaleźć wolny pokój, a zimą rynek znowu cichnie, jakby odpoczywał po letnim zgiełku.

Dobry żurek zaczyna się od zakwasu. Mąkę żytnią razową zalewa się przegotowaną, letnią wodą, dodaje ząbek czosnku, skórkę chleba i liść laurowy, po czym odstawia w ciepłe miejsce na cztery, pięć dni. Zakwas powinien pachnieć kwaśno, ale czysto; jeśli pojawi się pleśń, trzeba zacząć od nowa. Wywar gotuje się na wędzonce z warzywami, a zakwas wlewa na końcu, mieszając, żeby nie powstały grudki. Majeranek dodaje się dopiero przed podaniem.

Zespół, który planuje migrację bazy danych, powinien najpierw spisać wszystkie zależności: usługi, raporty, zadania wsadowe i ręczne skrypty, o których nikt już nie pamięta. Następnie warto przygotować środowisko testowe z kopią danych produkcyjnych i sprawdzić, ile trwa pełne przeniesienie. Plan wycofania nie jest formalnością. Jeśli nie da się go przećwiczyć, lepiej przesunąć termin, niż liczyć na to, że wszystko pójdzie gładko.

Jesień w górach potrafi zaskoczyć. Rano słońce i dwanaście stopni, po południu mgła tak gęsta, że szlak znika po kilku metrach, a wieczorem pierwszy śnieg na graniach. Doświadczeni turyści zabierają czołówkę nawet na krótką wycieczkę, sprawdzają prognozę w dwóch źródłach i mówią komuś w schronisku, dokąd idą. Najczęstszym błędem nie jest brak sprzętu, tylko upór: niechęć do zawrócenia, gdy warunki się pogarszają.

Babcia twierdziła, że pogodę najlepiej przewidują jaskółki i jej lewe kolano. Dziadek wolał barometr, który wisiał w sieni od czasów przedwojennych i którego nikt poza nim nie umiał odczytać. Spierali się o to przez pięćdziesiąt lat, a my, wnuki, prowadziliśmy tabelę trafień w zeszycie w kratkę. Wynik był remisowy, co obie strony uznały za dowód własnej racji.

Nauka programowania przypomina naukę języka obcego: najpierw zapamiętuje się słówka, potem zdania, a dopiero po długim czasie zaczyna się myśleć w nowym języku. Początkujący często przepisują kod z poradników bez zrozumienia, co jest normalnym etapem, o ile w końcu zaczną zadawać pytania: dlaczego ta pętla kończy się tutaj, co się stanie, gdy lista będzie pusta, skąd program wie, jaki jest typ tej zmiennej. Takie pytania są ważniejsze niż kolejny kurs.
"""


def json_doc(n=60, seed=20260929):
    rnd = random.Random(seed)
    first = ["Anna", "Piotr", "Maria", "Jan", "Olivia", "Liam", "Katarzyna", "Tomasz", "Sofia", "Mateo", "Zofia", "Noah"]
    last = ["Nowak", "Kowalski", "Smith", "Garcia", "Wiśniewska", "Müller", "Rossi", "Dubois", "Lewandowski", "Kim"]
    cities = ["Warszawa", "Kraków", "Gdańsk", "Berlin", "Lyon", "Porto", "Toronto", "Osaka", "Wrocław", "Austin"]
    status = ["pending", "paid", "shipped", "delivered", "refunded", "cancelled"]
    orders = []
    for i in range(n):
        items = [{"sku": f"SKU-{rnd.randint(1000, 9999)}", "qty": rnd.randint(1, 5),
                  "unit_price": round(rnd.uniform(1.5, 499.0), 2), "gift": rnd.random() < 0.1}
                 for _ in range(rnd.randint(1, 4))]
        orders.append({"order_id": f"ORD-{2026_0000 + i * 37}", "customer": {
            "name": f"{rnd.choice(first)} {rnd.choice(last)}", "email": f"user{rnd.randint(10, 99999)}@example.com",
            "address": {"city": rnd.choice(cities), "postal_code": f"{rnd.randint(10, 99)}-{rnd.randint(100, 999)}"}},
            "created_at": f"2026-{rnd.randint(1, 9):02d}-{rnd.randint(1, 28):02d}T{rnd.randint(0, 23):02d}:"
                          f"{rnd.randint(0, 59):02d}:00Z",
            "status": rnd.choice(status), "items": items,
            "total": round(sum(x["qty"] * x["unit_price"] for x in items), 2),
            "note": rnd.choice([None, "leave at the door", "call before delivery", "fragile", "zadzwonić przed dostawą"])})
    return json.dumps({"orders": orders}, indent=2, ensure_ascii=False)


def panel(name, texts_path, seed=GEN_SEED):
    if texts_path:
        texts = bigread.capped_json_load(texts_path, label="texts")
    else:
        texts = gen_long_texts(seed)
    if name == "long":
        return [{"id": t["id"], "kind": t.get("kind", ""), "text": t["text"], "offset": 0, "tokens": int(t["tokens"])}
                for t in texts]
    src = {t["id"]: t["text"] for t in texts}
    src.update(polish=POLISH, json=json_doc())
    return [{"id": i, "kind": k, "text": src[s], "offset": o, "tokens": n} for i, k, s, o, n in SHORT]


# ------------------------------------------------------------------------------------------------ KLD collect
def kld_collect(a):
    corpus = f"generated (seed {a.seed})" if not a.texts else a.texts   # PORT(3): record corpus origin
    out = {"model": MODEL, "url": BASE, "panel": a.panel, "k": a.k, "gen": a.gen, "tf": a.tf,
           "corpus": corpus, "items": []}
    stamp = time.strftime("%Y%m%d-%H%M%S")
    toks, warns = {}, []
    for t in panel(a.panel, a.texts, a.seed):
        if t["text"] not in toks:
            toks[t["text"]] = tokenize(t["text"])
        full = toks[t["text"]]
        want = t["tokens"] or len(full)
        ids = full[t["offset"]:t["offset"] + want]
        n = len(ids)
        rec = {"id": t["id"], "kind": t["kind"], "offset": t["offset"], "target": want, "n_prompt": n}
        if n < want:
            warns.append(f"{t['id']}: only {n} of {want} tokens available")
        t0 = time.time()
        r = generate(ids, a.gen, a.k, None, salt=f"kld-{stamp}-{t['id']}")  # output logprobs only, cold prefill
        rec["cont_s"] = round(time.time() - t0, 2)
        mi = r.get("meta_info") or {}
        out_lp = mi.get("output_token_logprobs") or []
        rec["gen_tokens"] = [int(x) for x in (r.get("output_ids") or [entry(e)[1] for e in out_lp])]
        rec["gen_top"] = [top_dict(x) for x in mi.get("output_top_logprobs") or []]
        rec["finish"] = mi.get("finish_reason")
        rec["cont_cached"] = mi.get("cached_tokens")
        if not a.tf:
            rec["prompt_lp"], rec["prompt_tok_lp"] = [], []
            out["items"].append(rec)
            print(f"  {t['id']:12s} prompt {n} tok (offset {t['offset']}) continuation {rec['cont_s']} s "
                  f"({len(rec['gen_tokens'])} tok, cached {rec['cont_cached']})", flush=True)
            continue
        t0 = time.time()
        r = generate(ids, 1, a.k, 0)
        rec["tf_s"] = round(time.time() - t0, 2)
        mi = r.get("meta_info") or {}
        rec["prompt_lp"] = [top_dict(x) for x in mi.get("input_top_logprobs") or []]
        rec["prompt_tok_lp"] = [entry(e)[0] for e in mi.get("input_token_logprobs") or []]
        rec["tf_cached"] = mi.get("cached_tokens")
        rec["tf_prompt_tokens"] = mi.get("prompt_tokens")
        if rec["tf_cached"]:
            warns.append(f"{t['id']}: teacher-forced request reported cached_tokens {rec['tf_cached']} (not a cold prefill)")
        if len(rec["prompt_lp"]) != n:
            warns.append(f"{t['id']}: {len(rec['prompt_lp'])} teacher-forced positions for {n} prompt tokens")
        out["items"].append(rec)
        print(f"  {t['id']:12s} prompt {n} tok (target {want}, offset {t['offset']}) continuation {rec['cont_s']} s "
              f"({len(rec['gen_tokens'])} tok, cached {rec['cont_cached']}) teacher-forced {rec['tf_s']} s "
              f"({len(rec['prompt_lp'])} positions, cached {rec['tf_cached']})", flush=True)
    out["warnings"] = warns
    with open(a.out, "w") as f:
        json.dump(out, f)
    for w in warns:
        print("WARN " + w)
    print(f"KLD-COLLECT {a.panel} {a.out} [corpus: {corpus}, tf={'on' if a.tf else 'off'}]: "
          f"{len(out['items'])} texts, prompts {[i['n_prompt'] for i in out['items']]}, "
          f"{sum(i['n_prompt'] for i in out['items'])} tokens, {len(warns)} warning(s)")
    return 0


# ------------------------------------------------------------------------------------------------ KLD compare
def kl_top(p, q):
    """KL(p || q) over p's top-k support plus one tail bucket; q entries missing from its top-k get q's floor."""
    if not p or not q:
        return None
    floor = min(q.values())
    kl, pm, qm = 0.0, 0.0, 0.0
    for tok, lp in p.items():
        lq = q.get(tok, floor)
        pp = math.exp(lp)
        kl += pp * (lp - lq)
        pm += pp
        qm += math.exp(lq)
    pt, qt = max(1e-12, 1 - pm), max(1e-12, 1 - min(qm, 1 - 1e-12))
    return max(0.0, kl + pt * math.log(pt / qt))


def stats(xs):
    if not xs:
        return {"n": 0, "mean": float("nan"), "p99": float("nan"), "max": float("nan")}
    s = sorted(xs)
    return {"n": len(s), "mean": sum(s) / len(s), "p99": s[max(0, int(0.99 * len(s)) - 1)], "max": s[-1]}


def nll(rec):
    v = [-x for x in rec.get("prompt_tok_lp") or [] if x is not None]
    return sum(v) / len(v) if v else float("nan")


def argmax(d):
    return max(d, key=d.get)


def kld_compare(a):
    R = bigread.capped_json_load(a.ref, label="kld_ref")
    C = bigread.capped_json_load(a.cand, label="kld_cand")
    pn = R.get("panel", "long")
    tag = f"kld_{pn}"
    max_kl = a.max_kl if a.max_kl is not None else MAX_KL.get(pn, 0.035)
    same_panel = C.get("panel", "long") == pn and len(R["items"]) == len(C["items"]) and all(
        r["id"] == c["id"] and r["n_prompt"] == c["n_prompt"] for r, c in zip(R["items"], C["items"]))
    if not same_panel:
        print(f"MISMATCHED PANEL: {pn} {[(i['id'], i['n_prompt']) for i in R['items']]} vs "
              f"{C.get('panel', 'long')} {[(i['id'], i['n_prompt']) for i in C['items']]}")
        print(f"GATE {tag} nan FAIL 0")
        return 1
    pooled, agree_all, tail_all, cont_all, top1 = [], [], [], [], 0
    for r, c in zip(R["items"], C["items"]):
        kls, agree = [], []
        for p, q in zip(r["prompt_lp"], c["prompt_lp"]):
            k = kl_top(p, q)
            if k is None:
                continue
            kls.append(k)
            if argmax(p) == argmax(q):
                agree.append(k)
        tail = kls[-2048:] if pn == "long" else []
        gr, gc = r["gen_tokens"], c["gen_tokens"]
        div = next((i for i, (u, v) in enumerate(zip(gr, gc)) if u != v), min(len(gr), len(gc)))
        ck = [k for k in (kl_top(p, q) for p, q in zip(r["gen_top"][:div + 1], c["gen_top"][:div + 1])) if k is not None]
        pooled += kls
        agree_all += agree
        tail_all += tail
        cont_all += ck
        top1 += len(agree)
        s, sa = stats(kls), stats(agree)
        print(f"{r['id']:12s} prompt {r['n_prompt']:6d}  tf KL mean {s['mean']:.5f} p99 {s['p99']:.4f} "
              f"top1 {100 * len(agree) / max(1, len(kls)):.2f} %  agree-only KL {sa['mean']:.5f}"
              + (f"  last-2048 KL {stats(tail)['mean']:.5f}" if tail else "")
              + f"  NLL {nll(r):.4f} -> {nll(c):.4f}  continuation: identical {div}/{len(gr)} tokens"
              f"{' (full)' if gr == gc else ''}, KL to divergence {stats(ck)['mean']:.5f} ({len(ck)} pos)")
        for side, x in (("ref", r), ("cand", c)):
            if x.get("tf_cached"):
                print(f"WARN {r['id']}: {side} teacher-forced request had cached_tokens {x['tf_cached']}")
    s, sa, sc = stats(pooled), stats(agree_all), stats(cont_all)
    if s["n"] == 0:  # no teacher-forced positions (--no-tf collect, or a bounded-replay server)
        ok = sc["n"] > 0 and sc["mean"] <= max_kl
        print(f"continuation-only panel: {sc['n']} positions (up to and including the first divergence), mean KL "
              f"{sc['mean']:.5f}, p99 {sc['p99']:.4f}, max {sc['max']:.4f}")
        print(f"GATE {tag}_cont {sc['mean']:.5f} {'PASS' if ok else 'FAIL'} {sc['n']}")
        return 0 if ok else 1
    ok = s["n"] > 0 and s["mean"] <= max_kl
    n_ref = [nll(r) for r in R["items"]]
    n_cand = [nll(c) for c in C["items"]]
    print(f"pooled: {s['n']} teacher-forced positions, mean KL {s['mean']:.5f}, p99 {s['p99']:.4f}, max {s['max']:.4f}, "
          f"top-1 {100 * top1 / max(1, s['n']):.2f} %; agree-only {sa['n']} positions, mean KL {sa['mean']:.5f}, "
          f"p99 {sa['p99']:.4f}"
          + (f"; last-2048 mean {stats(tail_all)['mean']:.5f}" if tail_all else "")
          + f"; mean NLL {sum(n_ref) / len(n_ref):.4f} -> {sum(n_cand) / len(n_cand):.4f}"
          f"; continuation mean {sc['mean']:.5f} ({sc['n']} pos)")
    print(f"GATE {tag} {s['mean']:.5f} {'PASS' if ok else 'FAIL'} {s['n']}")
    print(f"GATE {tag}_agree {sa['mean']:.5f} info {sa['n']}")
    print(f"GATE {tag}_cont {sc['mean']:.5f} info {sc['n']}")
    return 0 if ok else 1


# ------------------------------------------------------------------------------------------------ T > 0 scan
PROMPTS = [
    ("prose", "low", "Explain how to decide whether a medium-sized software project is ready for a database migration. "
     "Cover dependencies, schema compatibility, tests, rollout and rollback in several paragraphs."),
    ("prose", "low", "Describe how a city could reduce traffic congestion over ten years without building new roads. "
     "Discuss pricing, public transport, zoning and the politics of each option."),
    ("think", "high", "A small town has one bridge that is closing for two years of repairs. The council must choose "
     "between a free ferry, a temporary pontoon bridge, and expanded bus service over a longer road. Reason carefully "
     "through the costs and risks of each option, then recommend one."),
    ("think", "high", "Three friends split a restaurant bill unevenly because one arrived late and ordered less, another "
     "paid the tip, and the third covered a previous taxi. Work out a fair way to settle up step by step."),
    ("code", "low", "Write a Python 3 module with a thread-safe bounded LRU cache with per-item TTL: get, set, delete, "
     "clear, __len__, injectable monotonic clock, plus five unittest tests. Return only code."),
    ("code", "low", "Write a Python function that parses an INI-like config format with sections, comments, multi-line "
     "values and typed getters, with docstrings and doctests. Return only code."),
    ("json", "low", "Return only a JSON object describing three fictional employees: name, role, start_date (ISO 8601), "
     "skills (array of strings), manager (name or null). No prose, no code fences."),
    ("json", "low", "Return only a JSON array of five cities with fields name, country, population (integer), "
     "coordinates {lat, lon} and a one-sentence note. No prose, no code fences."),
    ("polish", "low", "Napisz po polsku kilka akapitów o tym, jak przygotować się do pierwszego maratonu: plan "
     "treningowy, odżywianie, sprzęt i regeneracja."),
    ("story", "low", "Write a short story (about 500 words) about a lighthouse keeper who finds a message in a bottle "
     "written in her own handwriting."),
    ("schema", "low", "Give me a packing list for a three-day hiking trip as JSON."),
]
SCHEMA = {"type": "json_schema", "json_schema": {"name": "packing", "schema": {
    "type": "object", "properties": {"items": {"type": "array", "items": {"type": "object", "properties": {
        "name": {"type": "string"}, "qty": {"type": "integer"}}, "required": ["name", "qty"]}}},
    "required": ["items"]}}}
EFFORT = {"low": "low", "medium": "medium", "high": "high", "max": "high"}


def loop_tail(s, min_rep=6, max_unit=200):
    t = s[-1500:]
    if len(t) < 300:
        return False
    for u in range(1, max_unit + 1):
        unit = t[-u:]
        reps, i = 1, len(t) - 2 * u
        while i >= 0 and t[i:i + u] == unit:
            reps += 1
            i -= u
        if reps >= min_rep and reps * u >= 120:
            return True
    return False


def scan_text(text):
    cjk = sum(0x4E00 <= ord(ch) <= 0x9FFF or 0x3040 <= ord(ch) <= 0x30FF or 0xAC00 <= ord(ch) <= 0xD7AF for ch in text)
    bad = text.count("\ufffd")
    flags = []
    if cjk >= 5 or bad >= 3:
        flags.append("SALAD")
    if loop_tail(text):
        flags.append("LOOP")
    return flags, cjk, bad


def json_ok(text):
    t = re.sub(r"^```(?:json)?\s*|\s*```$", "", text.strip())
    try:
        json.loads(t)
        return True
    except Exception:  # noqa: BLE001
        return False


def one_chat(kind, effort, prompt, temp, top_p, seed, max_tokens, thinking=True):
    body = {"model": MODEL, "messages": [{"role": "user", "content": prompt}], "max_tokens": max_tokens,
            "temperature": temp, "top_p": top_p, "chat_template_kwargs": {"thinking": thinking}}
    if thinking:
        body["reasoning_effort"] = EFFORT.get(effort, "high")
    if seed is not None:
        body["seed"] = seed
    if kind == "schema":
        body["response_format"] = SCHEMA
    t0 = time.time()
    r = post("/v1/chat/completions", body, timeout=900)
    ch = r["choices"][0]
    msg = ch.get("message") or {}
    usage = r.get("usage") or {}
    return {"kind": kind, "temp": temp, "top_p": top_p, "seed": seed, "finish": ch.get("finish_reason"),
            "matched_stop": ch.get("matched_stop"), "tokens": usage.get("completion_tokens"),
            "wall_s": round(time.time() - t0, 2), "content": msg.get("content") or "",
            "reasoning": msg.get("reasoning_content") or msg.get("reasoning") or ""}


def flag_row(r):
    """Adds flags / cjk / fffd to a result row; returns (salad_or_loop, badjson)."""
    flags, cjk, bad = scan_text((r.get("reasoning") or "") + "\n" + (r.get("content") or ""))
    if r.get("matched_stop") == "repetition" and "LOOP" not in flags:
        flags.append("LOOP")
    badjson = r["kind"] in ("json", "schema") and r.get("finish") == "stop" and r.get("matched_stop") != "repetition" \
        and not json_ok(r.get("content") or "")
    if badjson:
        flags.append("BADJSON")
    r.update(flags=flags, cjk=cjk, fffd=bad)
    return any(f in ("SALAD", "LOOP") for f in flags), badjson


def tscan(a):
    out_dir = os.path.expanduser(a.out_dir or os.path.join("~/ds-gate", a.label))
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "tscan.jsonl")
    think = a.thinking == "on"
    rows = []
    for temp, top_p, seeded in ((1.0, 0.95, True), (0.6, 0.95, False)):
        for i, (kind, effort, prompt) in enumerate(PROMPTS):
            seed = (20260929 + i) if seeded else None
            try:
                rows.append(dict(one_chat(kind, effort, prompt, temp, top_p, seed, a.max_tokens, think), phase="c1"))
            except Exception as exc:  # noqa: BLE001
                rows.append({"phase": "c1", "kind": kind, "temp": temp, "seed": seed, "error": repr(exc)[:300]})
    # c = 4: every prompt at T = 1 plus two greedy requests, four at a time (mixed sampled / greedy batches)
    mix = [(k, e, p, 1.0, 0.95, 777 + i) for i, (k, e, p) in enumerate(PROMPTS)]
    mix.insert(3, ("prose", "low", PROMPTS[0][2], 0.0, 1.0, None))
    mix.insert(8, ("code", "low", PROMPTS[4][2], 0.0, 1.0, None))
    with cf.ThreadPoolExecutor(4) as ex:
        futs = [(m, ex.submit(one_chat, *m, a.max_tokens, think)) for m in mix]
        for m, f in futs:
            try:
                rows.append(dict(f.result(), phase="c4"))
            except Exception as exc:  # noqa: BLE001
                rows.append({"phase": "c4", "kind": m[0], "temp": m[3], "seed": m[5], "error": repr(exc)[:300]})
    salad = errors = badjson = 0
    with open(path, "w") as fo:
        for r in rows:
            if "error" in r:
                errors += 1
                r["flags"] = ["ERROR"]
            else:
                s, b = flag_row(r)
                salad += s
                badjson += b
            fo.write(json.dumps(r, ensure_ascii=False) + "\n")
            print(f"{r.get('phase', '?'):3s} {r.get('kind', '?'):7s} T={r.get('temp')} seed={r.get('seed')} "
                  f"tokens {r.get('tokens')} finish {r.get('finish')}"
                  f"{' (' + str(r['matched_stop']) + ')' if r.get('matched_stop') == 'repetition' else ''} "
                  f"{' '.join(r.get('flags', []))}", flush=True)
    print(f"TSCAN: {salad} salad of {len(rows)} outputs (errors {errors}, bad json {badjson}) -> {path}")
    return 0 if salad == 0 and errors == 0 else 1


# ------------------------------------------------------------------------------------------------ gen-panel / selfcheck
def gen_panel(a):
    texts = gen_long_texts(a.seed)
    with open(a.out, "w") as f:
        json.dump(texts, f)
    for t in texts:
        print(f"{t['id']:12s} kind {t['kind']:6s} target {t['tokens']:5d} tok  {len(t['text'])} chars "
              f"({len(t['text']) / t['tokens']:.1f} chars/tok)")
    print(f"GEN-PANEL seed {a.seed} -> {a.out}: {len(texts)} texts, {sum(len(t['text']) for t in texts)} chars")
    return 0


def _fake_collect(panel_name, diverge, tf):
    """PORT(4): constructed collect JSON for the offline compare-pipeline check. `diverge` swaps the
    candidate's top-k mass order (top-1 flips) at every prompt position and diverges the greedy
    continuation at token 5; `tf=False` produces a continuation-only file (empty prompt_lp)."""
    vocab = list(range(101, 111))
    probs = [0.22, 0.14, 0.11, 0.09, 0.08, 0.07, 0.06, 0.05, 0.04, 0.03]
    gprobs = [0.50, 0.20, 0.10, 0.08, 0.05, 0.04, 0.03]

    def dist(order, ps):
        return {t: math.log(p) for t, p in zip(order, ps)}

    ref_items, cand_items = [], []
    for i in range(3):
        pr = dist(vocab, probs)
        pc = dist(list(reversed(vocab)), probs)
        gt_r = dist(range(201, 208), gprobs)
        gt_c = dist(range(207, 200, -1), gprobs)
        gen_r = [201 + j for j in range(32)]
        gen_c = ([201 + j for j in range(5)] + [999] + [201 + j for j in range(6, 32)])
        base = {"id": f"txt{i}", "kind": "prose", "n_prompt": 2048 + 17 * i, "target": 2048 + 17 * i, "offset": 0,
                "tf_cached": 0, "cont_cached": 0,
                "prompt_lp": ([pr] * 64 if tf else []), "prompt_tok_lp": ([math.log(0.9)] * 64 if tf else []),
                "gen_tokens": list(gen_r), "gen_top": [dict(gt_r)] * 32}
        cand = dict(base)
        cand["prompt_lp"] = ([dict(pc)] * 64 if diverge else ([dict(pr)] * 64 if tf else []))
        cand["prompt_tok_lp"] = ([math.log(0.9)] * 64 if tf else [])
        cand["gen_tokens"] = list(gen_c) if diverge else list(gen_r)
        cand["gen_top"] = [dict(gt_c)] * 32 if diverge else [dict(gt_r)] * 32
        ref_items.append(base)
        cand_items.append(cand)
    mk = lambda items: {"model": MODEL, "panel": panel_name, "tf": tf, "items": items}
    return mk(ref_items), mk(cand_items)


def selfcheck(a):
    """PORT(4): offline dry-run. No network access: corpus generator checks plus the full compare
    pipeline on constructed pairs, including the discriminative two-state test."""
    ok = True

    def need(cond, why):
        nonlocal ok
        print(("PASS" if cond else "FAIL"), why)
        ok = ok and cond

    with tempfile.TemporaryDirectory(prefix="dsgate-selfcheck-") as td:
        # 1. panel corpus: magnitude, exact targets, determinism, divergence across seeds
        p1 = gen_long_texts(20261001)
        p2 = gen_long_texts(20261001)
        need([(t["id"], t["kind"], t["tokens"]) for t in p1] ==
             [("prose-docs", "prose", 16500), ("code-runner", "code", 18000),
              ("code-sched", "code", 24003), ("mixed-long", "mixed", 40001)], "long 面板 4 文本与精确 token 档")
        need([t["text"] for t in p1] == [t["text"] for t in p2], "生成器同 seed 可复现")
        need([t["text"] for t in p1] != [t["text"] for t in gen_long_texts(20261002)], "跨 seed 不同文本")
        for t in p1:
            need(6.0 * t["tokens"] <= len(t["text"]) <= 10.0 * t["tokens"],
                 f"{t['id']} 字符量级 {len(t['text'])} chars vs 目标 {t['tokens']} tok（切档余量充足）")
        short = panel("short", None, 20261001)
        need(len(short) == 12 and all(s["text"] for s in short), f"short 面板 12 段齐（{len(short)}）")
        need(any(s["id"] == "polish" for s in short) and any(s["id"] == "json" for s in short),
             "short 面板含波兰语与 JSON 生成档")
        jd = json.loads(json_doc(n=6, seed=99))
        need(len(jd["orders"]) == 6 and all("SKU-" in it["sku"] for o in jd["orders"] for it in o["items"]),
             "JSON 生成器记录/SKU 随机码存在")
        # 2. gen-panel to disk (落盘抽查)
        out_json = os.path.join(td, "kld_texts.json")
        gen_panel(argparse.Namespace(seed=20261001, out=out_json))
        need(os.path.getsize(out_json) > 400_000, f"gen-panel 落盘体量 ({os.path.getsize(out_json)} bytes)")
        loaded = bigread.capped_json_load(out_json, label="panel")
        need([t["id"] for t in loaded] == [t["id"] for t in p1] and loaded[0]["text"] == p1[0]["text"],
             "gen-panel 落盘可回读且与内存生成一致")
        # 3. compare pipeline, four states (tf/cont x identical/diverged)
        for tf, diverge, expect in ((True, False, "PASS"), (True, True, "FAIL"),
                                    (False, False, "PASS"), (False, True, "FAIL")):
            R, C = _fake_collect("long", diverge, tf)
            rp, cp = os.path.join(td, f"r{tf}{diverge}.json"), os.path.join(td, f"c{tf}{diverge}.json")
            with open(rp, "w") as f:
                json.dump(R, f)
            with open(cp, "w") as f:
                json.dump(C, f)
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = kld_compare(argparse.Namespace(ref=rp, cand=cp, max_kl=None))
            out = buf.getvalue()
            gate = [ln for ln in out.splitlines() if ln.startswith("GATE") and " info " not in ln]
            mean, verdict = float(gate[0].split()[2]), gate[0].split()[3]
            need(rc == (0 if expect == "PASS" else 1) and verdict == expect,
                 f"compare tf={tf} diverge={diverge} -> {expect} (rc {rc}, mean {mean:.5f})")
            if not diverge:
                need(mean < 1e-9, "自比态 KL≈0 (mean %g)" % mean)
                if tf:
                    need("100.00 %" in out, "自比态 top-1 一致率 100%")
            else:
                need(mean > 0.035, f"分叉态 KL 高于阈值 (mean {mean:.4f} > 0.035)")
        # 4. kl_top math spot checks
        d = {1: math.log(0.5), 2: math.log(0.5)}
        need(abs(kl_top(d, dict(d))) < 1e-12, "kl_top 同分布 = 0")
        d2 = {1: math.log(0.9), 2: math.log(0.1)}
        need(kl_top(d, d2) > 0.1, "kl_top 异分布 > 0")
        need(stats([1.0, 2.0, 3.0])["mean"] == 2.0 and stats([])["n"] == 0, "stats 空态/均值")
        # 5. tscan text flags (offline detectors)
        flags, cjk, _ = scan_text("正常的中文回答不应该被标记" * 1)
        need("SALAD" in flags and cjk >= 5, "SALAD 检测器对 CJK 有牙")
        need(len(POLISH) >= 300 and not loop_tail(POLISH), f"loop_tail 自然长文不误报（POLISH {len(POLISH)} chars）")
        need(loop_tail("abc " + "unit" * 100), "loop_tail 重复尾必报")
        need(json_ok('{"a": 1}') and not json_ok("{a:1}"), "json_ok 两态")
        # 6. production-port guard
        try:
            check_base("http://127.0.0.1:8899")
            need(False, "8899 生产口必须拒绝")
        except SystemExit:
            need(True, "8899 生产口必须拒绝")
        need(check_base("http://127.0.0.1:8898") == "http://127.0.0.1:8898", "8898 测试口放行")
    print("SELFCHECK", "PASS" if ok else "FAIL")
    return 0 if ok else 1


# ------------------------------------------------------------------------------------------------ CLI
def main(argv=None):
    global BASE, MODEL
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--url", default=BASE, help="test engine base (default %(default)s; the production "
                   "port is refused)")
    common.add_argument("--model", default=MODEL, help="served model name (default %(default)s; confirm with "
                   "GET /get_model_info)")
    ap = argparse.ArgumentParser(description="DeepSeek-V4.1-Flash SGLang gate helpers (port of knapcio v2.3 "
                                              "5f11a97; see module docstring for our changes)")
    sp = ap.add_subparsers(dest="cmd", required=True)
    k = sp.add_parser("kld")
    ksp = k.add_subparsers(dest="sub", required=True)
    c = ksp.add_parser("collect", parents=[common])
    c.add_argument("--panel", choices=("long", "short"), default="long")
    c.add_argument("--out", required=True)
    c.add_argument("--texts", default=None, help="kld_long_texts.json-format corpus; default = built-in seeded "
                   "generator (knapcio's corpus is not carried over, taskcard C3)")
    c.add_argument("--seed", type=int, default=GEN_SEED, help="seed of the built-in generator (ignored with --texts)")
    c.add_argument("--k", type=int, default=10)
    c.add_argument("--gen", type=int, default=256)
    c.add_argument("--tf", action=argparse.BooleanOptionalAction, default=True,
                   help="teacher-forced prompt logprobs (default ON: our boot runs without decoder SWA bounded "
                        "replay, so prompt logprobs are servable - an upgrade over the source stack; --no-tf "
                        "reproduces the source's continuation-only behavior)")
    m = ksp.add_parser("compare")
    m.add_argument("ref")
    m.add_argument("cand")
    m.add_argument("--max-kl", type=float, default=None, help="default 0.035 (long and short)")
    g = ksp.add_parser("gen-panel")
    g.add_argument("--out", required=True)
    g.add_argument("--seed", type=int, default=GEN_SEED)
    t = sp.add_parser("tscan", parents=[common])
    t.add_argument("label")
    t.add_argument("--max-tokens", type=int, default=768)
    t.add_argument("--thinking", choices=("on", "off"), default="on")
    t.add_argument("--out-dir", default=None, help="default ~/ds-gate/LABEL")
    sc = sp.add_parser("selfcheck")
    a = ap.parse_args(argv)
    BASE, MODEL = check_base(getattr(a, "url", BASE)), getattr(a, "model", MODEL)
    if a.cmd == "kld":
        if a.sub == "collect":
            return kld_collect(a)
        if a.sub == "compare":
            return kld_compare(a)
        return gen_panel(a)
    if a.cmd == "selfcheck":
        return selfcheck(a)
    return tscan(a)


if __name__ == "__main__":
    sys.exit(main() or 0)
