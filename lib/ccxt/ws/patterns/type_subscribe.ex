defmodule CCXT.WS.Patterns.TypeSubscribe do
  @moduledoc """
  KuCoin/Coinbase/Onetrading-style WebSocket subscription pattern.

  Message format:
  ```json
  {
    "type": "subscribe",
    "topic": "/market/ticker:BTC-USDT"
  }
  ```

  Or with channels array (Coinbase):
  ```json
  {
    "type": "subscribe",
    "channels": ["ticker"]
  }
  ```

  Exchanges: KuCoin, Coinbase, Onetrading.
  """
  @behaviour CCXT.WS.Pattern

  alias CCXT.WS.Pattern

  @impl true
  def subscribe(channels, config) when is_list(channels) do
    type_field = config[:op_field] || "type"
    args_field = config[:args_field] || "topic"
    args_format = config[:args_format] || :string

    base = %{type_field => "subscribe"}

    case args_format do
      :string ->
        # Single topic per message (KuCoin style)
        channel = List.first(channels) || ""
        Map.put(base, args_field, channel)

      _ ->
        # Array of channels (Coinbase style)
        Map.put(base, args_field, channels)
    end
  end

  @impl true
  def unsubscribe(channels, config) when is_list(channels) do
    type_field = config[:op_field] || "type"
    args_field = config[:args_field] || "topic"
    args_format = config[:args_format] || :string

    base = %{type_field => "unsubscribe"}

    case args_format do
      :string ->
        channel = List.first(channels) || ""
        Map.put(base, args_field, channel)

      _ ->
        Map.put(base, args_field, channels)
    end
  end

  @impl true
  def format_channel(template, params, config) do
    channel_name = template[:channel_name] || ""
    separator = template[:separator] || config[:separator] || ":"
    market_id_format = template[:market_id_format] || config[:market_id_format] || :native

    case params[:symbol] do
      nil -> channel_name
      symbol -> channel_name <> separator <> Pattern.format_market_id(symbol, market_id_format)
    end
  end
end
