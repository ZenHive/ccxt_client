# Changelog

## Unreleased

- docs: fixed Deribit trades usage in `llms.txt` to call `CCXT.Deribit.fetch_trades/2` (`"BTC-PERPETUAL", nil`) instead of missing `/1`
- docs: added `BUGS.md` with Tidewave-verified issues:
  - `CCXT.Deribit.fetch_trades/1` missing
  - `CCXT.Deribit.WS.watch_balance_subscription/0` building an empty channel (`""`)

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
