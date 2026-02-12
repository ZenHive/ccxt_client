# Known Bugs (ccxt_client)

Last verified: February 12, 2026 (via Tidewave MCP in this repo).

## 1) Deribit `fetch_trades/1` Missing

- Status: Open
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

## 2) Deribit WS Balance Subscription Builds Empty Channel

- Status: Open
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
