# ccxt_client Roadmap

**Vision:** A polished, consumer-facing Elixir library for 100+ cryptocurrency exchanges — unified API, rich types, trading analytics, and excellent developer experience.

**Parent project:** Extraction and generation happen in [ccxt_ex](../ccxt_ex/ROADMAP.md). Fixes flow downstream via `mix ccxt.sync --output --force`.

**Completed work:** See [CHANGELOG.md](CHANGELOG.md) for finished tasks.

---

## 🎯 Current Focus

**Response Quality & Documentation** — Finish WS reconnection README guide.

> **Philosophy reminder:** ccxt_client owns consumer-facing DX. If it helps the user of the library (not the builder of the generator), it belongs here.

> **Library vs App:** Tasks marked `[APP]` require stateful coordination (GenServers, ETS caches, process supervision) and belong in a consuming application. Everything else is pure-function library code. See Phase 14/15 notes for details.

### ✅ Recently Completed

| Task | Description | Notes |
|------|-------------|-------|
| Feature #2: Symbol Precision Metadata | `CCXT.MarketPrecision` module | `from_market/2`, `from_markets/2`, `tradingview_price_format/1`, 3 precision modes |
| WS Reconnection Tests | Reconnect config + subscription restoration tests | 15 behavioral tests, auth expiry scheduling |
| Auth Expiry Scheduling | Deribit WS token auto-refresh at 80% TTL | Manually ported to preserved adapter file |

### 📋 Current Tasks

| Task | Status | Notes |
|------|--------|-------|
| Feature #1: WS Reconnection Docs | 🔄 | Remaining: README reconnection guide only (llms.txt ✅) |

### Quick Commands

```bash
mix test.json --quiet                              # Unit tests (excludes :integration)
mix test.json --quiet --failed --first-failure     # Iterate on failures
mix test.json --quiet --only integration --only tier1  # Tier 1 integration
mix dialyzer.json --quiet                          # Type checking
```

---

## Pending Sync from ccxt_ex

All 3 bugs in [BUGS.md](BUGS.md) are fixed upstream. Run `mix ccxt.sync --output --force` from ccxt_ex to pull fixes:

| Bug | Fix | ccxt_ex Task |
|-----|-----|-------------|
| Deribit `fetch_trades/1` missing | Optional param arity fix | Task 176 |
| Deribit WS balance empty channel | Pattern 7 + `apply_template_params` | Task 177 |
| Deribit WS ticker missing interval | Template param application | Task 177 |

---

## Phase 1: Response Quality & Documentation

Consumer-facing documentation and metadata enrichment.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| Feature #1: WS Reconnection Docs | 🔄 | [D:5/B:9 → 1.8] 🚀 | README guide remaining (llms.txt ✅, tests ✅) |
| Feature #2: Symbol Precision Metadata | ✅ | [D:4/B:8 → 2.0] 🎯 | `CCXT.MarketPrecision` — see CHANGELOG.md |

### Feature #1: WS Reconnection Docs

[D:5/B:9 → Priority:1.8] 🚀

Document and harden WebSocket reconnection behavior for both public and authenticated flows. Clarify when to use `CCXT.WS.Client` vs adapter processes, and verify reconnect-related contracts with deterministic tests.

Success criteria:
- [x] WS helper/client tests explicitly validate reconnect configuration and restoration behavior
- [x] Adapter tests cover generated reconnection-related contract surface
- [x] `llms.txt` has a dedicated reconnection section with client vs adapter decision rules (section 12, line 325)
- [ ] `README.md` contains a short reconnection guide and points to `llms.txt`
- [x] If tests expose generator/spec defects, create a `ccxt_ex` follow-up item with repro details

Progress notes:
- 2026-02-19: Auth expiry scheduling manually ported to ccxt_client adapter (preserved file).
- 2026-02-13: Reconnection tests backported to ccxt_ex and verified via `--output --force` rebuild.

**ccxt_ex:** Linked to Task 171 (WS Auth State Tracking + Reconnection Docs)

---

### Feature #2: Normalized Symbol Precision/Tick Metadata

[D:4/B:8 → Priority:2.0] 🎯

Expose a normalized, symbol-addressable precision contract suitable for live consumers (charts, order forms, validators), so clients do not infer display/step precision from ticks. Include at least `price_increment`, `price_precision`, and `amount_precision` with clear semantics across spot/swap/future/option markets.

