defmodule CCXT.WS.MessageRouter do
  @moduledoc """
  Routes raw WS messages to payload families using envelope extraction.

  Given a raw decoded WS message, an envelope config (from W13's handler
  mappings), and an exchange ID, this module:

  1. Extracts the channel name using the envelope's `discriminator_field`
  2. Resolves the channel → family via `WsHandlerMappings.resolve_channel/2`
  3. Extracts payload data using the envelope's `data_field`

  ## Return Values

  - `{:routed, family, payload}` — Channel found, family resolved
  - `{:system, raw_msg}` — Handler maps to nil (auth/pong/subscription), or
    response/ack message detected when discriminator is absent
  - `{:unknown, raw_msg}` — No envelope config or no mapping

  ## Envelope Patterns

  | Pattern | Exchange | Discriminator | Data |
  |---------|----------|---------------|------|
  | `flat` | Binance | `msg["e"]` | entire message |
  | `topic_data` | Bybit | `msg["topic"]` | `msg["data"]` |
  | `jsonrpc_subscription` | Deribit | `msg["params"]["channel"]` | `msg["params"]["data"]` |
  | `arg_data` | OKX | `msg["arg"]["channel"]` | `msg["data"]` |
  | `channel_result` | Gate | `msg["channel"]` | `msg["result"]` |

  ## List Unwrapping

  Some exchanges (OKX, Kraken, Poloniex, Toobit) wrap data payloads in a
  single-element list: `"data": [%{...}]`. When the envelope has
  `"unwrap_list" => true`, `extract_data/2` applies
  `ResponseTransformer.unwrap_single_element_list/1` to unwrap `[single_map]`
  to `single_map`. Multi-element lists and non-lists pass through unchanged.
  """

  alias CCXT.Extract.WsHandlerMappings
  alias CCXT.ResponseTransformer

  @doc """
  Routes a raw WS message to a payload family.

  ## Parameters

  - `raw_msg` - Decoded JSON map from the WebSocket
  - `envelope` - Envelope config map with `"discriminator_field"` and `"data_field"` keys
  - `exchange_id` - Exchange identifier string (e.g., `"binance"`)

  ## Returns

  - `{:routed, family, payload}` — Successfully routed to a family
  - `{:system, raw_msg}` — System message (auth, pong, subscription management)
  - `{:unknown, raw_msg}` — Could not route (no channel or no mapping)

  """
  @spec route(map(), map() | nil, String.t()) ::
          {:routed, atom(), term()} | {:system, map()} | {:unknown, map()}
  def route(raw_msg, nil, _exchange_id), do: {:unknown, raw_msg}

  def route(raw_msg, envelope, exchange_id) when is_map(raw_msg) and is_map(envelope) do
    case extract_channel(raw_msg, envelope) do
      nil ->
        if response_message?(raw_msg), do: {:system, raw_msg}, else: {:unknown, raw_msg}

      channel ->
        resolve_family(raw_msg, envelope, exchange_id, channel)
    end
  end

  @doc false
  # Resolves a channel to a family using tri-state semantics from
  # WsHandlerMappings.resolve_channel/2 to correctly distinguish:
  # - {:family, atom} — known handler with a family mapping
  # - :system — known handler but non-family (auth/pong/subscription)
  # - :not_found — no handler matches (unknown channel OR unknown exchange)
  @spec resolve_family(map(), map(), String.t(), String.t()) ::
          {:routed, atom(), term()} | {:system, map()} | {:unknown, map()}
  defp resolve_family(raw_msg, envelope, exchange_id, channel) do
    case WsHandlerMappings.resolve_channel(exchange_id, channel) do
      {:family, family} ->
        payload = extract_data(raw_msg, envelope)
        {:routed, family, payload}

      :system ->
        {:system, raw_msg}

      :not_found ->
        {:unknown, raw_msg}
    end
  end

  @doc false
  # Detects subscription ack / response messages when discriminator is absent.
  # Requires both "id" and "result" keys (JSON-RPC convention).
  # Safe: data messages always have the discriminator field; this only fires when it's missing.
  # Gate.io uses "result" as data_field but always has "channel" discriminator → routes normally.
  @spec response_message?(map()) :: boolean()
  defp response_message?(%{"id" => _, "result" => _}), do: true
  defp response_message?(_), do: false

  @doc """
  Extracts the channel name from a raw message using the envelope config.

  The `discriminator_field` supports dot-notation paths (e.g., `"params.channel"`).
  """
  @spec extract_channel(map(), map()) :: String.t() | nil
  def extract_channel(raw_msg, envelope) do
    field = Map.get(envelope, "discriminator_field")
    get_nested(raw_msg, field)
  end

  @doc """
  Extracts the payload data from a raw message using the envelope config.

  When `data_field` is `"self"`, returns the entire message.
  Supports dot-notation paths (e.g., `"params.data"`).
  When `unwrap_list` is truthy, unwraps single-element list payloads.
  """
  @spec extract_data(map(), map()) :: term()
  def extract_data(raw_msg, envelope) do
    data =
      case Map.get(envelope, "data_field") do
        "self" -> raw_msg
        field -> get_nested(raw_msg, field)
      end

    if Map.get(envelope, "unwrap_list") do
      ResponseTransformer.unwrap_single_element_list(data)
    else
      data
    end
  end

  @doc """
  Resolves a dot-notation path in a nested map.

  ## Examples

      iex> CCXT.WS.MessageRouter.get_nested(%{"a" => %{"b" => "value"}}, "a.b")
      "value"

      iex> CCXT.WS.MessageRouter.get_nested(%{"x" => 1}, "x")
      1

      iex> CCXT.WS.MessageRouter.get_nested(%{}, "a.b.c")
      nil

  """
  @spec get_nested(map(), String.t() | nil) :: term()
  def get_nested(_map, nil), do: nil

  def get_nested(map, path) when is_map(map) and is_binary(path) do
    path
    |> String.split(".")
    |> Enum.reduce_while(map, fn key, acc ->
      case acc do
        %{} = m -> {:cont, Map.get(m, key)}
        _ -> {:halt, nil}
      end
    end)
  end

  def get_nested(_, _), do: nil
end
