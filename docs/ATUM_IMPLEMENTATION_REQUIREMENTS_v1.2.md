# ATUM — Autonomous Market Research Agents

**Engineering implementation directive for Claude Code**  
**Document:** ATUM-RD-002 / revision 1.2  
**Date:** 2026-11-27  
**Repository:** https://github.com/Lord1Egypt/atum  
**Reviewed baseline:** `9a254ac744d8c274250ee490a5e770b4ad3d9b74` (`main`)  
**Status:** Requirements and implementation handoff; not an implementation or a completed runtime audit.

## 1. Mission and non-negotiable requirements

Upgrade the existing ATUM project into an autonomous, instrumented, economical, multi-market AI research workstation. It must enable an economical LLM to continuously discover, investigate, compare and manage **virtual** trading opportunities across Forex and crypto, using real tools, independently of user chat messages. It must support both historical experiments and forward paper simulation using externally observed market data.

The intended behavior is an active virtual dealing room, not a passive chatbot that prints an analysis, returns Buy/Sell/Hold and stops. An agent should explore opportunities, notice changing conditions, examine competing explanations, use available tools, select appropriate research strategies, manage its fictional positions, review results and continue its assigned experiment without needing another user prompt. It should also recognize when there is no valid opportunity. Activity is not a target in itself.

The owner has access to cTrader market-data APIs and MCP integrations. ATUM must be usable on Linux without MetaTrader, Windows, Wine, or a graphical trading terminal. The owner also requires arbitrary OpenAI-compatible inference endpoints, including OpenCode, and direct providers. OpenRouter is explicitly excluded from the required provider configuration and must never be an implicit dependency or fallback. Deployment must be simple: Docker Compose plus a documented `.env.example`, with persistent state and a working offline demo. Revision 1.1 also requires an AI quantitative workbench with agent-authored indicators and strategies, isolated PineTS evaluation, bounded iterative backtests, programmable multi-chart tools and independent strategy validation; see section 15. Revision 1.2 adds a mandatory deep-research and capability-amplification mandate, configurable research personas, simultaneous multi-server MCP composition, ATUM-owned virtual accounts with scoped API access, token-efficient task contracts and final security verification; see section 16.

Preserve the established research boundary in `docs/ATUM-RD-001.md`, `docs/ATUM_Engineering_Blueprint.txt`, `docs/ATUM_DOCKER_AND_AGENT_ACCOUNTS.md` and `docs/ATUM_STRATEGY_COMPATIBILITY_RESEARCH.md`: **all orders, positions, balances, margin and execution in this scope are fictional.** External market observations may be read-only; no real-money execution, broker order access, funding, withdrawals or external order routing. A real-time market feed is not a real-money execution venue. Do not weaken or silently reinterpret this boundary.

The user has observed a third-party demo system with extremely high reported returns and high activity. Treat this as motivation for research, not verified evidence of an LLM's identity, a reproducible return target, a risk-adjusted edge, or a reason to optimize for leverage or trade count. No claim of profitability may be made from the proposed implementation alone.

**Your role:** act as the lead engineer. Audit, diagnose, plan, implement, test and document. Do not stop after writing recommendations. Preserve the working architecture and validated functionality. Where a required credential, external service or entitlement is absent, implement and verify the contract with fixtures, mark the live-data/provider integration `BLOCKED` or `UNVERIFIED`, and finish the remaining independent work. Do not fabricate evidence.

## 2. Repository audit — perform before feature work

### 2.1 Establish the actual baseline

1. Inspect `git status`, current branch, exact HEAD, recent commits, and all repository-level agent instructions. Preserve existing user changes. Do not reset, force-push, rewrite history, or overwrite unrelated work.
2. Read the four research documents listed above, the README, relevant design documents and `strategy-library/README.md`, `ATTRIBUTIONS.md`, `BACKTEST_RESULTS.md`. Reconcile contradictory claims against executable code and test evidence; research requirements take precedence over README descriptions of optional live venues.
3. Inspect the entire source tree, configuration, migrations, build scripts, Go engine, TypeScript CLI/runtime, React dashboard, SDKs, adapters, analysis, risk, security, memory, event bus, MCP client/server, strategy library catalogue and tests. Inventory all stubs, placeholders, dead configuration, missing wiring, duplicated paths, errors swallowed, incorrect capability flags, and assumptions about accounts or market data.
4. Record dependency/toolchain requirements and build/test logs. The reviewed `go.mod` requires Go 1.25.0, while the README advertises a lower version. Resolve against actual builds; pin the validated versions and lockfiles rather than guessing.
5. Reproduce or reject the preliminary findings below. Assign severity, evidence, owner and regression test. Establish which earlier RD-001 tasks are already complete, still open or superseded. Run baseline tests before modifying behavior.

### 2.2 Preliminary findings from static inspection (not runtime verification)

The baseline tree enumeration contained 4,679 files, including 63 Go test files outside the strategy library. Selected core source files were reviewed through GitHub. No build, test, external API integration or full line-by-line source audit was performed for this handoff. Counts are inventory, not coverage. All findings must be reconfirmed against the actual checkout.

| ID | Severity | Source evidence / issue to reproduce |
|---|---|---|
| RD2-001 | P0 | `internal/agent/tools.go` around L582-L625 and L664-L705: risk check can report allowed when the engine is absent; risk/size calculations begin from a fabricated fallback balance; `execPlaceOrder` calls the adapter directly. Do not rely on prompt-level risk checks or the order tool being called in a particular sequence. |
| RD2-002 | P0 | `internal/adapter/simulation/simulation.go`: in-memory balances, unsupported candles, synthetic spread/book, and sale/limit-order behavior requiring accounting and lifecycle regression tests. Read RD-001 findings ATUM-001 through ATUM-006. |
| RD2-003 | P0 | `internal/mcp/server.go` around L291-L380: inspect hardcoded portfolio and filled-order responses; replace research stubs with real virtual state or explicit unsupported responses, never fabricated successful fills. |
| RD2-004 | P0 | `internal/api/server.go`: broad CORS and no authentication enforcement apparent in reviewed constructor; verify authorization on REST, WebSocket, MCP, chat, experiment controls and account resources. Ensure real execution paths cannot be reached in research deployment. |
| RD2-005 | P0 | `internal/backtest/engine.go`, `portfolio.go`, `data.go`: validate causal fills, short accounting, fee/spread/slippage consistency, true historical range pagination, and deterministic replay. No future candle information or same-bar hindsight. |
| RD2-006 | P1 | `cmd/atum/main.go` around L176-L235: `serve()` initializes Binance and Bybit only in the inspected path; other adapter implementations are not proof of runtime registration. Verify connect/close lifecycle and health; add read-only cTrader/crypto data registration and local simulation wiring. |
| RD2-007 | P1 | `internal/agent/agent.go`: `Run()` is request-driven with hardcoded provider endpoints and a limit of 10 tool iterations. Keep bounded tool use, but provide persistent experiment orchestration independent of chat. |
| RD2-008 | P1 | `internal/agent/context.go` around L50-L175: user-facing assistant prompt and confirmation behavior; portfolio context stops after first connected venue. Separate interactive and autonomous research sessions; include correctly scoped multi-market context. |
| RD2-009 | P1 | `cmd/atum/main.go` L239, L455-L468 and `internal/api/server.go` L72: a context builder receives sub-agent insights separately from the main agent constructed by the API server. Verify and repair the actual insight propagation path, including freshness and account scope. |
| RD2-010 | P1 | `internal/subagent/market_analyst.go`: default five-minute scan, sequential watchlist scan, first connected adapter selection; validate scalability, instrument routing, data freshness, deadlines, and analysis handoff. |
| RD2-011 | P1 | `internal/config/config.go`, `internal/agent/agent.go`, `internal/subagent/llm.go`, `plugins/runtime/src/llm/`: provider logic duplicated; hardcoded base URLs and provider key selection. Implement a consistent configurable provider contract; no implicit OpenRouter. |
| RD2-012 | P1 | `internal/mcp/client.go`, `internal/config/config.go`, `internal/api/server.go`: reviewed external client uses stdio subprocess transport. Add standards-compliant remote Streamable HTTP and safe auth/header configuration; validate actual MCP server capabilities. |
| RD2-013 | P1 | `internal/database/migrations.go`: inspect persistence and ownership of runs, virtual accounts, orders, ledger, budgets and memory; do not infer isolation from existing memory tables. |
| RD2-014 | P1 | No Dockerfile, Compose file or GitHub Actions workflow was present in the enumerated baseline tree outside the strategy library. Implement and verify the existing Docker addendum. Reconcile build/install/package artifacts with the actual frontend and Go requirements. |
| RD2-015 | P1 | `strategy-library/BACKTEST_RESULTS.md` reports only 32 usable backtests from 4,405 files, and leverage configured in some experiments had no effect. This is repository-reported evidence, not a rerun. Do not treat the corpus as thousands of validated runnable strategies. |

Use source permalinks at the reviewed baseline in the audit report, not just mutable branch URLs. Root: https://github.com/Lord1Egypt/atum/tree/9a254ac744d8c274250ee490a5e770b4ad3d9b74

## 3. Target architecture — extend, do not replace

Keep Go as the authoritative engine, SQLite as the initial persistent database, React/TypeScript as the dashboard, existing CLI/SDK contracts and the existing event-driven architecture. Prefer a modular monolith and isolated connector/worker services where needed. Do not introduce Redis, PostgreSQL, Kubernetes or a new language/runtime unless an actual measured need and migration plan justify it.

```text
Read-only data sources                  Approved model providers
cTrader API / read-only MCP             OpenAI-compatible / native / local
Crypto public data / historical files   OpenCode / direct providers / mocks
           |                                         |
           v                                         v
Market Data Service ---------> Research Orchestrator <---- Provider Registry
  normalized observations          |        |                   budgets/usage
  instrument metadata              |        +---- specialized sub-agents
  quality + provenance             v
                              Isolated agent sessions
                              tools / memory / experiments
                                      |
                           typed virtual order proposals
                                      v
                         Deterministic policy + risk gate
                                      v
                        One virtual execution/ledger kernel
                                      |
                   SQLite / immutable datasets / event stream
                                      v
                         Dashboard / reports / replay / arena
```

Separate market-data capabilities from execution capabilities. No externally connected data adapter may be used as an execution adapter merely because an old `TradingAdapter` interface includes `PlaceOrder`. Introduce narrow interfaces and a virtual-only execution gateway; migrate incrementally and retain compatibility for existing safe consumers. Use explicit `(venue, instrument, account, experiment, timestamp)` identities everywhere. One authoritative source of fictional account state must serve chat, tools, MCP, risk, UI and evaluation.

## 4. Forex and crypto data without MT5

### 4.1 cTrader Open API