Success criteria:
- [ ] Public API provides per-symbol normalized precision metadata without requiring consumers to parse raw exchange payloads
- [ ] Contract defines exact meaning for `price_increment` vs decimal precision and how they map to exchanges with different precision modes
- [ ] Deribit (and at least one non-Deribit exchange) has tests proving normalized outputs are stable and symbol-correct
- [ ] Docs include migration guidance for consumers currently reading `__ccxt_spec__`/raw market data
- [ ] Backward compatibility is preserved for existing `fetch_markets` callers

Notes:
- Motivation: live TradingView/lightweight-charts integration where chart `priceFormat` should be symbol-aware
- Streaming ticker payloads do not carry precision metadata, so consumers need a stable companion metadata API

**ccxt_ex:** Linked to Task 178 (Normalized Market Precision Metadata)

---

## Phase 2: Trading DX

Pure-function trading analytics and helpers. All modules live in `lib/ccxt/trading/` (survives `--output --force` rebuilds).

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| Task 125: Order Sanity Checks | ⬜ | [D:4/B:8 → 2.0] 🎯 | Pre-submit validation for orders |
| Task 135: Best Price Routing | ⬜ | [D:5/B:7 → 1.4] 📋 | Multi-exchange best price selection |
| Task 136: Position Summary | ⬜ | [D:5/B:7 → 1.4] 📋 | Aggregate position view across exchanges |
| Task 137: Exposure Calculator | ⬜ | [D:5/B:7 → 1.4] 📋 | Total exposure across positions/exchanges |
| Task 179: Implied Probability from Options | ⬜ | [D:4/B:6 → 1.5] 🚀 | Extract market-implied probabilities from option prices |
| Task 99: Fee Calculation Logic | ⬜ | [D:4/B:6 → 1.5] 🚀 | Unified fee calculation across exchanges |

### Task 125: Order Sanity Checks

[D:4/B:8 → Priority:2.0] 🎯

Add pre-submit validation for orders: check symbol validity, order type support, min/max notional, price sanity (deviation from mark price). Pure functions that return `{:ok, order_params}` or `{:error, {:sanity_check, reason}}` — no side effects, no API calls. Uses market metadata from `fetch_markets` or `__ccxt_spec__`.

Success criteria:
- [ ] Validates symbol exists and is tradeable on the exchange
- [ ] Validates order type is supported (limit, market, stop, etc.)
- [ ] Checks min/max notional when metadata available
- [ ] Price deviation warning when far from reference price
- [ ] Tests cover all validation paths with both valid and invalid inputs

---

### Task 135: Best Price Routing

[D:5/B:7 → Priority:1.4] 📋

Given a symbol and side (buy/sell), compare prices across multiple exchanges and return the best available. Pure function that takes pre-fetched ticker data — no API calls.

Success criteria:
- [ ] Accepts list of `{exchange, ticker}` tuples, returns sorted by best price
- [ ] Handles missing/stale data gracefully
- [ ] Tests cover buy vs sell ordering, partial data, empty inputs

---

### Task 136: Position Summary

[D:5/B:7 → Priority:1.4] 📋

Aggregate position data across exchanges into a unified summary. Pure function that takes pre-fetched position data and returns totals by symbol, side, and exchange.

Success criteria:
- [ ] Aggregates long/short positions by symbol
- [ ] Calculates net exposure per symbol
- [ ] Handles mixed exchange position formats
- [ ] Tests cover single-exchange and multi-exchange scenarios

---

### Task 137: Exposure Calculator

[D:5/B:7 → Priority:1.4] 📋

Calculate total portfolio exposure across positions, including notional value, leverage, and margin usage. Pure function operating on pre-fetched data.

Success criteria:
- [ ] Calculates total notional exposure by symbol and direction
- [ ] Computes effective leverage across positions
- [ ] Tests cover spot, perpetual, and futures positions

---

### Task 179: Implied Probability from Options

[D:4/B:6 → Priority:1.5] 🚀

Extract market-implied event probabilities from option prices. Extends `CCXT.Trading.Options` with functions to derive probability distributions from call/put spreads and binary option pricing.

Success criteria:
- [ ] Functions to extract implied probability from vanilla option prices
- [ ] Support for both call and put spread implied probabilities
- [ ] Tests with known theoretical values

---

### Task 99: Fee Calculation Logic

[D:4/B:6 → Priority:1.5] 🚀

Provide unified fee calculation across exchanges. Pure functions that compute trading fees given exchange fee schedules and trade parameters.

Success criteria:
- [ ] Calculate maker/taker fees for a given trade
- [ ] Support tiered fee schedules
- [ ] Handle fee currency differences (base vs quote vs third-party token)
- [ ] Tests for major fee structures (flat, tiered, negative maker)

