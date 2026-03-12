import json
import os
import sys
import urllib.error
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def load_json_request(url: str, payload: dict, headers: dict[str, str], timeout: int) -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def request_tenant_access_token(base_url: str, app_id: str, app_secret: str, timeout: int) -> str:
    response = load_json_request(
        f"{base_url}/open-apis/auth/v3/tenant_access_token/internal",
        {"app_id": app_id, "app_secret": app_secret},
        {"Content-Type": "application/json; charset=utf-8"},
        timeout,
    )
    token = response.get("tenant_access_token", "")
    if not token:
        raise ValueError(f"tenant access token missing: {response}")
    return token


def normalize_text_message(content: str) -> str:
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        return content.strip()

    text = str(data.get("text", "")).strip()
    return " ".join(text.split())


def extract_event_message(payload: dict) -> dict:
    if "challenge" in payload:
        return {"challenge": payload["challenge"]}

    event = payload.get("event") or {}
    header = payload.get("header") or {}
    event_type = header.get("event_type") or payload.get("type") or ""
    message = event.get("message") or {}
    sender = event.get("sender") or {}

    return {
        "event_type": event_type,
        "message_id": message.get("message_id", ""),
        "chat_id": message.get("chat_id", ""),
        "chat_type": message.get("chat_type", ""),
        "message_type": message.get("message_type", ""),
        "content": normalize_text_message(message.get("content", "")),
        "mentions": message.get("mentions", []) if isinstance(message.get("mentions"), list) else [],
        "open_id": ((sender.get("sender_id") or {}).get("open_id", "")),
        "user_id": ((sender.get("sender_id") or {}).get("user_id", "")),
    }


