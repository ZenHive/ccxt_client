defmodule CCXT.WS.Patterns.MethodTopics do
  @moduledoc """
  Exmo-style WebSocket subscription pattern.

  Message format:
  ```json
  {
    "method": "subscribe",
    "topics": ["spot/ticker:BTC_USDT", "spot/depth:BTC_USDT"]
  }
  ```

  Exchanges: Exmo.
  """
  @behaviour CCXT.WS.Pattern

  alias CCXT.WS.Pattern

  @impl true
  def subscribe(channels, config) when is_list(channels) do
    method_field = config[:op_field] || "method"
    topics_field = config[:args_field] || "topics"

    %{
      method_field => "subscribe",
      topics_field => channels
    }
  end

  @impl true
  def unsubscribe(channels, config) when is_list(channels) do
    method_field = config[:op_field] || "method"
    topics_field = config[:args_field] || "topics"

    %{
      method_field => "unsubscribe",
      topics_field => channels
    }
  end

  @impl true
  def format_channel(template, params, config) do
    channel_name = template[:channel_name] || ""
    separator = template[:separator] || config[:separator] || ":"
    market_id_format = template[:market_id_format] || config[:market_id_format] || :native

    case params[:symbol] do
      nil -> channel_name
      symbol -> channel_name <> separator <> Pattern.format_market_id(symbol, market_id_format, config[:symbol_context])
    end
  end
end