---

## Phase 3: Convenience & Introspection

Developer experience improvements for discovery and exploration.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| Task 78: CCXT Convenience Methods | ⬜ | [D:4/B:7 → 1.75] 🚀 | Shorthand helpers for common operations |
| Task 162: Pagination Helpers | ⬜ | [D:6/B:7 → 1.2] 📋 | Auto-paginate multi-page API responses |
| Task 131: Examples in Introspection | ⬜ | [D:5/B:7 → 1.4] 📋 | Add usage examples to introspection output |
| Task 132: Exchange Quirks | ⬜ | [D:6/B:6 → 1.0] 📋 | Document exchange-specific behaviors |
| Task 139: Nullable Field Indicators | ⬜ | [D:5/B:6 → 1.2] 📋 | Mark which response fields can be nil |

### Task 78: CCXT Convenience Methods

[D:4/B:7 → Priority:1.75] 🚀

Add shorthand helpers for the most common multi-step operations (e.g., "get my BTC balance on Bybit" without manually parsing the full balance response). Should compose existing functions, not add new API calls.

Success criteria:
- [ ] Convenience functions for common workflows (quick balance lookup, position check, etc.)
- [ ] All functions are thin wrappers around existing API — no new HTTP calls
- [ ] Tests verify correct composition of underlying functions

---

### Task 162: Pagination Helpers

[D:6/B:7 → Priority:1.2] 📋

Provide helpers for auto-paginating endpoints that return partial results (trade history, order history). Should handle cursor-based and offset-based pagination patterns.

Success criteria:
- [ ] Generic pagination function that works across exchanges
- [ ] Handles cursor-based (since/until) and offset-based patterns
- [ ] Configurable page size and max pages
- [ ] Tests with mock paginated responses

---

### Task 131: Examples in Introspection

[D:5/B:7 → Priority:1.4] 📋

Enrich `__ccxt_spec__` introspection output with usage examples for each endpoint. When an AI coder inspects an exchange module, they should see how to call each function.

Success criteria:
- [ ] Each endpoint in introspection includes at least one usage example
- [ ] Examples show required and optional parameters
- [ ] Tests verify examples are present and syntactically valid

---

### Task 132: Exchange Quirks

[D:6/B:6 → Priority:1.0] 📋

Document known exchange-specific behaviors that deviate from the unified API contract (e.g., "Kraken returns fees in a different currency", "Deribit requires interval suffix for ticker subscriptions").

Success criteria:
- [ ] Quirks accessible via introspection API
- [ ] At least Tier 1 exchanges have documented quirks
- [ ] Tests verify quirks data is present for documented exchanges

---

### Task 139: Nullable Field Indicators

[D:5/B:6 → Priority:1.2] 📋

Mark which fields in response types can be nil. Currently consumers discover nullable fields by trial and error. Add metadata so they can handle nil values proactively.

Success criteria:
- [ ] Response type introspection includes nullable field list
- [ ] At least core types (Ticker, Order, Balance) have nullable fields documented
- [ ] Tests verify nullable metadata matches actual API behavior

---

## Phase 4: Normalization Expansion (Deferred)

These tasks expand the normalization pipeline built during the ccxt_ex split. Lower priority until Phase 1-3 items are stable.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| Task 170d: Missing Schema Types | ⬜ | [D:5/B:5 → 1.0] 📋 | Add types not yet in schema |
| Task 175e: Broad Normalization Phase 2 | ⬜ | [D:6/B:6 → 1.0] 📋 | Extend normalization to more response types |

---

## Phase 5: Options Analytics Expansion

Pure functions extending `CCXT.Trading.Options.*`. No API calls — all operate on pre-fetched data.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `Options.GammaWalls.aggregate/3` | ⬜ | [D:2/B:9 → 4.5] 🎯 | Pure GEX aggregation from chain/greeks/OI |
| `Options.atm_iv/2` | ⬜ | [D:2/B:8 → 4.0] 🎯 | ATM implied volatility extraction |
| `Options.pin_risk/3` | ⬜ | [D:2/B:8 → 4.0] 🎯 | High-OI strikes near spot |
| `Options.aggregate_oi/1` | ⬜ | [D:2/B:7 → 3.5] 🎯 | Aggregate OI across expiries |
| `Options.breakeven_move/2` | ⬜ | [D:2/B:7 → 3.5] 🎯 | % move needed to profit |
| `Options.expected_range/3` | ⬜ | [D:2/B:7 → 3.5] 🎯 | 1-sigma move from IV |
| `Options.theta_per_hour/1` | ⬜ | [D:2/B:6 → 3.0] 🎯 | Hourly theta decay rate |
| `Options.Mispricing.scan/3` | ⬜ | [D:3/B:8 → 2.67] 🎯 | Market vs model price comparison |
| `Options.Snapshot.to_report/2` | ⬜ | [D:3/B:7 → 2.33] 🎯 | Chain → briefing data |
| `Options.Pricing.with_drift/3` | ⬜ | [D:4/B:8 → 2.0] 🎯 | Black-Scholes variant with drift term |
| `Options.Surface.build/1` | ⬜ | [D:4/B:7 → 1.75] 🚀 | IV/strike/expiry matrix |
| `Options.Skew.term_structure/1` | ⬜ | [D:4/B:5 → 1.25] 📋 | Skew helpers |

