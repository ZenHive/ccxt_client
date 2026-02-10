defmodule CCXT.Trading.Funding do
  @moduledoc """
  Funding rate analysis functions for perpetual futures.

  Pure functions for analyzing funding rates, calculating annualized returns,
  detecting spikes, and comparing rates across exchanges.

  Works with `CCXT.Types.FundingRate` structs from exchange APIs.

  ## Example

      rates = [
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.00015}
      ]

      CCXT.Trading.Funding.average(rates)
      # => 0.000125

      CCXT.Trading.Funding.annualize(0.0001)
      # => 0.1095  (10.95% APR)

  """

  alias CCXT.Types.FundingRate

  @hours_per_year 8760

  @doc """
  Annualize a funding rate.

  Converts a periodic funding rate to Annual Percentage Rate (APR).
  Standard perpetual futures use 8-hour funding periods.

  ## Parameters

    * `rate` - The funding rate for one period (e.g., 0.0001 = 0.01%)
    * `period_hours` - Hours per funding period (default: 8)

  ## Example

      CCXT.Trading.Funding.annualize(0.0001)
      # => 0.1095  (10.95% APR)

      CCXT.Trading.Funding.annualize(0.0001, 4)
      # => 0.219  (4-hour funding period)

  """
  @spec annualize(number(), pos_integer()) :: float()
  def annualize(rate, period_hours \\ 8) when is_number(rate) and is_integer(period_hours) and period_hours > 0 do
    periods_per_year = @hours_per_year / period_hours
    rate * periods_per_year
  end

  @doc """
  Calculate average funding rate from a list of rates.

  ## Example

      rates = [
        %FundingRate{funding_rate: 0.0001},
        %FundingRate{funding_rate: 0.00015},
        %FundingRate{funding_rate: 0.00005}
      ]

      CCXT.Trading.Funding.average(rates)
      # => 0.0001

  """
  @spec average([FundingRate.t()]) :: float() | nil
  def average([]), do: nil

  def average(rates) when is_list(rates) do
    valid_rates =
      rates
      |> Enum.map(& &1.funding_rate)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(valid_rates) do
      nil
    else
      Enum.sum(valid_rates) / length(valid_rates)
    end
  end

  @doc """
  Detect funding rate spikes (abnormally high or low rates).

  A spike is defined as a rate exceeding the threshold standard deviations
  from the mean.

  ## Parameters

    * `rates` - List of FundingRate structs
    * `opts` - Options:
      * `:threshold` - Number of standard deviations (default: 2.0)

  ## Returns

  List of tuples with spike direction and the FundingRate:
    * `{:high, rate}` - Rate is abnormally high (longs pay shorts)
    * `{:low, rate}` - Rate is abnormally low/negative (shorts pay longs)

  ## Example

      CCXT.Trading.Funding.detect_spikes(rates, threshold: 2.0)
      # => [{:high, %FundingRate{...}}, {:low, %FundingRate{...}}]

  """
  @spec detect_spikes([FundingRate.t()], keyword()) :: [{:high | :low, FundingRate.t()}]
  def detect_spikes(rates, opts \\ []) when is_list(rates) do
    threshold = Keyword.get(opts, :threshold, 2.0)
    valid_rates = Enum.reject(rates, &is_nil(&1.funding_rate))

    do_detect_spikes(valid_rates, threshold)
  end

  @doc false
  defp do_detect_spikes(valid_rates, _threshold) when length(valid_rates) < 3, do: []

  defp do_detect_spikes(valid_rates, threshold) do
    mean = average(valid_rates)
    std_dev = standard_deviation(valid_rates, mean)

    find_spikes(valid_rates, mean, std_dev, threshold)
  end

  @doc false
  defp find_spikes(_rates, _mean, std_dev, _threshold) when std_dev == 0, do: []

  defp find_spikes(rates, mean, std_dev, threshold) do
    upper_bound = mean + threshold * std_dev
    lower_bound = mean - threshold * std_dev

    rates
    |> Enum.filter(&spike?(&1, upper_bound, lower_bound))
    |> Enum.map(&classify_spike(&1, mean))
  end

  @doc false
  defp spike?(rate, upper_bound, lower_bound) do
    rate.funding_rate > upper_bound or rate.funding_rate < lower_bound
  end

  @doc false
  defp classify_spike(rate, mean) do
    direction = if rate.funding_rate > mean, do: :high, else: :low
    {direction, rate}
  end

  @doc """
  Compare funding rates across multiple exchanges/symbols.

  Returns rates sorted by funding rate (highest first), with annualized APR.

  ## Parameters

    * `rates` - List of FundingRate structs from different exchanges

  ## Returns

  List of maps with symbol, rate, and annualized APR, sorted by rate descending.

  ## Example

      rates = [
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001},
        %FundingRate{symbol: "ETH/USDT:USDT", funding_rate: 0.0002}
      ]

      CCXT.Trading.Funding.compare(rates)
      # => [
      #   %{symbol: "ETH/USDT:USDT", rate: 0.0002, apr: 0.219},
      #   %{symbol: "BTC/USDT:USDT", rate: 0.0001, apr: 0.1095}
      # ]

  """
  @spec compare([FundingRate.t()]) :: [%{symbol: String.t(), rate: float(), apr: float()}]
  def compare(rates) when is_list(rates) do
    rates
    |> Enum.reject(&is_nil(&1.funding_rate))
    |> Enum.map(fn rate ->
      %{
        symbol: rate.symbol,
        rate: rate.funding_rate,
        apr: annualize(rate.funding_rate)
      }
    end)
    |> Enum.sort_by(& &1.rate, :desc)
  end

  @doc """
  Calculate cumulative funding over a period.

  Sums funding rates to show total funding paid/received.

  ## Example

      CCXT.Trading.Funding.cumulative(rates)
      # => 0.00125  (total funding over period)

  """
  @spec cumulative([FundingRate.t()]) :: float()
  def cumulative(rates) when is_list(rates) do
    rates
    |> Enum.map(& &1.funding_rate)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
  end

  @doc """
  Calculate funding rate volatility (standard deviation).

  High volatility indicates unstable funding conditions.

  ## Example

      CCXT.Trading.Funding.volatility(rates)
      # => 0.00005

  """
  @spec volatility([FundingRate.t()]) :: float() | nil
  def volatility(rates) when is_list(rates) do
    valid_rates = Enum.reject(rates, &is_nil(&1.funding_rate))

    if length(valid_rates) < 2 do
      nil
    else
      mean = average(valid_rates)
      standard_deviation(valid_rates, mean)
    end
  end

  @doc """
  Check if current funding is favorable for a position direction.

  ## Parameters

    * `rate` - FundingRate struct
    * `direction` - Position direction (`:long` or `:short`)

  ## Returns

    * `true` if funding is favorable (you receive funding)
    * `false` if funding is unfavorable (you pay funding)

  ## Example

      # Positive funding = longs pay shorts
      CCXT.Trading.Funding.favorable?(%FundingRate{funding_rate: 0.0001}, :short)
      # => true

      CCXT.Trading.Funding.favorable?(%FundingRate{funding_rate: 0.0001}, :long)
      # => false

  """
  @spec favorable?(FundingRate.t(), :long | :short) :: boolean()
  def favorable?(%FundingRate{funding_rate: rate}, :long) when is_number(rate), do: rate < 0
  def favorable?(%FundingRate{funding_rate: rate}, :short) when is_number(rate), do: rate > 0
  def favorable?(%FundingRate{funding_rate: nil}, _direction), do: false

  # Calculate standard deviation of funding rates
  @doc false
  defp standard_deviation(rates, mean) do
    n = length(rates)

    variance =
      rates
      |> Enum.map(fn rate -> :math.pow(rate.funding_rate - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(n)

    :math.sqrt(variance)
  end
end
