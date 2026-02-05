defmodule CCXT.WS.Patterns.JsonRpc do
  @moduledoc """
  Deribit-style JSON-RPC 2.0 WebSocket subscription pattern.

  Message format:
  ```json
  {
    "jsonrpc": "2.0",
    "method": "public/subscribe",
    "params": {
      "channels": ["ticker.BTC-PERPETUAL", "book.BTC-PERPETUAL.100ms"]
    },
    "id": 1
  }
  ```

  Exchanges: Deribit.
  """
  @behaviour CCXT.WS.Pattern

  alias CCXT.WS.Pattern

  @impl true
  def subscribe(channels, _config) when is_list(channels) do
    %{
      "jsonrpc" => "2.0",
      "method" => "public/subscribe",
      "params" => %{
        "channels" => channels
      },
      "id" => generate_id()
    }
  end

  @impl true
  def unsubscribe(channels, _config) when is_list(channels) do
    %{
      "jsonrpc" => "2.0",
      "method" => "public/unsubscribe",
      "params" => %{
        "channels" => channels
      },
      "id" => generate_id()
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
  # Generates a unique request ID for JSON-RPC correlation
  # Uses System.unique_integer for uniqueness within the node
  defp generate_id do
    System.unique_integer([:positive, :monotonic])
  end
end
