defmodule CCXT.WS.Patterns.OpSubscribe do
  @moduledoc """
  Bybit/Bitmex-style WebSocket subscription pattern.

  Message format:
  ```json
  {
    "op": "subscribe",
    "args": ["tickers.BTCUSDT", "orderbook.50.BTCUSDT"]
  }
  ```

  Exchanges: Bybit, Bitmex, and similar.
  """
  @behaviour CCXT.WS.Pattern

  alias CCXT.WS.Pattern

  @impl true
  def subscribe(channels, config) when is_list(channels) do
    op_field = config[:op_field] || "op"
    args_field = config[:args_field] || "args"

    %{
      op_field => "subscribe",
      args_field => channels
    }
  end

  @impl true
  def unsubscribe(channels, config) when is_list(channels) do
    op_field = config[:op_field] || "op"
    args_field = config[:args_field] || "args"

    %{
      op_field => "unsubscribe",
      args_field => channels
    }
  end

  @impl true
  def format_channel(template, params, config) do
    channel_name = template[:channel_name] || ""
    separator = template[:separator] || config[:separator] || "."
    market_id_format = template[:market_id_format] || config[:market_id_format] || :native

    # Build channel parts: channel_name, timeframe, limit, symbol
    [channel_name]
    |> Pattern.maybe_add_part(params[:timeframe])
    |> Pattern.maybe_add_part(params[:limit], &to_string/1)
    |> Pattern.maybe_add_part(params[:symbol], &Pattern.format_market_id(&1, market_id_format, config[:symbol_context]))
    |> Pattern.build_channel(separator)
  end
end
