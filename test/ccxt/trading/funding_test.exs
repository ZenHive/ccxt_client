defmodule CCXT.Trading.FundingTest do
  use ExUnit.Case, async: true

  alias CCXT.Trading.Funding
  alias CCXT.Types.FundingRate

  # Sample funding rates for testing
  @sample_rates [
    %FundingRate{
      symbol: "BTC/USDT:USDT",
      funding_rate: 0.0001,
      raw: %{}
    },
    %FundingRate{
      symbol: "BTC/USDT:USDT",
      funding_rate: 0.00015,
      raw: %{}
    },
    %FundingRate{
      symbol: "BTC/USDT:USDT",
      funding_rate: 0.00005,
      raw: %{}
    }
  ]

  describe "annualize/2" do
    test "converts 8-hour rate to APR" do
      # 0.01% per 8 hours = 10.95% APR
      result = Funding.annualize(0.0001)

      # 8760 hours/year / 8 hours = 1095 periods
      # 0.0001 * 1095 = 0.1095
      assert_in_delta result, 0.1095, 0.0001
    end

    test "handles custom period" do
      # 4-hour funding period
      result = Funding.annualize(0.0001, 4)

      # 8760 / 4 = 2190 periods
      assert_in_delta result, 0.219, 0.001
    end

    test "handles negative rates" do
      result = Funding.annualize(-0.0001)

      assert_in_delta result, -0.1095, 0.0001
    end

    test "returns 0 for zero rate" do
      assert Funding.annualize(0) == 0.0
    end
  end

  describe "average/1" do
    test "calculates average of rates" do
      result = Funding.average(@sample_rates)

      # (0.0001 + 0.00015 + 0.00005) / 3 = 0.0001
      assert_in_delta result, 0.0001, 0.00001
    end

    test "returns nil for empty list" do
      assert Funding.average([]) == nil
    end

    test "skips nil funding rates" do
      rates = [
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: nil, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0002, raw: %{}}
      ]

      result = Funding.average(rates)

      # (0.0001 + 0.0002) / 2 = 0.00015
      assert_in_delta result, 0.00015, 0.00001
    end

    test "returns nil when all rates are nil" do
      rates = [
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: nil, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: nil, raw: %{}}
      ]

      assert Funding.average(rates) == nil
    end
  end

  describe "detect_spikes/2" do
    test "detects high spikes" do
      # Need many normal values and one extreme outlier
      rates = [
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.01, raw: %{}}
      ]

      result = Funding.detect_spikes(rates, threshold: 2.0)

      assert [{:high, spike}] = result
      assert spike.funding_rate == 0.01
    end

    test "detects low spikes" do
      # Need many normal values and one extreme outlier
      rates = [
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: -0.01, raw: %{}}
      ]

      result = Funding.detect_spikes(rates, threshold: 2.0)

      assert [{:low, spike}] = result
      assert spike.funding_rate == -0.01
    end

    test "returns empty list when not enough data" do
      rates = [
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.001, raw: %{}}
      ]

      assert Funding.detect_spikes(rates) == []
    end

    test "returns empty list when all rates are equal" do
      rates = [
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}}
      ]

      assert Funding.detect_spikes(rates) == []
    end
  end

  describe "compare/1" do
    test "sorts rates descending by funding rate" do
      rates = [
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "ETH/USDT:USDT", funding_rate: 0.0002, raw: %{}},
        %FundingRate{symbol: "SOL/USDT:USDT", funding_rate: 0.00005, raw: %{}}
      ]

      result = Funding.compare(rates)

      assert length(result) == 3
      assert hd(result).symbol == "ETH/USDT:USDT"
      assert List.last(result).symbol == "SOL/USDT:USDT"
    end

    test "includes annualized APR" do
      rates = [%FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}}]

      [result] = Funding.compare(rates)

      assert result.rate == 0.0001
      assert_in_delta result.apr, 0.1095, 0.0001
    end

    test "filters nil rates" do
      rates = [
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "ETH/USDT:USDT", funding_rate: nil, raw: %{}}
      ]

      result = Funding.compare(rates)

      assert length(result) == 1
    end
  end

  describe "cumulative/1" do
    test "sums all funding rates" do
      result = Funding.cumulative(@sample_rates)

      # 0.0001 + 0.00015 + 0.00005 = 0.0003
      assert_in_delta result, 0.0003, 0.00001
    end

    test "returns 0 for empty list" do
      assert Funding.cumulative([]) == 0
    end

    test "skips nil rates" do
      rates = [
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: nil, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0002, raw: %{}}
      ]

      result = Funding.cumulative(rates)

      assert_in_delta result, 0.0003, 0.00001
    end
  end

  describe "volatility/1" do
    test "calculates standard deviation" do
      result = Funding.volatility(@sample_rates)

      # Should be positive for varying rates
      assert result > 0
    end

    test "returns nil for insufficient data" do
      rates = [%FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}}]

      assert Funding.volatility(rates) == nil
    end

    test "returns 0 for equal rates" do
      rates = [
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}},
        %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}}
      ]

      result = Funding.volatility(rates)

      assert result == 0.0
    end
  end

  describe "favorable?/2" do
    test "positive rate is favorable for shorts" do
      rate = %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001, raw: %{}}

      assert Funding.favorable?(rate, :short) == true
      assert Funding.favorable?(rate, :long) == false
    end

    test "negative rate is favorable for longs" do
      rate = %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: -0.0001, raw: %{}}

      assert Funding.favorable?(rate, :long) == true
      assert Funding.favorable?(rate, :short) == false
    end

    test "nil rate is never favorable" do
      rate = %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: nil, raw: %{}}

      assert Funding.favorable?(rate, :long) == false
      assert Funding.favorable?(rate, :short) == false
    end

    test "zero rate is not favorable for either" do
      rate = %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0, raw: %{}}

      assert Funding.favorable?(rate, :long) == false
      assert Funding.favorable?(rate, :short) == false
    end
  end
end
