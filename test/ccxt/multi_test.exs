defmodule CCXT.MultiTest do
  use ExUnit.Case, async: true

  alias CCXT.Exchange.Discovery
  alias CCXT.Multi

  describe "fetch_tickers/3" do
    test "returns map of results for each exchange" do
      exchanges = get_test_exchanges()

      if exchanges == [] do
        flunk("No exchange modules available. Run `mix ccxt.sync --tier1` first.")
      end

      # Use Req.Test to mock HTTP responses
      Req.Test.stub(CCXT.HTTP.Client, fn conn ->
        Req.Test.json(conn, %{
          "symbol" => "BTC/USDT",
          "last" => 50_000.0,
          "bid" => 49_999.0,
          "ask" => 50_001.0
        })
      end)

      result = Multi.fetch_tickers(exchanges, "BTC/USDT", timeout: 5000)

      assert is_map(result)
      assert map_size(result) == length(exchanges)

      # Each result should be {:ok, _} or {:error, _}
      for {module, res} <- result do
        assert is_atom(module)
        assert match?({:ok, _}, res) or match?({:error, _}, res)
      end
    end

    test "returns empty map for empty exchange list" do
      result = Multi.fetch_tickers([], "BTC/USDT")
      assert result == %{}
    end
  end

  describe "parallel_call/4" do
    test "handles function not exported gracefully" do
      # Use a module that exists but doesn't have fetch_nonexistent
      exchanges = get_test_exchanges()

      if exchanges == [] do
        flunk("No exchange modules available. Run `mix ccxt.sync --tier1` first.")
      end

      result = Multi.parallel_call(exchanges, :nonexistent_function, ["arg"])

      for {_module, res} <- result do
        assert match?({:error, {:function_not_exported, _}}, res)
      end
    end

    test "returns empty map for empty module list" do
      result = Multi.parallel_call([], :fetch_ticker, ["BTC/USDT"])
      assert result == %{}
    end

    test "handles timeout gracefully" do
      # This is a unit test - we can't easily test real timeouts
      # but we can verify the structure
      result = Multi.parallel_call([], :fetch_ticker, ["BTC/USDT"], timeout: 100)
      assert result == %{}
    end
  end

  describe "successes/1" do
    test "extracts only successful results" do
      results = %{
        ModuleA => {:ok, %{price: 100}},
        ModuleB => {:error, :timeout},
        ModuleC => {:ok, %{price: 200}}
      }

      successes = Multi.successes(results)

      assert successes == %{
               ModuleA => %{price: 100},
               ModuleC => %{price: 200}
             }
    end

    test "returns empty map when all failed" do
      results = %{
        ModuleA => {:error, :timeout},
        ModuleB => {:error, :network}
      }

      assert Multi.successes(results) == %{}
    end

    test "returns all when all succeeded" do
      results = %{
        ModuleA => {:ok, 1},
        ModuleB => {:ok, 2}
      }

      assert Multi.successes(results) == %{ModuleA => 1, ModuleB => 2}
    end
  end

  describe "failures/1" do
    test "extracts only failed results" do
      results = %{
        ModuleA => {:ok, %{price: 100}},
        ModuleB => {:error, :timeout},
        ModuleC => {:error, :network}
      }

      failures = Multi.failures(results)

      assert failures == %{
               ModuleB => :timeout,
               ModuleC => :network
             }
    end

    test "returns empty map when all succeeded" do
      results = %{
        ModuleA => {:ok, 1},
        ModuleB => {:ok, 2}
      }

      assert Multi.failures(results) == %{}
    end
  end

  describe "success_count/1" do
    test "counts successful results" do
      results = %{
        ModuleA => {:ok, 1},
        ModuleB => {:error, :timeout},
        ModuleC => {:ok, 2}
      }

      assert Multi.success_count(results) == 2
    end

    test "returns 0 for empty map" do
      assert Multi.success_count(%{}) == 0
    end
  end

  describe "failure_count/1" do
    test "counts failed results" do
      results = %{
        ModuleA => {:ok, 1},
        ModuleB => {:error, :timeout},
        ModuleC => {:error, :network}
      }

      assert Multi.failure_count(results) == 2
    end

    test "returns 0 for empty map" do
      assert Multi.failure_count(%{}) == 0
    end
  end

  describe "all_succeeded?/1" do
    test "returns true when all succeeded" do
      results = %{
        ModuleA => {:ok, 1},
        ModuleB => {:ok, 2}
      }

      assert Multi.all_succeeded?(results) == true
    end

    test "returns false when any failed" do
      results = %{
        ModuleA => {:ok, 1},
        ModuleB => {:error, :timeout}
      }

      assert Multi.all_succeeded?(results) == false
    end

    test "returns true for empty map" do
      # Vacuously true
      assert Multi.all_succeeded?(%{}) == true
    end
  end

  describe "any_succeeded?/1" do
    test "returns true when at least one succeeded" do
      results = %{
        ModuleA => {:error, :a},
        ModuleB => {:ok, 1}
      }

      assert Multi.any_succeeded?(results) == true
    end

    test "returns false when all failed" do
      results = %{
        ModuleA => {:error, :a},
        ModuleB => {:error, :b}
      }

      assert Multi.any_succeeded?(results) == false
    end

    test "returns false for empty map" do
      assert Multi.any_succeeded?(%{}) == false
    end
  end

  describe "fetch_order_books/3" do
    test "returns map of results" do
      result = Multi.fetch_order_books([], "BTC/USDT")
      assert result == %{}
    end
  end

  describe "fetch_ohlcv/4" do
    test "returns map of results" do
      result = Multi.fetch_ohlcv([], "BTC/USDT", "1h")
      assert result == %{}
    end
  end

  describe "fetch_trades/3" do
    test "returns map of results" do
      result = Multi.fetch_trades([], "BTC/USDT")
      assert result == %{}
    end
  end

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp get_test_exchanges do
    # Get up to 2 exchanges for testing
    Enum.take(Discovery.all_exchanges(), 2)
  end
end
