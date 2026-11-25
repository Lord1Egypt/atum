# Backtest harness

Scripts that produced [BACKTEST_RESULTS.md](../BACKTEST_RESULTS.md). Kept so every number in
that report can be reproduced or disproved.

## Requirements

```bash
pip install backtrader yfinance freqtrade
```

## Backtrader

`run_backtrader.py` runs one strategy in isolation — its own process, so a crash in one file
cannot contaminate another.

```bash
python run_backtrader.py <relative-path-in-library> <SYMBOL>
python run_backtrader.py python/backtrader/jiangbohhh_candleforge/dual_ma.py EURUSD
```

Emits one JSON line on stdout:

```json
{"ok": true, "class": "DualMA", "symbol": "EURUSD", "leverage": 100,
 "return_pct": 3.08, "trades": 8, "win_rate": 25.0, "bars": 516, "degenerate": false}
```

- Starting cash: 10,000 USD
- Commission: 0.02% per side
- Sizing: `PercentSizer(percents=95)`
- Leverage: parsed from the strategy's own settings, else 100

**Known limitation:** `PercentSizer` sizes off cash, not margin, so the broker's leverage
multiplier never binds. Backtrader results are effectively unleveraged. Verified by running
one strategy at leverage 1 and 100 and getting identical equity.

Data is cached to `mktdata/<SYMBOL>.csv`; download 10 instruments once with yfinance before
running a sweep.

## Freqtrade

`freqtrade_config_example.json` is the working config: futures mode, 10,000 USDT dry-run
wallet, 1,000 USDT stake, Binance USDT-margined pairs.

```bash
freqtrade download-data --config freqtrade_config_example.json \
  --pairs BTC/USDT:USDT ETH/USDT:USDT --timeframes 15m 30m 1h 4h 6h 1d \
  --timerange 20241124-20261124

freqtrade backtesting --config freqtrade_config_example.json \
  --strategy <ClassName> --timeframe <its own timeframe> \
  --timerange 20241124-20261124 --export none
```

Parse `Tot Profit %`, `Trades` and `Win%` from the strategy summary table.

## Regenerating the report

```bash
python generate_report.py
```

Reads `bt_final.json` and `ft_results.json` and rewrites `BACKTEST_RESULTS.md`. Edit the
paths at the top for your environment.

## What this harness will not do

It cannot backtest Pine Script (TradingView-only runtime) or MQL4/MQL5 expert advisors
(require the MetaTrader terminal). Those are 3,755 of the 4,405 files in this library. There
is no honest way to produce results for them here.
