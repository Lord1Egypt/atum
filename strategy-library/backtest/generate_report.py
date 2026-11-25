#!/usr/bin/env python3
"""Generate the final BACKTEST_RESULTS.md from verified run data only."""
import json, os, datetime
from collections import Counter

LIB = "/home/lordegypt/CLaw/strategy-library"
OUT = os.path.join(LIB, "BACKTEST_RESULTS.md")

bt = json.load(open("/tmp/bt_final.json"))
ft = json.load(open("/tmp/ft_results.json")) if os.path.exists("/tmp/ft_results.json") else []

bt_clean = sorted([r for r in bt["ran"] if r.get("trades") and not r.get("degenerate")],
                  key=lambda r: (-(r["win_rate"] or 0), -r["trades"]))
bt_degen = [r for r in bt["ran"] if r.get("degenerate")]
bt_notrade = [r for r in bt["ran"] if not r.get("trades")]
bt_fail = bt.get("failed", [])

ft_ok = [r for r in ft if r.get("ok")]
ft_traded = sorted([r for r in ft_ok if r.get("trades")],
                   key=lambda r: (-(r.get("win_rate") or 0), -(r["trades"] or 0)))
ft_notrade = [r for r in ft_ok if not r.get("trades")]
ft_fail = [r for r in ft if not r.get("ok")]

def table(rows, cols, headers=None):
    headers = headers or cols
    out = ["| " + " | ".join(headers) + " |", "|" + "|".join(["---"] * len(cols)) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(r.get(c, "")) for c in cols) + " |")
    return "\n".join(out)

total = 4405
ran_total = len(bt["ran"]) + len(ft_ok)
traded_total = len(bt_clean) + len(ft_traded)

L = []
L.append("# Backtest Results\n")
L.append("Real runs, 24-month window, demo money. Nothing in this file is estimated or")
L.append("invented — where a strategy could not run, it is listed with the reason.\n")
L.append("| Setting | Value |")
L.append("|---|---|")
L.append("| Window | 2024-11-24 → 2026-11-24 |")
L.append("| Starting balance | 10,000 USD (demo, no real money) |")
L.append("| Leverage | Set to 1:100 (or each expert's declared value) — **had no effect; see note below** |")
L.append("| Commission | 0.02% per side |")
L.append("| Position size | 95% of equity (Backtrader) / 1,000 USD stake (Freqtrade) |")
L.append(f"| Generated | {datetime.date.today().isoformat()} |")
L.append("")

L.append("## The headline\n")
L.append(f"**{traded_total} of {total} files produced a usable backtest.** That is under 1%.\n")
L.append("| Runtime | Files | Executed | Traded | Why the rest did not run |")
L.append("|---|---:|---:|---:|---|")
L.append(f"| Backtrader (Python) | 378 | {len(bt['ran'])} | {len(bt_clean)} | missing deps, local imports, non-strategy code, runtime errors |")
L.append(f"| Freqtrade (Python) | 272 | {len(ft_ok)} | {len(ft_traded)} | needs columns we lack, load failures, long-runtime timeouts |")
L.append("| Pine Script (TradingView) | 3,093 | 0 | 0 | **no open runtime** — executes only in TradingView's cloud |")
L.append("| MQL4 / MQL5 (MetaTrader) | 662 | 0 | 0 | **no Linux runtime** — needs the MT4/MT5 terminal, Windows-only |")
L.append(f"| **Total** | **{total}** | **{ran_total}** | **{traded_total}** | |")
L.append("")
L.append("The two categories you asked about most — **expert advisors (662)** and **Pine")
L.append("strategies (757)** — are precisely the ones with **zero** executable results here.")
L.append("MetaTrader experts need the proprietary MT4/MT5 terminal. Pine Script is not a")
L.append("general-purpose language and has no offline interpreter. Any number I published for")
L.append("those would be fabricated.\n")

L.append("## Backtrader — ranked by win rate\n")
L.append("Completed a run and closed at least one trade. Sorted by win rate, then by trade")
L.append("count so larger samples rank above ties.\n")
L.append(table(bt_clean, ["win_rate", "trades", "return_pct", "symbol", "class", "file"],
              ["Win %", "Trades", "Return %", "Symbol", "Class", "File"]))
L.append("")
ws = [r["win_rate"] for r in bt_clean]
rs = [r["return_pct"] for r in bt_clean]
L.append(f"**{len(bt_clean)} strategies** · mean win rate {sum(ws)/len(ws):.1f}% · "
         f"median {sorted(ws)[len(ws)//2]:.1f}% · mean return {sum(rs)/len(rs):.2f}% · "
         f"{sum(1 for x in rs if x>0)} profitable of {len(rs)}\n")

L.append("### Leverage did not actually apply\n")
L.append("I set 1:100 leverage on the broker and verified it changes nothing: `PercentSizer`")
L.append("allocates a percentage of *cash*, not of margin, so the broker's leverage multiplier")
L.append("never binds. Confirmed empirically — the same strategy at leverage 1 and leverage 100")
L.append("returns identical equity (+59.16% both times). **These results are effectively")
L.append("unleveraged.** That is the safer interpretation, but it is not what you asked for, and")
L.append("you should know the difference.\n")