---

## Phase 6: Funding, Risk & Quantitative Models

Extensions to `CCXT.Trading.Funding`, `CCXT.Trading.Risk`, `CCXT.Trading.PowerLaw`, and new `CCXT.Trading.Models.*`.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `PowerLaw.fair_value_range/2` | ⬜ | [D:2/B:8 → 4.0] 🎯 | Fair value with confidence intervals |
| `Risk.portfolio_delta/1` | ⬜ | [D:2/B:7 → 3.5] 🎯 | Net delta exposure across positions |
| `Risk.exposure_by_asset/1` | ⬜ | [D:2/B:7 → 3.5] 🎯 | Group positions by asset |
| `Aggregate.funding_rank/2` | ⬜ | [D:2/B:7 → 3.5] 🎯 | Rank symbols by funding rate |
| `Aggregate.bbo/2` | ⬜ | [D:3/B:7 → 2.33] 🎯 | Best bid/offer across exchanges |
| `PowerLaw.forecast/2` | ⬜ | [D:2/B:6 → 3.0] 🎯 | Project fair value to future date |
| `Models.MeanReversion.half_life/1` | ⬜ | [D:2/B:6 → 3.0] 🎯 | Ornstein-Uhlenbeck half-life calc |
| `Funding.trend/2` | ⬜ | [D:3/B:8 → 2.67] 🎯 | Detect funding rate trend |
| `Risk.check_limits/2` (pipeline) | ⬜ | [D:3/B:8 → 2.67] 🎯 | Composable risk limit pipeline (basic `check_limits/2` exists — this extends to pipeline) |
| `Funding.mean_reversion_signal/2` | ⬜ | [D:3/B:7 → 2.33] 🎯 | Z-score on funding distribution |
| `Funding.arb_opportunities/2` | ⬜ | [D:4/B:9 → 2.25] 🎯 | Cross-exchange funding arb detection |
| `Risk.liquidation_watch/2` | ⬜ | [D:4/B:7 → 1.75] 🚀 | Distance to liquidation monitoring |
| `Risk.stress_test/3` | ⬜ | [D:5/B:7 → 1.4] 📋 | Hypothetical move P&L |

---

## Phase 7: Deribit Convenience API

Network wrappers for common Deribit workflows. These make API calls using existing exchange module functions.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `Options.Deribit.dvol/1` | ⬜ | [D:1/B:7 → 7.0] 🎯 | Single API call for DVOL index |
| `Options.Deribit.chain/2` | ⬜ | [D:2/B:9 → 4.5] 🎯 | Fetch full options chain |
| `Options.Deribit.block_trades/2` | ⬜ | [D:2/B:6 → 3.0] 🎯 | Institutional flow signal |
| `Options.Deribit.gamma_walls/4` | ⬜ | [D:3/B:9 → 3.0] 🎯 | Networked fetch + GEX assembly |

---

## Phase 8: 0DTE & Expiry Helpers

Specialized functions for zero-days-to-expiry and near-expiry options analysis.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `ZeroDTE.near_strikes/3` | ⬜ | [D:2/B:7 → 3.5] 🎯 | Strikes near spot for near-expiry |
| `ZeroDTE.theta_acceleration/2` | ⬜ | [D:3/B:7 → 2.33] 🎯 | Theta decay acceleration curve |
| `ZeroDTE.gamma_exposure/2` | ⬜ | [D:4/B:9 → 2.25] 🎯 | GEX for near-expiry options |
| `ZeroDTE.pin_risk/3` | ⬜ | [D:4/B:6 → 1.5] 🚀 | Pin risk for near-expiry |
| `ZeroDTE.roll_to_next/4` | ⬜ | [D:5/B:6 → 1.2] 📋 | `[APP]` Roll position to next expiry |

