"""Strategy export — bundle a promoted strategy into a self-contained zip the
user can download and run OUTSIDE Strat Hunter.

Freqtrade bundle:  strategy file + a minimal runnable config (pair whitelist
from the job's universe) + README with backtest / dry-run / live commands.
Nautilus bundle:   strategy file + the job's frozen-CLI backtest.py (and
data_prep.py when present) + README covering deps, data catalog, and the
path to live deployment.

Both include metrics.json (discovery vs OOS numbers + provenance).
"""
from __future__ import annotations

import io
import json
import re
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from strathunter import models
from strathunter.config import Config


_FT_CLASS_RE = re.compile(r"^class\s+(\w+)\s*\(\s*IStrategy\s*\)", re.MULTILINE)
_NAUT_CLASS_RE = re.compile(r"^class\s+(\w+)\s*\([^)]*\bStrategy\b[^)]*\)", re.MULTILINE)
_TIMEFRAME_RE = re.compile(r"^\s*timeframe\s*=\s*[\"'](\w+)[\"']", re.MULTILINE)


def _strategy_class(code: str, engine: str) -> str:
    m = (_FT_CLASS_RE if engine == models.ENGINE_FREQTRADE else _NAUT_CLASS_RE).search(code)
    return m.group(1) if m else "UNKNOWN"


