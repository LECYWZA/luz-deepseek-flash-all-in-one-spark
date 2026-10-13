#!/usr/bin/env python3
"""f4_de_load.py — F4 decode 负载驱动（长前缀并发 decode；census 采窗配套）

口径：
  - 长前缀 prompt=header(salt)+prose 指令+repeated filler+footer（sd_bench PR 构造同式，
    filler=" the"；每流独立 salt 防前缀共享；指令=hash-map essay prose（DE_PROSE 原文）
    ⇒ 生成段稳定长输出，decode 相纯净）。
  - --prose：c1 对表档=DE_PROSE_PROMPT 精确原文（sd_bench 同源；W25a 对表用）。
  - 全流首 token 齐 ⇒ 写 marker 文件（F4 采集脚本据此开 by-stage decode 窗=纯稳态 decode）。
  - 逐流逐 chunk 时间戳落 json（T7 N-1：ITL 序列=广播持续性+长尾对端等待的非 kineto 读数）。
"""
import argparse, json, threading, time, uuid
import requests

DE_PROSE = ("Write a detailed step-by-step explanation of how a hash map works, "
            "including collision handling, resizing, and time complexity. Be thorough.")

def send_one(base_url, prompt, max_tokens, timeout):
    """非流式单发（warm 相用）。返回 usage dict 或 raise。"""
    r = requests.post("%s/chat/completions" % base_url,
                      json={"messages": [{"role": "user", "content": prompt}],
                            "max_tokens": max_tokens, "temperature": 0.0, "top_p": 1.0},
                      timeout=timeout)
    r.raise_for_status()
    j = r.json()
    return {"completion": j.get("usage", {}).get("completion_tokens"),
            "prompt_tokens": j.get("usage", {}).get("prompt_tokens")}

def build_prefix_prompt(target_tokens, salt):
    header = ("[f4-decode %s]\nIgnore the filler below. After the filler, do this task: %s\n"
              % (salt, DE_PROSE))
    footer = "\nBegin the task now."
    fill = max(1, target_tokens - (len(header) + len(footer)) // 4)
    return header + " the" * fill + footer

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="http://127.0.0.1:8898/v1")
    ap.add_argument("--conc", type=int, required=True)
    ap.add_argument("--prefix", type=int, default=0, help="0=--prose 短提示模式")
    ap.add_argument("--prose", action="store_true")
    ap.add_argument("--max-tokens", type=int, default=128)
    ap.add_argument("--marker-file", default="")
    ap.add_argument("--json-out", required=True)
    ap.add_argument("--warm-prefix", action="store_true",
                    help="两相式：先逐流 max_tokens=1 热驻前缀（每流自命中，非跨流共享），"
                         "再全流并发重发同 prompt ⇒ prefill 串行错峰消除，ttft 齐一 ⇒ 纯稳态 c8 窗")
    a = ap.parse_args()
    salt = uuid.uuid4().hex[:8]
    if a.prose or a.prefix <= 0:
        prompts = [DE_PROSE] if a.conc == 1 else ["%s (stream %d/%d)" % (DE_PROSE, i + 1, a.conc) for i in range(a.conc)]
    else:
        prompts = [build_prefix_prompt(a.prefix, "%s-%d" % (salt, i)) for i in range(a.conc)]
    warm = None
    if a.warm_prefix:
        # 相A：逐流 1-token 热驻（每流独立 salt 前缀=自命中；跨流零共享）。串行发以彻底错峰。
        t0w = time.perf_counter(); warm = []
        for p in prompts:
            u = send_one(a.base_url, p, 1, max(600, a.prefix // 100))
            warm.append(u)
        warm_s = round(time.perf_counter() - t0w, 3)
    out = [None] * a.conc
    first_seen = [False] * a.conc
    def work(i):
        body = {"messages": [{"role": "user", "content": prompts[i]}],
                "max_tokens": a.max_tokens, "temperature": 0.0, "top_p": 1.0,
                "stream": True, "stream_options": {"include_usage": True}}
        chunks = []
        t_req = time.perf_counter(); t_first = None; t_last = None
        completion = prompt_tokens = None
        try:
            r = requests.post("%s/chat/completions" % a.base_url, json=body,
                              stream=True, timeout=max(600, a.max_tokens * 20))
            r.raise_for_status()
            for line in r.iter_lines(decode_unicode=False):
                if not line or not line.startswith(b"data:"):
                    continue
                payload = line[5:].strip()
                if payload == b"[DONE]":
                    break
                try:
                    j = json.loads(payload)
                except json.JSONDecodeError:
                    continue
                now = time.perf_counter()
                vis = any(ch.get("delta", {}).get("content") for ch in j.get("choices", []))
                if vis:
                    if t_first is None:
                        t_first = now
                        first_seen[i] = True   # 修：首 token 即置位（原置位于 work() 末=流完结，marker 语义错）
                    t_last = now
                    chunks.append(round(now - t_req, 4))
                u = j.get("usage")
                if u:
                    completion = u.get("completion_tokens")
                    prompt_tokens = u.get("prompt_tokens")
            out[i] = {"ok": t_first is not None and completion is not None,
                      "ttft": round(t_first - t_req, 3) if t_first else None,
                      "wall": round(t_last - t_req, 3) if t_last else None,
                      "completion": completion, "prompt_tokens": prompt_tokens,
                      "chunk_ts": chunks}
        except Exception as e:
            out[i] = {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}
        first_seen[i] = t_first is not None
    th = [threading.Thread(target=work, args=(i,)) for i in range(a.conc)]
    t0 = time.perf_counter()
    for t in th:
        t.start()
    marker_at = None
    if a.marker_file:
        while any(t.is_alive() for t in th):
            if marker_at is None and all(first_seen):
                marker_at = round(time.perf_counter() - t0, 3)
                with open(a.marker_file, "w") as f:
                    f.write("ALL-FIRST-TOKEN t=%.3f\n" % marker_at)
            time.sleep(0.2)
        if marker_at is None and all(first_seen):
            marker_at = round(time.perf_counter() - t0, 3)
            with open(a.marker_file, "w") as f:
                f.write("ALL-FIRST-TOKEN t=%.3f\n" % marker_at)
    for t in th:
        t.join()
    res = {"conc": a.conc, "prefix_target": a.prefix, "prose_mode": bool(a.prose or a.prefix <= 0),
           "max_tokens": a.max_tokens, "salt": salt, "marker_at_s": marker_at,
           "warm_prefix": bool(a.warm_prefix), "warm_phase": warm,
           "warm_phase_s": (warm_s if a.warm_prefix else None), "streams": out}
    with open(a.json_out, "w") as f:
        json.dump(res, f, ensure_ascii=False, indent=1)
    ok = sum(1 for o in out if o and o.get("ok"))
    print("DE-LOAD-DONE conc=%d ok=%d/%d marker=%s" % (a.conc, ok, a.conc, marker_at))

if __name__ == "__main__":
    main()