---

## Phase 9: Execution

Order execution helpers. `best_price/3` overlaps with Task 135 (Phase 2) — merge when implementing.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `Execution.best_price/3` | ⬜ | [D:3/B:8 → 2.67] 🎯 | Overlaps Task 135, merge |
| `Execution.split_order/4` | ⬜ | [D:5/B:7 → 1.4] 📋 | Split large order into chunks |
| `Execution.twap/5` | ⬜ | [D:6/B:6 → 1.0] 📋 | `[APP]` Time-weighted average price execution |
| `Execution.iceberg/5` | ⬜ | [D:5/B:5 → 1.0] 📋 | `[APP]` Iceberg order logic |

---

## Phase 10: Market Making

Pure-function market making analytics and helpers.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `MM.spread_calculator/2` | ⬜ | [D:2/B:7 → 3.5] 🎯 | Optimal spread from volatility/inventory |
| `MM.fair_value/3` | ⬜ | [D:3/B:7 → 2.33] 🎯 | Fair value estimate from orderbook |
| `MM.spread_tracker/3` | ⬜ | [D:4/B:8 → 2.0] 🎯 | Track spread changes over time |
| `MM.inventory_skew/3` | ⬜ | [D:5/B:8 → 1.6] 🚀 | Adjust quotes for inventory |
| `MM.fill_rate/3` | ⬜ | [D:4/B:6 → 1.5] 🚀 | Historical fill rate analysis |
| `MM.quote_manager/4` | ⬜ | [D:6/B:8 → 1.33] 📋 | `[APP]` Quote lifecycle management |

---

## Phase 11: Orderflow

Pure functions operating on trade maps. `side` and `taker_or_maker` already exist as optional fields in the WS trade contract (`lib/ccxt/ws/contract.ex:136`). No dependency on stale Task 154.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `Orderflow.cvd_delta/1` | ⬜ | [D:1/B:9 → 9.0] 🎯 | Cumulative volume delta from trades |
| `Orderflow.imbalance/2` | ⬜ | [D:2/B:8 → 4.0] 🎯 | Buy/sell imbalance ratio |
| `Orderflow.vwap/1` | ⬜ | [D:2/B:7 → 3.5] 🎯 | Volume-weighted average price |
| `Orderflow.heatmap_point/2` | ⬜ | [D:2/B:7 → 3.5] 🎯 | Price/volume heatmap data point |
| `Orderflow.footprint_cell/3` | ⬜ | [D:3/B:8 → 2.67] 🎯 | Footprint chart cell data |
| `Orderflow.dom_level/2` | ⬜ | [D:3/B:8 → 2.67] 🎯 | Depth-of-market level construction |

---

## Phase 12: Health & Monitoring

Exchange health checks and latency monitoring.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `Health.latency/1` | ⬜ | [D:1/B:7 → 7.0] 🎯 | Finch telemetry wrapper for latency |
| `Health.ping/1` | ⬜ | [D:2/B:8 → 4.0] 🎯 | Exchange alive check |
| `Health.all/1` | ⬜ | [D:3/B:8 → 2.67] 🎯 | Bulk health check across exchanges |
| `Health.status/2` | ⬜ | [D:3/B:7 → 2.33] 🎯 | Composite status with degradation |

---

## Phase 13: WS Aggregation & Monitors

Thin wrappers over ZenWebsocket for multi-exchange streaming workflows. ZenWebsocket provides the underlying APIs — these add coordination logic. Note: 4 of 6 tasks are `[APP]`-level (require GenServers, process supervision, or real-time state).

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `WS.stale_check/2` | ⬜ | [D:1/B:8 → 8.0] 🎯 | Detect stale WS data |
| `WS.reconnect_metrics/1` | ⬜ | [D:1/B:6 → 6.0] 🎯 | Reconnection stats |
| `WS.liquidation_monitor/2` | ⬜ | [D:3/B:9 → 3.0] 🎯 | `[APP]` Margin alert system |
| `WS.cross_exchange_bbo/3` | ⬜ | [D:4/B:8 → 2.0] 🎯 | `[APP]` Cross-exchange best bid/offer |
| `WS.funding_monitor/2` | ⬜ | [D:3/B:6 → 2.0] 🎯 | `[APP]` Real-time funding rate monitor |
| `WS.Aggregator` | ⬜ | [D:5/B:9 → 1.8] 🚀 | `[APP]` Multi-exchange WS manager |

---

## Phase 14: Order Management