- Add a read-only cTrader market-data connector, preferably in Go using the documented language-neutral protocol, or an isolated official-SDK connector if a measured compatibility requirement warrants it. The owner already has API access; do not invent their account IDs, application credentials or MCP schemas. Supply placeholders and clear setup instructions. Never require MT5 for this path.
- Implement application/account authentication using the documented OAuth flow with view-only authorization (`accounts` scope). Verify that the supplied grant and chosen account permit the required observations. Reject trading-enabled credentials for this research connector where scope can be determined; if read-only access cannot be established, keep it disabled and report why. Store credentials outside prompts, tool results, reports and source control. Use the lowest required privilege, secure refresh/revocation and redact URL query parameters and authentication errors.
- Consume bid/ask quote updates, historical and live trendbars where available, and instrument metadata: stable provider symbol ID, tick/pip sizes, digits, contract units, volume precision, trading calendar, currency and data timestamps. Do not assume every FX/CFD symbol has an order book, exchange volume, or a meaningful last-trade price. Distinguish actual depth, tick volume, synthetic values and unavailable data.
- Correctly handle initial snapshots, partial bid/ask updates, no-tick intervals, missing bars, spread changes, broker symbol suffixes, time zones/DST, market closures, delayed data and stale subscriptions. Apply provider-documented scaling and normalization with reference fixtures; do not apply crypto quantity assumptions to FX lots.
- Support streaming, heartbeat, connection health, reconnect/backoff, resubscription and bounded history backfill. Current official docs specify a 10-second heartbeat recommendation and rate limits of 50 non-historical / 5 historical requests per second per connection. Verify current rules, budget below them, cache and batch. Respect provider data licenses and usage limits; no account rotation or rate-limit evasion.
- Use separate market-data and account identities. Never interpret cTrader account balance as ATUM's fictional balance or emit provider order requests. A cTrader account is only a permitted data-access context here.

### 4.2 Crypto and historical data

- Reuse and verify Binance/Bybit public market-data capabilities. Add other existing read-only adapters only after proving their registration, normalization and data availability. No private exchange trade keys are needed in the default research deployment.
- Normalize Forex, crypto, metals and other configured instruments through venue-aware symbol metadata. Support configured watchlists or instrument-universe discovery with allowlists; do not scan every available asset blindly. Avoid conflating symbols across venues.
- Provide common historical and forward data contracts, immutable dataset manifests and hashes, explicit time windows, range pagination, gap and duplicate detection, causal replay clock, bounded caches and provenance. Include fixture import and export. No invented candles, fabricated spread, or news inferred from an LLM's training data.
- Provide a deterministic offline dataset and scripted inference fixture. The core must boot and run a meaningful experiment with zero external credentials, network access, MT5 or subscriptions.

**Acceptance:** demonstrate a multi-symbol fictional Forex experiment using recorded cTrader-compatible observations; independently verify the optional read-only connection if owner credentials are available. Demonstrate concurrent crypto and FX data, correct routing and safe handling of missing/stale data. Prove zero external execution requests in these tests.

## 5. MCP integration and tool reliability

Support both inbound and outbound MCP without conflating them. Existing external MCP servers are user-provided, not assumed to have any particular trading functions.

- Extend the existing client to support local stdio and remote Streamable HTTP with standards-compliant initialization, protocol/capability negotiation, tools discovery, schemas, cancellation, deadlines, sessions, reconnects, pagination and typed errors. Support legacy SSE only when an actual configured server requires it. Use a reviewed SDK if appropriate; do not invent a JSON-RPC dialect.
- Configurable server name, URL or command/args, transport, auth mode, secret references, custom headers, enabled flag, timeout, and explicit tool allowlist. Support authorized bearer headers or documented OAuth without exposing tokens to models. Remote URLs must be configured by the operator, not chosen by a model. No shell expansion of model input. Namespaced tool identifiers must prevent collisions.
- Discover and inspect the user's cTrader/data/analysis MCP tools before enabling them. Expose only approved read-only external tools. Route fictional order operations through ATUM's own virtual execution gateway, never through untrusted external MCP tools. A tool description or annotation is not proof it is read-only; review schema, behavior and permissions.
- Add ATUM research MCP endpoints for dataset inspection, market observations, validated indicator calculations, fictional account state, research notes, run status, reports, and scoped fictional proposals. Existing fake/stub tool results must not be shown as executed events. Default deny external broker/exchange order tools, administrative operations, arbitrary shell/files, provider credential access and unrestricted network access.
- Validate JSON/schema and types, normalize units, attach timestamps and source IDs, cap result size, reject invalid/stale values, preserve errors. Implement retries for idempotent reads only and replay-safe identifiers for virtual mutations. Audit each call and outcome without secrets. Treat external tool content and news as untrusted data, not instructions.

**Acceptance:** exercise at least one stdio fixture and one HTTP MCP fixture; test auth failures, server disconnect, malformed tool arguments, conflicting tool names, prompt injection in tool data, forbidden external actions, and successful use of a real approved external read-only tool if available. No dependency on a particular MCP provider for offline CI.

## 6. Universal inference provider layer (mandatory)

The owner must be able to connect a new model by configuring an endpoint, credentials and model ID, without editing Go or TypeScript source. This is essential to selecting inexpensive intelligent research agents and switching between providers.

### 6.1 Provider registry and API support

- Implement a shared provider-neutral contract for chat/inference, tool definitions and calls, results, streaming events, cancellation, timeout, model metadata and usage. Use it in the main agent, sub-agents, interactive chat and experiment runtime; reconcile duplicated Go and plugin-runtime behavior. Maintain existing supported native integrations or document explicit capability limitations.
- **Required:** generic OpenAI-compatible Chat Completions (`/chat/completions`) and configurable OpenAI Responses (`/responses`) for providers/models that require it. Keep native Anthropic Messages and Gemini support where already present. Capability negotiation/configuration must distinguish protocol, streaming, tools, structured output, multimodal inputs, reasoning controls and context limits. A model that returns text is not necessarily compatible with tool calling.
- Define each provider by stable ID, exact base URL, protocol, model ID, credential reference, optional approved headers, capabilities, limits, timeout, retry policy, price metadata and enabled status. Support multiple registered models/providers with per-agent selection, stable aliases and explicit model switching. Avoid blindly appending `/v1` or duplicating an endpoint path. Do not silently rewrite model identifiers or treat the response model name as cryptographic proof of identity.
- Support optional model discovery with provider-specific semantics; manual model entry must work if `/models` is unavailable. Validate with a harmless inference and multi-turn tool-call test. Handle standard OpenAI-style tool call IDs/results, parallel calls, streaming fragments, finish reasons, reasoning-model-specific message requirements where documented, context exhaustion, malformed responses, 401/403/429/5xx and cancellation. Do not force unsupported sampling parameters or reasoning options on every model.
- Per-provider credentials, redacted logging, TLS validation, endpoint allowlists/SSRF protections, bounded HTTP response sizes, explicit connect/read/overall timeouts, limited retry with `Retry-After`, circuit breakers, request/session IDs and concurrency controls. Never transmit another provider's key to a custom base URL; do not accept untrusted redirects for authenticated calls. Local services may use explicit operator-approved internal addresses.
- Support direct DeepSeek, Z.ai/GLM, Alibaba/Qwen, MiniMax, Moonshot/Kimi, other authorized OpenAI-compatible services and local inference. Model names, prices and capabilities must be verified from each provider at test time. OpenRouter must not be required, recommended by the setup wizard, or selected automatically. Preserve legacy compatibility only if appropriate and explicitly enabled by an existing user; do not break unrelated configs gratuitously.
- Use a stable per-agent session identifier when the chosen provider documents such a feature. Keep usage, rate limits, model identity and provider routing observable. No undisclosed fallback, paid conversion or subscription pooling. Fallback is optional, operator-authorized and logged; disable during comparative experiments unless explicitly part of their manifest.

### 6.2 OpenCode support — concrete required test case

OpenCode Console documents official APIs for both pay-as-you-go and Go plans. Use a key from the correct eligible workspace and the correct protocol. The current documented examples are:

| Mode | OpenAI-compatible base URL | Route appended by client |
|---|---|---|
| Console pay-as-you-go | `https://opencode.ai/inference/openai/v1` | `/chat/completions` or `/responses` |
| OpenCode Go | `https://opencode.ai/inference/go/openai/v1` | `/chat/completions` or `/responses` |

Go requires a stable `x-opencode-session` header; follow its current documented session format and scope it to the relevant agent/session. Check current model entitlements and permitted workloads, especially autonomous financial research. Free-tier chat models are documented as restricted to the OpenCode client, so do not assume external API access or attempt to circumvent a 403. Treat denied access as a typed unavailable state. Verify model ID and correct endpoint against the current docs, not a hardcoded marketing name or stale Zen endpoint. Test both OpenAI protocols against mocks; perform a real opt-in test only with authorized credentials, entitlement and usage limits.

Official references: https://opencode.ai/docs/console/api/inference ; https://opencode.ai/docs/console/api/models ; https://opencode.ai/docs/console/harnesses

### 6.3 Subscription/native client support (optional, policy-gated)

