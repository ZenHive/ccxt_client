# ccxt_client Roadmap

**Vision:** A lean, consumer-facing Elixir library for 100+ cryptocurrency exchanges — unified API, rich types, and excellent developer experience.

**Parent project:** Extraction and generation happen in [ccxt_ex](../ccxt_ex/ROADMAP.md). Fixes flow downstream via `mix ccxt.sync --output --force`.

**Trading features:** Analytics, orderflow, execution, and other trading features are being extracted to **quantex** (`../quantex`). See [TRADING_BACKLOG.md](TRADING_BACKLOG.md) for the full inventory (~77 tasks, ~85 already-built functions).

**Completed work:** See [CHANGELOG.md](CHANGELOG.md) for finished tasks.

---

## 🎯 Current Focus

**Quantex Extraction** — Extract trading modules to standalone `quantex` library.

> **Philosophy reminder:** ccxt_client owns exchange access DX. If it helps the user talk to exchanges (not analyze trades), it belongs here. Trading analytics belong in quantex.

### ✅ Recently Completed

| Task | Description | Notes |
|------|-------------|-------|
| ccxt_ex Sync | Synced upstream fixes + adapter refactor | 3 bugs resolved, response_transformers, auth_required flags, adapter decomposition |
| Feature #2: Symbol Precision Metadata | `CCXT.MarketPrecision` module | `from_market/2`, `from_markets/2`, `tradingview_price_format/1`, 3 precision modes |
| WS Reconnection Tests | Reconnect config + subscription restoration tests | 15 behavioral tests, auth expiry scheduling |
| Auth Expiry Scheduling | Deribit WS token auto-refresh at 80% TTL | Manually ported to preserved adapter file |
| Quantex Task 1: Create project | `mix new quantex --sup`, standard deps, CLAUDE.md | Tidewave on 4002, ccxt_client test dep |
| Quantex Task 2: Move source + tests | 13 source files, 17 test files → quantex | Struct→map decoupling, 355 tests passing |

### 📋 Current Tasks

| Task | Status | Notes |
|------|--------|-------|
| Feature #1: WS Reconnection Docs | ✅ | Complete — llms.txt section 12, README WS guide, 15 behavioral tests |
| Extract Trading Modules to quantex | 🔄 | Tasks 1-3 complete, Task 4-5 pending — see Extraction section below |

### Quick Commands

```bash
mix test.json --quiet                              # Unit tests (excludes :integration)
mix test.json --quiet --failed --first-failure     # Iterate on failures
mix test.json --quiet --only integration --only tier1  # Tier 1 integration
mix dialyzer.json --quiet                          # Type checking
```

---

## ~~Pending Sync from ccxt_ex~~ ✅ Synced 2026-02-20

All 3 bugs synced and verified. See [BUGS.md](BUGS.md) for details. Also included: adapter structural refactor, response_transformers on ~12 Deribit endpoints, `auth_required` flags on all private WS channel templates, updated symbol format samples.

---

## Extraction: Remove Trading Modules → quantex

Before publishing v0.2.0, extract `CCXT.Trading.*` (13 source files, 17 test files, ~85 functions) to **quantex** — a standalone trading analytics library. See [TRADING_BACKLOG.md](TRADING_BACKLOG.md) for the full feature inventory.

### Decisions

- **Name**: `quantex` (app `:quantex`, module prefix `Quantex.*`)
- **Location**: `../quantex` (sibling to ccxt_client)
- **Type coupling**: Plain maps for all inputs — no dependency on ccxt_client types. CCXT structs are maps so they work as-is (zero friction for CCXT users, zero coupling for non-CCXT users).
- **Output types**: No output structs in initial extraction. May add `Quantex.Greeks.Result` etc. later as needed.
- **Integration tests**: Move to quantex with `{:ccxt_client, path: "../ccxt_client", only: :test}`. Keeps test coverage intact.
- **Runtime deps**: Zero Hex deps. Only OTP `:math`.

### Extraction inventory

- 13 source files in `lib/ccxt/trading/` → `lib/quantex/`
- 17 test files in `test/ccxt/trading/` → `test/quantex/`
- 3 CCXT type references (`FundingRate`, `Option`, `Position`) → refactor to plain map pattern matches
- 4 integration tests call real exchange endpoints → need ccxt_client as test-only dep
- Zero non-trading modules reference `CCXT.Trading.*` — clean removal

### Tasks

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| 1. Create quantex project | ✅ | [D:3/B:9 → 3.0] 🎯 | Standard deps + sobelow, tidewave on 4002, git initialized |
| 2. Move source + tests | ✅ | [D:2/B:9 → 4.5] 🎯 | 13 source, 17 tests, struct→map decoupling, 355 tests passing |
| 3. Rename CCXT.Trading → Quantex | ✅ | [D:2/B:7 → 3.5] 🎯 | Decided: `Quantex.*`, plain maps, no ccxt_client dep |
| 4. Update ccxt_client docs | ⬜ | [D:2/B:7 → 3.5] 🎯 | README, CLAUDE.md, llms.txt, TRADING_BACKLOG.md |
| 5. Publish v0.2.0 | ⬜ | [D:2/B:8 → 4.0] 🎯 | Clean exchange-access library |

