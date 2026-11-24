"""Base class all strategies inherit from."""
import backtrader as bt
import numpy as np
from . import _exec

POINT_VALUE = 2.0   # MNQ. Change to 20=NQ, 5=MES, 50=ES
TICK_SIZE   = 0.25

def bw_top_at(h, i):
    c = i - 2
    return c >= 2 and h[c-2]<h[c] and h[c-1]<=h[c] and h[c]>=h[c+1] and h[c]>h[i]

def bw_bot_at(l, i):
    c = i - 2
    return c >= 2 and l[c-2]>l[c] and l[c-1]>=l[c] and l[c]<=l[c+1] and l[c]<l[i]

class BaseStrategy(bt.Strategy):
    """
    Subclass this. Override: params, init_strategy(), next_strategy().
    Call self.market_buy(sl, tp) / self.market_sell(sl, tp) to enter.
    """
    params = dict(dollar_risk=100.0, printlog=False)

    # ── Subclass hooks ────────────────────────────────────────────────────────
    def init_strategy(self):  pass
    def next_strategy(self):  pass

    # ── Infrastructure ────────────────────────────────────────────────────────
    def __init__(self):
        self.init_strategy()

    def log(self, msg):
        if self.p.printlog:
            print(f"{self.data.datetime.datetime(0):%Y-%m-%d %H:%M}  {msg}")

    def market_buy(self, sl: float, tp: float):
        pts = abs(self.data.close[0] - sl)
        if pts <= 0: return
        qty = max(1, int(self.p.dollar_risk / (pts * POINT_VALUE)))
        self.log(f"BUY  qty={qty}  sl={sl:.2f}  tp={tp:.2f}")
        _exec.enter_bracket(self, True, qty, sl, tp)

    def market_sell(self, sl: float, tp: float):
        pts = abs(self.data.close[0] - sl)
        if pts <= 0: return
        qty = max(1, int(self.p.dollar_risk / (pts * POINT_VALUE)))
        self.log(f"SELL qty={qty}  sl={sl:.2f}  tp={tp:.2f}")
        _exec.enter_bracket(self, False, qty, sl, tp)

    def next(self):
        self.next_strategy()

    def notify_trade(self, trade):
        if trade.isclosed:
            self.log(f"TRADE closed  pnl=${trade.pnl:.2f}")

    def stop(self):
        if self.p.printlog:
            print(f"  Final: ${self.broker.getvalue():.2f}")
