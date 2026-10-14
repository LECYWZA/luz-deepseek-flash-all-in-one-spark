#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rc3.8.5 桌面测试台（AUTH-DEPLOY-20261014；零流量——全程 127.0.0.1 本地回环，
不上隧道不碰 8899/产线面）。

五型（任务书 §一.3）：
  a 无钥 /v1/chat/completions → 401（全局门工作；/health 豁免；/metrics 收钥）
  b 带钥+假模型 → 404 OpenAI 形（model_not_found；本地应答零上游载）
  c 带钥+真模型 → 放行到 stub 上游（验转发头：Authorization 透传/XFF 注入）
  d GW_REQUIRE_AUTH=0 且 GW_ALLOWED_MODELS 置空 ⇒ 与 rc3.8.4 行为逐字节等价
    （休眠门判别力；对照基准=git HEAD 的 rc3.8.4 载荷，响应 status+body 逐字节比对；
    /gw/metrics 与流式 X-Gateway 头含版本串=版本自证面，不属行为面，电池内排除）
  e 流式路径两态：无钥 401（门在早开流之前）/ 带钥真模型 SSE 全量中继 /
    带钥假模型 404（模型门先于流）

另附：/gw/metrics 新计数键（auth_rejected/models_rejected）执法。

用法：python3 tests/test_rc385.py  （自跑全绿才准部署——任务书 §一.3 门）
退出码：0=全绿 / 1=有红。SKIP 不算红（仅对照基准不可得时 d 的字节比对段跳过）。
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
PROXY_RC385 = os.path.join(PAYLOAD_DIR, "concurrency_proxy_v2.py")
REPO_ROOT = os.path.abspath(os.path.join(PAYLOAD_DIR, "..", "..", "..", ".."))

TEST_KEY = "test-gw-key-rc385-synthetic-not-a-secret-0000000"   # 47 字形对齐产线；非密
REAL_MODEL = "deepseek-v4.1-flash"
FAKE_MODEL = "no-such-model-zzz"

RESULTS: list[tuple[str, bool, str]] = []


def report(case: str, ok: bool, note: str = "") -> None:
    RESULTS.append((case, ok, note))
    print(f"[test_rc385] {'PASS' if ok else 'RED '} {case}{'  ' + note if note else ''}")


def rc384_reference(tmpdir: str) -> str | None:
    """对照基准：git HEAD 的 rc3.8.4 载荷（战役仓历史=永久基准位）。不可得→None。"""
    rel = os.path.relpath(PROXY_RC385, REPO_ROOT)
    try:
        out = subprocess.run(["git", "-C", REPO_ROOT, "show", f"HEAD:{rel}"],
                             capture_output=True, timeout=15, check=True)
        ref = os.path.join(tmpdir, "concurrency_proxy_v2.rc384.py")
        with open(ref, "wb") as f:
            f.write(out.stdout)
        return ref
    except Exception:
        return None


# ---------------------------------------------------------------- stub 上游
STUB_HITS: list[dict] = []


async def start_stub(port: int):
    from aiohttp import web

    CHAT_BODY = (b'{"id":"stub-1","object":"chat.completion","created":0,'
                 b'"model":"deepseek-v4.1-flash","choices":[{"index":0,'
                 b'"message":{"role":"assistant","content":"OK"},'
                 b'"finish_reason":"stop"}],"usage":{"prompt_tokens":1,'
                 b'"completion_tokens":1,"total_tokens":2}}')
    SSE_BODY = (b'data: {"id":"stub-s","object":"chat.completion.chunk","created":0,'
                b'"model":"deepseek-v4.1-flash","choices":[{"index":0,'
                b'"delta":{"content":"A"},"finish_reason":null}]}\n\n'
                b'data: {"id":"stub-s","object":"chat.completion.chunk","created":0,'
                b'"model":"deepseek-v4.1-flash","choices":[{"index":0,'
                b'"delta":{},"finish_reason":"stop"}]}\n\n'
                b'data: [DONE]\n\n')

    async def chat(request):
        body = await request.read()
        STUB_HITS.append({"method": request.method, "path": request.path,
                          "headers": dict(request.headers), "body": body})
        if b'"stream"' in body:
            return web.Response(status=200, body=SSE_BODY,
                                content_type="text/event-stream")
        return web.Response(status=200, body=CHAT_BODY, content_type="application/json")

    async def health(request):
        return web.json_response({"status": "ok"})

    async def models(request):
        STUB_HITS.append({"method": request.method, "path": request.path,
                          "headers": dict(request.headers), "body": b""})
        return web.json_response(
            {"object": "list",
             "data": [{"id": REAL_MODEL, "object": "model"}]})

    async def metrics(request):
        STUB_HITS.append({"method": request.method, "path": request.path,
                          "headers": dict(request.headers), "body": b""})
        return web.Response(text="# stub engine metrics\nstub_up 1\n",
                            content_type="text/plain")

    app = web.Application()
    app.router.add_post("/v1/chat/completions", chat)
    app.router.add_get("/health", health)
    app.router.add_get("/v1/models", models)
    app.router.add_get("/metrics", metrics)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "127.0.0.1", port)
    await site.start()
    return runner


