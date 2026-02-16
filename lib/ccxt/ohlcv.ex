defmodule CCXT.OHLCV do
  @moduledoc """
  Canonical OHLCV bar normalization and chart-library conversion helpers.

  Shared pipeline used by both REST (`ResponseCoercer`) and WS (`Normalizer`).

  ## Normalization Pipeline

  1. Validate each candle is a 6-element list
  2. Coerce string values to numbers (timestamps → integer, OHLCV → float)
  3. Build `%OHLCVBar{}` structs
  4. Sort ascending by timestamp (stable sort — duplicates preserve input order)

  ## Chart Conversion

  Built-in adapters for TradingView and Lightweight Charts, plus a generic
  `to_adapter/2` for custom chart libraries (SciChart, etc.).
  """

  alias CCXT.Types.OHLCVBar

  @candle_length 6

  @ohlcv_fields [:open, :high, :low, :close, :volume]

  # Column keys for columnar OHLCV format (e.g., Deribit)
  @columnar_required_keys ~w(ticks open high low close volume)

  # -- Normalization -----------------------------------------------------------

  @doc """
  Normalizes raw candle data to sorted `[%OHLCVBar{}]`.

  Accepts two formats:
  - **Row format** (list of lists): `[[timestamp, open, high, low, close, volume], ...]`
  - **Columnar format** (map of lists): `%{"ticks" => [...], "open" => [...], ...}`

  String values are coerced to numbers. Bars are sorted ascending by timestamp.

  Returns `{:ok, [%OHLCVBar{}]}` on success, `{:error, reason}` on failure.
  """
  @spec normalize(list() | map()) :: {:ok, [OHLCVBar.t()]} | {:error, term()}
  def normalize(data) when is_map(data) do
    if Enum.any?(@columnar_required_keys, &Map.has_key?(data, &1)) do
      case pivot_columnar(data) do
        {:ok, rows} -> normalize(rows)
        {:error, _} = err -> err
      end
    else
      {:error, {:invalid_ohlcv_format, "expected list of candles, got map with keys: #{inspect(Map.keys(data))}"}}
    end
  end

  def normalize(candles) when is_list(candles) do
    candles
    |> Enum.with_index()
    |> Enum.reduce_while([], fn {candle, idx}, acc ->
      case coerce_candle(candle, idx) do
        {:ok, bar} -> {:cont, [bar | acc]}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:error, _} = error -> error
      bars -> {:ok, bars |> Enum.reverse() |> Enum.sort_by(& &1.timestamp)}
    end
  end

  def normalize(other), do: {:error, {:expected_list, other}}

  # -- Chart Conversion --------------------------------------------------------

  @doc """
  Converts OHLCV bars to TradingView-compatible bar maps.

  Time in seconds (Unix timestamp). Atom-keyed for JSON encoding.
  """
  @spec to_tradingview([OHLCVBar.t()]) :: [map()]
  def to_tradingview(bars), do: Enum.map(bars, &tv_bar/1)

  @doc """
  Converts OHLCV bars to Lightweight Charts format.

  Same structure as TradingView (Lightweight Charts is TradingView's open-source lib).
  """
  @spec to_lightweight_charts([OHLCVBar.t()]) :: [map()]
  def to_lightweight_charts(bars), do: to_tradingview(bars)

  @doc """
  Converts OHLCV bars using a custom adapter function.

  The adapter receives an `%OHLCVBar{}` and returns the target format.
  Use this for SciChart, custom dashboards, or any chart library not covered
  by the built-in converters.

  ## Examples

      bars = [%CCXT.Types.OHLCVBar{timestamp: 1704153600000, open: 42000.0,
              high: 42500.0, low: 41500.0, close: 42100.0, volume: 1000.0}]

      CCXT.OHLCV.to_adapter(bars, fn bar ->
        {bar.timestamp, bar.open, bar.high, bar.low, bar.close}
      end)
  """
  @spec to_adapter([OHLCVBar.t()], (OHLCVBar.t() -> term())) :: [term()]
  def to_adapter(bars, adapter_fn) when is_function(adapter_fn, 1) do
    Enum.map(bars, adapter_fn)
  end

  # -- Private: Candle Coercion ------------------------------------------------

  @doc false
  # Accepts candles with 6+ elements (extra fields like turnover are ignored).
  @spec coerce_candle(term(), non_neg_integer()) :: {:ok, OHLCVBar.t()} | {:error, term()}
  defp coerce_candle(candle, _idx) when is_list(candle) and length(candle) < @candle_length do
    {:error, {:wrong_candle_length, expected: @candle_length, got: length(candle)}}
  end

  defp coerce_candle(candle, idx) when is_list(candle) do
    [raw_ts | rest] = Enum.take(candle, @candle_length)
    raw_ohlcv = rest

    with {:ok, ts} <- coerce_timestamp(raw_ts, idx),
         {:ok, ohlcv} <- coerce_ohlcv_values(raw_ohlcv, idx) do
      {:ok, OHLCVBar.from_list([ts | ohlcv])}
    end
  end

  defp coerce_candle(other, idx) do
    {:error, {:expected_candle_list, index: idx, got: other}}
  end

  @doc false
  # Coerces a timestamp value to integer milliseconds.
  # Timestamps are required (nil is rejected).
  @spec coerce_timestamp(term(), non_neg_integer()) :: {:ok, integer()} | {:error, term()}
  defp coerce_timestamp(ts, _idx) when is_integer(ts), do: {:ok, ts}
  defp coerce_timestamp(ts, _idx) when is_float(ts), do: {:ok, trunc(ts)}

  defp coerce_timestamp(ts, _idx) when is_binary(ts) do
    cond do
      match?({_int, ""}, Integer.parse(ts)) ->
        {int, ""} = Integer.parse(ts)
        {:ok, int}

      match?({_float, ""}, Float.parse(ts)) ->
        {float, ""} = Float.parse(ts)
        {:ok, trunc(float)}

      true ->
        {:error, {:invalid_timestamp, ts}}
    end
  end

  defp coerce_timestamp(nil, idx), do: {:error, {:nil_timestamp, idx}}
  defp coerce_timestamp(other, _idx), do: {:error, {:invalid_timestamp, other}}

  @doc false
  # Coerces the 5 OHLCV values (open, high, low, close, volume) to floats.
  # nil values are preserved. Strings are parsed. Integers are promoted to float.
  @spec coerce_ohlcv_values([term()], non_neg_integer()) :: {:ok, [float() | nil]} | {:error, term()}
  defp coerce_ohlcv_values(values, idx) do
    values
    |> Enum.zip(@ohlcv_fields)
    |> Enum.reduce_while([], fn {val, field}, acc ->
      case coerce_ohlcv_value(val) do
        {:ok, coerced} -> {:cont, [coerced | acc]}
        :error -> {:halt, {:error, {:invalid_value, field, val, idx}}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      coerced -> {:ok, Enum.reverse(coerced)}
    end
  end

  @doc false
  # Coerces a single OHLCV value to float.
  @spec coerce_ohlcv_value(term()) :: {:ok, float() | nil} | :error
  defp coerce_ohlcv_value(nil), do: {:ok, nil}
  defp coerce_ohlcv_value(v) when is_float(v), do: {:ok, v}
  defp coerce_ohlcv_value(v) when is_integer(v), do: {:ok, v * 1.0}

  defp coerce_ohlcv_value(v) when is_binary(v) do
    if match?({_float, ""}, Float.parse(v)) do
      {float, ""} = Float.parse(v)
      {:ok, float}
    else
      :error
    end
  end

  defp coerce_ohlcv_value(_), do: :error

  # -- Private: Columnar pivot -------------------------------------------------

  @doc false
  # Pivots columnar OHLCV data (e.g., Deribit) into row format.
  # Input: %{"ticks" => [t1, t2], "open" => [o1, o2], ...}
  # Output: {:ok, [[t1, o1, h1, l1, c1, v1], [t2, o2, h2, l2, c2, v2]]}
  @spec pivot_columnar(map()) :: {:ok, [[term()]]} | {:error, term()}
  defp pivot_columnar(data) do
    with :ok <- validate_columnar_keys(data),
         columns = Enum.map(@columnar_required_keys, &Map.fetch!(data, &1)),
         :ok <- validate_columnar_types(columns),
         :ok <- validate_columnar_lengths(columns) do
      rows = columns |> Enum.zip() |> Enum.map(&Tuple.to_list/1)
      {:ok, rows}
    end
  end

  defp validate_columnar_keys(data) do
    case Enum.reject(@columnar_required_keys, &Map.has_key?(data, &1)) do
      [] -> :ok
      missing -> {:error, {:missing_ohlcv_columns, missing}}
    end
  end

  defp validate_columnar_types(columns) do
    non_lists = Enum.reject(Enum.zip(@columnar_required_keys, columns), fn {_k, v} -> is_list(v) end)

    if non_lists == [] do
      :ok
    else
      bad = Enum.map(non_lists, fn {k, v} -> {k, inspect(v)} end)
      {:error, {:invalid_ohlcv_column_type, bad}}
    end
  end

  defp validate_columnar_lengths(columns) do
    lengths = Enum.map(columns, &length/1)

    if length(Enum.uniq(lengths)) > 1 do
      {:error, {:mismatched_ohlcv_column_lengths, Enum.zip(@columnar_required_keys, lengths)}}
    else
      :ok
    end
  end

  # -- Private: Chart helpers --------------------------------------------------

  @doc false
  defp tv_bar(%OHLCVBar{} = bar) do
    %{
      time: ms_to_seconds(bar.timestamp),
      open: bar.open,
      high: bar.high,
      low: bar.low,
      close: bar.close,
      volume: bar.volume
    }
  end

  @doc false
  defp ms_to_seconds(ms) when is_integer(ms), do: div(ms, 1000)
end
