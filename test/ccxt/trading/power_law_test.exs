defmodule CCXT.Trading.PowerLawTest do
  use ExUnit.Case, async: true

  alias CCXT.Trading.PowerLaw

  describe "genesis_date/0" do
    test "returns Bitcoin genesis block date" do
      assert PowerLaw.genesis_date() == ~D[2009-01-03]
    end
  end

  describe "days_since_genesis/1" do
    test "calculates days from genesis to today" do
      days = PowerLaw.days_since_genesis()

      # Should be a large positive number (5000+ days as of 2023)
      assert days > 5000
    end

    test "calculates days for specific date" do
      # One year after genesis
      days = PowerLaw.days_since_genesis(~D[2010-01-03])

      assert days == 365
    end

    test "accepts DateTime" do
      {:ok, dt} = DateTime.new(~D[2010-01-03], ~T[12:00:00], "Etc/UTC")
      days = PowerLaw.days_since_genesis(dt)

      assert days == 365
    end
  end

  describe "fair_value/1" do
    test "returns positive value for today" do
      fair = PowerLaw.fair_value()

      assert fair > 0
      # Should be in reasonable BTC range (thousands to hundreds of thousands)
      assert fair > 1000
      assert fair < 10_000_000
    end

    test "returns higher value for later dates" do
      early = PowerLaw.fair_value(~D[2020-01-01])
      later = PowerLaw.fair_value(~D[2025-01-01])

      assert later > early
    end

    test "accepts integer days" do
      # 4000 days after genesis
      fair = PowerLaw.fair_value(4000)

      assert fair > 0
    end

    test "increases over time (power law growth)" do
      fair_1000 = PowerLaw.fair_value(1000)
      fair_2000 = PowerLaw.fair_value(2000)
      fair_4000 = PowerLaw.fair_value(4000)

      # Each should be higher than the previous
      assert fair_2000 > fair_1000
      assert fair_4000 > fair_2000
    end
  end

  describe "z_score/2" do
    test "returns positive for price above fair value" do
      fair = PowerLaw.fair_value()
      above_fair = fair * 1.5

      z = PowerLaw.z_score(above_fair)

      assert z > 0
    end

    test "returns negative for price below fair value" do
      fair = PowerLaw.fair_value()
      below_fair = fair * 0.5

      z = PowerLaw.z_score(below_fair)

      assert z < 0
    end

    test "returns approximately 0 for fair value price" do
      fair = PowerLaw.fair_value()

      z = PowerLaw.z_score(fair)

      assert_in_delta z, 0.0, 0.01
    end

    test "accepts date parameter" do
      date = ~D[2024-01-01]
      fair = PowerLaw.fair_value(date)

      z = PowerLaw.z_score(fair, date)

      assert_in_delta z, 0.0, 0.01
    end
  end

  describe "support/2" do
    test "returns value below fair value" do
      fair = PowerLaw.fair_value()
      support = PowerLaw.support()

      assert support < fair
    end

    test "respects deviation parameter" do
      support_1 = PowerLaw.support(nil, 1.0)
      support_2 = PowerLaw.support(nil, 2.0)

      # More deviations = lower support
      assert support_2 < support_1
    end
  end

  describe "resistance/2" do
    test "returns value above fair value" do
      fair = PowerLaw.fair_value()
      resistance = PowerLaw.resistance()

      assert resistance > fair
    end

    test "respects deviation parameter" do
      resistance_1 = PowerLaw.resistance(nil, 1.0)
      resistance_2 = PowerLaw.resistance(nil, 2.0)

      # More deviations = higher resistance
      assert resistance_2 > resistance_1
    end
  end

  describe "classify/2" do
    test "returns :fair for prices near fair value" do
      fair = PowerLaw.fair_value()

      assert PowerLaw.classify(fair) == :fair
      assert PowerLaw.classify(fair * 1.1) == :fair
      assert PowerLaw.classify(fair * 0.9) == :fair
    end

    test "returns :overvalued for high prices" do
      fair = PowerLaw.fair_value()
      # Well above trend but not extreme
      high_price = fair * 2.5

      result = PowerLaw.classify(high_price)

      assert result in [:overvalued, :extreme_high]
    end

    test "returns :undervalued for low prices" do
      fair = PowerLaw.fair_value()
      # Well below trend but not extreme
      low_price = fair * 0.4

      result = PowerLaw.classify(low_price)

      assert result in [:undervalued, :extreme_low]
    end

    test "returns :extreme_high for bubble prices" do
      fair = PowerLaw.fair_value()
      # Extremely above trend (>2 std dev in log space)
      # 10^(2 * 0.35) = ~5x, so need more than 5x
      bubble_price = fair * 10.0

      assert PowerLaw.classify(bubble_price) == :extreme_high
    end

    test "returns :extreme_low for crash prices" do
      fair = PowerLaw.fair_value()
      # Extremely below trend (>2 std dev)
      crash_price = fair * 0.15

      assert PowerLaw.classify(crash_price) == :extreme_low
    end
  end

  describe "model consistency" do
    test "support < fair < resistance" do
      support = PowerLaw.support()
      fair = PowerLaw.fair_value()
      resistance = PowerLaw.resistance()

      assert support < fair
      assert fair < resistance
    end

    test "corridor widens over time (same ratio)" do
      # The corridor width in log space stays constant
      # but in absolute terms it widens
      date1 = ~D[2020-01-01]
      date2 = ~D[2025-01-01]

      fair1 = PowerLaw.fair_value(date1)
      support1 = PowerLaw.support(date1)

      fair2 = PowerLaw.fair_value(date2)
      support2 = PowerLaw.support(date2)

      # Ratios should be approximately the same (log-space corridor is constant)
      ratio1 = fair1 / support1
      ratio2 = fair2 / support2

      assert_in_delta ratio1, ratio2, 0.1
    end
  end
end
