import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional


ROOT_DIR = Path(__file__).resolve().parent.parent
ROUTER_SCRIPT = ROOT_DIR / "scripts" / "openclaw-router.sh"


@dataclass
class ChatRoute:
    action: str
    target: str = ""
    value: str = ""
    instruction: str = ""
    source: str = "openclaw-local-chat"
    mode: str = "auto"
    reason: str = ""


def _extract_mode(message: str) -> str:
    lowered = message.lower()
    if "昨天" in message or "yesterday" in lowered:
        return "yesterday"
    if "今天" in message or "today" in lowered:
        return "today"
    if "最近" in message or "recent" in lowered:
        return "recent"
    if "最新" in message or "latest" in lowered:
        return "latest"
    return "latest"


def _extract_futures_symbol(message: str) -> str:
    pattern = re.compile(r"\b([A-Za-z]{1,4}\d{0,4})\b")
    for match in pattern.finditer(message):
        value = match.group(1)
        lowered = value.lower()
        if lowered in {"query", "explain", "trigger", "modify", "create", "latest", "today", "recent"}:
            continue
        return value.lower()
    return ""


def _normalize_value(target: str, value_text: str, message: str) -> str:
    combined = " ".join(part for part in (value_text, message) if part)
    if target == "futures":
        return _extract_futures_symbol(combined) or "a0"

    lowered = combined.lower()
    if "昨天" in combined or "yesterday" in lowered:
        return "yesterday"
    if "今天" in combined or "today" in lowered:
        return "today"
    if "最近" in combined or "recent" in lowered:
        return "recent"
    if "最新" in combined or "latest" in lowered:
        return "latest"
    return "latest"


def _resolve_target(message: str) -> str:
    lowered = message.lower()
    if any(keyword in message for keyword in ("健康", "状态")) or "health" in lowered:
        return "health"
    if any(keyword in message for keyword in ("期货",)) or _extract_futures_symbol(message):
        return "futures"
    if any(keyword in message for keyword in ("新闻", "新鲜事", "热点", "舆情")) or "news" in lowered:
        return "news"
    if any(keyword in message for keyword in ("股票", "个股")) or "stock" in lowered:
        return "stock"
    if any(keyword in message for keyword in ("汇总", "统一", "日报", "简报")):
        return "unified"
    return "unified"


def _normalize_action(action_text: str, message: str, target_text: str, instruction_text: str) -> str:
    combined = " ".join(
        part for part in (action_text, message, target_text, instruction_text) if part
    ).lower()
    combined_zh = " ".join(part for part in (action_text, message, target_text, instruction_text) if part)

    if any(keyword in combined_zh for keyword in ("新增", "新建", "创建", "加一个功能", "加个功能", "增加模块", "新增项目")):
        return "create"
    if any(keyword in combined_zh for keyword in ("修改", "改", "优化", "修复", "压缩", "缩短", "精简", "调整")):
        return "modify"
    if any(keyword in combined_zh for keyword in ("解释", "解读", "分析", "怎么看", "怎么理解", "顺便解释", "解析")):
        return "explain"
    if any(keyword in combined_zh for keyword in ("触发", "执行", "运行", "发送", "重跑", "重新生成")):
        return "trigger"
    if any(keyword in combined_zh for keyword in ("查询", "查看", "看看", "获取", "搜索")):
        return "query"
    if "create" in combined:
        return "create"
    if "modify" in combined or "update" in combined or "optimize" in combined or "shorten" in combined:
        return "modify"
    if "trigger" in combined or "run" in combined:
        return "trigger"
    if "explain" in combined or "analy" in combined or "interpret" in combined:
        return "explain"
    if "query" in combined or "search" in combined or "look up" in combined:
        return "query"
    return ""


def _normalize_target(target_text: str, message: str, instruction_text: str) -> str:
    combined = " ".join(part for part in (target_text, message, instruction_text) if part)
    return _resolve_target(combined)


def infer_route(message: str) -> ChatRoute:
    text = message.strip()
    lowered = text.lower()

    if any(keyword in text for keyword in ("新增", "创建", "新建", "加个功能", "加一个功能")) or "create " in lowered:
        return ChatRoute(action="create", instruction=text, reason="matched create keywords")

    if any(keyword in text for keyword in ("修改", "改一下", "改成", "优化", "修复", "补一下", "更新文档")) or "modify " in lowered:
        return ChatRoute(action="modify", instruction=text, reason="matched modify keywords")

    if any(keyword in text for keyword in ("触发", "运行", "执行", "重新生成", "马上发", "立即发送")) or "trigger" in lowered:
        target = _resolve_target(text)
        value = _extract_futures_symbol(text) if target == "futures" else _extract_mode(text)
        return ChatRoute(action="trigger", target=target, value=value, reason="matched trigger keywords")

    if any(keyword in text for keyword in ("解释", "怎么看", "怎么理解", "说明一下", "解读")) or "explain" in lowered:
        target = _resolve_target(text)
        value = _extract_futures_symbol(text) if target == "futures" else _extract_mode(text)
        return ChatRoute(action="explain", target=target, value=value, reason="matched explain keywords")

    target = _resolve_target(text)
    value = _extract_futures_symbol(text) if target == "futures" else _extract_mode(text)
    return ChatRoute(action="query", target=target, value=value, reason="defaulted to query")


