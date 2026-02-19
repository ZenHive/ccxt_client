defmodule CCXT.Generator.HelpersTest do
  use ExUnit.Case, async: true

  alias CCXT.Generator.Helpers
  alias CCXT.Generator.HelpersTest.OkTupleCoercer

  describe "apply_endpoint_mappings/2" do
    test "maps atom param keys using string-keyed mappings" do
      params = %{timeframe: "1h", symbol: "BTCUSDT"}
      mappings = %{"timeframe" => "interval", "since" => "startTime"}

      result = Helpers.apply_endpoint_mappings(params, mappings)

      # timeframe should be mapped to interval
      assert result["interval"] == "1h"
      # symbol has no mapping, but is normalized to string key
      assert result["symbol"] == "BTCUSDT"
      # Original atom keys should not be present
      refute Map.has_key?(result, :timeframe)
      refute Map.has_key?(result, :symbol)
    end

    test "normalizes keys even when mappings is empty" do
      params = %{timeframe: "1h", symbol: "BTCUSDT"}

      result = Helpers.apply_endpoint_mappings(params, %{})

      # Keys are normalized to strings even with empty mappings
      assert result == %{"timeframe" => "1h", "symbol" => "BTCUSDT"}
    end

    test "handles string param keys with string mappings" do
      params = %{"timeframe" => "1h", "symbol" => "BTCUSDT"}
      mappings = %{"timeframe" => "interval"}

      result = Helpers.apply_endpoint_mappings(params, mappings)

      assert result["interval"] == "1h"
      assert result["symbol"] == "BTCUSDT"
      refute Map.has_key?(result, "timeframe")
    end

    test "normalizes all keys to strings" do
      params = %{foo: "bar", baz: 123}
      mappings = %{"foo" => "mapped_foo"}

      result = Helpers.apply_endpoint_mappings(params, mappings)

      # foo is mapped to string key
      assert result["mapped_foo"] == "bar"
      # baz is normalized to string key (not preserved as atom)
      assert result["baz"] == 123
      refute Map.has_key?(result, :baz)
    end

    test "handles mixed key types in params" do
      params = %{"string_key" => "value2", atom_key: "value1"}
      mappings = %{"atom_key" => "mapped_atom", "string_key" => "mapped_string"}

      result = Helpers.apply_endpoint_mappings(params, mappings)

      assert result["mapped_atom"] == "value1"
      assert result["mapped_string"] == "value2"
    end
  end

  describe "convert_ohlcv_timestamp/2" do
    # 2024-01-01 00:00:00 UTC in milliseconds
    @test_timestamp_ms 1_704_067_200_000
    @test_timestamp_s 1_704_067_200

    test "returns milliseconds unchanged for :milliseconds resolution" do
      assert Helpers.convert_ohlcv_timestamp(@test_timestamp_ms, :milliseconds) == @test_timestamp_ms
    end

    test "converts to seconds for :seconds resolution" do
      assert Helpers.convert_ohlcv_timestamp(@test_timestamp_ms, :seconds) == @test_timestamp_s
    end

    test "returns milliseconds unchanged for :unknown resolution" do
      assert Helpers.convert_ohlcv_timestamp(@test_timestamp_ms, :unknown) == @test_timestamp_ms
    end

    test "returns nil unchanged" do
      assert Helpers.convert_ohlcv_timestamp(nil, :milliseconds) == nil
      assert Helpers.convert_ohlcv_timestamp(nil, :seconds) == nil
      assert Helpers.convert_ohlcv_timestamp(nil, :unknown) == nil
    end
  end

  describe "convert_ohlcv_timestamps/2" do
    # 2024-01-01 00:00:00 UTC in milliseconds
    @test_timestamp_ms 1_704_067_200_000
    @test_timestamp_s 1_704_067_200

    test "converts all timestamp params for :seconds resolution" do
      params = %{
        :since => @test_timestamp_ms,
        "to" => @test_timestamp_ms,
        "from" => @test_timestamp_ms,
        "other" => "unchanged"
      }

      result = Helpers.convert_ohlcv_timestamps(params, :seconds)

      assert result[:since] == @test_timestamp_s
      assert result["to"] == @test_timestamp_s
      assert result["from"] == @test_timestamp_s
      assert result["other"] == "unchanged"
    end

    test "leaves timestamps unchanged for :milliseconds resolution" do
      params = %{:since => @test_timestamp_ms, "to" => @test_timestamp_ms}

      result = Helpers.convert_ohlcv_timestamps(params, :milliseconds)

      assert result[:since] == @test_timestamp_ms
      assert result["to"] == @test_timestamp_ms
    end

    test "handles mixed timestamp and non-timestamp params" do
      params = %{
        :since => @test_timestamp_ms,
        "symbol" => "BTCUSDT",
        "limit" => 100,
        "to" => @test_timestamp_ms
      }

      result = Helpers.convert_ohlcv_timestamps(params, :seconds)

      assert result[:since] == @test_timestamp_s
      assert result["to"] == @test_timestamp_s
      assert result["symbol"] == "BTCUSDT"
      assert result["limit"] == 100
    end

    test "handles empty params" do
      assert Helpers.convert_ohlcv_timestamps(%{}, :seconds) == %{}
    end
  end

  # ===========================================================================
  # Task 23: Coverage gap tests
  # ===========================================================================

  describe "get_path_param/3" do
    test "returns value for atom key present in params" do
      params = %{symbol: "BTCUSDT", limit: 100}
      assert Helpers.get_path_param(params, :symbol, "symbol") == "BTCUSDT"
    end

    test "falls back to string key when atom key missing" do
      params = %{"order_id" => "abc-123"}
      assert Helpers.get_path_param(params, :order_id, "order_id") == "abc-123"
    end

    test "returns empty string when neither key present" do
      params = %{other: "value"}
      assert Helpers.get_path_param(params, :missing, "missing") == ""
    end

    test "atom key takes precedence over string key" do
      params = Map.put(%{symbol: "ATOM_VALUE"}, "symbol", "STRING_VALUE")
      assert Helpers.get_path_param(params, :symbol, "symbol") == "ATOM_VALUE"
    end

    test "converts non-string values to string" do
      params = %{limit: 100}
      assert Helpers.get_path_param(params, :limit, "limit") == "100"
    end
  end

  describe "resolve_generated_placeholders/1" do
    test "preserves params without <generated> placeholder" do
      params = %{"symbol" => "BTC", "limit" => 100}
      result = Helpers.resolve_generated_placeholders(params)
      assert result == %{"symbol" => "BTC", "limit" => 100}
    end

    test "replaces end_timestamp <generated> with current timestamp" do
      params = %{"end_timestamp" => "<generated>", "symbol" => "BTC"}
      result = Helpers.resolve_generated_placeholders(params)

      assert is_integer(result["end_timestamp"])
      now_ms = System.system_time(:millisecond)
      # Should be within 2 seconds of now (generous for CI)
      assert abs(result["end_timestamp"] - now_ms) < 2000
      assert result["symbol"] == "BTC"
    end

    test "replaces start_timestamp <generated> with one-hour-ago timestamp" do
      params = %{"start_timestamp" => "<generated>"}
      result = Helpers.resolve_generated_placeholders(params)

      assert is_integer(result["start_timestamp"])
      one_hour_ago = System.system_time(:millisecond) - 3_600_000
      # Should be within 1 second of one-hour-ago
      assert abs(result["start_timestamp"] - one_hour_ago) < 2000
    end

    test "replaces startTime <generated> with one-hour-ago timestamp" do
      params = %{"startTime" => "<generated>"}
      result = Helpers.resolve_generated_placeholders(params)

      assert is_integer(result["startTime"])
      one_hour_ago = System.system_time(:millisecond) - 3_600_000
      assert abs(result["startTime"] - one_hour_ago) < 2000
    end

    test "replaces endTime <generated> with current timestamp" do
      params = %{"endTime" => "<generated>"}
      result = Helpers.resolve_generated_placeholders(params)

      assert is_integer(result["endTime"])
      now_ms = System.system_time(:millisecond)
      assert abs(result["endTime"] - now_ms) < 2000
    end

    test "filters out non-timestamp params with <generated> placeholder" do
      params = %{"nonce" => "<generated>", "symbol" => "BTC"}
      result = Helpers.resolve_generated_placeholders(params)

      refute Map.has_key?(result, "nonce")
      assert result["symbol"] == "BTC"
    end

    test "handles mix of generated and non-generated params" do
      params = %{
        "end_timestamp" => "<generated>",
        "nonce" => "<generated>",
        "symbol" => "BTC",
        "limit" => 100
      }

      result = Helpers.resolve_generated_placeholders(params)

      assert is_integer(result["end_timestamp"])
      refute Map.has_key?(result, "nonce")
      assert result["symbol"] == "BTC"
      assert result["limit"] == 100
    end
  end

  describe "denormalize_symbol_param/3" do
    @binance_spec %CCXT.Spec{
      id: "binance",
      name: "Binance",
      urls: %{api: "https://api.binance.com"},
      symbol_format: %{separator: "", case: :upper}
    }

    test "denormalizes symbol when present in params" do
      params = %{symbol: "BTC/USDT", limit: 100}
      result = Helpers.denormalize_symbol_param(params, @binance_spec, nil)

      # Binance format: no separator, upper case
      assert result[:symbol] == "BTCUSDT"
      assert result[:limit] == 100
    end

    test "returns params unchanged when symbol is nil" do
      params = %{limit: 100}
      result = Helpers.denormalize_symbol_param(params, @binance_spec, nil)

      assert result == %{limit: 100}
    end

    test "returns params unchanged when symbol is empty string" do
      params = %{symbol: "", limit: 100}
      result = Helpers.denormalize_symbol_param(params, @binance_spec, nil)

      assert result == %{symbol: "", limit: 100}
    end
  end

  # ===========================================================================
  # Task 208: execute_request/9 coercer pipeline tests
  # ===========================================================================

  describe "execute_request/9 coercer pipeline" do
    @test_spec %CCXT.Spec{
      id: "test",
      name: "Test",
      urls: %{api: "https://test.example.com"}
    }

    setup do
      stub_name = :"helpers_test_#{System.unique_integer([:positive])}"
      %{stub_name: stub_name}
    end

    test "without coercer — returns raw transformed response", %{stub_name: stub_name} do
      Req.Test.stub(stub_name, fn conn ->
        Req.Test.json(conn, %{"price" => "50000", "symbol" => "BTC/USDT"})
      end)

      assert {:ok, %{"price" => "50000", "symbol" => "BTC/USDT"}} =
               Helpers.execute_request(
                 @test_spec,
                 :get,
                 "/ticker",
                 [plug: {Req.Test, stub_name}],
                 nil,
                 nil,
                 nil,
                 []
               )
    end

    test "without coercer (explicit nil 9th arg) — same as default", %{stub_name: stub_name} do
      Req.Test.stub(stub_name, fn conn ->
        Req.Test.json(conn, %{"data" => [1, 2, 3]})
      end)

      assert {:ok, %{"data" => [1, 2, 3]}} =
               Helpers.execute_request(
                 @test_spec,
                 :get,
                 "/data",
                 [plug: {Req.Test, stub_name}],
                 nil,
                 nil,
                 nil,
                 [],
                 nil
               )
    end

    test "with coercer — delegates to coercer.coerce/4", %{stub_name: stub_name} do
      Req.Test.stub(stub_name, fn conn ->
        Req.Test.json(conn, %{"price" => "50000"})
      end)

      assert {:ok, {:coerced, %{"price" => "50000"}, :ticker, [], :parser_fn}} =
               Helpers.execute_request(
                 @test_spec,
                 :get,
                 "/ticker",
                 [plug: {Req.Test, stub_name}],
                 nil,
                 :ticker,
                 :parser_fn,
                 [],
                 OkTupleCoercer
               )
    end

    test "with coercer, nil parser_mapping — coercer receives nil", %{stub_name: stub_name} do
      Req.Test.stub(stub_name, fn conn ->
        Req.Test.json(conn, %{"balance" => "100"})
      end)

      assert {:ok, {:coerced, %{"balance" => "100"}, :balance, [format: :raw], nil}} =
               Helpers.execute_request(
                 @test_spec,
                 :get,
                 "/balance",
                 [plug: {Req.Test, stub_name}],
                 nil,
                 :balance,
                 nil,
                 [format: :raw],
                 OkTupleCoercer
               )
    end

    test "coercer returning bare value gets wrapped in {:ok, ...}", %{stub_name: stub_name} do
      Req.Test.stub(stub_name, fn conn ->
        Req.Test.json(conn, %{"price" => "50000"})
      end)

      assert {:ok, :bare_result} =
               Helpers.execute_request(
                 @test_spec,
                 :get,
                 "/ticker",
                 [plug: {Req.Test, stub_name}],
                 nil,
                 :ticker,
                 nil,
                 [],
                 CCXT.Generator.HelpersTest.BareValueCoercer
               )
    end

    test "coercer returning {:error, reason} propagates error", %{stub_name: stub_name} do
      Req.Test.stub(stub_name, fn conn ->
        Req.Test.json(conn, %{"price" => "50000"})
      end)

      assert {:error, :coerce_failed} =
               Helpers.execute_request(
                 @test_spec,
                 :get,
                 "/ticker",
                 [plug: {Req.Test, stub_name}],
                 nil,
                 :ticker,
                 nil,
                 [],
                 CCXT.Generator.HelpersTest.ErrorCoercer
               )
    end

    test "HTTP error propagates without coercer involvement", %{stub_name: stub_name} do
      Req.Test.stub(stub_name, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => "internal"})
      end)

      result =
        Helpers.execute_request(
          @test_spec,
          :get,
          "/ticker",
          [plug: {Req.Test, stub_name}],
          nil,
          :ticker,
          nil,
          [],
          OkTupleCoercer
        )

      # HTTP errors are handled by Client before reaching coercer
      assert {:error, _} = result
    end
  end
end

# Test coercer modules — defined outside the test module for clean module naming
defmodule CCXT.Generator.HelpersTest.OkTupleCoercer do
  @moduledoc false
  def coerce(data, response_type, user_opts, parser_mapping) do
    {:ok, {:coerced, data, response_type, user_opts, parser_mapping}}
  end
end

defmodule CCXT.Generator.HelpersTest.BareValueCoercer do
  @moduledoc false
  def coerce(_data, _response_type, _user_opts, _parser_mapping), do: :bare_result
end

defmodule CCXT.Generator.HelpersTest.ErrorCoercer do
  @moduledoc false
  def coerce(_data, _response_type, _user_opts, _parser_mapping), do: {:error, :coerce_failed}
end
