"""
MNQ ORB V5 — Pullback-to-midpoint with NDOG/NWOG gap filter
ORB: configurable (default 9:30 for 15 min) | Breakout → confirm bars → pullback to ORB midpoint → entry
Gap filter: blocks entry if ORB edge coincides with overnight/weekly gap level.
Use with 1-min bar export from NT8.
"""
import numpy as np
import backtrader as bt
import pandas as pd
from . import _exec

LABEL       = "MNQ ORB V5 (pullback-to-mid, NDOG/NWOG filter)"
DESCRIPTION = "ORB breakout → N bars confirm → pullback to midpoint. Gap filter blocks entries near gap levels."

PARAM_GRID = {
    'rr_ratio':     [1.0, 1.5, 2.0],
    'orb_minutes':  [11, 15, 20, 30],
    'sl_multiplier':[0.75, 1.0, 1.25],
}

DEFAULT_PARAMS = dict(
    dollar_risk=250.0, rr_ratio=1.5,
    orb_start_hour=9, orb_start_minute=30, orb_minutes=15,
    breakout_bars=5, sl_multiplier=1.0,
    max_trades=2, trade_end_hhmm=1200,
    use_ndog=True, use_nwog=True,
    gap_tolerance_ticks=10, break_buffer_ticks=3,
    printlog=False,
)

POINT_VALUE = 2.0
TICK_SIZE   = 0.25

PH_IDLE=0; PH_FORMING=1; PH_WAITING=2; PH_CONFIRM=3; PH_PULLBACK=4; PH_DONE=5


def precompute(df: pd.DataFrame) -> pd.DataFrame:
    return df

def make_feed(df: pd.DataFrame):
    return bt.feeds.PandasData(dataname=df, datetime=None,
                               open='Open', high='High', low='Low',
                               close='Close', volume='Volume', openinterest=-1)


