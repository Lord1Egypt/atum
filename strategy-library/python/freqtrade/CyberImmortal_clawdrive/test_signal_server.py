"""Tests for templates/signal-server/server.py

Run:  pytest tests/test_signal_server.py -v

Tests that need Freqtrade installed are marked with
  @pytest.mark.skipif(not HAS_FREQTRADE, ...)
"""

from __future__ import annotations

import json
import os
import sys
import textwrap
import threading
import time
from http.server import HTTPServer
from pathlib import Path
from typing import Any, Dict
from unittest.mock import MagicMock, patch
from urllib.request import urlopen

import pytest

# Ensure templates/ is importable
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "templates" / "signal-server"))

import server as signal_server


# Check if freqtrade is installed (for optional tests)
try:
    from freqtrade.strategy import IStrategy
    HAS_FREQTRADE = True
except ImportError:
    HAS_FREQTRADE = False


# -----------------------------------------------------------------------
# Fixtures
# -----------------------------------------------------------------------


@pytest.fixture()
def tmp_strategy_dir(tmp_path: Path) -> Path:
    """Create a minimal strategy directory with strategy.py."""
    d = tmp_path / "trading_test"
    d.mkdir()

    # Write a fake strategy that doesn't import freqtrade
    (d / "strategy.py").write_text(textwrap.dedent("""\
        class TestSignalStrategy:
            \"\"\"Minimal strategy for testing signal server.\"\"\"

            def populate_indicators(self, dataframe, metadata):
                return dataframe

            def populate_entry_trend(self, dataframe, metadata):
                return dataframe

            def populate_exit_trend(self, dataframe, metadata):
                return dataframe
    """))
    return d


@pytest.fixture()
def tmp_strategy_with_result(tmp_strategy_dir: Path) -> Path:
    (tmp_strategy_dir / "backtest_result.json").write_text(json.dumps({
        "status": "pass",
        "best_params": {"buy_rsi": 25, "sell_rsi": 75},
        "primary_pair": "BNB/USDT",
        "timeframe": "15m",
    }))
    return tmp_strategy_dir


# -----------------------------------------------------------------------
# Tests: load_best_params
# -----------------------------------------------------------------------


class TestLoadBestParams:
    def test_loads_from_backtest_result(self, tmp_strategy_with_result: Path) -> None:
        params = signal_server.load_best_params(str(tmp_strategy_with_result))
        assert params == {"buy_rsi": 25, "sell_rsi": 75}

    def test_returns_empty_when_no_file(self, tmp_strategy_dir: Path) -> None:
        params = signal_server.load_best_params(str(tmp_strategy_dir))
        assert params == {}

    def test_returns_empty_on_malformed_json(self, tmp_strategy_dir: Path) -> None:
        (tmp_strategy_dir / "backtest_result.json").write_text("not json")
        params = signal_server.load_best_params(str(tmp_strategy_dir))
        assert params == {}

    def test_returns_empty_when_no_best_params_key(self, tmp_strategy_dir: Path) -> None:
        (tmp_strategy_dir / "backtest_result.json").write_text(json.dumps({"status": "pass"}))
        params = signal_server.load_best_params(str(tmp_strategy_dir))
        assert params == {}


# -----------------------------------------------------------------------
# Tests: load_strategy_class
# -----------------------------------------------------------------------


class TestLoadStrategyClass:
    def test_loads_class_with_required_methods(self, tmp_strategy_dir: Path) -> None:
        cls = signal_server.load_strategy_class(str(tmp_strategy_dir))
        assert cls.__name__ == "TestSignalStrategy"
        assert hasattr(cls, "populate_indicators")
        assert hasattr(cls, "populate_entry_trend")
        assert hasattr(cls, "populate_exit_trend")

    def test_raises_on_missing_file(self, tmp_path: Path) -> None:
        with pytest.raises(Exception):
            signal_server.load_strategy_class(str(tmp_path / "nonexistent"))

    def test_raises_on_no_strategy_class(self, tmp_path: Path) -> None:
        d = tmp_path / "empty_strat"
        d.mkdir()
        (d / "strategy.py").write_text("x = 42\n")
        with pytest.raises(RuntimeError, match="No IStrategy subclass"):
            signal_server.load_strategy_class(str(d))


