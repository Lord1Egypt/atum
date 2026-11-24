# ATUM Strategy Compatibility Engine
## Research and engineering proposal — development addendum 02

**Date:** 2026-11-24  
**Status:** Proposed; no runtime implementation or compatibility claim.  
**Scope:** Offline and fictional-market experiments only. Companion to [Engineering Blueprint](ATUM_Engineering_Blueprint.txt) and [Docker and Agent Accounts](ATUM_DOCKER_AND_AGENT_ACCOUNTS.md).

## Abstract

ATUM possesses a substantial research corpus but cannot currently execute its source languages as native strategies. This proposal investigates a language-neutral research representation, static analysis, isolated compatibility workers, and semantic conformance testing. Preserve the Go simulation kernel, SQLite persistence and existing React/TypeScript interface. Treat the original files as untrusted research specimens. All generated events and balances are fictional, and no compatibility component may route orders to an external broker, exchange or financial service.

## 1. Repository evidence and baseline

Inspected tree: `8e86e47863e80354bb6183bc7f2eba143ad505c0`.

| Corpus label | Files | Required investigation |
|---|---:|---|
| Pine indicators | 647 | Time-series and indicator semantics |
| Pine strategies | 95 | Historical evaluation semantics |
| MQL5 expert advisors | 183 | MT5 language and event compatibility |
| MQL4 expert advisors | 81 | Separate MT4 semantics |
| Freqtrade | 50 | Python framework interfaces |
| Backtrader | 135 | Python framework interfaces |
| Total source files | 1191 | Not a count of runnable strategies |

The corpus represents 131 repositories. The [library README](../strategy-library/README.md) explicitly states that files cannot be executed directly by ATUM. Its existing native backtest interfaces are in [internal/backtest/strategy.go](../internal/backtest/strategy.go), including StrategyRunner, CodeStrategy and ConfigStrategy. Indicator calculations, strategy arena and plugin IPC also exist, but the existence of these interfaces does not demonstrate support for external runtimes.

The earlier manifest audit found all 1191 referenced paths present, no byte-identical Git blobs among the 1194 library files, and 800 recorded-size mismatches against the Git tree. CRLF normalization is a hypothesis, not a verified explanation. Original upstream commit identifiers are not present in the manifest schema. Some classifier results are utilities or tests rather than strategies. Resolve provenance and classification before treating this corpus as a benchmark.

## 2. Research questions and hypotheses

- H1: A versioned neutral representation can reproduce a useful, explicitly bounded subset of source-language time-series computations against immutable fixtures.
- H2: A common simulation clock and data contract reduce semantic divergence between compatibility paths.
- H3: A semantic conformance corpus detects differences which source parsing and successful compilation alone cannot detect.
- H4: An isolated worker architecture can preserve the existing Go core while preventing imported code from accessing host resources or external services.
- H5: Actual compatibility varies with language version, dependency availability and source features; report it per file and construct rather than claiming blanket support.

Reject or narrow a hypothesis when evidence fails. Preserve negative results.

## 3. Proposed architecture

```text
Untrusted corpus (read-only)
        |
Provenance + classification + license gate
        |
Static analysis / capability inventory
        |
Versioned research IR or reviewed isolated compatibility worker
        |
Immutable fixture dataset + virtual clock
        |
Existing ATUM simulation and fictional ledger
        |
Independent conformance evaluator + reproducible evidence
```

The IR and workers are experimental, not current features. Keep the original source immutable. Maintain mapping from every translated element to its source location, original hash, upstream revision and supported semantic version. Unsupported syntax, unavailable dependencies and ambiguous behavior must return typed errors; do not substitute invented results.

The host owns all time, data, accounting and experiment state. A compatibility component can only consume authorized fixture observations and emit bounded research events into the fictional experiment. It cannot access real financial accounts, provider credentials, network trading routes or modify the simulator's accounting rules.

## 4. Language research tracks

### Pine Script

TradingView documents a specialized sequential, event-driven execution model and cloud-based runtime. Pine is not a general-purpose local runtime that can be assumed to be installable in a container. Study documented language versions and the semantics of historical bars, time-series history, persistent state, missing values, warm-up, multi-timeframe alignment and recalculation. Start with reviewed pure indicator examples and compare their outputs against known reference fixtures. Investigate a clean-room parser/interpreter for a documented subset only if licensing and semantics permit. Do not imply official TradingView compatibility, bypass access controls, scrape protected scripts or treat chart output as an independently verified reference. Keep external imports unsupported until reviewed.

