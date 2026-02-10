defmodule CCXT.Generator.Functions.TypespecsTest do
  @moduledoc """
  Tests for typespec generation from endpoint parameters.

  Covers generate_typespec_signature/4, param_types/0, return_type_ast/1,
  ok_error_return_type_ast/1, and TypeScript type parsing via return_type_ast.
  """
  use ExUnit.Case, async: true

  alias CCXT.Generator.Functions.Typespecs

  # ===========================================================================
  # param_types/0
  # ===========================================================================

  describe "param_types/0" do
    test "returns a map" do
      assert is_map(Typespecs.param_types())
    end

    test "contains expected parameter keys" do
      types = Typespecs.param_types()
      expected_keys = [:symbol, :amount, :price, :side, :type, :limit, :since, :id, :code]
      Enum.each(expected_keys, fn key -> assert Map.has_key?(types, key), "Missing key: #{key}" end)
    end
  end

  # ===========================================================================
  # generate_typespec_signature/4
  # ===========================================================================

  describe "generate_typespec_signature/4" do
    test "public endpoint with no params generates name(keyword())" do
      ast = Typespecs.generate_typespec_signature(:fetch_time, [], false, [])
      sig = Macro.to_string(ast)

      assert sig =~ "fetch_time"
      assert sig =~ "keyword()"
      refute sig =~ "Credentials"
    end

    test "public endpoint with known params includes correct types" do
      ast = Typespecs.generate_typespec_signature(:fetch_ticker, [:symbol], false, [:symbol])
      sig = Macro.to_string(ast)

      assert sig =~ "fetch_ticker"
      assert sig =~ "String.t()"
      assert sig =~ "keyword()"
    end

    test "private endpoint prepends CCXT.Credentials.t()" do
      ast = Typespecs.generate_typespec_signature(:fetch_balance, [], true, [])
      sig = Macro.to_string(ast)

      assert sig =~ "CCXT.Credentials.t()"
      assert sig =~ "keyword()"
    end

    test "optional param not in required_params gets nil union" do
      # :limit is in @optional_params
      ast = Typespecs.generate_typespec_signature(:fetch_trades, [:symbol, :limit], false, [:symbol])
      sig = Macro.to_string(ast)

      # :limit should have `| nil` since it's optional and not in required_params
      assert sig =~ "nil"
      assert sig =~ "String.t()"
    end

    test "optional param in required_params keeps base type (no extra nil added)" do
      # :limit is in @optional_params, but we mark it as required.
      # required_params prevents adding EXTRA nil (via maybe_nilable_type),
      # but the base type `non_neg_integer() | nil` is preserved as-is
      # because nil is part of the domain type (API accepts null limit).
      ast_required = Typespecs.generate_typespec_signature(:fetch_trades, [:symbol, :limit], false, [:symbol, :limit])
      sig_required = Macro.to_string(ast_required)

      ast_optional = Typespecs.generate_typespec_signature(:fetch_trades, [:symbol, :limit], false, [:symbol])
      sig_optional = Macro.to_string(ast_optional)

      # Both should have non_neg_integer()
      assert sig_required =~ "non_neg_integer()"
      assert sig_optional =~ "non_neg_integer()"

      # The type signature should be identical — required_params only affects
      # default values (\\ nil) in the function args, not the typespec types
      assert sig_required == sig_optional
    end

    test "param already including nil does not get double nil" do
      # :price type is `number() | nil` already — should not become `number() | nil | nil`
      ast =
        Typespecs.generate_typespec_signature(:create_order, [:symbol, :type, :side, :amount, :price], true, [
          :symbol,
          :type,
          :side,
          :amount
        ])

      sig = Macro.to_string(ast)

      # Should have price with nil, but not double nil
      assert sig =~ "number()"
      # Count occurrences of "nil" — should appear exactly once for price
      nil_count = length(Regex.scan(~r/\bnil\b/, sig))
      assert nil_count == 1, "Expected exactly 1 nil in signature, got #{nil_count}: #{sig}"
    end

    test "list param :symbols produces list type" do
      ast = Typespecs.generate_typespec_signature(:fetch_tickers, [:symbols], false, [])
      sig = Macro.to_string(ast)

      assert sig =~ "[String.t()]"
      assert sig =~ "nil"
    end

    test "unknown param falls back to term()" do
      ast = Typespecs.generate_typespec_signature(:some_method, [:unknown_param_xyz], false, [:unknown_param_xyz])
      sig = Macro.to_string(ast)

      assert sig =~ "term()"
    end

    test "multiple params with mixed required/optional" do
      ast =
        Typespecs.generate_typespec_signature(
          :fetch_ohlcv,
          [:symbol, :timeframe, :since, :limit],
          false,
          [:symbol]
        )

      sig = Macro.to_string(ast)

      # symbol is required (String.t())
      assert sig =~ "String.t()"
      # since and limit are optional — should have nil
      assert sig =~ "nil"
      assert sig =~ "keyword()"
    end
  end

  # ===========================================================================
  # return_type_ast/1
  # ===========================================================================

  describe "return_type_ast/1" do
    test "method with known return type produces correct AST" do
      # :fetch_ticker → "Ticker" → CCXT.Types.Ticker.t()
      ast = Typespecs.return_type_ast(:fetch_ticker)
      sig = Macro.to_string(ast)

      assert sig =~ "Ticker"
    end

    test "method with no return type defaults to map()" do
      ast = Typespecs.return_type_ast(:some_unknown_method_xyz)
      sig = Macro.to_string(ast)

      assert sig == "map()"
    end

    test "method returning a list type wraps in list" do
      # :fetch_trades → "Trade[]" → [CCXT.Types.Trade.t()]
      ast = Typespecs.return_type_ast(:fetch_trades)
      sig = Macro.to_string(ast)

      assert sig =~ "Trade"
      # Should be wrapped in list brackets
      assert sig =~ "["
    end

    test "method returning OrderBook produces correct type" do
      ast = Typespecs.return_type_ast(:fetch_order_book)
      sig = Macro.to_string(ast)

      assert sig =~ "OrderBook"
    end
  end

  # ===========================================================================
  # ok_error_return_type_ast/1
  # ===========================================================================

  describe "ok_error_return_type_ast/1" do
    test "wraps known type in ok/error tuple" do
      ast = Typespecs.ok_error_return_type_ast(:fetch_ticker)
      sig = Macro.to_string(ast)

      assert sig =~ "{:ok,"
      assert sig =~ "Ticker"
      assert sig =~ "{:error, CCXT.Error.t()}"
    end

    test "wraps unknown method (map()) in ok/error tuple" do
      ast = Typespecs.ok_error_return_type_ast(:unknown_method_xyz)
      sig = Macro.to_string(ast)

      assert sig =~ "{:ok, map()}"
      assert sig =~ "{:error, CCXT.Error.t()}"
    end
  end

  # ===========================================================================
  # TypeScript type parsing (via return_type_ast)
  # ===========================================================================

  describe "TypeScript type parsing via return_type_ast" do
    test "array suffix Type[] produces list type" do
      # fetch_markets → "Market[]" → [CCXT.Types.Market.t()]
      ast = Typespecs.return_type_ast(:fetch_markets)
      sig = Macro.to_string(ast)

      assert sig =~ "["
      assert sig =~ "Market"
    end

    test "primitive types map correctly" do
      # fetch → "any" → term()
      ast = Typespecs.return_type_ast(:fetch)
      sig = Macro.to_string(ast)

      assert sig == "term()"
    end

    test "currencies return type maps to Currencies" do
      # fetchCurrencies → "Currencies"
      ast = Typespecs.return_type_ast(:fetch_currencies)
      sig = Macro.to_string(ast)

      assert sig =~ "Currencies"
    end

    test "named type becomes module reference" do
      # fetchMarginMode → "MarginMode" → CCXT.Types.MarginMode.t()
      ast = Typespecs.return_type_ast(:fetch_margin_mode)
      sig = Macro.to_string(ast)

      assert sig =~ "CCXT.Types.MarginMode.t()"
    end

    test "Dictionary generic produces map type" do
      # fetchDepositWithdrawFees → "Dictionary<DepositWithdrawFee>"
      ast = Typespecs.return_type_ast(:fetch_deposit_withdraw_fees)
      sig = Macro.to_string(ast)

      assert sig =~ "%{"
      assert sig =~ "DepositWithdrawFee"
    end
  end
end
