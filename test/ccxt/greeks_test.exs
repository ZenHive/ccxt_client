defmodule CCXT.GreeksTest do
  use ExUnit.Case, async: true

  alias CCXT.Greeks
  alias CCXT.Types.Option

  @sample_positions [
    %{delta: 0.5, gamma: 0.02, theta: -10.0, vega: 25.0, quantity: 10},
    %{delta: -0.3, gamma: 0.015, theta: -8.0, vega: 20.0, quantity: 5}
  ]

  describe "position_greeks/1" do
    test "aggregates Greeks across positions" do
      result = Greeks.position_greeks(@sample_positions)

      # Delta: 0.5 * 10 + -0.3 * 5 = 5.0 - 1.5 = 3.5
      assert_in_delta result.delta, 3.5, 0.001
      # Gamma: 0.02 * 10 + 0.015 * 5 = 0.2 + 0.075 = 0.275
      assert_in_delta result.gamma, 0.275, 0.001
      # Theta: -10 * 10 + -8 * 5 = -100 - 40 = -140
      assert_in_delta result.theta, -140.0, 0.001
      # Vega: 25 * 10 + 20 * 5 = 250 + 100 = 350
      assert_in_delta result.vega, 350.0, 0.001
    end

    test "handles short positions (negative quantity)" do
      positions = [
        %{delta: 0.5, gamma: 0.02, theta: -10.0, vega: 25.0, quantity: 10},
        %{delta: -0.3, gamma: 0.015, theta: -8.0, vega: 20.0, quantity: -5}
      ]

      result = Greeks.position_greeks(positions)

      # Delta: 0.5 * 10 + -0.3 * -5 = 5.0 + 1.5 = 6.5
      assert_in_delta result.delta, 6.5, 0.001
    end

    test "returns zeros for empty list" do
      result = Greeks.position_greeks([])

      assert result.delta == 0.0
      assert result.gamma == 0.0
      assert result.theta == 0.0
      assert result.vega == 0.0
    end

    test "handles missing fields" do
      positions = [
        %{delta: 0.5, quantity: 10}
      ]

      result = Greeks.position_greeks(positions)

      assert_in_delta result.delta, 5.0, 0.001
      assert result.gamma == 0.0
      assert result.theta == 0.0
      assert result.vega == 0.0
    end

    test "defaults quantity to 1" do
      positions = [%{delta: 0.5, gamma: 0.02, theta: -10.0, vega: 25.0}]

      result = Greeks.position_greeks(positions)

      assert_in_delta result.delta, 0.5, 0.001
    end
  end

  describe "dollar_delta/3" do
    test "calculates delta exposure in currency" do
      result = Greeks.dollar_delta(5.0, 50_000)

      assert result == 250_000.0
    end

    test "handles contract multiplier" do
      result = Greeks.dollar_delta(5.0, 50_000, 10)

      assert result == 2_500_000.0
    end

    test "handles negative delta" do
      result = Greeks.dollar_delta(-3.0, 50_000)

      assert result == -150_000.0
    end
  end

  describe "dollar_gamma/3" do
    test "calculates gamma for 1% move" do
      result = Greeks.dollar_gamma(0.5, 50_000)

      # 0.5 * 50000 * 0.01 = 250
      assert result == 250.0
    end

    test "handles contract multiplier" do
      result = Greeks.dollar_gamma(0.5, 50_000, 10)

      assert result == 2500.0
    end
  end

  describe "delta_neutral?/2" do
    test "returns true when delta within tolerance" do
      assert Greeks.delta_neutral?(0.05, 0.1)
      assert Greeks.delta_neutral?(-0.05, 0.1)
      assert Greeks.delta_neutral?(0.0, 0.1)
    end

    test "returns false when delta exceeds tolerance" do
      refute Greeks.delta_neutral?(0.15, 0.1)
      refute Greeks.delta_neutral?(-0.15, 0.1)
    end

    test "uses default tolerance of 0.1" do
      assert Greeks.delta_neutral?(0.1)
      refute Greeks.delta_neutral?(0.11)
    end
  end

  describe "hedge_ratio/2" do
    test "calculates hedge for long delta" do
      result = Greeks.hedge_ratio(5.0)

      assert result == -5.0
    end

    test "calculates hedge for short delta" do
      result = Greeks.hedge_ratio(-3.0)

      assert result == 3.0
    end

    test "handles custom hedge delta" do
      # Hedging with instrument that has delta of 0.5
      result = Greeks.hedge_ratio(5.0, 0.5)

      assert result == -10.0
    end
  end

  describe "from_chain/2" do
    test "extracts Greeks from option chain" do
      chain = %{
        "BTC-31JAN26-84000-C" => %Option{
          symbol: "BTC-31JAN26-84000-C",
          currency: "BTC",
          open_interest: 100.0,
          implied_volatility: 0.65,
          bid_price: 1000.0,
          ask_price: 1100.0,
          mid_price: 1050.0,
          mark_price: 1050.0,
          last_price: 1040.0,
          underlying_price: 85_000.0,
          change: 0.0,
          percentage: 0.0,
          base_volume: 0.0,
          quote_volume: 0.0,
          raw: %{"delta" => 0.5, "gamma" => 0.02, "theta" => -10.0, "vega" => 25.0}
        }
      }

      positions = %{"BTC-31JAN26-84000-C" => 10}

      [result] = Greeks.from_chain(chain, positions)

      assert result.symbol == "BTC-31JAN26-84000-C"
      assert result.delta == 0.5
      assert result.gamma == 0.02
      assert result.theta == -10.0
      assert result.vega == 25.0
      assert result.quantity == 10
    end

    test "filters out positions not in chain" do
      chain = %{}
      positions = %{"BTC-31JAN26-84000-C" => 10}

      result = Greeks.from_chain(chain, positions)

      assert result == []
    end
  end

  describe "daily_theta/1" do
    test "returns portfolio theta" do
      result = Greeks.daily_theta(@sample_positions)

      assert_in_delta result, -140.0, 0.001
    end
  end

  describe "vega_exposure/1" do
    test "returns portfolio vega" do
      result = Greeks.vega_exposure(@sample_positions)

      assert_in_delta result, 350.0, 0.001
    end
  end

  describe "gamma_pnl/3" do
    test "calculates P&L from gamma for given move" do
      # Gamma of 0.1, BTC at $50k, 2% move
      result = Greeks.gamma_pnl(0.1, 50_000, 2.0)

      # Move = 50000 * 0.02 = 1000
      # P&L = 0.5 * 0.1 * 1000 * 1000 = 50,000
      assert_in_delta result, 50_000.0, 0.001
    end

    test "returns 0 for zero move" do
      result = Greeks.gamma_pnl(0.1, 50_000, 0.0)

      assert result == 0.0
    end

    test "handles negative gamma" do
      result = Greeks.gamma_pnl(-0.1, 50_000, 2.0)

      assert_in_delta result, -50_000.0, 0.001
    end
  end
end
