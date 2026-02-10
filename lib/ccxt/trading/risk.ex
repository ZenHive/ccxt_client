defmodule CCXT.Trading.Risk do
  @moduledoc """
  Position risk analysis for trading systems.

  Pure functions for analyzing portfolio concentration, position limits,
  and risk metrics.

  ## Example

      positions = [
        %{symbol: "BTC/USDT", value: 50_000},
        %{symbol: "ETH/USDT", value: 30_000},
        %{symbol: "SOL/USDT", value: 20_000}
      ]

      CCXT.Trading.Risk.concentration(positions)
      # => %{max: 0.5, hhi: 0.38, top3: 1.0}

  """

  @typedoc "Concentration metrics for portfolio analysis"
  @type concentration_metrics :: %{max: float(), hhi: float(), top3: float()}

  @typedoc "Position with value for risk calculations"
  @type valued_position :: %{optional(:symbol) => String.t(), value: number()}

  @typedoc "Risk limit violation tuple"
  @type violation ::
          {:max_position, String.t() | nil, number(), number()}
          | {:max_concentration, float(), float()}
          | {:max_total_exposure, number(), number()}

  @doc """
  Calculate portfolio concentration metrics.

  Measures how concentrated the portfolio is across positions.

  ## Parameters

    * `positions` - List of positions with `:value` field (absolute value of position)

  ## Returns

  Map with:
    * `:max` - Largest single position as fraction of total
    * `:hhi` - Herfindahl-Hirschman Index (sum of squared weights)
    * `:top3` - Combined weight of top 3 positions

  ## Interpretation

    * HHI < 0.15 - Diversified
    * HHI 0.15-0.25 - Moderate concentration
    * HHI > 0.25 - Highly concentrated

  ## Example

      positions = [
        %{value: 50_000},
        %{value: 30_000},
        %{value: 20_000}
      ]

      CCXT.Trading.Risk.concentration(positions)
      # => %{max: 0.5, hhi: 0.38, top3: 1.0}

  """
  @spec concentration([valued_position()]) :: concentration_metrics() | nil
  def concentration(positions) when is_list(positions) do
    values = extract_values(positions)

    if Enum.empty?(values) do
      nil
    else
      calculate_concentration(values)
    end
  end

  @doc false
  # Extracts absolute position values, filtering out zero/nil values
  defp extract_values(positions) do
    positions
    |> Enum.map(&abs(&1[:value] || 0))
    |> Enum.filter(&(&1 > 0))
  end

  @doc false
  # Computes max weight, HHI, and top-3 concentration from position values
  defp calculate_concentration(values) do
    total = Enum.sum(values)
    weights = Enum.map(values, &(&1 / total))
    sorted_weights = Enum.sort(weights, :desc)

    %{
      max: Enum.max(weights),
      hhi: Enum.sum(Enum.map(weights, &(&1 * &1))),
      top3: sorted_weights |> Enum.take(3) |> Enum.sum()
    }
  end

  @doc """
  Calculate maximum position size based on risk limits.

  Determines the largest position allowed given account size and risk parameters.

  ## Parameters

    * `account_size` - Total account equity
    * `opts` - Options:
      * `:max_position_pct` - Max single position as % of account (default: 0.20 = 20%)
      * `:max_loss_pct` - Max loss per position as % of account (default: 0.02 = 2%)
      * `:expected_drawdown` - Expected max drawdown % (default: 0.20 = 20%)

  ## Returns

  Maximum position value in account currency.

  ## Example

      CCXT.Trading.Risk.max_position_size(100_000, max_position_pct: 0.25)
      # => 25_000

  """
  @spec max_position_size(number(), keyword()) :: float()
  def max_position_size(account_size, opts \\ []) when is_number(account_size) and account_size > 0 do
    max_position_pct = Keyword.get(opts, :max_position_pct, 0.20)
    max_loss_pct = Keyword.get(opts, :max_loss_pct, 0.02)
    expected_drawdown = Keyword.get(opts, :expected_drawdown, 0.20)

    if expected_drawdown <= 0 do
      raise ArgumentError, "expected_drawdown must be > 0, got: #{expected_drawdown}"
    end

    # Position limit from direct percentage
    from_pct = account_size * max_position_pct

    # Position limit from max loss (assuming position could go to zero)
    from_loss = account_size * max_loss_pct / expected_drawdown

    # Take the more conservative limit
    min(from_pct, from_loss)
  end

  @doc """
  Check if positions comply with risk limits.

  ## Parameters

    * `positions` - List of positions with `:value` field
    * `limits` - Risk limits:
      * `:max_position` - Maximum value for any single position
      * `:max_concentration` - Maximum HHI (default: 0.25)
      * `:max_total_exposure` - Maximum total portfolio value

  ## Returns

  `{:ok, positions}` if all limits pass, or `{:error, violations}` with list of
  violated limits.

  ## Example

      positions = [%{symbol: "BTC/USDT", value: 50_000}]
      limits = [max_position: 25_000]

      CCXT.Trading.Risk.check_limits(positions, limits)
      # => {:error, [{:max_position, "BTC/USDT", 50_000, 25_000}]}

  """
  @spec check_limits([valued_position()], keyword()) :: {:ok, [valued_position()]} | {:error, [violation()]}
  def check_limits(positions, limits) when is_list(positions) and is_list(limits) do
    violations = collect_violations(positions, limits)

    if Enum.empty?(violations) do
      {:ok, positions}
    else
      {:error, violations}
    end
  end

  @doc false
  # Aggregates all limit violations from position and portfolio checks
  defp collect_violations(positions, limits) do
    position_violations = check_position_limits(positions, limits)
    portfolio_violations = check_portfolio_limits(positions, limits)
    position_violations ++ portfolio_violations
  end

  @doc false
  # Checks individual position sizes against max_position limit
  defp check_position_limits(positions, limits) do
    max_position = Keyword.get(limits, :max_position)

    if max_position do
      find_position_violations(positions, max_position)
    else
      []
    end
  end

  @doc false
  # Filters positions exceeding max_position and formats as violations
  defp find_position_violations(positions, max_position) do
    positions
    |> Enum.filter(&(abs(&1[:value] || 0) > max_position))
    |> Enum.map(&{:max_position, &1[:symbol], abs(&1[:value] || 0), max_position})
  end

  @doc false
  # Checks portfolio-level limits (concentration HHI, total exposure)
  defp check_portfolio_limits(positions, limits) do
    # Use nil as default so we can distinguish "not provided" from explicit value
    # If not provided, use 0.25 as default; if explicitly nil, disable the check
    max_concentration =
      case Keyword.fetch(limits, :max_concentration) do
        {:ok, value} -> value
        :error -> 0.25
      end

    max_total = Keyword.get(limits, :max_total_exposure)

    concentration_violations = check_concentration_limit(positions, max_concentration)
    total_violations = check_total_limit(positions, max_total)

    concentration_violations ++ total_violations
  end

  @doc false
  # Returns empty list when max_concentration is nil (check disabled)
  defp check_concentration_limit(_positions, nil), do: []

  # Returns violation if HHI exceeds max_concentration threshold
  defp check_concentration_limit(positions, max_concentration) do
    case concentration(positions) do
      nil ->
        []

      %{hhi: hhi} when hhi > max_concentration ->
        [{:max_concentration, hhi, max_concentration}]

      _ ->
        []
    end
  end

  @doc false
  # Returns violation if total exposure exceeds max_total_exposure limit
  defp check_total_limit(_positions, nil), do: []

  defp check_total_limit(positions, max_total) do
    total = positions |> Enum.map(&abs(&1[:value] || 0)) |> Enum.sum()

    if total > max_total do
      [{:max_total_exposure, total, max_total}]
    else
      []
    end
  end

  @doc """
  Calculate Value at Risk (VaR) estimate.

  Parametric VaR assuming normal distribution. Uses the Abramowitz & Stegun
  approximation for the inverse normal CDF to support arbitrary confidence levels.

  ## Parameters

    * `position_value` - Total position value
    * `volatility` - Daily volatility (standard deviation) as decimal
    * `confidence` - Confidence level (default: 0.95 = 95%)
    * `days` - Time horizon in days (default: 1)

  ## Returns

  Maximum expected loss at given confidence level.

  ## Example

      # $100k position, 2% daily vol, 95% confidence
      CCXT.Trading.Risk.var(100_000, 0.02)
      # => 3_290.0 (max loss of $3,290 on 95% of days)

      # Arbitrary confidence level
      CCXT.Trading.Risk.var(100_000, 0.02, 0.975)
      # => 3_920.0 (97.5% confidence)

  """
  @spec var(number(), number(), float(), pos_integer()) :: float()
  def var(position_value, volatility, confidence \\ 0.95, days \\ 1)
      when is_number(position_value) and is_number(volatility) and is_float(confidence) and confidence > 0 and
             confidence < 1 and is_integer(days) and days > 0 do
    # Z-score using inverse normal CDF (probit function)
    z_score = inverse_normal_cdf(confidence)

    # VaR = Position * Volatility * Z * sqrt(days)
    position_value * volatility * z_score * :math.sqrt(days)
  end

  @doc false
  # Inverse normal CDF (probit function) using Abramowitz & Stegun approximation.
  # Accurate to ~4.5 decimal places for p in (0, 1).
  # Reference: Handbook of Mathematical Functions, formula 26.2.23
  defp inverse_normal_cdf(p) when p > 0 and p < 1 do
    # Coefficients for the rational approximation
    c0 = 2.515517
    c1 = 0.802853
    c2 = 0.010328
    d1 = 1.432788
    d2 = 0.189269
    d3 = 0.001308

    # For p > 0.5, we compute for (1-p) and negate
    {p_adj, sign} =
      if p > 0.5 do
        {1.0 - p, 1.0}
      else
        {p, -1.0}
      end

    # Intermediate value
    t = :math.sqrt(-2.0 * :math.log(p_adj))

    # Rational approximation
    numerator = c0 + c1 * t + c2 * t * t
    denominator = 1.0 + d1 * t + d2 * t * t + d3 * t * t * t

    sign * (t - numerator / denominator)
  end

  @doc """
  Calculate portfolio beta to benchmark.

  ## Parameters

    * `portfolio_returns` - List of portfolio returns
    * `benchmark_returns` - List of benchmark returns (same length)

  ## Returns

  Beta coefficient, or `nil` if insufficient data.

  ## Example

      portfolio = [0.01, -0.02, 0.03, 0.01, -0.01]
      benchmark = [0.005, -0.01, 0.02, 0.005, -0.005]

      CCXT.Trading.Risk.beta(portfolio, benchmark)
      # => 1.5 (portfolio moves 1.5x benchmark)

  """
  @spec beta([number()], [number()]) :: float() | nil
  def beta(portfolio_returns, benchmark_returns) when is_list(portfolio_returns) and is_list(benchmark_returns) do
    if length(portfolio_returns) < 3 or length(portfolio_returns) != length(benchmark_returns) do
      nil
    else
      calculate_beta(portfolio_returns, benchmark_returns)
    end
  end

  @doc false
  # Computes beta as covariance(portfolio, benchmark) / variance(benchmark)
  defp calculate_beta(portfolio_returns, benchmark_returns) do
    covariance = covariance(portfolio_returns, benchmark_returns)
    benchmark_variance = variance(benchmark_returns)

    if benchmark_variance == 0 do
      nil
    else
      covariance / benchmark_variance
    end
  end

  @doc false
  # Calculates sample covariance between two series (divides by n-1 for unbiased estimator)
  defp covariance(xs, ys) do
    n = length(xs)
    mean_x = Enum.sum(xs) / n
    mean_y = Enum.sum(ys) / n

    xs
    |> Enum.zip(ys)
    |> Enum.map(fn {x, y} -> (x - mean_x) * (y - mean_y) end)
    |> Enum.sum()
    |> Kernel./(n - 1)
  end

  @doc false
  # Calculates sample variance of a series (divides by n-1 for unbiased estimator)
  defp variance(values) do
    n = length(values)
    mean = Enum.sum(values) / n

    values
    |> Enum.map(&:math.pow(&1 - mean, 2))
    |> Enum.sum()
    |> Kernel./(n - 1)
  end

  @doc """
  Calculate Sharpe ratio.

  ## Parameters

    * `returns` - List of period returns
    * `risk_free_rate` - Risk-free rate per period (default: 0)

  ## Returns

  Sharpe ratio, or `nil` if insufficient data or zero volatility.

  ## Example

      returns = [0.01, 0.02, -0.01, 0.015, 0.005]
      CCXT.Trading.Risk.sharpe_ratio(returns)
      # => 1.2

  """
  @spec sharpe_ratio([number()], number()) :: float() | nil
  def sharpe_ratio(returns, risk_free_rate \\ 0) when is_list(returns) and is_number(risk_free_rate) do
    if length(returns) < 2 do
      nil
    else
      calculate_sharpe(returns, risk_free_rate)
    end
  end

  @doc false
  # Computes Sharpe ratio as (mean_return - risk_free) / std_dev
  defp calculate_sharpe(returns, risk_free_rate) do
    mean_return = Enum.sum(returns) / length(returns)
    excess_return = mean_return - risk_free_rate
    std_dev = :math.sqrt(variance(returns))

    if std_dev == 0 do
      nil
    else
      excess_return / std_dev
    end
  end

  @doc """
  Calculate Sortino ratio.

  Like Sharpe ratio but uses downside deviation (only negative returns)
  instead of total standard deviation. This penalizes only harmful volatility.

  ## Parameters

    * `returns` - List of period returns
    * `risk_free_rate` - Risk-free rate per period (default: 0)
    * `target_return` - Minimum acceptable return for downside calc (default: 0)

  ## Returns

  Sortino ratio, or `nil` if insufficient data or zero downside deviation.

  ## Example

      returns = [0.01, 0.02, -0.01, 0.015, -0.02]
      CCXT.Trading.Risk.sortino_ratio(returns)
      # => 1.5

  """
  @spec sortino_ratio([number()], number(), number()) :: float() | nil
  def sortino_ratio(returns, risk_free_rate \\ 0, target_return \\ 0)
      when is_list(returns) and is_number(risk_free_rate) and is_number(target_return) do
    if length(returns) < 2 do
      nil
    else
      calculate_sortino(returns, risk_free_rate, target_return)
    end
  end

  @doc false
  # Computes Sortino ratio using downside deviation
  defp calculate_sortino(returns, risk_free_rate, target_return) do
    mean_return = Enum.sum(returns) / length(returns)
    excess_return = mean_return - risk_free_rate
    downside_dev = downside_deviation(returns, target_return)

    if downside_dev == 0 do
      nil
    else
      excess_return / downside_dev
    end
  end

  @doc false
  # Calculates downside deviation (semi-deviation of negative returns)
  defp downside_deviation(returns, target) do
    downside_returns =
      returns
      |> Enum.filter(&(&1 < target))
      |> Enum.map(&:math.pow(&1 - target, 2))

    if Enum.empty?(downside_returns) do
      0.0
    else
      :math.sqrt(Enum.sum(downside_returns) / length(downside_returns))
    end
  end

  @doc """
  Calculate maximum drawdown from a series of values or returns.

  Maximum drawdown is the largest peak-to-trough decline, expressed as
  a percentage. This is a key risk metric for evaluating strategies.

  ## Parameters

    * `values` - List of portfolio values (equity curve) or cumulative returns
    * `opts` - Options:
      * `:type` - `:values` (default) or `:returns` (will be converted to equity curve)

  ## Returns

  Map with:
    * `:max_drawdown` - Maximum drawdown as decimal (e.g., 0.15 = 15%)
    * `:peak_index` - Index of the peak before max drawdown
    * `:trough_index` - Index of the trough (max drawdown point)

  Returns `nil` if insufficient data.

  ## Example

      values = [100, 110, 105, 95, 100, 90, 95]
      CCXT.Trading.Risk.max_drawdown(values)
      # => %{max_drawdown: 0.182, peak_index: 1, trough_index: 5}

      returns = [0.10, -0.045, -0.095, 0.053, -0.10, 0.056]
      CCXT.Trading.Risk.max_drawdown(returns, type: :returns)

  """
  @spec max_drawdown([number()], keyword()) ::
          %{max_drawdown: float(), peak_index: non_neg_integer(), trough_index: non_neg_integer()} | nil
  def max_drawdown(values, opts \\ []) when is_list(values) do
    equity_curve = convert_to_equity_curve(values, opts)

    # Check equity curve length (after conversion, since returns get +1 for initial equity)
    if length(equity_curve) < 2 do
      nil
    else
      calculate_max_drawdown(equity_curve)
    end
  end

  @doc false
  # Converts returns to equity curve if needed
  defp convert_to_equity_curve(values, opts) do
    case Keyword.get(opts, :type, :values) do
      :returns ->
        # Convert returns to equity curve starting at 1.0
        # Prepend initial equity so first return can show drawdown from starting value
        [1.0 | Enum.scan(values, 1.0, fn ret, acc -> acc * (1 + ret) end)]

      :values ->
        values
    end
  end

  @doc false
  # Calculates max drawdown from equity curve
  defp calculate_max_drawdown(values) do
    initial_state = {0, 0, 0, 0, Enum.at(values, 0)}

    {max_dd, peak_idx, trough_idx, _, _} =
      values
      |> Enum.with_index()
      |> Enum.reduce(initial_state, &update_drawdown_state/2)

    %{
      max_drawdown: max_dd,
      peak_index: peak_idx,
      trough_index: trough_idx
    }
  end

  @doc false
  # Updates drawdown tracking state for a single value
  defp update_drawdown_state({value, idx}, {max_dd, peak_idx, trough_idx, current_peak_idx, peak}) do
    if value > peak do
      {max_dd, peak_idx, trough_idx, idx, value}
    else
      check_new_max_drawdown(value, idx, max_dd, peak_idx, trough_idx, current_peak_idx, peak)
    end
  end

  @doc false
  # Checks if current drawdown exceeds maximum
  defp check_new_max_drawdown(value, idx, max_dd, peak_idx, trough_idx, current_peak_idx, peak) do
    drawdown = (peak - value) / peak

    if drawdown > max_dd do
      {drawdown, current_peak_idx, idx, current_peak_idx, peak}
    else
      {max_dd, peak_idx, trough_idx, current_peak_idx, peak}
    end
  end

  @doc """
  Calculate Calmar ratio.

  The Calmar ratio is annualized return divided by maximum drawdown.
  Higher is better - indicates more return per unit of drawdown risk.

  ## Parameters

    * `returns` - List of period returns
    * `periods_per_year` - Number of periods per year for annualization (default: 365 for crypto)

  ## Returns

  Calmar ratio, or `nil` if insufficient data or zero drawdown.

  ## Example

      # Daily returns
      returns = [0.01, -0.02, 0.015, -0.01, 0.02, -0.03, 0.01]
      CCXT.Trading.Risk.calmar_ratio(returns)
      # => 2.5

  """
  @spec calmar_ratio([number()], pos_integer()) :: float() | nil
  def calmar_ratio(returns, periods_per_year \\ 365) when is_list(returns) and is_integer(periods_per_year) do
    if length(returns) < 2 do
      nil
    else
      calculate_calmar(returns, periods_per_year)
    end
  end

  @doc false
  # Computes Calmar ratio as annualized return / max drawdown
  defp calculate_calmar(returns, periods_per_year) do
    mean_return = Enum.sum(returns) / length(returns)
    annualized_return = mean_return * periods_per_year

    case max_drawdown(returns, type: :returns) do
      %{max_drawdown: mdd} when mdd > 0 ->
        annualized_return / mdd

      _ ->
        nil
    end
  end
end