def _safe_name(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-") or "strategy"


def _metrics_json(s: models.Strategy, job: models.Job | None, engine: str) -> str:
    universe = dict(job.universe or {}) if job else {}
    universe.pop("prior_proposals", None)  # bulky, irrelevant to running it
    return json.dumps({
        "name": s.name,
        "job_id": s.job_id,
        "engine": engine,
        "market": universe.get("market") or ("crypto" if engine == models.ENGINE_FREQTRADE else ""),
        "hypothesis": (job.hypothesis if job else "") or "",
        "universe": universe,
        "discovery": {
            "return_pct": s.claude_return_pct,
            "win_rate": s.claude_win_rate,
            "max_dd": s.claude_max_dd,
            "trades": s.claude_trades,
        },
        "oos": {
            "return_pct": s.oos_return_pct,
            "win_rate": s.oos_win_rate,
            "max_dd": s.oos_max_dd,
            "trades": s.oos_trades,
            "window": s.oos_window,
            "divergent": s.oos_divergent,
        },
        "created_at": s.created_at.isoformat() if s.created_at else None,
        "exported_at": datetime.now(timezone.utc).isoformat(),
    }, indent=2)


def _metrics_table(s: models.Strategy) -> str:
    def fmt(v, suffix=""):
        return f"{v:.1f}{suffix}" if isinstance(v, (int, float)) else "—"
    return "\n".join([
        "| | Discovery | Independent OOS |",
        "|---|---|---|",
        f"| Return | {fmt(s.claude_return_pct, '%')} | {fmt(s.oos_return_pct, '%')}"
        + (" ⚠ divergent" if s.oos_divergent else "") + " |",
        f"| Win rate | {fmt(s.claude_win_rate, '%')} | {fmt(s.oos_win_rate, '%')} |",
        f"| Max drawdown | {fmt(s.claude_max_dd, '%')} | {fmt(s.oos_max_dd, '%')} |",
        f"| Trades | {s.claude_trades if s.claude_trades is not None else '—'} "
        f"| {s.oos_trades if s.oos_trades is not None else '—'} |",
    ])


_DISCLAIMER = (
    "## Disclaimer\n\n"
    "Backtested performance does not predict future returns. Review the code, "
    "understand the position sizing and stoploss, paper-trade first, and risk "
    "only what you can afford to lose. Nothing here is financial advice.\n"
)


# ── freqtrade ───────────────────────────────────────────────────────────────

def _ft_pairs(job: models.Job | None) -> list[str]:
    universe = (job.universe or {}) if job else {}
    pairs = [str(p) for p in (universe.get("pairs") or []) if p]
    single = str(universe.get("pair") or "")
    if single and single not in pairs:
        pairs = [single, *pairs]
    return pairs or ["BTC/USDT:USDT"]


def _ft_config(pairs: list[str], timeframe: str) -> str:
    return json.dumps({
        "trading_mode": "futures",
        "margin_mode": "isolated",
        "stake_currency": "USDT",
        "stake_amount": "unlimited",
        "max_open_trades": 5,
        "dry_run": True,
        "dry_run_wallet": 1000,
        "timeframe": timeframe,
        "dataformat_ohlcv": "feather",
        "exchange": {
            "name": "binance",
            "key": "",
            "secret": "",
            "pair_whitelist": pairs,
            "pair_blacklist": [],
        },
        "pairlists": [{"method": "StaticPairList"}],
        "entry_pricing": {
            "price_side": "same",
            "use_order_book": True,
            "order_book_top": 1,
            "check_depth_of_market": {"enabled": False, "bids_to_ask_delta": 1},
        },
        "exit_pricing": {
            "price_side": "same",
            "use_order_book": True,
            "order_book_top": 1,
        },
    }, indent=2)


def _ft_readme(s: models.Strategy, job: models.Job | None, *,
               strategy_file: str, strategy_class: str,
               pairs: list[str], timeframe: str) -> str:
    hypothesis = (job.hypothesis if job else "") or "(unknown)"
    return f"""# {s.name} — freqtrade strategy export

> {hypothesis}

Produced by Strat Hunter (job #{s.job_id}).

{_metrics_table(s)}

## Bundle contents

- `{strategy_file}` — the strategy (`{strategy_class}`, INTERFACE_VERSION 3)
- `config.export.json` — minimal runnable config: Binance USDT-M futures,
  static pair whitelist matching the universe it was developed on, dry-run ON
- `metrics.json` — machine-readable provenance + metrics

## Run a backtest

Requires a [freqtrade](https://www.freqtrade.io/) install (2024.x+).

```bash
freqtrade download-data --config config.export.json \\
  --timerange 20250101- -t {timeframe} --trading-mode futures

freqtrade backtesting --config config.export.json \\
  --strategy {strategy_class} --strategy-path . \\
  --timerange 20250101-
```

## Paper-trade (dry run)

`config.export.json` ships with `"dry_run": true` — this simulates fills with
no real orders:

```bash
freqtrade trade --config config.export.json \\
  --strategy {strategy_class} --strategy-path .
```

## Go live

1. Re-validate on a recent window first — edges decay.
2. Put your API keys in `exchange.key` / `exchange.secret` (or use
   `freqtrade new-config` and merge the `pair_whitelist` + timeframe over it).
3. Set `"dry_run": false`, review `max_open_trades`, `stake_amount`, and the
   strategy's `stoploss` / leverage before real money touches it.

Developed against: {", ".join(pairs)} @ {timeframe}.

{_DISCLAIMER}"""


# ── nautilus ────────────────────────────────────────────────────────────────

def _naut_readme(s: models.Strategy, job: models.Job | None, cfg: Config, *,
                 strategy_file: str, strategy_class: str,
                 has_backtest: bool, has_data_prep: bool) -> str:
    universe = (job.universe or {}) if job else {}
    market = universe.get("market", "")
    instruments = [str(i) for i in (universe.get("instruments") or []) if i]
    timeframe = universe.get("timeframe", "1h")
    hypothesis = (job.hypothesis if job else "") or "(unknown)"
    data_dir = cfg.nautilus.resolved_data_dir()

    files = [f"- `{strategy_file}` — the strategy (`{strategy_class}`, a nautilus `Strategy` subclass)"]
    if has_backtest:
        files.append("- `backtest.py` — the job's frozen-CLI backtest runner "
                     "(`--strategy --start --end --out`)")
    if has_data_prep:
        files.append("- `data_prep.py` — the job's data-download helper")
    files.append("- `metrics.json` — machine-readable provenance + metrics")

    backtest_section = f"""## Run a backtest

```bash
pip install nautilus_trader yfinance pandas pyarrow

python backtest.py --strategy {strategy_file} \\
  --start 2026-01-01 --end 2026-07-01 --out results.json
```

`backtest.py` reads OHLCV parquets from the data catalog this job used:

    {data_dir}/yahoo/<SYMBOL><no slash>_<TF>.parquet   (e.g. EURUSD_1h.parquet)

If you're running on another machine, either copy that folder, edit the
catalog path inside `backtest.py`, or rebuild the files with yfinance —
plain OHLCV frames (tz-aware UTC index; open/high/low/close/volume).""" if has_backtest else """## Run a backtest

This job predates the bundled runner — wire the strategy class into a
`nautilus_trader.backtest.engine.BacktestEngine` (add a venue, the
instruments, bar data, then the strategy). See the NautilusTrader docs."""

    return f"""# {s.name} — NautilusTrader strategy export

> {hypothesis}

Produced by Strat Hunter (job #{s.job_id}) on the **{market or "multi-asset"}**
market ({", ".join(instruments) or "instruments in metrics.json"} @ {timeframe}).

{_metrics_table(s)}

## Bundle contents

{chr(10).join(files)}

{backtest_section}

## Going live

The strategy class is portable: nautilus uses the same `Strategy` API for
backtest and live. To trade it for real you wire the class into a
`TradingNode` with a live venue adapter (Interactive Brokers, Binance,
Polymarket, Betfair, dYdX, … — see the `nautilus_trader.adapters` docs),
map the instrument IDs to that venue's, and paper-trade first. Order
management, fills, and risk config carry over; the venue integration and
credentials are the work.

{_DISCLAIMER}"""


# ── bundle builder ──────────────────────────────────────────────────────────

def build_strategy_export(
    s: models.Strategy, job: models.Job | None, cfg: Config,
) -> tuple[bytes, str]:
    """Returns (zip bytes, download filename). Raises FileNotFoundError when
    the strategy file has vanished from disk (workdir cleaned up)."""
    code_path = Path(s.code_path)
    if not code_path.exists():
        raise FileNotFoundError(f"strategy file missing on disk: {code_path}")
    code = code_path.read_text()
    engine = (getattr(job, "engine", "") or models.ENGINE_FREQTRADE) if job else models.ENGINE_FREQTRADE
    strategy_class = _strategy_class(code, engine)
    strategy_file = code_path.name

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(strategy_file, code)
        zf.writestr("metrics.json", _metrics_json(s, job, engine))

        if engine == models.ENGINE_NAUTILUS:
            workdir = Path(job.workdir) if job and job.workdir else None
            has_backtest = has_data_prep = False
            if workdir:
                for helper in ("backtest.py", "data_prep.py"):
                    src = workdir / helper
                    if src.exists():
                        zf.writestr(helper, src.read_text())
                        if helper == "backtest.py":
                            has_backtest = True
                        else:
                            has_data_prep = True
            zf.writestr("README.md", _naut_readme(
                s, job, cfg,
                strategy_file=strategy_file, strategy_class=strategy_class,
                has_backtest=has_backtest, has_data_prep=has_data_prep,
            ))
        else:
            pairs = _ft_pairs(job)
            tf_match = _TIMEFRAME_RE.search(code)
            timeframe = tf_match.group(1) if tf_match else str(
                ((job.universe or {}).get("timeframe") if job else "") or "1h")
            zf.writestr("config.export.json", _ft_config(pairs, timeframe))
            zf.writestr("README.md", _ft_readme(
                s, job,
                strategy_file=strategy_file, strategy_class=strategy_class,
                pairs=pairs, timeframe=timeframe,
            ))

    return buf.getvalue(), f"{_safe_name(s.name)}.zip"
