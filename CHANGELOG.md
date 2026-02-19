# Changelog

## [Unreleased]

### Fixed

- **WS Adapter: Auth expiry scheduling** — Ported auth expiry timer logic from ccxt_ex's adapter. `mark_auth_success/3` and `re_auth_success/3` now schedule `Process.send_after(:auth_expired, delay_ms)` via `CCXT.WS.Auth.Expiry` pure functions. Fixes Deribit WS integration test failures where auth tokens would expire without re-authentication.

- **WS Coverage module missing** — `CCXT.WS.Coverage` was not being copied during sync. Fixed upstream in ccxt_ex's PackageBuilder.

- **KuCoin `fetch_markets` 404** — Ported version-override clause in `build_prefixed_path_ast` from ccxt_ex Task 204. KuCoin's `/v2/symbols` path was being prefixed with `/api/v1/` instead of `/api/v2/`, causing 16 endpoints to 404.

## v0.1.0 — Initial Release

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
