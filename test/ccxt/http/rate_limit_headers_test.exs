defmodule CCXT.HTTP.RateLimitHeadersTest do
  use ExUnit.Case, async: true

  alias CCXT.HTTP.RateLimitHeaders
  alias CCXT.HTTP.RateLimitInfo

  @moduletag :unit

  describe "parse/3 - Binance pattern" do
    test "parses x-mbx-used-weight-1m" do
      headers = %{"x-mbx-used-weight-1m" => ["850"]}
      spec_rate_limits = %{requests: 1200}

      assert {:ok, %RateLimitInfo{} = info} = RateLimitHeaders.parse(:binance, headers, spec_rate_limits)

      assert info.exchange == :binance
      assert info.used == 850
      assert info.limit == 1200
      assert info.remaining == 350
      assert info.source == :binance_weight
      assert info.raw_headers["x-mbx-used-weight-1m"] == "850"
      assert info.raw_headers["matched"] == "x-mbx-used-weight-1m"
    end

    test "parses x-sapi-used-ip-weight-1m" do
      headers = %{"x-sapi-used-ip-weight-1m" => ["200"]}
      spec_rate_limits = %{requests: 1200}

      assert {:ok, %RateLimitInfo{} = info} = RateLimitHeaders.parse(:binance, headers, spec_rate_limits)

      assert info.used == 200
      assert info.limit == 1200
      assert info.remaining == 1000
      assert info.source == :binance_weight
      assert info.raw_headers["matched"] == "x-sapi-used-ip-weight-1m"
    end

    test "prefers x-mbx-used-weight-1m over x-sapi-used-ip-weight-1m" do
      headers = %{
        "x-mbx-used-weight-1m" => ["100"],
        "x-sapi-used-ip-weight-1m" => ["200"]
      }

      assert {:ok, info} = RateLimitHeaders.parse(:binance, headers, %{requests: 1200})
      assert info.used == 100
      assert info.raw_headers["matched"] == "x-mbx-used-weight-1m"
    end

    test "calculates remaining as 0 when used exceeds limit" do
      headers = %{"x-mbx-used-weight-1m" => ["1500"]}

      assert {:ok, info} = RateLimitHeaders.parse(:binance, headers, %{requests: 1200})
      assert info.remaining == 0
    end

    test "remaining is nil when spec_rate_limits is nil" do
      headers = %{"x-mbx-used-weight-1m" => ["850"]}

      assert {:ok, info} = RateLimitHeaders.parse(:binance, headers, nil)
      assert info.used == 850
      assert info.limit == nil
      assert info.remaining == nil
    end

    test "remaining is nil when spec_rate_limits has no requests key" do
      headers = %{"x-mbx-used-weight-1m" => ["850"]}

      assert {:ok, info} = RateLimitHeaders.parse(:binance, headers, %{period: 60_000})
      assert info.used == 850
      assert info.limit == nil
      assert info.remaining == nil
    end
  end

  describe "parse/3 - Bybit pattern" do
    test "parses all three Bybit headers" do
      headers = %{
        "x-bapi-limit" => ["120"],
        "x-bapi-limit-status" => ["95"],
        "x-bapi-limit-reset-timestamp" => ["1704067200000"]
      }

      assert {:ok, %RateLimitInfo{} = info} = RateLimitHeaders.parse(:bybit, headers)

      assert info.exchange == :bybit
      assert info.limit == 120
      assert info.remaining == 95
      assert info.used == 25
      assert info.reset_at == 1_704_067_200_000
      assert info.source == :bybit_bapi
      assert info.raw_headers["x-bapi-limit"] == "120"
      assert info.raw_headers["x-bapi-limit-status"] == "95"
      assert info.raw_headers["x-bapi-limit-reset-timestamp"] == "1704067200000"
    end

    test "handles partial Bybit headers (limit only)" do
      headers = %{"x-bapi-limit" => ["120"]}

      assert {:ok, info} = RateLimitHeaders.parse(:bybit, headers)
      assert info.limit == 120
      assert info.remaining == nil
      assert info.used == nil
      assert info.reset_at == nil
    end

    test "handles Bybit limit and status without reset" do
      headers = %{
        "x-bapi-limit" => ["120"],
        "x-bapi-limit-status" => ["95"]
      }

      assert {:ok, info} = RateLimitHeaders.parse(:bybit, headers)
      assert info.limit == 120
      assert info.remaining == 95
      assert info.used == 25
      assert info.reset_at == nil
    end
  end

  describe "parse/3 - Standard pattern" do
    test "parses standard x-ratelimit-* headers" do
      headers = %{
        "x-ratelimit-limit" => ["100"],
        "x-ratelimit-remaining" => ["75"],
        "x-ratelimit-reset" => ["1704067200"]
      }

      assert {:ok, %RateLimitInfo{} = info} = RateLimitHeaders.parse(:kucoin, headers)

      assert info.exchange == :kucoin
      assert info.limit == 100
      assert info.remaining == 75
      assert info.used == 25
      # Reset is in seconds, converted to ms
      assert info.reset_at == 1_704_067_200_000
      assert info.source == :standard
    end

    test "handles partial standard headers (limit only)" do
      headers = %{"x-ratelimit-limit" => ["100"]}

      assert {:ok, info} = RateLimitHeaders.parse(:kucoin, headers)
      assert info.limit == 100
      assert info.remaining == nil
      assert info.used == nil
      assert info.reset_at == nil
    end

    test "converts reset time from seconds to milliseconds" do
      headers = %{
        "x-ratelimit-limit" => ["100"],
        "x-ratelimit-reset" => ["1704067200"]
      }

      assert {:ok, info} = RateLimitHeaders.parse(:kucoin, headers)
      assert info.reset_at == 1_704_067_200 * 1000
    end
  end

  describe "parse/3 - no matching pattern" do
    test "returns :none for headers without rate limit info" do
      headers = %{
        "content-type" => ["application/json"],
        "date" => ["Mon, 01 Jan 2024 00:00:00 GMT"]
      }

      assert :none = RateLimitHeaders.parse(:okx, headers)
    end

    test "returns :none for empty headers" do
      assert :none = RateLimitHeaders.parse(:kraken, %{})
    end
  end

  describe "parse/3 - pattern priority" do
    test "Binance pattern takes priority over standard" do
      headers = %{
        "x-mbx-used-weight-1m" => ["500"],
        "x-ratelimit-limit" => ["100"]
      }

      assert {:ok, info} = RateLimitHeaders.parse(:binance, headers, %{requests: 1200})
      assert info.source == :binance_weight
    end

    test "Bybit pattern takes priority over standard" do
      headers = %{
        "x-bapi-limit" => ["120"],
        "x-ratelimit-limit" => ["100"]
      }

      assert {:ok, info} = RateLimitHeaders.parse(:bybit, headers)
      assert info.source == :bybit_bapi
    end
  end

  describe "parse/3 - malformed values" do
    test "handles non-numeric header values gracefully" do
      headers = %{"x-mbx-used-weight-1m" => ["not-a-number"]}

      assert {:ok, info} = RateLimitHeaders.parse(:binance, headers)
      assert info.used == nil
    end

    test "handles empty string header values" do
      headers = %{"x-bapi-limit" => [""]}

      assert {:ok, info} = RateLimitHeaders.parse(:bybit, headers)
      assert info.limit == nil
    end
  end
end
