"""Tests for order-routing detection (orders must target data0 only)."""

from bt_validator import (
    LookAheadDetector,
    BiasType,
    Severity,
    DetectionCategory,
    has_order_routing_errors,
    get_order_routing_issues,
)


def types_in(code):
    issues = LookAheadDetector(
        categories=[DetectionCategory.ORDER_ROUTING]
    ).detect(code)
    return {i.bias_type for i in issues}


def test_order_on_data1_keyword_is_critical():
    code = """
class S(bt.Strategy):
    def next(self):
        self.buy(data=self.data1)
"""
    assert BiasType.ORDER_ON_NON_DATA0 in types_in(code)
    assert has_order_routing_errors(code)


def test_order_on_datas_index_positional_is_critical():
    code = """
class S(bt.Strategy):
    def next(self):
        self.sell(self.datas[1])
"""
    assert BiasType.ORDER_ON_NON_DATA0 in types_in(code)


def test_order_on_data0_is_allowed():
    code = """
class S(bt.Strategy):
    def next(self):
        self.buy(data=self.data0)
        self.sell(data=self.data)
        self.close()
"""
    assert not has_order_routing_errors(code)


def test_order_routing_is_error_severity():
    code = """
class S(bt.Strategy):
    def next(self):
        self.order_target_percent(data=self.data2, target=0.5)
"""
    issues = get_order_routing_issues(code)
    assert issues and all(i.severity == Severity.ERROR for i in issues)
