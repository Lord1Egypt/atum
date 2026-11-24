"""Tests for data-feed limit detection (max data0, data1, data2)."""

from bt_validator import (
    LookAheadDetector,
    BiasType,
    Severity,
    DetectionCategory,
    has_data_feed_errors,
    get_data_feed_issues,
)


def types_in(code):
    issues = LookAheadDetector(categories=[DetectionCategory.DATA_FEED]).detect(code)
    return {i.bias_type for i in issues}


def test_datas_index_3_exceeds_limit():
    code = """
class S(bt.Strategy):
    def next(self):
        x = self.datas[3].close[0]
"""
    assert BiasType.DATA_FEED_LIMIT_EXCEEDED in types_in(code)
    assert has_data_feed_errors(code)


def test_data3_attribute_exceeds_limit():
    code = """
class S(bt.Strategy):
    def next(self):
        x = self.data3.close[-1]
"""
    assert BiasType.DATA_FEED_LIMIT_EXCEEDED in types_in(code)


def test_data2_is_allowed():
    code = """
class S(bt.Strategy):
    def next(self):
        x = self.data2.close[-1]
"""
    assert not has_data_feed_errors(code)


def test_data_feed_errors_are_error_severity():
    code = """
class S(bt.Strategy):
    def next(self):
        x = self.datas[4].close[0]
"""
    issues = get_data_feed_issues(code)
    assert issues and all(i.severity == Severity.ERROR for i in issues)
