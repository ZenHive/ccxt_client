# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@include ~/.claude/includes/across-instances.md
@include ~/.claude/includes/critical-rules.md
@include ~/.claude/includes/skills-awareness.md
@include ~/.claude/includes/task-prioritization.md
@include ~/.claude/includes/task-writing.md
@include ~/.claude/includes/web-command.md
@include ~/.claude/includes/code-style.md
@include ~/.claude/includes/development-philosophy.md
@include ~/.claude/includes/documentation-guidelines.md
@include ~/.claude/includes/api-integration.md
@include ~/.claude/includes/development-commands.md
@include ~/.claude/includes/elixir-patterns.md
@include ~/.claude/includes/elixir-setup.md
@include ~/.claude/includes/ex-unit-json.md
@include ~/.claude/includes/dialyzer-json.md
@include ~/.claude/includes/library-design.md
@include ~/.claude/includes/zen-websocket.md

## Project Overview

**ccxt_client** is a standalone Elixir library providing unified access to 100+ cryptocurrency exchanges. It is the **distributable product** generated from the parent `ccxt_ex` project (the factory). This repo contains only runtime code — no extraction tooling or Node.js dependencies.

- **App name**: `:ccxt_client`
- **Module namespace**: `CCXT.*` (not `CcxtClient.*`)
- **Parent project**: `ccxt_ex` at `~/_DATA/code/ccxt_ex`

## Commands

```bash
mix test.json --quiet                    # Run tests (AI-friendly output, excludes :integration)
mix test.json --quiet --failed           # Re-run only previously failed tests
mix test.json --quiet --only signing     # Signing tests (offline, no credentials)
mix test.json --quiet --only integration --only tier1   # Tier 1 integration tests
mix dialyzer.json --quiet                # Type checking
mix credo                                # Static analysis
mix format                               # Format code (Styler plugin)
mix tidewave                             # Start Tidewave MCP server on port 4001
```

### Integration tests require testnet credentials

Set env vars before running (e.g., `BYBIT_TESTNET_API_KEY`, `BYBIT_TESTNET_API_SECRET`). See `test/test_helper.exs` for the full list of supported exchanges and env var naming conventions.

## Architecture

### Compile-Time Code Generation

Exchange modules are ~11 lines each — all API functions are generated at compile time from spec files:

```
priv/specs/extracted/*.exs  →  CCXT.Generator macro  →  CCXT.Bybit, CCXT.Deribit, etc.
```

Each exchange module: `use CCXT.Generator, spec: "bybit"` — this expands into all endpoint functions, typespecs, and introspection methods. Specs are tracked via `@external_resource` for automatic recompilation on change.

### Key Layers

| Layer | Modules | Purpose |
|-------|---------|---------|
| **Exchange Modules** | `CCXT.Bybit`, `CCXT.Deribit`, etc. | Generated API surface — one module per exchange |
| **Generator** | `CCXT.Generator`, `.Functions`, `.SpecLoader`, `.Introspection` | Macro system that builds exchange modules from specs |
| **HTTP** | `CCXT.HTTP.Client`, `CCXT.HTTP.RateLimiter` | Req-based client with per-credential rate limiting |
| **Signing** | `CCXT.Signing.*` (7 patterns) | Parameterized signing covers 95%+ of exchanges |
| **Symbols** | `CCXT.Symbol` | Bidirectional normalization: `"BTC/USDT"` ↔ `"BTCUSDT"` |
| **Errors** | `CCXT.Error` | Unified error types (`:rate_limited`, `:insufficient_balance`, etc.) |
| **Resilience** | `CCXT.CircuitBreaker`, `CCXT.Recovery` | Per-exchange circuit breakers via req_fuse |
| **Observability** | `CCXT.Telemetry` | Centralized telemetry contract (6 events), `attach/2`/`detach/1`, contract versioning |
| **Types** | `CCXT.Types.*` | Response structs (Order, Ticker, Balance, etc.) |
| **Trading** | `CCXT.Trading.*` (Funding, Greeks, Risk, Basis, Sizing, Volatility, Options, Portfolio, PowerLaw) | Analytics and trading helpers — hand-written, survive `--output --force` |

### Signing Patterns (7 parameterized patterns)

