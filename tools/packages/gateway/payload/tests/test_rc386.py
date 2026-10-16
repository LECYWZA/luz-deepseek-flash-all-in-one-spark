#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rc3.8.6 桌面测试台（GW-PATCH-20261015 窗；零流量——全程 127.0.0.1 本地回环，
不上隧道不碰 8899/产线面）。

被测=②-a 响应侧容量广播（ADVERTISE_MODEL_CAPACITY，A10 / GitHub issue #3）：
  GET /v1/models 与 /v1/models/{id} 的响应体在每个 model 条目补客户端模型发现
  四键（context_length / context_window / max_input_tokens / limit.context），
  取值=条目自带 max_model_len（引擎真值，不写死）。

用例（G3 三硬门 + G4 不写死 + 活引擎实况夹具）：
  a 开关开+列表形：多条目（600000 / 131072）四键各自随 max_model_len（不写死
    判别力）；原字段语义逐项保留（纯增量）；缺 max_model_len 的 LoRA 行零触碰。
  b 开关开+单卡形（/v1/models/{id}）：四键=该卡 max_model_len。
  c 幂等：已带字段的响应入 → 与 stub 原始字节**逐字节**同出。
  d 开关关（缺省 0）对 rc3.8.5 判别力电池：GW_REQUIRE_AUTH=0 ⇒ 与内容寻址
    的 rc3.8.5 载荷 status+body 逐字节等价（九元电池含 /v1/models 目标路径）。
  e fail-open 三型：非法 JSON / 无 max_model_len（LoRA 行）/ 非目标路径
    （/get_server_info）——全部原样透传（逐字节同），绝不因本变换回 500。
  f 非目标方法与路径：POST /v1/chat/completions 响应不改写；HEAD /v1/models
    原样透传（无体）。
  g 覆盖位：MODELS_CONTEXT_LEN=262144（应急面）⇒ 四键=覆盖值（非条目值）。
  h 活引擎实况夹具：本窗 8899 实捕获字节（engine-models-1.json 形）经网关 →
    四键全=600000；低估值条目（131072）纠正面在 a。
  另附：/gw/metrics 回归面（新变换零涉）。

