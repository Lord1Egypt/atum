"""Shared backtest engine: data loading, strategy discovery, single-run evaluation.

Every other module in the suite (optimize, walkforward, report, suite) builds on
run_single() so a parameter combo is always evaluated exactly the same way.
"""
import importlib
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import backtrader as bt

ROOT        = Path(__file__).parent
DATA_DIR    = ROOT / "data"
RESULTS_DIR = ROOT / "results"
STRATS_DIR  = ROOT / "strategies"

# Broker model — must match strategy sizing (MNQ micro)
POINT_VALUE  = 2.0
COMMISSION   = 0.62    # $ per contract per side
MARGIN       = 50.0
DEFAULT_CASH = 10000.0


# ── Data ──────────────────────────────────────────────────────────────────────
def load_csv(path) -> pd.DataFrame:
    """Load OHLCV CSV. Handles both formats in use:
    - headered:  dt,Open,High,Low,Close,Volume  with ISO datetimes
    - NT8 raw :  headerless, ';' or ',' separated, YYYYMMDD HHMMSS datetimes
    """
    path = Path(path)
    with open(path) as f:
        first = f.readline()
    sep = ';' if first.count(';') > first.count(',') else ','
    has_header = any(ch.isalpha() for ch in first.split(sep)[0])
    if has_header:
        df = pd.read_csv(path, sep=sep)
        df.columns = [c.strip().capitalize() for c in df.columns]
        dt_col = df.columns[0]
        df[dt_col] = pd.to_datetime(df[dt_col])
        df = df.rename(columns={dt_col: 'dt'})
    else:
        df = pd.read_csv(path, sep=sep, header=None,
                         names=['dt', 'Open', 'High', 'Low', 'Close', 'Volume'])
        df['dt'] = pd.to_datetime(df['dt'].str.strip(), format='%Y%m%d %H%M%S')
    df = df.set_index('dt').sort_index()
    return df[['Open', 'High', 'Low', 'Close', 'Volume']].astype(float)


def slice_dates(df: pd.DataFrame, start=None, end=None) -> pd.DataFrame:
    if start:
        df = df[df.index.date >= pd.to_datetime(start).date()]
    if end:
        df = df[df.index.date <= pd.to_datetime(end).date()]
    return df


def list_data_files():
    DATA_DIR.mkdir(exist_ok=True)
    return sorted(DATA_DIR.glob('*.csv'), key=lambda p: p.stat().st_mtime, reverse=True)


# ── Strategy registry ─────────────────────────────────────────────────────────
def discover_strategies():
    """Return [(stem, label, module)] for every plug-in in strategies/."""
    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))
    found = []
    for f in sorted(STRATS_DIR.glob('*.py')):
        if f.stem.startswith('_'):
            continue
        try:
            mod = importlib.import_module(f"strategies.{f.stem}")
            if hasattr(mod, 'Strategy') and hasattr(mod, 'LABEL'):
                found.append((f.stem, mod.LABEL, mod))
        except Exception as e:
            print(f"  [skip {f.name}: {e}]")
    return found


def get_strategy(stem: str):
    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))
    return importlib.import_module(f"strategies.{stem}")


# ── Analyzers ─────────────────────────────────────────────────────────────────
class TradeRecorder(bt.Analyzer):
    """Records every closed trade with timestamps and net P&L."""
    def start(self):
        self.trades = []

    def notify_trade(self, trade):
        if trade.isclosed:
            self.trades.append({
                'entry':   bt.num2date(trade.dtopen),
                'exit':    bt.num2date(trade.dtclose),
                'dir':     'long' if trade.long else 'short',
                'price':   trade.price,
                'bars':    trade.barlen,
                'pnl':     trade.pnl,
                'pnlcomm': trade.pnlcomm,
            })

    def get_analysis(self):
        return self.trades


