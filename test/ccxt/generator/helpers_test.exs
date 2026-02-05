defmodule CCXT.Generator.HelpersTest do
  use ExUnit.Case, async: true

  alias CCXT.Generator.Helpers

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
end
