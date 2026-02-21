defmodule CCXT.ResponseParser.MappingCompilerTest do
  use ExUnit.Case, async: true

  alias CCXT.ResponseParser.MappingCompiler

  @analysis MappingCompiler.load_analysis()

  describe "compile_mapping/3" do
    test "returns instruction list for known exchange/method" do
      instructions = MappingCompiler.compile_mapping("binance", "parseTicker", @analysis)

      assert is_list(instructions)
      assert instructions != []

      # Each instruction is a 3-tuple with atom or tagged tuple coercion
      Enum.each(instructions, fn {field, coercion, source_keys} ->
        assert is_atom(field)
        assert is_atom(coercion) or match?({:bool_enum, _, _}, coercion)
        assert is_list(source_keys)
        assert Enum.all?(source_keys, &is_binary/1)
      end)
    end

    test "returns nil for unknown exchange" do
      assert MappingCompiler.compile_mapping("nonexistent_exchange", "parseTicker", @analysis) == nil
    end

    test "returns nil for unknown parse method" do
      assert MappingCompiler.compile_mapping("binance", "parseNonexistent", @analysis) == nil
    end

    test "returns nil for empty analysis data" do
      assert MappingCompiler.compile_mapping("binance", "parseTicker", %{}) == nil
    end

    test "produces correct coercion types from schema" do
      instructions = MappingCompiler.compile_mapping("binance", "parseTicker", @analysis)

      ask = Enum.find(instructions, fn {field, _, _} -> field == :ask end)
      assert ask
      {_, coercion, _} = ask
      assert coercion == :number

      bid = Enum.find(instructions, fn {field, _, _} -> field == :bid end)
      assert bid
      {_, coercion, _} = bid
      assert coercion == :number
    end

    test "extracts source keys from safe_accessor category" do
      instructions = MappingCompiler.compile_mapping("binance", "parseTicker", @analysis)

      # Binance ticker uses "askPrice" for ask
      ask = Enum.find(instructions, fn {field, _, _} -> field == :ask end)
      assert ask
      {_, _, source_keys} = ask
      assert is_list(source_keys)
      assert source_keys != []
    end

    test "skips computed/iso8601/undefined categories" do
      instructions = MappingCompiler.compile_mapping("binance", "parseTicker", @analysis)

      # datetime is typically iso8601 category - should be skipped
      datetime = Enum.find(instructions, fn {field, _, _} -> field == :datetime end)
      assert datetime == nil
    end

    test "compiles parseTrade mappings" do
      instructions = MappingCompiler.compile_mapping("binance", "parseTrade", @analysis)

      assert is_list(instructions)
      assert instructions != []

      price = Enum.find(instructions, fn {field, _, _} -> field == :price end)
      assert price
    end

    test "compiles parseOrder mappings" do
      instructions = MappingCompiler.compile_mapping("binance", "parseOrder", @analysis)

      assert is_list(instructions)
      assert instructions != []

      status = Enum.find(instructions, fn {field, _, _} -> field == :status end)
      assert status
    end

    test "compiles parseFundingRate mappings" do
      instructions = MappingCompiler.compile_mapping("bybit", "parseFundingRate", @analysis)

      assert is_list(instructions)
      assert instructions != []

      funding_rate = Enum.find(instructions, fn {field, _, _} -> field == :funding_rate end)
      assert funding_rate
    end

    test "compiles parsePosition mappings" do
      instructions = MappingCompiler.compile_mapping("bybit", "parsePosition", @analysis)

      assert is_list(instructions)
      assert instructions != []

      # Bybit maps realized_pnl in parsePosition
      realized_pnl = Enum.find(instructions, fn {field, _, _} -> field == :realized_pnl end)
      assert realized_pnl
    end

    test "compiles parseOrderBook mappings for exchanges with custom keys" do
      instructions = MappingCompiler.compile_mapping("bybit", "parseOrderBook", @analysis)

      assert is_list(instructions)
      assert instructions != []
      assert {:bids, :value, ["b"]} in instructions
      assert {:asks, :value, ["a"]} in instructions
    end

    test "compiles boolean_derivation to tagged tuple for Binance trade.side" do
      instructions = MappingCompiler.compile_mapping("binance", "parseTrade", @analysis)

      side = Enum.find(instructions, fn {field, _, _} -> field == :side end)
      assert side
      assert {:side, {:bool_enum, "sell", "buy"}, ["m", "isBuyerMaker"]} = side
    end

    test "boolean_derivation with empty source_keys is skipped" do
      custom_analysis = %{
        "methods" => %{
          "parseTrade" => %{
            "exchange_mappings" => %{
              "test_exchange" => %{
                "side" => %{
                  "category" => "boolean_derivation",
                  "source_keys" => [],
                  "true_value" => "sell",
                  "false_value" => "buy"
                },
                "price" => %{"category" => "safe_accessor", "fields" => ["p"]}
              }
            }
          }
        }
      }

      instructions = MappingCompiler.compile_mapping("test_exchange", "parseTrade", custom_analysis)

      # side should be skipped (empty source_keys), price should compile
      side = Enum.find(instructions, fn {field, _, _} -> field == :side end)
      assert side == nil

      price = Enum.find(instructions, fn {field, _, _} -> field == :price end)
      assert price
    end

    test "safe_fn overrides coercion for Bybit trade.side to string_lower" do
      instructions = MappingCompiler.compile_mapping("bybit", "parseTrade", @analysis)

      side = Enum.find(instructions, fn {field, _, _} -> field == :side end)
      assert side
      {_, coercion, _} = side
      assert coercion == :string_lower
    end

    test "safe_fn overrides coercion for Bybit trade.timestamp to integer" do
      instructions = MappingCompiler.compile_mapping("bybit", "parseTrade", @analysis)

      timestamp = Enum.find(instructions, fn {field, _, _} -> field == :timestamp end)
      assert timestamp
      {_, coercion, _} = timestamp
      assert coercion == :integer
    end

    test "skips unknown unified keys instead of creating new atoms" do
      unknown_key = "veryLikelyUnseenFieldName123XYZ"

      custom_analysis = %{
        "methods" => %{
          "parseTicker" => %{
            "exchange_mappings" => %{
              "binance" => %{
                "ask" => %{"category" => "safe_accessor", "fields" => ["askPrice"]},
                unknown_key => %{"category" => "safe_accessor", "fields" => ["mysteryKey"]}
              }
            }
          }
        }
      }

      instructions = MappingCompiler.compile_mapping("binance", "parseTicker", custom_analysis)

      assert {:ask, :number, ["askPrice"]} in instructions

      generated_fields =
        Enum.map(instructions, fn {field, _coercion, _source_keys} ->
          Atom.to_string(field)
        end)

      refute "very_likely_unseen_field_name123_xyz" in generated_fields
    end
  end

  describe "type_to_coercion/1" do
    test "maps number type" do
      assert MappingCompiler.type_to_coercion("number() | nil") == :number
      assert MappingCompiler.type_to_coercion("number()") == :number
    end

    test "maps integer type" do
      assert MappingCompiler.type_to_coercion("integer() | nil") == :integer
      assert MappingCompiler.type_to_coercion("integer()") == :integer
    end

    test "maps string type" do
      assert MappingCompiler.type_to_coercion("String.t() | nil") == :string
      assert MappingCompiler.type_to_coercion("String.t()") == :string
    end

    test "maps boolean type" do
      assert MappingCompiler.type_to_coercion("boolean() | nil") == :bool
      assert MappingCompiler.type_to_coercion("boolean()") == :bool
    end

    test "defaults to value for unknown types" do
      assert MappingCompiler.type_to_coercion("any()") == :value
      assert MappingCompiler.type_to_coercion("[map()]") == :value
      assert MappingCompiler.type_to_coercion("CCXT.Types.FeeInterface.t() | nil") == :value
    end
  end

  describe "load_analysis/0" do
    test "loads P1 analysis data" do
      analysis = MappingCompiler.load_analysis()
      assert is_map(analysis)
      assert Map.has_key?(analysis, "methods")
      assert Map.has_key?(analysis["methods"], "parseTicker")
    end
  end

  describe "method_schemas/0" do
    test "returns all supported method mappings" do
      schemas = MappingCompiler.method_schemas()
      assert is_map(schemas)
      assert Map.has_key?(schemas, "parseTicker")
      assert Map.has_key?(schemas, "parseTrade")
      assert Map.has_key?(schemas, "parseOrder")
      assert Map.has_key?(schemas, "parseFundingRate")
      assert Map.has_key?(schemas, "parsePosition")
    end
  end
end