class DailyEquity(bt.Analyzer):
    """Records end-of-day broker value plus bar-level max drawdown
    (daily closes alone understate DD on short windows)."""
    def start(self):
        self.rows = []
        self.peak = -np.inf
        self.maxdd_abs = 0.0
        self.maxdd_pct = 0.0

    def next(self):
        d = self.strategy.data.datetime.date(0)
        v = self.strategy.broker.getvalue()
        self.peak = max(self.peak, v)
        dd = self.peak - v
        if dd > self.maxdd_abs:
            self.maxdd_abs = dd
            self.maxdd_pct = dd / self.peak * 100 if self.peak > 0 else 0.0
        if self.rows and self.rows[-1][0] == d:
            self.rows[-1] = (d, v)
        else:
            self.rows.append((d, v))

    def get_analysis(self):
        return {'rows': self.rows,
                'maxdd_$': round(self.maxdd_abs, 2),
                'maxdd_%': round(self.maxdd_pct, 2)}


# ── Metrics ───────────────────────────────────────────────────────────────────
def compute_metrics(trades: list, equity_rows: list, cash: float,
                    bar_dd: dict = None) -> dict:
    """Full performance metrics from a trade list and daily equity curve.
    bar_dd, if given, overrides drawdown with the analyzer's bar-level figure."""
    m = {'trades': len(trades)}
    pnls = np.array([t['pnlcomm'] for t in trades]) if trades else np.array([])
    wins, losses = pnls[pnls > 0], pnls[pnls <= 0]

    m['pnl']         = round(float(pnls.sum()), 2) if len(pnls) else 0.0
    m['win%']        = round(len(wins) / len(pnls) * 100, 1) if len(pnls) else 0.0
    gross_w, gross_l = float(wins.sum()), float(-losses.sum())
    m['profit_factor'] = round(gross_w / gross_l, 2) if gross_l > 0 else (np.inf if gross_w > 0 else 0.0)
    m['expectancy']  = round(float(pnls.mean()), 2) if len(pnls) else 0.0
    m['avg_win']     = round(float(wins.mean()), 2) if len(wins) else 0.0
    m['avg_loss']    = round(float(losses.mean()), 2) if len(losses) else 0.0

    streak = worst = 0
    for p in pnls:
        streak = streak + 1 if p <= 0 else 0
        worst = max(worst, streak)
    m['max_consec_loss'] = worst

    if equity_rows:
        eq = np.array([v for _, v in equity_rows])
        peak = np.maximum.accumulate(eq)
        dd_abs = peak - eq
        m['maxdd_$'] = round(float(dd_abs.max()), 2)
        m['maxdd_%'] = round(float((dd_abs / peak).max() * 100), 2)
        rets = np.diff(eq) / eq[:-1]
        m['sharpe'] = round(float(rets.mean() / rets.std() * np.sqrt(252)), 3) \
            if len(rets) > 1 and rets.std() > 0 else 0.0
    else:
        m['maxdd_$'] = m['maxdd_%'] = m['sharpe'] = 0.0

    if bar_dd:   # bar-level DD catches intraday troughs daily closes miss
        m['maxdd_$'] = bar_dd['maxdd_$']
        m['maxdd_%'] = bar_dd['maxdd_%']

    m['pnl_dd'] = round(m['pnl'] / max(m['maxdd_$'], 1.0), 2)   # return / max-drawdown
    return m


# ── Single evaluation ─────────────────────────────────────────────────────────
def run_single(mod, df_enriched: pd.DataFrame, params: dict,
               cash: float = DEFAULT_CASH, detail: bool = False):
    """Run one backtest. Returns metrics dict; with detail=True also returns
    (metrics, trades_df, equity_df) for reporting."""
    cerebro = bt.Cerebro(stdstats=False)
    cerebro.adddata(mod.make_feed(df_enriched))
    cerebro.addstrategy(mod.Strategy, **params)
    cerebro.broker.setcash(cash)
    cerebro.broker.setcommission(commission=COMMISSION, margin=MARGIN, mult=POINT_VALUE)
    cerebro.addanalyzer(TradeRecorder, _name='tr')
    cerebro.addanalyzer(DailyEquity, _name='eq')
    res = cerebro.run()
    trades = res[0].analyzers.tr.get_analysis()
    eq_an  = res[0].analyzers.eq.get_analysis()
    equity = eq_an['rows']
    metrics = compute_metrics(trades, equity, cash, bar_dd=eq_an)
    if not detail:
        return metrics
    trades_df = pd.DataFrame(trades)
    equity_df = pd.DataFrame(equity, columns=['date', 'equity']).set_index('date') \
        if equity else pd.DataFrame(columns=['equity'])
    return metrics, trades_df, equity_df