| Pattern | Style | Exchanges |
|---------|-------|-----------|
| `:hmac_sha256_query` | Binance-style | ~40 exchanges |
| `:hmac_sha256_headers` | Bybit-style | ~30 exchanges |
| `:hmac_sha256_iso_passphrase` | OKX-style | ~10 exchanges |
| `:hmac_sha256_passphrase_signed` | KuCoin-style | handful |
| `:hmac_sha512_nonce` | Kraken-style | handful |
| `:hmac_sha512_gate` | Gate.io-style | handful |
| `:hmac_sha384_payload` | Bitfinex-style | handful |

### Design Decisions

- **No behaviour enforcement**: Exchange APIs vary too much for a strict behaviour. Each exchange module has its own `@spec` definitions validated by Dialyzer instead.
- **Safe retry policy**: Default `:safe_transient` only retries GET/HEAD — prevents duplicate orders on POST timeout/retry.
- **Manual query encoding**: Not using Req's `:params` step because signing requires raw params before URL encoding, and some exchanges require alphabetically sorted params.
- **Per-credential rate limiting**: Key format `{:exchange, api_key}` isolates users — User A's limits don't affect User B.
- **Circuit breaker isolation**: Per-exchange — Binance down ≠ Bybit down. Does NOT trip on 429 (rate limits) or 4xx (client errors).

## Test Tags

Tests use an extensive tag system. Default `mix test` excludes `:integration`. Key tags:

- **Type**: `:unit`, `:integration`, `:smoke`, `:ws_smoke`, `:introspection`
- **Tier**: `:tier1` (production-ready), `:tier2` (integration-tested), `:tier3` (compile-only)
- **Feature**: `:public`, `:authenticated`, `:signing`, `:passphrase`
- **Exchange**: `:exchange_bybit`, `:exchange_deribit`, etc.

## Updating This Package

This is a generated package. To update from the parent project:

```bash
# From ccxt_ex directory:
mix ccxt.sync --tier1 --output ../ccxt_client --force    # Tier 1 only
mix ccxt.sync --all --output ../ccxt_client --force      # All exchanges
```

Do not manually edit generated exchange modules or spec files — changes will be overwritten on next sync.

## Rebuild Safety

The `--output --force` sync from ccxt_ex **preserves hand-written directories**:

| Directory | Contents | Survives rebuild? |
|-----------|----------|-------------------|
| `lib/ccxt/trading/` | Trading DX modules (`CCXT.Trading.*`) | Yes |
| `test/ccxt/trading/` | Trading tests | Yes |
| `lib/ccxt/exchanges/` | Generated exchange modules | No (regenerated) |
| `priv/specs/` | Exchange spec files | No (regenerated) |

**Safe to edit**: Anything in `lib/ccxt/trading/` and `test/ccxt/trading/`. These are backed up before clean and restored after.

**Do NOT edit**: Generated exchange modules, spec files, or core runtime modules — these are overwritten on every sync.

## Trading Modules (`CCXT.Trading.*`)

Hand-written pure-function modules for trading analytics and helpers. These live in ccxt_client (not ccxt_ex) because they are consumer-facing features with zero coupling to extraction infrastructure.

| Module | Purpose |
|--------|---------|
| `CCXT.Trading.Funding` | Funding rate calculations, annualized APR/APY |
| `CCXT.Trading.Greeks` | Options greeks (delta, gamma, theta, vega, rho) via Black-Scholes |
| `CCXT.Trading.Risk` | Position risk metrics (Kelly criterion, Sharpe, Sortino, drawdown) |
| `CCXT.Trading.Basis` | Futures basis/premium calculations, annualized carry |
| `CCXT.Trading.Sizing` | Position sizing strategies (fixed, percent equity, volatility-based) |
| `CCXT.Trading.Volatility` | Volatility estimators (realized, Parkinson, Garman-Klass, Yang-Zhang) |
| `CCXT.Trading.Options` | Options strategy analysis, payoff diagrams, breakeven |
| `CCXT.Trading.Options.Deribit` | Deribit-specific option instrument parsing |
| `CCXT.Trading.PowerLaw` | Bitcoin power law model calculations |
| `CCXT.Trading.Portfolio` | Portfolio analytics (correlation, beta, VaR) |
| `CCXT.Trading.Helpers.Funding` | Funding rate display formatting |
| `CCXT.Trading.Helpers.Greeks` | Greeks display formatting |
| `CCXT.Trading.Helpers.Risk` | Risk metrics display formatting |

## Git Commit Configuration

**Configured**: 2026-02-11

### Commit Message Format

**Format**: conventional-commits

#### Template
```
<type>(<scope>): <description>
```
**Types**: feat, fix, docs, style, refactor, test, chore
