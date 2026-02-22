# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## Phase 5: Health & Monitoring

### CCXT.Health Module
**Completed** | `Health.latency/1` [D:1/B:7 → 7.0], `Health.ping/1` [D:2/B:8 → 4.0], `Health.all/1` [D:3/B:8 → 2.67], `Health.status/2` [D:3/B:7 → 2.33]

**What was done:**
- `CCXT.Health` module at `lib/ccxt/health.ex` — stateless, one-shot exchange health checks
- `ping/1` — checks exchange reachability via `fetch_time/1`, returns `:ok` or `{:error, Error.t()}`
- `latency/1` — wall-clock round-trip measurement in milliseconds (float), wraps `fetch_time/1` with `System.monotonic_time()`
- `all/1` — concurrent bulk health check via `Task.async_stream/3` with `on_timeout: :kill_task`, returns `%{exchange => :ok | {:error, term()}}`
- `status/2` — composite snapshot combining reachability, latency, and `CircuitBreaker.status/1`
- Private `resolve_module/1` validates exchange atom → module with `__ccxt_spec__/0` check
- 11 tests (6 unit, 5 integration) covering error paths, concurrency, and real exchange calls

**Design decisions:**
- Wall-clock measurement around `fetch_time` (not Finch telemetry) — simpler, gives total round-trip including signing and rate-limit wait
- No struct for status result — plain map keeps the API simple and extensible
- `resolve_module/1` checks `__ccxt_spec__/0` export to distinguish real exchange modules from other `CCXT.*` modules

---

## Task 225: Normalization QA Sweep (2026-02-22)

**Completed** | [D:5/B:10 → Priority:2.0]

**What was done:**
- **Normalization contract tests** (`test/ccxt/normalization_contract_test.exs`) — 54 tests covering 5 tier1 exchanges × 3 endpoints (ticker, trade, order) + 2 order book tests (Bybit with parser mapping, baseline without)
- **Parser coverage tests** (`test/ccxt/parser_coverage_test.exs`) — 20 tests: tier1 hard assertions, cross-validation (method_schemas ⊆ type_modules), coverage inventory, known exceptions
- **Contract assertions**: numeric fields are `number() | nil` (never strings), enum fields (`side`, `status`, `taker_or_maker`) are atoms (never strings/booleans), `timestamp` is `integer() | nil`, `raw` is always a map
- **List-shape contracts**: `:trades` and `:orders` coerce lists of raw maps to `[%Trade{}]` and `[%Order{}]`
- **Exchange-specific coercion tests**: Binance bool→side, Bybit isMaker→taker_or_maker, Deribit liquidity→taker_or_maker, string_lower normalization, string timestamp→integer
- **Known exceptions documented**: `:order_book` (unified keys), `:balance` (nested maps)

**Triage result:** No bugs found — pipeline works correctly for all tier1 exchanges.

**Coverage snapshot:** Binance/Bybit 76.7%, OKX/Gate 63.3%, Htx 53.3%, Deribit 43.3%, Kucoin 40%, Bitmex 36.7%, Kraken 26.7%, Coinbase 20%

**Run with:** `mix test.json --quiet --only normalization` and `mix test.json --quiet test/ccxt/parser_coverage_test.exs`

---

## Fix: OrderBook levels return strings instead of floats (2026-02-21)

**What was done:**
- **Level coercion** — `OrderBook.from_map/1` now coerces string bid/ask level values to floats via `Safe.to_number/1`. Previously, `fetch_order_book(normalize: true)` returned `[["67795.8", "1.636265"]]` instead of `[[67795.8, 1.636265]]`. Root cause: MappingCompiler's `type_to_coercion/1` fell through to `:value` (passthrough) for `[[number() | nil]]` schema type.
- **Raw field fix** — `book.raw` now uses precedence chain `raw || info || map` instead of always falling back to the enriched parsed map. Preserves original exchange payload.
- **Test update** — WS normalizer test updated to assert coerced floats instead of raw strings.

**Related to:** Task 225 (Normalization QA Sweep) — proactive fix before sweep

---

## Pipeline default for deps + maybe_coerce warning (2026-02-21)

**What was done:**
- **Pipeline default hardcoded** — `CCXT.Pipeline` module provides single source of truth for default pipeline config. Both REST (`CCXT.Generator`) and WS (`CCXT.WS.Generator`) generators use `CCXT.Pipeline.default()` as fallback instead of `[]`. Fixes normalization not working when ccxt_client is compiled as a path dependency (dep config files not loaded by parent app).
- **maybe_coerce warning** — `maybe_coerce/5` nil-coercer path now logs actionable warning with `response_type` when `normalize: true` (the default) is active but no coercer is configured.

**Verified:** 2649 tests, 0 failures (398 excluded)

---

## Task 224: Normalization — boolean_derivation, safe_fn, info injection (2026-02-21)

