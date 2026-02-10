defmodule CCXT.Trading.BasisTest do
  use ExUnit.Case, async: true

  alias CCXT.Trading.Basis

  describe "spot_perp/2" do
    test "calculates contango basis" do
      result = Basis.spot_perp(50_000, 50_100)

      assert result.absolute == 100.0
      assert_in_delta result.percent, 0.2, 0.001
      assert result.direction == :contango
    end

    test "calculates backwardation basis" do
      result = Basis.spot_perp(50_000, 49_900)

      assert result.absolute == -100.0
      assert_in_delta result.percent, -0.2, 0.001
      assert result.direction == :backwardation
    end

    test "calculates flat basis" do
      result = Basis.spot_perp(50_000, 50_000)

      assert result.absolute == 0.0
      assert result.percent == 0.0
      assert result.direction == :flat
    end
  end

  describe "annualized/3" do
    test "calculates annualized yield" do
      # 0.2% over 30 days = 0.002 * (365/30) = 0.0243
      result = Basis.annualized(50_000, 50_100, 30)

      assert_in_delta result, 0.0243, 0.001
    end

    test "higher yield for shorter duration" do
      short = Basis.annualized(50_000, 50_100, 7)
      long = Basis.annualized(50_000, 50_100, 30)

      assert short > long
    end

    test "negative yield for backwardation" do
      result = Basis.annualized(50_000, 49_900, 30)

      assert result < 0
    end
  end

  describe "futures_curve/2" do
    test "builds curve sorted by expiry" do
      futures = [
        %{expiry: Date.add(Date.utc_today(), 60), price: 51_000},
        %{expiry: Date.add(Date.utc_today(), 30), price: 50_500}
      ]

      result = Basis.futures_curve(50_000, futures)

      assert length(result) == 2
      # Should be sorted by expiry (30 days first)
      [first, second] = result
      assert first.days_to_expiry < second.days_to_expiry
    end

    test "calculates basis for each contract" do
      futures = [
        %{expiry: Date.add(Date.utc_today(), 30), price: 50_500}
      ]

      [result] = Basis.futures_curve(50_000, futures)

      assert result.basis == 500
      assert_in_delta result.basis_pct, 1.0, 0.001
      assert result.annualized > 0
    end

    test "filters expired contracts" do
      futures = [
        %{expiry: Date.add(Date.utc_today(), -1), price: 50_500},
        %{expiry: Date.add(Date.utc_today(), 30), price: 50_500}
      ]

      result = Basis.futures_curve(50_000, futures)

      assert length(result) == 1
    end

    test "includes same-day expiry contracts" do
      today = Date.utc_today()

      futures = [
        %{expiry: today, price: 50_100}
      ]

      result = Basis.futures_curve(50_000, futures)

      assert length(result) == 1
      [contract] = result
      assert contract.days_to_expiry == 0
      assert contract.basis == 100
      # Same-day contracts have 0 days so annualized is 0.0
      assert contract.annualized == 0.0
    end

    test "handles string keys" do
      futures = [
        %{"expiry" => Date.add(Date.utc_today(), 30), "price" => 50_500}
      ]

      [result] = Basis.futures_curve(50_000, futures)

      assert result.basis == 500
    end
  end

  describe "implied_funding/3" do
    test "calculates implied 8-hour funding" do
      # 0.1% basis / 3 periods = 0.000333 per period
      result = Basis.implied_funding(50_000, 50_050)

      assert_in_delta result, 0.000333, 0.0001
    end

    test "handles custom funding interval" do
      eight_hour = Basis.implied_funding(50_000, 50_050, 8)
      four_hour = Basis.implied_funding(50_000, 50_050, 4)

      # 4-hour has 2x the periods of 8-hour, so implied rate is half per period
      # 0.0001 tolerance matches 8-hour test
      assert_in_delta four_hour, eight_hour / 2, 0.0001
    end

    test "negative for backwardation" do
      result = Basis.implied_funding(50_000, 49_950)

      assert result < 0
    end
  end

  describe "compare/1" do
    test "compares basis across exchanges" do
      exchanges = [
        %{exchange: :binance, spot: 50_000, perp: 50_100},
        %{exchange: :okx, spot: 50_000, perp: 50_150}
      ]

      result = Basis.compare(exchanges)

      # Sorted by basis descending
      assert length(result) == 2
      [first, second] = result
      assert first.exchange == :okx
      assert first.basis == 150
      assert second.exchange == :binance
      assert second.basis == 100
    end

    test "calculates implied APR" do
      exchanges = [%{exchange: :test, spot: 50_000, perp: 50_100}]

      [result] = Basis.compare(exchanges)

      # Annualize basis assuming ~1 day convergence: 0.2% * 365 = 73%
      expected_apr = (50_100 - 50_000) / 50_000 * 365 * 100
      assert_in_delta result.implied_apr, expected_apr, 0.01
    end

    test "handles string keys" do
      exchanges = [%{"exchange" => "test", "spot" => 50_000, "perp" => 50_100}]

      [result] = Basis.compare(exchanges)

      assert result.exchange == "test"
      assert result.basis == 100
    end
  end

  describe "arbitrage_opportunity?/3" do
    test "returns true when above threshold" do
      assert Basis.arbitrage_opportunity?(50_000, 50_100, 0.1)
    end

    test "returns false when below threshold" do
      refute Basis.arbitrage_opportunity?(50_000, 50_025, 0.1)
    end

    test "works with backwardation" do
      assert Basis.arbitrage_opportunity?(50_000, 49_900, 0.1)
    end

    test "uses default threshold of 0.1%" do
      assert Basis.arbitrage_opportunity?(50_000, 50_100)
      refute Basis.arbitrage_opportunity?(50_000, 50_025)
    end
  end
end
