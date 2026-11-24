"""Strategy classes and signal generation for qbacktester."""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Dict, Optional, Union

import numpy as np
import pandas as pd

from .indicators import crossover, sma, rsi, macd, bollinger_bands, stochastic


@dataclass
class StrategyParams:
    """
    Parameters for trading strategy configuration.

    Attributes:
        symbol: Trading symbol (e.g., 'AAPL', 'MSFT')
        start: Start date in YYYY-MM-DD format
        end: End date in YYYY-MM-DD format
        fast_window: Fast moving average window
        slow_window: Slow moving average window
        initial_cash: Starting capital (default: 100,000)
        fee_bps: Round-trip cost in basis points (default: 1.0)
        slippage_bps: Slippage cost in basis points (default: 0.5)
    """

    symbol: str
    start: str
    end: str
    fast_window: int
    slow_window: int
    initial_cash: float = 100_000
    fee_bps: float = 1.0
    slippage_bps: float = 0.5

    def __post_init__(self):
        """Validate parameters after initialization."""
        if self.fast_window <= 0:
            raise ValueError(f"fast_window must be positive, got {self.fast_window}")
        if self.slow_window <= 0:
            raise ValueError(f"slow_window must be positive, got {self.slow_window}")
        if self.fast_window >= self.slow_window:
            raise ValueError(
                f"fast_window ({self.fast_window}) must be less than slow_window ({self.slow_window})"
            )
        if self.initial_cash <= 0:
            raise ValueError(f"initial_cash must be positive, got {self.initial_cash}")
        if self.fee_bps < 0:
            raise ValueError(f"fee_bps must be non-negative, got {self.fee_bps}")
        if self.slippage_bps < 0:
            raise ValueError(
                f"slippage_bps must be non-negative, got {self.slippage_bps}"
            )


def generate_signals(
    price_df: pd.DataFrame, fast_window: int, slow_window: int
) -> pd.DataFrame:
    """
    Generate trading signals based on SMA crossover strategy.

    This function implements a vectorized SMA crossover strategy that:
    - Calculates fast and slow SMAs
    - Detects crossovers using the indicators.crossover function
    - Generates signals with 1-day delay to avoid look-ahead bias
    - Only allows long positions (1) or flat (0), no shorting

    Args:
        price_df: DataFrame with OHLCV data, must have 'Close' column
        fast_window: Fast SMA window period
        slow_window: Slow SMA window period

    Returns:
        DataFrame with additional columns:
        - 'sma_fast': Fast SMA values
        - 'sma_slow': Slow SMA values
        - 'crossover': Crossover detection (-1, 0, 1)
        - 'signal': Trading signal (0 or 1) with 1-day delay

    Raises:
        ValueError: If windows are invalid or 'Close' column missing
    """
    if "Close" not in price_df.columns:
        raise ValueError("price_df must contain 'Close' column")

    if fast_window <= 0 or slow_window <= 0:
        raise ValueError("Both fast_window and slow_window must be positive")

    if fast_window >= slow_window:
        raise ValueError("fast_window must be less than slow_window")

    # Create a copy to avoid modifying original DataFrame
    result_df = price_df.copy()

    # Calculate SMAs using the indicators module
    result_df["sma_fast"] = sma(price_df, window=fast_window, col="Close")
    result_df["sma_slow"] = sma(price_df, window=slow_window, col="Close")

    # Detect crossovers using the indicators module
    result_df["crossover"] = crossover(result_df["sma_fast"], result_df["sma_slow"])

    # Generate signals with 1-day delay to avoid look-ahead bias
    # Only enter long positions (1) on bullish crossovers, otherwise flat (0)
    # Shift by 1 day to ensure no look-ahead bias
    bullish_crossovers = (
        (result_df["crossover"] == 1).shift(1).fillna(False).astype(bool)
    )
    result_df["signal"] = bullish_crossovers.astype(int)

    return result_df


class Strategy(ABC):
    """
    Abstract base class for trading strategies.

    All trading strategies should inherit from this class and implement
    the generate_signal method.
    """

    def __init__(self, name: str) -> None:
        """
        Initialize the strategy.

        Args:
            name: Name of the strategy
        """
        self.name = name

    @abstractmethod
    def generate_signal(
        self, data: pd.Series, portfolio_value: float, positions: Dict[str, float]
    ) -> Optional[Dict[str, Union[str, float]]]:
        """
        Generate trading signal based on current market data.

        Args:
            data: Current market data (OHLCV)
            portfolio_value: Current portfolio value
            positions: Current positions

        Returns:
            Trading signal dictionary or None for no action
        """
        pass


class BuyAndHoldStrategy(Strategy):
    """Simple buy and hold strategy."""

    def __init__(self) -> None:
        super().__init__("Buy and Hold")
        self.bought = False

    def generate_signal(
        self, data: pd.Series, portfolio_value: float, positions: Dict[str, float]
    ) -> Optional[Dict[str, Union[str, float]]]:
        """Generate buy signal on first day, then hold."""
        if not self.bought:
            self.bought = True
            return {
                "action": "buy",
                "quantity": portfolio_value / data["close"],
                "price": data["close"],
            }
        return None


