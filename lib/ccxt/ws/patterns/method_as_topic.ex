defmodule CCXT.WS.Patterns.MethodAsTopic do
  @moduledoc """
  Coinex/Phemex-style WebSocket subscription pattern.

  The method field itself IS the channel name.

  Message format:
  ```json
  {
    "method": "ticker.subscribe",
    "params": ["BTCUSDT"],
    "id": 1
  }
  ```

  Exchanges: Coinex, Phemex.
  """
  @behaviour CCXT.WS.Pattern

  alias CCXT.WS.Pattern

  @impl true
  def subscribe(channels, config) when is_list(channels) do
    # For this pattern, we expect channels to be the full method names
    # e.g., ["ticker.subscribe", "depth.subscribe"]
    method_field = config[:op_field] || "method"
    params_field = config[:args_field] || "params"

    # Take the first channel as the method
    method = List.first(channels) || "subscribe"

    %{
      method_field => method,
      params_field => [],
      "id" => generate_id()
    }
  end

  @impl true
  def unsubscribe(channels, config) when is_list(channels) do
    method_field = config[:op_field] || "method"
    params_field = config[:args_field] || "params"

    # Convert subscribe to unsubscribe in method name
    method =
      channels
      |> List.first()
      |> to_string()
      |> String.replace(".subscribe", ".unsubscribe")

    %{
      method_field => method,
      params_field => [],
      "id" => generate_id()
    }
  end

  @impl true
  def format_channel(template, params, config) do
    channel_name = template[:channel_name] || ""
    separator = template[:separator] || config[:separator] || "."
    market_id_format = template[:market_id_format] || config[:market_id_format] || :native

    # For method_as_topic, the channel becomes the method name
    base = channel_name <> ".subscribe"

    case params[:symbol] do
      nil -> base
      symbol -> base <> separator <> Pattern.format_market_id(symbol, market_id_format, config[:symbol_context])
    end
  end

  @doc false
  defp generate_id do
    System.unique_integer([:positive, :monotonic])
  end
end