# -----------------------------------------------------------------------
# Tests: SignalEngine
# -----------------------------------------------------------------------


class TestSignalEngine:
    def test_initial_signal_is_hold(self, tmp_strategy_dir: Path) -> None:
        cls = signal_server.load_strategy_class(str(tmp_strategy_dir))
        engine = signal_server.SignalEngine(
            cls, {}, "BNB/USDT", "15m", "http://localhost:9876",
        )
        assert engine.last_signal["action"] == "hold"
        assert engine.running is True

    def test_get_info(self, tmp_strategy_dir: Path) -> None:
        cls = signal_server.load_strategy_class(str(tmp_strategy_dir))
        engine = signal_server.SignalEngine(
            cls, {}, "BNB/USDT", "15m", "http://localhost:9876",
        )
        info = engine.get_info()
        assert info["name"] == "TestSignalStrategy"
        assert info["pair"] == "BNB/USDT"
        assert info["timeframe"] == "15m"
        assert info["type"] == "freqtrade-signal"

    def test_get_stats(self, tmp_strategy_dir: Path) -> None:
        cls = signal_server.load_strategy_class(str(tmp_strategy_dir))
        engine = signal_server.SignalEngine(
            cls, {}, "ETH/USDT", "1h", "http://localhost:9876",
        )
        stats = engine.get_stats()
        assert "last_signal" in stats
        assert "signal_count" in stats
        assert stats["running"] is True
        assert stats["error"] is None

    def test_stop_and_start(self, tmp_strategy_dir: Path) -> None:
        cls = signal_server.load_strategy_class(str(tmp_strategy_dir))
        engine = signal_server.SignalEngine(
            cls, {}, "BNB/USDT", "15m", "http://localhost:9876",
        )
        engine.running = False
        assert engine.get_stats()["running"] is False
        engine.running = True
        assert engine.get_stats()["running"] is True

    def test_update_skips_when_not_running(self, tmp_strategy_dir: Path) -> None:
        cls = signal_server.load_strategy_class(str(tmp_strategy_dir))
        engine = signal_server.SignalEngine(
            cls, {}, "BNB/USDT", "15m", "http://localhost:9876",
        )
        engine.running = False
        engine.update()
        assert engine.last_update is None

    @patch("server.fetch_candles")
    def test_update_with_candle_data(self, mock_fetch, tmp_strategy_dir: Path) -> None:
        pytest.importorskip("pandas")

        mock_fetch.return_value = [
            {"open_time": 1000, "open": 600, "high": 605, "low": 598, "close": 603, "volume": 100},
            {"open_time": 2000, "open": 603, "high": 608, "low": 601, "close": 606, "volume": 150},
            {"open_time": 3000, "open": 606, "high": 610, "low": 604, "close": 607, "volume": 120},
        ]

        cls = signal_server.load_strategy_class(str(tmp_strategy_dir))
        engine = signal_server.SignalEngine(
            cls, {}, "BNB/USDT", "15m", "http://localhost:9876",
        )
        engine.update()

        assert engine.last_update is not None
        assert engine.last_signal["action"] == "hold"
        assert engine.error is None

    @patch("server.fetch_candles")
    def test_update_handles_empty_candles(self, mock_fetch, tmp_strategy_dir: Path) -> None:
        mock_fetch.return_value = []
        cls = signal_server.load_strategy_class(str(tmp_strategy_dir))
        engine = signal_server.SignalEngine(
            cls, {}, "BNB/USDT", "15m", "http://localhost:9876",
        )
        engine.update()
        assert engine.last_update is None

    @patch("server.fetch_candles")
    def test_update_handles_error_gracefully(self, mock_fetch, tmp_strategy_dir: Path) -> None:
        mock_fetch.side_effect = Exception("connection refused")
        cls = signal_server.load_strategy_class(str(tmp_strategy_dir))
        engine = signal_server.SignalEngine(
            cls, {}, "BNB/USDT", "15m", "http://localhost:9876",
        )
        engine.update()
        assert engine.error is not None
        assert "connection refused" in engine.error


