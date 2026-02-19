# Known Bugs (ccxt_client)

Last verified: February 19, 2026.

> **Upstream tracking:** All bugs below originate in `ccxt_ex` and are tracked in
> [ccxt_ex/ROADMAP.md](../ccxt_ex/ROADMAP.md). Fixes flow downstream via
> `mix ccxt.sync --output --force`.

## 1) Deribit `fetch_trades/1` Missing

- Status: ✅ Fixed upstream (ccxt_ex Task 176)
- Affected module: `CCXT.Deribit`
- Type: API surface inconsistency (docs/examples vs generated module)

### Repro

```elixir
CCXT.Deribit.fetch_trades("BTC-PERPETUAL")
```

Raises:

```elixir
** (UndefinedFunctionError) function CCXT.Deribit.fetch_trades/1 is undefined or private
```

### Observed exported arities

`fetch_trades/2`, `fetch_trades/3`, `fetch_trades/4`

### Notes

- `llms.txt` was updated to use `fetch_trades("BTC-PERPETUAL", nil)`.
- Root fix likely belongs in `ccxt_ex` generation/spec logic if `/1` is intended to exist.
- **ccxt_ex:** Tracked as Task 176 (Generator Optional Param Arity) [D:2/B:8 -> 4.0]

## 2) Deribit WS Balance Subscription Builds Empty Channel

- Status: ✅ Fixed upstream (ccxt_ex Task 177)
- Affected module: `CCXT.Deribit.WS`
- Type: WS channel generation issue

### Repro

```elixir
CCXT.Deribit.WS.watch_balance_subscription()
```

Returns:

```elixir
{:ok,
 %{
   method: :watch_balance,
   channel: "",
   auth_required: true,
   message: %{
     "method" => "public/subscribe",
     "params" => %{"channels" => [""]}
   }
 }}
```

### Notes

- Function exists, but channel is empty (`""`), which is likely invalid for real Deribit private balance subscriptions.
- Most likely a `ccxt_ex` WS extraction/template issue propagated into generated `ccxt_client` code.
- **ccxt_ex:** Tracked as Task 177 (WS Channel Template Param Application) [D:3/B:9 -> 3.0]

## 3) Deribit WS Ticker Subscription Omits Required Interval Suffix

- Status: ✅ Fixed upstream (ccxt_ex Task 177)
- Affected module: `CCXT.Deribit.WS`
- Type: WS channel generation issue

### Repro

```elixir
CCXT.Deribit.WS.watch_ticker_subscription("BTC-PERPETUAL")
```

Returns a subscription channel without interval suffix:

```elixir
{:ok,
 %{
   method: :watch_ticker,
   channel: "ticker.BTC-PERPETUAL",
   auth_required: false,
   message: %{
     "method" => "public/subscribe",
     "params" => %{"channels" => ["ticker.BTC-PERPETUAL"]}
   }
 }}
```

### Observed runtime behavior

- Subscribing to `ticker.BTC-PERPETUAL` returns subscribe ACK only (no ongoing ticker stream).
- Subscribing to `ticker.BTC-PERPETUAL.100ms` returns live `subscription` events with ticker data.

### Notes

- Current generated Deribit ticker channel template includes an `interval` param with default `100ms`, but it is not applied in generated channel output for `watch_ticker_subscription/1`.
- This causes downstream apps to appear connected but receive no live ticker updates unless they manually append the interval suffix.
- Long-term fix path tracked in `FEATURE_REQ.md` item #2: normalized symbol precision/tick metadata for streaming consumers.
- **ccxt_ex:** Tracked as Task 177 (WS Channel Template Param Application) [D:3/B:9 -> 3.0]