### MQL4 and MQL5

Treat MT4 and MT5 as separate dialects with different APIs and behavioral contracts. MetaQuotes documents its own tester runtime; ATUM's existing bridge is not evidence that a standalone MQL implementation exists. Begin with static classification, dependency inventory, pure mathematical functions and deterministic historical fixtures. Investigate a restricted educational compatibility subset or approved reference-output comparison. Do not redistribute proprietary platform runtimes, DLLs or binaries without permission. Exclude live terminal integrations, external communications, trading credentials and real order execution from this work. Native vendor runtime experiments, if ever authorized, belong in a separate offline research environment, not the default deployment.

### Python / Freqtrade / Backtrader

Distinguish framework-specific behavior from ordinary Python. Inventory imports, package versions, callback contracts, data schema and fixture dependencies. First validate reviewed pure transformations using pinned dependencies and isolated, network-disabled workers. No arbitrary corpus execution, auto-installation of dependencies, dynamic shell invocation or import-time side effects in the host process. Third-party package and license obligations must be reviewed separately from the source file's license. The presence of a framework class name in a file is not proof of functional compatibility. Framework-specific research evaluation remains disconnected from any live brokerage or exchange service.

### ATUM native

Use the existing native interfaces as the reference boundary. Extend them only after writing an explicit compatibility contract and preserving existing verified behavior. Do not allow generated source or configuration to bypass policy checks. A translation must identify unsupported behavior and pass equivalence tests before becoming a verified research artifact.

## 5. Corpus catalogue and reproducibility

Maintain separate immutable original-source and derived-artifact records. Required metadata: upstream repository and exact commit, original path, original and stored SHA-256, byte count, encoding and normalization policy, license and notice references, language/dialect/version, actual content class, dependencies, unsupported features, research status, evaluator version, fixture ID and evidence location.

Correct the 800 size inconsistencies with an independently reproducible audit. Never rewrite original checksums to conceal a transformation; distinguish original and normalized content. Detect exact duplicates and cluster near-duplicates without discarding provenance. Preserve full applicable license texts, notices and file-level exceptions. MPL-2.0 is file-level copyleft, not a purely permissive license. Repository-level labels alone do not establish redistribution rights. Quarantine uncertain material until reviewed.

Suggested states: INVENTORIED, LICENSE_REVIEW, CLASSIFIED, PARSED, SUBSET_SUPPORTED, FIXTURE_VERIFIED, UNSUPPORTED, QUARANTINED. A file can be useful as reference material without being executable. Expose these statuses in a searchable catalogue to research agents; never represent an unsupported file as a usable runtime strategy.

## 6. Worker isolation and safety boundary

Default deployment is offline fixture research. Run approved workloads as non-root, resource-bounded workers with read-only inputs and a disposable working directory. No Docker socket, host mounts, arbitrary outbound network, external trading credentials, privilege escalation or access to other experiments. Use a hardened runtime and stronger isolation where untrusted code cannot be safely contained by a shared kernel. Deny unsupported imports and capabilities by default. Review code and dependencies before execution; a container by itself is not a sufficient trust boundary.

Use a bounded, typed IPC interface with explicit schema versions, deadlines, cancellation and deterministic error reporting. Validate every emitted event at the Go kernel boundary. Preserve immutable logs and fixture manifests without capturing secrets. Agent-facing tools may inspect the catalogue, request static analysis, inspect evidence and propose reviewed fictional research experiments. Imported source and documentation are untrusted data, never instructions that override policy.

## 7. Evaluation design

Build a conformance suite with hand-computed fixtures, flat and missing data, time gaps, duplicate timestamps, different warm-up lengths, rounding boundaries and causal multi-timeframe alignment. Use independent expected outputs, not another copy of the implementation being tested. Measure numerical error under declared tolerance, event ordering, replay hashes, source mapping correctness and unsupported-feature detection. Label all datasets and results synthetic or historical research as appropriate.