class Proxy:
    """被测网关进程（rc3.8.5 / rc3.8.4 同管理面）。"""

    def __init__(self, script: str, port: int, upstream: str,
                 require_auth: str = "1", allowed_models: str = REAL_MODEL):
        env = dict(os.environ)
        env.update({
            "PORT": str(port), "UPSTREAM": upstream,
            "GW_API_KEY": TEST_KEY,
            "GW_REQUIRE_AUTH": require_auth,
            "GW_ALLOWED_MODELS": allowed_models,
            "MAX_CONCURRENCY": "4", "QUEUE_TIMEOUT": "5",
            "DEDUP_ENABLE": "0", "HEARTBEAT_INTERVAL": "30",
            "FIRST_TOKEN_TIMEOUT": "20", "CHUNK_IDLE_TIMEOUT": "20",
            "WRITE_TIMEOUT": "10", "TOTAL_STREAM_TIMEOUT": "60",
            "NONSTREAM_TOTAL_TIMEOUT": "30", "LOG_LEVEL": "WARNING",
        })
        # allowed_models=""=显式空串（模型门关）；rc3.8.4 进程不识该键，多余 env 无害
        env["GW_ALLOWED_MODELS"] = allowed_models
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


def chat_body(model: str, stream: bool = False, tag: str = "x") -> bytes:
    return json.dumps({"model": model, "max_tokens": 1, "stream": stream,
                       "messages": [{"role": "user", "content": "hi " + tag}]}).encode()