State tracking for order lifecycle. `on_fill/2` is a pure immutable update (library). `history/1` and `track/2` require stateful infrastructure (GenServer/ETS) — `[APP]`-level.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `OrderState.on_fill/2` | ⬜ | [D:3/B:8 → 2.67] 🎯 | Fill event handling |
| `OrderState.history/1` | ⬜ | [D:3/B:6 → 2.0] 🎯 | `[APP]` Order history tracking |
| `OrderState.track/2` | ⬜ | [D:4/B:7 → 1.75] 🚀 | `[APP]` Stateful order tracking (GenServer) |

---

## Phase 15: Market Data Infrastructure

Caching, bootstrapping, and subscription management. 4 of 5 tasks are `[APP]`-level (ETS caches, process supervision, startup coordination). Only `Telemetry` is library code (event schema definition).

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `MarketData.Store` | ⬜ | [D:3/B:9 → 3.0] 🎯 | `[APP]` ETS-backed market data cache |
| `MarketData.Telemetry` | ⬜ | [D:2/B:6 → 3.0] 🎯 | Market data telemetry events |
| `Cache` macro (ETS+TTL+stampede) | ⬜ | [D:4/B:9 → 2.25] 🎯 | `[APP]` Generic cache with TTL and stampede prevention |
| `MarketData.Bootstrapper` | ⬜ | [D:5/B:7 → 1.4] 📋 | `[APP]` Initial data loading on startup |
| `MarketData.SubscriptionRegistry` | ⬜ | [D:4/B:5 → 1.25] 📋 | `[APP]` Track active WS subscriptions |

---

## Phase 16: Timeseries & Recording

Data recording and replay for backtesting and debugging.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `Recorder.JSONL` | ⬜ | [D:2/B:8 → 4.0] 🎯 | JSONL file recorder |
| `Recorder.Replay` | ⬜ | [D:3/B:7 → 2.33] 🎯 | Replay recorded data |
| `Recorder.SQLite` | ⬜ | [D:5/B:5 → 1.0] 📋 | SQLite storage backend |

---

## Phase 17: Symbol & Instrument Normalization

Deeper symbol normalization beyond what Phase 4 covers.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `Instrument` struct | ⬜ | [D:3/B:8 → 2.67] 🎯 | Rich instrument type (symbol + metadata) |
| `Symbol.normalize/2` | ✅ | [D:4/B:7 → 1.75] 🚀 | `CCXT.Symbol.normalize/2` + `denormalize/2` exist |
| `Symbol.to_exchange/3` | ✅ | [D:4/B:7 → 1.75] 🚀 | `CCXT.Symbol.to_exchange_id/3` + `from_exchange_id/3` exist |

---

## Phase 18: Testing & Dev Tools

Tools to make testing and development with ccxt_client easier.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| Analytics fixtures | ⬜ | [D:2/B:7 → 3.5] 🎯 | Shared test fixtures for trading modules |
| One-liner setup docs | ⬜ | [D:2/B:6 → 3.0] 🎯 | Quickstart guide improvements |
| `WS.Debug.capture_subscription/3` | ⬜ | [D:3/B:7 → 2.33] 🎯 | Capture WS subscription for debugging |
| `Snapshot.capture/2` | ⬜ | [D:3/B:6 → 2.0] 🎯 | Capture exchange state snapshot |
| `Mock.stub_exchange/2` | ⬜ | [D:4/B:7 → 1.75] 🚀 | Mock exchange for testing |

---

## Phase 19: Distribution & Extensibility

Allow consumers to extend ccxt_client with custom exchanges or override specs.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| Custom spec loading | ⬜ | [D:3/B:8 → 2.67] 🎯 | Load specs from consumer's priv directory |
| CCXT as optional update source | ⬜ | [D:5/B:7 → 1.4] 📋 | Pull spec updates without ccxt_ex |
| Spec registry | ⬜ | [D:6/B:7 → 1.17] 📋 | Registry for spec discovery/management |

---

## Phase 20: Reliability & Ops

Production reliability improvements.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `Policy` (retry/backoff) | ⬜ | [D:3/B:8 → 2.67] 🎯 | Configurable retry/backoff policies |
| `RateLimit` visibility | ✅ | [D:3/B:6 → 2.0] 🎯 | `CCXT.HTTP.RateLimiter` — per-credential sliding window, state accessible |

---

## Deferred / Specialized

Items from wishlists that depend on other infrastructure or are assumption-heavy. Revisit when dependencies are met.

