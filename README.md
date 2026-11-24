# 𓀭 A T U M
### AI Market Simulation Framework
**Virtual Markets. Artificial Agents. Measurable Intelligence.**

Atum is a self-hosted framework for running populations of AI agents against simulated and live markets — then measuring what they actually do. You define the venues, the agents, and the risk envelope. Atum provides the execution layer, the memory, and the instrumentation.

Every agent decision is a recorded event. Every result is reproducible. Nothing is hidden behind a prompt.

---

## Why Atum

Most "AI trading" tools are a chat box pointed at a brokerage API. You get an opinion and no way to verify it. Atum is built the other way around: the simulation is the product, and the agent is a subject inside it.

| Principle | What it means in practice |
|---|---|
| **Virtual markets first** | Simulated venue runs by default. Live venues are opt-in, per-account. |
| **Agents are instrumented** | Tool calls, reasoning steps, and outcomes are captured as events, not chat logs. |
| **Intelligence is measured** | Backtests, walk-forward runs, and cross-agent arenas produce comparable metrics. |
| **Your keys, your machine** | Credentials live in an encrypted local vault. No telemetry, no hosted control plane. |
| **Bring your own model** | Anthropic, OpenAI, Google, DeepSeek, OpenRouter, or local Ollama. |

---

## Quick Start

```bash
# Install
npm install -g atum

# Interactive setup (venues, model, risk envelope)
atum init

# Start the simulation server
atum serve
```

The dashboard is served at **http://127.0.0.1:9090**.

Requirements: Go 1.21+ and Node 18+ to build from source. The npm package builds the server binary on install when Go is present.

---

## Core Concepts

**Venue** — a market connection. Simulated, centralized exchange, DEX, FX bridge, or equities gateway. Each venue exposes the same normalized interface.

**Agent** — an LLM-driven actor with a tool registry, a memory store, and a risk budget. Agents observe market state, call tools, and emit decisions as events.

**Sub-agent** — a specialized reviewer an agent consults before committing a decision: market analyst, devil's advocate, narrative tracker, reflection engine, correlation scanner.

**Run** — a bounded simulation over a historical or live window, producing a metric set you can compare against other runs.

**Arena** — a ranked comparison of strategies or agent configurations over identical market data.

---

## Capabilities

### Simulation & Execution
- **Paper mode by default** — deterministic fills against simulated liquidity, configurable fees and slippage.
- **Live venues (opt-in)** — Binance, Bybit, OKX, Hyperliquid, Uniswap, Jupiter, MetaTrader 5, Interactive Brokers.
- **Normalized adapter layer** — one market interface across every venue; add a venue without touching agent code.
- **Order lifecycle** — place, cancel, monitor, reconcile. Every transition emits an event.

### Agents & Tooling
- **14 built-in tools** — `get_price`, `get_candles`, `analyze_market`, `get_balances`, `get_positions`, `risk_check`, `calculate_position_size`, `place_order`, `cancel_order`, `get_open_orders`, `backtest`, `create_alert`, `list_alerts`, `delete_alert`.
- **Real tool use** — the agent calls tools and reasons over returned data instead of narrating.
- **Context injection** — the system prompt carries live balances, positions, risk limits, and recent decisions.
- **MCP bridge** — attach external Model Context Protocol servers to extend the tool surface.
- **Structural strategies** — versioned methodology documents (Smart Money Concepts, ICT, price action, volume profile) that shape how an agent reads a chart.

### Memory
Five layers, each with a distinct role, so an agent accumulates experience without collapsing into a single embedding blob:
- **Episodic** — what happened, and when.
- **Semantic** — durable facts about venues and instruments.
- **Temporal** — time-decayed relevance.
- **Graph** — relations between entities and events.
- **Emotional** — salience weighting that decides what is worth recalling.

Consolidation runs on a schedule, promoting and pruning the store.

