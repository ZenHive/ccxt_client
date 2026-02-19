defmodule CCXT.WS.Patterns.SubBased do
  @moduledoc """
  HTX-style WebSocket subscription pattern.

  Message format:
  ```json
  {
    "sub": "market.btcusdt.ticker",
    "id": "ticker1"
  }
  ```

  Exchanges: HTX (Huobi).
  """
  @behaviour CCXT.WS.Pattern

  alias CCXT.WS.Pattern

  @impl true
  def subscribe(channels, _config) when is_list(channels) do
    # For HTX, each subscription is a single "sub" message
    channel = List.first(channels) || ""

    %{
      "sub" => channel,
      "id" => generate_id()
    }
  end

  @impl true
  def unsubscribe(channels, _config) when is_list(channels) do
    channel = List.first(channels) || ""

    %{
      "unsub" => channel,
      "id" => generate_id()
    }
  end

  @impl true
  def format_channel(template, params, config) do
    channel_name = template[:channel_name] || ""
    separator = template[:separator] || config[:separator] || "."
    market_id_format = template[:market_id_format] || config[:market_id_format] || :lowercase

    case params[:symbol] do
      nil ->
        channel_name

      symbol ->
        # HTX format: market.{symbol}.{channel}
        "market" <>
          separator <>
          Pattern.format_market_id(symbol, market_id_format, config[:symbol_context]) <> separator <> channel_name
    end
  end

  @doc false
  defp generate_id do
    "id#{System.unique_integer([:positive, :monotonic])}"
  end
end