# -----------------------------------------------------------------------
# Tests: HTTP handler
# -----------------------------------------------------------------------


class TestSignalHTTPHandler:
    @pytest.fixture(autouse=True)
    def _setup_server(self, tmp_strategy_dir: Path):
        cls = signal_server.load_strategy_class(str(tmp_strategy_dir))
        engine = signal_server.SignalEngine(
            cls, {}, "BNB/USDT", "15m", "http://localhost:9876",
        )
        signal_server.SignalHandler.engine = engine
        signal_server.SignalHandler.strategy_name = "test_strat"

        self.server = HTTPServer(("127.0.0.1", 0), signal_server.SignalHandler)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever)
        self.thread.daemon = True
        self.thread.start()

        yield

        self.server.shutdown()

    def _get(self, path: str) -> Dict[str, Any]:
        resp = urlopen(f"http://127.0.0.1:{self.port}{path}", timeout=3)
        return json.loads(resp.read())

    def test_signal_endpoint(self) -> None:
        data = self._get("/signal")
        assert data["action"] == "hold"

    def test_info_endpoint(self) -> None:
        data = self._get("/info")
        assert data["name"] == "TestSignalStrategy"
        assert data["pair"] == "BNB/USDT"

    def test_stats_endpoint(self) -> None:
        data = self._get("/stats")
        assert "last_signal" in data
        assert "signal_count" in data

    def test_health_endpoint(self) -> None:
        data = self._get("/health")
        assert data["status"] == "ok"

    def test_404_for_unknown_path(self) -> None:
        from urllib.error import HTTPError
        with pytest.raises(HTTPError) as exc_info:
            self._get("/nonexistent")
        assert exc_info.value.code == 404


# -----------------------------------------------------------------------
# Tests: POLL_INTERVAL
# -----------------------------------------------------------------------


class TestPollInterval:
    def test_poll_interval_is_60(self) -> None:
        assert signal_server.POLL_INTERVAL == 60


# -----------------------------------------------------------------------
# Tests with real Freqtrade IStrategy — skip if not installed
# -----------------------------------------------------------------------


@pytest.mark.skipif(
    not HAS_FREQTRADE or not os.environ.get("RUN_FREQTRADE"),
    reason="Freqtrade not installed or RUN_FREQTRADE not set",
)
class TestWithRealFreqtrade:
    @pytest.fixture()
    def ft_strategy_dir(self, tmp_path: Path) -> Path:
        d = tmp_path / "trading_ft_test"
        d.mkdir()
        (d / "strategy.py").write_text(textwrap.dedent("""\
            from freqtrade.strategy import IStrategy, IntParameter
            import talib.abstract as ta
            from pandas import DataFrame

            class TestFTStrategy(IStrategy):
                INTERFACE_VERSION = 3
                timeframe = '15m'
                can_short = False
                buy_rsi = IntParameter(10, 40, default=30, space='buy')
                stoploss = -0.05

                def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
                    dataframe['rsi'] = ta.RSI(dataframe, timeperiod=14)
                    return dataframe

                def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
                    dataframe.loc[
                        dataframe['rsi'] < self.buy_rsi.value,
                        'enter_long'] = 1
                    return dataframe

                def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
                    dataframe.loc[
                        dataframe['rsi'] > 70,
                        'exit_long'] = 1
                    return dataframe
        """))
        (d / "backtest_result.json").write_text(json.dumps({
            "status": "pass",
            "best_params": {"buy_rsi": 25},
        }))
        return d

    def test_load_real_freqtrade_strategy(self, ft_strategy_dir: Path) -> None:
        cls = signal_server.load_strategy_class(str(ft_strategy_dir))
        assert cls.__name__ == "TestFTStrategy"

    def test_engine_with_real_strategy(self, ft_strategy_dir: Path) -> None:
        cls = signal_server.load_strategy_class(str(ft_strategy_dir))
        params = signal_server.load_best_params(str(ft_strategy_dir))
        engine = signal_server.SignalEngine(
            cls, params, "BNB/USDT", "15m", "http://localhost:9876",
        )
        assert engine.last_signal["action"] == "hold"