### Task details

**1. Create quantex project.** Run `mix new quantex --sup` at `../quantex`. Set up standard deps (ex_unit_json, dialyzer_json, styler, credo, dialyxir, ex_doc, doctor). Add `{:ccxt_client, path: "../ccxt_client", only: :test}` for integration tests. Create CLAUDE.md with project context. No runtime deps beyond OTP `:math`.

**2. Move source + tests.** Copy 13 files from `lib/ccxt/trading/` and 17 files from `test/ccxt/trading/` to quantex. Rename module prefix `CCXT.Trading` → `Quantex` across all files. Replace any `CCXT.Types.FundingRate`, `CCXT.Types.Option`, `CCXT.Types.Position` references with plain map pattern matches (e.g., `%{funding_rate: rate}` instead of `%FundingRate{funding_rate: rate}`). Verify `mix test.json --quiet` passes in quantex and `mix compile` still works in ccxt_client.

**3. Rename CCXT.Trading → Quantex.** ✅ Decided — namespace is `Quantex.*`, inputs are plain maps, no ccxt_client runtime dependency.

**4. Update ccxt_client docs.** Remove Trading Modules section from ccxt_client README, CLAUDE.md, and llms.txt. Update TRADING_BACKLOG.md header to reference quantex as the new home. Add a note in ccxt_client README pointing users to quantex for trading analytics.

**5. Publish v0.2.0.** After extraction, ccxt_client is a clean exchange-access library. Remove `lib/ccxt/trading/` and `test/ccxt/trading/` directories. Verify `mix test.json --quiet` passes, `mix dialyzer.json --quiet` is clean. Tag v0.2.0.

---

## Phase 1: Response Quality & Documentation

Consumer-facing documentation and metadata enrichment.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| Feature #1: WS Reconnection Docs | ✅ | [D:5/B:9 → 1.8] 🚀 | Complete — see CHANGELOG.md |
| Feature #2: Symbol Precision Metadata | ✅ | [D:4/B:8 → 2.0] 🎯 | `CCXT.MarketPrecision` — see CHANGELOG.md |

### Feature #1: WS Reconnection Docs

[D:5/B:9 → Priority:1.8] 🚀

Document and harden WebSocket reconnection behavior for both public and authenticated flows. Clarify when to use `CCXT.WS.Client` vs adapter processes, and verify reconnect-related contracts with deterministic tests.

Success criteria:
- [x] WS helper/client tests explicitly validate reconnect configuration and restoration behavior
- [x] Adapter tests cover generated reconnection-related contract surface
- [x] `llms.txt` has a dedicated reconnection section with client vs adapter decision rules (section 12, line 325)
- [x] `README.md` contains a short reconnection guide and points to `llms.txt`
- [x] If tests expose generator/spec defects, create a `ccxt_ex` follow-up item with repro details

Progress notes:
- 2026-02-20: README WebSocket Streaming section added. All 5 success criteria met. Feature complete.
- 2026-02-19: Auth expiry scheduling manually ported to ccxt_client adapter (preserved file).
- 2026-02-13: Reconnection tests backported to ccxt_ex and verified via `--output --force` rebuild.

**ccxt_ex:** Linked to Task 171 (WS Auth State Tracking + Reconnection Docs)

---

## Phase 2: Exchange DX

Exchange-level validation and fee utilities.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| Task 125: Order Sanity Checks | ⬜ | [D:4/B:8 → 2.0] 🎯 | Pre-submit validation for orders |
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

## Phase 5: Health & Monitoring

Exchange health checks and latency monitoring. One-shot stateless checks, not dashboards.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `Health.latency/1` | ⬜ | [D:1/B:7 → 7.0] 🎯 | Finch telemetry wrapper for latency |
| `Health.ping/1` | ⬜ | [D:2/B:8 → 4.0] 🎯 | Exchange alive check |
| `Health.all/1` | ⬜ | [D:3/B:8 → 2.67] 🎯 | Bulk health check across exchanges |
| `Health.status/2` | ⬜ | [D:3/B:7 → 2.33] 🎯 | Composite status with degradation |

---

## Phase 6: Symbol & Instrument Normalization

Deeper symbol normalization beyond what Phase 4 covers.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `Instrument` struct | ⬜ | [D:3/B:8 → 2.67] 🎯 | Rich instrument type (symbol + metadata) |
| `Symbol.normalize/2` | ✅ | [D:4/B:7 → 1.75] 🚀 | `CCXT.Symbol.normalize/2` + `denormalize/2` exist |
| `Symbol.to_exchange/3` | ✅ | [D:4/B:7 → 1.75] 🚀 | `CCXT.Symbol.to_exchange_id/3` + `from_exchange_id/3` exist |

---

## Phase 7: Testing & Dev Tools