### Measurement
- **Backtesting engine** — event-driven replay with fees, slippage, and multi-timeframe context.
- **Metrics** — total return, win rate, profit factor, max drawdown, Sharpe and Sortino ratios, trade count.
- **Rule expressions** — `"rsi < 30 AND close > sma_50"` for fast hypothesis testing.
- **Strategy arena** — rank configurations head-to-head on shared data.
- **Optimizer** — parameter search over a declared space.

### Risk
- Pre-trade checks: position size, leverage, exposure, per-trade risk.
- Continuous P&L monitoring with drawdown thresholds.
- Circuit breaker that halts activity on abnormal loss.
- Scenario and stress analysis before capital is committed.

### Observability
- **Web dashboard** — portfolio, positions, performance vs benchmarks, allocation, risk panel, monthly return heatmap, and agent chat with tool-call traces.
- **Event bus** — `market.*`, `trade.*`, `risk.*`, `portfolio.*`, `alert.*`, `system.*` over WebSocket.
- **Alerting** — price, P&L, risk, execution, and custom-expression alerts, delivered by WebSocket, Telegram, or Discord.
- **Audit trail** — every privileged action is logged.

### Security
- AES-256-GCM credential vault with PBKDF2 key derivation.
- Role-based permissions.
- Dead switch for immediate shutdown.
- Local-only default binding (`127.0.0.1`).

---

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│                    Web Dashboard (React)                  │
├───────────────────────────────────────────────────────────┤
│              API — REST · WebSocket · GraphQL             │
├───────────┬───────────┬───────────┬───────────────────────┤
│ Agent     │  Risk     │ Backtest  │  Adapter Router       │
│ + Memory  │  Engine   │  + Arena  │  ├─ Simulated         │
│ + Sub-    │           │           │  ├─ CEX (Binance…)    │
│   agents  │           │           │  ├─ DEX (Uniswap…)    │
│ + Alerts  │           │           │  └─ FX / Equities     │
├───────────┴───────────┴───────────┴───────────────────────┤
│      SQLite  ·  Encrypted Vault  ·  Event Bus             │
└───────────────────────────────────────────────────────────┘
```

Go for the engine and concurrency, React for the dashboard, TypeScript for the CLI and plugin runtime, SQLite for zero-config local state.

---

## CLI

### Core
```bash
atum init                  # Setup wizard
atum serve                 # Start the simulation server
atum status                # System status
atum version               # Version info
```

### Venues
```bash
atum exchange list
atum exchange add binance
atum exchange test binance
atum exchange remove binance
```

Supported: `binance`, `bybit`, `okx`, `mt5`, `ibkr`, `hyperliquid`, `uniswap`

> MetaTrader 5 requires the MT5 terminal (Windows). Atum installs the Python bridge and connects with your login, password, and server name.

### Configuration
```bash
atum config show
atum config set server.port 8080
atum risk show
atum risk set max_leverage 10
atum agent show
atum agent set auto_trade false
atum agent watchlist add SOL/USDT
```

### Models
```bash
atum models setup                              # Interactive provider setup
atum models set anthropic/claude-sonnet-4-6
atum models list
atum models status
```

Keys come from the environment or the encrypted vault:

```bash
export ANTHROPIC_API_KEY=...
export OPENAI_API_KEY=...
```

### Simulation
```bash
atum backtest --symbol BTC/USDT --timeframe 4h --from 2025-06-01
atum backtest --strategy macd_cross --capital 50000
atum backtest --config strategies/my_rules.yaml
```

### Agents & Chat
```bash
atum chat          # Interactive agent session
```

### Notifications
```bash
atum telegram setup
atum telegram test
atum notify show
atum notify set discord.webhook_url <url>
```

---

## API

```bash
# Health and version
GET  /api/v1/system/health
GET  /api/v1/system/version

# Agent
POST /api/v1/chat
GET  /api/v1/agents
GET  /api/v1/agents/events

