defmodule CCXT.Greeks do
  @moduledoc """
  Portfolio Greeks aggregation and analysis.

  Pure functions for aggregating option Greeks across positions
  and analyzing portfolio-level risk exposure.

  ## Greek Definitions

    * **Delta** - Rate of change of option price with respect to underlying
    * **Gamma** - Rate of change of delta with respect to underlying
    * **Theta** - Time decay (value lost per day)
    * **Vega** - Sensitivity to implied volatility changes

  ## Example

      positions = [
        %{delta: 0.5, gamma: 0.02, theta: -10.0, vega: 25.0, quantity: 10},
        %{delta: -0.3, gamma: 0.015, theta: -8.0, vega: 20.0, quantity: 5}
      ]

      CCXT.Greeks.position_greeks(positions)
      # => %{delta: 3.5, gamma: 0.275, theta: -140.0, vega: 350.0}

  """

  alias CCXT.Types.Option

  @typedoc "Aggregated portfolio Greeks"
  @type portfolio_greeks :: %{delta: float(), gamma: float(), theta: float(), vega: float()}

  @typedoc "Position with Greeks data for aggregation"
  @type position :: %{
          optional(:symbol) => String.t(),
          optional(:delta) => number(),
          optional(:gamma) => number(),
          optional(:theta) => number(),
          optional(:vega) => number(),
          optional(:quantity) => number()
        }

  @doc """
  Aggregate Greeks across multiple positions.

  Calculates the net portfolio Greeks by summing individual position Greeks
  weighted by quantity.

  ## Parameters

    * `positions` - List of positions, each with `:delta`, `:gamma`, `:theta`,
      `:vega`, and `:quantity` fields. Quantity can be negative for short positions.

  ## Returns

  Map with aggregated `:delta`, `:gamma`, `:theta`, `:vega`.

  ## Example

      positions = [
        %{delta: 0.5, gamma: 0.02, theta: -10.0, vega: 25.0, quantity: 10},
        %{delta: -0.3, gamma: 0.015, theta: -8.0, vega: 20.0, quantity: -5}
      ]

      CCXT.Greeks.position_greeks(positions)
      # => %{delta: 6.5, gamma: 0.125, theta: -60.0, vega: 150.0}

  """
  @spec position_greeks([position()]) :: portfolio_greeks()
  def position_greeks(positions) when is_list(positions) do
    Enum.reduce(positions, %{delta: 0.0, gamma: 0.0, theta: 0.0, vega: 0.0}, fn pos, acc ->
      quantity = pos[:quantity] || 1.0

      %{
        delta: acc.delta + (pos[:delta] || 0.0) * quantity,
        gamma: acc.gamma + (pos[:gamma] || 0.0) * quantity,
        theta: acc.theta + (pos[:theta] || 0.0) * quantity,
        vega: acc.vega + (pos[:vega] || 0.0) * quantity
      }
    end)
  end

  @doc """
  Calculate dollar delta (delta exposure in currency terms).

  ## Parameters

    * `delta` - Portfolio delta
    * `underlying_price` - Current price of underlying
    * `contract_multiplier` - Contract multiplier (default: 1)

  ## Example

      CCXT.Greeks.dollar_delta(5.0, 50_000, 1)
      # => 250_000.0

  """
  @spec dollar_delta(number(), number(), number()) :: float()
  def dollar_delta(delta, underlying_price, contract_multiplier \\ 1)
      when is_number(delta) and is_number(underlying_price) and is_number(contract_multiplier) do
    delta * underlying_price * contract_multiplier
  end

  @doc """
  Calculate dollar gamma (gamma exposure in currency terms).

  Shows how much delta will change for a 1% move in underlying.

  ## Parameters

    * `gamma` - Portfolio gamma
    * `underlying_price` - Current price of underlying
    * `contract_multiplier` - Contract multiplier (default: 1)

  ## Example

      CCXT.Greeks.dollar_gamma(0.5, 50_000)
      # => 250.0 (delta change for 1% move)

  """
  @spec dollar_gamma(number(), number(), number()) :: float()
  def dollar_gamma(gamma, underlying_price, contract_multiplier \\ 1)
      when is_number(gamma) and is_number(underlying_price) and is_number(contract_multiplier) do
    # For a 1% move in underlying
    gamma * underlying_price * 0.01 * contract_multiplier
  end

  @doc """
  Check if portfolio is delta neutral within tolerance.

  ## Parameters

    * `delta` - Portfolio delta
    * `tolerance` - Maximum acceptable delta (default: 0.1)

  ## Example

      CCXT.Greeks.delta_neutral?(0.05, 0.1)
      # => true

  """
  @spec delta_neutral?(number(), number()) :: boolean()
  def delta_neutral?(delta, tolerance \\ 0.1) when is_number(delta) and is_number(tolerance) and tolerance >= 0 do
    abs(delta) <= tolerance
  end

  @doc """
  Calculate hedge ratio to neutralize delta.

  Returns the number of underlying units to buy (positive) or sell (negative)
  to achieve delta neutrality.

  ## Parameters

    * `portfolio_delta` - Current portfolio delta
    * `hedge_delta` - Delta of the hedging instrument (default: 1.0 for spot/futures)

  ## Example

      # Portfolio has delta of 5.0, hedge with futures (delta = 1)
      CCXT.Greeks.hedge_ratio(5.0)
      # => -5.0 (sell 5 futures)

  """
  @spec hedge_ratio(number(), number()) :: float()
  def hedge_ratio(portfolio_delta, hedge_delta \\ 1.0)
      when is_number(portfolio_delta) and is_number(hedge_delta) and hedge_delta != 0 do
    -portfolio_delta / hedge_delta
  end

  @doc """
  Extract Greeks from option chain for aggregation.

  Converts an option chain map to a list of position maps suitable
  for `position_greeks/1`.

  ## Parameters

    * `chain` - Map of symbol => Option structs
    * `positions` - Map of symbol => quantity (positive for long, negative for short)

  ## Example

      chain = %{"BTC-31JAN26-84000-C" => %Option{...}}
      positions = %{"BTC-31JAN26-84000-C" => 10}

      CCXT.Greeks.from_chain(chain, positions)
      # => [%{delta: 0.5, gamma: 0.02, ..., quantity: 10}]

  """
  @spec from_chain(%{String.t() => Option.t()}, %{String.t() => number()}) :: [position()]
  def from_chain(chain, positions) when is_map(chain) and is_map(positions) do
    positions
    |> Enum.filter(fn {symbol, _qty} -> Map.has_key?(chain, symbol) end)
    |> Enum.map(fn {symbol, quantity} ->
      option = chain[symbol]
      raw = option.raw || %{}

      %{
        symbol: symbol,
        delta: raw["delta"] || 0.0,
        gamma: raw["gamma"] || 0.0,
        theta: raw["theta"] || 0.0,
        vega: raw["vega"] || 0.0,
        quantity: quantity
      }
    end)
  end

  @doc """
  Calculate portfolio theta in daily terms.

  Shows how much value the portfolio loses per day from time decay.

  ## Parameters

    * `positions` - List of positions with Greeks

  ## Example

      CCXT.Greeks.daily_theta(positions)
      # => -150.0 (losing $150/day to theta)

  """
  @spec daily_theta([position()]) :: float()
  def daily_theta(positions) when is_list(positions) do
    position_greeks(positions).theta
  end

  @doc """
  Calculate portfolio vega exposure.

  Shows how much portfolio value changes for a 1% change in IV.

  ## Parameters

    * `positions` - List of positions with Greeks

  ## Example

      CCXT.Greeks.vega_exposure(positions)
      # => 500.0 (gain $500 for +1% IV)

  """
  @spec vega_exposure([position()]) :: float()
  def vega_exposure(positions) when is_list(positions) do
    position_greeks(positions).vega
  end

  @doc """
  Calculate gamma scalping potential.

  Estimates profit from gamma if underlying moves by a given percentage.

  ## Parameters

    * `gamma` - Portfolio gamma
    * `underlying_price` - Current underlying price
    * `expected_move_pct` - Expected move as percentage (e.g., 2.0 for 2%)

  ## Returns

  Estimated P&L from gamma exposure.

  ## Example

      # Gamma of 0.1, BTC at $50k, expecting 2% move
      CCXT.Greeks.gamma_pnl(0.1, 50_000, 2.0)
      # => 500.0

  """
  @spec gamma_pnl(number(), number(), number()) :: float()
  def gamma_pnl(gamma, underlying_price, expected_move_pct)
      when is_number(gamma) and is_number(underlying_price) and is_number(expected_move_pct) do
    move = underlying_price * (expected_move_pct / 100)
    0.5 * gamma * move * move
  end
end
