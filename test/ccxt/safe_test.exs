defmodule CCXT.SafeTest do
  use ExUnit.Case, async: true

  alias CCXT.Safe

  # --- prop/2 ---

  describe "prop/2" do
    test "returns value for string key" do
      assert Safe.prop(%{"price" => 42}, "price") == 42
    end

    test "returns value for atom key" do
      assert Safe.prop(%{price: 42}, :price) == 42
    end

    test "falls back to atom key when string key missing" do
      assert Safe.prop(%{price: 42}, "price") == 42
    end

    test "falls back to string key when atom key missing" do
      assert Safe.prop(%{"price" => 42}, :price) == 42
    end

    test "returns nil for missing key" do
      assert Safe.prop(%{"other" => 1}, "price") == nil
    end

    test "returns nil for nil value" do
      assert Safe.prop(%{"price" => nil}, "price") == nil
    end

    test "treats empty string as missing" do
      assert Safe.prop(%{"side" => ""}, "side") == nil
    end

    test "treats empty string as missing for atom keys" do
      assert Safe.prop(%{side: ""}, :side) == nil
    end

    test "returns false (not nil) for boolean false" do
      assert Safe.prop(%{"active" => false}, "active") == false
    end

    test "returns 0 (not nil) for zero" do
      assert Safe.prop(%{"count" => 0}, "count") == 0
    end

    test "multi-key fallback returns first non-nil" do
      assert Safe.prop(%{"a" => nil, "b" => "found"}, ["a", "b"]) == "found"
    end

    test "multi-key fallback skips empty strings" do
      assert Safe.prop(%{"a" => "", "b" => "found"}, ["a", "b"]) == "found"
    end

    test "multi-key fallback returns nil when all missing" do
      assert Safe.prop(%{"x" => 1}, ["a", "b", "c"]) == nil
    end

    test "multi-key uses first match" do
      assert Safe.prop(%{"a" => "first", "b" => "second"}, ["a", "b"]) == "first"
    end

    test "returns nil for non-map input" do
      assert Safe.prop(nil, "key") == nil
      assert Safe.prop("not a map", "key") == nil
    end
  end

  # --- string/3 ---

  describe "string/3" do
    test "returns string value" do
      assert Safe.string(%{"side" => "buy"}, "side") == "buy"
    end

    test "coerces number to string" do
      assert Safe.string(%{"code" => 200}, "code") == "200"
    end

    test "coerces atom to string" do
      assert Safe.string(%{"type" => :limit}, "type") == "limit"
    end

    test "returns nil for missing key" do
      assert Safe.string(%{}, "side") == nil
    end

    test "returns default for missing key" do
      assert Safe.string(%{}, "side", "unknown") == "unknown"
    end

    test "multi-key fallback" do
      assert Safe.string(%{"kind" => nil, "type" => "limit"}, ["kind", "type"]) == "limit"
    end

    test "empty string treated as missing" do
      assert Safe.string(%{"side" => ""}, "side") == nil
      assert Safe.string(%{"side" => ""}, "side", "default") == "default"
    end
  end

  # --- number/3 ---

  describe "number/3" do
    test "returns numeric value as-is" do
      assert Safe.number(%{"price" => 42_000}, "price") == 42_000
      assert Safe.number(%{"price" => 42.5}, "price") == 42.5
    end

    test "parses string to number" do
      assert Safe.number(%{"price" => "42000.50"}, "price") == 42_000.50
    end

    test "parses integer string" do
      assert Safe.number(%{"count" => "100"}, "count") == 100.0
    end

    test "returns nil for non-numeric string" do
      assert Safe.number(%{"price" => "abc"}, "price") == nil
    end

    test "returns nil for missing key" do
      assert Safe.number(%{}, "price") == nil
    end

    test "returns default for missing key" do
      assert Safe.number(%{}, "price", 0.0) == 0.0
    end

    test "multi-key fallback" do
      assert Safe.number(%{"price" => nil, "lastPrice" => "100"}, ["price", "lastPrice"]) == 100.0
    end

    test "empty string treated as missing" do
      assert Safe.number(%{"price" => ""}, "price") == nil
    end

    test "returns nil for non-numeric types" do
      assert Safe.number(%{"price" => [1, 2]}, "price") == nil
    end

    test "parses partial numeric string (CCXT behavior)" do
      assert Safe.number(%{"price" => "42.5abc"}, "price") == 42.5
    end
  end

  # --- integer/3 ---

  describe "integer/3" do
    test "returns integer as-is" do
      assert Safe.integer(%{"count" => 42}, "count") == 42
    end

    test "truncates float" do
      assert Safe.integer(%{"count" => 42.7}, "count") == 42
    end

    test "parses string integer" do
      assert Safe.integer(%{"count" => "42"}, "count") == 42
    end

    test "parses string float and truncates" do
      assert Safe.integer(%{"count" => "42.9"}, "count") == 42
    end

    test "returns nil for non-numeric string" do
      assert Safe.integer(%{"count" => "abc"}, "count") == nil
    end

    test "returns default for missing key" do
      assert Safe.integer(%{}, "count", 0) == 0
    end

    test "empty string treated as missing" do
      assert Safe.integer(%{"count" => ""}, "count") == nil
    end
  end

  # --- bool/3 ---

  describe "bool/3" do
    test "returns true" do
      assert Safe.bool(%{"active" => true}, "active") == true
    end

    test "returns false" do
      assert Safe.bool(%{"active" => false}, "active") == false
    end

    test "returns nil for non-boolean" do
      assert Safe.bool(%{"active" => "yes"}, "active") == nil
      assert Safe.bool(%{"active" => 1}, "active") == nil
    end

    test "returns default for missing" do
      assert Safe.bool(%{}, "active", false) == false
    end
  end

  # --- value/3 ---

  describe "value/3" do
    test "returns raw value without coercion" do
      assert Safe.value(%{"data" => [1, 2, 3]}, "data") == [1, 2, 3]
      assert Safe.value(%{"info" => %{"a" => 1}}, "info") == %{"a" => 1}
    end

    test "empty string treated as missing" do
      assert Safe.value(%{"data" => ""}, "data") == nil
    end

    test "returns default for missing" do
      assert Safe.value(%{}, "data", :none) == :none
    end
  end

  # --- timestamp/3 ---

  describe "timestamp/3" do
    test "returns millisecond timestamp as integer" do
      assert Safe.timestamp(%{"ts" => "1700000000000"}, "ts") == 1_700_000_000_000
    end

    test "converts seconds to milliseconds" do
      assert Safe.timestamp(%{"ts" => 1_700_000.0}, "ts") == 1_700_000_000
    end

    test "converts string seconds to milliseconds" do
      assert Safe.timestamp(%{"ts" => "1700000"}, "ts") == 1_700_000_000
    end

    test "passes through millisecond integer" do
      assert Safe.timestamp(%{"ts" => 1_700_000_000_000}, "ts") == 1_700_000_000_000
    end

    test "returns nil for missing" do
      assert Safe.timestamp(%{}, "ts") == nil
    end

    test "returns default for missing" do
      assert Safe.timestamp(%{}, "ts", 0) == 0
    end

    test "multi-key fallback" do
      map = %{"timestamp" => nil, "ts" => 1_700_000_000_000}
      assert Safe.timestamp(map, ["timestamp", "ts"]) == 1_700_000_000_000
    end
  end

  # --- string_lower/3 ---

  describe "string_lower/3" do
    test "lowercases string value" do
      assert Safe.string_lower(%{"side" => "BUY"}, "side") == "buy"
    end

    test "already lowercase" do
      assert Safe.string_lower(%{"side" => "buy"}, "side") == "buy"
    end

    test "coerces number then lowercases" do
      assert Safe.string_lower(%{"code" => 200}, "code") == "200"
    end

    test "returns nil for missing" do
      assert Safe.string_lower(%{}, "side") == nil
    end

    test "returns default for missing" do
      assert Safe.string_lower(%{}, "side", "unknown") == "unknown"
    end
  end

  # --- string_upper/3 ---

  describe "string_upper/3" do
    test "upcases string value" do
      assert Safe.string_upper(%{"currency" => "btc"}, "currency") == "BTC"
    end

    test "returns default for missing" do
      assert Safe.string_upper(%{}, "currency", "USD") == "USD"
    end
  end

  # --- list/3 ---

  describe "list/3" do
    test "returns list value" do
      assert Safe.list(%{"items" => [1, 2]}, "items") == [1, 2]
    end

    test "returns nil for non-list" do
      assert Safe.list(%{"items" => "not a list"}, "items") == nil
      assert Safe.list(%{"items" => 42}, "items") == nil
    end

    test "returns empty list" do
      assert Safe.list(%{"items" => []}, "items") == []
    end

    test "returns default for missing" do
      assert Safe.list(%{}, "items", []) == []
    end
  end

  # --- dict/3 ---

  describe "dict/3" do
    test "returns map value" do
      assert Safe.dict(%{"fee" => %{"cost" => 0.1}}, "fee") == %{"cost" => 0.1}
    end

    test "returns nil for non-map" do
      assert Safe.dict(%{"fee" => "not a map"}, "fee") == nil
    end

    test "returns empty map" do
      assert Safe.dict(%{"fee" => %{}}, "fee") == %{}
    end

    test "returns default for missing" do
      assert Safe.dict(%{}, "fee", %{}) == %{}
    end
  end

  # --- integer_product/4 ---

  describe "integer_product/4" do
    test "multiplies and truncates" do
      assert Safe.integer_product(%{"amount" => 5}, "amount", 100) == 500
    end

    test "satoshi conversion" do
      assert Safe.integer_product(%{"satoshis" => "100000000"}, "satoshis", 1.0e-8) == 1
    end

    test "returns nil for missing" do
      assert Safe.integer_product(%{}, "amount", 100) == nil
    end

    test "returns default for missing" do
      assert Safe.integer_product(%{}, "amount", 100, 0) == 0
    end

    test "parses string and multiplies" do
      assert Safe.integer_product(%{"val" => "10"}, "val", 3) == 30
    end
  end

  # --- ccxt_to_elixir/1 ---

  describe "ccxt_to_elixir/1" do
    test "maps string variants" do
      assert Safe.ccxt_to_elixir("safeString") == {:string, 1}
      assert Safe.ccxt_to_elixir("safeString2") == {:string, 2}
      assert Safe.ccxt_to_elixir("safeStringN") == {:string, :n}
    end

    test "maps string case variants" do
      assert Safe.ccxt_to_elixir("safeStringLower") == {:string_lower, 1}
      assert Safe.ccxt_to_elixir("safeStringLower2") == {:string_lower, 2}
      assert Safe.ccxt_to_elixir("safeStringUpper") == {:string_upper, 1}
      assert Safe.ccxt_to_elixir("safeStringUpperN") == {:string_upper, :n}
    end

    test "maps number variants including Float aliases" do
      assert Safe.ccxt_to_elixir("safeNumber") == {:number, 1}
      assert Safe.ccxt_to_elixir("safeNumber2") == {:number, 2}
      assert Safe.ccxt_to_elixir("safeFloat") == {:number, 1}
      assert Safe.ccxt_to_elixir("safeFloat2") == {:number, 2}
      assert Safe.ccxt_to_elixir("safeFloatN") == {:number, :n}
    end

    test "maps integer variants" do
      assert Safe.ccxt_to_elixir("safeInteger") == {:integer, 1}
      assert Safe.ccxt_to_elixir("safeInteger2") == {:integer, 2}
      assert Safe.ccxt_to_elixir("safeIntegerProduct") == {:integer_product, 1}
    end

    test "maps timestamp variants" do
      assert Safe.ccxt_to_elixir("safeTimestamp") == {:timestamp, 1}
      assert Safe.ccxt_to_elixir("safeTimestamp2") == {:timestamp, 2}
    end

    test "maps bool variants" do
      assert Safe.ccxt_to_elixir("safeBool") == {:bool, 1}
      assert Safe.ccxt_to_elixir("safeBool2") == {:bool, 2}
    end

    test "maps value variants" do
      assert Safe.ccxt_to_elixir("safeValue") == {:value, 1}
      assert Safe.ccxt_to_elixir("safeValue2") == {:value, 2}
    end

    test "maps list and dict" do
      assert Safe.ccxt_to_elixir("safeList") == {:list, 1}
      assert Safe.ccxt_to_elixir("safeDict") == {:dict, 1}
    end

    test "returns nil for unknown" do
      assert Safe.ccxt_to_elixir("unknownFunction") == nil
      assert Safe.ccxt_to_elixir("safeWhatever") == nil
    end
  end

  # --- Edge cases ---

  describe "edge cases" do
    test "atom key with string fallback across all types" do
      map = %{"price" => "42.5"}

      assert Safe.string(map, :price) == "42.5"
      assert Safe.number(map, :price) == 42.5
      assert Safe.integer(map, :price) == 42
    end

    test "string key with atom fallback across all types" do
      map = %{price: 42.5}

      assert Safe.string(map, "price") == "42.5"
      assert Safe.number(map, "price") == 42.5
      assert Safe.integer(map, "price") == 42
    end

    test "nil map argument returns nil for all types" do
      assert Safe.string(nil, "key") == nil
      assert Safe.number(nil, "key") == nil
      assert Safe.integer(nil, "key") == nil
      assert Safe.bool(nil, "key") == nil
      assert Safe.value(nil, "key") == nil
      assert Safe.timestamp(nil, "key") == nil
      assert Safe.string_lower(nil, "key") == nil
      assert Safe.string_upper(nil, "key") == nil
      assert Safe.list(nil, "key") == nil
      assert Safe.dict(nil, "key") == nil
      assert Safe.integer_product(nil, "key", 100) == nil
    end

    test "struct input works like a map" do
      struct = %URI{host: "example.com", port: 443}

      assert Safe.string(struct, :host) == "example.com"
      assert Safe.integer(struct, :port) == 443
    end
  end
end
