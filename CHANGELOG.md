# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

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
