defmodule CCXT.WS.Patterns.EventSubscribe do
  @moduledoc """
  Gate/Bitfinex/Woo/Bitrue/Hashkey/Toobit-style WebSocket subscription pattern.

  Message format (Gate):
  ```json
  {
    "event": "subscribe",
    "channel": "spot.tickers",
    "payload": ["BTC_USDT"]
  }
  ```

  Message format (Bitfinex):
  ```json
  {
    "event": "subscribe",
    "channel": "ticker",
    "symbol": "tBTCUSD"
  }
  ```

  Exchanges: Gate, Bitfinex, Woo, Bitrue, Hashkey, Toobit.
  """
  @behaviour CCXT.WS.Pattern

  alias CCXT.WS.Pattern

  @impl true
  def subscribe(channels, config) when is_list(channels) do
    event_field = config[:op_field] || "event"
    args_field = config[:args_field] || "payload"

    base = %{event_field => "subscribe"}

    case config[:args_format] do
      :object_list ->
        # Each channel is an object with its own fields
        Map.put(base, args_field, channels)

      :string ->
        # Single channel as string
        Map.put(base, args_field, List.first(channels) || "")

      _ ->
        # Default: array of channel strings
        Map.put(base, args_field, channels)
    end
  end

  @impl true
  def unsubscribe(channels, config) when is_list(channels) do
    event_field = config[:op_field] || "event"
    args_field = config[:args_field] || "payload"

    base = %{event_field => "unsubscribe"}

    case config[:args_format] do
      :object_list ->
        Map.put(base, args_field, channels)

      :string ->
        Map.put(base, args_field, List.first(channels) || "")

      _ ->
        Map.put(base, args_field, channels)
    end
  end

  @impl true
  def format_channel(template, params, config) do
    channel_name = template[:channel_name] || ""
    separator = template[:separator] || config[:separator] || "."
    market_id_format = template[:market_id_format] || config[:market_id_format] || :native

    [channel_name]
    |> Pattern.maybe_add_part(params[:timeframe])
    |> Pattern.maybe_add_part(params[:limit], &to_string/1)
    |> Pattern.maybe_add_part(params[:symbol], &Pattern.format_market_id(&1, market_id_format))
    |> Pattern.build_channel(separator)
  end
end
