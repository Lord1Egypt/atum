"""Tests for look-ahead bias detection."""

from bt_validator import LookAheadDetector, BiasType, Severity, DetectionCategory


def types_in(code, categories=None):
    issues = LookAheadDetector(categories=categories).detect(code)
    return {i.bias_type for i in issues}


def test_future_index_is_error():
    code = """
class S(bt.Strategy):
    def next(self):
        if self.data.close[1] > self.data.close[0]:
            self.buy()
"""
    issues = LookAheadDetector().detect(code)
    assert BiasType.FUTURE_INDEX in {i.bias_type for i in issues}
    assert any(i.severity == Severity.ERROR for i in issues)


def test_lines_positive_index_is_error():
    code = """
class S(bt.Strategy):
    def next(self):
        x = self.data.lines.close[1]
"""
    assert BiasType.LINES_POSITIVE_INDEX in types_in(code)


def test_higher_tf_close_zero_warns():
    code = """
class S(bt.Strategy):
    def next(self):
        if self.data1.close[0] > 10:
            self.buy()
"""
    assert BiasType.HIGHER_TF_CLOSE_ZERO in types_in(code)


def test_data0_close_zero_is_not_higher_tf():
    code = """
class S(bt.Strategy):
    def next(self):
        if self.data.close[0] > 10:
            self.buy()
"""
    assert BiasType.HIGHER_TF_CLOSE_ZERO not in types_in(code)


def test_low_zero_as_order_price_is_error():
    code = """
class S(bt.Strategy):
    def next(self):
        self.buy(price=self.data.low[0])
"""
    issues = LookAheadDetector(categories=[DetectionCategory.LOOKAHEAD]).detect(code)
    assert BiasType.IMPROPER_LIMIT_PRICE in {i.bias_type for i in issues}
    assert any(i.severity == Severity.ERROR for i in issues)


def test_implicit_low_as_order_price_is_error():
    code = """
class S(bt.Strategy):
    def next(self):
        self.buy(price=self.data.low)
"""
    assert BiasType.IMPROPER_LIMIT_PRICE in types_in(
        code, [DetectionCategory.LOOKAHEAD]
    )


def test_intrabar_extreme_in_condition_warns():
    code = """
class S(bt.Strategy):
    def next(self):
        if self.data.high[0] > 10:
            self.buy()
"""
    assert BiasType.INTRABAR_EXTREME in types_in(code, [DetectionCategory.LOOKAHEAD])


def test_lookback_zero_warns():
    code = """
class S(bt.Strategy):
    def __init__(self):
        self.sma = bt.indicators.SMA(self.data, period=0)
"""
    assert BiasType.LOOKBACK_ZERO in types_in(code)


def test_indicator_atr_intrabar_info():
    code = """
class S(bt.Strategy):
    def next(self):
        if self.atr[0] > 5:
            self.buy()
"""
    assert BiasType.INDICATOR_INTRABAR in types_in(code, [DetectionCategory.LOOKAHEAD])


def test_entry_price_lookahead_is_error_without_notify():
    code = """
class S(bt.Strategy):
    def next(self):
        self.entry_price = self.data.close[0]
"""
    issues = LookAheadDetector().detect(code)
    entry = [i for i in issues if i.bias_type == BiasType.ENTRY_PRICE_LOOKAHEAD]
    assert entry and entry[0].severity == Severity.ERROR


def test_entry_price_fallback_is_info_when_notify_order_present():
    code = """
class S(bt.Strategy):
    def next(self):
        self.entry_price = self.data.close[0]
    def notify_order(self, order):
        self.entry_price = order.executed.price
"""
    issues = LookAheadDetector().detect(code)
    entry = [i for i in issues if i.bias_type == BiasType.ENTRY_PRICE_LOOKAHEAD]
    assert entry and entry[0].severity == Severity.INFO


def test_entry_price_none_reset_is_not_flagged():
    code = """
class S(bt.Strategy):
    def next(self):
        self.entry_price = None
"""
    assert BiasType.ENTRY_PRICE_LOOKAHEAD not in types_in(code)


def test_clean_strategy_has_no_errors():
    code = """
class S(bt.Strategy):
    def next(self):
        if not self.position and self.data.close[-1] > self.sma[-1]:
            self.buy()
"""
    issues = LookAheadDetector().detect(code)
    assert not any(i.severity == Severity.ERROR for i in issues)


def test_syntax_error_returns_empty():
    assert LookAheadDetector().detect("def (:") == []


def test_category_filter_only_returns_selected():
    code = """
class S(bt.Strategy):
    def next(self):
        if self.data.close[1] > 0:
            self.buy(data=self.data1)
"""
    cats = {
        i.category
        for i in LookAheadDetector(
            categories=[DetectionCategory.LOOKAHEAD]
        ).detect(code)
    }
    assert cats == {DetectionCategory.LOOKAHEAD}