class Strategy(bt.Strategy):
    params = dict(
        dollar_risk=250.0, rr_ratio=1.5,
        orb_start_hour=9, orb_start_minute=30, orb_minutes=15,
        breakout_bars=5, sl_multiplier=1.0,
        max_trades=2, trade_end_hhmm=1200,
        use_ndog=True, use_nwog=True,
        gap_tolerance_ticks=10, break_buffer_ticks=3,
        printlog=False,
    )

    def log(self, msg):
        if self.p.printlog:
            print(f"{self.data.datetime.datetime(0):%Y-%m-%d %H:%M}  {msg}")

    def __init__(self):
        self._prev_day = None
        # Persistent gap levels (NWOG lasts all week)
        self._ndog_h = self._ndog_l = 0.0; self._ndog_valid = False
        self._nwog_h = self._nwog_l = 0.0; self._nwog_valid = False
        self._prev_day_close  = 0.0; self._day_close_captured  = False
        self._prev_week_close = 0.0; self._week_close_captured = False
        self._reset_daily()

    def _reset_daily(self):
        self._orb_h = -np.inf; self._orb_l = np.inf; self._orb_mid = 0.0
        self._orb_locked = False; self._phase = PH_IDLE
        self._break_dir = 0; self._break_count = 0
        self._long_taken = self._short_taken = False
        # NB: must NOT be named _trades — that shadows bt.Strategy's internal dict
        self._trade_count = 0
        self._day_close_captured = False; self._orb_open_captured = False
        self._ndog_valid = False

    @property
    def _orb_start_hhmm(self):
        return self.p.orb_start_hour * 100 + self.p.orb_start_minute

    @property
    def _orb_end_hhmm(self):
        total = self.p.orb_start_hour * 60 + self.p.orb_start_minute + self.p.orb_minutes
        return (total // 60) * 100 + (total % 60)

    def _gap_blocks(self, orb_level, direction, close):
        tol = self.p.gap_tolerance_ticks * TICK_SIZE
        buf = self.p.break_buffer_ticks  * TICK_SIZE
        blocked = False
        def check(lvl):
            nonlocal blocked
            if lvl == 0 or abs(orb_level - lvl) > tol: return
            if direction ==  1 and close <= lvl + buf: blocked = True
            if direction == -1 and close >= lvl - buf: blocked = True
        if self.p.use_ndog and self._ndog_valid:
            check(self._ndog_h); check(self._ndog_l)
        if self.p.use_nwog and self._nwog_valid:
            check(self._nwog_h); check(self._nwog_l)
        return blocked

    def notify_trade(self, trade):
        if trade.isclosed: self.log(f"TRADE pnl=${trade.pnl:.2f}")

    def next(self):
        t    = self.data.datetime.datetime(0)
        h, l, o, c = self.data.high[0], self.data.low[0], self.data.open[0], self.data.close[0]
        hhmm = t.hour * 100 + t.minute
        day  = t.date()

        if day != self._prev_day:
            # Capture 4 PM close before resetting
            if self._prev_day is not None:
                self._prev_day_close = c; self._day_close_captured = True
                if t.weekday() == 4:  # Friday
                    self._prev_week_close = c; self._week_close_captured = True
            self._prev_day = day
            self._reset_daily()

        # Time exit
        if hhmm >= self.p.trade_end_hhmm and self.position:
            _exec.flatten(self); return

        # Compute gap levels at ORB start
        if hhmm >= self._orb_start_hhmm and not self._orb_open_captured:
            self._orb_open_captured = True
            if self.p.use_ndog and self._prev_day_close > 0 and abs(self._prev_day_close - o) >= TICK_SIZE:
                self._ndog_h = max(self._prev_day_close, o)
                self._ndog_l = min(self._prev_day_close, o)
                self._ndog_valid = True
            if self.p.use_nwog and self._week_close_captured and t.weekday() == 0:
                if abs(self._prev_week_close - o) >= TICK_SIZE:
                    self._nwog_h = max(self._prev_week_close, o)
                    self._nwog_l = min(self._prev_week_close, o)
                    self._nwog_valid = True
                    self._week_close_captured = False

        # ORB formation
        if self._orb_start_hhmm <= hhmm < self._orb_end_hhmm:
            self._phase = PH_FORMING
            self._orb_h = max(self._orb_h, h)
            self._orb_l = min(self._orb_l, l)

        if hhmm >= self._orb_end_hhmm and not self._orb_locked and self._orb_h > -np.inf:
            self._orb_locked = True
            self._orb_mid = (self._orb_h + self._orb_l) / 2.0
            self._phase = PH_WAITING
            self.log(f"ORB locked H={self._orb_h:.2f} L={self._orb_l:.2f} Mid={self._orb_mid:.2f}")

        if not self._orb_locked: return
        if hhmm >= self.p.trade_end_hhmm: return
        if self._trade_count >= self.p.max_trades: return

        # State machine
        if self._phase == PH_WAITING:
            if c > self._orb_h and not self._long_taken:
                if not self._gap_blocks(self._orb_h, 1, c):
                    self._break_dir = 1; self._break_count = 1
                    self._phase = PH_PULLBACK if self.p.breakout_bars <= 1 else PH_CONFIRM
            elif c < self._orb_l and not self._short_taken:
                if not self._gap_blocks(self._orb_l, -1, c):
                    self._break_dir = -1; self._break_count = 1
                    self._phase = PH_PULLBACK if self.p.breakout_bars <= 1 else PH_CONFIRM

        elif self._phase == PH_CONFIRM:
            held = (self._break_dir == 1 and c > self._orb_h) or \
                   (self._break_dir == -1 and c < self._orb_l)
            if held:
                self._break_count += 1
                if self._break_count >= self.p.breakout_bars:
                    self._phase = PH_PULLBACK
            else:
                self._break_dir = 0; self._break_count = 0; self._phase = PH_WAITING

        elif self._phase == PH_PULLBACK and not self.position:
            half = (self._orb_h - self._orb_l) / 2.0
            if self._break_dir == 1:
                if c < self._orb_l: self._break_dir = 0; self._phase = PH_WAITING; return
                if l <= self._orb_mid and not self._long_taken:
                    sl   = self._orb_mid - self.p.sl_multiplier * half
                    risk = c - sl
                    if risk > 0:
                        qty = max(1, int(self.p.dollar_risk / (risk * POINT_VALUE)))
                        _exec.enter_bracket(self, True, qty, sl, c + risk * self.p.rr_ratio)
                        self._long_taken = True; self._trade_count += 1
                        self.log(f"LONG entry={c:.2f} sl={sl:.2f}")
                        self._phase = PH_WAITING if self._trade_count < self.p.max_trades else PH_DONE
            elif self._break_dir == -1:
                if c > self._orb_h: self._break_dir = 0; self._phase = PH_WAITING; return
                if h >= self._orb_mid and not self._short_taken:
                    sl   = self._orb_mid + self.p.sl_multiplier * half
                    risk = sl - c
                    if risk > 0:
                        qty = max(1, int(self.p.dollar_risk / (risk * POINT_VALUE)))
                        _exec.enter_bracket(self, False, qty, sl, c - risk * self.p.rr_ratio)
                        self._short_taken = True; self._trade_count += 1
                        self.log(f"SHORT entry={c:.2f} sl={sl:.2f}")
                        self._phase = PH_WAITING if self._trade_count < self.p.max_trades else PH_DONE