**What was done:**
- **MappingCompiler: `boolean_derivation` category** — Compiles P1 `boolean_derivation` entries to `{:bool_enum, true_value, false_value}` tagged tuple coercion (34 occurrences across exchanges, e.g., Binance `side` from `"m"` boolean)
- **MappingCompiler: `safe_fn` override** — `resolved_safe_accessor` entries with `safe_fn` field now override schema-derived coercion (e.g., Bybit `side` → `:string_lower`, `timestamp` → `:integer`)
- **ResponseParser: `{:bool_enum, tv, fv}` coercion** — New `apply_coercion/3` clause with dedicated `find_boolean/2` that correctly handles `false` as a found value (unlike `Safe.value` which treats `false` as falsy)
- **ResponseCoercer: info injection** — `coerce_single/3` injects `"info" => data` before parsing so `from_map`'s `:raw`/`:info` field gets populated. Doesn't overwrite existing `"info"` or `:info` keys
- **Helpers: capitalized side normalization** — Added `"Buy"`, `"Sell"`, `"Long"`, `"Short"` clauses to `normalize_side/1`
- **Typespecs** — Widened instruction type across 7 locations to accept tagged tuple coercion

**ccxt_ex:** Linked to Tasks 221-223 (P1 analysis improvements)

**Verified:** 2645 tests, 0 failures (398 excluded)

---

## v0.2.1 — Full Exchange Sync (2026-02-21)

**107 exchanges** now bundled (up from 10 tier1/tier2). Synced from CCXT v4.5.39.

- Full exchange sync: 97 new exchange modules, specs, and test files (433 files total)
- New WS methods: `watch_position_for_symbols`, `watch_private_multiple`, `watch_public`, `watch_multiple`, `watch_public_multiple`
- Updated extractor data: symbol formats, emulated methods, error codes, parse methods
- Fixed version references in README.md and llms.txt (`~> 0.1` → `~> 0.2`)
- Moved `TRADING_BACKLOG.md` to quantex as `ROADMAP.md`

**Verified:** 6650 tests, 3852 passed, 0 code failures (all failures credential-related)

---

## v0.2.0 — Trading Modules Removed (Breaking)

**Breaking:** `CCXT.Trading.*` modules (Funding, Greeks, Risk, Basis, Sizing,
Volatility, Options, Portfolio, PowerLaw, and helpers) have been removed.
These trading analytics have been extracted to a separate library.

ccxt_client is now a focused exchange-access library — HTTP, WebSocket,
signing, symbol normalization, and types only.

No changes to exchange API functionality.

---

## Spec Cost Sync + Test Improvement (2026-02-20)

**What was done:**
- **Spec cost/weight sync:** Updated rate limit costs across all 10 Tier 1 exchange specs (binance, bitmex, bybit, coinbaseexchange, deribit, gate, htx, kraken, kucoin, okx) from upstream CCXT
- **Test improvement:** `test_since_value/2` in `PublicEndpointsTest` now derives `since` requirements from endpoint spec metadata (`required_params`, `param_mappings`, path patterns) instead of hardcoding exchange IDs — resolves inline TODO

**Verified:** 3380 tests, 0 code failures (15 failures + 178 invalid all credential-related)

---

## ccxt_ex Sync (2026-02-20)

**What was synced:**
- **Bug #1 resolved:** `CCXT.Deribit.fetch_trades/1` now exists (optional param arity fix, Task 176)
- **Bug #2 resolved:** Deribit WS balance subscription builds correct channel (Task 177)
- **Bug #3 resolved:** Deribit WS ticker subscription includes interval suffix (Task 177)
- **Adapter refactor:** Monolithic generator functions decomposed into focused sub-generators (`_ast` naming convention)
- **Deribit spec updates:** `response_transformer` added to ~12 endpoints, `auth_required: true` on all private WS channel templates, updated symbol format samples, `api_sections` map
- **Generator updates:** Pipeline-based coercer/parser decoupling, version-override path prefix handling, dynamic app name resolution

**Verified:** 3380 tests, 0 code failures (15 failures + 178 invalid all credential-related)

---

## Phase 1: Response Quality & Documentation

### Feature #2: Symbol Precision Metadata
**Completed** | [D:4/B:8 → Priority:2.0]

**What was done:**
- `CCXT.MarketPrecision` module at `lib/ccxt/market_precision.ex`
- `from_market/2` — builds precision struct from a single market map
- `from_markets/2` — builds precision map for all symbols on an exchange
- `tradingview_price_format/1` — TradingView-compatible price format
- `decimal_places/1`, `increment_from_decimals/1` — precision mode conversions
- Handles all 3 CCXT precision modes: TICK_SIZE, DECIMALS, SIGNIFICANT_DIGITS

**Linked to:** ccxt_ex Task 178 (Normalized Market Precision Metadata)

---

## Pre-existing (included in v0.1.1)

The following roadmap items were found to already exist in the initial release:

- **`Symbol.normalize/2` + `Symbol.denormalize/2`** (Phase 17) — `CCXT.Symbol` provides bidirectional normalization
- **`Symbol.to_exchange_id/3` + `Symbol.from_exchange_id/3`** (Phase 17) — pattern-based exchange format conversion
- **`RateLimit` visibility** (Phase 20) — `CCXT.HTTP.RateLimiter` provides per-credential sliding window rate tracking

---

## v0.1.1 — Initial Release

- Elixir client for 110+ cryptocurrency exchanges
- 7 signing patterns covering 95%+ of exchanges
- Unified API: fetch_ticker, fetch_order_book, create_order, fetch_balance, etc.
- WebSocket support with automatic reconnection
- Type-safe response structs (Ticker, Order, Balance, Position, etc.)
- Bidirectional symbol normalization (unified ↔ exchange format)
- Circuit breaker and rate limiting
- Selective compilation (configure which exchanges to compile)

Generated from [ccxt_ex](https://github.com/ZenHive/ccxt_ex), extracted from
CCXT's 7+ years of accumulated exchange knowledge.