async def main() -> int:
    import aiohttp

    tmpdir = tempfile.mkdtemp(prefix="gw-rc385-test.")
    stub_port, gw_port, ref_port = 18101, 18102, 18103
    stub = await start_stub(stub_port)
    upstream = f"http://127.0.0.1:{stub_port}"
    gw = Proxy(PROXY_RC385, gw_port, upstream,
               require_auth="1", allowed_models=REAL_MODEL)
    ref = None
    red = 0
    try:
        if not await gw.wait_up(gw_port):
            report("boot", False, "rc3.8.5 网关 10s 内未起（/health 不通）")
            return 1
        report("boot", True, "rc3.8.5 网关起（GW_REQUIRE_AUTH=1）")

        # ---- a 无钥面 -------------------------------------------------
        st, body = await fetch(gw_port, "POST", "/v1/chat/completions",
                               chat_body(REAL_MODEL, tag="a"))
        try:
            got = json.loads(body)
        except Exception:
            got = None
        ok = (st == 401
              and got == {"error": {"message": "unauthorized", "type": "gw_auth"}})
        report("a1 无钥 POST /v1/chat/completions→401（体= gw_auth 形）", ok,
               f"status={st}")
        st, _ = await fetch(gw_port, "GET", "/v1/models")
        report("a2 无钥 GET /v1/models→401（名录面同门）", st == 401, f"status={st}")
        st, _ = await fetch(gw_port, "GET", "/metrics")
        report("a3 无钥 GET /metrics→401（prometheus 面收钥）", st == 401,
               f"status={st}")
        st, body = await fetch(gw_port, "GET", "/health")
        report("a4 无钥 GET /health→200（探针豁免面）",
               st == 200 and b"ok" in body, f"status={st}")
        st, _ = await fetch(gw_port, "GET", "/gw/health")
        report("a5 无钥 /gw/health→401（管理面维持原门）", st == 401, f"status={st}")

        # ---- b 带钥+假模型 --------------------------------------------
        n0 = len(STUB_HITS)
        st, body = await fetch(gw_port, "POST", "/v1/chat/completions",
                               chat_body(FAKE_MODEL, tag="b"), auth=TEST_KEY)
        want = {"error": {"message": f"The model `{FAKE_MODEL}` does not exist.",
                          "type": "invalid_request_error",
                          "code": "model_not_found"}}
        ok = (st == 404
              and json.loads(body) == want
              and len(STUB_HITS) == n0)          # 本地应答零上游载
        report("b 带钥+假模型→404 OpenAI 形+零上游载", ok, f"status={st}")

        # ---- c 带钥+真模型 → stub 上游（验转发头） ----------------------
        n0 = len(STUB_HITS)
        st, body = await fetch(gw_port, "POST", "/v1/chat/completions",
                               chat_body(REAL_MODEL, tag="c"), auth=TEST_KEY)
        hit = STUB_HITS[-1] if len(STUB_HITS) > n0 else None
        ok = (st == 200 and hit is not None
              and hit["headers"].get("Authorization") == f"Bearer {TEST_KEY}"
              and "X-Forwarded-For" in hit["headers"]
              and hit["headers"].get("Content-Type") == "application/json")
        report("c 带钥+真模型→放行 stub（Authorization 透传+XFF 注入+CT）", ok,
               f"status={st} stub_hits={len(STUB_HITS) - n0}")

        # ---- e 流式两态 ------------------------------------------------
        st, body = await fetch(gw_port, "POST", "/v1/chat/completions",
                               chat_body(REAL_MODEL, stream=True, tag="e1"))
        report("e1 流式无钥→401（门先于早开流，无 SSE 体）",
               st == 401 and b"event-stream" not in body, f"status={st}")
        n0 = len(STUB_HITS)
        st, body = await fetch(gw_port, "POST", "/v1/chat/completions",
                               chat_body(REAL_MODEL, stream=True, tag="e2"),
                               auth=TEST_KEY)
        ok = (st == 200 and b"data: [DONE]" in body and b'"delta"' in body
              and len(STUB_HITS) > n0)
        report("e2 流式带钥+真模型→SSE 全量中继（含 [DONE]）", ok, f"status={st}")
        st, body = await fetch(gw_port, "POST", "/v1/chat/completions",
                               chat_body(FAKE_MODEL, stream=True, tag="e3"),
                               auth=TEST_KEY)
        report("e3 流式带钥+假模型→404（模型门先于流）", st == 404, f"status={st}")

        # ---- 新计数键执法 ----------------------------------------------
        st, body = await fetch(gw_port, "GET", "/gw/metrics", auth=TEST_KEY)
        try:
            m = json.loads(body)
            ok = (st == 200 and m.get("auth_rejected", 0) >= 2
                  and m.get("models_rejected", 0) >= 2)
        except Exception:
            ok = False
        report("f1 /gw/metrics 新计数键 auth_rejected/models_rejected≥2", ok,
               f"status={st}")

        # ---- d 休眠门：rc3.8.4 vs rc3.8.5(GW_REQUIRE_AUTH=0, 模型门空) ---
        gw.stop()
        ref_script = rc384_reference(tmpdir)
        if ref_script is None:
            report("d0 对照基准 git HEAD(rc3.8.4) 不可得——d 字节比对段 SKIP",
                   True, "SKIP（不红；战役仓内恒可得）")
        else:
            sleeper = Proxy(PROXY_RC385, gw_port, upstream,
                            require_auth="0", allowed_models="")
            old = Proxy(ref_script, ref_port, upstream,
                        require_auth="0", allowed_models="")
            try:
                up1 = await sleeper.wait_up(gw_port)
                up2 = await old.wait_up(ref_port)
                if not (up1 and up2):
                    report("d0 双网关进程起", False,
                           f"rc385={up1} rc384={up2}")
                    return 1
                battery = [
                    ("GET", "/health", None, None),
                    ("GET", "/v1/models", None, None),
                    ("GET", "/metrics", None, None),
                    ("POST", "/v1/chat/completions", chat_body(REAL_MODEL, tag="d1"), None),
                    ("POST", "/v1/chat/completions", chat_body(FAKE_MODEL, tag="d2"), None),
                    ("POST", "/v1/chat/completions", chat_body(REAL_MODEL, tag="d3"), TEST_KEY),
                    ("POST", "/v1/chat/completions", chat_body(REAL_MODEL, stream=True, tag="d4"), None),
                    ("POST", "/v1/chat/completions", chat_body(FAKE_MODEL, stream=True, tag="d5"), TEST_KEY),
                    ("POST", "/v1/chat/completions", b"{not-json", None),  # 非法 body 原样转发
                    ("GET", "/get_server_info", None, None),               # GET 透传面
                ]
                all_ok, notes = True, []
                for i, (meth, path, bd, auth) in enumerate(battery, 1):
                    s1, b1 = await fetch(gw_port, meth, path, bd, auth)
                    s2, b2 = await fetch(ref_port, meth, path, bd, auth)
                    same = (s1 == s2) and (b1 == b2)
                    if not same:
                        all_ok = False
                        notes.append(f"#{i} {meth} {path} rc385={s1}/{len(b1)}B "
                                     f"rc384={s2}/{len(b2)}B")
                report("d 休眠门=rc3.8.4 逐字节等价（status+body 十元电池含"
                       "无钥/假模型/流式/非法body/GET透传）", all_ok,
                       "; ".join(notes) if notes else f"{len(battery)} 元全同")
            finally:
                sleeper.stop()
                old.stop()
    finally:
        gw.stop()
        await stub.cleanup()
        shutil.rmtree(tmpdir, ignore_errors=True)

    bad = [c for c, ok, _ in RESULTS if not ok]
    print(f"[test_rc385] 总结：{len(RESULTS) - len(bad)}/{len(RESULTS)} 绿"
          + (f"；红={bad}" if bad else "——全绿"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
