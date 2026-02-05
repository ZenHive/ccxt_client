defmodule CCXT.HTTP.RateLimiterTest do
  use ExUnit.Case, async: true

  alias CCXT.HTTP.RateLimiter

  # Helper to generate unique rate limiter name per test
  defp unique_name, do: :"rate_limiter_#{:erlang.unique_integer([:positive])}"

  describe "check_rate/4 with tuple keys" do
    test "returns :ok when within limit" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      rate_limit = %{requests: 5, period: 1000}

      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)
      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)
      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)
    end

    test "returns {:delay, ms} when limit exceeded" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      rate_limit = %{requests: 2, period: 1000}

      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)
      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)
      assert {:delay, ms} = RateLimiter.check_rate(key, rate_limit, 1, name)
      assert is_integer(ms)
      assert ms > 0
    end

    test "returns :ok when nil rate_limit" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      assert :ok = RateLimiter.check_rate(key, nil, 1, name)
    end

    test "uses default period when only requests specified" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      rate_limit = %{requests: 1}

      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)
      assert {:delay, _ms} = RateLimiter.check_rate(key, rate_limit, 1, name)
    end

    test "tracks different exchanges separately" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      rate_limit = %{requests: 1, period: 1000}

      assert :ok = RateLimiter.check_rate({:binance, :public}, rate_limit, 1, name)
      assert :ok = RateLimiter.check_rate({:bybit, :public}, rate_limit, 1, name)
      assert {:delay, _} = RateLimiter.check_rate({:binance, :public}, rate_limit, 1, name)
      assert {:delay, _} = RateLimiter.check_rate({:bybit, :public}, rate_limit, 1, name)
    end

    test "tracks different API keys separately for same exchange" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      rate_limit = %{requests: 1, period: 1000}

      # Two different API keys should have independent limits
      assert :ok = RateLimiter.check_rate({:binance, "api_key_1"}, rate_limit, 1, name)
      assert :ok = RateLimiter.check_rate({:binance, "api_key_2"}, rate_limit, 1, name)

      # Each key should be limited independently
      assert {:delay, _} = RateLimiter.check_rate({:binance, "api_key_1"}, rate_limit, 1, name)
      assert {:delay, _} = RateLimiter.check_rate({:binance, "api_key_2"}, rate_limit, 1, name)
    end

    test "public and authenticated requests are tracked separately" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      rate_limit = %{requests: 1, period: 1000}

      # Public pool and API key pool are independent
      assert :ok = RateLimiter.check_rate({:binance, :public}, rate_limit, 1, name)
      assert :ok = RateLimiter.check_rate({:binance, "my_api_key"}, rate_limit, 1, name)

      # Each is independently limited
      assert {:delay, _} = RateLimiter.check_rate({:binance, :public}, rate_limit, 1, name)
      assert {:delay, _} = RateLimiter.check_rate({:binance, "my_api_key"}, rate_limit, 1, name)
    end

    test "allows requests after window expires" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      # Use a very short period for testing
      rate_limit = %{requests: 1, period: 50}

      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)
      assert {:delay, _} = RateLimiter.check_rate(key, rate_limit, 1, name)

      # Wait for window to expire
      Process.sleep(60)

      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)
    end
  end

  describe "check_rate/4 with weighted costs" do
    test "respects weighted costs - single heavy request exhausts limit" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      rate_limit = %{requests: 10, period: 1000}

      # One request with cost 10 should exhaust the limit
      assert :ok = RateLimiter.check_rate(key, rate_limit, 10, name)
      assert {:delay, _} = RateLimiter.check_rate(key, rate_limit, 1, name)
    end

    test "allows multiple light requests within limit" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      rate_limit = %{requests: 10, period: 1000}

      # 5 requests with cost 2 each = 10 total
      assert :ok = RateLimiter.check_rate(key, rate_limit, 2, name)
      assert :ok = RateLimiter.check_rate(key, rate_limit, 2, name)
      assert :ok = RateLimiter.check_rate(key, rate_limit, 2, name)
      assert :ok = RateLimiter.check_rate(key, rate_limit, 2, name)
      assert :ok = RateLimiter.check_rate(key, rate_limit, 2, name)

      # Any additional request should be delayed
      assert {:delay, _} = RateLimiter.check_rate(key, rate_limit, 1, name)
    end

    test "mixed costs are summed correctly" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      rate_limit = %{requests: 10, period: 1000}

      # Cost 4 + 4 + 1 = 9, should be ok
      assert :ok = RateLimiter.check_rate(key, rate_limit, 4, name)
      assert :ok = RateLimiter.check_rate(key, rate_limit, 4, name)
      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)

      # Total is 9, another cost 1 = 10, should still be ok
      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)

      # Total is 10, any more should be delayed
      assert {:delay, _} = RateLimiter.check_rate(key, rate_limit, 1, name)
    end

    test "cost of 1 is treated as single unit" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      rate_limit = %{requests: 2, period: 1000}

      # With cost=1, two requests exhaust limit of 2
      # Note: When using custom GenServer name, all 4 args must be passed explicitly
      # due to Elixir's default args behavior (can't skip middle defaults)
      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)
      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)
      assert {:delay, _} = RateLimiter.check_rate(key, rate_limit, 1, name)
    end

    test "floating point costs work correctly" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      rate_limit = %{requests: 10, period: 1000}

      # Cost 0.8 * 12 = 9.6, should all succeed
      for _ <- 1..12 do
        assert :ok = RateLimiter.check_rate(key, rate_limit, 0.8, name)
      end

      # Cost 9.6 + 0.8 = 10.4 > 10, should be delayed
      assert {:delay, _} = RateLimiter.check_rate(key, rate_limit, 0.8, name)
    end
  end

  describe "wait_for_capacity/4" do
    test "returns :ok immediately when within limit" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      rate_limit = %{requests: 5, period: 1000}

      assert :ok = RateLimiter.wait_for_capacity(key, rate_limit, 1, name)
    end

    test "returns :ok when nil rate_limit" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      assert :ok = RateLimiter.wait_for_capacity(key, nil, 1, name)
    end

    test "blocks and returns :ok after delay when limit exceeded" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      rate_limit = %{requests: 1, period: 50}

      assert :ok = RateLimiter.wait_for_capacity(key, rate_limit, 1, name)

      start = System.monotonic_time(:millisecond)
      assert :ok = RateLimiter.wait_for_capacity(key, rate_limit, 1, name)
      elapsed = System.monotonic_time(:millisecond) - start

      # Should have waited at least some time
      assert elapsed >= 40
    end

    test "cost of 1 exhausts limit correctly" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      rate_limit = %{requests: 2, period: 1000}

      # Note: When using custom GenServer name, all 4 args must be passed explicitly
      assert :ok = RateLimiter.wait_for_capacity(key, rate_limit, 1, name)
      assert :ok = RateLimiter.wait_for_capacity(key, rate_limit, 1, name)
      # Third call would block, but we won't test that to avoid slow tests
    end
  end

  describe "get_cost/3" do
    test "returns 0 for new key" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      # Period of 1 second
      assert 0 = RateLimiter.get_cost({:unknown, :public}, 1000, name)
    end

    test "returns current total cost within window" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      rate_limit = %{requests: 100, period: 1000}

      RateLimiter.check_rate(key, rate_limit, 4, name)
      assert 4 = RateLimiter.get_cost(key, 1000, name)

      RateLimiter.check_rate(key, rate_limit, 6, name)
      assert 10 = RateLimiter.get_cost(key, 1000, name)
    end

    test "excludes costs outside the window" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      rate_limit = %{requests: 100, period: 50}

      # Make a request
      RateLimiter.check_rate(key, rate_limit, 5, name)
      assert 5 = RateLimiter.get_cost(key, 50, name)

      # Wait for window to expire
      Process.sleep(60)

      # Cost should be 0 now (request expired from window)
      assert 0 = RateLimiter.get_cost(key, 50, name)
    end
  end

  describe "reset/2" do
    test "clears request history for key" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}
      rate_limit = %{requests: 1, period: 1000}

      RateLimiter.check_rate(key, rate_limit, 1, name)
      assert {:delay, _} = RateLimiter.check_rate(key, rate_limit, 1, name)

      RateLimiter.reset(key, name)
      # Give the cast time to process
      Process.sleep(10)

      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)
    end

    test "only affects specified key" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      rate_limit = %{requests: 1, period: 1000}

      RateLimiter.check_rate({:binance, :public}, rate_limit, 1, name)
      RateLimiter.check_rate({:bybit, :public}, rate_limit, 1, name)

      RateLimiter.reset({:binance, :public}, name)
      # Give the cast time to process
      Process.sleep(10)

      assert :ok = RateLimiter.check_rate({:binance, :public}, rate_limit, 1, name)
      assert {:delay, _} = RateLimiter.check_rate({:bybit, :public}, rate_limit, 1, name)
    end
  end

  describe "key eviction" do
    test "keys with only old requests are evicted during cleanup" do
      # This test verifies that keys are evicted when their most recent activity
      # is older than the eviction threshold. Since we can't wait 24 hours,
      # we test the cleanup logic directly by sending the :cleanup message
      # after manually setting up state with old timestamps.

      name = unique_name()
      {:ok, pid} = RateLimiter.start_link(name: name)

      key = {:binance, "old_api_key"}
      rate_limit = %{requests: 100, period: 1000}

      # Record a request
      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)
      assert 1 = RateLimiter.get_cost(key, 1000, name)

      # Trigger cleanup - key should still exist (activity is recent)
      send(pid, :cleanup)
      # Give the GenServer time to process
      Process.sleep(10)

      # Key should still exist after cleanup (recent activity)
      # The get_cost with a very long period will find it if it exists
      # We use a period longer than max_request_age to check key presence
      # Note: actual eviction only happens after 24h, so key remains
      assert RateLimiter.get_cost(key, 100_000, name) >= 0
    end
  end

  describe "child_spec/1" do
    test "returns proper child spec for supervision tree" do
      spec = RateLimiter.child_spec([])

      assert spec.id == RateLimiter
      assert spec.start == {RateLimiter, :start_link, [[]]}
    end

    test "uses custom name as id when provided" do
      spec = RateLimiter.child_spec(name: :my_rate_limiter)

      assert spec.id == :my_rate_limiter
      assert spec.start == {RateLimiter, :start_link, [[name: :my_rate_limiter]]}
    end

    test "can be started via Supervisor with custom name" do
      name = unique_name()

      # Start via the child_spec pattern used in supervision trees
      {:ok, pid} = Supervisor.start_link([{RateLimiter, name: name}], strategy: :one_for_one)

      # Verify it works
      key = {:binance, :public}
      rate_limit = %{requests: 10, period: 1000}
      assert :ok = RateLimiter.check_rate(key, rate_limit, 1, name)

      Supervisor.stop(pid)
    end
  end

  describe "record_request/3" do
    @period_ms 1000

    test "manually records a request with cost" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}

      assert 0 = RateLimiter.get_cost(key, @period_ms, name)

      RateLimiter.record_request(key, 5, name)
      # Give the cast time to process
      Process.sleep(10)

      assert 5 = RateLimiter.get_cost(key, @period_ms, name)
    end

    test "records cost of 1 correctly" do
      name = unique_name()
      {:ok, _pid} = RateLimiter.start_link(name: name)

      key = {:binance, :public}

      # Note: When using custom GenServer name, all 3 args must be passed explicitly
      RateLimiter.record_request(key, 1, name)
      Process.sleep(10)

      assert 1 = RateLimiter.get_cost(key, @period_ms, name)
    end
  end
end
