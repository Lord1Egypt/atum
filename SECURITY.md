# Security policy and threat model

ATUM is a research workstation for simulated trading experiments. This policy describes the required security posture, review scope and vulnerability disclosure process. It is not a declaration that the current implementation has passed a security audit.

## Reporting a vulnerability

Please do not open a public issue or post sensitive proof-of-concept details, credentials, private logs, account data or exploit instructions in a public pull request.

Use [GitHub private vulnerability reporting](https://github.com/Lord1Egypt/atum/security/advisories/new) if the repository has enabled it. If private reporting is unavailable, contact the maintainer through an established private channel and request a secure way to provide the report. A public issue may request a private reporting channel without describing the vulnerability.

Provide the affected revision/version, component, impact, prerequisites, sanitized reproduction, relevant evidence and suggested mitigation. Use only authorized local fixtures and fictional accounts. Do not test against someone else's deployment, access private systems or data, disrupt services, or execute real financial operations. Coordinate disclosure with the maintainer; no response-time, bounty, support or remediation guarantee is implied.

The repository is under development. Report issues against the affected commit or release and, if safe, verify whether the current main branch is affected. No supported-release list or completed security certification has been established.

## Non-negotiable security boundaries

The authoritative implementation specification is [ATUM-RD-002 v1.5](docs/ATUM_IMPLEMENTATION_REQUIREMENTS_v1.5.md), particularly sections 1, 5, 6, 8, 10, 15–18 and 20.8.

- All orders, positions, balances, margin, settlements and execution are fictional. External market-data connections are read-only. Never enable real-money execution, external broker/exchange orders, transfers, funding or withdrawals in this scope.
- Risk limits, permissions, account ownership, data requirements, resource budgets and stopping conditions are enforced independently of model output. Missing required enforcement or ambiguous state must fail closed.
- Trading/research agents can request tools and use approved artifacts; they cannot write executable scripts, access a general shell, install packages, edit repository code, change policies or deploy. Separate engineering identities implement code, with independent verification.
- Claude Code develops on scoped branches; Codex reviews changes without editing, merging or deploying. Only the maintainer authorizes merge and promotion. GitHub comments and AI recommendations are never deployment authorization.
- Default to local/offline fixtures and least privilege. Explicitly authorize external endpoints, paid inference and publishing. Never silently fall back to another billed provider or bypass subscription or service restrictions. Do not assume all requested capabilities already exist.

## Threat model

### Assets and trust boundaries

| Asset | Required protection |
|---|---|
| Fictional account ledger, positions, reservations and risk state | Integrity, isolation, transactionality, reconciliation, durable auditability. |
| Credentials and configuration | Confidentiality, rotation/revocation, scoped service identities and validated configuration. |
| Market observations, strategy artifacts, research memory and test evidence | Provenance, causal availability, versioning, access isolation and retention. |
| Provider quotas, tokens, storage and compute | Hard budgets, bounded concurrency, resource governance and graceful failure. |
| Source code, workflows, image digests and release approvals | Authenticity, least privilege, independent review, reproducibility and controlled promotion. |
| Operator UI, APIs, MCP and private operational evidence | Authentication, authorization, confidentiality and abuse resistance. |

Treat model output, external MCP responses, market/news content, imported scripts, uploaded files, repository/issue/PR text, third-party dependencies and webhooks as untrusted. Validate at every transition: external source -> data adapter; model -> typed tool dispatcher; tool -> policy and virtual kernel; research request -> sanitized development queue; developer -> isolated PR/CI; approved artifact -> trusted deployment controller. UI or prompt-level restrictions are not sufficient authorization controls.

### Security review checklist

| Area | Review requirements |
|---|---|
| Identity and authorization | Authenticate protected endpoints and MCP sessions; verify account/run/tool scopes, actor identity and operator authorization at the server. Deny cross-account reads/writes, forged roles, replayed approvals and privilege escalation. |
| Execution and accounting | Independently enforce demo-only routing and risk checks. Reject invalid values, stale/incomplete data and missing policy; ensure atomic reservations/fills, idempotency, single authoritative writer, restart reconciliation and tested migrations. |
| Credentials | Store secrets outside Git, prompts, telemetry, images, fixtures and PR artifacts. Use scoped, revocable credentials and secret references. Redact authorization headers, URLs/query parameters, diagnostics and provider output. Never print or copy raw OAuth tokens, API keys or session files into GitHub. |
| Endpoint and transport security | Enforce authorized connector destinations and tool allowlists, TLS validation, redirect restrictions, SSRF protections including DNS/IP changes and internal/metadata destinations, response limits, deadlines and bounded retries. Only explicitly approved local integrations may access scoped internal endpoints. |
| External inputs and injection | Validate schemas, types, sizes, paths and provenance. Treat prompt injection, tool descriptions, market/news text, PR comments and imported code as data. Do not interpolate untrusted event text into shell commands or trusted workflow configuration. |
| Strategy and script sandbox | Only approved, versioned engineering-authored artifacts execute. Use isolated non-root workers with explicit resource limits, denied arbitrary filesystem/network/shell/secret access, independent cancellation and hostile-input tests. Verify PineTS coverage and licensing before shipping. |
| API/UI and persistence | Review access checks, cross-account isolation, WebSocket origins, CORS/CSRF where applicable, injection, path traversal, safe rendering, concurrency, migrations, permissions, backup encryption and restoration. Bind internal services privately by default. |
| Provider costs and availability | Reserve and enforce budgets, reconcile actual/unknown usage, cap queues/retries, prevent cancellation bypass or late mutations, preserve deterministic safety when an LLM is offline, and prevent implicit paid fallback. |
| Data and scientific integrity | Require timestamp/provenance checks, no future leakage/repainting, honest fill/cost semantics, validated strategy versions, negative controls and independent evaluation. Do not fabricate successful tool results or evidence. |
| Dependencies and build | Review dependency provenance, known vulnerabilities, licenses, lockfiles and pinned external actions; avoid arbitrary install scripts/downloads. Verify artifact digests, build provenance and applicable SBOM/scans. |
| GitHub and CI/CD | Authorize trigger actors and task scope. Separate developer, reviewer, CI, publisher and promotion identities. Protect sensitive workflow/policy changes. Do not run untrusted PR code with privileged credentials, expose full inference logs, or allow bot-to-bot trigger loops. Use minimum token permissions and ephemeral isolated runners. |
| Docker and deployment | Never give trading agents, reviewer, web app or coding agents the production Docker socket, SSH credentials, deployment token or unrestricted host mounts. Verify immutable approved image digests, staging isolation, signed/authorized promotion, fencing, checkpoint, semantic validation, compatible rollback and explicit recovery states. |
| Abuse and denial of service | Enforce upload/body limits, request quotas, queue/concurrency caps, backpressure, tool deadlines, disk/retention bounds and cancellation. Isolate failed dependencies and prevent indefinite polling or runaway inference. |
| Public/private evidence boundary | Keep raw logs, model transcripts, operational account data, credentials and proprietary research data private. External reports must be minimized, sanitized and authorized. Do not publish raw debug output or execution artifacts merely to diagnose an error. |

### Required evidence and release decisions

For security-sensitive changes, identify the affected boundary and plausible failure mode; include a regression or negative test demonstrating that the prohibited action is denied independently of model compliance. Test concurrent/replayed requests, malformed and adversarial tool responses, stale data, invalid/expired credentials, cross-account access, sandbox limits, workflow/approval forgery, outage and recovery when applicable. Use mock or synthetic inputs and isolated state; never use actual financial execution or private production credentials as a test fixture.

Prioritize demonstrated impact. Treat external financial execution reachability, credential disclosure, arbitrary privileged code execution, authorization bypass and serious ledger integrity violations as potential release blockers. Do not hide a failing gate, weaken security controls, or mark a check passed without evidence. Report the exact revision, commands/results, severity, scope, fixes, retests and residual risks; label PASS, FAIL, BLOCKED or NOT RUN.

Codex should review the changed code and its relevant call paths. Claude Code implements fixes in the designated development branch, with independent review of each changed revision. Only the maintainer may accept residual risk, authorize a release or promote an immutable approved artifact. No review comment is itself a merge or deployment approval.

## Handling suspected credential exposure or incidents

Stop affected automated tasks and external publication when safe, isolate the affected integration, notify the maintainer privately, and revoke/rotate exposed credentials through their issuing service. Do not print the credential to prove exposure. Preserve minimal access-controlled evidence and audit lineage; remove public exposure through an authorized remediation process. Validate the fix and restore only verified compatible state. Resume experiments or development tasks only after the required checks and authorization. Do not claim a successful recovery without reconciliation and evidence.

## Current implementation status

This document is the baseline for threat modeling and security reviews. Reviewers must verify the actual code, configuration, repository permissions, private-reporting availability, test coverage and deployed controls. A written policy, enabled review toggle, or green CI job alone does not establish security.
