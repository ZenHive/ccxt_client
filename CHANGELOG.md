# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

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