class MovingAverageCrossoverStrategy(Strategy):
    """Moving average crossover strategy."""

    def __init__(self, short_window: int = 20, long_window: int = 50) -> None:
        """
        Initialize the strategy.

        Args:
            short_window: Short moving average window
            long_window: Long moving average window
        """
        super().__init__("Moving Average Crossover")
        self.short_window = short_window
        self.long_window = long_window
        self.prices = []

    def generate_signal(
        self, data: pd.Series, portfolio_value: float, positions: Dict[str, float]
    ) -> Optional[Dict[str, Union[str, float]]]:
        """Generate signal based on moving average crossover."""
        self.prices.append(data["close"])

        if len(self.prices) < self.long_window:
            return None

        # Calculate moving averages
        short_ma = np.mean(self.prices[-self.short_window :])
        long_ma = np.mean(self.prices[-self.long_window :])

        # Previous values for crossover detection
        if len(self.prices) > self.long_window:
            prev_short_ma = np.mean(self.prices[-self.short_window - 1 : -1])
            prev_long_ma = np.mean(self.prices[-self.long_window - 1 : -1])

            # Golden cross (buy signal)
            if prev_short_ma <= prev_long_ma and short_ma > long_ma:
                return {
                    "action": "buy",
                    "quantity": portfolio_value / data["close"],
                    "price": data["close"],
                }
            # Death cross (sell signal)
            elif prev_short_ma >= prev_long_ma and short_ma < long_ma:
                return {
                    "action": "sell",
                    "quantity": positions.get("quantity", 0),
                    "price": data["close"],
                }

        return None


class RSIStrategy(Strategy):
    """RSI-based mean reversion strategy."""

    def __init__(self, window: int = 14, oversold: float = 30, overbought: float = 70) -> None:
        """
        Initialize the RSI strategy.

        Args:
            window: RSI calculation window (default: 14)
            oversold: RSI level to trigger buy signal (default: 30)
            overbought: RSI level to trigger sell signal (default: 70)
        """
        super().__init__("RSI Mean Reversion")
        self.window = window
        self.oversold = oversold
        self.overbought = overbought
        self.prices = []
        self.rsi_values = []

    def generate_signal(
        self, data: pd.Series, portfolio_value: float, positions: Dict[str, float]
    ) -> Optional[Dict[str, Union[str, float]]]:
        """Generate signal based on RSI levels."""
        self.prices.append(data["close"])

        if len(self.prices) < self.window + 1:
            return None

        # Calculate RSI
        price_series = pd.Series(self.prices)
        rsi_val = rsi(pd.DataFrame({"Close": price_series}), window=self.window, col="Close").iloc[-1]
        self.rsi_values.append(rsi_val)

        if len(self.rsi_values) < 2:
            return None

        prev_rsi = self.rsi_values[-2]
        current_rsi = self.rsi_values[-1]

        # Buy when RSI crosses above oversold level
        if prev_rsi <= self.oversold and current_rsi > self.oversold:
            return {
                "action": "buy",
                "quantity": portfolio_value / data["close"],
                "price": data["close"],
            }
        # Sell when RSI crosses below overbought level
        elif prev_rsi >= self.overbought and current_rsi < self.overbought:
            return {
                "action": "sell",
                "quantity": positions.get("quantity", 0),
                "price": data["close"],
            }

        return None


class MACDStrategy(Strategy):
    """MACD crossover strategy."""

    def __init__(self, fast: int = 12, slow: int = 26, signal: int = 9) -> None:
        """
        Initialize the MACD strategy.

        Args:
            fast: Fast EMA period (default: 12)
            slow: Slow EMA period (default: 26)
            signal: Signal line EMA period (default: 9)
        """
        super().__init__("MACD Crossover")
        self.fast = fast
        self.slow = slow
        self.signal = signal
        self.prices = []
        self.macd_values = []
        self.signal_values = []

    def generate_signal(
        self, data: pd.Series, portfolio_value: float, positions: Dict[str, float]
    ) -> Optional[Dict[str, Union[str, float]]]:
        """Generate signal based on MACD crossover."""
        self.prices.append(data["close"])

        if len(self.prices) < self.slow + self.signal:
            return None

        # Calculate MACD
        price_series = pd.Series(self.prices)
        macd_result = macd(pd.DataFrame({"Close": price_series}), 
                          fast=self.fast, slow=self.slow, signal=self.signal, col="Close")
        
        macd_line = macd_result["macd"].iloc[-1]
        signal_line = macd_result["signal"].iloc[-1]
        
        self.macd_values.append(macd_line)
        self.signal_values.append(signal_line)

        if len(self.macd_values) < 2:
            return None

        prev_macd = self.macd_values[-2]
        prev_signal = self.signal_values[-2]

        # Buy when MACD crosses above signal line
        if prev_macd <= prev_signal and macd_line > signal_line:
            return {
                "action": "buy",
                "quantity": portfolio_value / data["close"],
                "price": data["close"],
            }
        # Sell when MACD crosses below signal line
        elif prev_macd >= prev_signal and macd_line < signal_line:
            return {
                "action": "sell",
                "quantity": positions.get("quantity", 0),
                "price": data["close"],
            }

        return None