| Item | Depends on | Notes |
|------|-----------|-------|
| `Options.ProxyRegime.classify/1` | Recorder (Phase 16) | Regime classification from recorded data |
| `Options.ExpiryGreeks.diff/2` | Snapshots (Phase 18) | Greeks diff between snapshots |
| `DealerPositioning.estimate/2` | — | Probabilistic, assumption-heavy — needs research |
| Orderflow macros (CVD, Footprint, DOM, Heatmap) | Phase 11 complete | Level 2: composable dashboard macros |
| `use Orderflow.Dashboard` | Orderflow macros | Level 3: UI layer |

---

## Priority Order (Top 40 by ROI)

Sorted by Benefit/Difficulty ratio. Complete list — lower-priority items within each phase table above.

| # | Item | Score | Phase |
|---|------|-------|-------|
| 1 | `Orderflow.cvd_delta/1` | [D:1/B:9 → 9.0] 🎯 | 11 |
| 2 | `WS.stale_check/2` | [D:1/B:8 → 8.0] 🎯 | 13 |
| 3 | `Health.latency/1` | [D:1/B:7 → 7.0] 🎯 | 12 |
| 4 | `Options.Deribit.dvol/1` | [D:1/B:7 → 7.0] 🎯 | 7 |
| 5 | `WS.reconnect_metrics/1` | [D:1/B:6 → 6.0] 🎯 | 13 |
| 6 | `Options.GammaWalls.aggregate/3` | [D:2/B:9 → 4.5] 🎯 | 5 |
| 7 | `Options.Deribit.chain/2` | [D:2/B:9 → 4.5] 🎯 | 7 |
| 8 | `Options.atm_iv/2` | [D:2/B:8 → 4.0] 🎯 | 5 |
| 9 | `Options.pin_risk/3` | [D:2/B:8 → 4.0] 🎯 | 5 |
| 10 | `PowerLaw.fair_value_range/2` | [D:2/B:8 → 4.0] 🎯 | 6 |
| 11 | `Orderflow.imbalance/2` | [D:2/B:8 → 4.0] 🎯 | 11 |
| 12 | `Health.ping/1` | [D:2/B:8 → 4.0] 🎯 | 12 |
| 13 | `Recorder.JSONL` | [D:2/B:8 → 4.0] 🎯 | 16 |
| 14 | `Options.aggregate_oi/1` | [D:2/B:7 → 3.5] 🎯 | 5 |
| 15 | `Options.breakeven_move/2` | [D:2/B:7 → 3.5] 🎯 | 5 |
| 16 | `Options.expected_range/3` | [D:2/B:7 → 3.5] 🎯 | 5 |
| 17 | `Risk.portfolio_delta/1` | [D:2/B:7 → 3.5] 🎯 | 6 |
| 18 | `Risk.exposure_by_asset/1` | [D:2/B:7 → 3.5] 🎯 | 6 |
| 19 | `Aggregate.funding_rank/2` | [D:2/B:7 → 3.5] 🎯 | 6 |
| 20 | `MM.spread_calculator/2` | [D:2/B:7 → 3.5] 🎯 | 10 |
| 21 | `Orderflow.vwap/1` | [D:2/B:7 → 3.5] 🎯 | 11 |
| 22 | `Orderflow.heatmap_point/2` | [D:2/B:7 → 3.5] 🎯 | 11 |
| 23 | `ZeroDTE.near_strikes/3` | [D:2/B:7 → 3.5] 🎯 | 8 |
| 24 | Analytics fixtures | [D:2/B:7 → 3.5] 🎯 | 18 |
| 25 | `Options.theta_per_hour/1` | [D:2/B:6 → 3.0] 🎯 | 5 |
| 26 | `PowerLaw.forecast/2` | [D:2/B:6 → 3.0] 🎯 | 6 |
| 27 | `Models.MeanReversion.half_life/1` | [D:2/B:6 → 3.0] 🎯 | 6 |
| 28 | `MarketData.Store` | [D:3/B:9 → 3.0] 🎯 | 15 |
| 29 | `MarketData.Telemetry` | [D:2/B:6 → 3.0] 🎯 | 15 |
| 30 | `Options.Deribit.block_trades/2` | [D:2/B:6 → 3.0] 🎯 | 7 |
| 31 | `Options.Deribit.gamma_walls/4` | [D:3/B:9 → 3.0] 🎯 | 7 |
| 32 | `WS.liquidation_monitor/2` | [D:3/B:9 → 3.0] 🎯 | 13 |
| 33 | One-liner setup docs | [D:2/B:6 → 3.0] 🎯 | 18 |
| 34 | `Options.Mispricing.scan/3` | [D:3/B:8 → 2.67] 🎯 | 5 |
| 35 | `Funding.trend/2` | [D:3/B:8 → 2.67] 🎯 | 6 |
| 36 | `Risk.check_limits/2` (pipeline extension) | [D:3/B:8 → 2.67] 🎯 | 6 |
| 37 | `Execution.best_price/3` | [D:3/B:8 → 2.67] 🎯 | 9 |
| 38 | `Orderflow.footprint_cell/3` | [D:3/B:8 → 2.67] 🎯 | 11 |
| 39 | `Orderflow.dom_level/2` | [D:3/B:8 → 2.67] 🎯 | 11 |
| 40 | `Health.all/1` | [D:3/B:8 → 2.67] 🎯 | 12 |

