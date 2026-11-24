"""
HAEMADoji — Heikin Ashi + EMA + Wide-Range Doji
Chart must be set to Heikin Ashi bars in NT8 before exporting.
Doji with both wicks, above/below EMA zone, after clean pullback in trend direction.
SL: 1 tick beyond doji extreme. TP: doji range × TpMultiplier.
"""
import numpy as np
import backtrader as bt
import pandas as pd
import backtrader.indicators as btind
from . import _exec

LABEL       = "HA EMA Doji (HA bars required)"
DESCRIPTION = "Heikin Ashi doji above/below EMA after clean pullback. Export chart as HA bars from NT8."

PARAM_GRID = {
    'tp_multiplier':   [0.5, 1.0, 1.5, 2.0],
    'min_pullback':    [2, 3, 4],
    'ema_zone_ticks':  [0, 5, 10],
}

DEFAULT_PARAMS = dict(
    dollar_risk=100.0,
    ema_period=100, doji_body_ticks=2, wick_tol_ticks=0,
    range_lookback=3, min_pullback=2, min_run=2,
    ema_zone_ticks=5, tp_multiplier=1.0,
    printlog=False,
)

POINT_VALUE = 2.0
TICK_SIZE   = 0.25


def precompute(df: pd.DataFrame) -> pd.DataFrame:
    return df

def make_feed(df: pd.DataFrame):
    return bt.feeds.PandasData(dataname=df, datetime=None,
                               open='Open', high='High', low='Low',
                               close='Close', volume='Volume', openinterest=-1)


class Strategy(bt.Strategy):
    params = dict(
        dollar_risk=100.0,
        ema_period=100, doji_body_ticks=2, wick_tol_ticks=0,
        range_lookback=3, min_pullback=2, min_run=2,
        ema_zone_ticks=5, tp_multiplier=1.0,
        printlog=False,
    )

    def log(self, msg):
        if self.p.printlog:
            print(f"{self.data.datetime.datetime(0):%Y-%m-%d %H:%M}  {msg}")

    def __init__(self):
        self.ema = btind.EMA(self.data.close, period=self.p.ema_period)

    def notify_trade(self, trade):
        if trade.isclosed: self.log(f"TRADE pnl=${trade.pnl:.2f}")

    def _count_clean_bearish(self, wick_tol):
        count = 0
        for i in range(1, min(31, len(self))):
            if self.data.close[-i] < self.data.open[-i] and \
               (self.data.high[-i] - self.data.open[-i]) <= wick_tol:
                count += 1
            else:
                break
        return count

    def _count_clean_bullish(self, wick_tol):
        count = 0
        for i in range(1, min(31, len(self))):
            if self.data.close[-i] > self.data.open[-i] and \
               (self.data.open[-i] - self.data.low[-i]) <= wick_tol:
                count += 1
            else:
                break
        return count

    def _pullback_clears_ema(self, pb_count, ema_val, is_long):
        for i in range(1, pb_count + 1):
            if is_long  and self.data.low[-i]  <= ema_val: return False
            if not is_long and self.data.high[-i] >= ema_val: return False
        return True

    def _count_run(self, pb_count, long_run):
        count = 0
        for i in range(pb_count + 1, pb_count + 31):
            if i >= len(self): break
            is_run = self.data.close[-i] > self.data.open[-i] if long_run \
                     else self.data.close[-i] < self.data.open[-i]
            if is_run: count += 1
            else: break
        return count

    def next(self):
        min_bars = self.p.ema_period + self.p.min_pullback + self.p.range_lookback + 2
        if len(self) < min_bars: return
        if self.position: return

        o, h, l, c = self.data.open[0], self.data.high[0], self.data.low[0], self.data.close[0]
        body      = abs(c - o)
        doji_max  = self.p.doji_body_ticks * TICK_SIZE
        wick_tol  = self.p.wick_tol_ticks  * TICK_SIZE

        # Gate 1: small body with both wicks
        if body > doji_max: return
        body_top = max(o, c); body_bot = min(o, c)
        if h <= body_top or l >= body_bot: return

        # Gate 2: doji range >= last N candles
        doji_range = h - l
        for i in range(1, self.p.range_lookback + 1):
            if doji_range < (self.data.high[-i] - self.data.low[-i]): return

        ema_val  = self.ema[0]
        ema_zone = self.p.ema_zone_ticks * TICK_SIZE

        # Long setup: above EMA zone + bearish pullback + bullish run before it
        bear_pb = self._count_clean_bearish(wick_tol)
        if (c > ema_val + ema_zone and bear_pb >= self.p.min_pullback
                and self._pullback_clears_ema(bear_pb, ema_val, True)
                and self._count_run(bear_pb, True) >= self.p.min_run):
            sl  = round((l - TICK_SIZE)        / TICK_SIZE) * TICK_SIZE
            tp  = round((h + doji_range * self.p.tp_multiplier) / TICK_SIZE) * TICK_SIZE
            qty = max(1, int(self.p.dollar_risk / (doji_range * POINT_VALUE)))
            _exec.enter_bracket(self, True, qty, sl, tp)
            self.log(f"LONG  entry={c:.2f} sl={sl:.2f} tp={tp:.2f}")
            return

        # Short setup: below EMA zone + bullish pullback + bearish run before it
        bull_pb = self._count_clean_bullish(wick_tol)
        if (c < ema_val - ema_zone and bull_pb >= self.p.min_pullback
                and self._pullback_clears_ema(bull_pb, ema_val, False)
                and self._count_run(bull_pb, False) >= self.p.min_run):
            sl  = round((h + TICK_SIZE)        / TICK_SIZE) * TICK_SIZE
            tp  = round((l - doji_range * self.p.tp_multiplier) / TICK_SIZE) * TICK_SIZE
            qty = max(1, int(self.p.dollar_risk / (doji_range * POINT_VALUE)))
            _exec.enter_bracket(self, False, qty, sl, tp)
            self.log(f"SHORT entry={c:.2f} sl={sl:.2f} tp={tp:.2f}")