def llm_route_message(message: str) -> Optional[ChatRoute]:
    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    base_url = os.environ.get("OPENAI_BASE_URL", "").strip()
    model = os.environ.get("OPENAI_MODEL", "").strip()

    if not api_key or not base_url or not model:
        return None

    endpoint = base_url.rstrip("/") + "/chat/completions"
    system_prompt = (
        "You are a strict intent router for the local gupiao1 project. "
        "Do not answer the user's business question. Only classify the request for routing. "
        "Allowed action values are exactly: query, explain, trigger, modify, create. "
        "Allowed target values are exactly: unified, health, futures, stock, news. "
        "For modify/create, put the original user request into instruction. "
        "Prefer local project meanings over generic office document search. "
        "If the user mentions 统一汇总/日报/简报 use unified. "
        "If the user mentions 股票/个股 use stock. "
        "If the user mentions 期货 or a symbol like a0 use futures. "
        "If the user mentions 新闻/新鲜事/热点/舆情 use news. "
        "If the user asks to explain or interpret, use explain. "
        "If the user asks to change code, add a feature, create files, modify output, shorten output, or optimize implementation, use modify or create. "
        "Return compact JSON only with keys action,target,value,instruction,reason. "
        "Do not invent any other action names."
    )
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": message},
        ],
        "temperature": 0,
    }
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json; charset=utf-8",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, json.JSONDecodeError, KeyError):
        return None

    try:
        content = body["choices"][0]["message"]["content"]
        if isinstance(content, list):
            text_parts = []
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text":
                    text_parts.append(str(item.get("text", "")))
            content = "\n".join(text_parts).strip()
        content = str(content).strip()
        if "```" in content:
            match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", content, re.S)
            if match:
                content = match.group(1)
        else:
            match = re.search(r"(\{.*\})", content, re.S)
            if match:
                content = match.group(1)
        parsed = json.loads(content)
    except (KeyError, IndexError, TypeError, json.JSONDecodeError):
        return None

    raw_action = str(parsed.get("action", "")).strip()
    raw_target = str(parsed.get("target", "")).strip()
    raw_value = str(parsed.get("value", "")).strip()
    raw_instruction = str(parsed.get("instruction", "")).strip()
    raw_reason = str(parsed.get("reason", "")).strip()

    action = _normalize_action(raw_action, message, raw_target, raw_instruction)
    if action not in {"query", "explain", "trigger", "modify", "create"}:
        return None

    route = ChatRoute(
        action=action,
        target=_normalize_target(raw_target, message, raw_instruction),
        value="",
        instruction=raw_instruction,
        reason=raw_reason or f"llm-router normalized from {raw_action or 'empty'}",
    )

    route.value = _normalize_value(route.target, raw_value, message)

    if route.action in {"modify", "create"} and not route.instruction:
        route.instruction = message

    if route.action in {"query", "explain", "trigger"} and not route.target:
        route.target = "unified"
        route.value = _normalize_value(route.target, raw_value, message)

    if route.target == "futures" and not route.value:
        route.value = "a0"

    return route


def resolve_route(payload: dict) -> ChatRoute:
    message = str(payload.get("message", "")).strip()
    action = str(payload.get("action", "")).strip()
    target = str(payload.get("target", "")).strip()
    value = str(payload.get("value", "")).strip()
    source = str(payload.get("source", "openclaw-local-chat")).strip() or "openclaw-local-chat"
    mode = str(payload.get("mode", "auto")).strip() or "auto"

    if action:
        route = ChatRoute(
            action=action,
            target=target,
            value=value,
            instruction=message,
            source=source,
            mode=mode,
            reason="explicit action provided by caller",
        )
    else:
        route = llm_route_message(message) or infer_route(message)
        route.source = source
        route.mode = mode
        if route.action in {"modify", "create"}:
            route.target = ""
            route.value = ""

    if route.action in {"modify", "create"} and not route.instruction:
        raise ValueError("message is required for modify/create requests")

    if route.action in {"query", "explain", "trigger"} and not route.target:
        route.target = "unified"

    if route.target == "futures" and not route.value:
        route.value = "a0"

    return route