**Phases 1-4 items** (from original roadmap, sorted by ROI):

| # | Item | Score | Phase |
|---|------|-------|-------|
| 1 | ~~Feature #2: Symbol Precision Metadata~~ | ~~[D:4/B:8 → 2.0] 🎯~~ ✅ | 1 |
| 2 | Task 125: Order Sanity Checks | [D:4/B:8 → 2.0] 🎯 | 2 |
| 3 | Feature #1: WS Reconnection Docs | [D:5/B:9 → 1.8] 🚀 (README guide remaining) | 1 |
| 4 | Task 78: CCXT Convenience Methods | [D:4/B:7 → 1.75] 🚀 | 3 |
| 5 | Task 179: Implied Probability from Options | [D:4/B:6 → 1.5] 🚀 | 2 |
| 6 | Task 99: Fee Calculation Logic | [D:4/B:6 → 1.5] 🚀 | 2 |
| 7 | Task 131: Examples in Introspection | [D:5/B:7 → 1.4] 📋 | 3 |
| 8 | Task 135: Best Price Routing | [D:5/B:7 → 1.4] 📋 | 2 |
| 9 | Task 136: Position Summary | [D:5/B:7 → 1.4] 📋 | 2 |
| 10 | Task 137: Exposure Calculator | [D:5/B:7 → 1.4] 📋 | 2 |
| 11 | Task 162: Pagination Helpers | [D:6/B:7 → 1.2] 📋 | 3 |
| 12 | Task 139: Nullable Field Indicators | [D:5/B:6 → 1.2] 📋 | 3 |
| 13 | Task 132: Exchange Quirks | [D:6/B:6 → 1.0] 📋 | 3 |
| 14 | Task 170d: Missing Schema Types | [D:5/B:5 → 1.0] 📋 | 4 |
| 15 | Task 175e: Broad Normalization Phase 2 | [D:6/B:6 → 1.0] 📋 | 4 |

---

## Roadmap Maintenance

When completing a task:
1. Move full task details to `CHANGELOG.md`
2. Update summary table status (⬜ → ✅)
3. Keep only a one-line reference in this file
4. Strike through in priority order list

**Cross-repo coordination:** Tasks requiring generator/spec changes are tracked in [ccxt_ex/ROADMAP.md](../ccxt_ex/ROADMAP.md). Consumer-facing work stays here. When a task spans both repos, use the same task ID/title in both files.

**Source wishlists:** Phases 5-20 were sourced from two wishlist files in ccxt_ex:
- `ccxt_ex/NADA_wishlist.md` — Options, orderflow, market data infrastructure items
- `ccxt_ex/claude_wishlist.md` — Trading analytics, execution, monitoring, distribution items

Many items from those wishlists are **already implemented** in `CCXT.Trading.*` modules (~85 public functions). See the audit plan for the full list of already-built functions.

**Already implemented (from wishlists):** Options (max_pain, put_call_ratio, gamma_flip, pin_magnets, oi_by_strike, oi_by_expiry, greeks_sum, gex_by_strike, etc.), Greeks (position_greeks, dollar_delta, delta_neutral?, hedge_ratio, etc.), Risk (var, beta, sharpe_ratio, sortino_ratio, max_drawdown, etc.), Funding (annualize, average, detect_spikes, compare, cumulative, etc.), Basis (spot_perp, annualized, futures_curve, implied_funding, etc.), Sizing (fixed_fractional, kelly, volatility_scaled, etc.), Volatility (realized, parkinson, iv_percentile, iv_rank, cone, etc.), PowerLaw (fair_value, z_score, support, resistance, classify, etc.), Portfolio (total_exposure, unrealized_pnl, realized_pnl), Options.Deribit (parse_option, strike, expiry, option_type, underlying, valid_option?).
