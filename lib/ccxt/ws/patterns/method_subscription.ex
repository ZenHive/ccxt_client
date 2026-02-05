defmodule CCXT.WS.Patterns.MethodSubscription do
  @moduledoc """
  Hyperliquid-style WebSocket subscription pattern.

  Message format:
  ```json
  {
    "method": "subscribe",
    "subscription": {
      "type": "allMids"
    }
  }
  ```

  Exchanges: Hyperliquid.
  """
  @behaviour CCXT.WS.Pattern

  alias CCXT.WS.Pattern

  @impl true
  def subscribe(channels, config) when is_list(channels) do
    method_field = config[:op_field] || "method"
    subscription_field = config[:args_field] || "subscription"

    %{
      method_field => "subscribe",
      subscription_field => build_subscription(channels)
    }
  end

  @impl true
  def unsubscribe(channels, config) when is_list(channels) do
    method_field = config[:op_field] || "method"
    subscription_field = config[:args_field] || "subscription"

    %{
      method_field => "unsubscribe",
      subscription_field => build_subscription(channels)
    }
  end

  @impl true
  def format_channel(template, params, config) do
    channel_name = template[:channel_name] || ""
    separator = template[:separator] || config[:separator] || "."
    market_id_format = template[:market_id_format] || config[:market_id_format] || :native

    case params[:symbol] do
      nil -> channel_name
      symbol -> channel_name <> separator <> Pattern.format_market_id(symbol, market_id_format)
    end
  end

  @doc false
  defp build_subscription(channels) do
    %{"type" => List.first(channels) || ""}
  end
end
