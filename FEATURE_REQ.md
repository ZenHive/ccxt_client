# Feature Requests (ccxt_client)

Use this file for requested enhancements only.

- Confirmed defects/regressions belong in `BUGS.md`.
- Completed changes move to `CHANGELOG.md`.

> **Upstream tracking:** Features requiring generator/spec changes are tracked in
> [ccxt_ex/ROADMAP.md](../ccxt_ex/ROADMAP.md). Fixes flow downstream via
> `mix ccxt.sync --output --force`.

## Open Requests

### ~~1) WebSocket Reconnection Hardening and Documentation~~ ✅ Complete

Status: ✅ Complete (2026-02-20) — See [CHANGELOG.md](CHANGELOG.md)
Score: [D:5/B:9 -> Priority:1.8] (High ROI)
Area: WebSocket (`CCXT.WS.Client`, `CCXT.<Exchange>.WS.Adapter`, docs)

All success criteria met. llms.txt section 12, README WS guide, 15 behavioral tests, auth expiry scheduling.

**ccxt_ex:** Tracked as Task 171 (WS Auth State Tracking + Reconnection Docs)

### 2) Normalized Symbol Precision/Tick Metadata for Streaming Consumers

Status: Pending  
Score: [D:4/B:8 -> Priority:2.0] (High ROI)  
Area: Market metadata normalization (`fetch_markets`, typed market schema, WS consumers)

Prompt:
Expose a normalized, symbol-addressable precision contract suitable for live consumers (charts, order forms, validators), so clients do not infer display/step precision from ticks. Include at least `price_increment` (or equivalent), `price_precision`, and `amount_precision` with clear semantics across spot/swap/future/option markets.

Success criteria:
- [ ] Public API provides per-symbol normalized precision metadata without requiring consumers to parse raw exchange payloads.
- [ ] Contract defines exact meaning for `price_increment` vs decimal precision and how they map to exchanges with different precision modes.
- [ ] Deribit (and at least one non-Deribit exchange) has tests proving normalized outputs are stable and symbol-correct.
- [ ] Docs include migration guidance for consumers currently reading `__ccxt_spec__`/raw market data.
- [ ] Backward compatibility is preserved for existing `fetch_markets` callers (or migration path is clearly versioned).

Notes:
- Motivation came from a live TradingView/lightweight-charts integration where chart `priceFormat` should be symbol-aware.
- Today, streaming ticker payloads do not carry precision metadata, so consumers need a stable companion metadata API.

**ccxt_ex:** Tracked as Task 178 (Normalized Market Precision Metadata) [D:4/B:8 -> 2.0]
