import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from unittest.mock import patch

from openclaw_chat_api.app import (
    ChatRoute,
    _normalize_action,
    _normalize_target,
    _normalize_value,
    build_router_command,
    infer_route,
    resolve_route,
)


class InferRouteTests(unittest.TestCase):
    def test_defaults_to_query_unified_latest(self) -> None:
        route = infer_route("看看今天的统一汇总")

        self.assertEqual(route.action, "query")
        self.assertEqual(route.target, "unified")
        self.assertEqual(route.value, "today")

    def test_detects_explain_futures_symbol(self) -> None:
        route = infer_route("解释一下期货 a0 最近怎么看")

        self.assertEqual(route.action, "explain")
        self.assertEqual(route.target, "futures")
        self.assertEqual(route.value, "a0")

    def test_detects_modify_request(self) -> None:
        route = infer_route("修改 futures 输出模板，别动别的")

        self.assertEqual(route.action, "modify")
        self.assertIn("futures", route.instruction)


class LlmNormalizationTests(unittest.TestCase):
    def test_normalizes_modify_style_action(self) -> None:
        action = _normalize_action(
            "压缩内容篇幅",
            "把新闻模块的输出改短一点，但不要改别的模块",
            "新闻模块的输出内容",
            "仅对新闻模块的输出内容进行缩短处理",
        )
        self.assertEqual(action, "modify")

    def test_normalizes_explain_style_action(self) -> None:
        action = _normalize_action(
            "查询并解析期货市场整体行情",
            "帮我看看今天期货整体怎么样，顺便解释一下",
            "当日全品类期货市场运行表现",
            "",
        )
        self.assertEqual(action, "explain")

    def test_normalizes_target_to_news(self) -> None:
        target = _normalize_target(
            "新闻模块的输出内容",
            "把新闻模块的输出改短一点，但不要改别的模块",
            "仅对新闻模块的输出内容进行缩短处理",
        )
        self.assertEqual(target, "news")

    def test_normalizes_futures_value_to_symbol(self) -> None:
        value = _normalize_value(
            "futures",
            "今日期货整体行情及相关解释",
            "帮我看看今天期货整体怎么样，顺便解释一下",
        )
        self.assertEqual(value, "a0")


class ResolveRouteTests(unittest.TestCase):
    def test_uses_explicit_action_and_target(self) -> None:
        route = resolve_route({"action": "query", "target": "health", "value": "today"})

        self.assertEqual(route.action, "query")
        self.assertEqual(route.target, "health")
        self.assertEqual(route.value, "today")

    def test_requires_message_for_modify(self) -> None:
        with self.assertRaises(ValueError):
            resolve_route({"action": "modify"})

    def test_builds_modify_command_with_source(self) -> None:
        route = resolve_route(
            {"action": "modify", "message": "补一份文档", "source": "feishu-test"}
        )

        command = build_router_command(route)
        self.assertEqual(command[1], "modify")
        self.assertEqual(command[2:4], ["--source", "feishu-test"])
        self.assertEqual(command[-1], "补一份文档")

    def test_defaults_target_for_query(self) -> None:
        route = resolve_route({"action": "query", "value": "latest"})

        self.assertEqual(route.target, "unified")

    def test_prefers_llm_router_when_available(self) -> None:
        with patch("openclaw_chat_api.app.llm_route_message", return_value=ChatRoute(action="query", target="news", value="latest", reason="llm")):
            route = resolve_route({"message": "今天有什么新闻新鲜事"})

        self.assertEqual(route.action, "query")
        self.assertEqual(route.target, "news")
        self.assertEqual(route.reason, "llm")


if __name__ == "__main__":
    unittest.main()
