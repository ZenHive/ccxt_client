defmodule CCXT.WS.ContractTest do
  use ExUnit.Case, async: true

  alias CCXT.Test.WsContractHelpers
  alias CCXT.Types.Balance
  alias CCXT.Types.OHLCVBar
  alias CCXT.Types.Order
  alias CCXT.Types.OrderBook
  alias CCXT.Types.Position
  alias CCXT.Types.Ticker
  alias CCXT.Types.Trade
  alias CCXT.WS.Contract

  @all_families Contract.families()

  describe "families/0" do
    test "returns exactly 7 families" do
      assert length(@all_families) == 7
    end

    test "contains all expected family atoms" do
      expected = [
        :watch_ticker,
        :watch_trades,
        :watch_order_book,
        :watch_ohlcv,
        :watch_orders,
        :watch_balance,
        :watch_positions
      ]

      for family <- expected do
        assert family in @all_families, "Missing family: #{inspect(family)}"
      end
    end
  end

  describe "family_spec/1" do
    test "every family has a valid spec" do
      for family <- @all_families do
        spec = Contract.family_spec(family)
        assert is_map(spec), "#{inspect(family)} spec is not a map"
        assert Map.has_key?(spec, :type_module)
        assert Map.has_key?(spec, :result_shape)
        assert Map.has_key?(spec, :update_semantics)
        assert Map.has_key?(spec, :coercion_type)
        assert Map.has_key?(spec, :auth_required)
        assert Map.has_key?(spec, :required_fields)
        assert Map.has_key?(spec, :optional_fields)
      end
    end

    test "result_shape is :single or :list" do
      for family <- @all_families do
        spec = Contract.family_spec(family)
        assert spec.result_shape in [:single, :list]
      end
    end

    test "type_module exists for all families" do
      for family <- @all_families do
        spec = Contract.family_spec(family)
        assert is_atom(spec.type_module), "#{inspect(family)} has no type_module"
      end
    end

    test "type_module has from_map/1 for struct families (except OHLCVBar)" do
      for family <- @all_families, family != :watch_ohlcv do
        spec = Contract.family_spec(family)
        mod = spec.type_module
        assert function_exported?(mod, :from_map, 1), "#{inspect(mod)} missing from_map/1"
      end
    end

    test "watch_ohlcv has OHLCVBar type_module" do
      spec = Contract.family_spec(:watch_ohlcv)
      assert spec.type_module == OHLCVBar
    end

    test "coercion_type is an atom for all families" do
      for family <- @all_families do
        coercion = Contract.coercion_type(family)
        assert is_atom(coercion), "#{inspect(family)} has non-atom coercion_type"
      end
    end

    test "coercion_type is recognized by ResponseCoercer for struct families (except OHLCV)" do
      type_modules = CCXT.ResponseCoercer.type_modules()

      for family <- @all_families, family != :watch_ohlcv do
        coercion = Contract.coercion_type(family)

        assert Map.has_key?(type_modules, coercion),
               "ResponseCoercer doesn't know coercion type #{inspect(coercion)} for #{inspect(family)}"
      end
    end

    test "watch_ohlcv has :ohlcv coercion_type" do
      assert Contract.coercion_type(:watch_ohlcv) == :ohlcv
    end
  end

  describe "required_fields/1" do
    test "returns a list of atoms for each family" do
      for family <- @all_families do
        fields = Contract.required_fields(family)
        assert is_list(fields)
        assert Enum.all?(fields, &is_atom/1)
      end
    end

    test "required fields are subset of struct fields for all families" do
      for family <- @all_families do
        spec = Contract.family_spec(family)
        mod = spec.type_module
        required = Contract.required_fields(family)
        struct_fields = mod |> struct() |> Map.keys() |> MapSet.new()

        for field <- required do
          assert MapSet.member?(struct_fields, field),
                 "#{inspect(field)} not in #{inspect(mod)} struct fields"
        end
      end
    end

    test "watch_ohlcv requires timestamp" do
      assert Contract.required_fields(:watch_ohlcv) == [:timestamp]
    end
  end

  describe "update_semantics/1" do
    test "returns valid semantic for each family" do
      valid_semantics = [:snapshot, :append, :snapshot_and_delta, :update_in_place, :update, :partial_or_full]

      for family <- @all_families do
        semantic = Contract.update_semantics(family)

        assert semantic in valid_semantics,
               "#{inspect(family)} has invalid update_semantics: #{inspect(semantic)}"
      end
    end

    test "specific semantics match expected values" do
      assert Contract.update_semantics(:watch_ticker) == :snapshot
      assert Contract.update_semantics(:watch_trades) == :append
      assert Contract.update_semantics(:watch_order_book) == :snapshot_and_delta
      assert Contract.update_semantics(:watch_ohlcv) == :update_in_place
      assert Contract.update_semantics(:watch_orders) == :update
      assert Contract.update_semantics(:watch_balance) == :partial_or_full
      assert Contract.update_semantics(:watch_positions) == :update
    end
  end

  describe "auth_required?/1" do
    test "public families don't require auth" do
      refute Contract.auth_required?(:watch_ticker)
      refute Contract.auth_required?(:watch_trades)
      refute Contract.auth_required?(:watch_order_book)
      refute Contract.auth_required?(:watch_ohlcv)
    end

    test "private families require auth" do
      assert Contract.auth_required?(:watch_orders)
      assert Contract.auth_required?(:watch_balance)
      assert Contract.auth_required?(:watch_positions)
    end
  end

  describe "envelope_patterns/0" do
    test "returns 5 documented patterns" do
      patterns = Contract.envelope_patterns()
      assert length(patterns) == 5
    end

    test "each pattern has required keys" do
      for pattern <- Contract.envelope_patterns() do
        assert Map.has_key?(pattern, :name)
        assert Map.has_key?(pattern, :exchanges)
        assert Map.has_key?(pattern, :family_field)
        assert Map.has_key?(pattern, :data_field)
        assert is_list(pattern.exchanges)
      end
    end

    test "pattern names are unique" do
      names = Enum.map(Contract.envelope_patterns(), & &1.name)
      assert names == Enum.uniq(names)
    end
  end

  describe "validate/2 - ticker" do
    test "accepts valid ticker" do
      ticker = WsContractHelpers.build_sample_payload(:watch_ticker)
      assert {:ok, ^ticker} = Contract.validate(:watch_ticker, ticker)
    end

    test "rejects plain map" do
      assert {:error, violations} = Contract.validate(:watch_ticker, %{symbol: "BTC/USDT"})
      assert Enum.any?(violations, &match?({:wrong_type, Ticker, _}, &1))
    end

    test "rejects ticker with nil symbol" do
      ticker = %Ticker{symbol: nil}
      assert {:error, violations} = Contract.validate(:watch_ticker, ticker)
      assert {:missing_field, :symbol} in violations
    end
  end

  describe "validate/2 - trades" do
    test "accepts valid trades list" do
      trades = WsContractHelpers.build_sample_payload(:watch_trades)
      assert {:ok, ^trades} = Contract.validate(:watch_trades, trades)
    end

    test "rejects non-list" do
      trade = %Trade{symbol: "BTC/USDT", price: 42_000.0, amount: 0.5, timestamp: 1_000}
      assert {:error, violations} = Contract.validate(:watch_trades, trade)
      assert Enum.any?(violations, &match?({:wrong_shape, :list, _}, &1))
    end

    test "rejects trades with missing required fields" do
      trades = [%Trade{symbol: nil, price: nil, amount: nil, timestamp: nil}]
      assert {:error, violations} = Contract.validate(:watch_trades, trades)
      assert {:missing_field, :symbol} in violations
      assert {:missing_field, :price} in violations
      assert {:missing_field, :amount} in violations
      assert {:missing_field, :timestamp} in violations
    end

    test "rejects list with non-Trade elements" do
      assert {:error, violations} = Contract.validate(:watch_trades, [%{symbol: "BTC/USDT"}])
      assert Enum.any?(violations, &match?({:wrong_element_type, 0, Trade, _}, &1))
    end

    test "accepts empty list" do
      assert {:ok, []} = Contract.validate(:watch_trades, [])
    end
  end

  describe "validate/2 - order book" do
    test "accepts valid order book" do
      book = WsContractHelpers.build_sample_payload(:watch_order_book)
      assert {:ok, ^book} = Contract.validate(:watch_order_book, book)
    end

    test "rejects order book with nil bids" do
      book = %OrderBook{bids: nil, asks: []}
      assert {:error, violations} = Contract.validate(:watch_order_book, book)
      assert {:missing_field, :bids} in violations
    end

    test "rejects order book with nil asks" do
      book = %OrderBook{bids: [], asks: nil}
      assert {:error, violations} = Contract.validate(:watch_order_book, book)
      assert {:missing_field, :asks} in violations
    end
  end

  describe "validate/2 - OHLCV" do
    test "accepts valid OHLCVBar structs" do
      candles = WsContractHelpers.build_sample_payload(:watch_ohlcv)
      assert {:ok, ^candles} = Contract.validate(:watch_ohlcv, candles)
    end

    test "rejects raw array format (not structs)" do
      candles = [[1_700_000_000_000, 42_000.0, 42_500.0, 41_800.0, 42_100.0, 150.5]]
      assert {:error, violations} = Contract.validate(:watch_ohlcv, candles)
      assert Enum.any?(violations, &match?({:wrong_element_type, 0, OHLCVBar, _}, &1))
    end

    test "rejects non-OHLCVBar struct elements" do
      candles = [%{timestamp: 1_700_000_000_000}]
      assert {:error, violations} = Contract.validate(:watch_ohlcv, candles)
      assert Enum.any?(violations, &match?({:wrong_element_type, 0, OHLCVBar, _}, &1))
    end

    test "rejects OHLCVBar with nil timestamp (required field)" do
      candles = [
        %OHLCVBar{
          timestamp: nil,
          open: 42_000.0,
          high: 42_500.0,
          low: 41_800.0,
          close: 42_100.0,
          volume: 150.5
        }
      ]

      assert {:error, violations} = Contract.validate(:watch_ohlcv, candles)
      assert {:missing_field, :timestamp} in violations
    end

    test "accepts OHLCVBar with nil OHLCV values (sparse data)" do
      candles = [
        %OHLCVBar{timestamp: 1_700_000_000_000, open: 42_000.0, high: nil, low: nil, close: 42_100.0, volume: nil}
      ]

      assert {:ok, ^candles} = Contract.validate(:watch_ohlcv, candles)
    end

    test "rejects non-list input and includes actual value" do
      assert {:error, [{:wrong_shape, :list, "not a list"}]} =
               Contract.validate(:watch_ohlcv, "not a list")
    end

    test "accepts empty list" do
      assert {:ok, []} = Contract.validate(:watch_ohlcv, [])
    end
  end

  describe "validate/2 - orders" do
    test "accepts valid orders list" do
      orders = WsContractHelpers.build_sample_payload(:watch_orders)
      assert {:ok, ^orders} = Contract.validate(:watch_orders, orders)
    end

    test "rejects orders with missing required fields" do
      orders = [%Order{id: nil, symbol: nil, status: nil}]
      assert {:error, violations} = Contract.validate(:watch_orders, orders)
      assert {:missing_field, :id} in violations
      assert {:missing_field, :symbol} in violations
      assert {:missing_field, :status} in violations
    end
  end

  describe "validate/2 - balance" do
    test "accepts valid balance" do
      balance = WsContractHelpers.build_sample_payload(:watch_balance)
      assert {:ok, ^balance} = Contract.validate(:watch_balance, balance)
    end

    test "accepts empty balance (no required fields)" do
      balance = %Balance{}
      assert {:ok, ^balance} = Contract.validate(:watch_balance, balance)
    end

    test "rejects non-Balance struct" do
      assert {:error, violations} = Contract.validate(:watch_balance, %Ticker{symbol: "X"})
      assert Enum.any?(violations, &match?({:wrong_type, Balance, _}, &1))
    end
  end

  describe "validate/2 - positions" do
    test "accepts valid positions list" do
      positions = WsContractHelpers.build_sample_payload(:watch_positions)
      assert {:ok, ^positions} = Contract.validate(:watch_positions, positions)
    end

    test "rejects positions with missing symbol" do
      positions = [%Position{symbol: nil}]
      assert {:error, violations} = Contract.validate(:watch_positions, positions)
      assert {:missing_field, :symbol} in violations
    end
  end

  describe "sample payloads" do
    test "all sample payloads pass validation" do
      for family <- @all_families do
        payload = WsContractHelpers.build_sample_payload(family)
        WsContractHelpers.assert_contract_compliance(family, payload)
      end
    end
  end

  describe "assert_required_fields/2" do
    test "passes for valid payloads" do
      for family <- @all_families do
        payload = WsContractHelpers.build_sample_payload(family)
        assert :ok = WsContractHelpers.assert_required_fields(family, payload)
      end
    end
  end

  describe "assert_coercion_applied/2" do
    test "passes when numeric fields are numbers" do
      ticker = WsContractHelpers.build_sample_payload(:watch_ticker)
      assert :ok = WsContractHelpers.assert_coercion_applied(ticker, [:last, :bid, :ask])
    end
  end

  describe "assert_raw_preserved/2" do
    test "passes when raw matches original" do
      original = %{"symbol" => "BTC/USDT", "last" => 42_000.0}
      ticker = %Ticker{symbol: "BTC/USDT", last: 42_000.0, raw: original}
      assert :ok = WsContractHelpers.assert_raw_preserved(ticker, original)
    end
  end
end
