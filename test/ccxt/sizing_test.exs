defmodule CCXT.SizingTest do
  use ExUnit.Case, async: true

  alias CCXT.Sizing

  describe "fixed_fractional/3" do
    test "calculates correct position size" do
      # $100k account, 1% risk, $500 stop distance
      result = Sizing.fixed_fractional(100_000, 0.01, 500)

      # $1000 risk / $500 stop = 2 units
      assert result == 2.0
    end

    test "handles smaller account sizes" do
      result = Sizing.fixed_fractional(10_000, 0.02, 100)

      # $200 risk / $100 stop = 2 units
      assert result == 2.0
    end

    test "handles fractional results" do
      result = Sizing.fixed_fractional(50_000, 0.01, 300)

      # $500 risk / $300 stop = 1.666...
      assert_in_delta result, 1.666, 0.01
    end
  end

  describe "max_loss/2" do
    test "calculates position size from max loss" do
      result = Sizing.max_loss(1000, 250)

      assert result == 4.0
    end

    test "handles fractional units" do
      result = Sizing.max_loss(1000, 300)

      assert_in_delta result, 3.333, 0.01
    end
  end

  describe "kelly/3" do
    test "calculates half kelly by default" do
      # 55% win rate, 1.5:1 reward/risk
      result = Sizing.kelly(0.55, 1.5)

      # Full Kelly = (0.55 * 1.5 - 0.45) / 1.5 = 0.375 / 1.5 = 0.25
      # Half Kelly = 0.25 * 0.5 = 0.125
      assert_in_delta result, 0.125, 0.01
    end

    test "calculates quarter kelly" do
      result = Sizing.kelly(0.55, 1.5, 0.25)

      # Quarter Kelly = 0.25 * 0.25 = 0.0625
      assert_in_delta result, 0.0625, 0.01
    end

    test "returns 0 for negative expected value" do
      # 40% win rate, 1:1 reward/risk = negative EV
      result = Sizing.kelly(0.40, 1.0)

      assert result == 0.0
    end

    test "returns 0 at breakeven" do
      # 50% win rate, 1:1 = exactly breakeven
      result = Sizing.kelly(0.50, 1.0)

      assert result == 0.0
    end

    test "handles high win rate" do
      # 70% win rate, 2:1 reward
      result = Sizing.kelly(0.70, 2.0, 1.0)

      # Full Kelly = (0.7 * 2 - 0.3) / 2 = 0.55
      assert_in_delta result, 0.55, 0.01
    end
  end

  describe "volatility_scaled/4" do
    test "reduces size when volatility is high" do
      # Current vol 50, target 30 = reduce by 30/50 = 0.6
      result = Sizing.volatility_scaled(100_000, 0.01, 50, 30)

      # $1000 base * 0.6 = $600
      assert result == 600.0
    end

    test "increases size when volatility is low" do
      # Current vol 20, target 30 = increase by 30/20 = 1.5
      result = Sizing.volatility_scaled(100_000, 0.01, 20, 30)

      # $1000 base * 1.5 = $1500
      assert result == 1500.0
    end

    test "maintains size at target volatility" do
      result = Sizing.volatility_scaled(100_000, 0.01, 30, 30)

      assert result == 1000.0
    end
  end

  describe "anti_martingale/4" do
    test "increases size after wins" do
      result = Sizing.anti_martingale(1.0, 3, 0.25)

      # 1.0 * (1 + 3 * 0.25) = 1.75
      assert result == 1.75
    end

    test "decreases size after losses" do
      result = Sizing.anti_martingale(1.0, -2, 0.25)

      # 1.0 * (1 + -2 * 0.25) = 0.5
      assert result == 0.5
    end

    test "respects max scale limit" do
      # 10 wins would be 3.5x but max is 2.0
      result = Sizing.anti_martingale(1.0, 10, 0.25, 2.0)

      assert result == 2.0
    end

    test "respects min scale limit" do
      # -10 wins would be -1.5x but min is 1/max = 0.5
      result = Sizing.anti_martingale(1.0, -10, 0.25, 2.0)

      assert result == 0.5
    end

    test "maintains base at zero wins" do
      result = Sizing.anti_martingale(2.0, 0)

      assert result == 2.0
    end
  end

  describe "optimal_f/1" do
    test "calculates optimal f for trade series" do
      trades = [100.0, -50.0, 75.0, -25.0, 150.0, -75.0, 200.0]
      result = Sizing.optimal_f(trades)

      # Should return a value between 0 and 1
      assert result
      assert result > 0
      assert result < 1
    end

    test "returns nil for insufficient data" do
      trades = [100.0, -50.0]

      assert Sizing.optimal_f(trades) == nil
    end

    test "returns nil for all winning trades" do
      trades = [100.0, 200.0, 150.0, 300.0]

      assert Sizing.optimal_f(trades) == nil
    end

    test "handles mixed positive and negative trades" do
      # Realistic trade series
      trades = [
        50.0,
        -30.0,
        75.0,
        -40.0,
        100.0,
        -25.0,
        -35.0,
        80.0,
        -50.0,
        120.0
      ]

      result = Sizing.optimal_f(trades)

      assert result
      assert result > 0
      assert result < 1
    end
  end
end
