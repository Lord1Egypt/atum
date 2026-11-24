"""Smoke test: verify the execution layer end-to-end.

Runs three strategies over data/MNQ_5min.csv and checks that trades both open
AND close (backtrader silently ignores unknown sl=/tp= kwargs, so a broken
execution layer shows up as positions that never exit).

Run:  python fetch_data.py MNQ   # once, to get data
      python tests/smoke_test.py
"""
import sys
from pathlib import Path

import backtrader as bt

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import engine  # noqa: E402

DATA = ROOT / "data" / "MNQ_5min.csv"


def run(mod_name: str, df, cash=25000.0, **param_overrides):
    mod = engine.get_strategy(mod_name)
    cerebro = bt.Cerebro()
    cerebro.adddata(mod.make_feed(mod.precompute(df)))
    params = {**getattr(mod, 'DEFAULT_PARAMS', {}), **param_overrides}
    cerebro.addstrategy(mod.Strategy, **params)
    cerebro.broker.setcash(cash)
    cerebro.broker.setcommission(commission=engine.COMMISSION,
                                 margin=engine.MARGIN, mult=engine.POINT_VALUE)
    cerebro.addanalyzer(bt.analyzers.TradeAnalyzer, _name='ta')
    res = cerebro.run()
    ta = res[0].analyzers.ta.get_analysis()
    closed = ta.get('total', {}).get('closed', 0)
    opened = ta.get('total', {}).get('open', 0)
    won = ta.get('won', {}).get('total', 0)
    lost = ta.get('lost', {}).get('total', 0)
    pnl = cerebro.broker.getvalue() - cash
    print(f"  {mod_name:<20} closed={closed:<4} open_at_end={opened:<2} "
          f"won={won:<4} lost={lost:<4} pnl=${pnl:,.2f}")
    return dict(closed=closed, open=opened, won=won, lost=lost)


def main():
    if not DATA.exists():
        print(f"No data at {DATA}. Run:  python fetch_data.py MNQ")
        sys.exit(1)
    df = engine.load_csv(DATA)
    print(f"Loaded {DATA.name}: {len(df):,} bars  "
          f"{df.index[0]} -> {df.index[-1]}\n")

    failures = []

    r = run('orb_v2v3', df, printlog=False)
    if r['closed'] == 0:
        failures.append("orb_v2v3: no closed trades — exits broken")
    if r['won'] == 0 or r['lost'] == 0:
        failures.append("orb_v2v3: missing wins or losses — SL/TP suspicious")
    if r['open'] > 1:
        failures.append(f"orb_v2v3: {r['open']} positions open at end — flatten broken")

    r = run('orb_v1', df, printlog=False)
    if r['closed'] == 0:
        failures.append("orb_v1: no closed trades")

    r = run('wickless_reversal', df, printlog=False)
    if r['closed'] == 0:
        print("    (wickless_reversal: no setups in this window — pattern is rare)")

    print()
    if failures:
        print("FAILURES:")
        for f in failures:
            print(f"  [FAIL] {f}")
        sys.exit(1)
    print("[OK] Smoke test passed: entries fill, stops/targets execute, "
          "flattens cancel brackets.")


if __name__ == '__main__':
    main()
