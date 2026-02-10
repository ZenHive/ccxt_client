defmodule CCXT.ResponseParserTest do
  use ExUnit.Case, async: true

  alias CCXT.ResponseParser

  describe "parse_single/2" do
    test "returns data unchanged when mapping is nil" do
      data = %{"askPrice" => "42000"}
      assert ResponseParser.parse_single(data, nil) == data
    end

    test "returns data unchanged when mapping is empty list" do
      data = %{"askPrice" => "42000"}
      assert ResponseParser.parse_single(data, []) == data
    end

    test "returns data unchanged when data is not a map" do
      assert ResponseParser.parse_single("not a map", [{:ask, :number, ["askPrice"]}]) == "not a map"
    end

    test "applies number coercion from string" do
      data = %{"askPrice" => "42000.50"}
      instructions = [{:ask, :number, ["askPrice"]}]
      result = ResponseParser.parse_single(data, instructions)

      assert result["ask"] == 42_000.50
      # Original key preserved
      assert result["askPrice"] == "42000.50"
    end

    test "applies number coercion from integer" do
      data = %{"volume" => 1000}
      instructions = [{:base_volume, :number, ["volume"]}]
      result = ResponseParser.parse_single(data, instructions)

      assert result["baseVolume"] == 1000
    end

    test "applies string coercion" do
      data = %{"s" => "BTCUSDT"}
      instructions = [{:symbol, :string, ["s"]}]
      result = ResponseParser.parse_single(data, instructions)

      assert result["symbol"] == "BTCUSDT"
    end

    test "applies integer coercion" do
      data = %{"ts" => "1704067200000"}
      instructions = [{:timestamp, :integer, ["ts"]}]
      result = ResponseParser.parse_single(data, instructions)

      assert result["timestamp"] == 1_704_067_200_000
    end

    test "applies bool coercion" do
      data = %{"isReduceOnly" => true}
      instructions = [{:reduce_only, :bool, ["isReduceOnly"]}]
      result = ResponseParser.parse_single(data, instructions)

      assert result["reduceOnly"] == true
    end

    test "applies value coercion (passthrough)" do
      data = %{"extra" => [1, 2, 3]}
      instructions = [{:extra, :value, ["extra"]}]
      result = ResponseParser.parse_single(data, instructions)

      assert result["extra"] == [1, 2, 3]
    end

    test "tries source keys in order (multi-key fallback)" do
      # First key missing, second key present
      data = %{"ask1Size" => "1.5"}
      instructions = [{:ask_volume, :number, ["askSize", "ask1Size"]}]
      result = ResponseParser.parse_single(data, instructions)

      assert result["askVolume"] == 1.5
    end

    test "first matching key wins in multi-key lookup" do
      data = %{"askSize" => "2.0", "ask1Size" => "1.5"}
      instructions = [{:ask_volume, :number, ["askSize", "ask1Size"]}]
      result = ResponseParser.parse_single(data, instructions)

      assert result["askVolume"] == 2.0
    end

    test "skips instructions with empty source_keys" do
      data = %{"askPrice" => "42000"}
      instructions = [{:ask, :number, []}]
      result = ResponseParser.parse_single(data, instructions)

      refute Map.has_key?(result, "ask")
    end

    test "skips instructions where source key is not found" do
      data = %{"other" => "value"}
      instructions = [{:ask, :number, ["askPrice"]}]
      result = ResponseParser.parse_single(data, instructions)

      refute Map.has_key?(result, "ask")
      assert result["other"] == "value"
    end

    test "preserves all original keys in output" do
      data = %{"askPrice" => "42000", "extra" => "kept", "nested" => %{"a" => 1}}
      instructions = [{:ask, :number, ["askPrice"]}]
      result = ResponseParser.parse_single(data, instructions)

      assert result["askPrice"] == "42000"
      assert result["extra"] == "kept"
      assert result["nested"] == %{"a" => 1}
      assert result["ask"] == 42_000.0
    end

    test "handles multiple instructions" do
      data = %{"askPrice" => "42000.50", "bidPrice" => "41999.00", "lastPrice" => "42000.00"}

      instructions = [
        {:ask, :number, ["askPrice"]},
        {:bid, :number, ["bidPrice"]},
        {:last, :number, ["lastPrice"]}
      ]

      result = ResponseParser.parse_single(data, instructions)

      assert result["ask"] == 42_000.50
      assert result["bid"] == 41_999.00
      assert result["last"] == 42_000.00
    end

    test "maps snake_case field atoms to camelCase unified keys" do
      data = %{"bidSize" => "2.0", "askSize" => "1.5", "previousClose" => "41000"}

      instructions = [
        {:bid_volume, :number, ["bidSize"]},
        {:ask_volume, :number, ["askSize"]},
        {:previous_close, :number, ["previousClose"]}
      ]

      result = ResponseParser.parse_single(data, instructions)

      assert result["bidVolume"] == 2.0
      assert result["askVolume"] == 1.5
      assert result["previousClose"] == 41_000.0
    end

    test "handles unknown coercion type gracefully" do
      data = %{"foo" => "bar"}
      instructions = [{:foo, :unknown_type, ["foo"]}]
      result = ResponseParser.parse_single(data, instructions)

      # Unknown coercion returns nil, so field is skipped
      refute Map.has_key?(result, "foo_unified")
    end
  end
end
