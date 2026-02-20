# Trading Features Backlog

> **For the Claude instance reading this:** This is the feature backlog for trading analytics. The already-built modules have been extracted to **quantex** (`../quantex`) — a standalone trading analytics library. Remaining tasks here are future work for quantex.

**Origin:** Extracted from ccxt_client's ROADMAP.md on 2026-02-20. These features were originally planned alongside exchange access but are trading analytics and stateful coordination — not core exchange functionality.

**Status:** The 13 already-built modules (85+ functions) were extracted to quantex in February 2026. They now live at `../quantex/lib/quantex/`. quantex is a private library and is not publicly available.

**Architecture direction:** May be delivered as an EIP-8004 agent service rather than a traditional Hex library. Delivery mechanism TBD — what matters here is the feature inventory.

**Dependency:** All features depend on [ccxt_client](https://hex.pm/packages/ccxt_client) for exchange access (HTTP, WebSocket, signing, symbol normalization).

**Classification:** Tasks marked `[APP]` require stateful coordination (GenServers, ETS caches, process supervision). Unmarked tasks are pure functions. In an agent architecture, `[APP]` tasks are natural — agents ARE processes.

**Source wishlists:** Many tasks originated from `ccxt_ex/NADA_wishlist.md` and `ccxt_ex/claude_wishlist.md`. ~85 functions from those wishlists are already implemented.

---

## Already Built (Extracted to quantex)

These modules now live in **quantex** at `../quantex/lib/quantex/` (tests at `../quantex/test/quantex/`). Previously in ccxt_client at `lib/ccxt/trading/`, they were extracted in February 2026.

| Module | Key Functions |
|--------|---------------|
| `CCXT.Trading.Options` | max_pain, put_call_ratio, gamma_flip, pin_magnets, oi_by_strike, oi_by_expiry, greeks_sum, gex_by_strike, payoff, breakeven, strategy analysis |
| `CCXT.Trading.Options.Deribit` | parse_option, strike, expiry, option_type, underlying, valid_option? |
| `CCXT.Trading.Greeks` | delta, gamma, theta, vega, rho, position_greeks, dollar_delta, delta_neutral?, hedge_ratio |
| `CCXT.Trading.Risk` | var, beta, sharpe_ratio, sortino_ratio, max_drawdown, check_limits |
| `CCXT.Trading.Funding` | annualize, average, detect_spikes, compare, cumulative |
| `CCXT.Trading.Basis` | spot_perp, annualized, futures_curve, implied_funding |
| `CCXT.Trading.Sizing` | fixed_fractional, kelly, volatility_scaled |
| `CCXT.Trading.Volatility` | realized, parkinson, garman_klass, yang_zhang, iv_percentile, iv_rank, cone |
| `CCXT.Trading.PowerLaw` | fair_value, z_score, support, resistance, classify |
| `CCXT.Trading.Portfolio` | total_exposure, unrealized_pnl, realized_pnl |
| `CCXT.Trading.Helpers.Funding` | Display formatting for funding rates |
| `CCXT.Trading.Helpers.Greeks` | Display formatting for greeks |
| `CCXT.Trading.Helpers.Risk` | Display formatting for risk metrics |

---

## Options Analytics

**Already built:** Options, Options.Deribit, Greeks modules (see inventory above).

### Pure Analytics

| Task | Score | Notes |
|------|-------|-------|
| `Options.GammaWalls.aggregate/3` | [D:2/B:9 → 4.5] 🎯 | Pure GEX aggregation from chain/greeks/OI |
| `Options.atm_iv/2` | [D:2/B:8 → 4.0] 🎯 | ATM implied volatility extraction |
| `Options.pin_risk/3` | [D:2/B:8 → 4.0] 🎯 | High-OI strikes near spot |
| `Options.aggregate_oi/1` | [D:2/B:7 → 3.5] 🎯 | Aggregate OI across expiries |
| `Options.breakeven_move/2` | [D:2/B:7 → 3.5] 🎯 | % move needed to profit |
| `Options.expected_range/3` | [D:2/B:7 → 3.5] 🎯 | 1-sigma move from IV |
| `Options.theta_per_hour/1` | [D:2/B:6 → 3.0] 🎯 | Hourly theta decay rate |
| `Options.Mispricing.scan/3` | [D:3/B:8 → 2.67] 🎯 | Market vs model price comparison |
| `Options.Snapshot.to_report/2` | [D:3/B:7 → 2.33] 🎯 | Chain data to briefing |
| `Options.Pricing.with_drift/3` | [D:4/B:8 → 2.0] 🎯 | Black-Scholes variant with drift term |
| `Options.Surface.build/1` | [D:4/B:7 → 1.75] 🚀 | IV/strike/expiry matrix |
| `Options.Skew.term_structure/1` | [D:4/B:5 → 1.25] 📋 | Skew helpers |
| Implied Probability | [D:4/B:6 → 1.5] 🚀 | Extract market-implied probabilities from option prices via call/put spreads |

### Deribit Convenience (Networked)

Stateless multi-call orchestration composing ccxt_client exchange functions.

| Task | Score | Notes |
|------|-------|-------|
| `Options.Deribit.dvol/1` | [D:1/B:7 → 7.0] 🎯 | Single API call for DVOL index |
| `Options.Deribit.chain/2` | [D:2/B:9 → 4.5] 🎯 | Fetch full options chain |
| `Options.Deribit.block_trades/2` | [D:2/B:6 → 3.0] 🎯 | Institutional flow signal |
| `Options.Deribit.gamma_walls/4` | [D:3/B:9 → 3.0] 🎯 | Networked fetch + GEX assembly |

### 0DTE & Expiry Helpers

| Task | Score | Notes |
|------|-------|-------|
| `ZeroDTE.near_strikes/3` | [D:2/B:7 → 3.5] 🎯 | Strikes near spot for near-expiry |
| `ZeroDTE.theta_acceleration/2` | [D:3/B:7 → 2.33] 🎯 | Theta decay acceleration curve |
| `ZeroDTE.gamma_exposure/2` | [D:4/B:9 → 2.25] 🎯 | GEX for near-expiry options |
| `ZeroDTE.pin_risk/3` | [D:4/B:6 → 1.5] 🚀 | Pin risk for near-expiry |
| `ZeroDTE.roll_to_next/4` | [D:5/B:6 → 1.2] 📋 | `[APP]` Roll position to next expiry (order coordination across fills) |

---

## Funding, Risk & Quantitative Models

**Already built:** Funding, Risk, Basis, Sizing, Volatility, PowerLaw, Portfolio modules (see inventory above).

| Task | Score | Notes |
|------|-------|-------|
| `PowerLaw.fair_value_range/2` | [D:2/B:8 → 4.0] 🎯 | Fair value with confidence intervals |
| `Risk.portfolio_delta/1` | [D:2/B:7 → 3.5] 🎯 | Net delta exposure across positions |
| `Risk.exposure_by_asset/1` | [D:2/B:7 → 3.5] 🎯 | Group positions by asset |
| `Aggregate.funding_rank/2` | [D:2/B:7 → 3.5] 🎯 | Rank symbols by funding rate |
| `Aggregate.bbo/2` | [D:3/B:7 → 2.33] 🎯 | Best bid/offer across exchanges |
| `PowerLaw.forecast/2` | [D:2/B:6 → 3.0] 🎯 | Project fair value to future date |
| `Models.MeanReversion.half_life/1` | [D:2/B:6 → 3.0] 🎯 | Ornstein-Uhlenbeck half-life calc |
| `Funding.trend/2` | [D:3/B:8 → 2.67] 🎯 | Detect funding rate trend |
| `Risk.check_limits/2` (pipeline) | [D:3/B:8 → 2.67] 🎯 | Composable risk limit pipeline (basic exists — extends to pipeline) |
| `Funding.mean_reversion_signal/2` | [D:3/B:7 → 2.33] 🎯 | Z-score on funding distribution |
| `Funding.arb_opportunities/2` | [D:4/B:9 → 2.25] 🎯 | Cross-exchange funding arb detection |
| `Risk.liquidation_watch/2` | [D:4/B:7 → 1.75] 🚀 | Distance to liquidation monitoring |
| `Risk.stress_test/3` | [D:5/B:7 → 1.4] 📋 | Hypothetical move P&L |
| Position Summary | [D:5/B:7 → 1.4] 📋 | Aggregate position view across exchanges (pre-fetched data) |
| Exposure Calculator | [D:5/B:7 → 1.4] 📋 | Total exposure across positions/exchanges (pre-fetched data) |

---

## Execution & Order Management

| Task | Score | Notes |
|------|-------|-------|
| `Execution.best_price/3` | [D:3/B:8 → 2.67] 🎯 | Pure price comparison across exchanges (merge with Best Price Routing below) |
| Best Price Routing | [D:5/B:7 → 1.4] 📋 | Multi-exchange best price selection — overlaps best_price/3, merge when implementing |
| `Execution.split_order/4` | [D:5/B:7 → 1.4] 📋 | Split large order into chunks (pure function) |
| `OrderState.on_fill/2` | [D:3/B:8 → 2.67] 🎯 | Pure immutable order update from fill event |
| `Execution.twap/5` | [D:6/B:6 → 1.0] 📋 | `[APP]` Time-weighted average price execution (timing loop + state machine) |
| `Execution.iceberg/5` | [D:5/B:5 → 1.0] 📋 | `[APP]` Iceberg order logic (hidden order state machine + fill monitoring) |
| `OrderState.history/1` | [D:3/B:6 → 2.0] 🎯 | `[APP]` Order history tracking (ETS/persistence) |
| `OrderState.track/2` | [D:4/B:7 → 1.75] 🚀 | `[APP]` Stateful order tracking (GenServer state machine) |

---

## Market Making

| Task | Score | Notes |
|------|-------|-------|
| `MM.spread_calculator/2` | [D:2/B:7 → 3.5] 🎯 | Optimal spread from volatility/inventory |
| `MM.fair_value/3` | [D:3/B:7 → 2.33] 🎯 | Fair value estimate from orderbook |
| `MM.spread_tracker/3` | [D:4/B:8 → 2.0] 🎯 | Track spread changes over time |
| `MM.inventory_skew/3` | [D:5/B:8 → 1.6] 🚀 | Adjust quotes for inventory |
| `MM.fill_rate/3` | [D:4/B:6 → 1.5] 🚀 | Historical fill rate analysis |
| `MM.quote_manager/4` | [D:6/B:8 → 1.33] 📋 | `[APP]` Quote lifecycle management (place/cancel/update GenServer) |

---

## Orderflow

All pure functions operating on trade maps. `side` and `taker_or_maker` fields exist in the WS trade contract.

| Task | Score | Notes |
|------|-------|-------|
| `Orderflow.cvd_delta/1` | [D:1/B:9 → 9.0] 🎯 | Cumulative volume delta from trades |
| `Orderflow.imbalance/2` | [D:2/B:8 → 4.0] 🎯 | Buy/sell imbalance ratio |
| `Orderflow.vwap/1` | [D:2/B:7 → 3.5] 🎯 | Volume-weighted average price |
| `Orderflow.heatmap_point/2` | [D:2/B:7 → 3.5] 🎯 | Price/volume heatmap data point |
| `Orderflow.footprint_cell/3` | [D:3/B:8 → 2.67] 🎯 | Footprint chart cell data |
| `Orderflow.dom_level/2` | [D:3/B:8 → 2.67] 🎯 | Depth-of-market level construction |

---

## WebSocket Infrastructure

| Task | Score | Notes |
|------|-------|-------|
| `WS.stale_check/2` | [D:1/B:8 → 8.0] 🎯 | Detect stale WS data (pure timestamp comparison) |
| `WS.reconnect_metrics/1` | [D:1/B:6 → 6.0] 🎯 | Reconnection stats (read-only from existing state) |
| `WS.liquidation_monitor/2` | [D:3/B:9 → 3.0] 🎯 | `[APP]` Margin alert system (GenServer + WS subscriptions) |
| `WS.cross_exchange_bbo/3` | [D:4/B:8 → 2.0] 🎯 | `[APP]` Cross-exchange best bid/offer (multi-WS aggregation) |
| `WS.funding_monitor/2` | [D:3/B:6 → 2.0] 🎯 | `[APP]` Real-time funding rate monitor (alert thresholds) |
| `WS.Aggregator` | [D:5/B:9 → 1.8] 🚀 | `[APP]` Multi-exchange WS manager (supervisor tree) |

---

## Market Data Infrastructure

| Task | Score | Notes |
|------|-------|-------|
| `MarketData.Telemetry` | [D:2/B:6 → 3.0] 🎯 | Telemetry event schema definition (metadata, not state) |
| `MarketData.Store` | [D:3/B:9 → 3.0] 🎯 | `[APP]` ETS-backed market data cache |
| `Cache` macro (ETS+TTL+stampede) | [D:4/B:9 → 2.25] 🎯 | `[APP]` Generic cache with TTL and stampede prevention |
| `MarketData.Bootstrapper` | [D:5/B:7 → 1.4] 📋 | `[APP]` Initial data loading on startup |
| `MarketData.SubscriptionRegistry` | [D:4/B:5 → 1.25] 📋 | `[APP]` Track active WS subscriptions |

---

## Timeseries & Recording

| Task | Score | Notes |
|------|-------|-------|
| `Recorder.JSONL` | [D:2/B:8 → 4.0] 🎯 | JSONL file recorder |
| `Recorder.Replay` | [D:3/B:7 → 2.33] 🎯 | Replay recorded data |
| `Recorder.SQLite` | [D:5/B:5 → 1.0] 📋 | SQLite storage backend (optional dep: exqlite) |

---

## Testing

| Task | Score | Notes |
|------|-------|-------|
| Analytics fixtures | [D:2/B:7 → 3.5] 🎯 | Shared test fixtures for trading modules |

---

## Deferred / Speculative

Depend on other infrastructure or need research before implementing.

| Task | Depends On | Notes |
|------|-----------|-------|
| `Options.ProxyRegime.classify/1` | Recorder | Regime classification from recorded data |
| `Options.ExpiryGreeks.diff/2` | Snapshots | Greeks diff between snapshots |
| `DealerPositioning.estimate/2` | — | Probabilistic, assumption-heavy — needs research |
| Orderflow macros (CVD, Footprint, DOM, Heatmap) | Orderflow tasks | Level 2: composable dashboard macros |
| `use Orderflow.Dashboard` | Orderflow macros | Level 3: UI layer |

---

## Summary

| Category | Count |
|----------|-------|
| Pure-function tasks | 63 |
| `[APP]` tasks (stateful) | 14 |
| Deferred | 5 |
| **Total** | **~77** |

86% pure functions. The 14 `[APP]` tasks naturally fit an agent architecture where process state is expected.
