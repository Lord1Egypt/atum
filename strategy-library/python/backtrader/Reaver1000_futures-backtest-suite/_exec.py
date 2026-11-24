"""Bracket-order execution helpers shared by all strategy modules.

WHY THIS EXISTS
---------------
backtrader's buy()/sell() silently IGNORE unknown keyword arguments.
The original modules called  self.buy(..., sl=..., tp=...)  — those sl/tp
values were thrown away, so positions had NO stop and NO target and could
only exit via the few manual close() paths (or never). Every result
produced before this fix is invalid.

Rules:
  * every entry goes through enter_bracket()
  * every manual flatten goes through flatten() so pending bracket children
    are cancelled (a leftover stop/limit child would otherwise fire later
    and open a new, unintended position)
  * break-even / stop moves go through move_stop()
"""
import backtrader as bt


def enter_bracket(strat, is_long, qty, sl, tp):
    """Market entry with attached stop-loss and take-profit (OCO bracket).

    Children only activate after the parent market order fills, and cancel
    each other when one executes (native backtrader bracket semantics).
    """
    fn = strat.buy_bracket if is_long else strat.sell_bracket
    orders = fn(size=qty, exectype=bt.Order.Market, stopprice=sl, limitprice=tp)
    strat._bracket_children = [o for o in orders[1:] if o is not None]
    return orders


def flatten(strat):
    """Cancel pending bracket children, then close any open position."""
    for o in getattr(strat, '_bracket_children', None) or []:
        if o.alive():
            strat.cancel(o)        # cancelling one bracket child cancels its sibling too
    strat._bracket_children = []
    if strat.position:
        strat.close()


def move_stop(strat, is_long, new_stop):
    """Replace the protective stop (e.g. move to break-even).

    Cancelling a bracket child cancels its sibling, so we read the target
    price first, cancel the old pair, and submit a fresh stop+limit pair
    linked by a generic OCO.
    """
    children = getattr(strat, '_bracket_children', None) or []
    stop_o  = next((o for o in children if o.exectype == bt.Order.Stop  and o.alive()), None)
    limit_o = next((o for o in children if o.exectype == bt.Order.Limit and o.alive()), None)
    size = abs(strat.position.size)
    if stop_o is None or size == 0:
        return
    tp_price = limit_o.created.price if limit_o is not None else None
    strat.cancel(stop_o)           # kills the limit sibling as well
    fn = strat.sell if is_long else strat.buy
    new_stop = fn(size=size, exectype=bt.Order.Stop, price=new_stop)
    new_children = [new_stop]
    if tp_price is not None:
        new_children.append(fn(size=size, exectype=bt.Order.Limit, price=tp_price, oco=new_stop))
    strat._bracket_children = new_children
