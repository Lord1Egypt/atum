# Atum Strategy Library

A curated collection of open-source trading strategies, expert advisors, and technical
indicators gathered from public GitHub repositories — normalized, deduplicated, and
organized so Atum agents can draw on them.

**1191 files · 131 repositories · all permissively licensed.**

---

## Layout

```
strategy-library/
├── pine/
│   ├── strategy/             95  Pine Script strategies (TradingView)
│   └── indicator/           647  Pine Script indicators
├── mql/
│   ├── expert-advisor/      183  MQL5 expert advisors (MT5)
│   └── expert-advisor-mt4/   81  MQL4 expert advisors (MT4)
├── python/
│   ├── freqtrade/            50  Freqtrade IStrategy classes
│   └── backtrader/          135  Backtrader strategy classes
├── _manifest.json          Per-file provenance and SHA-256
└── ATTRIBUTIONS.md         Source repo and license for every file
```

Files sit under `<category>/<kind>/<owner>_<repo>/`. Names are the originals, with a
numeric suffix on collision.

## What each kind is

| Kind | Runtime | Entry point | Use |
|---|---|---|---|
| `pine/strategy` | TradingView | `strategy(...)` | Full backtestable strategies |
| `pine/indicator` | TradingView | `indicator(...)` | Signal components and studies |
| `mql/expert-advisor` | MetaTrader 5 | `OnTick()` | Complete MT5 trading robots |
| `mql/expert-advisor-mt4` | MetaTrader 4 | `OnTick()` | Complete MT4 trading robots |
| `python/freqtrade` | Freqtrade | `IStrategy` | Crypto strategy classes |
| `python/backtrader` | Backtrader | `bt.Strategy` | Event-driven strategies |

Classification is by code signature, not filename: an `.mq5` file counts as an EA only if
it defines `OnTick`, and a `.pine` file counts as a strategy only if it calls `strategy()`.

## Licensing

Everything here is MIT, Apache-2.0, BSD, MPL-2.0, or Unlicense. See `ATTRIBUTIONS.md` for
the per-repo breakdown and `_manifest.json` for per-file detail.

GPL, AGPL, and unlicensed repositories were deliberately excluded, so this library can be
used inside Atum without forcing Atum's own license to change. If you want the copyleft
corpus too, that is a separate decision — track it separately and do not link it into the
core.

Two things to check before shipping anything derived from this library:

1. **MPL-2.0 files** (106 files) are file-level copyleft. You may use them, but modifications to those files must stay MPL-2.0.
2. **Vendor example code** under `mql/` that carries a MetaQuotes copyright header is published by the vendor for use with their platform; keep the notice.

## Using it with Atum

The `strategies/` directory at the repo root holds Atum's native methodology documents
(`smc.md`, `ict.md`, and so on). This library is raw material, not Atum-native format.

To turn a candidate into an Atum strategy:

1. Pick a strategy file and read its entry conditions.
2. Write the logic as an Atum rule expression, e.g. `"rsi < 30 AND close > sma_50"`.
3. Backtest it: `atum backtest --config strategies/my_rules.yaml`.
4. Compare runs in the strategy arena.

None of these files are executable by Atum directly. They are references and logic sources.

## Refreshing

The library was built by searching the GitHub API, cloning permissive repositories, and
extracting files by code signature. To extend it, add repositories to the allowed list and
re-run extraction — deduplication is content-hash based, so re-runs are idempotent.
