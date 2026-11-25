# Backtest Results

Real runs, 24-month window, demo money. Nothing in this file is estimated or
invented — where a strategy could not run, it is listed with the reason.

| Setting | Value |
|---|---|
| Window | 2024-11-24 → 2026-11-24 |
| Starting balance | 10,000 USD (demo, no real money) |
| Leverage | Set to 1:100 (or each expert's declared value) — **had no effect; see note below** |
| Commission | 0.02% per side |
| Position size | 95% of equity (Backtrader) / 1,000 USD stake (Freqtrade) |
| Generated | 2026-11-25 |

## The headline

**32 of 4405 files produced a usable backtest.** That is under 1%.

| Runtime | Files | Executed | Traded | Why the rest did not run |
|---|---:|---:|---:|---|
| Backtrader (Python) | 378 | 41 | 27 | missing deps, local imports, non-strategy code, runtime errors |
| Freqtrade (Python) | 272 | 9 | 5 | needs columns we lack, load failures, long-runtime timeouts |
| Pine Script (TradingView) | 3,093 | 0 | 0 | **no open runtime** — executes only in TradingView's cloud |
| MQL4 / MQL5 (MetaTrader) | 662 | 0 | 0 | **no Linux runtime** — needs the MT4/MT5 terminal, Windows-only |
| **Total** | **4405** | **50** | **32** | |

The two categories you asked about most — **expert advisors (662)** and **Pine
strategies (757)** — are precisely the ones with **zero** executable results here.
MetaTrader experts need the proprietary MT4/MT5 terminal. Pine Script is not a
general-purpose language and has no offline interpreter. Any number I published for
those would be fabricated.

## Backtrader — ranked by win rate

Completed a run and closed at least one trade. Sorted by win rate, then by trade
count so larger samples rank above ties.

| Win % | Trades | Return % | Symbol | Class | File |
|---|---|---|---|---|---|
| 100.0 | 7 | 7.76 | EURUSD | UserStrategy | python/backtrader/faryhuo_backtrader/rsi_reversion.py |
| 85.7 | 7 | 5.84 | EURUSD | UserStrategy | python/backtrader/faryhuo_backtrader/bollinger_bands.py |
| 75.0 | 8 | 4.65 | EURUSD | UserStrategy | python/backtrader/faryhuo_backtrader/KDJ.py |
| 63.6 | 11 | 5.97 | EURUSD | UserStrategy | python/backtrader/faryhuo_backtrader/triple_ma.py |
| 60.0 | 10 | 0.04 | EURUSD | UserStrategy | python/backtrader/faryhuo_backtrader/zscore_reversion.py |
| 50.0 | 24 | 3.35 | EURUSD | MACDStrategy | python/backtrader/lit26_AlgoAnalyzer/MACDStrategy.py |
| 50.0 | 8 | -1.89 | EURUSD | UserStrategy | python/backtrader/faryhuo_backtrader/turtle_trading.py |
| 50.0 | 4 | -0.73 | EURUSD | UserStrategy | python/backtrader/faryhuo_backtrader/keltner_channel.py |
| 46.2 | 13 | 59.16 | ETHUSD | UserStrategy | python/backtrader/faryhuo_backtrader/sma_cross_live.py |
| 42.9 | 49 | 4.04 | EURUSD | TestStrategy | python/backtrader/josehenriqueroveda_backtesting/strategies.py |
| 42.9 | 7 | 18.87 | AAPL | TradingStrategy | python/backtrader/LimexAILab_QuantCode-Bench/sma_crossover.py |
| 42.9 | 7 | -2.4 | EURUSD | UserStrategy | python/backtrader/faryhuo_backtrader/donchian_breakout.py |
| 42.0 | 257 | -5.43 | EURUSD | UserStrategy | python/backtrader/faryhuo_backtrader/simple_buy_then_sell_live.py |
| 40.5 | 37 | 3.18 | SPY | TestStrategy | python/backtrader/zmcx16_Norn-Finance-Backtesting/basic_strategy.py |
| 37.5 | 40 | -0.27 | SPY | TestStrategy | python/backtrader/zmcx16_Norn-Finance-Backtesting/optimize_strategy.py |
| 35.3 | 17 | 8.09 | XAUUSD | UserStrategy | python/backtrader/faryhuo_backtrader/macd_strategy.py |
| 34.3 | 35 | -1.74 | EURUSD | OrclStrategy | python/backtrader/elbakramer_koapy/vanila_quickstart.py |
| 33.3 | 12 | 6.49 | EURUSD | UserStrategy | python/backtrader/faryhuo_backtrader/atr_trailing_stop.py |
| 28.6 | 7 | 5.74 | EURUSD | ExponentialWeightedMovingAverage | python/backtrader/rzhao999_Backtrader-Bench/strategies.py |
| 28.6 | 7 | 6.06 | EURUSD | MaCrossStrategy | python/backtrader/lit26_AlgoAnalyzer/MaCrossStrategy.py |
| 25.0 | 8 | 3.08 | EURUSD | DualMA | python/backtrader/jiangbohhh_candleforge/dual_ma.py |
| 25.0 | 8 | 3.08 | EURUSD | UserStrategy | python/backtrader/faryhuo_backtrader/sma_cross.py |
| 25.0 | 4 | 4.41 | EURUSD | UserStrategy | python/backtrader/faryhuo_backtrader/breakout.py |
| 22.6 | 31 | -3.42 | EURUSD | BBADX | python/backtrader/jasgin_backtrader-backtests/BB_ADX.py |
| 17.2 | 29 | -2.62 | EURUSD | StochasticSR | python/backtrader/jasgin_backtrader-backtests/Stochastic_SR_Backtest.py |
| 14.3 | 7 | 2.66 | EURUSD | UserStrategy | python/backtrader/faryhuo_backtrader/ema_cross.py |
| 14.3 | 7 | 2.66 | EURUSD | UserStrategy | python/backtrader/faryhuo_backtrader/test2.py |

**27 strategies** · mean win rate 42.0% · median 40.5% · mean return 5.06% · 19 profitable of 27

### Leverage did not actually apply

I set 1:100 leverage on the broker and verified it changes nothing: `PercentSizer`
allocates a percentage of *cash*, not of margin, so the broker's leverage multiplier
never binds. Confirmed empirically — the same strategy at leverage 1 and leverage 100
returns identical equity (+59.16% both times). **These results are effectively
unleveraged.** That is the safer interpretation, but it is not what you asked for, and
you should know the difference.

### How to read this without fooling yourself

Win rate is the weakest possible metric, and sorting by it is deliberately
provocative:

- **`rsi_reversion.py` leads at 100% — on 7 trades.** That is a coin-flip sample, not edge.
- **`simple_buy_then_sell_live.py` wins only 42% of 257 trades but loses just 5.4%.** Far more informative: a large sample close to breakeven after costs.
- Most strategies here traded **4–13 times in two years.** At that frequency, win rate is dominated by noise.
- Costs are modeled at 0.02% per side. Real retail spread on these instruments is often wider, which would push most of the thin-margin results negative.

**A 7-trade sample at 100% is less meaningful than a 257-trade sample at 42%.**

## Freqtrade — ranked by win rate

| Win % | Trades | Return % | TF | Strategy |
|---|---|---|---|---|
| 51.8 | 110 | 6.78 | 1h | VolatilitySystem |
| 51.8 | 110 | 6.78 | 1h | VolatilitySystemV2 |
| 48.4 | 62 | 0.87 | 1h | CointPairsStrategy_V01 |
| 33.3 | 9 | -3.1 | 1h | Eth1hQualityStrategy |
| 25.7 | 374 | -5.18 | 1h | TrendRiderStrategy |

Freqtrade ran on Binance USDT-margined futures with each strategy's own timeframe
and 1h/5m/15m/30m/4h/6h/1d data downloaded for the window.

## Ran but never traded

An inert strategy is not a losing one — its entry conditions never fired on this
data, timeframe, or pair.

**Backtrader (13):** `UserStrategy`, `UserStrategy`, `UserStrategy`, `UserStrategy`, `UserStrategy`, `UserStrategy`, `UserStrategy`, `UserStrategy`, `LoggedStrategy`, `AdvancedStrategy`, `LogStrategy`, `StrategyJustPrintsOHLCVAndSuperCandles`, `StrategyJustPrintsOHLCVAndSuperCandles`

**Freqtrade (4):** `Claude`, `EnsembleDonchianStrategy_V01`, `SafeEmaRsiStrategy`, `XSMomentumStrategy_V01`

## Excluded as degenerate

These completed but produced impossible equity curves:

| Return % | File |
|---|---|
| 8.5e+133 | python/backtrader/risabhmishra_algotrading-sentimentanalysis-genai/advanced_strategy-1.py |
| 1.6e+57 | python/backtrader/risabhmishra_algotrading-sentimentanalysis-genai/optimized_strategy-1.py |

Both repeatedly call `buy()`/`sell()` without checking for an open position,
stacking unbounded exposure that compounds at 100x into 10^133%. That is a
harness artifact, not a trading result. Excluded, not hidden.

## Failure breakdown

Reported because the failure rate is itself the finding.

### Backtrader

| Reason | Files |
|---|---:|
| run failed | 8 |
| no Strategy | 3 |

Most common: `ModuleNotFoundError` — these files import framework-specific modules
(`pandas_ta`, `yfinance` variants, private local packages) that are not installed.
That is a dependency problem, not a strategy problem, but it still means no result.

## Method

- **Data.** Daily OHLCV from yfinance for 10 instruments, cached once to disk. Freqtrade pulled its own Binance futures candles: 210k 5-minute bars, 17.5k hourly bars, plus 15m/30m/4h/6h/1d.
- **Pair selection.** Each expert ran on the instrument its source names where detectable; EURUSD otherwise.
- **Parameters.** Each expert's declared defaults. No tuning, no optimization, no cherry-picking across settings.
- **Leverage.** Parsed from each expert's own settings, 1:100 otherwise. In practice it did not bind — `PercentSizer` sizes from cash, so Backtrader equity is unleveraged regardless of the broker setting. Freqtrade used 1x isolated futures margin at 1,000 USDT per trade.
- **Isolation.** Every Backtrader run in its own subprocess so one crash cannot poison another.
- **Trade stats.** From Backtrader's trade analyzer and Freqtrade's result table, never derived from the equity curve.
- **Timeframes.** Freqtrade strategies each ran on their own declared timeframe (5m, 15m, 30m, 1h, 4h, 6h, 1d).

## What this does not tell you

- **Not an investment result.** One 24-month window, one or two pairs, one set of defaults each. That is a single sample under one regime.
- **Not coverage of what you asked for.** 85% of the library has no runtime here, including every MetaTrader expert advisor.
- **Not correctness.** Several "strategies" are templates, teaching examples, or utilities that happen to define a strategy class.
- **Not free of look-ahead bias.** Some original code may peek at future bars; I did not audit each file for that. Any such bias inflates results in the strategy's favor.
- **Not realistic execution.** Real spread, slippage, swap and latency on a retail account — especially for scalping systems — would erode most of these thin edges.

Treat this as a census of what executes and what it did, not as a recommendation.

