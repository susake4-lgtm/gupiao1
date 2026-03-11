import sys
import unittest
from json import JSONDecodeError
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from futures_api.errors import EmptyDataError, UpstreamFetchError
from futures_api import service


class _FakeDataFrame:
    def __init__(self, empty: bool) -> None:
        self.empty = empty


class _FakeAkshareFailure:
    def futures_zh_realtime(self):
        raise JSONDecodeError("Expecting value", "", 0)


class _FakeAkshareSuccess:
    def __init__(self, dataframe) -> None:
        self._dataframe = dataframe

    def futures_zh_realtime(self):
        return self._dataframe


class FetchRealtimeDataframeTests(unittest.TestCase):
    def test_wraps_json_decode_error_with_upstream_wording(self) -> None:
        with patch.object(service, "_get_akshare_module", return_value=_FakeAkshareFailure()):
            with self.assertRaises(UpstreamFetchError) as ctx:
                service._fetch_realtime_dataframe()

        message = str(ctx.exception)
        self.assertIn("上游行情源异常", message)
        self.assertIn("AkShare 返回空响应或非预期响应", message)
        self.assertIn("JSONDecodeError", message)
        self.assertNotIn("llm", message.lower())
        self.assertNotIn("model", message.lower())

    def test_raises_empty_data_error_with_empty_data_wording(self) -> None:
        with patch.object(service, "_get_akshare_module", return_value=_FakeAkshareSuccess(_FakeDataFrame(empty=True))):
            with self.assertRaises(EmptyDataError) as ctx:
                service._fetch_realtime_dataframe()

        self.assertIn("AkShare 返回空数据", str(ctx.exception))

    def test_returns_dataframe_when_not_empty(self) -> None:
        dataframe = _FakeDataFrame(empty=False)

        with patch.object(service, "_get_akshare_module", return_value=_FakeAkshareSuccess(dataframe)):
            result = service._fetch_realtime_dataframe()

        self.assertIs(result, dataframe)


if __name__ == "__main__":
    unittest.main()
