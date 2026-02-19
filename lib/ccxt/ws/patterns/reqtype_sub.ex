defmodule CCXT.WS.Patterns.ReqtypeSub do
  @moduledoc """
  BingX-style WebSocket subscription pattern.

  Message format:
  ```json
  {
    "reqType": "sub",
    "dataType": "BTC-USDT@ticker"
  }
  ```

  Exchanges: BingX.
  """
  @behaviour CCXT.WS.Pattern

  alias CCXT.WS.Pattern

  @impl true
  def subscribe(channels, config) when is_list(channels) do
    reqtype_field = config[:op_field] || "reqType"
    datatype_field = config[:args_field] || "dataType"

    channel = List.first(channels) || ""

    %{
      reqtype_field => "sub",
      datatype_field => channel
    }
  end

  @impl true
  def unsubscribe(channels, config) when is_list(channels) do
    reqtype_field = config[:op_field] || "reqType"
    datatype_field = config[:args_field] || "dataType"

    channel = List.first(channels) || ""

    %{
      reqtype_field => "unsub",
      datatype_field => channel
    }
  end

  @impl true
  def format_channel(template, params, config) do
    channel_name = template[:channel_name] || ""
    separator = template[:separator] || config[:separator] || "@"
    market_id_format = template[:market_id_format] || config[:market_id_format] || :native

    case params[:symbol] do
      nil -> channel_name
      symbol -> Pattern.format_market_id(symbol, market_id_format, config[:symbol_context]) <> separator <> channel_name
    end
  end
end
