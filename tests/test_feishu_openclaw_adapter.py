import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from feishu_openclaw_adapter.app import extract_event_message, normalize_text_message, summarize_chat_result


class NormalizeTextMessageTests(unittest.TestCase):
    def test_extracts_text_field(self) -> None:
        content = json.dumps({"text": "  看看今天的汇总  "}, ensure_ascii=False)
        self.assertEqual(normalize_text_message(content), "看看今天的汇总")

    def test_falls_back_to_raw_string(self) -> None:
        self.assertEqual(normalize_text_message("plain text"), "plain text")


class ExtractEventMessageTests(unittest.TestCase):
    def test_extracts_challenge(self) -> None:
        self.assertEqual(extract_event_message({"challenge": "abc"}), {"challenge": "abc"})

    def test_extracts_text_event(self) -> None:
        payload = {
            "schema": "2.0",
            "header": {"event_type": "im.message.receive_v1"},
            "event": {
                "message": {
                    "message_id": "om_xxx",
                    "chat_id": "oc_xxx",
                    "chat_type": "group",
                    "message_type": "text",
                    "content": json.dumps({"text": "解释一下今天的统一汇总"}, ensure_ascii=False),
                    "mentions": [{"name": "bot"}],
                },
                "sender": {"sender_id": {"open_id": "ou_xxx", "user_id": "u_xxx"}},
            },
        }

        event = extract_event_message(payload)
        self.assertEqual(event["message_id"], "om_xxx")
        self.assertEqual(event["chat_id"], "oc_xxx")
        self.assertEqual(event["content"], "解释一下今天的统一汇总")
        self.assertEqual(len(event["mentions"]), 1)


class SummarizeChatResultTests(unittest.TestCase):
    def test_uses_modify_summary(self) -> None:
        result = {
            "route": {"action": "modify"},
            "result": {
                "stdout": json.dumps(
                    {"status": "completed", "summary": "router-ok", "request_id": "req-1"},
                    ensure_ascii=False,
                )
            },
        }
        summary = summarize_chat_result(result)
        self.assertIn("router-ok", summary)
        self.assertIn("req-1", summary)

    def test_uses_stdout_for_query(self) -> None:
        result = {"route": {"action": "query"}, "result": {"stdout": "查询结果"}}
        self.assertEqual(summarize_chat_result(result), "查询结果")


if __name__ == "__main__":
    unittest.main()
