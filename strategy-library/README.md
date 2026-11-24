# Atum Strategy Library

Open-source trading strategies, expert advisors, and technical indicators gathered from
public GitHub repositories — normalized, deduplicated, and organized by runtime so Atum
agents can draw on real, battle-tested logic.

**4534 files · 433 repositories · permissive licenses only.**

---

## Layout

```
strategy-library/
├── pine/
│   ├── strategy/             757  Pine Script strategies (TradingView)
│   └── indicator/           2338  Pine Script indicators
├── mql/
│   ├── expert-advisor/       473  MQL5 expert advisors (MT5)
│   └── expert-advisor-mt4/   189  MQL4 expert advisors (MT4)
├── python/
│   ├── freqtrade/            294  Freqtrade IStrategy classes
│   └── backtrader/           483  Backtrader strategy classes
├── _manifest.json          Per-file provenance and SHA-256
└── ATTRIBUTIONS.md         Source repo and license for every file
```

Files live at `<category>/<kind>/<owner>_<repo>/`. Filenames are original, with a numeric
suffix on collision.

## What each kind is

| Kind | Runtime | Entry point | Use |
|---|---|---|---|
| `pine/strategy` | TradingView | `strategy(...)` | Full backtestable strategies |
| `pine/indicator` | TradingView | `indicator(...)` | Signal components and studies |
| `mql/expert-advisor` | MetaTrader 5 | `OnTick()` | Complete MT5 trading robots |
| `mql/expert-advisor-mt4` | MetaTrader 4 | `OnTick()` | Complete MT4 trading robots |
| `python/freqtrade` | Freqtrade | `IStrategy` | Crypto strategy classes |
| `python/backtrader` | Backtrader | `bt.Strategy` | Event-driven strategies |

Classification is by code signature rather than filename, so an `.mq5` file with only
indicator callbacks never lands in `expert-advisor/`.

## License mix

| License | Files |
|---|---|
| mit | 3171 |
| mpl-2.0 | 1168 |
| apache-2.0 | 167 |
| bsd-3-clause | 17 |
| unlicense | 8 |
| cc0-1.0 | 3 |

See `ATTRIBUTIONS.md` for the per-repository table and `_manifest.json` for per-file detail.

GPL, AGPL, and unlicensed repositories are excluded, so this library can be used inside
Atum without forcing Atum's own license to change. Files inside permissive repositories
that nevertheless carried GPL headers were removed.

Two things to check before shipping anything derived from this library:

1. **MPL-2.0 files** (1168 files) are file-level copyleft. Use is fine; modifications to those files must stay MPL-2.0.
2. **Vendor example code** under `mql/` bearing a MetaQuotes copyright header should keep that notice.

## Using it with Atum

`strategies/` at the repo root holds Atum's native methodology documents (`smc.md`,
`ict.md`, and so on). This library is raw material, not Atum-native format — no file here
is executed directly by Atum.

To turn a candidate into an Atum strategy:

1. Read its entry conditions.
2. Express the logic as an Atum rule expression, e.g. `"rsi < 30 AND close > sma_50"`.
3. Backtest it: `atum backtest --config strategies/my_rules.yaml`.
4. Compare runs in the strategy arena.

## How it was built

Search the GitHub API across MQL4/MQL5, Pine, Freqtrade, Backtrader, and quant ecosystems;
filter to permissive, non-archived repositories; clone shallowly; extract by code
signature; deduplicate by content hash; record provenance.

To extend it, add repositories to the allow list and re-run extraction. Deduplication is
content-hash based, so re-runs are idempotent and never create duplicates.