# Market data
GET  /api/v1/price?symbol=BTC/USDT&exchange=binance
GET  /api/v1/candles?symbol=BTC/USDT&timeframe=1h&limit=100
GET  /api/v1/orderbook?symbol=BTC/USDT&depth=20

# Account
GET  /api/v1/balances?exchange=binance
GET  /api/v1/positions?exchange=binance
GET  /api/v1/portfolio
GET  /api/v1/exchanges

# Research
POST /api/v1/backtest

# Streaming
GET  /ws
```

Chat request:

```json
{
  "messages": [
    { "role": "user", "content": "Compare RSI and SMC behavior on BTC/USDT over the last 90 days." }
  ]
}
```

---

## Configuration

`config/default.yaml`:

```yaml
server:
  host: 127.0.0.1
  port: 9090
database:
  path: data/atum.db
risk:
  max_risk_per_trade: 0.02
  max_daily_loss: 0.05
  max_positions: 5
  max_leverage: 10
  default_mode: paper        # paper | live
agent:
  enabled: true
  auto_trade: false
  confirmation: true
  min_confidence: 0.7
  scan_interval: 30
  watchlist:
    - BTC/USDT
    - ETH/USDT
  model:
    primary: ""              # e.g. anthropic/claude-sonnet-4-6
    max_tokens: 4096
    temperature: 0.7
mcp:
  servers: []
notifications:
  telegram:
    enabled: false
    token: ""
    chat_id: ""
  discord:
    enabled: false
    webhook_url: ""
```

Credentials are encrypted at rest in `data/vault.enc`. The database lives at `data/atum.db`.

---

## SDKs

Go, Python, and TypeScript clients live in `sdk/`.

```python
from atum import AtumClient

client = AtumClient(base_url="http://127.0.0.1:9090")
print(client.health())
```

```go
import "github.com/Lord1Egypt/atum/sdk/go/atum"

client := atum.NewClient(atum.Config{BaseURL: "http://127.0.0.1:9090"})
```

---

## Development

```bash
git clone https://github.com/Lord1Egypt/atum.git
cd atum

make build          # Build the Go server
make test           # Run the Go test suite
make run            # Start the server

cd web && npm install && npm run dev   # Dashboard in dev mode
```

### Layout

```
cmd/atum/          Go entry point and CLI commands
internal/
  adapter/         Venue adapters and normalization
  agent/           Tool registry, agent loop, context builder
  analysis/        Indicators, screener, news
  api/             HTTP, WebSocket, GraphQL
  backtest/        Replay engine, strategies, arena
  data/            Market data providers
  engine/          Event bus
  memory/          Five-layer agent memory
  mcp/             Model Context Protocol bridge
  plugin/          IPC runtime
  risk/            Risk engine, circuit breaker, monitoring
  security/        Vault, audit, permissions, dead switch
  strategy/        Arena and optimizer
  streaming/       Live price and portfolio streams
  subagent/        Specialized reviewing agents
web/               React dashboard
cli/               TypeScript CLI
sdk/               Go, Python, TypeScript clients
plugins/           Plugin runtime
strategies/        Methodology documents
config/            Default configuration
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Engine | Go |
| Dashboard | React, TypeScript, Vite |
| Storage | SQLite (WAL) |
| Encryption | AES-256-GCM, PBKDF2 |
| API | REST, WebSocket, GraphQL |
| CLI | Node.js, Go |

---

## Status

Early. The simulation core, adapter layer, memory system, and measurement engine are functional. Live execution paths exist and are opt-in; treat them as the least mature surface in the project.

---

## License

MIT — see [LICENSE](LICENSE).

---

## Strategy Library

`strategy-library/` holds a curated collection of open-source strategies, expert advisors, and indicators gathered from public GitHub repositories — 4,405 files from 433 repositories, under permissive licenses, deduplicated and organized by runtime.

See [strategy-library/README.md](strategy-library/README.md) for the layout and [strategy-library/ATTRIBUTIONS.md](strategy-library/ATTRIBUTIONS.md) for per-repo licensing.
