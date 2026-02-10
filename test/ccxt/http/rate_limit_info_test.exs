defmodule CCXT.HTTP.RateLimitInfoTest do
  use ExUnit.Case, async: true

  alias CCXT.HTTP.RateLimitInfo

  @moduletag :unit

  describe "should_wait?/2" do
    test "returns true when remaining is below threshold" do
      info = %RateLimitInfo{limit: 1200, remaining: 100, source: :binance_weight}
      # 100/1200 = 8.3% < 10% default threshold
      assert RateLimitInfo.should_wait?(info)
    end

    test "returns false when remaining is above threshold" do
      info = %RateLimitInfo{limit: 1200, remaining: 400, source: :binance_weight}
      # 400/1200 = 33.3% > 10%
      refute RateLimitInfo.should_wait?(info)
    end

    test "respects custom threshold" do
      info = %RateLimitInfo{limit: 1000, remaining: 300, source: :standard}
      # 300/1000 = 30% < 50% threshold
      assert RateLimitInfo.should_wait?(info, 0.5)
      # 300/1000 = 30% > 20% threshold
      refute RateLimitInfo.should_wait?(info, 0.2)
    end

    test "returns false when limit is nil" do
      info = %RateLimitInfo{limit: nil, remaining: 100, source: :binance_weight}
      refute RateLimitInfo.should_wait?(info)
    end

    test "returns false when remaining is nil" do
      info = %RateLimitInfo{limit: 1200, remaining: nil, source: :binance_weight}
      refute RateLimitInfo.should_wait?(info)
    end

    test "returns false when limit is zero" do
      info = %RateLimitInfo{limit: 0, remaining: 0, source: :standard}
      refute RateLimitInfo.should_wait?(info)
    end

    test "returns true when remaining is zero" do
      info = %RateLimitInfo{limit: 1200, remaining: 0, source: :standard}
      assert RateLimitInfo.should_wait?(info)
    end
  end

  describe "wait_time/1" do
    test "returns milliseconds until reset" do
      future_ms = System.system_time(:millisecond) + 5000
      info = %RateLimitInfo{reset_at: future_ms, source: :bybit_bapi}
      wait = RateLimitInfo.wait_time(info)
      # Should be approximately 5000ms (within 100ms tolerance for test execution time)
      assert wait > 4800
      assert wait <= 5100
    end

    test "returns 0 when reset_at is nil" do
      info = %RateLimitInfo{reset_at: nil, source: :binance_weight}
      assert RateLimitInfo.wait_time(info) == 0
    end

    test "returns 0 when reset_at is in the past" do
      past_ms = System.system_time(:millisecond) - 1000
      info = %RateLimitInfo{reset_at: past_ms, source: :standard}
      assert RateLimitInfo.wait_time(info) == 0
    end
  end

  describe "usage_percent/1" do
    test "calculates from used and limit" do
      info = %RateLimitInfo{used: 800, limit: 1200, source: :binance_weight}
      assert_in_delta RateLimitInfo.usage_percent(info), 66.67, 0.01
    end

    test "calculates from remaining and limit when used is nil" do
      info = %RateLimitInfo{remaining: 400, limit: 1200, source: :standard}
      # (1200 - 400) / 1200 * 100 = 66.67%
      assert_in_delta RateLimitInfo.usage_percent(info), 66.67, 0.01
    end

    test "prefers used over remaining when both present" do
      info = %RateLimitInfo{used: 600, remaining: 400, limit: 1200, source: :bybit_bapi}
      # Should use used: 600/1200 = 50%
      assert_in_delta RateLimitInfo.usage_percent(info), 50.0, 0.01
    end

    test "returns 100.0 when fully used" do
      info = %RateLimitInfo{used: 1200, limit: 1200, source: :binance_weight}
      assert_in_delta RateLimitInfo.usage_percent(info), 100.0, 0.01
    end

    test "returns 0.0 when nothing used" do
      info = %RateLimitInfo{used: 0, limit: 1200, source: :binance_weight}
      assert_in_delta RateLimitInfo.usage_percent(info), 0.0, 0.01
    end

    test "returns nil when limit is nil" do
      info = %RateLimitInfo{used: 800, limit: nil, source: :binance_weight}
      assert RateLimitInfo.usage_percent(info) == nil
    end

    test "returns nil when both used and remaining are nil" do
      info = %RateLimitInfo{limit: 1200, source: :standard}
      assert RateLimitInfo.usage_percent(info) == nil
    end

    test "returns nil when limit is zero" do
      info = %RateLimitInfo{used: 0, limit: 0, source: :standard}
      assert RateLimitInfo.usage_percent(info) == nil
    end
  end
end
