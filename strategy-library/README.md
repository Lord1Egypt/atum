# Atum Strategy Library

Open-source trading strategies, expert advisors, and technical indicators gathered from
public GitHub repositories — normalized, deduplicated, and organized by runtime so Atum
agents can draw on real, battle-tested logic.

**4405 files · 433 repositories · permissive licenses only.**

---

## Layout

```
strategy-library/
├── pine/
│   ├── strategy/             757  Pine Script strategies (TradingView)
│   └── indicator/           2336  Pine Script indicators
├── mql/
│   ├── expert-advisor/       473  MQL5 expert advisors (MT5)
│   └── expert-advisor-mt4/   189  MQL4 expert advisors (MT4)
├── python/
│   ├── freqtrade/            272  Freqtrade IStrategy classes
│   └── backtrader/           378  Backtrader strategy classes
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
| mit | 3055 |
| mpl-2.0 | 1167 |
| apache-2.0 | 155 |
| bsd-3-clause | 17 |
| unlicense | 8 |
| cc0-1.0 | 3 |

See `ATTRIBUTIONS.md` for the per-repository table and `_manifest.json` for per-file detail.

GPL, AGPL, and unlicensed repositories are excluded, so this library can be used inside
Atum without forcing Atum's own license to change. Files inside permissive repositories
that nevertheless carried GPL headers were removed.

Two things to check before shipping anything derived from this library:

1. **MPL-2.0 files** (1167 files) are file-level copyleft. Use is fine; modifications to those files must stay MPL-2.0.
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

## Provenance and limits

Every manifest entry records: `repo`, `license`, `stars`, `path` (original path in the
upstream repo), `saved` (path in this library), `bytes`, `sha256`, and `commit` (the
upstream commit the file was taken from). `commit_source: "api-head"` marks entries whose
SHA was resolved from the repository's API head rather than a local clone, so a freshly
cloned upstream may be slightly newer than the recorded SHA.

Known limits, stated plainly:

- **Files are not executed here.** A file matching a strategy signature may still be a
  utility, a template, or a partial implementation. Signature matching proves the entry
  point exists, not that the strategy is complete or correct.
- **No byte-identical duplicates** exist within the library, but files that are
  functionally equivalent with different formatting will both be present.
- **Test and conftest files were removed** (129 files) since they are not strategies.
- **Commit SHAs for early entries** come from each repository's current head, which may
  postdate the state the file was taken from.
- **License is per file where a header exists**, otherwise the repository license. This
  is a best-effort read of the header, not a legal determination.

Treat this as a research corpus of untrusted specimens. Nothing in it is wired into the
Atum runtime.

## How it was built

Search the GitHub API across MQL4/MQL5, Pine, Freqtrade, Backtrader, and quant ecosystems;
filter to permissive, non-archived repositories; clone shallowly; extract by code
signature; deduplicate by content hash; record provenance.

To extend it, add repositories to the allow list and re-run extraction. Deduplication is
content-hash based, so re-runs are idempotent and never create duplicates.