class BollingerBandsStrategy(Strategy):
    """Bollinger Bands mean reversion strategy."""

    def __init__(self, window: int = 20, std_dev: float = 2.0) -> None:
        """
        Initialize the Bollinger Bands strategy.

        Args:
            window: Moving average window (default: 20)
            std_dev: Standard deviation multiplier (default: 2.0)
        """
        super().__init__("Bollinger Bands Mean Reversion")
        self.window = window
        self.std_dev = std_dev
        self.prices = []

    def generate_signal(
        self, data: pd.Series, portfolio_value: float, positions: Dict[str, float]
    ) -> Optional[Dict[str, Union[str, float]]]:
        """Generate signal based on Bollinger Bands."""
        self.prices.append(data["close"])

        if len(self.prices) < self.window:
            return None

        # Calculate Bollinger Bands
        price_series = pd.Series(self.prices)
        bb_result = bollinger_bands(pd.DataFrame({"Close": price_series}), 
                                   window=self.window, std_dev=self.std_dev, col="Close")
        
        upper_band = bb_result["upper"].iloc[-1]
        lower_band = bb_result["lower"].iloc[-1]
        current_price = data["close"]

        # Buy when price touches lower band (oversold)
        if current_price <= lower_band:
            return {
                "action": "buy",
                "quantity": portfolio_value / data["close"],
                "price": data["close"],
            }
        # Sell when price touches upper band (overbought)
        elif current_price >= upper_band:
            return {
                "action": "sell",
                "quantity": positions.get("quantity", 0),
                "price": data["close"],
            }

        return None


class MomentumStrategy(Strategy):
    """Momentum strategy based on price rate of change."""

    def __init__(self, window: int = 10, threshold: float = 0.02) -> None:
        """
        Initialize the momentum strategy.

        Args:
            window: Period for momentum calculation (default: 10)
            threshold: Minimum momentum threshold for signals (default: 0.02 = 2%)
        """
        super().__init__("Momentum")
        self.window = window
        self.threshold = threshold
        self.prices = []

    def generate_signal(
        self, data: pd.Series, portfolio_value: float, positions: Dict[str, float]
    ) -> Optional[Dict[str, Union[str, float]]]:
        """Generate signal based on momentum."""
        self.prices.append(data["close"])

        if len(self.prices) < self.window + 1:
            return None

        # Calculate momentum (rate of change)
        current_price = data["close"]
        past_price = self.prices[-self.window - 1]
        momentum = (current_price - past_price) / past_price

        # Buy on positive momentum above threshold
        if momentum > self.threshold:
            return {
                "action": "buy",
                "quantity": portfolio_value / data["close"],
                "price": data["close"],
            }
        # Sell on negative momentum below threshold
        elif momentum < -self.threshold:
            return {
                "action": "sell",
                "quantity": positions.get("quantity", 0),
                "price": data["close"],
            }

        return None


class StochasticStrategy(Strategy):
    """Stochastic oscillator strategy."""

    def __init__(self, k_window: int = 14, d_window: int = 3, 
                 oversold: float = 20, overbought: float = 80) -> None:
        """
        Initialize the stochastic strategy.

        Args:
            k_window: %K calculation window (default: 14)
            d_window: %D smoothing window (default: 3)
            oversold: Oversold level (default: 20)
            overbought: Overbought level (default: 80)
        """
        super().__init__("Stochastic Oscillator")
        self.k_window = k_window
        self.d_window = d_window
        self.oversold = oversold
        self.overbought = overbought
        self.prices = []
        self.highs = []
        self.lows = []

    def generate_signal(
        self, data: pd.Series, portfolio_value: float, positions: Dict[str, float]
    ) -> Optional[Dict[str, Union[str, float]]]:
        """Generate signal based on stochastic oscillator."""
        self.prices.append(data["close"])
        self.highs.append(data["high"])
        self.lows.append(data["low"])

        if len(self.prices) < self.k_window:
            return None

        # Calculate stochastic
        price_df = pd.DataFrame({
            "Close": self.prices,
            "High": self.highs,
            "Low": self.lows
        })
        
        stoch_result = stochastic(price_df, k_window=self.k_window, d_window=self.d_window)
        k_percent = stoch_result["%K"].iloc[-1]
        d_percent = stoch_result["%D"].iloc[-1]

        # Buy when %K crosses above %D from oversold
        if k_percent > d_percent and k_percent < self.oversold:
            return {
                "action": "buy",
                "quantity": portfolio_value / data["close"],
                "price": data["close"],
            }
        # Sell when %K crosses below %D from overbought
        elif k_percent < d_percent and k_percent > self.overbought:
            return {
                "action": "sell",
                "quantity": positions.get("quantity", 0),
                "price": data["close"],
            }

        return None
