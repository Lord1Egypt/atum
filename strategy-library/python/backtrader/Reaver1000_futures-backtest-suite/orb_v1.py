"""
MNQ ORB V1 — Opening Range Breakout
ORB: 9:15–9:30 ET | Entry: close above/below ORB | SL: candle extreme | RR: 1.5
One trade per direction per day. Exit at noon.
Use with 1-min bar export from NT8.
"""
import numpy as np
import backtrader as bt
import pandas as pd
from . import _exec

LABEL       = "MNQ ORB V1 (9:15-9:30 breakout, 1.5R)"
DESCRIPTION = "ORB formed 9:15-9:30 ET. Breakout close → SL at candle extreme, 1.5R TP, exit noon."

PARAM_GRID = {
    'rr_ratio':    [1.0, 1.5, 2.0, 2.5],
    'dollar_risk': [100, 250, 500],
}

DEFAULT_PARAMS = dict(
    dollar_risk=250.0, rr_ratio=1.5,
    orb_start_hhmm=915, orb_end_hhmm=930,
    trade_end_hhmm=1200,
    printlog=False,
)

POINT_VALUE = 2.0
TICK_SIZE   = 0.25


def precompute(df: pd.DataFrame) -> pd.DataFrame:
    return df   # no HTF needed

def make_feed(df: pd.DataFrame):
    return bt.feeds.PandasData(dataname=df, datetime=None,
                               open='Open', high='High', low='Low',
                               close='Close', volume='Volume', openinterest=-1)


class Strategy(bt.Strategy):
    params = dict(dollar_risk=250.0, rr_ratio=1.5,
                  orb_start_hhmm=915, orb_end_hhmm=930,
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
            self._prev_day = day
            self._reset()

        # Time exit
        if hhmm >= self.p.trade_end_hhmm and self.position:
            _exec.flatten(self); return

        # ORB formation
        if self.p.orb_start_hhmm <= hhmm < self.p.orb_end_hhmm:
            self._orb_h = max(self._orb_h, h)
            self._orb_l = min(self._orb_l, l)

        if hhmm >= self.p.orb_end_hhmm and not self._locked and self._orb_h > -np.inf:
            self._locked = True
            self.log(f"ORB locked  H={self._orb_h}  L={self._orb_l}")

        if not self._locked: return
        if hhmm >= self.p.trade_end_hhmm: return
        if self.position: return

        # Breakout entries
        if c > self._orb_h and not self._long_taken:
            sl   = l
            risk = c - sl
            if risk > 0:
                qty = max(1, int(self.p.dollar_risk / (risk * POINT_VALUE)))
                self.log(f"LONG  entry={c:.2f} sl={sl:.2f} tp={c+risk*self.p.rr_ratio:.2f}")
                _exec.enter_bracket(self, True, qty, sl, c + risk * self.p.rr_ratio)
                self._long_taken = True

        elif c < self._orb_l and not self._short_taken:
            sl   = h
            risk = sl - c
            if risk > 0:
                qty = max(1, int(self.p.dollar_risk / (risk * POINT_VALUE)))
                self.log(f"SHORT entry={c:.2f} sl={sl:.2f} tp={c-risk*self.p.rr_ratio:.2f}")
                _exec.enter_bracket(self, False, qty, sl, c - risk * self.p.rr_ratio)
                self._short_taken = True
