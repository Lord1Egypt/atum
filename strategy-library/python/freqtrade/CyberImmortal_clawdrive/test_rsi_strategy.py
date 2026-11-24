"""
Example Freqtrade strategy for manual testing of ClawDrive evaluation pipeline.

Usage:
  cp templates/examples/test_rsi_strategy.py \
     ~/.openclaw/workspace/skills/trading_test_rsi/strategy.py
"""
from freqtrade.strategy import IStrategy, IntParameter
import talib.abstract as ta
from pandas import DataFrame


class TestRsiStrategy(IStrategy):
    INTERFACE_VERSION = 3
    timeframe = '1h'
    can_short = False

    buy_rsi = IntParameter(20, 55, default=45, space='buy')
    sell_rsi = IntParameter(55, 80, default=65, space='sell')

    stoploss = -0.08
    trailing_stop = True
    trailing_stop_positive = 0.01
    trailing_stop_positive_offset = 0.03
    trailing_only_offset_is_reached = True

    minimal_roi = {
        "0": 0.06,
        "60": 0.03,
        "120": 0.01,
        "240": 0,
    }

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe['rsi'] = ta.RSI(dataframe, timeperiod=14)
        dataframe['ema_fast'] = ta.EMA(dataframe, timeperiod=8)
        dataframe['ema_slow'] = ta.EMA(dataframe, timeperiod=21)
        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[
            (dataframe['rsi'] < self.buy_rsi.value) &
            (dataframe['volume'] > 0),
            'enter_long'] = 1
        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[
            (dataframe['rsi'] > self.sell_rsi.value) &
            (dataframe['volume'] > 0),
            'exit_long'] = 1
        return dataframe
