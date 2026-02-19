defmodule CCXT.WS.Patterns.TypeSubscribe do
  @moduledoc """
  KuCoin/Coinbase/Onetrading-style WebSocket subscription pattern.

  Message format (single-field, KuCoin style):
  ```json
  {
    "type": "subscribe",
    "topic": "/market/ticker:BTC-USDT"
  }
  ```

  Message format (dual-field, Coinbase style):
  ```json
  {
    "type": "subscribe",
    "product_ids": ["BTC-USD"],
    "channels": ["matches"]
  }
  ```

  When `channels_field` is present in config, the pattern uses two separate
  fields: `args_field` for market IDs and `channels_field` for channel names.

  Exchanges: KuCoin, Coinbase, Onetrading.
  """
  @behaviour CCXT.WS.Pattern

  alias CCXT.WS.Pattern

  @impl true
  def subscribe(channels, config) when is_list(channels) do
    build_message(channels, config, "subscribe")
  end

  @impl true
  def unsubscribe(channels, config) when is_list(channels) do
    build_message(channels, config, "unsubscribe")
  end

  @doc false
  @spec build_message([String.t()], map(), String.t()) :: map()
  defp build_message(channels, config, action) do
    type_field = config[:op_field] || "type"
    args_field = config[:args_field] || "topic"
    args_format = config[:args_format] || :string
    channels_field = config[:channels_field]

    base = %{type_field => action}

    if channels_field do
      # Dual-field: args_field gets market IDs, channels_field gets channel name
      channel_name = config[:channel_name]

      base
      |> Map.put(args_field, channels)
      |> put_channels_field(channels_field, channel_name)
    else
      case args_format do
        :string ->
          # Single topic per message (KuCoin style)
          channel = List.first(channels) || ""
          Map.put(base, args_field, channel)

        _ ->
          # Array of channels
          Map.put(base, args_field, channels)
      end
    end
  end

  @impl true
  def format_channel(template, params, config) do
    channel_name = template[:channel_name] || ""
    separator = template[:separator] || config[:separator] || ":"
    market_id_format = template[:market_id_format] || config[:market_id_format] || :native
    channels_field = config[:channels_field]

    case params[:symbol] do
      nil ->
        channel_name

      symbol ->
        market_id = Pattern.format_market_id(symbol, market_id_format, config[:symbol_context])

        if channels_field do
          # Dual-field: return only the market ID — channel_name goes in channels field
          market_id
        else
          # Single-field: combine channel_name + separator + market_id
          channel_name <> separator <> market_id
        end
    end
  end

  # Populates the channels field: array for "channels", string for "channel"
  @doc false
  @spec put_channels_field(map(), String.t(), String.t() | nil) :: map()
  defp put_channels_field(message, "channels", channel_name) do
    Map.put(message, "channels", if(channel_name, do: [channel_name], else: []))
  end

  defp put_channels_field(message, field, channel_name) do
    Map.put(message, field, channel_name || "")
  end
end