L.append("### How to read this without fooling yourself\n")
L.append("Win rate is the weakest possible metric, and sorting by it is deliberately")
L.append("provocative:\n")
L.append("- **`rsi_reversion.py` leads at 100% — on 7 trades.** That is a coin-flip sample, not edge.")
L.append("- **`simple_buy_then_sell_live.py` wins only 42% of 257 trades but loses just 5.4%.** Far more informative: a large sample close to breakeven after costs.")
L.append("- Most strategies here traded **4–13 times in two years.** At that frequency, win rate is dominated by noise.")
L.append("- Costs are modeled at 0.02% per side. Real retail spread on these instruments is often wider, which would push most of the thin-margin results negative.\n")
L.append("**A 7-trade sample at 100% is less meaningful than a 257-trade sample at 42%.**\n")

if ft_traded:
    L.append("## Freqtrade — ranked by win rate\n")
    L.append(table(ft_traded, ["win_rate", "trades", "return_pct", "timeframe", "strategy"],
                  ["Win %", "Trades", "Return %", "TF", "Strategy"]))
    L.append("")
    L.append("Freqtrade ran on Binance USDT-margined futures with each strategy's own timeframe")
    L.append("and 1h/5m/15m/30m/4h/6h/1d data downloaded for the window.\n")

L.append("## Ran but never traded\n")
L.append("An inert strategy is not a losing one — its entry conditions never fired on this")
L.append("data, timeframe, or pair.\n")
if bt_notrade:
    L.append(f"**Backtrader ({len(bt_notrade)}):** " +
             ", ".join(f"`{r['class']}`" for r in bt_notrade) + "\n")
if ft_notrade:
    L.append(f"**Freqtrade ({len(ft_notrade)}):** " +
             ", ".join(f"`{r['strategy']}`" for r in ft_notrade) + "\n")

if bt_degen:
    L.append("## Excluded as degenerate\n")
    L.append("These completed but produced impossible equity curves:\n")
    L.append(table([{"ret": f"{r['return_pct']:.1e}", "f": r["file"]} for r in bt_degen],
                  ["ret", "f"], ["Return %", "File"]))
    L.append("")
    L.append("Both repeatedly call `buy()`/`sell()` without checking for an open position,")
    L.append("stacking unbounded exposure that compounds at 100x into 10^133%. That is a")
    L.append("harness artifact, not a trading result. Excluded, not hidden.\n")

L.append("## Failure breakdown\n")
L.append("Reported because the failure rate is itself the finding.\n")
L.append("### Backtrader\n")
bf = Counter(r.get("err", "unknown") for r in bt_fail)
L.append("| Reason | Files |")
L.append("|---|---:|")
for err, n in bf.most_common():
    L.append(f"| {err} | {n} |")
L.append("")
L.append("Most common: `ModuleNotFoundError` — these files import framework-specific modules")
L.append("(`pandas_ta`, `yfinance` variants, private local packages) that are not installed.")
L.append("That is a dependency problem, not a strategy problem, but it still means no result.\n")

L.append("## Method\n")
L.append("""- **Data.** Daily OHLCV from yfinance for 10 instruments, cached once to disk. Freqtrade pulled its own Binance futures candles: 210k 5-minute bars, 17.5k hourly bars, plus 15m/30m/4h/6h/1d.
- **Pair selection.** Each expert ran on the instrument its source names where detectable; EURUSD otherwise.
- **Parameters.** Each expert's declared defaults. No tuning, no optimization, no cherry-picking across settings.
- **Leverage.** Declared value where stated, 1:100 otherwise. All Backtrader runs that completed resolved to 1:100.
- **Isolation.** Every Backtrader run in its own subprocess so one crash cannot poison another.
- **Trade stats.** From Backtrader's trade analyzer and Freqtrade's result table, never derived from the equity curve.
- **Timeframes.** Freqtrade strategies each ran on their own declared timeframe (5m, 15m, 30m, 1h, 4h, 6h, 1d).
""")

L.append("## What this does not tell you\n")
L.append("""- **Not an investment result.** One 24-month window, one or two pairs, one set of defaults each. That is a single sample under one regime.
- **Not coverage of what you asked for.** 85% of the library has no runtime here, including every MetaTrader expert advisor.
- **Not correctness.** Several "strategies" are templates, teaching examples, or utilities that happen to define a strategy class.
- **Not free of look-ahead bias.** Some original code may peek at future bars; I did not audit each file for that. Any such bias inflates results in the strategy's favor.
- **Not realistic execution.** Real spread, slippage, swap and latency on a retail account — especially for scalping systems — would erode most of these thin edges.

Treat this as a census of what executes and what it did, not as a recommendation.
""")
open(OUT, "w").write("\n".join(L) + "\n")
print("wrote", OUT)
print(f"bt_clean={len(bt_clean)} ft_traded={len(ft_traded)} total={traded_total}")
