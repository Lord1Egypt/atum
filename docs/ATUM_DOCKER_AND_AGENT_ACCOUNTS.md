# ATUM — Docker deployment and account-based research agents

**Development addendum 01 | 2026-11-24 | Proposed, not implemented**

Companion to [ATUM Engineering Blueprint](ATUM_Engineering_Blueprint.txt). All execution and balances remain simulated. Preserve Go, SQLite and React/TypeScript unless a measured requirement warrants a change.

## 1. Objective

Deliver a reproducible, self-hosted Docker Compose research appliance. A researcher without separate model API keys should be able to use eligible official account-based integrations, or connect an independently authenticated native research client. An ATUM virtual market account and a model-provider account are distinct identities. No real-money routing, deposits, withdrawals, or broker credentials are permitted.

## 2. Docker deployment contract

- Provide a multi-stage Dockerfile (pinned Go and frontend toolchain, lockfiles, minimal non-root runtime), compose.yaml, .dockerignore, sample configuration, health/readiness endpoints, documented upgrade/backup/restore workflow.
- Build Linux amd64 and arm64 images in CI; pin release dependencies and publish image digests, SBOM and test evidence.
- Required core service: ATUM HTTP/WS API, static dashboard, simulator, ledger and experiment coordinator. Keep SQLite WAL on a local persistent volume owned by one writer; use transactional migrations and consistent backups. Store immutable research datasets and artifacts on separate volumes.
- Optional Compose profiles: local inference (Ollama or other supported local runtime), read-only market-data ingestion, and approved external research-client integration. Core must boot and run fixture experiments without internet, API keys or subscription credentials.
- Bind the dashboard to 127.0.0.1:9090 by default; internal services have no published ports. Expose only authenticated, scoped research interfaces. Use non-root UID, dropped capabilities, no privileged containers, no Docker socket, no broad host mounts, no secrets in images or environment examples. Separate writable state from read-only configuration and constrain CPU, memory, process counts and job concurrency.
- Network design: simulator has no route to external financial execution services. Optional inference or data connectors have narrow approved egress; never treat a model response as authorization to expand network access.
- Lifecycle: readiness verifies database and demo policy; graceful shutdown checkpoints experiments; restart resumes only explicitly resumable runs. Preserve volumes across upgrades. Provide an explicit, confirmed reset operation for fictional test data.

## 3. Provider / research-client architecture

Define a provider-neutral capability contract for research sessions: discover availability, open a session, submit a bounded research task, stream typed events, cancel, report limits, close. A provider can declare unsupported capabilities. A simulated account is allocated and scoped by ATUM, never by the inference provider. Store provider type, model ID, client version, experiment ID, timestamp, observed quota/cost if available, status, and artifacts. Do not store hidden model reasoning; capture observable decisions, evidence and tool calls.

Separate these modes:
- Local model: no cloud API key; report actual model and local resource limits.
- Official API provider: optional future integration using an explicitly supplied authorized key, never required for the baseline.
- Account-based provider: available only through documented, authorized mechanisms for eligible users and workloads.
- Native external client: a separately authenticated tool connects to scoped ATUM research interfaces; ATUM does not impersonate its user or handle the client's provider credentials.
- Scripted mock: deterministic offline fixtures for all CI runs.

No general-purpose subscription-to-API proxy, session-cookie scraping, extraction of private tokens, reverse-engineered endpoints, shared-account pool, rate-limit avoidance or silent conversion to paid API billing.

## 4. OpenAI / Codex — official ChatGPT plan path

Investigate the documented Sign in with ChatGPT (SIWC) plan-usage capability for eligible open-source and locally hosted applications. It is a preview, not a universal entitlement. Review current eligibility, allowed use, registration requirements and preview restrictions before implementation. Use the official registration, consent, account/session, model selection and refresh flows, with secure per-installation storage and revocation. Never reuse a copied CLI credential or browser cookie.

The official Codex app-server integration documents a plan-authorized inference path. Treat it as an optional provider-specific proof of concept for bounded research and analysis tasks, not a general execution service. Keep its subprocess and credentials isolated from simulation state, logs and other agents. Verify actual successful inference under the user's selected plan; a listed model is not proof of entitlement. Handle declined consent, missing access, expiration, revocation and quota exhaustion by reporting an explicit unavailable/paused state. No automatic paid fallback.

Alternative: let the researcher run the official Codex client independently and connect it to ATUM's scoped, read-only research MCP tools or submit a fictional experiment proposal for review. Do not assume autonomous or financial workflows are allowed merely because authentication succeeds.

## 5. Anthropic / Claude Code — native client path

Anthropic's published Claude Code terms distinguish first-party subscription sign-in from developer API authentication. Do not implement a third-party Claude.ai login, capture OAuth tokens, or route app inference through consumer-plan credentials. For the no-API-key workflow, support a researcher using the official, unmodified Claude Code client, independently signed in through Anthropic's own flow, with ATUM exposed as an optional scoped research MCP server. The researcher initiates the research session in the official client. If preinstallation or hosting is considered, first verify the applicable commercial terms and conditions; preserve native authentication and never intermediate billing.

Native client compatibility is a research integration, not a promise of unattended inference, headless service eligibility, unlimited usage or provider-account reuse. If an approved native flow is unavailable, use local models, offline fixtures, or an explicitly authorized API integration. Mark unavailable capabilities honestly.

## 6. ATUM research MCP / SDK boundary

Offer a narrow research-only endpoint with scoped per-experiment identity and expiration. Initial tools: inspect dataset provenance, get historical observations, compute descriptive indicators, inspect fictional experiment state, retrieve reports, write research notes, and submit bounded experiment proposals for human review. Existing simulation tools must remain demo-only and independently enforce identity, validation and accounting invariants. Do not expose shell execution, host files, provider credentials, Docker control, real brokerage routes or administrative tools through model-facing interfaces. Treat external data as untrusted and retain human review for changes to experiment policy.

## 7. Work plan and acceptance gates

| Phase | Deliverable | Required evidence |
|---|---|---|
| D0 | Inspect existing Docker/build assets, provider interfaces, MCP direction and blueprint gaps | pinned revision, inventory and risk register |
| D1 | Core Compose appliance | clean build, health check, offline fixture smoke, restart/persistence and backup/restore tests |
| D2 | Research provider abstraction and mock | contract tests, typed errors, cancellation, scoped accounts and deterministic offline tests |
| D3 | Native external research-client compatibility | documented client-initiated session, scoped access and denied cross-account/privileged requests |
| D4 | Optional official SIWC/Codex proof of concept | eligibility review, explicit user consent, redacted successful test, revocation and quota/error handling; otherwise BLOCKED |
| D5 | Claude Code compatibility | official native client test and policy review; no third-party credential collection; otherwise BLOCKED |
| D6 | Release validation | amd64/arm64 build results, security checks, docs, immutable artifacts and known limitations |

Do not commit credentials or require real subscriptions in automated CI. Use mocks for provider tests; record only sanitized evidence from manually authorized integration checks. Verify the simulator cannot access live execution endpoints even when a provider is connected. Do not expand trading capabilities until the primary blueprint's accounting, isolation and replay gates pass.

## 8. Source register (official documentation reviewed 2026-11-24)

- OpenAI, [ChatGPT plan usage overview](https://developers.openai.com/siwc/token-sharing-open-source).
- OpenAI, [Codex app-server integration](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server).
- OpenAI, [Preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).
- Anthropic, [Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance).

These references establish available documented integration paths and restrictions; they do not establish the repository's implementation status or the user's entitlement. Recheck before release.
