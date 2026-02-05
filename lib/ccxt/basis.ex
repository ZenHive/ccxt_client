defmodule CCXT.Basis do
  @moduledoc """
  Cash-and-carry basis calculations for spot/perpetual arbitrage.

  Pure functions for calculating basis between spot and derivative prices,
  annualized yields, and futures curve analysis.

  ## Terminology

    * **Basis** - Price difference between derivative and spot
    * **Contango** - Futures trading above spot (positive basis)
    * **Backwardation** - Futures trading below spot (negative basis)

  ## Example

      CCXT.Basis.spot_perp(50_000, 50_100)
      # => %{absolute: 100.0, percent: 0.2, direction: :contango}

      CCXT.Basis.annualized(50_000, 50_100, 30)
      # => 0.0243 (2.43% annualized yield)

  """

  @days_per_year 365

  @typedoc "Market structure direction relative to spot price"
  @type direction :: :contango | :backwardation | :flat

  @typedoc "Basis calculation result"
  @type basis_result :: %{absolute: float(), percent: float(), direction: direction()}

  @typedoc "Enriched futures contract with basis metrics"
  @type futures_point :: %{
          expiry: Date.t(),
          price: number(),
          days_to_expiry: integer(),
          basis: number(),
          basis_pct: float(),
          annualized: float()
        }

  @typedoc "Exchange basis comparison result"
  @type exchange_basis :: %{
          exchange: atom() | String.t(),
          basis: number(),
          basis_pct: float(),
          implied_apr: float()
        }

  @doc """
  Calculate basis between spot and perpetual/futures price.

  ## Parameters

    * `spot_price` - Current spot price
    * `derivative_price` - Perpetual or futures price

  ## Returns

  Map with:
    * `:absolute` - Absolute difference (derivative - spot)
    * `:percent` - Percentage difference
    * `:direction` - `:contango` (positive) or `:backwardation` (negative)

  ## Example

      CCXT.Basis.spot_perp(50_000, 50_100)
      # => %{absolute: 100.0, percent: 0.2, direction: :contango}

      CCXT.Basis.spot_perp(50_000, 49_900)
      # => %{absolute: -100.0, percent: -0.2, direction: :backwardation}

  """
  @spec spot_perp(number(), number()) :: basis_result()
  def spot_perp(spot_price, derivative_price)
      when is_number(spot_price) and spot_price > 0 and is_number(derivative_price) and derivative_price > 0 do
    absolute = derivative_price - spot_price
    percent = absolute / spot_price * 100

    direction =
      cond do
        absolute > 0 -> :contango
        absolute < 0 -> :backwardation
        true -> :flat
      end

    %{
      absolute: absolute * 1.0,
      percent: percent,
      direction: direction
    }
  end

  @doc """
  Calculate annualized basis yield.

  For a futures contract with known expiry, calculates the annualized
  return from a cash-and-carry trade.

  ## Parameters

    * `spot_price` - Current spot price
    * `futures_price` - Futures price
    * `days_to_expiry` - Days until futures expiration

  ## Returns

  Annualized yield as decimal (e.g., 0.05 = 5% APY).

  ## Example

      # 0.2% basis over 30 days annualizes to ~2.43%
      CCXT.Basis.annualized(50_000, 50_100, 30)
      # => 0.0243

  """
  @spec annualized(number(), number(), pos_integer()) :: float()
  def annualized(spot_price, futures_price, days_to_expiry)
      when is_number(spot_price) and spot_price > 0 and is_number(futures_price) and futures_price > 0 and
             is_integer(days_to_expiry) and days_to_expiry > 0 do
    basis_pct = (futures_price - spot_price) / spot_price
    basis_pct * (@days_per_year / days_to_expiry)
  end

  @doc """
  Build futures curve from multiple contracts.

  Takes a list of futures with expiry dates and prices, returns the
  term structure sorted by expiry.

  ## Parameters

    * `spot_price` - Current spot price
    * `futures` - List of maps with `:expiry` (Date) and `:price` fields

  ## Returns

  List of maps sorted by expiry with basis and annualized yield added.

  ## Example

      futures = [
        %{expiry: ~D[2026-03-28], price: 51_000},
        %{expiry: ~D[2026-01-31], price: 50_500}
      ]

      CCXT.Basis.futures_curve(50_000, futures)
      # => [
      #   %{expiry: ~D[2026-01-31], price: 50_500, basis: 500, basis_pct: 1.0, annualized: 0.122},
      #   %{expiry: ~D[2026-03-28], price: 51_000, basis: 1000, basis_pct: 2.0, annualized: 0.085}
      # ]

  """
  @spec futures_curve(number(), [map()]) :: [futures_point()]
  def futures_curve(spot_price, futures) when is_number(spot_price) and spot_price > 0 and is_list(futures) do
    today = Date.utc_today()

    futures
    |> Enum.map(fn future -> enrich_future(future, spot_price, today) end)
    |> Enum.filter(fn f -> f.days_to_expiry >= 0 end)
    |> Enum.sort_by(& &1.expiry, Date)
  end

  @doc false
  # Adds calculated basis metrics (days to expiry, basis, annualized yield) to a future contract
  defp enrich_future(future, spot_price, today) do
    expiry = future[:expiry] || future["expiry"]
    price = future[:price] || future["price"]
    days = Date.diff(expiry, today)
    basis = price - spot_price
    basis_pct = basis / spot_price * 100

    annualized_yield =
      if days > 0 do
        basis / spot_price * (@days_per_year / days)
      else
        0.0
      end

    %{
      expiry: expiry,
      price: price,
      days_to_expiry: days,
      basis: basis,
      basis_pct: basis_pct,
      annualized: annualized_yield
    }
  end

  @doc """
  Calculate implied funding rate from basis.

  For perpetuals, basis tends to converge to spot via funding payments.
  This estimates the implied 8-hour funding rate.

  ## Parameters

    * `spot_price` - Current spot price
    * `perp_price` - Perpetual price
    * `funding_interval_hours` - Hours between funding (default: 8)

  ## Returns

  Implied funding rate for one period.

  ## Example

      CCXT.Basis.implied_funding(50_000, 50_050)
      # => 0.000333 (0.033% per 8 hours)

  """
  @spec implied_funding(number(), number(), pos_integer()) :: float()
  def implied_funding(spot_price, perp_price, funding_interval_hours \\ 8)
      when is_number(spot_price) and spot_price > 0 and is_number(perp_price) and perp_price > 0 and
             is_integer(funding_interval_hours) and funding_interval_hours > 0 do
    # Basis as a percentage
    basis_pct = (perp_price - spot_price) / spot_price

    # Number of funding periods per day
    periods_per_day = 24 / funding_interval_hours

    # Implied rate = basis / periods per day (assuming basis converges in ~1 day)
    basis_pct / periods_per_day
  end

  @doc """
  Compare basis across multiple exchanges.

  ## Parameters

    * `exchanges` - List of maps with `:exchange`, `:spot`, and `:perp` fields

  ## Returns

  List sorted by basis (highest first) with calculated metrics.

  ## Example

      exchanges = [
        %{exchange: :binance, spot: 50_000, perp: 50_100},
        %{exchange: :okx, spot: 50_000, perp: 50_150}
      ]

      CCXT.Basis.compare(exchanges)
      # => [
      #   %{exchange: :okx, basis: 150, basis_pct: 0.3, implied_apr: 109.5},
      #   %{exchange: :binance, basis: 100, basis_pct: 0.2, implied_apr: 73.0}
      # ]

  """
  @spec compare([map()]) :: [exchange_basis()]
  def compare(exchanges) when is_list(exchanges) do
    exchanges
    |> Enum.map(&calculate_exchange_basis/1)
    |> Enum.sort_by(& &1.basis, :desc)
  end

  @doc false
  # Calculates basis metrics for a single exchange entry (spot/perp spread and implied APR)
  defp calculate_exchange_basis(exchange) do
    spot = exchange[:spot] || exchange["spot"]
    perp = exchange[:perp] || exchange["perp"]
    name = exchange[:exchange] || exchange["exchange"]

    basis = perp - spot
    basis_pct = basis / spot * 100
    # Assume basis converges in ~1 day, annualized by days per year
    # Use decimal rate (basis/spot), not percentage (basis_pct)
    implied_apr = basis / spot * @days_per_year * 100

    %{
      exchange: name,
      basis: basis,
      basis_pct: basis_pct,
      implied_apr: implied_apr
    }
  end

  @doc """
  Check if basis is at arbitrage-worthy levels.

  ## Parameters

    * `spot_price` - Current spot price
    * `derivative_price` - Perpetual or futures price
    * `threshold_pct` - Minimum basis percentage to consider (default: 0.1 = 0.1%)

  ## Example

      CCXT.Basis.arbitrage_opportunity?(50_000, 50_100, 0.1)
      # => true (0.2% basis > 0.1% threshold)

  """
  @spec arbitrage_opportunity?(number(), number(), float()) :: boolean()
  def arbitrage_opportunity?(spot_price, derivative_price, threshold_pct \\ 0.1)
      when is_number(spot_price) and spot_price > 0 and is_number(derivative_price) and derivative_price > 0 and
             is_float(threshold_pct) do
    basis_pct = abs(derivative_price - spot_price) / spot_price * 100
    basis_pct >= threshold_pct
  end
end
