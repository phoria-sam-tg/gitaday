#!/usr/bin/env python3
"""Tiny path/shape-fixing proxy so SillyTavern's OpenAI client works with the
samcloud model-service.

Two mismatches it fixes:
  1. model LIST lives at /models, CHAT at /v1/chat/completions (ST uses one base)
  2. /models isn't in OpenAI {"object":"list","data":[...]} shape

So: GET /v1/models -> fetch upstream /models, normalize to OpenAI shape.
Everything else -> forward unchanged to the LEASED model-service (no inference here).

Listen :8810  ->  upstream http://localhost:8800
"""
import http.server, http.client, json

UP_HOST, UP_PORT, LISTEN = "localhost", 8800, 8810

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _hdrs(self):
        return {k: v for k, v in self.headers.items()
                if k.lower() not in ("host", "content-length", "connection")}

    def _models(self):
        ids = []
        try:
            up = http.client.HTTPConnection(UP_HOST, UP_PORT, timeout=30)
            up.request("GET", "/models", headers=self._hdrs())
            raw = up.getresponse().read(); up.close()
            d = json.loads(raw)
            cand = (d.get("data") or d.get("models") or d.get("available")
                    or (d if isinstance(d, list) else []))
            for m in cand:
                mid = (m.get("id") or m.get("name")) if isinstance(m, dict) else m
                if mid and isinstance(mid, str):
                    ids.append(mid)
        except Exception:
            pass
        # Always advertise the friendly shortname so ST's dropdown is usable.
        for must in ("qwen3.5",):
            if must not in ids:
                ids.insert(0, must)
        out = json.dumps({"object": "list",
                          "data": [{"id": i, "object": "model", "owned_by": "samcloud"} for i in ids]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(out)

    def _proxy(self):
        if self.command == "GET" and self.path.rstrip("/") == "/v1/models":
            return self._models()
        n = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(n) if n else None
        try:
            up = http.client.HTTPConnection(UP_HOST, UP_PORT, timeout=300)
            up.request(self.command, self.path, body=body, headers=self._hdrs())
            resp = up.getresponse()
        except Exception as e:
            self.send_response(502); self.end_headers(); self.wfile.write(str(e).encode()); return
        self.send_response(resp.status)
        for k, v in resp.getheaders():
            if k.lower() in ("transfer-encoding", "connection", "content-length"):
                continue
            self.send_header(k, v)
        self.send_header("Connection", "close")
        self.end_headers()
        while True:
            chunk = resp.read(8192)
            if not chunk:
                break
            try:
                self.wfile.write(chunk); self.wfile.flush()
            except Exception:
                break
        up.close()

    do_GET = _proxy
    do_POST = _proxy
    def log_message(self, *a): pass

http.server.ThreadingHTTPServer(("127.0.0.1", LISTEN), H).serve_forever()
