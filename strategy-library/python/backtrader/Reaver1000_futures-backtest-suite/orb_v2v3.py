"""
MNQ ORB V2/V3 — Opening Range Breakout
ORB: 9:15–9:45 ET | Entry: close above/below ORB | SL: candle extreme | RR: configurable (0.4 default)
One trade per direction per day. Exit at noon.
Use with 1-min bar export from NT8.
"""
import numpy as np
import backtrader as bt
import pandas as pd
from . import _exec

LABEL       = "MNQ ORB V2/V3 (9:15-9:45, 0.4R default)"
DESCRIPTION = "ORB formed 9:15-9:45 ET. Breakout close → SL at candle extreme, configurable RR. Default 0.4R."

PARAM_GRID = {
    'rr_ratio':    [0.3, 0.4, 0.5, 0.6, 0.8, 1.0],
    'dollar_risk': [100, 250, 500],
}

DEFAULT_PARAMS = dict(
    dollar_risk=500.0, rr_ratio=0.4,
    orb_start_hhmm=915, orb_end_hhmm=945,
    trade_end_hhmm=1200,
    printlog=False,
)

POINT_VALUE = 2.0


def precompute(df: pd.DataFrame) -> pd.DataFrame:
    return df

def make_feed(df: pd.DataFrame):
    return bt.feeds.PandasData(dataname=df, datetime=None,
                               open='Open', high='High', low='Low',
                               close='Close', volume='Volume', openinterest=-1)


class Strategy(bt.Strategy):
    params = dict(dollar_risk=500.0, rr_ratio=0.4,
                  orb_start_hhmm=915, orb_end_hhmm=945,
                  trade_end_hhmm=1200, printlog=False)

    def log(self, msg):
        if self.p.printlog:
            print(f"{self.data.datetime.datetime(0):%Y-%m-%d %H:%M}  {msg}")

    def __init__(self):
        self._reset()
        self._prev_day = None

    def _reset(self):
        self._orb_h = -np.inf; self._orb_l = np.inf
        self._locked = False
        self._long_taken = self._short_taken = False

    def notify_trade(self, trade):
        if trade.isclosed:
            self.log(f"TRADE pnl=${trade.pnl:.2f}")

    def next(self):
        t    = self.data.datetime.datetime(0)
        h, l, c = self.data.high[0], self.data.low[0], self.data.close[0]
        hhmm = t.hour * 100 + t.minute
        day  = t.date()

        if day != self._prev_day:
            self._prev_day = day; self._reset()

        if hhmm >= self.p.trade_end_hhmm and self.position:
            _exec.flatten(self); return

        if self.p.orb_start_hhmm <= hhmm < self.p.orb_end_hhmm:
            self._orb_h = max(self._orb_h, h)
            self._orb_l = min(self._orb_l, l)

        if hhmm >= self.p.orb_end_hhmm and not self._locked and self._orb_h > -np.inf:
            self._locked = True

        if not self._locked or hhmm >= self.p.trade_end_hhmm or self.position: return

        if c > self._orb_h and not self._long_taken:
            sl = l; risk = c - sl
            if risk > 0:
                qty = max(1, int(self.p.dollar_risk / (risk * POINT_VALUE)))
                _exec.enter_bracket(self, True, qty, sl, c + risk * self.p.rr_ratio)
                self._long_taken = True
                self.log(f"LONG  entry={c:.2f} sl={sl:.2f} rr={self.p.rr_ratio}")

        elif c < self._orb_l and not self._short_taken:
            sl = h; risk = sl - c
            if risk > 0:
                qty = max(1, int(self.p.dollar_risk / (risk * POINT_VALUE)))
                _exec.enter_bracket(self, False, qty, sl, c - risk * self.p.rr_ratio)
                self._short_taken = True
                self.log(f"SHORT entry={c:.2f} sl={sl:.2f} rr={self.p.rr_ratio}")