用法：python3 tests/test_rc386.py  （自跑全绿才准部署——同 rc385 门）
退出码：0=全绿 / 1=有红。SKIP 不算红（仅 rc3.8.5 对照基准不可得时 d 段跳过）。
"""
import asyncio
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))            # .../payload/tests
PAYLOAD_DIR = os.path.dirname(HERE)                          # .../payload
PROXY_RC386 = os.path.join(PAYLOAD_DIR, "concurrency_proxy_v2.py")
REPO_ROOT = os.path.abspath(os.path.join(PAYLOAD_DIR, "..", "..", "..", ".."))

TEST_KEY = "test-gw-key-rc386-synthetic-not-a-secret-0000000"   # 47 字形对齐产线；非密
REAL_MODEL = "deepseek-v4.1-flash"

RESULTS: list[tuple[str, bool, str]] = []


def report(case: str, ok: bool, note: str = "") -> None:
    RESULTS.append((case, ok, note))
    print(f"[test_rc386] {'PASS' if ok else 'RED '} {case}{'  ' + note if note else ''}")


RC385_MD5 = "3e714a0ba596df9016ce105e5c1571cb"     # rc3.8.5 权威锚（内容寻址，不随 HEAD 漂移）


def rc385_reference(tmpdir: str) -> str | None:
    """对照基准：rc3.8.5 载荷（按内容 md5 寻址——git 历史内检索 md5 恰等于
    3e714a0b… 的历史 blob；HEAD 推进后仍稳定可寻）。不可得→None（d 段 SKIP）。"""
    env_ref = os.environ.get("RC385_REF", "")
    if env_ref and os.path.isfile(env_ref):
        ref = os.path.join(tmpdir, "rc385.py")
        shutil.copy(env_ref, ref)
        return ref
    rel = os.path.relpath(PROXY_RC386, REPO_ROOT)
    try:
        import hashlib
        commits = subprocess.run(
            ["git", "-C", REPO_ROOT, "log", "--format=%H", "-n", "50", "--", rel],
            capture_output=True, timeout=15, check=True).stdout.decode().split()
        for c in commits:
            blob = subprocess.run(["git", "-C", REPO_ROOT, "show", f"{c}:{rel}"],
                                  capture_output=True, timeout=15, check=True).stdout
            if hashlib.md5(blob).hexdigest() == RC385_MD5:
                ref = os.path.join(tmpdir, "concurrency_proxy_v2.rc385.py")
                with open(ref, "wb") as f:
                    f.write(blob)
                return ref
    except Exception:
        pass
    return None


# ---------------------------------------------------------------- 夹具（上游字节）
# 活引擎实况夹具：本窗 2026-10-15 自 8899 实捕获（/v1/models；created=请求时刻值
# 原样保留）——字段集与 issue #3 实测 7 字段逐字一致。
LIVE_FIXTURE = (b'{"object":"list","data":[{"id":"deepseek-v4.1-flash","object":"model",'
                b'"created":1792108401,"owned_by":"sglang","root":"deepseek-v4.1-flash",'
                b'"parent":null,"max_model_len":600000}]}')
# 双条目形（600000 + 低值 131072=不写死判别力）+ LoRA 行（无 max_model_len）
MULTI_FIXTURE = json.dumps({
    "object": "list",
    "data": [
        {"id": "deepseek-v4.1-flash", "object": "model", "created": 1792108401,
         "owned_by": "sglang", "root": "deepseek-v4.1-flash", "parent": None,
         "max_model_len": 600000},
        {"id": "deepseek-v4.1-flash-small", "object": "model", "created": 1,
         "owned_by": "sglang", "root": "deepseek-v4.1-flash-small",
         "parent": None, "max_model_len": 131072},
        {"id": "lora-row-zzz", "object": "model", "created": 1,
         "owned_by": "sglang", "root": "lora-row-zzz", "parent": None},
    ],
}, ensure_ascii=False, separators=(",", ":")).encode()
BARE_CARD = json.dumps({
    "id": REAL_MODEL, "object": "model", "created": 1792108401, "owned_by": "sglang",
    "root": REAL_MODEL, "parent": None, "max_model_len": 600000,
}, ensure_ascii=False, separators=(",", ":")).encode()
LORA_ONLY = json.dumps({
    "object": "list",
    "data": [{"id": "lora-row-zzz", "object": "model", "created": 1,
              "owned_by": "sglang"}],
}, ensure_ascii=False, separators=(",", ":")).encode()
BAD_JSON = b'{"object":"list","data":[{"id":'          # 非法 JSON（截断）
SERVER_INFO = b'{"model_path":"/models/deepseek-v4.1-flash","context_len":600000}'
CHAT_BODY = (b'{"id":"stub-1","object":"chat.completion","created":0,'
             b'"model":"deepseek-v4.1-flash","choices":[{"index":0,'
             b'"message":{"role":"assistant","content":"OK"},'
             b'"finish_reason":"stop"}],"usage":{"prompt_tokens":1,'
             b'"completion_tokens":1,"total_tokens":2}}')


def already_fields(body: bytes) -> bytes:
    """构造「已带四键」形（幂等夹具）：把 LIST 形逐条目补键（值=其 max_model_len）
    并重序列化作 stub 出体——经网关必须逐字节原样出。"""
    doc = json.loads(body)
    for ent in doc["data"]:
        if isinstance(ent.get("max_model_len"), int):
            for k in ("context_length", "context_window", "max_input_tokens"):
                ent.setdefault(k, ent["max_model_len"])
            ent.setdefault("limit", {})["context"] = ent["max_model_len"]
    return json.dumps(doc, ensure_ascii=False, separators=(",", ":")).encode()


# ---------------------------------------------------------------- stub 上游
STUB_HITS: list[dict] = []


async def start_stub(port: int):
    from aiohttp import web

    async def models(request):
        STUB_HITS.append({"method": request.method, "path": request.path})
        return web.Response(status=200, body=LIVE_FIXTURE,
                            content_type="application/json")

    async def models_multi(request):
        STUB_HITS.append({"method": request.method, "path": request.path})
        return web.Response(status=200, body=MULTI_FIXTURE,
                            content_type="application/json")

    async def models_bf(request):        # already-has-fields（幂等夹具入）
        STUB_HITS.append({"method": request.method, "path": request.path})
        return web.Response(status=200, body=already_fields(MULTI_FIXTURE),
                            content_type="application/json")

    async def models_id(request):
        STUB_HITS.append({"method": request.method, "path": request.path})
        return web.Response(status=200, body=BARE_CARD,
                            content_type="application/json")

    async def models_lora(request):
        STUB_HITS.append({"method": request.method, "path": request.path})
        return web.Response(status=200, body=LORA_ONLY,
                            content_type="application/json")

    async def models_bad(request):
        STUB_HITS.append({"method": request.method, "path": request.path})
        return web.Response(status=200, body=BAD_JSON,
                            content_type="application/json")

    async def server_info(request):
        STUB_HITS.append({"method": request.method, "path": request.path})
        return web.Response(status=200, body=SERVER_INFO,
                            content_type="application/json")

    async def chat(request):
        STUB_HITS.append({"method": request.method, "path": request.path})
        return web.Response(status=200, body=CHAT_BODY,
                            content_type="application/json")

    async def health(request):
        return web.json_response({"status": "ok"})

    async def metrics(request):
        return web.Response(text="# stub engine metrics\nstub_up 1\n",
                            content_type="text/plain")

    app = web.Application()
    app.router.add_route("*", "/v1/models", models)
    app.router.add_route("*", "/v1/models/multi", models_multi)
    app.router.add_route("*", "/v1/models/bf", models_bf)
    app.router.add_route("*", "/v1/models/lora-only", models_lora)
    app.router.add_route("*", "/v1/models/bad", models_bad)
    app.router.add_route("*", "/v1/models/deepseek-v4.1-flash", models_id)
    app.router.add_route("*", "/get_server_info", server_info)
    app.router.add_route("*", "/v1/chat/completions", chat)
    app.router.add_route("*", "/health", health)
    app.router.add_route("*", "/metrics", metrics)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "127.0.0.1", port)
    await site.start()
    return runner


class Proxy:
    """被测网关进程（rc3.8.6 / rc3.8.5 同管理面）。"""

    def __init__(self, script: str, port: int, upstream: str,
                 advertise: str = "0", models_ctx: str = "0",
                 require_auth: str = "0"):
        env = dict(os.environ)
        env.update({
            "PORT": str(port), "UPSTREAM": upstream,
            "GW_API_KEY": TEST_KEY,
            "GW_REQUIRE_AUTH": require_auth,
            "GW_ALLOWED_MODELS": "",
            "ADVERTISE_MODEL_CAPACITY": advertise,     # rc3.8.5 不识该键=多余 env 无害
            "MODELS_CONTEXT_LEN": models_ctx,
            "MAX_CONCURRENCY": "4", "QUEUE_TIMEOUT": "5",
            "DEDUP_ENABLE": "0", "HEARTBEAT_INTERVAL": "30",
            "FIRST_TOKEN_TIMEOUT": "20", "CHUNK_IDLE_TIMEOUT": "20",
            "WRITE_TIMEOUT": "10", "TOTAL_STREAM_TIMEOUT": "60",
            "NONSTREAM_TOTAL_TIMEOUT": "30", "LOG_LEVEL": "WARNING",
        })
        self.proc = subprocess.Popen(
            [sys.executable, "-u", script], env=env,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    async def wait_up(self, port: int, timeout: float = 10.0) -> bool:
        import aiohttp
        t0 = asyncio.get_event_loop().time()
        async with aiohttp.ClientSession() as s:
            while asyncio.get_event_loop().time() - t0 < timeout:
                try:
                    async with s.get(f"http://127.0.0.1:{port}/health",
                                     timeout=aiohttp.ClientTimeout(total=1)) as r:
                        if r.status == 200:
                            return True
                except Exception:
                    await asyncio.sleep(0.15)
        return False

    def stop(self) -> None:
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()


async def fetch(port: int, method: str, path: str, body: bytes | None = None,
                auth: str | None = None, timeout: float = 15.0):
    """返回 (status, body_bytes)。"""
    import aiohttp
    headers = {"Content-Type": "application/json"}
    if auth:
        headers["Authorization"] = f"Bearer {auth}"
    async with aiohttp.ClientSession() as s:
        async with s.request(method, f"http://127.0.0.1:{port}{path}",
                             data=body, headers=headers,
                             timeout=aiohttp.ClientTimeout(total=timeout)) as r:
            return r.status, await r.read()


def cap4(ent: dict) -> dict:
    """取四键（三扁平+limit.context）。"""
    out = {k: ent.get(k) for k in ("context_length", "context_window", "max_input_tokens")}
    lim = ent.get("limit")
    out["limit.context"] = lim.get("context") if isinstance(lim, dict) else None
    return out


def entries_of(body: bytes) -> list:
    return json.loads(body)["data"]


async def main() -> int:
    tmpdir = tempfile.mkdtemp(prefix="gw-rc386-test.")
    stub_port, gw_port, ref_port = 18515, 18516, 18517     # 本窗端口纪律 18515-18530
    stub = await start_stub(stub_port)
    upstream = f"http://127.0.0.1:{stub_port}"
    gw = Proxy(PROXY_RC386, gw_port, upstream, advertise="1")
    gw_off = None
    try:
        if not await gw.wait_up(gw_port):
            report("boot", False, "rc3.8.6 网关 10s 内未起（/health 不通）")
            return 1
        report("boot", True, "rc3.8.6 网关起（ADVERTISE_MODEL_CAPACITY=1）")

        # ---- a 开关开+列表形（不写死判别力+纯增量+LoRA 行零触碰） --------
        st, body = await fetch(gw_port, "GET", "/v1/models/multi")
        src = entries_of(MULTI_FIXTURE)
        try:
            ents = entries_of(body)
            ok = (st == 200 and len(ents) == 3
                  and cap4(ents[0]) == {"context_length": 600000, "context_window": 600000,
                                        "max_input_tokens": 600000, "limit.context": 600000}
                  and cap4(ents[1]) == {"context_length": 131072, "context_window": 131072,
                                        "max_input_tokens": 131072, "limit.context": 131072}
                  and set(ents[2].keys()) == set(src[2].keys())
                  and all(v is None for v in cap4(ents[2]).values()))
        except Exception:
            ok = False
        report("a1 列表形：四键各自随 max_model_len（600000/131072=不写死）+LoRA 行零触碰",
               ok, f"status={st}")
        ok = (len(ents) == len(src)
              and all(all(e.get(k) == s.get(k) for k in s)
                      for e, s in zip(ents, src)))
        report("a2 纯增量：原字段逐项保留（含父/根/created/owned_by）", ok)

        # ---- b 单卡形（/v1/models/{id}） --------------------------------
        st, body = await fetch(gw_port, "GET", f"/v1/models/{REAL_MODEL}")
        try:
            ent = json.loads(body)
            ok = (st == 200 and ent.get("id") == REAL_MODEL
                  and cap4(ent) == {"context_length": 600000, "context_window": 600000,
                                    "max_input_tokens": 600000, "limit.context": 600000})
        except Exception:
            ok = False
        report("b 单卡形 /v1/models/{id}：四键=该卡 max_model_len(600000)", ok,
               f"status={st}")

        # ---- c 幂等：已带字段入=逐字节出 ---------------------------------
        st, body = await fetch(gw_port, "GET", "/v1/models/bf")
        want = already_fields(MULTI_FIXTURE)
        report(f"c 幂等：已带字段响应=逐字节原样出（{len(want)}B）",
               st == 200 and body == want, f"status={st} bytes={len(body)}")

        # ---- e fail-open 三型（目标路径下异常面） ------------------------
        st, body = await fetch(gw_port, "GET", "/v1/models/bad")
        report("e1 fail-open：非法 JSON=原样透传（200+同字节）",
               st == 200 and body == BAD_JSON, f"status={st}")
        st, body = await fetch(gw_port, "GET", "/v1/models/lora-only")
        report("e2 fail-open：无 max_model_len（LoRA 行）=逐字节原样",
               st == 200 and body == LORA_ONLY, f"status={st}")
        st, body = await fetch(gw_port, "GET", "/get_server_info")
        report("e3 fail-open：非目标路径=逐字节原样（开关开态）",
               st == 200 and body == SERVER_INFO, f"status={st}")

        # ---- f 非目标方法/POST 响应不改写+HEAD 透传 ----------------------
        n0 = len(STUB_HITS)
        st, body = await fetch(gw_port, "POST", "/v1/chat/completions",
                               json.dumps({"model": REAL_MODEL, "messages": []}).encode())
        report("f1 POST /v1/chat/completions 响应零改写（逐字节同 stub）",
               st == 200 and body == CHAT_BODY and len(STUB_HITS) > n0, f"status={st}")
        st, body = await fetch(gw_port, "HEAD", "/v1/models")
        report("f2 HEAD /v1/models 原样透传（200+无体）",
               st == 200 and body == b"", f"status={st} bytes={len(body)}")

        # ---- g 覆盖位（应急面语义） --------------------------------------
        gw.stop()
        gwo = Proxy(PROXY_RC386, gw_port, upstream, advertise="1", models_ctx="262144")
        if await gwo.wait_up(gw_port):
            st, body = await fetch(gw_port, "GET", "/v1/models/multi")
            try:
                ok = (st == 200 and cap4(entries_of(body)[0])["context_length"] == 262144
                      and entries_of(body)[0]["max_model_len"] == 600000)
            except Exception:
                ok = False
            report("g 覆盖位 MODELS_CONTEXT_LEN=262144：四键=覆盖值（条目值原样）", ok,
                   f"status={st}")
        else:
            report("g 覆盖位", False, "覆盖位实例未起")
        gwo.stop()

        # ---- h 活引擎实况夹具：经网关 → 四键全 600000 ---------------------
        gwh = Proxy(PROXY_RC386, gw_port, upstream, advertise="1")
        if await gwh.wait_up(gw_port):
            st, body = await fetch(gw_port, "GET", "/v1/models")
            try:
                ent = entries_of(body)[0]
                ok = (st == 200 and cap4(ent) == {"context_length": 600000,
                                                  "context_window": 600000,
                                                  "max_input_tokens": 600000,
                                                  "limit.context": 600000}
                      and ent["max_model_len"] == 600000)
            except Exception:
                ok = False
            report("h 活引擎实况夹具（本窗 8899 实捕获形）：四键全=600000", ok,
                   f"status={st}")
        else:
            report("h 活夹具", False, "实例未起")
        gwh.stop()

        # ---- 回归面：/gw/metrics 可服务 ----------------------------------
        gwr = Proxy(PROXY_RC386, gw_port, upstream, advertise="1")
        if await gwr.wait_up(gw_port):
            st, body = await fetch(gw_port, "GET", "/gw/metrics", auth=TEST_KEY)
            ok = False
            try:
                m = json.loads(body)
                ok = (st == 200 and m.get("version", "").endswith("rc3.8.6"))
            except Exception:
                pass
            report("i /gw/metrics 回归面（version=rc3.8.6）", ok, f"status={st}")
        else:
            report("i 回归面", False, "实例未起")
        gwr.stop()

        # ---- d 开关关（缺省）对 rc3.8.5 判别力电池 ------------------------
        ref_script = rc385_reference(tmpdir)
        if ref_script is None:
            report("d0 rc3.8.5 对照基准不可得——d 字节比对段 SKIP", True,
                   "SKIP（不红；两仓内恒可得）")
        else:
            new = Proxy(PROXY_RC386, gw_port, upstream, advertise="0")
            old = Proxy(ref_script, ref_port, upstream, advertise="0")
            try:
                up1 = await new.wait_up(gw_port)
                up2 = await old.wait_up(ref_port)
                if not (up1 and up2):
                    report("d0 双网关进程起", False, f"rc386={up1} rc385={up2}")
                    return 1
                battery = [
                    ("GET", "/health"),
                    ("GET", "/v1/models"),                      # 目标路径（关态零改动）
                    ("GET", f"/v1/models/{REAL_MODEL}"),        # 单卡形
                    ("GET", "/v1/models/multi"),
                    ("GET", "/get_server_info"),
                    ("GET", "/metrics"),
                    ("POST", "/v1/chat/completions"),           # 非流式
                    ("HEAD", "/v1/models"),
                ]
                all_ok, notes = True, []
                for meth, path in battery:
                    bd = json.dumps({"model": REAL_MODEL, "messages": [],
                                     "stream": False}).encode() if meth == "POST" else None
                    s1, b1 = await fetch(gw_port, meth, path, bd)
                    s2, b2 = await fetch(ref_port, meth, path, bd)
                    if not ((s1 == s2) and (b1 == b2)):
                        all_ok = False
                        notes.append(f"{meth} {path} rc386={s1}/{len(b1)}B "
                                     f"rc385={s2}/{len(b2)}B")
                report("d 开关关=rc3.8.5 逐字节等价（八元电池含目标路径/单卡/POST/HEAD）",
                       all_ok, "; ".join(notes) if notes else f"{len(battery)} 元全同")
            finally:
                new.stop()
                old.stop()
    finally:
        gw.stop()
        if gw_off is not None:
            gw_off.stop()
        await stub.cleanup()
        shutil.rmtree(tmpdir, ignore_errors=True)

    bad = [c for c, ok, _ in RESULTS if not ok]
    print(f"[test_rc386] 总结：{len(RESULTS) - len(bad)}/{len(RESULTS)} 绿"
          + (f"；红={bad}" if bad else "——全绿"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
