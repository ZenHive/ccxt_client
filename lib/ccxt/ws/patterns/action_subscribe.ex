defmodule CCXT.WS.Patterns.ActionSubscribe do
  @moduledoc """
  Alpaca/LBank-style WebSocket subscription pattern.

  Message format:
  ```json
  {
    "action": "subscribe",
    "params": {
      "channels": ["ticker"],
      "symbols": ["BTC/USDT"]
    }
  }
  ```

  Exchanges: Alpaca, LBank.
  """
  @behaviour CCXT.WS.Pattern

  alias CCXT.WS.Pattern

  @impl true
  def subscribe(channels, config) when is_list(channels) do
    action_field = config[:op_field] || "action"
    params_field = config[:args_field] || "params"

    %{
      action_field => "subscribe",
      params_field => build_params(channels, config)
    }
  end

  @impl true
  def unsubscribe(channels, config) when is_list(channels) do
    action_field = config[:op_field] || "action"
    params_field = config[:args_field] || "params"

    %{
      action_field => "unsubscribe",
      params_field => build_params(channels, config)
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
  defp build_params(channels, _config) do
    %{"channels" => channels}
  end
end
