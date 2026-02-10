defmodule CCXT.Trading.Helpers.GreeksTest do
  use ExUnit.Case, async: true

  alias CCXT.Trading.Helpers.Greeks

  describe "days_to_expiry/1" do
    test "returns positive days for future expiry" do
      # 2 days in the future
      two_days_ms = 2 * 86_400_000
      future_ms = System.system_time(:millisecond) + two_days_ms

      result = Greeks.days_to_expiry(future_ms)

      # Should be approximately 2 days (within a small tolerance for test execution time)
      assert_in_delta result, 2.0, 0.01
    end

    test "returns negative days for past expiry" do
      # 1 day in the past
      one_day_ms = 86_400_000
      past_ms = System.system_time(:millisecond) - one_day_ms

      result = Greeks.days_to_expiry(past_ms)

      assert_in_delta result, -1.0, 0.01
    end

    test "returns fractional days" do
      # 12 hours in the future
      half_day_ms = 43_200_000
      future_ms = System.system_time(:millisecond) + half_day_ms

      result = Greeks.days_to_expiry(future_ms)

      assert_in_delta result, 0.5, 0.01
    end

    test "returns zero for current time" do
      now_ms = System.system_time(:millisecond)

      result = Greeks.days_to_expiry(now_ms)

      assert_in_delta result, 0.0, 0.01
    end
  end

  describe "days_to_expiry_from_datetime/1" do
    test "accepts DateTime and returns days" do
      # Create a DateTime 3 days in the future
      future = DateTime.add(DateTime.utc_now(), 3, :day)

      result = Greeks.days_to_expiry_from_datetime(future)

      assert_in_delta result, 3.0, 0.01
    end
  end

  describe "moneyness/3" do
    test "call option ITM when spot > strike" do
      assert Greeks.moneyness(50_000.0, 48_000.0, :call) == :itm
    end

    test "call option OTM when spot < strike" do
      assert Greeks.moneyness(50_000.0, 52_000.0, :call) == :otm
    end

    test "put option ITM when spot < strike" do
      assert Greeks.moneyness(50_000.0, 52_000.0, :put) == :itm
    end

    test "put option OTM when spot > strike" do
      assert Greeks.moneyness(50_000.0, 48_000.0, :put) == :otm
    end

    test "ATM when spot equals strike" do
      assert Greeks.moneyness(50_000.0, 50_000.0, :call) == :atm
      assert Greeks.moneyness(50_000.0, 50_000.0, :put) == :atm
    end

    test "ATM when spot within 0.1% of strike" do
      # 0.05% difference - should be ATM
      strike = 50_000.0
      spot = strike * 1.0005

      assert Greeks.moneyness(spot, strike, :call) == :atm
      assert Greeks.moneyness(spot, strike, :put) == :atm
    end

    test "not ATM when spot beyond 0.1% of strike" do
      # 0.2% difference - should NOT be ATM
      strike = 50_000.0
      spot = strike * 1.002

      assert Greeks.moneyness(spot, strike, :call) == :itm
      assert Greeks.moneyness(spot, strike, :put) == :otm
    end

    test "works with integer values" do
      assert Greeks.moneyness(50_000, 48_000, :call) == :itm
    end
  end
end
