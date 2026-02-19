# Feature Requests (ccxt_client)

Use this file for requested enhancements only.

- Confirmed defects/regressions belong in `BUGS.md`.
- Completed changes move to `CHANGELOG.md`.

> **Upstream tracking:** Features requiring generator/spec changes are tracked in
> [ccxt_ex/ROADMAP.md](../ccxt_ex/ROADMAP.md). Fixes flow downstream via
> `mix ccxt.sync --output --force`.

## Open Requests

### 1) WebSocket Reconnection Hardening and Documentation

Status: In Progress (auth expiry scheduling ported 2026-02-19)
Score: [D:5/B:9 -> Priority:1.8] (High ROI)  
Area: WebSocket (`CCXT.WS.Client`, `CCXT.<Exchange>.WS.Adapter`, docs)

Prompt:
Document and harden WebSocket reconnection behavior for both public and authenticated flows. Clarify when to use `CCXT.WS.Client` vs adapter processes, and verify reconnect-related contracts with deterministic tests.

Success criteria:
- [ ] `llms.txt` has a dedicated reconnection section with client vs adapter decision rules.
- [ ] `README.md` contains a short reconnection guide and points to `llms.txt`.
- [x] WS helper/client tests explicitly validate reconnect configuration and restoration behavior.
- [x] Adapter tests cover generated reconnection-related contract surface.
- [ ] If tests expose generator/spec defects, create a `ccxt_ex` follow-up item with repro details.

Progress notes:
- 2026-02-19: Auth expiry scheduling manually ported to ccxt_client adapter (preserved file).
  `mark_auth_success/3`, `re_auth_success/3`, `schedule_auth_expiry/2` wired with `CCXT.WS.Auth.Expiry`.
  Fixes Deribit WS auth token expiry — tokens now auto-refresh at 80% TTL.
- 2026-02-13: Reconnection tests backported to ccxt_ex and verified via `--output --force` rebuild.
  Tests cover: `restore_subscriptions` config, `reconnect_on_error` flags, mixed channel types,
  adapter AST reconnection handlers (`@reconnect_delay_ms`, `schedule_reconnect`, `handle_info(:reconnect, ...)`).

ccxt_ex escalation trigger:
- If reconnect behavior fails due generated spec/template mismatch, create a follow-up task in `ccxt_ex` with:
  - failing test name
  - expected vs actual behavior
  - suspected generator/spec area

**ccxt_ex:** Tracked as Task 171 (WS Auth State Tracking + Reconnection Docs) [D:5/B:8 -> 1.6]

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
