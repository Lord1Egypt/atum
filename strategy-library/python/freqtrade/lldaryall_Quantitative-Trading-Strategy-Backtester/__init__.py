"""
qbacktester: A quantitative backtesting library for financial strategies.

This package provides tools for backtesting trading strategies, analyzing performance,
and generating reports for quantitative finance research.
"""

__version__ = "0.1.0"
__author__ = "Quantitative Finance Team"
__email__ = "contact@qbacktester.dev"

from .backtester import Backtester
from .data import DataError, DataLoader
from .indicators import bollinger_bands, crossover, ema, macd, rsi, sma, stochastic
from .metrics import (
    avg_win_loss,
    cagr,
    calmar,
    cvar,
    daily_returns,
    hit_rate,
    max_drawdown,
    sharpe,
    sortino,
    var,
    volatility,
)
from .optimize import (
    grid_search,
    optimize_strategy,
    print_optimization_results,
    save_optimization_results,
)
from .plotting import (
    create_plot_style,
    plot_comprehensive_backtest,
    plot_drawdown,
    plot_equity,
    plot_equity_with_metrics,
    plot_price_signals,
    save_figure,
)
from .reports import generate_html_report, generate_pdf_report, ReportGenerator
from .run import print_backtest_report, run_crossover_backtest, run_quick_backtest
from .strategy import (
    BollingerBandsStrategy,
    BuyAndHoldStrategy,
    MACDStrategy,
    MomentumStrategy,
    MovingAverageCrossoverStrategy,
    RSIStrategy,
    StochasticStrategy,
    Strategy,
    StrategyParams,
    generate_signals,
)
from .walkforward import print_walkforward_results, walkforward_crossover

__all__ = [
    "Backtester",
    "DataLoader",
    "DataError",
    "Strategy",
    "BuyAndHoldStrategy",
    "MovingAverageCrossoverStrategy",
    "RSIStrategy",
    "MACDStrategy",
    "BollingerBandsStrategy",
    "MomentumStrategy",
    "StochasticStrategy",
    "StrategyParams",
    "generate_signals",
    "sma",
    "ema",
    "crossover",
    "rsi",
    "macd",
    "bollinger_bands",
    "stochastic",
    "daily_returns",
    "cagr",
    "sharpe",
    "max_drawdown",
    "calmar",
    "hit_rate",
    "avg_win_loss",
    "volatility",
    "sortino",
    "var",
    "cvar",
    "run_crossover_backtest",
    "print_backtest_report",
    "run_quick_backtest",
    "generate_html_report",
    "generate_pdf_report",
    "ReportGenerator",
    "plot_equity",
    "plot_drawdown",
    "plot_price_signals",
    "save_figure",
    "plot_equity_with_metrics",
    "plot_comprehensive_backtest",
    "create_plot_style",
    "grid_search",
    "optimize_strategy",
    "print_optimization_results",
    "save_optimization_results",
    "walkforward_crossover",
    "print_walkforward_results",
]
