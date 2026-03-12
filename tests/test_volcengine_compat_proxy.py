import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from volcengine_compat_proxy.app import strip_unsupported_fields


class StripUnsupportedFieldsTests(unittest.TestCase):
    def test_removes_prompt_cache_key_recursively(self) -> None:
        payload = {
            "model": "x",
            "prompt_cache_key": "abc",
            "input": [
                {
                    "role": "user",
                    "content": [{"type": "input_text", "text": "hi", "prompt_cache_key": "nested"}],
                }
            ],
        }

        cleaned = strip_unsupported_fields(payload)
        self.assertNotIn("prompt_cache_key", cleaned)
        self.assertNotIn("prompt_cache_key", cleaned["input"][0]["content"][0])


if __name__ == "__main__":
    unittest.main()
