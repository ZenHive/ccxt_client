defmodule CCXT.WS.Patterns.Custom do
  @moduledoc """
  Custom pattern for exchanges with unique WebSocket formats.

  These exchanges have unique subscription formats that don't fit into
  standard patterns. Each requires exchange-specific handling.

  ## Custom Types

  - `type_as_channel` (Bithumb) - Type field IS the channel name
  - `url_path` (Bitopro) - Channel embedded in URL path
  - `url_query` (IndependentReserve) - Channel in URL query param
  - `auth_only` (Luno) - Sends credentials only, no subscribe message
  - `numeric_message_type` (NDAX) - Numeric message type codes
  - `sendTopicAction` (Deepcoin) - Nested sendTopicAction structure
  - `array_format` (Upbit) - Array of subscription objects

  For these exchanges, the generator may need custom handling or
  the exchange module may override the generated functions.
  """
  @behaviour CCXT.WS.Pattern

  alias CCXT.WS.Pattern

  @impl true
  def subscribe(channels, config) when is_list(channels) do
    # Custom patterns require exchange-specific handling
    # Return a generic structure that can be extended
    custom_type = config[:custom_type]

    case custom_type do
      "array_format" ->
        # Upbit style: array of subscription objects
        Enum.map(channels, fn channel ->
          %{"type" => "ticker", "codes" => [channel]}
        end)

      "sendTopicAction" ->
        # Deepcoin style: nested structure
        %{
          "sendTopicAction" => %{
            "action" => "subscribe",
            "topics" => channels
          }
        }

      _ ->
        # Default fallback
        %{
          "subscribe" => true,
          "channels" => channels
        }
    end
  end

  @impl true
  def unsubscribe(channels, config) when is_list(channels) do
    custom_type = config[:custom_type]

    case custom_type do
      "array_format" ->
        Enum.map(channels, fn channel ->
          %{"type" => "ticker", "codes" => [channel], "isOnlyRealtime" => true}
        end)

      "sendTopicAction" ->
        %{
          "sendTopicAction" => %{
            "action" => "unsubscribe",
            "topics" => channels
          }
        }

      _ ->
        %{
          "unsubscribe" => true,
          "channels" => channels
        }
    end
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
end