def build_router_command(route: ChatRoute) -> list[str]:
    if not ROUTER_SCRIPT.is_file():
        raise FileNotFoundError(f"router script not found: {ROUTER_SCRIPT}")

    command = [str(ROUTER_SCRIPT), route.action]

    if route.action in {"modify", "create"}:
        command.extend(["--source", route.source, route.instruction])
        return command

    if route.target:
        command.append(route.target)
    if route.value:
        command.append(route.value)
    return command


def run_router(route: ChatRoute, timeout_seconds: int) -> dict:
    command = build_router_command(route)
    completed = subprocess.run(
        command,
        cwd=ROOT_DIR,
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
        check=False,
    )
    return {
        "ok": completed.returncode == 0,
        "exit_code": completed.returncode,
        "stdout": completed.stdout.strip(),
        "stderr": completed.stderr.strip(),
        "command": command,
    }


class OpenClawChatHandler(BaseHTTPRequestHandler):
    server_version = "OpenClawChatAPI/0.1"

    @property
    def auth_token(self) -> str:
        return getattr(self.server, "auth_token", "")

    @property
    def timeout_seconds(self) -> int:
        return getattr(self.server, "timeout_seconds", 120)

    @property
    def modify_timeout_seconds(self) -> int:
        return getattr(self.server, "modify_timeout_seconds", 600)

    def _write_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _require_auth(self) -> bool:
        if not self.auth_token:
            return True

        auth_header = self.headers.get("Authorization", "")
        expected = f"Bearer {self.auth_token}"
        if auth_header == expected:
            return True

        self._write_json(
            HTTPStatus.UNAUTHORIZED,
            {"status": "unauthorized", "message": "missing or invalid bearer token"},
        )
        return False

    def _read_json(self) -> dict:
        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length)
        if not raw_body:
            return {}
        try:
            return json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError(f"invalid json body: {exc.msg}") from exc

    def do_GET(self) -> None:
        if self.path != "/health":
            self._write_json(HTTPStatus.NOT_FOUND, {"status": "not_found"})
            return

        self._write_json(
            HTTPStatus.OK,
            {
                "status": "ok",
                "router_script": str(ROUTER_SCRIPT),
                "auth_enabled": bool(self.auth_token),
            },
        )

    def do_POST(self) -> None:
        if self.path != "/v1/chat":
            self._write_json(HTTPStatus.NOT_FOUND, {"status": "not_found"})
            return

        if not self._require_auth():
            return

        try:
            payload = self._read_json()
            route = resolve_route(payload)
            timeout_seconds = (
                self.modify_timeout_seconds
                if route.action in {"modify", "create"}
                else self.timeout_seconds
            )
            result = run_router(route, timeout_seconds)
        except FileNotFoundError as exc:
            self._write_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"status": "error", "message": str(exc)})
            return
        except subprocess.TimeoutExpired:
            self._write_json(
                HTTPStatus.GATEWAY_TIMEOUT,
                {"status": "timeout", "message": f"router command exceeded {timeout_seconds}s"},
            )
            return
        except ValueError as exc:
            self._write_json(HTTPStatus.BAD_REQUEST, {"status": "bad_request", "message": str(exc)})
            return
        except Exception as exc:  # pragma: no cover - defensive fallback
            self._write_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"status": "error", "message": str(exc)})
            return

        response = {
            "status": "ok" if result["ok"] else "failed",
            "route": asdict(route),
            "result": result,
        }
        self._write_json(HTTPStatus.OK if result["ok"] else HTTPStatus.BAD_GATEWAY, response)

    def log_message(self, fmt: str, *args: object) -> None:
        sys.stderr.write(f"[openclaw-chat-api] {self.address_string()} - {fmt % args}\n")


def main() -> None:
    host = os.environ.get("OPENCLAW_CHAT_API_HOST", "127.0.0.1")
    port = int(os.environ.get("OPENCLAW_CHAT_API_PORT", "18889"))
    auth_token = os.environ.get("OPENCLAW_CHAT_API_TOKEN", "")
    timeout_seconds = int(os.environ.get("OPENCLAW_CHAT_API_TIMEOUT_SECONDS", "120"))
    modify_timeout_seconds = int(os.environ.get("OPENCLAW_CHAT_API_MODIFY_TIMEOUT_SECONDS", "600"))

    server = ThreadingHTTPServer((host, port), OpenClawChatHandler)
    server.auth_token = auth_token
    server.timeout_seconds = timeout_seconds
    server.modify_timeout_seconds = modify_timeout_seconds

    print(f"[openclaw-chat-api] listening on http://{host}:{port}")
    print(f"[openclaw-chat-api] router: {ROUTER_SCRIPT}")
    print(
        "[openclaw-chat-api] timeout: "
        f"query={timeout_seconds}s modify={modify_timeout_seconds}s"
    )
    if auth_token:
        print("[openclaw-chat-api] auth: bearer token enabled")
    else:
        print("[openclaw-chat-api] auth: disabled (local use only)")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
