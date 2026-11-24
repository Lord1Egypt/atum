"""Tests for severity scoring and the high-level helper API."""

from bt_validator import (
    LookAheadDetector,
    Severity,
    DEFAULT_ACCEPTABLE_THRESHOLD,
    get_validation_summary,
    is_strategy_acceptable,
    get_severity_score,
    has_any_validation_errors,
)


def test_no_issues_scores_zero():
    code = """
class S(bt.Strategy):
    def next(self):
        if not self.position:
            if self.data.close[-1] > self.sma[-1]:
                self.buy()
"""
    assert get_severity_score(code) == 0.0
    assert is_strategy_acceptable(code)
    assert not has_any_validation_errors(code)


def test_single_issue_does_not_scale():
    # One ERROR future-index issue, weight 1.0, modifier 1.0 => capped at 1.0,
    # but with a single issue there is no (count-1) multiplier applied.
    code = """
class S(bt.Strategy):
    def next(self):
        x = self.data.close[1]
"""
    det = LookAheadDetector()
    det.detect(code)
    assert len([i for i in det.issues]) == 1
    # weight(1.0) * modifier(1.0) = 1.0, no scaling since count == 1
    assert det.calculate_severity_score() == 1.0


def test_score_is_capped_at_one():
    code = """
class S(bt.Strategy):
    def next(self):
        a = self.data.close[1]
        b = self.data.close[2]
        c = self.data.close[3]
        self.buy(data=self.data1)
"""
    score = get_severity_score(code)
    assert 0.0 < score <= 1.0


def test_threshold_boundary_is_strict():
    # is_acceptable uses score < threshold (strict).
    det = LookAheadDetector()
    det.detect("class S(bt.Strategy):\n    pass\n")
    assert det.calculate_severity_score() == 0.0
    assert det.is_acceptable(0.0) is False  # 0.0 < 0.0 is False
    assert det.is_acceptable(0.1) is True


def test_validation_summary_shape():
    code = """
class S(bt.Strategy):
    def next(self):
        x = self.data.close[1]
"""
    summary = get_validation_summary(code)
    assert set(summary) == {
        "is_acceptable",
        "score",
        "issue_count",
        "breakdown",
        "blocking_issues",
        "issues",
    }
    assert summary["issue_count"] >= 1
    assert summary["is_acceptable"] is False


def test_breakdown_counts_match_issues():
    code = """
class S(bt.Strategy):
    def next(self):
        x = self.data.close[1]
        self.buy(data=self.data1)
"""
    det = LookAheadDetector()
    issues = det.detect(code)
    b = det.get_severity_breakdown()
    counted = b["error_count"] + b["warning_count"] + b["info_count"]
    assert counted == len(issues) == b["issue_count"]


def test_default_threshold_value():
    assert DEFAULT_ACCEPTABLE_THRESHOLD == 0.5


def test_blocking_issues_include_errors():
    code = """
class S(bt.Strategy):
    def next(self):
        x = self.data.close[1]
"""
    det = LookAheadDetector()
    det.detect(code)
    blocking = det.get_blocking_issues()
    assert blocking and all(
        i.severity in (Severity.ERROR, Severity.WARNING) for i in blocking
    )
