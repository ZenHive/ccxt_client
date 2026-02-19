defmodule CCXT.WS.Patterns.MethodParams do
  @moduledoc """
  Kraken/Crypto.com/Arkham-style WebSocket subscription pattern.

  Message format (Kraken):
  ```json
  {
    "method": "subscribe",
    "params": {
      "channel": "ticker",
      "symbol": ["BTC/USD"]
    }
  }
  ```

  Exchanges: Kraken, Crypto.com, Arkham.
  """
  @behaviour CCXT.WS.Pattern

  alias CCXT.WS.Pattern

  @impl true
  def subscribe(channels, config) when is_list(channels) do
    method_field = config[:op_field] || "method"
    params_field = config[:args_field] || "params"

    %{
      method_field => "subscribe",
      params_field => build_params(channels)
    }
  end

  @impl true
  def unsubscribe(channels, config) when is_list(channels) do
    method_field = config[:op_field] || "method"
    params_field = config[:args_field] || "params"

    %{
      method_field => "unsubscribe",
      params_field => build_params(channels)
    }
  end

  @impl true
  def format_channel(template, params, config) do
    channel_name = template[:channel_name] || ""
    separator = template[:separator] || config[:separator] || "."
    market_id_format = template[:market_id_format] || config[:market_id_format] || :native

    case params[:symbol] do
      nil -> channel_name
      symbol -> channel_name <> separator <> Pattern.format_market_id(symbol, market_id_format, config[:symbol_context])
    end
  end

  @doc false
  defp build_params(channels) do
    %{"channel" => channels}
  end
end
