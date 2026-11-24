"""Tests for position-management detection."""

from bt_validator import (
    LookAheadDetector,
    BiasType,
    DetectionCategory,
    has_position_management_issues,
)


def types_in(code):
    issues = LookAheadDetector(
        categories=[DetectionCategory.POSITION_MANAGEMENT]
    ).detect(code)
    return {i.bias_type for i in issues}


def test_unguarded_buy_and_sell_flags_simultaneous():
    code = """
class S(bt.Strategy):
    def next(self):
        self.buy()
        self.sell()
"""
    assert BiasType.SIMULTANEOUS_LONG_SHORT in types_in(code)


def test_non_exclusive_if_branches_flagged():
    code = """
class S(bt.Strategy):
    def next(self):
        if self.fast > self.slow:
            self.buy()
        if self.fast < self.slow:
            self.sell()
"""
    assert BiasType.SIMULTANEOUS_LONG_SHORT in types_in(code)


def test_missing_position_guard_warns():
    code = """
class S(bt.Strategy):
    def next(self):
        self.buy()
"""
    assert BiasType.MISSING_POSITION_CHECK in types_in(code)


def test_position_guard_suppresses_missing_check():
    code = """
class S(bt.Strategy):
    def next(self):
        if not self.position:
            self.buy()
"""
    assert BiasType.MISSING_POSITION_CHECK not in types_in(code)


def test_guarded_mutually_exclusive_entries_are_clean():
    code = """
class S(bt.Strategy):
    def next(self):
        if not self.position:
            if self.fast > self.slow:
                self.buy()
            elif self.fast < self.slow:
                self.sell()
"""
    assert not has_position_management_issues(code)
