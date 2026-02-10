defmodule CCXT.Trading.Sizing do
  @moduledoc """
  Position sizing calculations for trading systems.

  Pure functions for calculating position sizes based on risk parameters,
  account size, and volatility. Supports multiple sizing strategies.

  ## Example

      # Fixed fractional sizing (risk 1% of account)
      CCXT.Trading.Sizing.fixed_fractional(100_000, 0.01, 500)
      # => 2.0  (2 units where each unit has $500 max loss)

      # Kelly criterion
      CCXT.Trading.Sizing.kelly(0.55, 1.5)
      # => 0.183  (18.3% of bankroll)

  """

  @typedoc "Fraction of bankroll (0.0 to 1.0)"
  @type fraction :: float()

  @typedoc "Position size in units or currency"
  @type position_size :: float()

  # Guard for validating probability (0.0 to 1.0 inclusive)
  defguardp is_probability(p) when is_float(p) and p >= 0 and p <= 1

  # Guard for validating positive ratio
  defguardp is_positive_ratio(r) when is_float(r) and r > 0

  # Guard for validating Kelly fraction (0.0 to 1.0, exclusive of 0)
  defguardp is_kelly_fraction(f) when is_float(f) and f > 0 and f <= 1

  @doc """
  Calculate position size using fixed fractional method.

  Risk a fixed percentage of account equity per trade. This is one of
  the most common position sizing strategies.

  ## Parameters

    * `account_size` - Total account equity
    * `risk_percent` - Risk per trade as decimal (e.g., 0.01 = 1%)
    * `stop_distance` - Distance to stop loss in account currency per unit

  ## Example

      # $100k account, risk 1%, $500 stop distance per contract
      CCXT.Trading.Sizing.fixed_fractional(100_000, 0.01, 500)
      # => 2.0 contracts

  """
  @spec fixed_fractional(number(), fraction(), number()) :: position_size()
  def fixed_fractional(account_size, risk_percent, stop_distance)
      when is_number(account_size) and account_size > 0 and is_float(risk_percent) and risk_percent > 0 and
             risk_percent <= 1 and is_number(stop_distance) and stop_distance > 0 do
    risk_amount = account_size * risk_percent
    risk_amount / stop_distance
  end

  @doc """
  Calculate position size based on maximum loss amount.

  Determine how many units you can buy given a fixed maximum loss.

  ## Parameters

    * `max_loss` - Maximum acceptable loss in account currency
    * `stop_distance` - Distance to stop loss per unit

  ## Example

      # Max loss $1000, stop distance $250 per contract
      CCXT.Trading.Sizing.max_loss(1000, 250)
      # => 4.0 contracts

  """
  @spec max_loss(number(), number()) :: position_size()
  def max_loss(max_loss_amount, stop_distance)
      when is_number(max_loss_amount) and max_loss_amount > 0 and is_number(stop_distance) and stop_distance > 0 do
    max_loss_amount / stop_distance
  end

  @doc """
  Calculate optimal position size using Kelly criterion.

  The Kelly criterion maximizes long-term growth rate. In practice,
  fractional Kelly (0.25-0.5) is often used to reduce variance.

  ## Parameters

    * `win_rate` - Probability of winning (0.0 to 1.0)
    * `win_loss_ratio` - Average win divided by average loss
    * `kelly_fraction` - Fraction of Kelly to use (default: 0.5 = half Kelly)

  ## Returns

  Optimal bet size as fraction of bankroll. Returns 0 if expected value
  is negative.

  ## Example

      # 55% win rate, 1.5:1 reward/risk, half Kelly
      CCXT.Trading.Sizing.kelly(0.55, 1.5)
      # => 0.183 (bet 18.3% of bankroll)

      # Same with quarter Kelly for more conservative sizing
      CCXT.Trading.Sizing.kelly(0.55, 1.5, 0.25)
      # => 0.092 (bet 9.2% of bankroll)

  """
  @spec kelly(fraction(), float(), fraction()) :: fraction()
  def kelly(win_rate, win_loss_ratio, kelly_fraction \\ 0.5)

  def kelly(win_rate, win_loss_ratio, kelly_fraction)
      when is_probability(win_rate) and is_positive_ratio(win_loss_ratio) and is_kelly_fraction(kelly_fraction) do
    # Kelly formula: f* = (p * b - q) / b
    # where p = win probability, q = loss probability (1-p), b = win/loss ratio
    loss_rate = 1.0 - win_rate
    full_kelly = (win_rate * win_loss_ratio - loss_rate) / win_loss_ratio

    # Don't bet if expected value is negative
    if full_kelly <= 0 do
      0.0
    else
      kelly_fraction * full_kelly
    end
  end

  @doc """
  Calculate position size scaled by volatility.

  Adjusts position size inversely with volatility to maintain consistent
  risk across different market conditions.

  ## Parameters

    * `account_size` - Total account equity
    * `risk_percent` - Base risk per trade as decimal
    * `current_volatility` - Current volatility measure (e.g., ATR, std dev)
    * `target_volatility` - Target/baseline volatility for normal sizing

  ## Example

      # $100k account, 1% risk, current ATR 50, target ATR 30
      # Volatility is higher than target, so reduce position
      CCXT.Trading.Sizing.volatility_scaled(100_000, 0.01, 50, 30)
      # => 600.0 (reduced from $1000 base risk)

  """
  @spec volatility_scaled(number(), fraction(), number(), number()) :: position_size()
  def volatility_scaled(account_size, risk_percent, current_volatility, target_volatility)
      when is_number(account_size) and account_size > 0 and is_float(risk_percent) and risk_percent > 0 and
             risk_percent <= 1 and is_number(current_volatility) and current_volatility > 0 and
             is_number(target_volatility) and target_volatility > 0 do
    base_risk = account_size * risk_percent
    volatility_ratio = target_volatility / current_volatility
    base_risk * volatility_ratio
  end

  @doc """
  Calculate anti-martingale position adjustment.

  Increases position size after wins, decreases after losses.
  Helps let winners run while cutting losses.

  ## Parameters

    * `base_size` - Starting position size
    * `consecutive_wins` - Number of consecutive wins (negative for losses)
    * `scale_factor` - How much to adjust per win/loss (default: 0.25 = 25%)
    * `max_scale` - Maximum multiplier (default: 2.0)

  ## Example

      # Base 1 contract, 3 consecutive wins, 25% scaling
      CCXT.Trading.Sizing.anti_martingale(1.0, 3, 0.25)
      # => 1.75 contracts

      # Base 1 contract, 2 consecutive losses
      CCXT.Trading.Sizing.anti_martingale(1.0, -2, 0.25)
      # => 0.5 contracts

  """
  @spec anti_martingale(number(), integer(), fraction(), float()) :: position_size()
  def anti_martingale(base_size, consecutive_wins, scale_factor \\ 0.25, max_scale \\ 2.0)
      when is_number(base_size) and base_size > 0 and is_integer(consecutive_wins) and is_float(scale_factor) and
             scale_factor > 0 and is_float(max_scale) and max_scale > 1 do
    adjustment = 1.0 + consecutive_wins * scale_factor
    multiplier = max(1.0 / max_scale, min(max_scale, adjustment))
    base_size * multiplier
  end

  @doc """
  Calculate optimal f (optimal fixed fraction).

  Ralph Vince's Optimal f finds the fraction that maximizes geometric
  growth. This is more aggressive than Kelly.

  ## Parameters

    * `trades` - List of trade results (positive for wins, negative for losses)

  ## Returns

  Optimal fraction of account to risk per trade, or `nil` if insufficient data.

  ## Example

      trades = [100, -50, 75, -25, 150, -75, 200]
      CCXT.Trading.Sizing.optimal_f(trades)
      # => 0.38

  """
  @spec optimal_f([number()]) :: fraction() | nil
  def optimal_f(trades) when is_list(trades) do
    if length(trades) < 3 do
      nil
    else
      calculate_optimal_f(trades)
    end
  end

  # Golden ratio for golden section search
  @golden_ratio (1 + :math.sqrt(5)) / 2
  # Tolerance for convergence (0.1% precision)
  @search_tolerance 0.001

  @doc false
  # Validates trades have losses then searches for optimal f
  defp calculate_optimal_f(trades) do
    largest_loss = Enum.min(trades)

    if largest_loss >= 0 do
      nil
    else
      golden_section_search(trades, abs(largest_loss))
    end
  end

  @doc false
  # Golden section search for optimal f (more efficient than brute force)
  # Finds maximum of TWRR function in range [0.01, 0.99]
  defp golden_section_search(trades, largest_loss) do
    a = 0.01
    b = 0.99
    c = b - (b - a) / @golden_ratio
    d = a + (b - a) / @golden_ratio

    state = %{
      a: a,
      b: b,
      c: c,
      d: d,
      fc: calculate_twrr(trades, c, largest_loss),
      fd: calculate_twrr(trades, d, largest_loss)
    }

    do_golden_search(trades, largest_loss, state)
  end

  @doc false
  # Recursive golden section search iteration using state map
  defp do_golden_search(trades, largest_loss, %{a: a, b: b} = state) do
    if abs(b - a) < @search_tolerance do
      (a + b) / 2
    else
      new_state = narrow_search_interval(trades, largest_loss, state)
      do_golden_search(trades, largest_loss, new_state)
    end
  end

  @doc false
  # Narrows the search interval based on function values at probe points
  defp narrow_search_interval(trades, largest_loss, %{a: a, b: b, c: c, d: d, fc: fc, fd: fd}) do
    if fc > fd do
      new_b = d
      new_d = c
      new_c = new_b - (new_b - a) / @golden_ratio
      %{a: a, b: new_b, c: new_c, d: new_d, fc: calculate_twrr(trades, new_c, largest_loss), fd: fc}
    else
      new_a = c
      new_c = d
      new_d = new_a + (b - new_a) / @golden_ratio
      %{a: new_a, b: b, c: new_c, d: new_d, fc: fd, fd: calculate_twrr(trades, new_d, largest_loss)}
    end
  end

  @doc false
  # Calculates Terminal Wealth Relative Ratio (geometric mean of holding period returns)
  defp calculate_twrr(trades, f, largest_loss) do
    trades
    |> Enum.reduce(1.0, fn trade, acc ->
      holding_period_return = 1.0 + f * trade / largest_loss
      acc * max(0.0001, holding_period_return)
    end)
    |> :math.pow(1 / length(trades))
  end
end