Preserve the architecture and constraints in `docs/ATUM_DOCKER_AND_AGENT_ACCOUNTS.md`. The owner may prefer eligible paid subscriptions instead of separate inference keys. Support documented native/authorized mechanisms only: official OpenAI plan-based integrations where eligible, and independently authenticated official clients connecting to scoped research MCP interfaces. Do not harvest CLI tokens, scrape cookies, impersonate consumer services, build a subscription-to-API proxy, evade quotas or silently fall back to separately billed API use. Lack of entitlement is a blocker for that optional integration, not a blocker for ATUM. A separately hosted legitimate AI gateway (including one on the owner's hosting) is simply another explicitly configured compatible endpoint; building it is not a required dependency of this task.

### 6.4 Cost controls and model selection

- Track observed input, output, cached and other billable tokens when supplied, estimated versus actual cost, request count, latency, rate limits, errors and usage per agent, provider, model and experiment. Prices are configurable, timestamped and denominated explicitly; never assume unknown usage is free or a promotional rate is permanent. Validate costs against provider evidence when available.
- Set hard per-run call/token/time limits and configurable monetary budgets (daily and monthly as appropriate). Reserve worst-case allowance before dispatch, reconcile actual usage, pause on unknown or exhausted budget according to policy, and protect concurrent reservations. Require explicit operator approval for nonzero paid runs. Reuse deterministic computed features, batch reads, compact context and retain stable prefixes for documented caching. Never send every market tick to an LLM.
- Evaluate the ordinary supported versions of DeepSeek Flash, GLM Flash, Qwen Flash/Plus, MiniMax Flash and optional stronger Kimi or other models. Verify their current availability and actual identifiers. No need for uncensored/abliterated models. The best research agent is not necessarily the highest general benchmark score, the cheapest advertised token price or the most verbose model. Do not claim a winning model before the controlled arena produces evidence.

**Acceptance:** adding a compliant provider and model requires configuration only; mocked Chat Completions and Responses pass real tool-call round trips; native provider behavior remains tested; paid/Go OpenCode routes and session headers are tested; unavailable models fail explicitly; usage/budget/cancellation tests pass; no request goes through OpenRouter unless explicitly enabled by a legacy operator config, and the delivered profiles never use it.

## 7. Autonomous agent runtime — active research, not a chatbot

### 7.1 Independent execution and lifecycle

- Keep the existing interactive chat mode as a separate supervised session. Create a persistent autonomous **paper experiment** lifecycle: create, start, pause, resume, stop, cancel, fail, complete, recover. Each experiment has an immutable configuration, virtual account, agent identity, provider/model, tool permissions, research objective and budgets. A user starts an experiment once; the system continues without new chat prompts until its approved limits or stopping conditions.
- Implement an event-driven orchestrator using market observations, closed candles, meaningful market/portfolio state changes, scheduled reviews and session boundaries. Include a periodic liveness heartbeat and watchdog, but avoid polling on every tick or spawning unbounded requests. Debounce and coalesce events, prioritize position-management events, deduplicate in-flight work, bound queues and concurrent workers, enforce deadlines and backpressure. Record why a research cycle was triggered, deferred, skipped or rejected.
- Support multiple markets/symbols/timeframes concurrently, with explicit instrument-to-data-source mapping. Isolate agents and experiments; use shared immutable market observations, not shared fictional balances or private memory. Initial research goal is ten independent agent sessions under bounded concurrency, following RD-001. Prove with fixtures before claiming capacity on a real VPS. Model speed and API latency must not be marketed as exchange-grade high-frequency execution.
- Keep bounded tool-iteration limits per cycle; replace the fixed 10-step restriction with configurable per-cycle budgets where justified. Checkpoint state between cycles and resume safely. Agent text alone is not a successful cycle: record typed observations, evidence references, tool calls, hypotheses, decisions and outcomes. A quiet period may be appropriate if data or edge is absent, but inactivity must be observable and explainable.
- On disconnect, stale data, quota exhaustion, invalid output, failed tools, circuit break or operator pause, block new virtual commitments as appropriate; continue safe deterministic monitoring when possible. No infinite retries or automatic policy relaxation. Stop must cancel queued/in-flight work and prevent late actions.

### 7.2 Research capabilities and initiative

Give the agent a flexible research mandate, not a mandatory Buy/Sell formula. Make it possible to compare scalping, bounded grid, momentum, trend following, mean reversion, breakout, price action, multi-timeframe analysis and other reviewed approaches in fictional experiments. Strategy availability must depend on validated implementation and the current dataset; do not declare any strategy automatically profitable. No forced trades, no automatic doubling down or unbounded grid, no objective to recover losses at any cost, and no target of 3,000% returns.

- Provide market-universe scanning and ranking, regime/volatility/spread/liquidity context, multi-timeframe indicators, cross-asset/currency relationships, session/calendar awareness, and genuine time-stamped news/economic information if licensed sources exist. Do not fabricate sentiment, depth, news, or cross-market correlations when unavailable.
- Make tools available for batched observations, price/candles, indicator computation, instrument metadata, validated strategy lookup, portfolio state, hypothesis/backtest/replay requests, risk preview, and virtual order lifecycle. Tools must use actual data with freshness/quality flags. Distinguish observations, computed features, estimates and hypotheses in every decision. Add required tools only when backed by implementation and tests; do not expose placeholders as real capabilities.
- Allow independent investigation of unusual opportunities and alternative explanations. Research agents may propose new strategy hypotheses and testable declarative rules, compare existing strategies, and suggest adaptations. New code or strategies must be reviewed, sandboxed and versioned before use; no self-modifying execution/risk code or automatic arbitrary shell access. Use existing library as research input, not unquestioned instructions.
- A decision can be `observe`, `investigate`, `propose`, `maintain`, `reduce/close virtual position`, `cancel virtual order`, `request experiment`, or `abstain`, subject to the configured policy. Include concise observable justification, data references, assumptions, horizon, invalidation and uncertainty. Do not request or store private hidden chain-of-thought. Uncalibrated model confidence is not evidence or a substitute for risk checks.
- Keep the deterministic execution and monitoring layer responsive while the LLM is slow or offline. In the virtual simulator, protective order semantics and account safeguards are enforced by code rather than waiting for a new generated answer. Each virtual mutation passes the independent gateway in section 8.

### 7.3 Sub-agents and memory

Reuse and verify the existing market analyst, narrative, correlation, devil's advocate, reflection and strategy analysis components. Connect their typed outputs to the actual active agent's context/event stream rather than a disconnected context builder. Allow role-specific model selection and budgets. Parallelize safe independent analyses under explicit limits; no requirement for every role to be a separate paid LLM invocation.

Reuse the five existing memory layers where validated. Record successful and failed hypotheses, outcomes, transaction costs, data regime, uncertainty, strategy version, and post-experiment review. Provide bounded retrieval, relevance/recency, consolidation, retention, and namespace isolation. Separate immutable factual events from tentative learned rules. Verify learned rules against independent evidence before promotion; no uncontrolled online retraining or cross-agent leakage. Support safe reset of a fictional experiment without erasing other accounts or audit history.

**Acceptance:** using a deterministic fixture, start an experiment once, then show independent scans, real tool calls, investigation of multiple symbols, varied research decisions, correctly managed fictional orders/positions, adaptation to changed conditions, and explicit abstention in an unsuitable fixture. Show no user-message dependency, no bypass of policy, bounded compute, checkpoint/restart and successful stop. No profitability claim follows from this demonstration.

## 8. Authoritative virtual execution, accounting and risk (P0 gate)

Implement or repair the shared simulation contract before autonomous virtual mutations are enabled. Address RD-001 and the blueprint's existing correctness findings. This is a virtual accounting and research system, not permission to operate external financial accounts.

- Separate market observation, order intent, risk authorization, accepted virtual order, fill, rejection, cancellation, expiration, reconciliation and audit events. Enforce ownership and permissions at the kernel boundary, not in the system prompt, UI, adapter name or an optional `risk_check` tool. Validate mode, account, instrument, size, price, order type, quote age, available capital/holdings, policy and budget atomically immediately before any mutation. Fail closed on missing/inconsistent state; remove fabricated $10,000 fallbacks and fail-open checks.
- Use exact decimal or a justified fixed-point representation for authoritative balances, prices, quantities, fees and P&L with explicit rounding rules and instrument precision. Existing float-based analytics may remain where independently validated. Persist an append-only ledger and consistent snapshots, order identifiers, idempotency keys, reservations and transaction boundaries. Test conservation, reconciliation, long/short semantics, multi-currency conversion, partial fills, restarts and duplicate event processing.
- Make paper and historical replay use a shared, documented execution model or a conformance-tested equivalent. Support only order types actually implemented. Correctly account for bid/ask, fees, slippage, latency, trading hours, gaps and where modeled, margin, leverage, financing/swaps/funding, stop/limit and partial fills. Label simplified/unsupported features. Do not invent depth/volume, assume fills at unavailable prices, or fill an action before the information used to choose it was observable. Treat OHLC intrabar ambiguities explicitly.
- Risk policy must be independent of model: configurable account/per-position and total exposure bounds, correlated/currency exposure, maximum loss/drawdown, margin constraints, maximum pending/open positions, per-cycle activity, stale-data rejection, concentration, grid bounds, and explicit experiment termination. A suggested risk preview is informational; authorization is enforced centrally at execution time. The model cannot override these controls or change the approved profile.
- Maintain the circuit breaker, dead switch and watchdog, including restart semantics, paused mode, permissions, protective virtual order behavior, and audit. Do not automatically loosen limits after losses, force a recovery trade, or conceal unrealized losses. Define safe default profiles and clearly label all values as experimental settings, not financial recommendations.
- No real order endpoint, external trading scope, deposits or withdrawals in the delivered research profile. Prove the boundary across chat, REST, WebSocket, inbound/outbound MCP, plugins, imported strategies and background jobs. A configuration flag alone is insufficient. Existing live-related code should be excluded or unreachable in this deployment, not silently invoked.

**Acceptance:** property/invariant tests for ledger conservation, insufficient funds/holdings, invalid numbers, duplicate/reordered events, short P&L, spread/costs, pending/cancelled/partial orders where supported, race conditions and cross-account isolation; adversarial attempts to bypass risk, use external order tools, or access another experiment fail. Reproduce the earlier defects and prove their fixes with regression tests.

## 9. Strategy library and scientific model arena

Keep the existing 4,405-file corpus and provenance; the exact count may change at the actual checkout. Follow the dedicated compatibility research document. Classify source language/dialect/version, dependencies, license, strategy versus indicator versus utility, source/hash and verification state. Do not claim Pine/MQL/Python compatibility based on file presence. Preserve original files and notices; sandbox reviewed subset execution, no arbitrary corpus execution or provider credentials in workers. Reuse existing native strategies and verified fixtures first. Any translation must pass semantic conformance tests. Record failures and unsupported cases.

Build a comparative arena for model and strategy experiments, not a leaderboard of raw returns alone:

- Use identical historical replay datasets, initial virtual accounts, costs, risk envelopes, tools, permitted resources, observation availability and budgets. Pin model/provider identifiers, prompt versions, strategy versions, fixture hashes, clock, seeds where possible, code commit and all experiment settings. Keep each agent's memory isolated. Record external LLM nondeterminism; reproducible replay of recorded model responses is distinct from obtaining identical fresh cloud responses.
- Separate development, validation and held-out evaluation windows. Prevent look-ahead, data leakage, survivorship, cherry-picking, and parameter/strategy overfitting. Include varied regimes, spreads, gaps, news-like shocks, stale feed, outages and no-opportunity scenarios. Use deterministic baseline strategies and a no-trade baseline. Run repeated experiments and retain every result, including losses, failures, timeouts and exhausted budgets.
- Track net fictional P&L and returns after modeled costs, equity drawdown including floating losses, profit factor, risk-adjusted metrics with documented sampling conventions, margin/exposure, turnover, trade count/duration, recovery, per-regime performance, activity, invalid action rate, valid opportunity investigation, tool reliability, abstention, missed/duplicate cycles, decision latency and observed/estimated inference cost. Report uncertainty, sample sizes and assumptions. No forced high-frequency trading or optimization against held-out results.
- Compare incremental value of different models, prompts, tools and runtime components separately. Support model-only comparisons under the same harness and ablation tests for memory, scanners and sub-agents. A provider's advertised model name, low price, impressive conversation or public coding benchmark does not establish trading aptitude or weight authenticity. Optionally compare approved provider behavior to an official baseline with non-sensitive tasks, without claiming black-box identity proof.
- Use existing backtest, arena and optimizer code after validating it. Produce machine-readable manifests/results plus HTML/CSV/JSON portfolio reports with order/event IDs, account, symbol, timestamp, cost assumptions, P&L, equity and performance. Explicitly separate fictional results, historical data and externally observed facts. No guaranteed future performance.

**Acceptance:** run a reproducible offline arena using independent mock agents and multiple strategies; demonstrate cost-inclusive accounting, repeatability of recorded replay, out-of-sample evaluation, failed-run retention, export and metric reconciliation. With explicit permission/budget and supported providers, compare economical direct models and OpenCode under identical conditions. If unavailable, report blocked instead of inventing results.

## 10. Docker Compose and easy `.env` configuration (mandatory)

Deliver a production-quality **research appliance**, consistent with the existing Docker addendum. The owner should be able to clone the project, copy one sample environment file, fill only the needed settings and start the dashboard and offline experiment. Do not require manual edits to Go source, Windows, MT5, pip installs on the host, or a running third-party gateway.

### 10.1 Deployment artifacts

Required: multi-stage `Dockerfile`, `compose.yaml`, `.dockerignore`, `.env.example`, validated sample configuration, operator setup/upgrade/backup/restore docs, pinned dependencies and lockfiles, build/test CI, and offline smoke test. Build the real React production UI and Go engine; serve UI/assets correctly rather than requiring Vite dev mode. Pin compatible toolchains using the actual manifest requirements (Go 1.25.0 at baseline); verify CLI/runtime if needed, and fix mismatched README/package metadata. Avoid optional services in the default path unless justified.

- Default Compose service `atum`: core, virtual ledger, runtime, dashboard, HTTP/WS API and fixture experiment support. Optional profiles: `marketdata` (read-only cTrader/crypto/external MCP), `local-llm`, and approved isolated research workers/connectors. External inference and data profiles are opt-in. No live execution profile in this deliverable.
- Persist SQLite WAL on a local volume with transactional versioned migrations and a consistent backup/restore process. Preserve virtual accounts, runs, memory, audit, quotas, datasets and artifacts across restarts/rebuilds. Use distinct volumes/read-only config as appropriate. Define graceful shutdown, readiness/liveness, recovery, safe migrations and restart behavior; do not reset balances on restart or automatically resume a prohibited experiment.
- Non-root runtime, minimal image, dropped capabilities, no privileged mode or Docker socket, bounded resources, read-only root filesystem where feasible, narrow internal networks and explicitly scoped outbound connectivity. Publish only necessary ports; bind host dashboard to loopback by default, allow authenticated HTTPS access via an explicitly configured reverse proxy if desired. Test auth, CORS/origin/WS controls and network isolation. Offline fixture core must run without network; optional connectors may have narrow egress to authorized data/inference sources, never external trading operations.
- Use `.env` for easy non-secret settings and local development credential references; support Docker secrets or the existing encrypted vault for production secrets. `.env`, secret files, databases, logs and local configuration containing credentials must be ignored and excluded from build context. No keys in image layers, examples, test fixtures, command output, telemetry, browser bundles or prompts. Clarify Docker Compose interpolation versus container environment: explicitly map and validate the variables actually consumed by the application. No broad `env_file` injection into every optional service; restrict each service to its own secrets.

### 10.2 Proposed `.env.example` interface

Implement a coherent and tested equivalent of the following example. **These are proposed names, not currently implemented settings.** Adapt naming to existing configuration conventions and document any changes. Defaults must be safe, operational offline and not spend money. Do not create a fake API token. More than one registered provider or MCP server should be configurable through a structured config file referencing environment variables, not a fragile list encoded in one variable. Provide validation and redacted effective-config output. Explicit precedence: defaults < config file < approved environment/secret overrides < authorized runtime session settings, with immutable policy limits never overridden by model output.

```dotenv
# Core / research mode
ATUM_BIND_HOST=127.0.0.1
ATUM_PORT=9090
ATUM_MODE=paper
ATUM_RESEARCH_ONLY=true
ATUM_DATA_DIR=/var/lib/atum
ATUM_DATA_SOURCE=fixture
ATUM_AUTH_SECRET_FILE=
ATUM_LOG_LEVEL=info
TZ=UTC

# Inference: safe offline defaults
ATUM_LLM_PROVIDER=mock
ATUM_LLM_PROTOCOL=chat_completions
ATUM_LLM_BASE_URL=
ATUM_LLM_MODEL=fixture-agent
ATUM_LLM_API_KEY=
ATUM_LLM_API_KEY_FILE=
ATUM_LLM_TIMEOUT_SECONDS=60
ATUM_LLM_MAX_CONCURRENT=2
ATUM_LLM_MAX_TOOL_ITERATIONS=10
ATUM_LLM_MAX_TOKENS_PER_CALL=4096
ATUM_LLM_DAILY_BUDGET_USD=0
ATUM_LLM_MONTHLY_BUDGET_USD=0
ATUM_LLM_ALLOW_PAID=false
ATUM_LLM_FALLBACK_ENABLED=false
# Provider-specific headers/session behavior belong in validated provider config.
# For OpenCode pay-as-you-go example, use the current documented base URL:
# ATUM_LLM_BASE_URL=https://opencode.ai/inference/openai/v1
# For Go, use /inference/go/openai/v1 and configured stable session headers.

# Agent runtime; enabled only by explicit experiment start
ATUM_AGENT_AUTO_START=false
ATUM_AGENT_MAX_SESSIONS=10
ATUM_AGENT_MAX_CONCURRENT=2
ATUM_AGENT_SCAN_INTERVAL_SECONDS=30
ATUM_AGENT_WATCHLIST=EURUSD,XAUUSD,BTCUSDT,ETHUSDT
# Watchlist strings resolve via venue-specific metadata, never guessed mappings.
ATUM_AGENT_MAX_RUN_MINUTES=60

# Read-only cTrader market data (optional, not enabled by default)
ATUM_CTRADER_ENABLED=false
ATUM_CTRADER_ENVIRONMENT=demo
ATUM_CTRADER_SCOPE=accounts
ATUM_CTRADER_CLIENT_ID=
ATUM_CTRADER_CLIENT_SECRET_FILE=
ATUM_CTRADER_ACCESS_TOKEN_FILE=
ATUM_CTRADER_REFRESH_TOKEN_FILE=
ATUM_CTRADER_ACCOUNT_ID=

# Optional crypto data and external MCP
ATUM_CRYPTO_DATA_ENABLED=false
ATUM_MCP_ENABLED=false
ATUM_MCP_CONFIG_FILE=/etc/atum/mcp.yaml
# Example MCP server config uses a URL/command, transport, auth secret ref,
# approved headers, timeout and explicit read-only tool allowlist.

# Optional quantitative workbench (section 15; license/security gated)
ATUM_PINE_ENABLED=false
ATUM_PINE_MAX_WORKERS=1
ATUM_PINE_JOB_TIMEOUT_SECONDS=30
ATUM_PINE_MAX_CONCURRENT_JOBS=1
ATUM_RESEARCH_MAX_ITERATIONS=5
ATUM_CHART_ENGINE=existing

# Optional notifications, no secrets in logs or examples
ATUM_TELEGRAM_ENABLED=false
ATUM_TELEGRAM_TOKEN_FILE=
ATUM_TELEGRAM_CHAT_ID=
```

Expose the actual supported settings in the dashboard/CLI with masked credentials, capability testing, clear errors and per-run configuration. Do not require a person to edit multiple contradictory config files. Distinguish agent run mode, data source, provider auth/plan, and virtual execution mode.

### 10.3 Required setup experience and verification

The following commands express the target workflow; implement/document exact commands supported by the resulting repo:

```bash
git clone https://github.com/Lord1Egypt/atum.git
cd atum
cp .env.example .env
# Default .env must work with offline fixtures and mock inference.
docker compose config --quiet
docker compose up -d --build
docker compose ps
# Dashboard: http://127.0.0.1:9090
# Document an offline fixture experiment smoke command.
# Optional read-only market-data profile after configuring authorized sources:
docker compose --profile marketdata up -d
docker compose logs --tail=100 atum
docker compose stop
```

Do not instruct operators to print effective secret-containing Compose config or use `down -v` as a routine restart. Document how to use a compatible provider by changing `.env` and/or structured provider settings, how to attach a read-only remote MCP server from inside Docker (container loopback is not host loopback), how to enable optional data, how to rotate credentials, how to export reports, and how to pause/stop and backup/restore. Include resource recommendations based on measured results, not arbitrary promises. Verify Linux amd64 and arm64 builds; report unavailable platform/runtime tests explicitly.

## 11. Dashboard, CLI, observability and operational usability

Extend the existing UI rather than rebuilding it. Section 15 adds the agent-driven quantitative workbench and a separately evaluated Vela chart adapter. Show agent/run states, last event/heartbeat, current scan universe and per-venue status, recent observations and tool traces, selected strategies/hypotheses, virtual orders/positions and ledger, account equity and drawdown, data freshness/quality, risk gate outcomes, provider/model/plan, latency, token/cost budgets, experiment comparison, failed-run diagnostics and provenance. Clearly mark fixture, historical replay and forward paper modes. Report unsupported capabilities explicitly. No fabricated numbers in UI. Show an active workstation even when the agent correctly abstains, through actual scan/tool/event telemetry rather than a fake activity animation.

Provide simple operator controls: provider registry and connection test, model selection per agent/role, data/MCP connection status, watchlist, run config, start/pause/resume/stop, budget/permission settings, logs and report export. Use scoped auth and consistent backend API contracts. Maintain backward-compatible CLI/SDK behavior where safe; add tests for any migration. Do not expose secrets via frontend environment variables. Persist run history and events, and retain minimal necessary redacted operational logs. Include health/readiness, metrics, bounded log retention and actionable errors. Optional Telegram/Discord notifications must be opt-in, rate-limited and not leak credentials or private data.

## 12. Delivery order and verification gates

Do the work in small reviewable changes, preserving the existing code. No wholesale rewrite and no final claim of completion based merely on compiling or implementing endpoints. Do not deploy to public hosting or use actual owner credentials without explicit permission. CI must not depend on paid providers.

| Gate | Deliverable | Required evidence before progressing |
|---|---|---|
| G0 | Full audit and baseline | exact revision, file/dependency/config inventory, severity register, reproducible baseline test/build logs and documented blockers |
| G1 | Virtual accounting, risk and security foundation | reproduce/fix P0 defects; invariant, concurrency, isolation, permission and external-execution denial tests; valid migrations and restart behavior |
| G2 | Docker + configuration + offline workflow | clean Compose build, offline mock + fixture run, dashboard/health, persistence, safe stop, backup/restore, secret checks and documented setup |
| G3 | Data and MCP | cTrader read-only protocol fixtures, crypto/historical routing, freshness/reconnect tests, stdio/HTTP MCP conformance and denied external actions; optional real read-only checks |
| G4 | Model registry | OpenAI-compatible Chat Completions and Responses round trips; provider switching, custom headers, OpenCode plan routing/session tests, budgets/cancellation, native provider regressions; no OpenRouter dependency |
| G5 | Autonomous research runtime | agent lifecycle, scheduler, parallel multi-symbol fixtures, role/insight integration, memory isolation, ten independent sessions under bounded resources, restart/pause/stop tests |
| G6 | Strategy evaluation and arena | validated corpus subset, deterministic replay, scientific comparison, cost-inclusive metrics, all failures retained and exportable reports |
| G6A–G6D | Quantitative workbench extension | section 15 license, runtime, builder/backtest, chart and independent validation gates; report each separately |
| G5A–G5D, G6E, G7A | Capability amplification extension | section 16 deep research, profile/runtime, five-server MCP, local virtual accounts/API, model efficiency and security gates; report each separately |
| G7 | Release candidate | full regression suite, UI/CLI/SDK checks, container/cross-platform results, long-running soak with outages, evidence and limitations, reproducible release artifacts; include all section 15 and 16 gate outcomes |

Phases may overlap where independent, but never turn on autonomous virtual mutation before G1 passes. New features must include negative tests and integration coverage rather than only happy-path unit tests. Add fixture coverage for malformed provider messages, failed auth, tool-call replay, missing data, stale price, unsafe MCP tool, cancellation, exhausted credits, clock mismatch, SQLite concurrency, unavailable dependencies, account isolation and crash recovery.

Baseline commands to verify/adapt and record with exit codes (use pinned versions and actual lockfiles):

```bash
git status --short
git rev-parse HEAD
go version
go mod verify
go test ./...
go test -race ./...
go vet ./...
go build ./cmd/atum
# Frontend: install using the committed, validated lockfile and build.
# CLI/plugin runtime: run the existing Bun tests using pinned tooling.
# Docker: compose config --quiet, build, offline smoke, restart and restore.
```

Use the actual repository's package scripts, supported platforms and resource limits. If there are missing lockfiles or tooling, fix reproducibility, report the baseline blocker and capture the subsequent successful result. Run dependency vulnerability checks, secret scanning and container SBOM/security checks using approved tools; record versions and limitations. Set a documented soak-test target (e.g. 24 hours of accelerated fixture stress and an appropriately bounded real-time run where resources permit); do not claim an unperformed duration. Measure CPU/RAM, queue depth, database growth, event throughput, provider call latency, response validity, and cost with the exact hardware/workload. Do not hide failures or fabricate hashes, logs, test counts or passing statuses.

## 13. Final deliverables and stopping conditions

In addition to the code/config changes and tests, maintain the existing RD-001 deliverables or update them in place with clear cross-references. At minimum deliver:

- `docs/REPOSITORY-AUDIT.md`: full scope, baseline, reproduced findings, source references, priorities, disposition and residual risks.
- `docs/ATUM-RD-002-IMPLEMENTATION.md`: implementation decisions and architecture, requirements-to-code/test traceability, compatibility and deviations.
- `docs/DEPLOYMENT.md`: Compose, `.env`, provider and MCP setup, read-only cTrader, local/remote access, offline demo, backups, upgrades, recovery and troubleshooting.
- `docs/PROVIDER-COMPATIBILITY.md`: verified endpoints/protocols, model/plan entitlement, model tool support, key handling, budget semantics and real vs mock validation. No undocumented credentials.
- `docs/TEST-EVIDENCE.md`, `docs/KNOWN-LIMITATIONS.md`, and a final research report with commits, test/build exit codes, reproducible commands, experiment manifests/results, artifacts, hashes where appropriate, and blockers. Reuse earlier report locations if already established; avoid redundant documentation.
- Working Dockerfile, Compose file, `.env.example`, actual wired configuration, updated README, migration scripts and regression tests. CI and offline fixture demo must be runnable from a clean checkout without external keys.

Include the Pine compatibility, AI quantitative workbench and independent strategy validation deliverables defined in section 15, as well as the deep-research, agent profiles, multi-server MCP, virtual account API, model efficiency and final security evidence specified in section 16.

Report each requirement as `PASS`, `FAIL`, `BLOCKED`, or `NOT RUN`, with evidence. Distinguish static review, mocked protocol test, real authorized provider/data test, and successful end-to-end simulation. State what is implemented versus merely proposed. List all assumptions and deviations explicitly. Missing owner credentials or subscriptions must not be filled with guessed values. Do not publish releases or push destructive changes without the owner's direction.

Final verdict: `RESEARCH READY`, `RESEARCH READY WITH LIMITATIONS`, or `NOT RESEARCH READY`, using the existing RD-001 criteria and actual evidence. The minimum successful handoff is a securely isolated, reproducible Dockerized offline research system, configurable OpenAI-compatible inference, validated virtual accounting and autonomous multi-symbol paper experimentation. External provider/market-data/MCP availability may be reported separately as blocked until an authorized integration test. Do not equate high simulated profits with readiness.

## 14. Source register and assumptions

Repository references at baseline:
- https://github.com/Lord1Egypt/atum/tree/9a254ac744d8c274250ee490a5e770b4ad3d9b74/docs
- https://github.com/Lord1Egypt/atum/blob/9a254ac744d8c274250ee490a5e770b4ad3d9b74/cmd/atum/main.go
- https://github.com/Lord1Egypt/atum/tree/9a254ac744d8c274250ee490a5e770b4ad3d9b74/internal
- https://github.com/Lord1Egypt/atum/blob/9a254ac744d8c274250ee490a5e770b4ad3d9b74/strategy-library/BACKTEST_RESULTS.md

Official external references (recheck current capabilities, terms and protocol revisions before integrating):
- cTrader Open API: https://help.ctrader.com/open-api/ ; https://help.ctrader.com/open-api/account-authentication/ ; https://help.ctrader.com/open-api/connection/ ; https://help.ctrader.com/open-api/symbol-data/
- OpenCode Console: https://opencode.ai/docs/console/api/inference ; https://opencode.ai/docs/console/api/models ; https://opencode.ai/docs/console/harnesses ; https://opencode.ai/docs/console/api/providers/
- MCP: https://modelcontextprotocol.io/ ; https://ts.sdk.modelcontextprotocol.io/v2/clients/connect
- OpenAI official plan integration: https://developers.openai.com/siwc/token-sharing-open-source
- Anthropic Claude Code compliance: https://code.claude.com/docs/en/legal-and-compliance

Owner-confirmed requirements (including revision 1.2): existing ATUM architecture; deep capability research and creative engineering beyond the minimum feature list; explicit agent objectives and boundaries; configurable research personas and trading styles; at least five simultaneous MCP integrations; ATUM-owned isolated virtual demo accounts and a scoped research API; small-model harness effectiveness, token efficiency and final security review; autonomous and active multi-market agent research; inexpensive capable model candidates; no OpenRouter dependency; arbitrary OpenAI-compatible providers and OpenCode; cTrader and existing MCP as available read-only data/tools; Linux operation without MT5; Docker Compose and easy environment configuration; the six quantitative workbench capabilities in section 15. The exact cTrader credentials, MCP servers/tool schemas, eligible provider plans, VPS resources, preferred budget, and live-data access are not supplied in this handoff. Defaults, environment-variable names, gate identifiers, and suggested test workload are engineering proposals; validate them and document any necessary adjustment. No repository changes or runtime test results are implied by this document.

## 15. AI quantitative workbench — PineTS, Vela and automated invention of research strategies (mandatory extension)

**Owner requirement added in revision 1.1:** give ATUM's research agents an instrumented charting and quantitative development workstation, inspired by the demonstrated Vela/Quant workflow. The six capabilities below are required research deliverables, not optional marketing features. The original RD-002 requirements and hard virtual-execution boundary remain in force. No rewrite of the Go engine, SQLite ledger or React/TypeScript dashboard is authorized by this extension.

| Capability | Required outcome |
|---|---|
| AI Indicator Builder | Agents can propose, author, validate, version and visualize original indicators against authorized observations. |
| AI Strategy Builder | Agents can propose and develop original experimental strategies, with explicit assumptions, bounded parameters and a reproducible execution contract. |
| PineTS Runtime | Locally evaluate a verified subset of existing and generated Pine scripts in isolated, resource-bounded workers. |
| Automatic Backtest Loop | Iteratively test, diagnose and revise hypotheses within approved experimental budgets and data splits. |
| Chart Manipulation Tools | Agents can inspect and control an instrumented multi-chart research workspace through typed, scoped tools. |
| Strategy Validation | Independently detect compilation/semantic defects, repainting, look-ahead, data leakage, unrealistic fills and overfitting before promotion. |

### 15.1 Upstream investigation, architecture and licensing gate

Evaluate [LuxAlgo/PineTS](https://github.com/LuxAlgo/PineTS) (`pinets`) and [LuxAlgo/Vela](https://github.com/LuxAlgo/Vela) (`@luxalgo/vela`) from exact pinned releases or commits. PineTS advertises native Pine v5/v6 evaluation, custom OHLCV input, time-series calculations, multiple timeframes, plot outputs and a strategy namespace. Upstream calls native language support experimental and does not promise full compatibility. Vela provides a headless financial chart and optional multi-chart workspace with pluggable data, drawing and scripting interfaces. The separate `@luxalgo/vela-pinets` addon connects them. The hosted Quant assistant and its model, prompts and proprietary services are not established as part of these open-source packages. Implement ATUM's own agent workflow; do not depend on the hosted service or copy proprietary components.

License gate: ATUM is MIT. PineTS offers AGPL-3.0 or a commercial license. The Vela core is Apache-2.0 with NOTICE/visible attribution requirements; the Vela PineTS addon is AGPL-3.0. Verify actual license files, release metadata, dependencies, upstream notices and the legal implications of integration, redistribution and network access before shipping. Do not assume that a subprocess, IPC boundary, separate repository or container automatically eliminates copyleft obligations. Do not change ATUM's license, remove upstream attribution, ship a potentially incompatible combined work, or acquire a paid license without explicit owner approval. Keep the core independently functional and evaluate the optional PineTS research integration only under a reviewed permitted arrangement. If distribution terms cannot be resolved, report `BLOCKED: LICENSE`, retain the workbench contracts and fixture tests, and provide a documented compatible alternative rather than claiming completion. Do not treat an optional profile as legal clearance.

Proposed architecture (adapt names to the repository):

```text
ATUM agent runtime / research orchestrator
  | typed hypothesis, indicator, strategy and chart tools
  v
Go research API / artifact registry / experiment policy
  | approved source + immutable causal dataset + bounded job
  v
Isolated PineTS compatibility worker (optional Compose profile)
  | typed plot series, diagnostics, experimental intent events
  v
Go validator + authoritative virtual simulation / backtest kernel
  | canonical events, virtual ledger, metrics, artifact provenance
  v
React dashboard / Vela chart adapter / report and replay workspace
```

The Go core owns experiment identity, clocks, permissions, evaluation and all authoritative virtual accounting. A chart renderer is not a source of market facts. PineTS's internal strategy results, if used, are a separate reference/compatibility result and must not silently replace the canonical ledger. Detect discrepancies and label unsupported semantics. If a strategy depends on its internal position state or fill timing, verify equivalence or explicitly limit its supported subset. Never show two incompatible equity curves as though they are the same result.

### 15.2 AI Indicator Builder and AI Strategy Builder

Provide first-class versioned research artifacts with stable IDs, source hash, parent revision, author/agent and model/provider identifiers, prompt/template version, language/version, dependency and license references, intended instruments/timeframes, input schemas and defaults, causal data requirements, hypothesis and assumptions, validation status, experiment IDs and diagnostic records. Preserve generated source and negative results; a code revision creates a new artifact, not an invisible overwrite of an existing experiment.

- Indicator Builder: let agents discover the existing indicator catalogue, compose or author new native/Pine-subset indicators, define typed parameters and expected plot outputs, run bounded evaluations, inspect compilation/runtime diagnostics, compare outputs against analytical reference fixtures and visualize results on any authorized chart. Separate source, numeric output series and visualization specifications. Support overlays, subpanels, lines, zones and markers with timestamps and provenance. Labels must distinguish derived or hypothetical signals from actual virtual fills.
- Strategy Builder: let agents formulate original research hypotheses, combine validated indicators, express and version experimental entry/exit logic and position-management rules in an approved runtime, and request controlled evaluation. Do not constrain research to a fixed list of pre-existing strategies, or assume novelty from a name change. For generated code, require review/classification, dependency inventory, static checks and isolated execution before use. Unsupported constructs fail with diagnostic errors. Neither builder can modify the engine, risk limits, account ownership, dataset splits, host configuration or permissions.
- Make parameters editable and inspectable in the dashboard with typed schema validation and revision history. Provide an indicator/strategy editor with source diff, preview, compile diagnostics, validation report, dependency graph, run history and explicit status. Keep the existing strategy corpus immutable; generated or adapted artifacts live separately and retain attribution.

Suggested tool contracts (names are proposals): `list_indicators`, `list_strategies`, `describe_runtime_capabilities`, `create_indicator_draft`, `create_strategy_draft`, `revise_artifact`, `validate_artifact`, `evaluate_indicator`, `submit_backtest`, `get_experiment_status`, `get_experiment_report`, `compare_experiments`, `cancel_experiment`. Validate schemas, scope resources to run/agent identity and enforce budgets before dispatch. Expensive work is a cancellable queued job, not a long blocking chat request. A tool returning success must correspond to persisted state and real evidence, not hardcoded demo responses.

### 15.3 PineTS compatibility runtime and corpus validation

Implement a small proof of concept before enabling bulk evaluation. Read the current PineTS language/API coverage and strategy semantics at the pinned version. Feed ATUM-owned OHLCV fixtures (explicit symbol, venue, timeframe, open/close timestamp, units and quality metadata) rather than exposing provider keys or network access to the script. Keep multi-timeframe data causal and aligned to the experiment clock. Define a versioned IPC request/response schema with source hash, dataset hash, input parameters, evaluation boundary, run identity, deadline, runtime version, seed where applicable, numeric series, plot/drawing outputs, typed errors and resource consumption. Use a local worker transport approved by the security review. Workers do not own authoritative accounts.

Process the existing Pine corpus through classification, static capability inventory and license/provenance gates. Distinguish actual indicators, strategies and unrelated files; distinguish v5/v6 support, older language versions, unsupported APIs, library/import dependencies and runtime errors. Check the current corpus count and do not infer compatibility from the previous inventory. Record per-file and per-feature counts for parse, compile, evaluate and semantic conformance success separately. Preserve failing samples and distinguish syntax support from behaviorally verified strategy execution. Do not advertise all 3,093 previously reported Pine files as runnable.

Enforce a hardened worker boundary: isolated non-root process/container, deny arbitrary filesystem, shell, secrets, host access, external network, dynamic downloads/imports and external order APIs; approved local dependencies only; bounded input size, output size, wall-clock time, loop iterations, memory, CPU, concurrent jobs and temporary storage. Use an externally supervised kill/cancel path for blocked synchronous code. An upstream execution timeout or JavaScript worker alone is not sufficient containment for untrusted code. Test exhaustion, malicious source, malformed IPC, dependency failures, worker crash, cancellation and recovery. Where stronger isolation is required, use it or mark execution blocked. Keep default offline core independent of this optional runtime and never automatically install unreviewed packages or skills.

### 15.4 Automatic Backtest Loop — bounded, auditable research iteration

Add a persistent research job state machine: `DRAFT -> VALIDATING -> QUEUED -> RUNNING -> EVALUATED -> REVIEWED/REVISE/REJECTED`, plus `FAILED`, `CANCELLED`, `BUDGET_EXHAUSTED` and `BLOCKED` states. Suggested names may change; state transitions and their evidence must be enforced. An agent can initiate a bounded experiment without a fresh chat turn, inspect the diagnostics, explain a plausible failure, propose a versioned revision and request the next authorized test. Store the parent-child experiment lineage, reason for revision, differences, configuration, observed output, baseline and cumulative budget. Stop on declared evaluation or resource limits, invalid data, policy violation, cancellation or no meaningful hypothesis improvement. Do not force continuous trade activity, endless model calls or repeated optimization against a held-out period.

Use immutable train/development/validation/held-out data partitions and a walk-forward methodology appropriate to the experiment. Every iteration must retain both successes and failures, record changes and costs, and compare against unchanged baselines using the same simulator and risk constraints. Do not expose future observations or held-out evaluation feedback to the optimization loop. After a strategy is selected, evaluate it independently under predeclared assumptions, across multiple instruments/regimes where appropriate, with cost and sensitivity analysis. Prevent the agent from redefining success metrics after seeing results. A profitable fixture run is not sufficient to promote an artifact or establish predictive ability.

### 15.5 Chart Manipulation Tools and Vela research workstation

Evaluate the existing `web/src/components/PriceChart.tsx`, `TradingViewChart.tsx`, replay components and API hooks; add a renderer-agnostic chart workspace contract. Retain existing working charts until an evidence-backed comparison justifies migration. Vela core is the preferred candidate for an optional prototype, not an unconditional replacement. Use ATUM's normalized data and canonical event stream; do not open uncontrolled provider connections from chart scripts. Preserve React/TypeScript, accessibility, navigation and saved workspace state.

Support multiple synchronized charts and symbol/timeframe selection, zoom/range and cursor synchronization, indicator overlays and separate panes, drawings/annotations, hypothetical setup markers, historical/virtual entry and exit markers, SL/TP visualization, replay clock controls, strategy metrics and experiment/report linking. Show data provenance, quote time, fixture/replay/forward-paper mode and stale-data status. A user must be able to inspect what the agent changed, undo or reset view-only changes, and distinguish an agent-authored chart annotation from a recorded virtual order. Render the same versioned plot series that were validated, not an independently recalculated unverified approximation.

Example agent-facing chart tools: `list_charts`, `open_chart`, `set_symbol`, `set_timeframe`, `set_view_range`, `get_chart_data`, `get_chart_snapshot`, `add_indicator_overlay`, `remove_indicator_overlay`, `annotate_chart`, `draw_research_level`, `link_experiment`, `get_workspace_state`. A chart snapshot may be a bounded image if supported by the provider, but canonical numerical observations must remain available to non-vision models. The agent must be able to inspect charts and add useful evidence-based drawings without user clicks, within its authorized workspace. Reject cross-workspace access, untrusted markup/code, oversized snapshots and stale handles. A chart tool may never change risk policy or dispatch an order directly. Provide audit events and scopes for tool mutations; use structured data rather than arbitrary browser JavaScript or unrestricted desktop access.

### 15.6 Independent strategy validation and promotion

Implement an independent validator, not merely a second LLM opinion. Check syntax and declared capability support, numeric outputs and warm-up behavior, parameter types/ranges, time alignment, causal execution, historical vs incremental behavior, deterministic fixtures, repainting and future-data leakage, spread/fee/slippage assumptions, order lifecycle and virtual ledger reconciliation. Compare independently computed analytical fixtures and, where legally available, authorized reference results; document version differences and numerical tolerances. Distinguish legitimate intrabar recalculation on an open candle from historical signals changing after a bar has closed. Include prefix-invariance tests (closed-bar outputs on a prefix remain stable after appending future bars), multi-timeframe confirmation and gap cases, negative controls with intentionally leaky/repainting scripts and repeated-run checks. Block promotion on critical mismatches or uncertain behavior; allow clearly labeled research-only exploratory artifacts where appropriate. Never equate a clean compile or a visually compelling chart with strategy correctness.

Required artifact states include draft, statically checked, fixture verified, semantically validated, unsupported, quarantined and rejected. Any changes to source, dependencies, runtime version, relevant data contract or evaluation assumptions invalidate affected verification. The validator and Go kernel must reject unauthorized mutation even if the generating model claims the artifact is safe. Keep real execution unreachable; strategy suggestions produce bounded fictional experiment intents only.

### 15.7 Integration into Compose, dashboard and release gates

Extend section 10's Compose contract with an optional `pine-research` worker profile, disabled by default until license/security gates are satisfied. The core fixture demo must still work without PineTS, Vela addon or internet. The Vela core may be evaluated independently of the Pine addon under its own license. Pin package versions and lockfiles, include approved dependencies in SBOM and notices, define private IPC and health checks, cap workers and storage, persist versioned artifacts/reports under core ownership, and add offline fixtures and mocked worker tests to CI. Do not place provider keys in the worker environment. Document the exact optional Compose startup command, health status, license requirements, resource limits and supported compatibility matrix. Add actual validated environment settings (see section 10.2), keeping safe defaults and configuration precedence.

Required gates in addition to G0-G7 (finish before release verification):

| Gate | Required deliverable | Required evidence |
|---|---|---|
| G6A | PineTS and Vela investigation | pinned upstream revisions, capability matrix, dependency/NOTICE review, license decision, and clean baseline preservation |
| G6B | Isolated indicator/strategy runtime | causal fixture parity, representative verified Pine subset, typed IPC, rejected unsupported and malicious samples, timeout/kill/recovery tests |
| G6C | AI builders and iterative backtests | versioned generated artifacts, actual mock-agent tool calls, bounded iteration lineage, negative results retained, isolated held-out data and reconciled virtual ledger |
| G6D | Chart workbench and independent validator | multi-chart E2E test, real plot/annotation provenance, closed-bar replay equivalence, repaint/leakage negative tests, cross-account denial and performance measurements |

Deliver one end-to-end offline proof: an agent proposes an original indicator, validates and plots it, proposes a related strategy, runs a historical virtual experiment, inspects genuine errors or metrics, records a revised artifact, executes a bounded next experiment and exports both results. Exercise supported PineTS in this workflow if licensed/available; otherwise run native/mock contract fixtures and report the exact missing gate. Do not fabricate performance, claim a strategy is profitable based on this proof, or treat a blocked PineTS integration as PASS. Include a reproducible screen capture or chart screenshot tied to the actual experiment ID, API/event traces, source and dataset hashes, test logs and resource/cost usage. Use actual mock or authorized inference and label which. Update the dashboard/CLI/SDK documentation and the existing compatibility research plan without duplicating or deleting original requirements.

Add or cross-reference these deliverables: `docs/PINE-COMPATIBILITY.md`, `docs/AI-QUANT-WORKBENCH.md`, `docs/STRATEGY-VALIDATION.md`, and the license/NOTICE assessment. Include per-feature/per-file compatibility results, validator fixtures, research lineage, tool schema reference, optional Compose deployment, operational limitations and exact reproduction commands. Record each G6A-G6D result with the existing PASS/FAIL/BLOCKED/NOT RUN rubric. The release verdict must disclose any incomplete extension.

### 15.8 Upstream source register (reviewed 2026-11-27)

- PineTS repository and license: https://github.com/LuxAlgo/PineTS ; https://github.com/LuxAlgo/PineTS/blob/main/LICENSE-COMMERCIAL.md
- PineTS documentation and coverage: https://github.com/LuxAlgo/PineTS/blob/main/docs/index.md ; https://github.com/LuxAlgo/PineTS/blob/main/docs/initialization-and-usage.md ; https://docs.luxalgo.com/developers/pinets/
- Vela core, addon and attribution requirements: https://github.com/LuxAlgo/Vela

These upstream descriptions establish candidates and advertised capabilities, not ATUM compatibility or a completed integration. Pin and verify them before implementation. The selected renderer, optional worker split, tool names, job state names and environment defaults are proposed engineering choices subject to validation. No upstream code was installed, executed or incorporated in this document revision.

---

## 16. High-agency research environment — capability amplification, agent autonomy and complete virtual dealing rooms (mandatory extension)

### 16.1 Owner intent and design hypothesis

The owner's central requirement is not a particular model, a larger parameter count, a clever system prompt, or an impressive chat answer. ATUM must be a complete, self-contained environment in which even an economical compact model can behave like an organized, resourceful, proactive quantitative research operator. The owner reports observing an approximately 27B-parameter model operating inside a sophisticated third-party demo trading environment. The model identity, parameter count, runtime, system prompt, methodology and reported performance have not been independently established. This is a motivating hypothesis, not a benchmark result or an assertion that 27B models are inherently weak.

Treat the environment as a **capability amplifier** for the model: supply the context, reliable tools, computational engines, memory, feedback, lifecycle, observability and explicit task boundaries necessary to turn reasoning into measurable work. The model should concentrate on interpretation, hypothesis formation, investigation and justified decisions. Deterministic software should carry out expensive or repetitive computations, maintain authoritative state and enforce all limits. The goal is high agency with bounded resources, not maximal token generation, constant trading or a guarantee of profit.

A capable agent must be able to operate independently after the operator authorizes a bounded paper experiment, whether the agent uses a small model, a low-cost cloud model, a local 27B-class model or an eligible native coding/research client. It must know what it can do, how to do it, what remains to investigate, what evidence is missing and when to stop or escalate. The environment must support creative investigation without giving a model authority to change its own risk, budget, permission or isolation boundaries. All execution remains local, fictional and virtual, as specified in sections 1, 8 and RD-001.

### 16.2 Deep research and engineering discovery mandate for Claude Code

Do not treat this specification as a closed feature checklist. It establishes the minimum requirements and non-negotiable boundaries, not the ceiling of the product. Before proposing final architecture changes, conduct a documented deep investigation of the current repository, upstream project documentation, open research, relevant quantitative trading frameworks, simulated brokerage platforms, event-driven research systems, agent harnesses, charting and indicator engines, local model runtimes, MCP ecosystems, accounting and reproducible experiment methodology. Include the existing Vela/PineTS research in section 15. Use primary sources and pin revisions where practical. Reconfirm current licensing, compatibility, interfaces and actual runtime behavior; do not assume a project's marketing claims are implementation evidence.

For each research domain, identify capabilities ATUM already possesses, capabilities present but disconnected or incomplete, missing primitives, integration opportunities, alternatives, dependencies, engineering cost, resource consumption, reliability, security implications, maintenance burden and measurable acceptance tests. Investigate at least the following domains, without treating them as an exhaustive list:

| Research domain | Questions and required outcomes |
|---|---|
| Agent harness engineering | How can compact models plan, use tools, maintain goals, recover from errors, work across sessions and make progress without repeatedly receiving instructions? |
| Quantitative research and virtual execution | What market observations, statistics, experiment controls, simulator semantics, accounting and evaluation methods are necessary for valid research? |
| Analysis and chart workbench | What makes an agent genuinely able to inspect, create, compare, validate and visualize research artifacts rather than merely describe them? |
| Multi-market data engineering | How can multiple symbol universes, providers, timeframes, timestamps and quality levels be normalized without fabricated or future data? |
| Tool ecosystems and interoperability | Which existing ATUM components, MCP tools, SDKs and APIs can be composed into useful workflows? What additional reviewed capabilities offer measurable value? |
| Model economics and small-model effectiveness | What state representations, tool schemas, context compression, caching and scheduling improve useful work per token and per dollar? |
| Security and operability | How can the research environment remain self-hostable, reproducible, isolated, observable, recoverable and safe to operate on modest infrastructure? |

Produce a capability inventory and an evidence-backed gap analysis, then select the best approach through reasoned engineering decisions. Consider unconventional and original architectures when justified. Absence of a pre-existing library or publication is not a reason to reject a promising, testable idea; formulate bounded hypotheses and compare prototypes against simple baselines. Preserve negative findings. Avoid needless rewrites, fashionable abstractions, duplicated dependencies and implementing a feature merely because another platform advertises it. Prefer a small correct primitive over a broad unreliable interface.

Claude Code is delegated authority to discover, propose and implement additional justified research capabilities not explicitly enumerated here, provided they preserve the architecture, existing verified behavior, licensing, security, fictional execution boundary and operator-defined resource limits. For substantial additions, record the rationale, alternatives, threat model, compatibility impact, expected benefit, scope, tests and rollback plan. If a dependency or entitlement is unavailable, deliver the fixture-backed portion and report the exact blocker instead of stopping unrelated work. Do not change research-only policy, deploy publicly, spend money, collect owner credentials or enable external financial execution under this delegation.

Deliver `docs/ATUM-DEEP-RESEARCH.md` containing sources, pinned versions, comparison matrices, original hypotheses, prioritized gaps, architecture decisions, rejected alternatives and a traceability map from discoveries to implemented and tested capabilities. The final report must distinguish research findings, proposals, completed implementations and actual validation. A literature review or an unimplemented backlog is not sufficient completion.

### 16.3 Complete agent workstation and closed-loop feedback

Provide a coherent, discoverable agent-facing workbench with a capability catalogue generated from the actual registry and permissions. The catalogue must accurately describe tool purpose, schemas, units, required data, freshness, cost class, availability, supported workloads, mutation permissions, failure modes and example calls. Present compact task-relevant subsets to the model, with a controlled way to discover additional authorized tools. Do not send every tool definition, all historical candles, the entire strategy corpus or the full conversation on every inference call. Do not represent unavailable capabilities as working tools.

The desired workstation includes market and symbol discovery, batched data access, analysis and statistical utilities, indicator and strategy authoring, versioned code artifacts, chart manipulation, experiment planning, backtesting, independent validation, virtual portfolio and order management, risk previews, research notes, memory retrieval, outcome review, and run control. Reuse sections 4–9 and 15 for their detailed contracts. Extend the catalogue based on the deep research findings; the model must have enough primitives to compose new research workflows without being hardcoded to a single strategy or chat script.

Implement a durable, bounded observe–investigate–test–decide–monitor–review loop. The operator assigns an experiment objective and resource envelope once. The runtime may generate appropriate follow-up research work from fresh observations, meaningful state changes, experiment results and scheduled review events without another user chat turn. Persist objectives, pending work, completed work, data/evidence references, hypotheses, invalidation conditions, current virtual state, task priority, next review time, failure history and remaining resources. Rebuild a compact working context from this state on restart or model switch. Separate observed decisions and tool events from private model reasoning; do not request hidden chain-of-thought.

Avoid two failure modes: a passive agent that completes one analysis and waits forever, and an overactive agent that generates unnecessary calls or orders to appear productive. Give the agent a clear objective, available resources, allowed actions, maximum work and completion criteria. A successful cycle produces useful verified progress, or a documented justified abstention. Surface why the agent is idle, what is being investigated, what triggered a review and whether work is blocked. Use deterministic monitoring for time-sensitive virtual account protections; a slow or unavailable LLM must not disable these safeguards. Escalate genuine blockers to the operator with a concise, actionable explanation rather than repeatedly spending tokens.

Measure initiative using completion of authorized tasks, tool-use validity, recovery from simulated failures, evidence-backed investigation, appropriate abstention, duplicate-work avoidance, responsiveness and resource efficiency. No reward solely for trade count, activity, predicted gain, leverage, risk taken or answer length. Evaluate fictional outcomes with the independent risk- and cost-aware methods in section 9. Preserve all failed hypotheses and avoid selecting favorable windows after seeing results.

### 16.4 Configurable research personas, strategy styles and explicit boundaries

Separate **research persona**, **strategy family**, **execution horizon** and **risk envelope** as independent configuration dimensions. A persona describes how an agent investigates and makes decisions; it is not a substitute for a hard risk policy. A strategy family describes a testable approach; it is not proof of an edge. A horizon describes the observation and review timescales; it does not guarantee an achievable execution latency.

Provide a configurable profile registry and UI/CLI/API selection. Start with these illustrative presets, validate the behavior and expand or improve them based on the deep research. Do not claim these are universally optimal or assign fixed risk percentages without documented simulation assumptions and operator approval.

| Profile | Intended research behavior within the virtual environment |
|---|---|
| Conservative | Emphasize uncertainty, selectivity, capital preservation, robust validation and fewer unsupported commitments. |
| Standard / balanced | Compare multiple eligible approaches and balance research activity, cost, uncertainty and virtual portfolio constraints. |
| Aggressive | Explore more opportunities and react to relevant changes more frequently within a separately approved finite research envelope; never interpret aggression as unlimited risk. |
| Exploratory / adventurous | Prioritize novel hypotheses and unusual market relationships in isolated sandbox experiments; speculative artifacts are not automatically promoted into active paper strategies. |
| Evidence-driven / optimality-seeking | Seek the best measured trade-offs between robustness, modeled costs, resource use and risk-adjusted virtual outcomes; not a promise of a perfect trader or an optimal market policy. |
| Custom | An operator-defined, versioned combination of research preferences and validated limits, subject to the same immutable safety and accounting rules. |

Support selectable simulated strategy families and horizons, including scalping, intraday, swing and longer-horizon research, bounded grid experiments, trend following, momentum, mean reversion, breakout, structural price action, multi-timeframe methods and other validated approaches discovered by Claude Code. An agent may investigate several strategy hypotheses concurrently and choose among authorized artifacts according to documented evidence and the experimental protocol. Do not force a particular family or number of trades. Unsupported methods remain explicitly unavailable; generated ideas remain drafts until validated.

Every profile and run must declare permitted instruments, authorized tools, maximum concurrent work, virtual account and allocation limits, risk/exposure constraints, maximum drawdown or loss stop conditions, data quality requirements, decision and research deadlines, model call/token/cost limits, allowed strategy artifacts, stopping conditions and review policy. The hard risk and permission layer owns these constraints; the model may propose a change for operator review but cannot approve or apply it itself. Profile transitions are versioned, audited and operator-authorized; changing a persona cannot silently increase financial or computational limits. No automatic escalation of leverage, unbounded grid, loss-recovery mandate or real-money execution.

Compare personas and models in identical fixtures, explicitly distinguishing changed research behavior from changed risk budgets or strategies. Verify that every profile honors its own limits, including contradictory tool requests, insufficient data, quota exhaustion, outages and unusual market conditions. Retain results even when a profile underperforms or abstains.

### 16.5 Multiple simultaneous MCP servers and tool composition

Extend section 5 from single-connection conformance into a genuine multi-server research fabric. The operator must be able to register at least five independent MCP servers simultaneously, mix approved stdio and Streamable HTTP transports, configure separate authentication/secret references, discover capabilities, enable or disable each server independently and inspect connection status. The model must be able to use permitted tools from several servers and ATUM's native tools in the same bounded research session. Do not assume the owner's five potential servers expose specific tools or protocols; inventory their actual schemas and permissions when authorized.

Use namespaced tool identities, stable registry metadata, per-server permission policies, connection and concurrency limits, deadlines, rate limits, health and cancellation. Route requests to the correct server, compose results with explicit source identity, timestamp, instrument/units and quality metadata, and make schema changes detectable. Allow safe parallel independent reads, sequential dependencies and deterministic aggregation when appropriate. External content remains untrusted and cannot expand the model's authority. Validate arguments and outputs, limit payloads, avoid duplicating data across prompts, and make missing or conflicting observations explicit. If one server disconnects, keep independent permitted work functioning where possible, rather than blindly substituting a different source or accepting stale data. No implicit credential sharing, unrestricted server discovery, direct broker/exchange order tools, or model-controlled network endpoints.

Provide a reproducible five-server fixture demonstration covering simultaneous discovery, name collisions, multi-server tool composition, concurrent requests, independent credentials, a failed server, malformed response, schema change, prompt injection, cancellation and denial of unauthorized actions. Demonstrate that the final research output cites the actual source observations and that no external financial execution request is emitted. Use real read-only integrations only if authorized; otherwise report which servers remain unverified.

### 16.6 ATUM-owned demo accounts and direct research API — no MetaTrader dependency

ATUM must act as its own authoritative virtual brokerage for research, not as a wrapper that requires MetaTrader, cTrader trading accounts or an external broker simulator. Provide locally created and persisted fictional demo accounts with configurable initial virtual capital/currency, independent account and agent identities, account-scoped memory and order/position/ledger histories, and explicit market simulation assumptions. The user must be able to create, inspect, compare, pause, archive and explicitly reset fictional accounts from the dashboard and authorized API. Preserve history and auditability on restart; never silently reset or transfer virtual state between accounts.

Provide first-class, documented, versioned REST/SDK and research MCP contracts. A model or independently authenticated research client may use ATUM-native tool calls, or an authorized scoped client may interact programmatically with its assigned **fictional** account through the same gateway. Support virtual account creation by authorized operators, account snapshots, order/position inspection, hypothetical intent submission, allowed simulated order lifecycle, run controls, event streams and portfolio/report export. All mutation paths must reach the identical authoritative risk, authorization, idempotency and accounting checks. Do not provide a separate permissive endpoint or a bypass for MCP/API callers. There must be no external execution credential, deposit, withdrawal, live-account routing or connection between virtual balances and actual funds.

Support multiple independent models or agents, including the initial ten-session target, each with its own virtual account, profile, permitted tools, provider/model configuration, memory, budgets, event history and comparison metrics. Support historical replay and forward paper experiments from read-only cTrader/crypto observations or approved MCP data. Clearly label ATUM's virtual accounts as ATUM-owned; they are distinct from cTrader demo accounts, model-provider accounts and real financial accounts. Import of an external anonymized HTML/CSV portfolio report, if implemented, is observational research only and must never alter the canonical virtual ledger.

Demonstrate an offline end-to-end workflow: create two or more accounts, authorize distinct simulated experiments, run agents independently against the same causal fixture data, submit virtual intents through both native and scoped API paths, reconcile balances/positions/events, restart the system, resume only authorized work, compare accounts on the dashboard and export reports. Attempt cross-account reads/mutations and unauthorized scope expansion; they must fail. Prove that this workflow runs on Linux with Docker Compose, no MT5 installation, no cTrader terminal, no external broker account and no paid inference requirement.

### 16.7 Token-efficient runtime and clear task contracts

The owner has experienced a powerful model exhausting substantial resources or failing a trading task when its objectives and boundaries were ambiguous. Do not treat this anecdote as a verified benchmark of any named model. The requirement is to make the harness efficient for both compact economical models and stronger models, including eligible Codex/native-client workflows. Verify actual model IDs, interfaces, capabilities and entitlements rather than assuming a model nickname implies a particular provider or capability. Preserve section 6's authorized integration rules.

Use a compact, versioned agent contract: objective, role, current fictional account, permitted tools, available context, current market/experiment time, next task, resource ceilings, expected typed output, success/failure criteria and stop conditions. Separate persistent goals from transient observations and deterministic calculations. Use bounded task queues, context summaries with evidence pointers, cache stable provider-supported prefixes, batch related reads, retain reusable computed features, use incremental deltas and retrieve relevant memory rather than replaying complete logs. Keep canonical raw observations available on demand. Summarization must not erase critical risk state, data freshness, provenance or known failures.

Use deterministic scanner, statistics, indicator, strategy evaluation, accounting and monitoring engines before spending inference tokens on tasks that do not require a language model. Give compact models typed schemas, concise tool descriptions, validated outputs and clear error feedback. Allow configurable reasoning depth and bounded escalation to a stronger authorized model only when justified and within a declared budget; no implicit paid fallback. Profile-specific limits must remain authoritative across model changes. Keep work resumable so context limits, process restarts or exhausted quotas do not destroy completed research. Do not interpret self-reported confidence as proof of accuracy.

Benchmark small/low-cost and stronger models with identical tools and datasets, and compare harness variants under declared budgets. Record total model calls, tool calls, input/output/cached tokens, completed tasks, invalid decisions, justified abstentions, latency distributions, errors, cost per valid completed research task, and cost-inclusive fictional experiment outcomes. Evaluate the contribution of the environment using controlled ablations (for example, with and without compact context, typed tooling or persistent state) while keeping other variables comparable. No presumption that a specific 27B model, Codex model, Luna, Astra or other nickname will outperform another; select configurations based on measured results and verified provider support. Treat private model information and credentials as secrets. Retain unsuccessful runs and disclose unknown billing or provider-side nondeterminism.

### 16.8 Security sweep, operational hardening and release extension

Security is a prerequisite, not a task postponed until the end. Continue to enforce the P0 accounting and isolation gates throughout implementation. After integrating the full workbench, run a final focused security and regression review of every new attack surface and its interactions with the existing system. The owner's request for a quick final check means a concise actionable release assessment backed by actual tests, not a superficial assertion that the project cannot be hacked.

At minimum review authentication and authorization on REST, WebSocket, MCP, SDK and dashboard paths; tenant/agent/account isolation; secret handling and redaction; remote endpoint SSRF, TLS and redirects; tool argument and result validation; malicious or injected external content; dependency and supply-chain vulnerabilities; untrusted strategy/indicator execution; sandbox escape and resource exhaustion; Docker privileges and network policy; CORS and WebSocket origins; unsafe file paths or uploads; concurrency, idempotency and late callbacks; backup/restore; and model/provider spend exhaustion. Verify that real-money execution is unreachable in the research deployment even if a malicious model or MCP server attempts to invoke it. Re-run regressions from sections 2, 5, 8, 10, 12 and 15. Prioritize reproducible P0/P1 findings, patch and retest, disclose remaining findings and avoid claims of absolute security. Do not expose the system publicly or use real secrets in CI to demonstrate security.

Extend the Compose/environment contract with a structured research-profile configuration, per-agent account and provider bindings, tool registry/server configuration, and validated resource controls. Suggested additional settings (names proposed, not existing): `ATUM_AGENT_PROFILE=standard`, `ATUM_AGENT_PROFILES_FILE=/etc/atum/profiles.yaml`, `ATUM_AGENT_MAX_PENDING_TASKS=32`, `ATUM_MCP_MAX_SERVERS=5`, `ATUM_MCP_MAX_CONCURRENT_CALLS=4`, `ATUM_AGENT_CONTEXT_BUDGET_TOKENS=8192`, `ATUM_AGENT_HEARTBEAT_SECONDS=30`. These are illustrative engineering starting values, not validated performance requirements or financial thresholds. Support more than five approved servers when resource and policy tests permit. The actual configuration must have explicit defaults, validation, redacted diagnostics and documented precedence. No production credentials or automatic paid inference in the default `.env`.

Add the following mandatory gates before G7 and record each separately using PASS/FAIL/BLOCKED/NOT RUN:

| Gate | Deliverable | Required evidence |
|---|---|---|
| G5A | Deep research and capability-amplification design | source register, capability/gap inventory, architecture decisions, new justified features, test traceability and limitations |
| G5B | High-agency runtime and profile registry | persistent bounded task loop, independent profiles, context recovery, observable progress or abstention, enforced stop and budget limits, comparative fixtures |
| G5C | Five-server MCP composition | five simultaneous fixture servers, namespaced tools, independent auth, multi-server successful workflow and adversarial/failure tests |
| G5D | ATUM-owned virtual accounts and scoped research API | independent local accounts, real virtual state via native and API tools, cross-account denial, reconciliation, restart, export and no external execution |
| G6E | Harness effectiveness and token economics | reproducible harness ablations, compact-model fixture tests, authorized model comparison where available, usage/cost/latency reports and retained failures |
| G7A | Final security sweep | findings with severity and evidence, fixes and rerun logs, dependency/secret/container checks, no unresolved critical boundary violations, known residual risks |

Add `docs/ATUM-AGENT-WORKBENCH.md`, `docs/AGENT-PROFILES.md`, `docs/MCP-MULTI-SERVER.md`, `docs/VIRTUAL-ACCOUNT-API.md`, `docs/MODEL-EFFICIENCY-REPORT.md` and the final security assessment to the existing deliverables, or merge their content into existing documents with clear cross-references. Provide a concise operator quickstart showing creation of a fictional account, selection of a profile and model, registration of multiple MCP servers, experiment start, live observation of research work, budget enforcement, stop and report export. Report the actual supported configuration and tested limits. The absence of paid-model credentials or the owner's specific MCP endpoints must not prevent a complete offline demonstration.

The final release should make ATUM feel like a comprehensive research workstation for an AI agent: every useful authorized capability discoverable, every objective bounded, every tool backed by real implementation, every important result traceable, and every fictional account protected by independent policy. The measure of success is not how much the agent talks, how many trades it opens, how much leverage it uses, or whether it repeats an extraordinary reported demo return. It is how effectively, independently, economically and reproducibly the agent investigates hypotheses and performs authorized virtual experiments with the supplied environment.

**ATUM — Virtual Markets. Artificial Agents. Measurable Intelligence.**
