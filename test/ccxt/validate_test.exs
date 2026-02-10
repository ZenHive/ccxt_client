defmodule CCXT.ValidateTest do
  use ExUnit.Case, async: true

  alias CCXT.Spec
  alias CCXT.Validate

  # Test spec with standard Binance-like format
  @binance_spec %Spec{
    id: "binance",
    name: "Binance",
    urls: %{api: "https://api.binance.com"},
    symbol_format: %{separator: "", case: :upper},
    endpoints: [
      %{
        name: :fetch_ticker,
        method: :get,
        path: "/api/v3/ticker/24hr",
        auth: false,
        params: [:symbol]
      },
      %{
        name: :create_order,
        method: :post,
        path: "/api/v3/order",
        auth: true,
        params: [:symbol, :side, :type, :quantity]
      },
      %{
        name: :fetch_balance,
        method: :get,
        path: "/api/v3/account",
        auth: true,
        params: []
      }
    ]
  }

  # Test spec with Coinbase-like format (dash separator)
  @coinbase_spec %Spec{
    id: "coinbase",
    name: "Coinbase",
    urls: %{api: "https://api.coinbase.com"},
    symbol_format: %{separator: "-", case: :upper},
    endpoints: [
      %{
        name: :fetch_ticker,
        method: :get,
        path: "/products/{symbol}/ticker",
        auth: false,
        params: [:symbol]
      }
    ]
  }

  # Test spec with explicit required_params
  @deribit_spec %Spec{
    id: "deribit",
    name: "Deribit",
    urls: %{api: "https://api.deribit.com"},
    symbol_format: %{separator: "-", case: :upper},
    endpoints: [
      %{
        name: :create_order,
        method: :post,
        path: "/api/v2/private/buy",
        auth: true,
        params: [:symbol, :amount, :price, :type],
        required_params: [:symbol, :amount]
      }
    ]
  }

  # =============================================================================
  # Task 126: Symbol Format Validation Tests
  # =============================================================================

  describe "symbol/3 - valid symbols" do
    test "accepts valid unified format" do
      assert {:ok, "BTC/USDT"} = Validate.symbol(@binance_spec, "BTC/USDT")
      assert {:ok, "ETH/BTC"} = Validate.symbol(@binance_spec, "ETH/BTC")
    end

    test "accepts derivative symbols with settle currency" do
      assert {:ok, "BTC/USDT:USDT"} = Validate.symbol(@binance_spec, "BTC/USDT:USDT")
      assert {:ok, "ETH/USD:USD"} = Validate.symbol(@coinbase_spec, "ETH/USD:USD")
    end

    test "works with spec struct directly" do
      assert {:ok, "BTC/USDT"} = Validate.symbol(@binance_spec, "BTC/USDT")
    end
  end

  describe "symbol/3 - invalid symbols" do
    test "rejects symbol without slash separator" do
      assert {:error, message} = Validate.symbol(@binance_spec, "BTCUSDT")
      assert message =~ "Invalid symbol format 'BTCUSDT'"
      assert message =~ "Binance"
      assert message =~ "BASE/QUOTE"
      assert message =~ "Example: BTC/USDT"
    end

    test "rejects symbol with wrong separator" do
      assert {:error, message} = Validate.symbol(@binance_spec, "BTC-USDT")
      assert message =~ "Invalid symbol format 'BTC-USDT'"
      assert message =~ "Binance"
    end

    test "rejects symbol with missing base" do
      assert {:error, message} = Validate.symbol(@binance_spec, "/USDT")
      assert message =~ "Invalid symbol format '/USDT'"
    end

    test "rejects symbol with missing quote" do
      assert {:error, message} = Validate.symbol(@binance_spec, "BTC/")
      assert message =~ "Invalid symbol format 'BTC/'"
    end

    test "rejects completely invalid symbol" do
      assert {:error, message} = Validate.symbol(@binance_spec, "invalid")
      assert message =~ "Invalid symbol format 'invalid'"
    end
  end

  describe "symbol/3 - error message quality" do
    test "includes exchange name in error" do
      {:error, message} = Validate.symbol(@coinbase_spec, "BTCUSD")
      assert message =~ "Coinbase"
    end

    test "shows expected format" do
      {:error, message} = Validate.symbol(@binance_spec, "BTC-USDT")
      assert message =~ "BASE/QUOTE"
    end

    test "provides example" do
      {:error, message} = Validate.symbol(@binance_spec, "BTCUSDT")
      assert message =~ "Example: BTC/USDT"
    end
  end

  # =============================================================================
  # Task 127: Required Param Validation Tests
  # =============================================================================

  describe "params/3 - valid params" do
    test "accepts all required params as map" do
      params = %{symbol: "BTC/USDT", side: "buy", type: "limit", quantity: 0.1}
      assert {:ok, ^params} = Validate.params(@binance_spec, :create_order, params)
    end

    test "accepts all required params as keyword list" do
      params = [symbol: "BTC/USDT", side: "buy", type: "limit", quantity: 0.1]
      {:ok, result} = Validate.params(@binance_spec, :create_order, params)
      assert result[:symbol] == "BTC/USDT"
      assert result[:side] == "buy"
    end

    test "accepts extra params beyond required" do
      params = %{symbol: "BTC/USDT", side: "buy", type: "limit", quantity: 0.1, extra: "value"}
      assert {:ok, _} = Validate.params(@binance_spec, :create_order, params)
    end

    test "accepts empty params for endpoints with no requirements" do
      assert {:ok, %{}} = Validate.params(@binance_spec, :fetch_balance, %{})
    end

    test "works with spec struct directly" do
      params = %{symbol: "BTC/USDT"}
      assert {:ok, ^params} = Validate.params(@binance_spec, :fetch_ticker, params)
    end
  end

  describe "params/3 - missing params" do
    test "rejects when missing required params" do
      assert {:error, message} = Validate.params(@binance_spec, :create_order, %{symbol: "BTC/USDT"})
      assert message =~ "Missing required parameters"
      assert message =~ ":side"
      assert message =~ ":type"
      assert message =~ ":quantity"
    end

    test "lists all missing params" do
      assert {:error, message} = Validate.params(@binance_spec, :create_order, %{})
      assert message =~ ":symbol"
      assert message =~ ":side"
      assert message =~ ":type"
      assert message =~ ":quantity"
    end

    test "shows endpoint name in error" do
      assert {:error, message} = Validate.params(@binance_spec, :create_order, %{})
      assert message =~ "Endpoint 'create_order'"
    end

    test "lists all required params in error" do
      assert {:error, message} = Validate.params(@binance_spec, :create_order, %{symbol: "BTC/USDT"})
      assert message =~ "requires:"
      assert message =~ "symbol"
    end
  end

  describe "params/3 - required_params field" do
    test "uses required_params when available instead of params" do
      # Deribit spec has required_params: [:symbol, :amount] but params has more
      params = %{symbol: "BTC-PERPETUAL", amount: 10}
      assert {:ok, _} = Validate.params(@deribit_spec, :create_order, params)
    end

    test "only checks required_params, not all params" do
      # Missing :price and :type should be OK since they're not in required_params
      params = %{symbol: "BTC-PERPETUAL", amount: 10}
      assert {:ok, _} = Validate.params(@deribit_spec, :create_order, params)
    end
  end

  describe "params/3 - unknown endpoint" do
    test "returns error for unknown endpoint" do
      assert {:error, message} = Validate.params(@binance_spec, :unknown_method, %{})
      assert message =~ "Unknown endpoint 'unknown_method'"
      assert message =~ "Binance"
    end
  end

  # =============================================================================
  # Task 144: WS Symbol Validation Tests
  # =============================================================================

  describe "ws_symbol/3 - valid symbols" do
    test "validates and transforms to exchange format" do
      # Binance spec has id "binance" which triggers lowercase transformation
      assert {:ok, "btcusdt"} = Validate.ws_symbol(@binance_spec, "BTC/USDT")
    end

    test "applies lowercase for Binance family" do
      # Binance uses lowercase for WebSocket symbols
      binance_spec = %{@binance_spec | id: "binance"}
      assert {:ok, "btcusdt"} = Validate.ws_symbol(binance_spec, "BTC/USDT")
    end

    test "applies lowercase for binanceusdm" do
      binanceusdm_spec = %{@binance_spec | id: "binanceusdm", name: "Binance USDM"}
      assert {:ok, "btcusdt"} = Validate.ws_symbol(binanceusdm_spec, "BTC/USDT")
    end

    test "applies lowercase for binancecoinm" do
      # Settle currency is stripped, symbol is lowercased
      binancecoinm_spec = %{@binance_spec | id: "binancecoinm", name: "Binance COINM"}
      assert {:ok, "btcusd"} = Validate.ws_symbol(binancecoinm_spec, "BTC/USD:BTC")
    end

    test "keeps case for non-Binance exchanges" do
      # Coinbase uses dash separator
      assert {:ok, "BTC-USD"} = Validate.ws_symbol(@coinbase_spec, "BTC/USD")
    end

    test "uses denormalize for exchange format" do
      assert {:ok, "BTC-USDT"} = Validate.ws_symbol(@coinbase_spec, "BTC/USDT")
    end

    test "works with spec struct directly" do
      assert {:ok, "btcusdt"} = Validate.ws_symbol(@binance_spec, "BTC/USDT")
    end
  end

  describe "ws_symbol/3 - invalid symbols" do
    test "rejects invalid symbol format" do
      assert {:error, message} = Validate.ws_symbol(@binance_spec, "BTCUSDT")
      assert message =~ "Invalid symbol format"
    end

    test "rejects symbol with wrong separator" do
      assert {:error, message} = Validate.ws_symbol(@binance_spec, "BTC-USDT")
      assert message =~ "Invalid symbol format"
    end
  end

  describe "ws_symbol/3 - market_type option" do
    test "supports market_type option" do
      # This exercises the code path even if format doesn't change
      assert {:ok, _} = Validate.ws_symbol(@binance_spec, "BTC/USDT", market_type: :swap)
    end
  end

  # =============================================================================
  # WS Symbol Format Variations (Task 5 coverage)
  # =============================================================================

  describe "ws_symbol/3 - format variations" do
    test "applies lowercase for exchange with lower case format" do
      lower_spec = %Spec{
        id: "htx",
        name: "HTX",
        urls: %{api: "https://api.htx.com"},
        symbol_format: %{separator: "", case: :lower},
        endpoints: []
      }

      assert {:ok, ws_sym} = Validate.ws_symbol(lower_spec, "BTC/USDT")
      # HTX is not in ws_lowercase_exchanges, so case transform comes from denormalize
      assert is_binary(ws_sym)
    end

    test "keeps dash separator for Coinbase-style WS symbols" do
      assert {:ok, "BTC-USDT"} = Validate.ws_symbol(@coinbase_spec, "BTC/USDT")
    end

    test "rejects invalid symbol for WS just like regular symbol validation" do
      lower_spec = %Spec{
        id: "htx",
        name: "HTX",
        urls: %{api: "https://api.htx.com"},
        symbol_format: %{separator: "", case: :lower},
        endpoints: []
      }

      assert {:error, message} = Validate.ws_symbol(lower_spec, "BTCUSDT")
      assert message =~ "Invalid symbol format"
      assert message =~ "HTX"
    end

    test "ws_symbol passes market_type through to denormalize" do
      assert {:ok, _} = Validate.ws_symbol(@coinbase_spec, "BTC/USD:BTC", market_type: :swap)
    end
  end

  # =============================================================================
  # Symbol Format Variations (Task 5 coverage)
  # =============================================================================

  describe "symbol/3 - symbol format variations" do
    test "error message mentions 'lower' for lowercase format" do
      spec = %Spec{
        id: "htx",
        name: "HTX",
        urls: %{api: "https://api.htx.com"},
        symbol_format: %{separator: "", case: :lower},
        endpoints: []
      }

      {:error, message} = Validate.symbol(spec, "invalid")
      assert message =~ "lower"
    end

    test "error message mentions 'mixed' for mixed case format" do
      spec = %Spec{
        id: "test_mixed",
        name: "TestMixed",
        urls: %{api: "https://api.test.com"},
        symbol_format: %{separator: "", case: :mixed},
        endpoints: []
      }

      {:error, message} = Validate.symbol(spec, "invalid")
      assert message =~ "mixed"
    end

    test "error message mentions custom separator" do
      spec = %Spec{
        id: "test_sep",
        name: "TestSep",
        urls: %{api: "https://api.test.com"},
        symbol_format: %{separator: "_", case: :upper},
        endpoints: []
      }

      {:error, message} = Validate.symbol(spec, "invalid")
      assert message =~ "_"
    end

    test "nil symbol_format uses defaults (upper case, no separator)" do
      spec = %Spec{
        id: "test_nil_fmt",
        name: "TestNilFmt",
        urls: %{api: "https://api.test.com"},
        symbol_format: nil,
        endpoints: []
      }

      {:error, message} = Validate.symbol(spec, "invalid")
      assert message =~ "upper"
      assert message =~ "no separator"
    end

    test "unknown case value falls back to 'upper' in error message" do
      spec = %Spec{
        id: "test_unknown",
        name: "TestUnknown",
        urls: %{api: "https://api.test.com"},
        symbol_format: %{separator: "", case: :other},
        endpoints: []
      }

      {:error, message} = Validate.symbol(spec, "invalid")
      assert message =~ "upper"
    end
  end

  # =============================================================================
  # Params - String Key Normalization (Task 5 coverage)
  # =============================================================================

  describe "params/3 - string key normalization" do
    test "string keys that map to existing atoms are converted" do
      # "symbol" is an existing atom
      params = %{"symbol" => "BTC/USDT"}
      assert {:ok, result} = Validate.params(@binance_spec, :fetch_ticker, params)
      assert result[:symbol] == "BTC/USDT"
    end

    test "safe_to_atom keeps unknown string keys as strings" do
      # Key that won't exist as an atom — exercises the ArgumentError rescue path
      params = %{
        "symbol" => "BTC/USDT",
        "side" => "buy",
        "type" => "limit",
        "quantity" => 0.1,
        "xyzzy_nonexistent_param_abc_12345" => "value"
      }

      {:ok, result} = Validate.params(@binance_spec, :create_order, params)
      # The unknown key should remain as a string (not converted to atom)
      assert result["xyzzy_nonexistent_param_abc_12345"] == "value"
    end
  end

  # =============================================================================
  # Exchange Resolution Tests (expanded for Task 5 coverage)
  # =============================================================================

  describe "exchange resolution" do
    test "accepts Spec struct directly" do
      assert {:ok, "BTC/USDT"} = Validate.symbol(@binance_spec, "BTC/USDT")
    end

    test "returns error for non-existent exchange string" do
      assert {:error, message} = Validate.symbol("nonexistent_exchange", "BTC/USDT")
      assert message =~ "Exchange 'nonexistent_exchange' not found"
    end

    test "returns error for non-existent exchange atom" do
      assert {:error, message} = Validate.symbol(:nonexistent_exchange_xyz, "BTC/USDT")
      assert message =~ "not found"
    end

    test "returns error for atom that is not a CCXT module" do
      # String module exists but doesn't have __ccxt_spec__/0
      assert {:error, message} = Validate.symbol(String, "BTC/USDT")
      assert message =~ "not found"
    end
  end
end
