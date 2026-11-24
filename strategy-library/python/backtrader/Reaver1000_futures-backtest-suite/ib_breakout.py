"""
MES IB Breakout — Initial Balance Breakout
IB: 9:30-10:30 ET (configurable). Entry: previous candle closed outside IB.
SL: IB edge or breakout candle extreme. Configurable RR.
"""
import numpy as np
import backtrader as bt
import pandas as pd
from . import _exec

LABEL       = "MES IB Breakout (Initial Balance)"
DESCRIPTION = "IB formed 9:30-10:30. Previous bar closes outside IB → entry next bar. SL at IB edge or candle."

PARAM_GRID = {
    'rr_ratio':   [3.0, 6.0, 9.0, 12.0],
    'sl_percent': [20.0, 30.0, 40.0, 50.0],
}

DEFAULT_PARAMS = dict(
    dollar_risk=50.0, rr_ratio=6.0,
    ib_start_hour=9, ib_start_minute=30, ib_minutes=60,
    sl_mode='ib_range', sl_percent=40.0, sl_buffer_ticks=9,
    trade_end_hour=15, trade_end_minute=30,
    printlog=False,
)

POINT_VALUE = 5.0   # MES = $5/point. Change to 2.0 for MNQ.
TICK_SIZE   = 0.25


def precompute(df: pd.DataFrame) -> pd.DataFrame:
    return df

def make_feed(df: pd.DataFrame):
    return bt.feeds.PandasData(dataname=df, datetime=None,
                               open='Open', high='High', low='Low',
                               close='Close', volume='Volume', openinterest=-1)


class Strategy(bt.Strategy):
    params = dict(
        dollar_risk=50.0, rr_ratio=6.0,
        ib_start_hour=9, ib_start_minute=30, ib_minutes=60,
        sl_mode='ib_range', sl_percent=40.0, sl_buffer_ticks=9,
        trade_end_hour=15, trade_end_minute=30,
        printlog=False,
    )

    def log(self, msg):
        if self.p.printlog:
            print(f"{self.data.datetime.datetime(0):%Y-%m-%d %H:%M}  {msg}")

    def __init__(self):
        self._reset()
        self._prev_day = None

    def _reset(self):
        self._ib_h = -np.inf; self._ib_l = np.inf
        self._ib_locked = False
        self._long_taken = self._short_taken = False

    @property
    def _ib_start_hhmm(self):
        return self.p.ib_start_hour * 100 + self.p.ib_start_minute

    @property
    def _ib_end_hhmm(self):
        total = self.p.ib_start_hour * 60 + self.p.ib_start_minute + self.p.ib_minutes
        return (total // 60) * 100 + (total % 60)

    @property
    def _trade_end_hhmm(self):
        return self.p.trade_end_hour * 100 + self.p.trade_end_minute

    def notify_trade(self, trade):
        if trade.isclosed: self.log(f"TRADE pnl=${trade.pnl:.2f}")

    def next(self):
        if len(self) < 2: return
        t    = self.data.datetime.datetime(0)
        h, l, c = self.data.high[0], self.data.low[0], self.data.close[0]
        h1, l1, c1 = self.data.high[-1], self.data.low[-1], self.data.close[-1]  # prev bar
        hhmm = t.hour * 100 + t.minute
        day  = t.date()

        if day != self._prev_day:
            self._prev_day = day; self._reset()

        if hhmm >= self._trade_end_hhmm and self.position:
            _exec.flatten(self); return

        # IB formation
        if self._ib_start_hhmm <= hhmm < self._ib_end_hhmm:
            self._ib_h = max(self._ib_h, h)
            self._ib_l = min(self._ib_l, l)

        if hhmm >= self._ib_end_hhmm and not self._ib_locked and self._ib_h > -np.inf:
            self._ib_locked = True
            self.log(f"IB locked H={self._ib_h:.2f} L={self._ib_l:.2f}")

        if not self._ib_locked or hhmm >= self._trade_end_hhmm or self.position: return

        ib_range = self._ib_h - self._ib_l
        buf      = self.p.sl_buffer_ticks * TICK_SIZE

        # Long: previous bar closed above IB high
        if c1 > self._ib_h and not self._long_taken:
            sl = (self._ib_h - (self.p.sl_percent / 100.0) * ib_range
                  if self.p.sl_mode == 'ib_range' else l1 - buf)
            risk = c1 - sl
            if risk > 0:
                qty = max(1, int(self.p.dollar_risk / (risk * POINT_VALUE)))
                _exec.enter_bracket(self, True, qty, sl, c1 + risk * self.p.rr_ratio)
                self._long_taken = True
                self.log(f"LONG  entry~{c1:.2f} sl={sl:.2f}")

        elif c1 < self._ib_l and not self._short_taken:
            sl = (self._ib_l + (self.p.sl_percent / 100.0) * ib_range
                  if self.p.sl_mode == 'ib_range' else h1 + buf)
            risk = sl - c1
            if risk > 0:
                qty = max(1, int(self.p.dollar_risk / (risk * POINT_VALUE)))
                _exec.enter_bracket(self, False, qty, sl, c1 - risk * self.p.rr_ratio)
                self._short_taken = True
                self.log(f"SHORT entry~{c1:.2f} sl={sl:.2f}")
