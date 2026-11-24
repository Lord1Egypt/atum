"""Backtrader strategy validator.

AST-based detection of look-ahead bias and rule violations in Backtrader
strategies, across four categories: look-ahead, data-feed limits, position
management, and order routing.

This package performs *static* analysis on strategy source code as text — it
never imports or executes ``backtrader``. It is heuristic: it flags known
problematic patterns but cannot guarantee the absence of bias.
"""

from .detector import (
    LookAheadDetector,
    LookAheadIssue,
    BiasType,
    Severity,
    DetectionCategory,
    DEFAULT_ACCEPTABLE_THRESHOLD,
    SEVERITY_WEIGHTS,
    get_validation_summary,
    is_strategy_acceptable,
    get_severity_score,
    has_any_validation_errors,
    get_all_validation_issues,
    has_lookahead_bias,
    get_lookahead_issues,
    has_data_feed_errors,
    get_data_feed_issues,
    has_position_management_issues,
    get_position_management_issues,
    has_order_routing_errors,
    get_order_routing_issues,
    format_issues_for_llm,
)

__version__ = "0.1.0"

__all__ = [
    "LookAheadDetector",
    "LookAheadIssue",
    "BiasType",
    "Severity",
    "DetectionCategory",
    "DEFAULT_ACCEPTABLE_THRESHOLD",
    "SEVERITY_WEIGHTS",
    "get_validation_summary",
    "is_strategy_acceptable",
    "get_severity_score",
    "has_any_validation_errors",
    "get_all_validation_issues",
    "has_lookahead_bias",
    "get_lookahead_issues",
    "has_data_feed_errors",
    "get_data_feed_issues",
    "has_position_management_issues",
    "get_position_management_issues",
    "has_order_routing_errors",
    "get_order_routing_issues",
    "format_issues_for_llm",
]
