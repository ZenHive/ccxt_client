defmodule CCXT.WS.Patterns.OpSubscribeObjects do
  @moduledoc """
  OKX-style WebSocket subscription pattern with object arguments.

  Message format:
  ```json
  {
    "op": "subscribe",
    "args": [
      {"channel": "tickers", "instId": "BTC-USDT"},
      {"channel": "books", "instId": "BTC-USDT"}
    ]
  }
  ```

  Exchanges: OKX.
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
    # For OKX, channels are objects, not strings
    # Returns a map that will be put in the args array
    channel_name = template[:channel_name] || ""

    base = %{"channel" => channel_name}

    case params[:symbol] do
      nil -> base
      symbol -> Map.put(base, "instId", Pattern.format_market_id(symbol, :native, config[:symbol_context]))
    end
  end
end
