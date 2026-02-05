defmodule CCXT.WS.Patterns.MethodSubscribe do
  @moduledoc """
  Binance/XT-style WebSocket subscription pattern.

  Message format:
  ```json
  {
    "method": "SUBSCRIBE",
    "params": ["btcusdt@ticker", "btcusdt@depth"]
  }
  ```

  Exchanges: Binance, XT, and similar.
  """
  @behaviour CCXT.WS.Pattern

  alias CCXT.WS.Pattern

  @impl true
  def subscribe(channels, config) when is_list(channels) do
    method_field = config[:op_field] || "method"
    params_field = config[:args_field] || "params"

    %{
      method_field => "SUBSCRIBE",
      params_field => channels
    }
  end

  @impl true
  def unsubscribe(channels, config) when is_list(channels) do
    method_field = config[:op_field] || "method"
    params_field = config[:args_field] || "params"

    %{
      method_field => "UNSUBSCRIBE",
      params_field => channels
    }
  end

  @impl true
  def format_channel(template, params, config) do
    channel_name = template[:channel_name] || ""
    separator = template[:separator] || config[:separator] || "@"
    market_id_format = template[:market_id_format] || config[:market_id_format] || :lowercase

    case params[:symbol] do
      nil -> channel_name
      symbol -> Pattern.format_market_id(symbol, market_id_format) <> separator <> channel_name
    end
  end
end
