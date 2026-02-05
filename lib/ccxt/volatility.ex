defmodule CCXT.Volatility do
  @moduledoc """
  Volatility calculations for trading systems.

  Pure functions for calculating historical (realized) volatility,
  comparing implied vs realized volatility, and computing volatility metrics.

  ## Example

      prices = [100, 102, 99, 103, 101, 105, 102]

      CCXT.Volatility.realized(prices)
      # => 0.023  (2.3% daily volatility)

      CCXT.Volatility.realized(prices, annualize: true)
      # => 0.365  (36.5% annualized)

  """

  @trading_days_per_year 365

  @typedoc "Volatility as decimal (e.g., 0.25 = 25%)"
  @type volatility :: float()

  @typedoc "IV comparison output format"
  @type iv_format :: :ratio | :premium | :premium_pct

  @typedoc "OHLC candle for volatility estimation"
  @type candle :: %{
          optional(:open) => number(),
          :high => number(),
          :low => number(),
          optional(:close) => number()
        }

  @doc """
  Calculate realized (historical) volatility from prices.

  Uses close-to-close returns to estimate volatility.

  ## Parameters

    * `prices` - List of prices (chronological order, oldest first)
    * `opts` - Options:
      * `:annualize` - Whether to annualize (default: false)
      * `:trading_days` - Trading days per year for annualization (default: 365)

  ## Returns

  Standard deviation of returns, or `nil` if insufficient data.

  ## Example

      prices = [100, 102, 99, 103, 101]

      CCXT.Volatility.realized(prices)
      # => 0.023 (daily)

      CCXT.Volatility.realized(prices, annualize: true)
      # => 0.44 (annualized)

  """
  @spec realized([number()], keyword()) :: volatility() | nil | {:error, :invalid_prices}
  def realized(prices, opts \\ []) when is_list(prices) do
    cond do
      length(prices) < 3 -> nil
      Enum.any?(prices, &(&1 <= 0)) -> {:error, :invalid_prices}
      true -> calculate_realized(prices, opts)
    end
  end

  @doc false
  # Computes standard deviation of log returns, optionally annualized
  defp calculate_realized(prices, opts) do
    returns = calculate_returns(prices)
    std_dev = standard_deviation(returns)

    if Keyword.get(opts, :annualize, false) do
      trading_days = Keyword.get(opts, :trading_days, @trading_days_per_year)
      std_dev * :math.sqrt(trading_days)
    else
      std_dev
    end
  end

  @doc false
  # Converts price series to log returns
  defp calculate_returns(prices) do
    prices
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [prev, curr] -> :math.log(curr / prev) end)
  end

  @doc """
  Calculate Parkinson volatility estimator.

  Uses high-low range, which is more efficient than close-to-close
  when intraday data is available.

  ## Parameters

    * `candles` - List of candles with `:high` and `:low` fields
    * `opts` - Options:
      * `:annualize` - Whether to annualize (default: false)
      * `:trading_days` - Trading days per year (default: 365)

  ## Returns

  Parkinson volatility estimate, or `nil` if insufficient data.

  ## Example

      candles = [
        %{high: 105, low: 98},
        %{high: 107, low: 100},
        %{high: 103, low: 96}
      ]

      CCXT.Volatility.parkinson(candles)
      # => 0.034

  """
  @spec parkinson([candle()], keyword()) :: volatility() | nil | {:error, :invalid_prices}
  def parkinson(candles, opts \\ []) when is_list(candles) do
    cond do
      length(candles) < 2 -> nil
      has_invalid_high_low?(candles) -> {:error, :invalid_prices}
      true -> calculate_parkinson(candles, opts)
    end
  end

  @doc false
  # Checks if any candle has zero or negative high/low values
  defp has_invalid_high_low?(candles) do
    Enum.any?(candles, fn candle ->
      high = candle[:high] || candle["high"]
      low = candle[:low] || candle["low"]
      (is_number(high) and high <= 0) or (is_number(low) and low <= 0)
    end)
  end

  @doc false
  # Computes Parkinson estimator from high-low ranges
  defp calculate_parkinson(candles, opts) do
    n = length(candles)

    sum_squared =
      candles
      |> Enum.map(fn candle ->
        high = candle[:high] || candle["high"]
        low = candle[:low] || candle["low"]
        :math.pow(:math.log(high / low), 2)
      end)
      |> Enum.sum()

    # Parkinson constant: 1 / (4 * ln(2))
    parkinson_constant = 1 / (4 * :math.log(2))
    variance = parkinson_constant * sum_squared / n
    std_dev = :math.sqrt(variance)

    if Keyword.get(opts, :annualize, false) do
      trading_days = Keyword.get(opts, :trading_days, @trading_days_per_year)
      std_dev * :math.sqrt(trading_days)
    else
      std_dev
    end
  end

  @doc """
  Calculate IV percentile relative to historical distribution.

  Shows where current IV ranks compared to past IV values.

  ## Parameters

    * `current_iv` - Current implied volatility
    * `historical_ivs` - List of historical IV values

  ## Returns

  Percentile (0-100) showing % of historical values below current,
  or `nil` if insufficient data.

  ## Example

      CCXT.Volatility.iv_percentile(0.65, [0.40, 0.55, 0.60, 0.70, 0.80])
      # => 60.0 (current IV is higher than 60% of historical)

  """
  @spec iv_percentile(number(), [number()]) :: float() | nil
  def iv_percentile(current_iv, historical_ivs) when is_number(current_iv) and is_list(historical_ivs) do
    if Enum.empty?(historical_ivs) do
      nil
    else
      count_below = Enum.count(historical_ivs, &(&1 < current_iv))
      count_below / length(historical_ivs) * 100
    end
  end

  @doc """
  Calculate IV rank (normalized position in range).

  Shows where current IV sits relative to the historical range.

  ## Parameters

    * `current_iv` - Current implied volatility
    * `historical_ivs` - List of historical IV values

  ## Returns

  Rank (0-100) showing position in min-max range,
  or `nil` if insufficient data.

  ## Example

      # Current 65%, range was 40-80%
      CCXT.Volatility.iv_rank(0.65, [0.40, 0.55, 0.60, 0.70, 0.80])
      # => 62.5 (65% is 62.5% of the way from 40% to 80%)

  """
  @spec iv_rank(number(), [number()]) :: float() | nil
  def iv_rank(current_iv, historical_ivs) when is_number(current_iv) and is_list(historical_ivs) do
    if length(historical_ivs) < 2 do
      nil
    else
      min_iv = Enum.min(historical_ivs)
      max_iv = Enum.max(historical_ivs)
      range = max_iv - min_iv

      if range == 0 do
        50.0
      else
        (current_iv - min_iv) / range * 100
      end
    end
  end

  @doc """
  Compare implied volatility to realized volatility.

  ## Parameters

    * `implied_vol` - Current implied volatility
    * `realized_vol` - Realized volatility over same period
    * `format` - Output format (default: `:ratio`)

  ## Returns

  Based on format:
    * `:ratio` - IV / RV ratio (>1 means IV premium)
    * `:premium` - IV - RV (positive means IV premium)
    * `:premium_pct` - (IV - RV) / RV * 100

  ## Example

      CCXT.Volatility.iv_vs_rv(0.65, 0.50)
      # => 1.3 (IV is 30% higher than RV)

      CCXT.Volatility.iv_vs_rv(0.65, 0.50, :premium)
      # => 0.15

      CCXT.Volatility.iv_vs_rv(0.65, 0.50, :premium_pct)
      # => 30.0

  """
  @spec iv_vs_rv(volatility(), volatility(), iv_format()) :: float() | nil
  def iv_vs_rv(implied_vol, realized_vol, format \\ :ratio) when is_number(implied_vol) and is_number(realized_vol) do
    if realized_vol == 0 do
      nil
    else
      calculate_iv_vs_rv(implied_vol, realized_vol, format)
    end
  end

  @doc false
  # Computes IV vs RV comparison in specified format (ratio, premium, or premium_pct)
  defp calculate_iv_vs_rv(implied_vol, realized_vol, :ratio) do
    implied_vol / realized_vol
  end

  defp calculate_iv_vs_rv(implied_vol, realized_vol, :premium) do
    implied_vol - realized_vol
  end

  defp calculate_iv_vs_rv(implied_vol, realized_vol, :premium_pct) do
    (implied_vol - realized_vol) / realized_vol * 100
  end

  @doc """
  Calculate volatility cone data for term structure analysis.

  Returns percentile bands at different lookback periods.

  ## Parameters

    * `prices` - List of prices (chronological order)
    * `periods` - List of lookback periods to calculate

  ## Returns

  Map of period => volatility value (or `nil` if insufficient data).

  ## Example

      CCXT.Volatility.cone(prices, [5, 10, 20, 30])
      # => %{5 => 0.02, 10 => 0.025, 20 => 0.028, 30 => 0.03}

  """
  @spec cone([number()], [pos_integer()]) :: %{pos_integer() => volatility() | nil}
  def cone(prices, periods) when is_list(prices) and is_list(periods) do
    price_count = length(prices)

    periods
    |> Enum.filter(&(&1 <= price_count))
    |> Map.new(fn period ->
      recent_prices = Enum.take(prices, -period)
      {period, result_to_value(realized(recent_prices))}
    end)
  end

  @doc """
  Check if volatility regime is elevated.

  ## Parameters

    * `current_vol` - Current volatility
    * `baseline_vol` - Normal/baseline volatility
    * `threshold` - Multiple of baseline considered elevated (default: 1.5)

  ## Example

      CCXT.Volatility.elevated?(0.45, 0.30)
      # => true (0.45 > 0.30 * 1.5)

  """
  @spec elevated?(number(), number(), number()) :: boolean()
  def elevated?(current_vol, baseline_vol, threshold \\ 1.5)
      when is_number(current_vol) and is_number(baseline_vol) and is_number(threshold) do
    current_vol > baseline_vol * threshold
  end

  @doc """
  Calculate Garman-Klass volatility estimator.

  Uses OHLC data for more efficient estimation than close-to-close.

  ## Parameters

    * `candles` - List of candles with `:open`, `:high`, `:low`, `:close` fields
    * `opts` - Options:
      * `:annualize` - Whether to annualize (default: false)

  ## Returns

  Garman-Klass volatility, or `nil` if insufficient data.

  """
  @spec garman_klass([candle()], keyword()) :: volatility() | nil | {:error, :invalid_prices}
  def garman_klass(candles, opts \\ []) when is_list(candles) do
    cond do
      length(candles) < 2 -> nil
      has_invalid_ohlc?(candles) -> {:error, :invalid_prices}
      true -> calculate_garman_klass(candles, opts)
    end
  end

  @doc false
  # Checks if any candle has zero or negative OHLC values
  defp has_invalid_ohlc?(candles) do
    Enum.any?(candles, &candle_has_invalid_ohlc?/1)
  end

  @doc false
  # Checks a single candle for invalid OHLC values
  defp candle_has_invalid_ohlc?(candle) do
    Enum.any?(
      [
        candle[:open] || candle["open"],
        candle[:high] || candle["high"],
        candle[:low] || candle["low"],
        candle[:close] || candle["close"]
      ],
      &invalid_price?/1
    )
  end

  @doc false
  # Returns true if the value is a number <= 0
  defp invalid_price?(value) when is_number(value), do: value <= 0
  defp invalid_price?(_), do: false

  @doc false
  # Computes Garman-Klass estimator using OHLC data
  defp calculate_garman_klass(candles, opts) do
    n = length(candles)

    sum =
      candles
      |> Enum.map(&gk_single_candle/1)
      |> Enum.sum()

    variance = sum / n
    std_dev = :math.sqrt(variance)

    if Keyword.get(opts, :annualize, false) do
      trading_days = Keyword.get(opts, :trading_days, @trading_days_per_year)
      std_dev * :math.sqrt(trading_days)
    else
      std_dev
    end
  end

  @doc false
  # Applies Garman-Klass formula to a single OHLC candle
  defp gk_single_candle(candle) do
    open = candle[:open] || candle["open"]
    high = candle[:high] || candle["high"]
    low = candle[:low] || candle["low"]
    close = candle[:close] || candle["close"]

    log_hl = :math.log(high / low)
    log_co = :math.log(close / open)

    # Garman-Klass formula
    0.5 * :math.pow(log_hl, 2) - (2 * :math.log(2) - 1) * :math.pow(log_co, 2)
  end

  @doc """
  Calculate rolling volatility over a price series.

  Returns a list of volatility values calculated over a rolling window.
  Useful for analyzing volatility trends and regime changes.

  ## Parameters

    * `prices` - List of prices (chronological order)
    * `window` - Rolling window size (number of periods)
    * `opts` - Options:
      * `:annualize` - Whether to annualize (default: false)
      * `:trading_days` - Trading days per year (default: 365)

  ## Returns

  List of volatility values. Length will be `length(prices) - window + 1`.
  Returns empty list if insufficient data.

  ## Example

      prices = [100, 102, 99, 103, 101, 105, 102, 108, 104, 110]
      CCXT.Volatility.rolling(prices, 5)
      # => [0.023, 0.025, 0.028, 0.026, 0.030, 0.027]

  """
  @spec rolling([number()], pos_integer(), keyword()) :: [volatility()]
  def rolling(prices, window, opts \\ []) when is_list(prices) and is_integer(window) and window > 2 do
    if length(prices) < window do
      []
    else
      calculate_rolling(prices, window, opts)
    end
  end

  @doc false
  # Calculates rolling volatility using sliding window
  defp calculate_rolling(prices, window, opts) do
    prices
    |> Enum.chunk_every(window, 1, :discard)
    |> Enum.map(&realized(&1, opts))
    |> Enum.map(&result_to_value/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc false
  # Converts error tuples to nil for aggregate functions
  defp result_to_value({:error, _}), do: nil
  defp result_to_value(value), do: value

  @doc false
  # Calculates sample standard deviation of a series (n-1 for unbiased estimator)
  defp standard_deviation(values) when length(values) < 2, do: 0.0

  defp standard_deviation(values) do
    n = length(values)
    mean = Enum.sum(values) / n

    variance =
      values
      |> Enum.map(&:math.pow(&1 - mean, 2))
      |> Enum.sum()
      |> Kernel./(n - 1)

    :math.sqrt(variance)
  end
end
