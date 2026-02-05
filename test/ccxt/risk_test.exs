defmodule CCXT.RiskTest do
  use ExUnit.Case, async: true

  alias CCXT.Risk

  @sample_positions [
    %{symbol: "BTC/USDT", value: 50_000},
    %{symbol: "ETH/USDT", value: 30_000},
    %{symbol: "SOL/USDT", value: 20_000}
  ]

  describe "concentration/1" do
    test "calculates concentration metrics" do
      result = Risk.concentration(@sample_positions)

      # Max: 50k / 100k = 0.5
      assert_in_delta result.max, 0.5, 0.001
      # HHI: 0.5^2 + 0.3^2 + 0.2^2 = 0.25 + 0.09 + 0.04 = 0.38
      assert_in_delta result.hhi, 0.38, 0.001
      # Top 3: all positions = 1.0
      assert_in_delta result.top3, 1.0, 0.001
    end

    test "handles single position" do
      positions = [%{value: 100_000}]
      result = Risk.concentration(positions)

      assert result.max == 1.0
      assert result.hhi == 1.0
      assert result.top3 == 1.0
    end

    test "returns nil for empty list" do
      assert Risk.concentration([]) == nil
    end

    test "uses absolute values" do
      positions = [
        %{value: -50_000},
        %{value: 30_000}
      ]

      result = Risk.concentration(positions)

      # Should use abs values: 50k + 30k = 80k total
      assert_in_delta result.max, 0.625, 0.001
    end

    test "handles more than 3 positions" do
      positions = [
        %{value: 40_000},
        %{value: 30_000},
        %{value: 20_000},
        %{value: 10_000}
      ]

      result = Risk.concentration(positions)

      # Top 3: 40 + 30 + 20 = 90 out of 100 = 0.9
      assert_in_delta result.top3, 0.9, 0.001
    end
  end

  describe "max_position_size/2" do
    test "calculates max position from percentage" do
      # With high loss tolerance, percentage limit dominates
      result = Risk.max_position_size(100_000, max_position_pct: 0.25, max_loss_pct: 0.10, expected_drawdown: 0.20)

      # Loss-based: 0.10 / 0.20 * 100k = 50k
      # Percentage: 0.25 * 100k = 25k
      # Min = 25k
      assert result == 25_000.0
    end

    test "uses default limits" do
      result = Risk.max_position_size(100_000)

      # Default: 20% position, 2% loss, 20% drawdown
      # Loss-based: 0.02 / 0.20 * 100k = 10k
      # Percentage: 0.20 * 100k = 20k
      # Min = 10k
      assert result == 10_000.0
    end

    test "respects loss-based limit when more restrictive" do
      # 2% max loss with 20% expected drawdown = 10% position limit
      # 25% position limit is less restrictive
      # So take the more conservative (from loss = 2% / 20% * 100k = 10k)
      result = Risk.max_position_size(100_000, max_position_pct: 0.25, max_loss_pct: 0.02, expected_drawdown: 0.20)

      assert result == 10_000.0
    end

    test "raises ArgumentError for zero expected_drawdown" do
      assert_raise ArgumentError, ~r/expected_drawdown must be > 0/, fn ->
        Risk.max_position_size(100_000, expected_drawdown: 0)
      end
    end

    test "raises ArgumentError for negative expected_drawdown" do
      assert_raise ArgumentError, ~r/expected_drawdown must be > 0/, fn ->
        Risk.max_position_size(100_000, expected_drawdown: -0.10)
      end
    end
  end

  describe "check_limits/2" do
    test "returns ok when all limits pass" do
      # Use diversified positions to pass default concentration limit (0.25)
      positions = [
        %{symbol: "BTC/USDT", value: 25_000},
        %{symbol: "ETH/USDT", value: 25_000},
        %{symbol: "SOL/USDT", value: 25_000},
        %{symbol: "AVAX/USDT", value: 25_000}
      ]

      limits = [max_position: 50_000]

      assert {:ok, ^positions} = Risk.check_limits(positions, limits)
    end

    test "returns error for position size violation" do
      positions = [%{symbol: "BTC/USDT", value: 50_000}]
      # Disable concentration check to isolate position size violation
      limits = [max_position: 25_000, max_concentration: 1.0]

      assert {:error, violations} = Risk.check_limits(positions, limits)
      assert [{:max_position, "BTC/USDT", 50_000, 25_000}] = violations
    end

    test "returns error for concentration violation" do
      positions = [%{symbol: "BTC/USDT", value: 100_000}]
      limits = [max_concentration: 0.5]

      assert {:error, violations} = Risk.check_limits(positions, limits)
      assert [{:max_concentration, 1.0, 0.5}] = violations
    end

    test "returns error for total exposure violation" do
      positions = @sample_positions
      # Disable concentration check to isolate total exposure violation
      limits = [max_total_exposure: 50_000, max_concentration: 1.0]

      assert {:error, violations} = Risk.check_limits(positions, limits)
      assert [{:max_total_exposure, 100_000, 50_000}] = violations
    end

    test "returns multiple violations" do
      positions = [%{symbol: "BTC/USDT", value: 100_000}]
      # Include concentration check (default 0.25 will trigger)
      limits = [max_position: 50_000, max_total_exposure: 50_000]

      assert {:error, violations} = Risk.check_limits(positions, limits)
      # Position + concentration + total = 3 violations
      assert length(violations) == 3
    end

    test "nil max_concentration disables concentration check" do
      # Single concentrated position that would fail default 0.25 HHI check
      positions = [%{symbol: "BTC/USDT", value: 100_000}]
      # Explicitly set max_concentration: nil to disable the check
      limits = [max_concentration: nil]

      assert {:ok, ^positions} = Risk.check_limits(positions, limits)
    end
  end

  describe "var/4" do
    test "calculates 95% VaR" do
      result = Risk.var(100_000, 0.02)

      # 100k * 0.02 * z_95 * sqrt(1) where z_95 ≈ 1.645
      # Using inverse normal CDF for more accuracy
      assert_in_delta result, 3_290.0, 5.0
    end

    test "calculates 99% VaR" do
      result = Risk.var(100_000, 0.02, 0.99)

      # 100k * 0.02 * z_99 * sqrt(1) where z_99 ≈ 2.326
      # Inverse normal CDF gives slightly different value
      assert_in_delta result, 4_653.0, 5.0
    end

    test "scales with time horizon" do
      one_day = Risk.var(100_000, 0.02, 0.95, 1)
      ten_days = Risk.var(100_000, 0.02, 0.95, 10)

      # 10-day VaR should be sqrt(10) times 1-day VaR
      assert_in_delta ten_days / one_day, :math.sqrt(10), 0.01
    end
  end

  describe "beta/2" do
    test "calculates beta coefficient" do
      portfolio = [0.02, -0.01, 0.03, -0.02, 0.01]
      benchmark = [0.01, -0.005, 0.015, -0.01, 0.005]

      result = Risk.beta(portfolio, benchmark)

      # Portfolio moves about 2x benchmark
      assert is_float(result), "Expected beta to return a float"
      assert result > 1.0
    end

    test "returns nil for insufficient data" do
      assert Risk.beta([0.01, 0.02], [0.01, 0.02]) == nil
    end

    test "returns nil for mismatched lengths" do
      assert Risk.beta([0.01, 0.02, 0.03], [0.01, 0.02]) == nil
    end

    test "returns nil for zero variance benchmark" do
      portfolio = [0.01, 0.02, 0.03]
      benchmark = [0.01, 0.01, 0.01]

      assert Risk.beta(portfolio, benchmark) == nil
    end
  end

  describe "sharpe_ratio/2" do
    test "calculates sharpe ratio" do
      returns = [0.01, 0.02, -0.01, 0.015, 0.005]

      result = Risk.sharpe_ratio(returns)

      assert is_float(result), "Expected sharpe_ratio to return a float"
      assert result > 0
    end

    test "returns nil for insufficient data" do
      assert Risk.sharpe_ratio([0.01]) == nil
    end

    test "returns nil for zero volatility" do
      returns = [0.01, 0.01, 0.01]

      assert Risk.sharpe_ratio(returns) == nil
    end

    test "accounts for risk-free rate" do
      returns = [0.01, 0.02, 0.015]

      with_rf = Risk.sharpe_ratio(returns, 0.005)
      without_rf = Risk.sharpe_ratio(returns, 0)

      assert with_rf < without_rf
    end
  end

  describe "sortino_ratio/3" do
    test "calculates sortino ratio" do
      returns = [0.01, 0.02, -0.01, 0.015, -0.02]

      result = Risk.sortino_ratio(returns)

      assert is_float(result), "Expected sortino_ratio to return a float"
      # Sortino should generally be higher than Sharpe (only penalizes downside)
    end

    test "returns nil for insufficient data" do
      assert Risk.sortino_ratio([0.01]) == nil
    end

    test "returns nil when no downside deviation" do
      returns = [0.01, 0.02, 0.03]

      assert Risk.sortino_ratio(returns) == nil
    end

    test "accounts for risk-free rate" do
      returns = [0.01, 0.02, -0.01, 0.015, -0.02]

      with_rf = Risk.sortino_ratio(returns, 0.005)
      without_rf = Risk.sortino_ratio(returns, 0)

      assert with_rf < without_rf
    end

    test "accounts for target return" do
      returns = [0.01, 0.02, -0.01, 0.015, 0.005]

      # With target of 0.01, more returns become "downside"
      with_target = Risk.sortino_ratio(returns, 0, 0.01)
      without_target = Risk.sortino_ratio(returns, 0, 0)

      assert with_target != without_target
    end
  end

  describe "max_drawdown/2" do
    test "calculates max drawdown from values" do
      values = [100, 110, 105, 95, 100, 90, 95]

      result = Risk.max_drawdown(values)

      # Peak at 110, trough at 90 = 18.18% drawdown
      assert_in_delta result.max_drawdown, 0.1818, 0.01
      assert result.peak_index == 1
      assert result.trough_index == 5
    end

    test "calculates max drawdown from returns" do
      returns = [0.10, -0.045, -0.095, 0.053, -0.10, 0.056]

      result = Risk.max_drawdown(returns, type: :returns)

      assert result.max_drawdown > 0
    end

    test "includes starting equity for returns" do
      # 50% drop then 100% gain to recover to breakeven
      returns = [-0.5, 1.0]

      result = Risk.max_drawdown(returns, type: :returns)

      # 50% from starting equity
      expected_drawdown = 0.5
      # float comparison tolerance
      tolerance = 0.0001

      assert_in_delta result.max_drawdown, expected_drawdown, tolerance
      assert result.peak_index == 0
      assert result.trough_index == 1
    end

    test "returns nil for insufficient data" do
      assert Risk.max_drawdown([100]) == nil
    end

    test "handles all-up market" do
      values = [100, 110, 120, 130, 140]

      result = Risk.max_drawdown(values)

      assert result.max_drawdown == 0
    end

    test "handles monotonic decline" do
      values = [100, 90, 80, 70, 60]

      result = Risk.max_drawdown(values)

      # 40% drawdown from 100 to 60
      assert_in_delta result.max_drawdown, 0.40, 0.01
      assert result.peak_index == 0
      assert result.trough_index == 4
    end

    test "handles negative first return (regression)" do
      # Regression test: first return is negative, should show drawdown from initial equity
      returns = [-0.5, 1.0]

      result = Risk.max_drawdown(returns, type: :returns)

      # Equity curve: [1.0, 0.5, 1.0] - 50% drawdown from initial 1.0 to 0.5
      assert_in_delta result.max_drawdown, 0.5, 0.01
      assert result.peak_index == 0
      assert result.trough_index == 1
    end

    test "handles single return (type: :returns)" do
      # Single negative return should work after conversion adds initial equity
      returns = [-0.5]

      result = Risk.max_drawdown(returns, type: :returns)

      # Equity curve: [1.0, 0.5] - 50% drawdown
      assert_in_delta result.max_drawdown, 0.5, 0.01
    end
  end

  describe "calmar_ratio/2" do
    test "calculates calmar ratio" do
      returns = [0.01, -0.02, 0.015, -0.01, 0.02, -0.03, 0.01]

      result = Risk.calmar_ratio(returns)

      assert is_float(result), "Expected calmar_ratio to return a float"
    end

    test "returns nil for insufficient data" do
      assert Risk.calmar_ratio([0.01]) == nil
    end

    test "returns nil for zero drawdown" do
      returns = [0.01, 0.02, 0.01]

      assert Risk.calmar_ratio(returns) == nil
    end

    test "uses custom periods per year" do
      returns = [0.01, -0.02, 0.015, -0.01, 0.02]

      daily = Risk.calmar_ratio(returns, 365)
      weekly = Risk.calmar_ratio(returns, 52)

      # Daily annualization should give higher ratio
      assert daily > weekly
    end
  end

  describe "var/4 with arbitrary confidence" do
    test "calculates VaR for 97.5% confidence" do
      result = Risk.var(100_000, 0.02, 0.975)

      # Z for 97.5% ≈ 1.96
      expected = 100_000 * 0.02 * 1.96
      assert_in_delta result, expected, 50
    end

    test "calculates VaR for 99.5% confidence" do
      result = Risk.var(100_000, 0.02, 0.995)

      # Z for 99.5% ≈ 2.576
      expected = 100_000 * 0.02 * 2.576
      assert_in_delta result, expected, 50
    end

    test "VaR increases with confidence level" do
      var_90 = Risk.var(100_000, 0.02, 0.90)
      var_95 = Risk.var(100_000, 0.02, 0.95)
      var_99 = Risk.var(100_000, 0.02, 0.99)

      assert var_90 < var_95
      assert var_95 < var_99
    end
  end
end
