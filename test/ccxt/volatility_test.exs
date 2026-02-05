defmodule CCXT.VolatilityTest do
  use ExUnit.Case, async: true

  alias CCXT.Volatility

  @sample_prices [100, 102, 99, 103, 101, 105, 102, 108, 104, 110]

  @sample_candles [
    %{open: 100, high: 105, low: 98, close: 103},
    %{open: 103, high: 107, low: 100, close: 105},
    %{open: 105, high: 110, low: 102, close: 108},
    %{open: 108, high: 112, low: 105, close: 110}
  ]

  describe "realized/2" do
    test "calculates daily volatility" do
      result = Volatility.realized(@sample_prices)

      assert result
      assert result > 0
      assert result < 1
    end

    test "annualizes volatility" do
      daily = Volatility.realized(@sample_prices)
      annual = Volatility.realized(@sample_prices, annualize: true)

      # Annualized should be sqrt(365) times daily
      assert_in_delta annual / daily, :math.sqrt(365), 0.01
    end

    test "uses custom trading days" do
      annual_365 = Volatility.realized(@sample_prices, annualize: true, trading_days: 365)
      annual_252 = Volatility.realized(@sample_prices, annualize: true, trading_days: 252)

      assert annual_365 > annual_252
    end

    test "returns nil for insufficient data" do
      assert Volatility.realized([100, 101]) == nil
    end

    test "returns error for zero price" do
      prices = [100, 102, 0, 103, 101]
      assert Volatility.realized(prices) == {:error, :invalid_prices}
    end

    test "returns error for negative price" do
      prices = [100, 102, -5, 103, 101]
      assert Volatility.realized(prices) == {:error, :invalid_prices}
    end
  end

  describe "parkinson/2" do
    test "calculates parkinson volatility" do
      result = Volatility.parkinson(@sample_candles)

      assert result
      assert result > 0
    end

    test "annualizes parkinson volatility" do
      daily = Volatility.parkinson(@sample_candles)
      annual = Volatility.parkinson(@sample_candles, annualize: true)

      assert annual > daily
    end

    test "returns nil for insufficient data" do
      assert Volatility.parkinson([%{high: 100, low: 95}]) == nil
    end

    test "handles string keys" do
      candles = [
        %{"high" => 105, "low" => 98},
        %{"high" => 107, "low" => 100}
      ]

      result = Volatility.parkinson(candles)

      assert result
      assert result > 0
    end

    test "returns error for zero high/low" do
      candles = [
        %{high: 105, low: 98},
        %{high: 0, low: 100}
      ]

      assert Volatility.parkinson(candles) == {:error, :invalid_prices}
    end

    test "returns error for negative high/low" do
      candles = [
        %{high: 105, low: -5},
        %{high: 107, low: 100}
      ]

      assert Volatility.parkinson(candles) == {:error, :invalid_prices}
    end
  end

  describe "iv_percentile/2" do
    test "calculates percentile" do
      historical = [0.40, 0.55, 0.60, 0.70, 0.80]
      result = Volatility.iv_percentile(0.65, historical)

      # 0.65 is higher than 3 of 5 values (40, 55, 60)
      assert result == 60.0
    end

    test "returns 0 for lowest value" do
      historical = [0.50, 0.60, 0.70]
      result = Volatility.iv_percentile(0.40, historical)

      assert result == 0.0
    end

    test "returns 100 for highest value" do
      historical = [0.40, 0.50, 0.60]
      result = Volatility.iv_percentile(0.70, historical)

      assert result == 100.0
    end

    test "returns nil for empty history" do
      assert Volatility.iv_percentile(0.50, []) == nil
    end
  end

  describe "iv_rank/2" do
    test "calculates rank in range" do
      historical = [0.40, 0.55, 0.60, 0.70, 0.80]
      # Range: 0.40 to 0.80 = 0.40
      # 0.65 - 0.40 = 0.25
      # 0.25 / 0.40 = 0.625 = 62.5%
      result = Volatility.iv_rank(0.65, historical)

      assert_in_delta result, 62.5, 0.1
    end

    test "returns 0 at minimum" do
      historical = [0.40, 0.60, 0.80]
      result = Volatility.iv_rank(0.40, historical)

      assert result == 0.0
    end

    test "returns 100 at maximum" do
      historical = [0.40, 0.60, 0.80]
      result = Volatility.iv_rank(0.80, historical)

      assert result == 100.0
    end

    test "returns 50 for zero range" do
      historical = [0.50, 0.50, 0.50]
      result = Volatility.iv_rank(0.50, historical)

      assert result == 50.0
    end

    test "returns nil for insufficient data" do
      assert Volatility.iv_rank(0.50, [0.50]) == nil
    end
  end

  describe "iv_vs_rv/3" do
    test "calculates ratio by default" do
      result = Volatility.iv_vs_rv(0.65, 0.50)

      assert result == 1.3
    end

    test "calculates premium" do
      result = Volatility.iv_vs_rv(0.65, 0.50, :premium)

      assert_in_delta result, 0.15, 0.0001
    end

    test "calculates premium percentage" do
      result = Volatility.iv_vs_rv(0.65, 0.50, :premium_pct)

      assert_in_delta result, 30.0, 0.0001
    end

    test "handles IV discount" do
      result = Volatility.iv_vs_rv(0.40, 0.50)

      assert result == 0.8
    end

    test "returns nil for zero realized vol" do
      assert Volatility.iv_vs_rv(0.50, 0) == nil
    end
  end

  describe "cone/2" do
    test "calculates volatility for each period" do
      result = Volatility.cone(@sample_prices, [3, 5, 7])

      assert Map.has_key?(result, 3)
      assert Map.has_key?(result, 5)
      assert Map.has_key?(result, 7)
    end

    test "includes periods equal to available data length" do
      # 10 == length(@sample_prices)
      result = Volatility.cone(@sample_prices, [10])

      assert Map.has_key?(result, 10)
      assert is_float(result[10])
    end

    test "filters periods longer than data" do
      result = Volatility.cone(@sample_prices, [5, 20])

      assert Map.has_key?(result, 5)
      refute Map.has_key?(result, 20)
    end

    test "returns nil when realized volatility is unavailable" do
      # 2 prices is below realized/2 minimum
      prices = [100, 101]
      # period matches price count
      result = Volatility.cone(prices, [2])

      assert Map.has_key?(result, 2)
      assert result[2] == nil
    end
  end

  describe "elevated?/3" do
    test "returns true when above threshold" do
      assert Volatility.elevated?(0.45, 0.30)
    end

    test "returns false when below threshold" do
      refute Volatility.elevated?(0.40, 0.30)
    end

    test "uses custom threshold" do
      # 0.50 is not > 0.30 * 2 = 0.60
      refute Volatility.elevated?(0.50, 0.30, 2.0)
      # 0.65 is > 0.30 * 2 = 0.60
      assert Volatility.elevated?(0.65, 0.30, 2.0)
    end
  end

  describe "garman_klass/2" do
    test "calculates GK volatility" do
      result = Volatility.garman_klass(@sample_candles)

      assert result
      assert result > 0
    end

    test "annualizes GK volatility" do
      daily = Volatility.garman_klass(@sample_candles)
      annual = Volatility.garman_klass(@sample_candles, annualize: true)

      assert annual > daily
    end

    test "returns nil for insufficient data" do
      assert Volatility.garman_klass([%{open: 100, high: 105, low: 98, close: 103}]) == nil
    end

    test "handles string keys" do
      candles = [
        %{"open" => 100, "high" => 105, "low" => 98, "close" => 103},
        %{"open" => 103, "high" => 107, "low" => 100, "close" => 105}
      ]

      result = Volatility.garman_klass(candles)

      assert result
      assert result > 0
    end

    test "returns error for zero OHLC value" do
      candles = [
        %{open: 100, high: 105, low: 98, close: 103},
        %{open: 0, high: 107, low: 100, close: 105}
      ]

      assert Volatility.garman_klass(candles) == {:error, :invalid_prices}
    end

    test "returns error for negative OHLC value" do
      candles = [
        %{open: 100, high: 105, low: 98, close: -5},
        %{open: 103, high: 107, low: 100, close: 105}
      ]

      assert Volatility.garman_klass(candles) == {:error, :invalid_prices}
    end
  end

  describe "rolling/3" do
    test "calculates rolling volatility" do
      result = Volatility.rolling(@sample_prices, 5)

      # With 10 prices and window of 5, we get 6 volatility values
      assert length(result) == 6
      assert Enum.all?(result, &(&1 > 0))
    end

    test "returns correct number of values" do
      result = Volatility.rolling(@sample_prices, 3)

      # length(prices) - window + 1 = 10 - 3 + 1 = 8
      assert length(result) == 8
    end

    test "returns empty list for insufficient data" do
      result = Volatility.rolling([100, 101, 102], 5)

      assert result == []
    end

    test "annualizes rolling volatility" do
      daily = Volatility.rolling(@sample_prices, 5)
      annual = Volatility.rolling(@sample_prices, 5, annualize: true)

      # Each annualized value should be sqrt(365) times daily
      daily
      |> Enum.zip(annual)
      |> Enum.each(fn {d, a} ->
        assert_in_delta a / d, :math.sqrt(365), 0.01
      end)
    end

    test "uses custom trading days" do
      annual_365 = Volatility.rolling(@sample_prices, 5, annualize: true, trading_days: 365)
      annual_252 = Volatility.rolling(@sample_prices, 5, annualize: true, trading_days: 252)

      # 365 trading days gives higher annualized values
      annual_365
      |> Enum.zip(annual_252)
      |> Enum.each(fn {a365, a252} ->
        assert a365 > a252
      end)
    end

    test "window must be greater than 2" do
      # Window of 2 would give insufficient data for volatility calc
      assert_raise FunctionClauseError, fn ->
        Volatility.rolling(@sample_prices, 2)
      end
    end
  end
end
