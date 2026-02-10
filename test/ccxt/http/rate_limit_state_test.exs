defmodule CCXT.HTTP.RateLimitStateTest do
  use ExUnit.Case, async: true

  alias CCXT.HTTP.RateLimitInfo
  alias CCXT.HTTP.RateLimitState

  @moduletag :unit

  # RateLimitState is started by CCXT.Application, so the ETS table exists.
  # Use unique exchange atoms to avoid cross-test interference.

  defp unique_exchange, do: :"state_test_#{System.unique_integer([:positive])}"

  describe "update/2 and status/1" do
    test "stores and retrieves rate limit info for public endpoint" do
      exchange = unique_exchange()
      info = %RateLimitInfo{exchange: exchange, limit: 1200, used: 500, remaining: 700, source: :binance_weight}

      assert :ok = RateLimitState.update({exchange, :public}, info)
      assert %RateLimitInfo{limit: 1200, used: 500} = RateLimitState.status(exchange)
    end

    test "returns nil for unknown exchange" do
      assert nil == RateLimitState.status(unique_exchange())
    end

    test "overwrites previous value on update" do
      exchange = unique_exchange()
      info1 = %RateLimitInfo{exchange: exchange, limit: 1200, used: 500, remaining: 700, source: :binance_weight}
      info2 = %RateLimitInfo{exchange: exchange, limit: 1200, used: 900, remaining: 300, source: :binance_weight}

      :ok = RateLimitState.update({exchange, :public}, info1)
      assert %RateLimitInfo{used: 500} = RateLimitState.status(exchange)

      :ok = RateLimitState.update({exchange, :public}, info2)
      assert %RateLimitInfo{used: 900} = RateLimitState.status(exchange)
    end
  end

  describe "status/2 with credential key" do
    test "stores and retrieves per-credential rate limit info" do
      exchange = unique_exchange()
      api_key = "test_key_123"

      info = %RateLimitInfo{exchange: exchange, limit: 120, remaining: 95, source: :bybit_bapi}
      :ok = RateLimitState.update({exchange, api_key}, info)

      assert %RateLimitInfo{limit: 120, remaining: 95} = RateLimitState.status(exchange, api_key)
    end

    test "separates public from credential-based status" do
      exchange = unique_exchange()
      api_key = "my_api_key"

      public_info = %RateLimitInfo{exchange: exchange, limit: 1200, used: 200, source: :binance_weight}
      private_info = %RateLimitInfo{exchange: exchange, limit: 120, used: 50, source: :bybit_bapi}

      :ok = RateLimitState.update({exchange, :public}, public_info)
      :ok = RateLimitState.update({exchange, api_key}, private_info)

      assert %RateLimitInfo{limit: 1200, used: 200} = RateLimitState.status(exchange)
      assert %RateLimitInfo{limit: 120, used: 50} = RateLimitState.status(exchange, api_key)
    end

    test "returns nil for unknown credential key" do
      exchange = unique_exchange()
      assert nil == RateLimitState.status(exchange, "nonexistent_key")
    end
  end

  describe "all/1" do
    test "returns all entries for an exchange" do
      exchange = unique_exchange()

      info1 = %RateLimitInfo{exchange: exchange, limit: 1200, used: 100, source: :binance_weight}
      info2 = %RateLimitInfo{exchange: exchange, limit: 120, used: 50, source: :binance_weight}

      :ok = RateLimitState.update({exchange, :public}, info1)
      :ok = RateLimitState.update({exchange, "key_abc"}, info2)

      all = RateLimitState.all(exchange)
      assert length(all) == 2
      assert Enum.any?(all, &(&1.limit == 1200))
      assert Enum.any?(all, &(&1.limit == 120))
    end

    test "returns empty list for unknown exchange" do
      assert [] == RateLimitState.all(unique_exchange())
    end

    test "does not return entries from other exchanges" do
      exchange_a = unique_exchange()
      exchange_b = unique_exchange()

      info_a = %RateLimitInfo{exchange: exchange_a, limit: 1200, source: :binance_weight}
      info_b = %RateLimitInfo{exchange: exchange_b, limit: 120, source: :bybit_bapi}

      :ok = RateLimitState.update({exchange_a, :public}, info_a)
      :ok = RateLimitState.update({exchange_b, :public}, info_b)

      assert [%RateLimitInfo{limit: 1200}] = RateLimitState.all(exchange_a)
      assert [%RateLimitInfo{limit: 120}] = RateLimitState.all(exchange_b)
    end
  end
end
