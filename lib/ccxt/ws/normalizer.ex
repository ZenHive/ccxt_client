defmodule CCXT.WS.Normalizer do
  @moduledoc """
  Normalizes WS payloads to canonical typed structs.

  Takes a family atom + raw payload + exchange module and produces the same
  unified types as REST endpoints (e.g., `%Ticker{}`, `%Trade{}`, `%OrderBook{}`).

  ## Integration

  Uses the existing REST parsing pipeline:

      Raw WS payload
        → ResponseParser.parse_single/2 (exchange-specific field mapping)
        → ResponseCoercer.coerce/4 (type coercion → struct)
        → struct with :raw field populated

  ## Graceful Degradation

  - No parser instructions → `from_map/1` directly
  - No exchange module parsers → raw payload with family tag
  - Normalization error → `{:error, reason}` (loud, not silent)
  """

  alias CCXT.ResponseCoercer
  alias CCXT.WS.Contract

  require Logger

  @doc """
  Normalizes a WS payload for a given family and exchange module.

  ## Parameters

  - `family` - Family atom (e.g., `:watch_ticker`, `:watch_trades`)
  - `payload` - Raw decoded payload data (map, list of maps, or list of lists)
  - `exchange_module` - The REST exchange module (e.g., `CCXT.Bybit`) for parser lookup

  ## Returns

  - `{:ok, normalized}` — Successfully normalized to struct(s)
  - `{:error, reason}` — Normalization failed

  ## Examples

      iex> CCXT.WS.Normalizer.normalize(:watch_ticker, %{"askPrice" => "42000"}, CCXT.Bybit)
      {:ok, %CCXT.Types.Ticker{ask: 42000.0, ...}}

  """
  @spec normalize(Contract.family(), term(), module()) :: {:ok, term()} | {:error, term()}
  def normalize(:watch_ohlcv, payload, _exchange_module) do
    normalize_ohlcv(payload)
  end

  def normalize(family, payload, exchange_module) when is_atom(family) do
    spec = Contract.family_spec(family)
    coercion_type = spec.coercion_type
    parser_instructions = get_parser_instructions(exchange_module, coercion_type)

    case spec.result_shape do
      :single ->
        normalize_single(payload, coercion_type, parser_instructions)

      :list ->
        normalize_list(payload, coercion_type, parser_instructions)
    end
  rescue
    e ->
      Logger.warning("[WS.Normalizer] Normalization failed for #{family}: #{Exception.message(e)}")
      {:error, {:normalization_failed, family, Exception.message(e)}}
  end

  # -- Private Helpers ---------------------------------------------------------

  @doc false
  # Normalizes a single payload map to a struct
  defp normalize_single(payload, coercion_type, parser_instructions) when is_map(payload) do
    payload_with_info = Map.put_new(payload, "info", payload)
    result = ResponseCoercer.coerce(payload_with_info, coercion_type, [], parser_instructions)
    {:ok, result}
  end

  defp normalize_single(payload, _coercion_type, _parser_instructions) do
    {:error, {:expected_map, payload}}
  end

  @doc false
  # Normalizes a list payload — handles both list-of-maps and single-map-wrapped-as-list
  defp normalize_list(payload, coercion_type, parser_instructions) when is_list(payload) do
    payload
    |> Enum.with_index()
    |> Enum.reduce_while([], fn
      {item, _idx}, acc when is_map(item) ->
        item_with_info = Map.put_new(item, "info", item)
        result = ResponseCoercer.coerce(item_with_info, coercion_type, [], parser_instructions)
        {:cont, [result | acc]}

      {item, idx}, _acc ->
        {:halt, {:error, {:invalid_list_element, index: idx, value: item}}}
    end)
    |> case do
      {:error, _} = error -> error
      results -> {:ok, Enum.reverse(results)}
    end
  end

  defp normalize_list(payload, coercion_type, parser_instructions) when is_map(payload) do
    # Some exchanges send a single item instead of a list
    normalize_list([payload], coercion_type, parser_instructions)
  end

  defp normalize_list(payload, _coercion_type, _parser_instructions) do
    {:error, {:expected_list, payload}}
  end

  @doc false
  # OHLCV: shared normalization — structs, sort, coerce via CCXT.OHLCV
  defp normalize_ohlcv(payload) when is_list(payload) do
    CCXT.OHLCV.normalize(payload)
  end

  defp normalize_ohlcv(payload) do
    {:error, {:expected_list, payload}}
  end

  @doc false
  # Looks up parser instructions from the exchange module's __ccxt_parsers__/0
  defp get_parser_instructions(exchange_module, coercion_type) do
    with {:module, _} <- Code.ensure_loaded(exchange_module),
         true <- function_exported?(exchange_module, :__ccxt_parsers__, 0) do
      parsers = exchange_module.__ccxt_parsers__()
      Map.get(parsers, coercion_type)
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