def call_local_chat_api(chat_api_url: str, token: str, message: str, timeout: int) -> dict:
    headers = {"Content-Type": "application/json; charset=utf-8"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    return load_json_request(
        f"{chat_api_url}/v1/chat",
        {"message": message, "source": "feishu-openclaw"},
        headers,
        timeout,
    )


def summarize_chat_result(result: dict) -> str:
    route = result.get("route") or {}
    data = result.get("result") or {}
    stdout = str(data.get("stdout", "")).strip()
    stderr = str(data.get("stderr", "")).strip()

    if route.get("action") in {"modify", "create"} and stdout:
        try:
            parsed = json.loads(stdout)
        except json.JSONDecodeError:
            parsed = None
        if isinstance(parsed, dict):
            status = parsed.get("status", "unknown")
            summary = parsed.get("summary", "").strip()
            request_id = parsed.get("request_id", "").strip()
            if summary:
                return f"[{status}] {summary}\nrequest_id: {request_id}".strip()

    if stdout:
        return stdout[:4000]
    if stderr:
        return f"[failed] {stderr[:4000]}"
    return "[empty response]"


def send_feishu_text_message(
    base_url: str,
    tenant_access_token: str,
    chat_id: str,
    text: str,
    timeout: int,
) -> dict:
    payload = {
        "receive_id": chat_id,
        "msg_type": "text",
        "content": json.dumps({"text": text}, ensure_ascii=False),
    }
    return load_json_request(
        f"{base_url}/open-apis/im/v1/messages?receive_id_type=chat_id",
        payload,
        {
            "Content-Type": "application/json; charset=utf-8",
            "Authorization": f"Bearer {tenant_access_token}",
        },
        timeout,
    )


class FeishuOpenClawHandler(BaseHTTPRequestHandler):
    server_version = "FeishuOpenClawAdapter/0.1"

    @property
    def config(self) -> dict:
        return getattr(self.server, "config", {})

    def _write_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict:
        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length)
        if not raw_body:
            return {}
        return json.loads(raw_body.decode("utf-8"))

    def do_GET(self) -> None:
        if self.path != "/health":
            self._write_json(HTTPStatus.NOT_FOUND, {"status": "not_found"})
            return

        self._write_json(
            HTTPStatus.OK,
            {
                "status": "ok",
                "chat_api_url": self.config["chat_api_url"],
                "app_id_configured": bool(self.config["app_id"]),
                "app_secret_configured": bool(self.config["app_secret"]),
            },
        )

    def do_POST(self) -> None:
        if self.path not in {"/feishu/events", "/webhook/feishu"}:
            self._write_json(HTTPStatus.NOT_FOUND, {"status": "not_found"})
            return

        try:
            payload = self._read_json()
            event = extract_event_message(payload)
        except json.JSONDecodeError as exc:
            self._write_json(HTTPStatus.BAD_REQUEST, {"status": "bad_request", "message": str(exc)})
            return

        if "challenge" in event:
            self._write_json(HTTPStatus.OK, {"challenge": event["challenge"]})
            return

        if event.get("message_type") != "text":
            self._write_json(HTTPStatus.OK, {"status": "ignored", "reason": "non-text message"})
            return

        if event.get("chat_type") != "group":
            self._write_json(HTTPStatus.OK, {"status": "ignored", "reason": "non-group message"})
            return

        if self.config["group_require_mention"] and not event.get("mentions"):
            self._write_json(HTTPStatus.OK, {"status": "ignored", "reason": "group mention required"})
            return

        if not event.get("content"):
            self._write_json(HTTPStatus.OK, {"status": "ignored", "reason": "empty text"})
            return

        try:
            chat_response = call_local_chat_api(
                self.config["chat_api_url"],
                self.config["chat_api_token"],
                event["content"],
                self.config["timeout_seconds"],
            )
            text = summarize_chat_result(chat_response)
            tenant_access_token = request_tenant_access_token(
                self.config["feishu_base_url"],
                self.config["app_id"],
                self.config["app_secret"],
                self.config["timeout_seconds"],
            )
            reply = send_feishu_text_message(
                self.config["feishu_base_url"],
                tenant_access_token,
                event["chat_id"],
                text,
                self.config["timeout_seconds"],
            )
        except (urllib.error.URLError, ValueError) as exc:
            self._write_json(
                HTTPStatus.BAD_GATEWAY,
                {"status": "failed", "message": str(exc), "event": event},
            )
            return

        self._write_json(
            HTTPStatus.OK,
            {
                "status": "ok",
                "event_type": event.get("event_type", ""),
                "message_id": event.get("message_id", ""),
                "reply_result": reply,
            },
        )

    def log_message(self, fmt: str, *args: object) -> None:
        sys.stderr.write(f"[feishu-openclaw-adapter] {self.address_string()} - {fmt % args}\n")


def main() -> None:
    host = os.environ.get("FEISHU_OPENCLAW_HOST", "127.0.0.1")
    port = int(os.environ.get("FEISHU_OPENCLAW_PORT", "18989"))
    config = {
        "feishu_base_url": os.environ.get("FEISHU_BASE_URL", "https://open.feishu.cn"),
        "app_id": os.environ.get("FEISHU_APP_ID", ""),
        "app_secret": os.environ.get("FEISHU_APP_SECRET", ""),
        "chat_api_url": os.environ.get("OPENCLAW_CHAT_API_URL", "http://127.0.0.1:18889"),
        "chat_api_token": os.environ.get("OPENCLAW_CHAT_API_TOKEN", ""),
        "timeout_seconds": int(os.environ.get("FEISHU_OPENCLAW_TIMEOUT_SECONDS", "120")),
        "group_require_mention": os.environ.get("FEISHU_GROUP_REQUIRE_MENTION", "true").lower() != "false",
    }

    server = ThreadingHTTPServer((host, port), FeishuOpenClawHandler)
    server.config = config

    print(f"[feishu-openclaw-adapter] listening on http://{host}:{port}")
    print(f"[feishu-openclaw-adapter] chat_api: {config['chat_api_url']}")
    print(f"[feishu-openclaw-adapter] feishu_base_url: {config['feishu_base_url']}")
    print(f"[feishu-openclaw-adapter] group_require_mention: {config['group_require_mention']}")
    if not config["app_id"] or not config["app_secret"]:
        print("[feishu-openclaw-adapter] warning: FEISHU_APP_ID / FEISHU_APP_SECRET not configured")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
