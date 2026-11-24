from freqtrade.strategy import IStrategy, IntParameter, DecimalParameter, BooleanParameter
import pandas as pd
import talib.abstract as ta
from datetime import datetime


class Eth1hQualityStrategy(IStrategy):
    """
    ETH 1H Quality Strategy — trend-following with momentum confirmation.

    Entry: price above EMA + RSI recovering from oversold zone.
    Exit:  at least 2 of 3 conditions (EMA break, RSI overbought, MACD bearish).
    Stop:  ATR-based dynamic stop loss, tightened after profit.

    Designed for 30-365 day backtesting with 10-50 trades per month.
    All tunable parameters use IntParameter/DecimalParameter for hyperopt.
    """

    INTERFACE_VERSION = 3
    timeframe = '1h'

    max_open_trades = 1
    stake_amount = 'unlimited'

    stoploss = -0.10

    trailing_stop = False

    minimal_roi = {
        '120': 0.01,
        '60':  0.03,
        '0':   100,
    }

    # -- Trend (buy) --
    trend_ema_period = IntParameter(20, 50, default=30, space='buy')

    # -- RSI (buy / sell) --
    rsi_period    = IntParameter(10, 20, default=14, space='buy')
    rsi_oversold  = IntParameter(30, 45, default=38, space='buy')
    rsi_overbought = IntParameter(60, 80, default=70, space='sell')

    # -- Volume filter (buy, off by default to keep trade frequency up) --
    volume_ma_period   = IntParameter(15, 30, default=20, space='buy')
    volume_multiplier  = DecimalParameter(1.2, 2.0, default=1.5, decimals=1, space='buy')
    use_volume_filter  = BooleanParameter(default=False, space='buy')

    # -- Exit toggles (sell) --
    use_ema_exit  = BooleanParameter(default=True, space='sell')
    use_rsi_exit  = BooleanParameter(default=True, space='sell')
    use_macd_exit = BooleanParameter(default=False, space='sell')

    # -- ATR stop multiplier (in 'buy' space since 'stoploss' only handles built-in stoploss) --
    atr_multiplier = DecimalParameter(1.5, 3.0, default=2.0, decimals=1, space='buy')

    ATR_PERIOD = 14

    # -----------------------------------------------------------------
    # Indicators
    # -----------------------------------------------------------------
    def populate_indicators(self, dataframe: pd.DataFrame, metadata: dict) -> pd.DataFrame:
        dataframe['atr'] = ta.ATR(dataframe, timeperiod=self.ATR_PERIOD)

        for p in self.trend_ema_period.range:
            dataframe[f'ema_{p}'] = ta.EMA(dataframe, timeperiod=p)

        for p in self.rsi_period.range:
            dataframe[f'rsi_{p}'] = ta.RSI(dataframe, timeperiod=p)

        macd = ta.MACD(dataframe['close'], fastperiod=12, slowperiod=26, signalperiod=9)
        dataframe['macd']        = macd[0]
        dataframe['macd_signal'] = macd[1]

        for p in self.volume_ma_period.range:
            dataframe[f'vol_ma_{p}'] = ta.SMA(dataframe['volume'], timeperiod=p)

        return dataframe

    # -----------------------------------------------------------------
    # Entry
    # -----------------------------------------------------------------
    def populate_entry_trend(self, dataframe: pd.DataFrame, metadata: dict) -> pd.DataFrame:
        dataframe.loc[:, 'enter_long'] = 0

        ema_p = self.trend_ema_period.value
        rsi_p = self.rsi_period.value
        rsi_t = self.rsi_oversold.value

        rsi = dataframe[f'rsi_{rsi_p}']

        above_ema       = dataframe['close'] > dataframe[f'ema_{ema_p}']
        rsi_was_low     = rsi.shift(1) < rsi_t
        rsi_recovering  = (rsi > rsi.shift(1)) & (rsi.shift(1) < rsi_t + 5)

        entry = above_ema & rsi_was_low & rsi_recovering

        if self.use_volume_filter.value:
            vol_p = self.volume_ma_period.value
            vol_m = self.volume_multiplier.value
            entry &= dataframe['volume'] > dataframe[f'vol_ma_{vol_p}'] * vol_m

        dataframe.loc[entry, 'enter_long'] = 1
        return dataframe

    # -----------------------------------------------------------------
    # Exit
    # -----------------------------------------------------------------
    def populate_exit_trend(self, dataframe: pd.DataFrame, metadata: dict) -> pd.DataFrame:
        dataframe.loc[:, 'exit_long'] = 0

        ema_p = self.trend_ema_period.value
        rsi_p = self.rsi_period.value
        rsi_t = self.rsi_overbought.value

        signals = []

        if self.use_ema_exit.value:
            signals.append(dataframe['close'] < dataframe[f'ema_{ema_p}'])

        if self.use_rsi_exit.value:
            signals.append(dataframe[f'rsi_{rsi_p}'] > rsi_t)

        if self.use_macd_exit.value:
            signals.append(dataframe['macd'] < dataframe['macd_signal'])

        if len(signals) >= 2:
            hits = signals[0].astype(int)
            for s in signals[1:]:
                hits = hits + s.astype(int)
            dataframe.loc[hits >= 2, 'exit_long'] = 1
        elif len(signals) == 1:
            dataframe.loc[signals[0], 'exit_long'] = 1

        return dataframe

    # -----------------------------------------------------------------
    # Dynamic stop loss (ATR-based)
    # -----------------------------------------------------------------
    def custom_stoploss(self, pair: str, trade, current_time: datetime,
                        current_rate: float, current_profit: float, **kwargs) -> float:
        if current_profit > 0.02:
            return -0.015

        if self.dp:
            df, _ = self.dp.get_analyzed_dataframe(pair, self.timeframe)
            if not df.empty:
                atr   = df.iloc[-1]['atr']
                price = df.iloc[-1]['close']
                if price > 0 and atr > 0:
                    pct = (atr * self.atr_multiplier.value) / price
                    return -min(pct, 0.08)

        return -0.03