For full-language claims, compare against legally obtained reference outputs for the exact version and fixture. Distinguish parser coverage, semantic coverage and verified-file coverage. Compilation success is not a semantic pass. Include negative cases, fuzz tests, resource exhaustion tests, restart/replay tests, and cross-experiment isolation tests. No profitability claims or promotion to real-money usage.

## 8. Milestones and release gates

| Phase | Deliverable | Evidence required |
|---|---|---|
| C0 | Catalogue/provenance repair and taxonomy | Reconciled paths and hashes, upstream revision records, license report |
| C1 | Compatibility contract and fixture harness | Versioned schema, deterministic replay, golden fixtures |
| C2 | Reviewed pure indicator subset | Reference comparisons, explicit unsupported constructs |
| C3 | Isolated Python research-worker proof of concept | Offline execution and negative security tests; pinned dependencies |
| C4 | Pine semantic feasibility | Documented subset and fixture comparison; no unsupported compatibility claims |
| C5 | Separate MQL4/MQL5 feasibility | Dialect-specific support matrix and independent reference evidence |
| C6 | Catalogue/UI and research-agent integration | Search, provenance, result artifacts, scoped access, failure reporting |
| C7 | Docker packaging and performance | Reproducible builds, measured RAM/CPU, multi-architecture status, resource limits |

All stages depend on the primary blueprint's ledger, isolation and causal-replay gates. Stop if a worker cannot be safely isolated or if lawful reference material is unavailable. Record BLOCKED rather than fabricate support. Require CI results, exact revision, fixture digests, known limitations and a pass/fail verdict per milestone.

## 9. Deployment feasibility — GoDaddy

The existing architecture is Go + React/TypeScript + SQLite, with proposed Python and other research workers. The core is not a Node.js-only web application.

| Hosting type | Assessment |
|---|---|
| GoDaddy Node.js Hosting | Suitable for a separately deployed compatible web frontend; full multi-runtime Docker Compose hosting is not established by the documented Node app service. |
| GoDaddy shared Web Hosting / Hosting Plus | May host compatible frontend content; not the recommended environment for an independent multi-container compute laboratory. |
| GoDaddy Linux VPS with root access | Candidate for the Docker research appliance. Validate CPU architecture, storage, OS support, Docker availability, network policy and actual resource limits before purchase/deployment. |
| Local Linux host / existing lab server | Suitable for initial offline fixture validation and benchmarking, before committing to paid hosting. |

GoDaddy describes Node.js Hosting as an application-oriented service with managed deployment and recommends VPS for root-level control. Its VPS product advertises root access and Linux distributions. This does not prove a particular subscription includes the resources needed for ATUM.

Start with local/offline tests; record CPU, resident memory, disk IO, startup time and concurrent worker footprint. As a planning estimate only, 2–4 vCPU and 4–8 GB RAM may be a reasonable initial small research-appliance test budget without local LLM inference. Larger parallel experiments or local models require separate measured sizing; do not promise performance from specifications alone. Use persistent storage, backups and authenticated access. Never expose provider credentials or research workers to the public internet. No paid purchase or hosting modification has been made.

## 10. Primary references

Repository sources above are evidence of the current project baseline. The following official sources inform the proposed research directions and hosting assessment (reviewed 2026-11-24):

- TradingView: [Pine execution model](https://www.tradingview.com/pine-script-docs/language/execution-model/), [cloud-runtime limitations](https://www.tradingview.com/pine-script-docs/writing/limitations/).
- MetaQuotes: [Testing MQL5 programs](https://www.mql5.com/en/docs/runtime/testing).
- Freqtrade: [strategy interface and historical-data caveats](https://www.freqtrade.io/en/stable/strategy-customization/).
- Backtrader: [strategy interface](https://www.backtrader.com/docu/strategy/).
- GoDaddy: [Node.js hosting FAQ](https://www.godaddy.com/it/help/nodejs-hosting-faq-42915?lc=en-US), [VPS hosting](https://www.godaddy.com/hosting/vps-hosting), [root access](https://www.godaddy.com/en/help/enable-root-or-admin-access-to-my-vps-hosting-24737?inapp=true).

## 11. Engineering handoff

Begin with C0, not a universal interpreter. Keep the existing Go architecture and demo-only boundary intact. Make reviewed, small changes; deliver auditable fixture-based proof before extending the supported subset. The document is a research proposal, not an implementation report. No runtimes, cloud services or source programs were executed during its preparation.
