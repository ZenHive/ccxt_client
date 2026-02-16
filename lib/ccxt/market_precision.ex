defmodule CCXT.MarketPrecision do
  @moduledoc """
  Normalizes per-symbol precision and limits metadata from exchange market data.

  CCXT exchanges report precision in one of three modes:

  | Mode | Value | `precision["price"]` means |
  |------|-------|---------------------------|
  | TICK_SIZE | 4 | The minimum price increment (e.g., `0.05`) |
  | DECIMALS | 0 | Number of decimal places (e.g., `2`) |
  | SIGNIFICANT_DIGITS | 1 | Not supported — varies per symbol |

  This module normalizes across modes so consumers always get both
  `price_increment` (tick size) and `price_precision` (decimal places).

  ## Usage

      # From a single market map (e.g., from fetch_markets result)
      mp = MarketPrecision.from_market(market, precision_mode)

      # From all markets at once
      precision_map = MarketPrecision.from_markets(markets, precision_mode)
      mp = precision_map["BTC/USDT"]

      # TradingView chart format
      MarketPrecision.tradingview_price_format(mp)
      #=> %{type: "price", precision: 2, minMove: 0.01}

  """

  @precision_mode_tick_size 4
  @precision_mode_decimals 0
  @precision_mode_significant_digits 1

  defstruct [
    :symbol,
    :precision_mode,
    :price_increment,
    :price_precision,
    :amount_increment,
    :amount_precision,
    :price_min,
    :price_max,
    :amount_min,
    :amount_max,
    :cost_min,
    :cost_max
  ]

  @type t :: %__MODULE__{
          symbol: String.t() | nil,
          precision_mode: non_neg_integer() | nil,
          price_increment: float() | nil,
          price_precision: non_neg_integer() | nil,
          amount_increment: float() | nil,
          amount_precision: non_neg_integer() | nil,
          price_min: float() | nil,
          price_max: float() | nil,
          amount_min: float() | nil,
          amount_max: float() | nil,
          cost_min: float() | nil,
          cost_max: float() | nil
        }

  @doc """
  Builds a `%MarketPrecision{}` from a market map or `%MarketInterface{}`.

  The `precision_mode` parameter determines how to interpret the precision values.
  Use `Exchange.__ccxt_precision_mode__/0` to get the exchange's mode.

  Returns `{:error, :unsupported_precision_mode}` for SIGNIFICANT_DIGITS mode.
  """
  @spec from_market(map() | struct(), non_neg_integer() | nil) :: t() | {:error, :unsupported_precision_mode}
  def from_market(_market, @precision_mode_significant_digits) do
    {:error, :unsupported_precision_mode}
  end

  def from_market(market, precision_mode) do
    precision = get_field(market, :precision, "precision")
    limits = get_field(market, :limits, "limits")
    symbol = get_field(market, :symbol, "symbol")

    {price_inc, price_prec} = normalize_precision(precision, "price", precision_mode)
    {amount_inc, amount_prec} = normalize_precision(precision, "amount", precision_mode)

    %__MODULE__{
      symbol: symbol,
      precision_mode: precision_mode,
      price_increment: price_inc,
      price_precision: price_prec,
      amount_increment: amount_inc,
      amount_precision: amount_prec,
      price_min: get_limit(limits, "price", "min"),
      price_max: get_limit(limits, "price", "max"),
      amount_min: get_limit(limits, "amount", "min"),
      amount_max: get_limit(limits, "amount", "max"),
      cost_min: get_limit(limits, "cost", "min"),
      cost_max: get_limit(limits, "cost", "max")
    }
  end

  @doc """
  Builds a `%{symbol => %MarketPrecision{}}` map from a list of markets.
  """
  @spec from_markets([map() | struct()], non_neg_integer() | nil) ::
          %{String.t() => t()} | {:error, :unsupported_precision_mode}
  def from_markets(_markets, @precision_mode_significant_digits) do
    {:error, :unsupported_precision_mode}
  end

  def from_markets(markets, precision_mode) do
    Map.new(markets, fn market ->
      mp = from_market(market, precision_mode)
      {mp.symbol, mp}
    end)
  end

  @doc """
  Returns TradingView-compatible price format configuration.

      MarketPrecision.tradingview_price_format(mp)
      #=> %{type: "price", precision: 2, minMove: 0.01}

  """
  @spec tradingview_price_format(t()) :: %{type: String.t(), precision: non_neg_integer() | nil, minMove: float() | nil}
  def tradingview_price_format(%__MODULE__{} = mp) do
    %{
      type: "price",
      precision: mp.price_precision,
      minMove: mp.price_increment
    }
  end

  @doc """
  Derives the number of decimal places from a tick size increment.

      decimal_places(0.01)   #=> 2
      decimal_places(0.05)   #=> 2
      decimal_places(0.0001) #=> 4
      decimal_places(1.0)    #=> 0
      decimal_places(0.25)   #=> 2
      decimal_places(0.5)    #=> 1
      decimal_places(1.0e-8) #=> 8

  """
  @spec decimal_places(number() | nil) :: non_neg_integer() | nil
  def decimal_places(nil), do: nil

  def decimal_places(increment) when is_number(increment) and increment > 0 do
    str = inspect(increment * 1.0)

    cond do
      String.contains?(str, "e-") ->
        # Scientific notation like "1.0e-8"
        [_, exp] = String.split(str, "e-")
        String.to_integer(exp)

      String.contains?(str, ".") ->
        [_, decimals] = String.split(str, ".")
        trimmed = String.replace_trailing(decimals, "0", "")
        String.length(trimmed)

      true ->
        0
    end
  end

  def decimal_places(_), do: 0

  @doc """
  Derives a tick size increment from a decimal place count.

      increment_from_decimals(2) #=> 0.01
      increment_from_decimals(4) #=> 0.0001
      increment_from_decimals(0) #=> 1.0

  """
  @spec increment_from_decimals(non_neg_integer() | nil) :: float() | nil
  def increment_from_decimals(nil), do: nil

  def increment_from_decimals(n) when is_integer(n) and n >= 0 do
    :math.pow(10, -n)
  end

  # -- Private helpers --

  @doc false
  # Gets a field from either a struct (dot access) or map (string key access)
  defp get_field(%{__struct__: _} = struct, atom_key, _string_key) do
    Map.get(struct, atom_key)
  end

  defp get_field(map, _atom_key, string_key) when is_map(map) do
    Map.get(map, string_key)
  end

  defp get_field(_, _, _), do: nil

  @doc false
  # Normalizes a precision value based on the precision mode
  defp normalize_precision(nil, _field, _mode), do: {nil, nil}

  defp normalize_precision(precision, field, @precision_mode_tick_size) when is_map(precision) do
    case Map.get(precision, field) do
      nil -> {nil, nil}
      increment when is_number(increment) -> {increment * 1.0, decimal_places(increment)}
    end
  end

  defp normalize_precision(precision, field, @precision_mode_decimals) when is_map(precision) do
    case Map.get(precision, field) do
      nil -> {nil, nil}
      decimals when is_number(decimals) -> {increment_from_decimals(trunc(decimals)), trunc(decimals)}
    end
  end

  defp normalize_precision(precision, field, _mode) when is_map(precision) do
    # Unknown or nil mode — try to pass through raw value
    case Map.get(precision, field) do
      nil -> {nil, nil}
      value when is_number(value) -> {value * 1.0, nil}
    end
  end

  defp normalize_precision(_, _, _), do: {nil, nil}

  @doc false
  # Gets a nested limit value
  defp get_limit(nil, _category, _bound), do: nil

  defp get_limit(limits, category, bound) when is_map(limits) do
    case Map.get(limits, category) do
      %{} = category_limits -> Map.get(category_limits, bound)
      _ -> nil
    end
  end

  defp get_limit(_, _, _), do: nil
end