Tools to make testing and development with ccxt_client easier.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| One-liner setup docs | ⬜ | [D:2/B:6 → 3.0] 🎯 | Quickstart guide improvements |
| `WS.Debug.capture_subscription/3` | ⬜ | [D:3/B:7 → 2.33] 🎯 | Capture WS subscription for debugging |
| `Snapshot.capture/2` | ⬜ | [D:3/B:6 → 2.0] 🎯 | Capture exchange state snapshot |
| `Mock.stub_exchange/2` | ⬜ | [D:4/B:7 → 1.75] 🚀 | Mock exchange for testing |

---

## Phase 8: Distribution & Extensibility

Allow consumers to extend ccxt_client with custom exchanges or override specs.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| Custom spec loading | ⬜ | [D:3/B:8 → 2.67] 🎯 | Load specs from consumer's priv directory |
| CCXT as optional update source | ⬜ | [D:5/B:7 → 1.4] 📋 | Pull spec updates without ccxt_ex |
| Spec registry | ⬜ | [D:6/B:7 → 1.17] 📋 | Registry for spec discovery/management |

---

## Phase 9: Reliability & Ops

Production reliability improvements.

| Task | Status | Score | Notes |
|------|--------|-------|-------|
| `Policy` (retry/backoff) | ⬜ | [D:3/B:8 → 2.67] 🎯 | Configurable retry/backoff policies |
| `RateLimit` visibility | ✅ | [D:3/B:6 → 2.0] 🎯 | `CCXT.HTTP.RateLimiter` — per-credential sliding window, state accessible |

---

## Priority Order (by ROI)

| # | Item | Score | Phase |
|---|------|-------|-------|
| 1 | `Health.latency/1` | [D:1/B:7 → 7.0] 🎯 | 5 |
| 2 | `Health.ping/1` | [D:2/B:8 → 4.0] 🎯 | 5 |
| 3 | One-liner setup docs | [D:2/B:6 → 3.0] 🎯 | 7 |
| 4 | `Health.all/1` | [D:3/B:8 → 2.67] 🎯 | 5 |
| 5 | `Instrument` struct | [D:3/B:8 → 2.67] 🎯 | 6 |
| 6 | Custom spec loading | [D:3/B:8 → 2.67] 🎯 | 8 |
| 7 | `Policy` (retry/backoff) | [D:3/B:8 → 2.67] 🎯 | 9 |
| 8 | `Health.status/2` | [D:3/B:7 → 2.33] 🎯 | 5 |
| 9 | `WS.Debug.capture_subscription/3` | [D:3/B:7 → 2.33] 🎯 | 7 |
| 10 | Task 125: Order Sanity Checks | [D:4/B:8 → 2.0] 🎯 | 2 |
| 11 | `Snapshot.capture/2` | [D:3/B:6 → 2.0] 🎯 | 7 |
| 12 | Feature #1: WS Reconnection Docs | [D:5/B:9 → 1.8] 🚀 | 1 |
| 13 | Task 78: Convenience Methods | [D:4/B:7 → 1.75] 🚀 | 3 |
| 14 | `Mock.stub_exchange/2` | [D:4/B:7 → 1.75] 🚀 | 7 |
| 15 | Task 99: Fee Calculation Logic | [D:4/B:6 → 1.5] 🚀 | 2 |
| 16 | Task 131: Examples in Introspection | [D:5/B:7 → 1.4] 📋 | 3 |
| 17 | CCXT as optional update source | [D:5/B:7 → 1.4] 📋 | 8 |
| 18 | Task 162: Pagination Helpers | [D:6/B:7 → 1.2] 📋 | 3 |
| 19 | Task 139: Nullable Field Indicators | [D:5/B:6 → 1.2] 📋 | 3 |
| 20 | Spec registry | [D:6/B:7 → 1.17] 📋 | 8 |
| 21 | Task 170d: Missing Schema Types | [D:5/B:5 → 1.0] 📋 | 4 |
| 22 | Task 175e: Broad Normalization Phase 2 | [D:6/B:6 → 1.0] 📋 | 4 |
| 23 | Task 132: Exchange Quirks | [D:6/B:6 → 1.0] 📋 | 3 |

Note: Quantex extraction tasks not listed — they're a prerequisite meta-task for v0.2.0. See "Extraction" section above.

---

## Roadmap Maintenance

When completing a task:
1. Move full task details to `CHANGELOG.md`
2. Update summary table status (⬜ → ✅)
3. Keep only a one-line reference in this file
4. Strike through in priority order list

**Cross-repo coordination:** Tasks requiring generator/spec changes are tracked in [ccxt_ex/ROADMAP.md](../ccxt_ex/ROADMAP.md). Consumer-facing work stays here. When a task spans both repos, use the same task ID/title in both files.

**Trading features:** Analytics, orderflow, execution, and other trading tasks are tracked in [TRADING_BACKLOG.md](TRADING_BACKLOG.md). When quantex extraction is complete, that file moves to `../quantex`.
