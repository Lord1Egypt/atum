"""
WicklessReversal — Wickless candle pattern reversal
Wickless Bull (no bottom wick) → Short | Wickless Bear (no top wick) → Long
SL at candle wick extreme. TP configurable.
"""
import numpy as np
import backtrader as bt
import pandas as pd
from . import _exec

LABEL       = "Wickless Reversal"
DESCRIPTION = "Wickless Bull candle → Short. Wickless Bear candle → Long. SL at wick side."

PARAM_GRID = {
    'sl_ratio':        [0.5, 1.0, 2.0, 3.0],
    'min_body_ticks':  [2, 4, 6, 8, 10],
    'wick_tol_ticks':  [0, 1, 2],
}

DEFAULT_PARAMS = dict(
    dollar_risk=100.0,
    sl_ratio=1.0, use_structural_sl=False,
    min_body_ticks=4, max_body_ticks=0,
    wick_tol_ticks=0,
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
        sl_ratio=1.0, use_structural_sl=False,
        min_body_ticks=4, max_body_ticks=0,
        wick_tol_ticks=0,
        printlog=False,
    )

    def log(self, msg):
        if self.p.printlog:
            print(f"{self.data.datetime.datetime(0):%Y-%m-%d %H:%M}  {msg}")

    def __init__(self):
        pass

    def notify_trade(self, trade):
        if trade.isclosed: self.log(f"TRADE pnl=${trade.pnl:.2f}")

    def next(self):
        o, h, l, c = self.data.open[0], self.data.high[0], self.data.low[0], self.data.close[0]
        wick_tol = self.p.wick_tol_ticks * TICK_SIZE
        min_body = self.p.min_body_ticks  * TICK_SIZE
        body     = abs(c - o)

        if body < min_body: return
        if self.p.max_body_ticks > 0 and body > self.p.max_body_ticks * TICK_SIZE: return

        is_bull = c > o; is_bear = c < o
        bottom_wick = (o - l) if is_bull else np.inf
        top_wick    = (h - o) if is_bear else np.inf

        wickless_bull = is_bull and bottom_wick <= wick_tol
        wickless_bear = is_bear and top_wick    <= wick_tol

        if not wickless_bull and not wickless_bear: return

        if wickless_bull:
            # Reversal: go short
            if self.position.size > 0: _exec.flatten(self)
            entry = c
            if self.p.use_structural_sl:
                sl = h + TICK_SIZE; tp = l
            else:
                sl = max(h + TICK_SIZE, entry + body / self.p.sl_ratio)
                tp = entry - body
            sl_dist = sl - entry
            if sl_dist < TICK_SIZE: return
            qty = max(1, int(self.p.dollar_risk / (sl_dist * POINT_VALUE)))
            _exec.enter_bracket(self, False, qty, sl, tp)
            self.log(f"SHORT entry={entry:.2f} sl={sl:.2f} tp={tp:.2f}")

        elif wickless_bear:
            # Reversal: go long
            if self.position.size < 0: _exec.flatten(self)
            entry = c
            if self.p.use_structural_sl:
                sl = l - TICK_SIZE; tp = h
            else:
                sl = min(l - TICK_SIZE, entry - body / self.p.sl_ratio)
                tp = entry + body
            sl_dist = entry - sl
            if sl_dist < TICK_SIZE: return
            qty = max(1, int(self.p.dollar_risk / (sl_dist * POINT_VALUE)))
            _exec.enter_bracket(self, True, qty, sl, tp)
            self.log(f"LONG  entry={entry:.2f} sl={sl:.2f} tp={tp:.2f}")
