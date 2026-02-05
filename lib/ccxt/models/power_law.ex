defmodule CCXT.Models.PowerLaw do
  @moduledoc """
  Bitcoin Power Law model calculations.

  The Power Law model describes Bitcoin's long-term price trend as a function
  of time since the genesis block. It provides a framework for understanding
  where current price sits relative to the historical trend.

  ## Model

  The power law relationship: `log(price) = a + b * log(days_since_genesis)`

  Where:
    * `a` - Intercept (approximately -17.01)
    * `b` - Slope (approximately 5.82)

  ## Example

      # Get fair value for today
      CCXT.Models.PowerLaw.fair_value()
      # => 85000.0

      # Calculate z-score for current price
      CCXT.Models.PowerLaw.z_score(95000.0)
      # => 0.35  (35% of a standard deviation above trend)

  ## References

  - Harold Christopher Burger's original research
  - Giovanni Santostasi's power law corridor model

  """

  # Bitcoin genesis block date
  @btc_genesis ~D[2009-01-03]

  # Power law coefficients (fitted from historical data)
  # log10(price) = a + b * log10(days)
  @coefficient_a -17.01
  @coefficient_b 5.82

  # Historical standard deviation of log residuals (approximately)
  @historical_std_dev 0.35

  @doc """
  Calculate the fair value price based on the power law model.

  Returns the model's predicted price for a given date or number of days
  since the genesis block.

  ## Parameters

    * `date_or_days` - Either a `Date`, `DateTime`, or integer days since genesis.
                       Defaults to today.

  ## Example

      CCXT.Models.PowerLaw.fair_value()
      # => 85000.0  (today's fair value)

      CCXT.Models.PowerLaw.fair_value(~D[2025-01-01])
      # => 75000.0

      CCXT.Models.PowerLaw.fair_value(6000)
      # => 80000.0  (6000 days after genesis)

  """
  @spec fair_value(Date.t() | DateTime.t() | pos_integer() | nil) :: float()
  def fair_value(date_or_days \\ nil)

  def fair_value(nil), do: fair_value(Date.utc_today())

  def fair_value(%Date{} = date) do
    days = Date.diff(date, @btc_genesis)
    fair_value(days)
  end

  def fair_value(%DateTime{} = datetime) do
    date = DateTime.to_date(datetime)
    fair_value(date)
  end

  def fair_value(days) when is_integer(days) and days > 0 do
    # log10(price) = a + b * log10(days)
    log_price = @coefficient_a + @coefficient_b * :math.log10(days)
    :math.pow(10, log_price)
  end

  @doc """
  Calculate z-score: how many standard deviations price is from fair value.

  A z-score indicates:
    * `z > 0` - Price is above the trend (potentially overvalued)
    * `z < 0` - Price is below the trend (potentially undervalued)
    * `|z| > 2` - Price is in extreme territory (±2 standard deviations)

  ## Parameters

    * `price` - Current BTC price in USD
    * `date_or_days` - Date, DateTime, or days since genesis (default: today)

  ## Example

      CCXT.Models.PowerLaw.z_score(95000.0)
      # => 0.35

      CCXT.Models.PowerLaw.z_score(50000.0)
      # => -0.82

  """
  @spec z_score(number(), Date.t() | DateTime.t() | pos_integer() | nil) :: float()
  def z_score(price, date_or_days \\ nil) when is_number(price) and price > 0 do
    fair = fair_value(date_or_days)
    log_price = :math.log10(price)
    log_fair = :math.log10(fair)

    (log_price - log_fair) / @historical_std_dev
  end

  @doc """
  Calculate the power law support price (lower band).

  This is typically 1-2 standard deviations below the fair value,
  representing historical support levels.

  ## Parameters

    * `date_or_days` - Date, DateTime, or days since genesis (default: today)
    * `deviations` - Number of standard deviations below (default: 1.5)

  ## Example

      CCXT.Models.PowerLaw.support()
      # => 45000.0

  """
  @spec support(Date.t() | DateTime.t() | pos_integer() | nil, number()) :: float()
  def support(date_or_days \\ nil, deviations \\ 1.5) do
    fair = fair_value(date_or_days)
    log_fair = :math.log10(fair)
    log_support = log_fair - deviations * @historical_std_dev

    :math.pow(10, log_support)
  end

  @doc """
  Calculate the power law resistance price (upper band).

  This is typically 1-2 standard deviations above the fair value,
  representing historical resistance/bubble territory.

  ## Parameters

    * `date_or_days` - Date, DateTime, or days since genesis (default: today)
    * `deviations` - Number of standard deviations above (default: 1.5)

  ## Example

      CCXT.Models.PowerLaw.resistance()
      # => 150000.0

  """
  @spec resistance(Date.t() | DateTime.t() | pos_integer() | nil, number()) :: float()
  def resistance(date_or_days \\ nil, deviations \\ 1.5) do
    fair = fair_value(date_or_days)
    log_fair = :math.log10(fair)
    log_resistance = log_fair + deviations * @historical_std_dev

    :math.pow(10, log_resistance)
  end

  @doc """
  Get the number of days since Bitcoin's genesis block.

  ## Example

      CCXT.Models.PowerLaw.days_since_genesis()
      # => 5845

      CCXT.Models.PowerLaw.days_since_genesis(~D[2025-01-01])
      # => 5842

  """
  @spec days_since_genesis(Date.t() | DateTime.t() | nil) :: integer()
  def days_since_genesis(date \\ nil)

  def days_since_genesis(nil), do: days_since_genesis(Date.utc_today())

  def days_since_genesis(%Date{} = date) do
    Date.diff(date, @btc_genesis)
  end

  def days_since_genesis(%DateTime{} = datetime) do
    datetime |> DateTime.to_date() |> days_since_genesis()
  end

  @doc """
  Classify the current price position in the power law corridor.

  ## Returns

    * `:extreme_low` - Below -2 std dev (rare buying opportunity)
    * `:undervalued` - Between -2 and -1 std dev
    * `:fair` - Within ±1 std dev of trend
    * `:overvalued` - Between +1 and +2 std dev
    * `:extreme_high` - Above +2 std dev (bubble territory)

  ## Example

      CCXT.Models.PowerLaw.classify(95000.0)
      # => :fair

      CCXT.Models.PowerLaw.classify(200000.0)
      # => :overvalued

  """
  @spec classify(number(), Date.t() | DateTime.t() | pos_integer() | nil) ::
          :extreme_low | :undervalued | :fair | :overvalued | :extreme_high
  def classify(price, date_or_days \\ nil) when is_number(price) and price > 0 do
    z = z_score(price, date_or_days)

    cond do
      z < -2.0 -> :extreme_low
      z < -1.0 -> :undervalued
      z > 2.0 -> :extreme_high
      z > 1.0 -> :overvalued
      true -> :fair
    end
  end

  @doc """
  Get the Bitcoin genesis block date.

  ## Example

      CCXT.Models.PowerLaw.genesis_date()
      # => ~D[2009-01-03]

  """
  @spec genesis_date() :: Date.t()
  def genesis_date, do: @btc_genesis
end
