import json
import os
import sys
import urllib.error
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urljoin


def strip_unsupported_fields(value):
    if isinstance(value, dict):
        return {
            key: strip_unsupported_fields(inner)
            for key, inner in value.items()
            if key not in {"prompt_cache_key"}
        }
    if isinstance(value, list):
        return [strip_unsupported_fields(item) for item in value]
    return value


class ProxyHandler(BaseHTTPRequestHandler):
    server_version = "VolcengineCompatProxy/0.1"

    @property
    def upstream_base(self) -> str:
        return getattr(self.server, "upstream_base")

    @property
    def api_key(self) -> str:
        return getattr(self.server, "api_key")

    @property
    def timeout_seconds(self) -> int:
        return getattr(self.server, "timeout_seconds")

    def _write_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _write_raw(self, status: int, body: bytes, content_type: str = "application/json; charset=utf-8") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path == "/health":
            self._write_json(
                HTTPStatus.OK,
                {
                    "status": "ok",
                    "upstream_base": self.upstream_base,
                    "api_key_configured": bool(self.api_key),
                },
            )
            return

        self._proxy_request()

    def do_POST(self) -> None:
        self._proxy_request()

    def _proxy_request(self) -> None:
        upstream_url = urljoin(f"{self.upstream_base.rstrip('/')}/", self.path.lstrip("/"))
        content_length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(content_length) if content_length > 0 else b""
        content_type = self.headers.get("Content-Type", "application/json")

        if body and "application/json" in content_type:
            try:
                payload = json.loads(body.decode("utf-8"))
                payload = strip_unsupported_fields(payload)
                body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            except json.JSONDecodeError:
                pass

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": content_type,
        }

        request = urllib.request.Request(
            upstream_url,
            data=body if self.command in {"POST", "PUT", "PATCH"} else None,
            headers=headers,
            method=self.command,
        )

        try:
            with urllib.request.urlopen(request, timeout=self.timeout_seconds) as response:
                response_body = response.read()
                response_type = response.headers.get("Content-Type", "application/json; charset=utf-8")
                self._write_raw(response.status, response_body, response_type)
        except urllib.error.HTTPError as exc:
            error_body = exc.read()
            response_type = exc.headers.get("Content-Type", "application/json; charset=utf-8")
            self._write_raw(exc.code, error_body, response_type)
        except urllib.error.URLError as exc:
            self._write_json(HTTPStatus.BAD_GATEWAY, {"status": "failed", "message": str(exc)})

    def log_message(self, fmt: str, *args: object) -> None:
        sys.stderr.write(f"[volcengine-compat-proxy] {self.address_string()} - {fmt % args}\n")


def main() -> None:
    host = os.environ.get("VOLCENGINE_PROXY_HOST", "127.0.0.1")
    port = int(os.environ.get("VOLCENGINE_PROXY_PORT", "19090"))
    upstream_base = os.environ.get("VOLCENGINE_PROXY_UPSTREAM_BASE", "https://ark.cn-beijing.volces.com")
    api_key = os.environ.get("VOLCENGINE_PROXY_API_KEY", "")
    timeout_seconds = int(os.environ.get("VOLCENGINE_PROXY_TIMEOUT_SECONDS", "120"))

    server = ThreadingHTTPServer((host, port), ProxyHandler)
    server.upstream_base = upstream_base
    server.api_key = api_key
    server.timeout_seconds = timeout_seconds

    print(f"[volcengine-compat-proxy] listening on http://{host}:{port}")
    print(f"[volcengine-compat-proxy] upstream: {upstream_base}")
    print("[volcengine-compat-proxy] strips: prompt_cache_key")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
