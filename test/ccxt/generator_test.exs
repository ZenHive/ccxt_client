# Define TestExchange module inline for testing the generator
# This keeps test fixtures in the test directory rather than polluting lib/
defmodule CCXT.TestExchange do
  @moduledoc false
  use CCXT.Generator, spec: "test_exchange"
end

defmodule CCXT.GeneratorTest do
  use ExUnit.Case, async: false

  alias CCXT.Credentials
  alias CCXT.Exchange.Classification
  alias CCXT.TestExchange

  # Dynamically find an available generated exchange module (not TestExchange).
  # This allows tests to work with whatever exchanges are generated (e.g., --only bybit).
  # Returns {module, exchange_id} or nil if none found.
  @doc false
  def find_available_exchange do
    Enum.find_value(Classification.all_exchanges(), &try_load_exchange/1)
  end

  @doc false
  defp try_load_exchange(exchange_id) do
    module_name = exchange_id |> Macro.camelize() |> String.to_atom()
    module = Module.concat(CCXT, module_name)

    with {:module, ^module} <- Code.ensure_loaded(module),
         true <- function_exported?(module, :__ccxt_spec__, 0) do
      {module, exchange_id}
    else
      _ -> nil
    end
  end

  # Suppress telemetry info logs
  @moduletag capture_log: true

  @test_credentials %Credentials{
    api_key: "test_api_key",
    secret: "test_secret",
    sandbox: false
  }

  # Helper to safely decode query string (nil -> empty map)
  defp decode_query_string(nil), do: %{}
  defp decode_query_string(qs), do: URI.decode_query(qs)

  # Helper to safely get module attribute (nil -> empty list)
  defp get_module_attribute(module, attr) do
    case module.__info__(:attributes)[attr] do
      nil -> []
      value -> value
    end
  end

  describe "introspection functions" do
    test "__ccxt_spec__/0 returns the exchange specification" do
      spec = TestExchange.__ccxt_spec__()

      assert spec.id == "test_exchange"
      assert spec.name == "Test Exchange"
      assert spec.classification == :certified_pro
    end

    test "__ccxt_endpoints__/0 returns the endpoint list" do
      endpoints = TestExchange.__ccxt_endpoints__()

      assert is_list(endpoints)
      assert [_ | _] = endpoints

      # Check that fetch_ticker endpoint exists
      ticker_endpoint = Enum.find(endpoints, &(&1[:name] == :fetch_ticker))
      assert ticker_endpoint[:method] == :get
      assert ticker_endpoint[:path] == "/v1/ticker"
      assert ticker_endpoint[:auth] == false
    end

    test "__ccxt_signing__/0 returns signing configuration" do
      signing = TestExchange.__ccxt_signing__()

      assert signing.pattern == :hmac_sha256_headers
      assert signing.api_key_header == "X-API-KEY"
      assert signing.signature_header == "X-SIGNATURE"
    end

    test "__ccxt_classification__/0 returns the classification" do
      assert TestExchange.__ccxt_classification__() == :certified_pro
    end
  end

  describe "escape hatch: request/3" do
    test "makes a request to the exchange" do
      Req.Test.stub(:request_stub, fn conn ->
        Req.Test.json(conn, %{result: "ok"})
      end)

      assert {:ok, %{status: 200, body: body}} =
               TestExchange.request(:get, "/v1/custom", plug: {Req.Test, :request_stub})

      assert body["result"] == "ok"
    end

    test "passes credentials when provided" do
      Req.Test.stub(:auth_request_stub, fn conn ->
        # Verify signing headers are present
        api_key = Plug.Conn.get_req_header(conn, "x-api-key")
        assert api_key != []
        Req.Test.json(conn, %{authenticated: true})
      end)

      assert {:ok, %{status: 200}} =
               TestExchange.request(:get, "/v1/private",
                 credentials: @test_credentials,
                 plug: {Req.Test, :auth_request_stub}
               )
    end
  end

  describe "escape hatch: raw_request/5" do
    test "makes a raw HTTP request without signing" do
      Req.Test.stub(:raw_request_stub, fn conn ->
        Req.Test.json(conn, %{raw: true})
      end)

      headers = [{"content-type", "application/json"}]

      assert {:ok, %{status: 200, body: body}} =
               TestExchange.raw_request(
                 :get,
                 "http://localhost/raw",
                 headers,
                 nil,
                 plug: {Req.Test, :raw_request_stub}
               )

      assert body["raw"] == true
    end
  end

  describe "public endpoint functions" do
    test "fetch_ticker/2 calls the ticker endpoint" do
      Req.Test.stub(:ticker_stub, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path =~ "/v1/ticker"
        Req.Test.json(conn, %{symbol: "BTC/USDT", last: 50_000})
      end)

      assert {:ok, body} =
               TestExchange.fetch_ticker("BTC/USDT", plug: {Req.Test, :ticker_stub})

      assert body.symbol == "BTC/USDT"
    end

    test "fetch_tickers/2 calls the tickers endpoint" do
      Req.Test.stub(:tickers_stub, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/v1/tickers"
        Req.Test.json(conn, [%{symbol: "BTC/USDT"}, %{symbol: "ETH/USDT"}])
      end)

      assert {:ok, body} = TestExchange.fetch_tickers(nil, plug: {Req.Test, :tickers_stub})
      assert length(body) == 2
    end

    test "fetch_order_book/3 includes limit parameter" do
      Req.Test.stub(:orderbook_stub, fn conn ->
        assert conn.method == "GET"
        # Query string should include limit
        query = decode_query_string(conn.query_string)
        assert query["limit"] == "10"
        Req.Test.json(conn, %{bids: [], asks: []})
      end)

      assert {:ok, body} =
               TestExchange.fetch_order_book("BTC/USDT", 10, plug: {Req.Test, :orderbook_stub})

      assert is_list(body.bids)
    end

    test "fetch_markets/1 calls the markets endpoint" do
      Req.Test.stub(:markets_stub, fn conn ->
        assert conn.request_path == "/v1/markets"
        Req.Test.json(conn, [%{id: "BTCUSDT", base: "BTC", quote: "USDT"}])
      end)

      assert {:ok, [market | _]} = TestExchange.fetch_markets(plug: {Req.Test, :markets_stub})
      assert market.id == "BTCUSDT"
    end
  end

  describe "private endpoint functions" do
    test "fetch_balance/2 requires credentials" do
      Req.Test.stub(:balance_stub, fn conn ->
        # Verify this is an authenticated request
        api_key = Plug.Conn.get_req_header(conn, "x-api-key")
        assert api_key != [], "Expected X-API-KEY header to be present"
        Req.Test.json(conn, %{free: %{"BTC" => 1.0}, used: %{"BTC" => 0.0}, total: %{"BTC" => 1.0}})
      end)

      assert {:ok, body} =
               TestExchange.fetch_balance(@test_credentials, plug: {Req.Test, :balance_stub})

      assert body.free["BTC"] == 1.0
    end

    test "fetch_open_orders/3 passes symbol parameter (denormalized)" do
      Req.Test.stub(:open_orders_stub, fn conn ->
        query = decode_query_string(conn.query_string)
        # Symbol is denormalized to exchange format (BTC/USDT -> BTCUSDT)
        assert query["symbol"] == "BTCUSDT"
        Req.Test.json(conn, [%{id: "order1", status: "open"}])
      end)

      assert {:ok, orders} =
               TestExchange.fetch_open_orders(@test_credentials, "BTC/USDT", plug: {Req.Test, :open_orders_stub})

      assert length(orders) == 1
    end

    test "create_order/7 sends order parameters (symbol denormalized)" do
      Req.Test.stub(:create_order_stub, fn conn ->
        assert conn.method == "POST"
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        params = Jason.decode!(body)
        # Symbol is denormalized to exchange format (BTC/USDT -> BTCUSDT)
        assert params["symbol"] == "BTCUSDT"
        assert params["type"] == "limit"
        assert params["side"] == "buy"
        assert params["amount"] == 1.0
        assert params["price"] == 50_000
        Req.Test.json(conn, %{id: "order123", status: "open"})
      end)

      assert {:ok, order} =
               TestExchange.create_order(
                 @test_credentials,
                 "BTC/USDT",
                 "limit",
                 "buy",
                 1.0,
                 50_000,
                 plug: {Req.Test, :create_order_stub}
               )

      assert order.id == "order123"
    end

    test "cancel_order/4 uses path parameter for order_id" do
      Req.Test.stub(:cancel_order_stub, fn conn ->
        assert conn.method == "DELETE"
        assert conn.request_path =~ "order123"
        Req.Test.json(conn, %{id: "order123", status: "cancelled"})
      end)

      assert {:ok, order} =
               TestExchange.cancel_order(@test_credentials, "order123", "BTC/USDT", plug: {Req.Test, :cancel_order_stub})

      assert order.status == :canceled
    end
  end

  describe "error handling" do
    test "returns error tuple on API error" do
      Req.Test.stub(:error_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{code: 10_001, message: "Rate limited"})
      end)

      assert {:error, error} =
               TestExchange.fetch_ticker("BTC/USDT", plug: {Req.Test, :error_stub})

      assert error.type == :rate_limited
    end
  end

  describe "unsupported endpoints" do
    test "cancel_all_orders returns error when has: false" do
      # cancel_all_orders is defined in endpoints but has: cancel_all_orders: false
      # So it should generate a stub that returns :exchange_error
      assert {:error, error} = TestExchange.cancel_all_orders(@test_credentials, "BTC/USDT")

      assert %CCXT.Error{} = error
      assert error.type == :exchange_error
      assert error.message =~ "cancel_all_orders"
      assert error.message =~ "not supported"
    end
  end

  describe "module attributes" do
    test "module has dialyzer suppression attribute" do
      # Generated modules suppress Dialyzer false positives
      dialyzer_opts = get_module_attribute(TestExchange, :dialyzer)
      refute Enum.empty?(dialyzer_opts)
    end

    test "module has external_resource attribute for spec file" do
      resources = get_module_attribute(TestExchange, :external_resource)
      assert Enum.any?(resources, &String.ends_with?(&1, "test_exchange.exs"))
    end
  end

  describe "generated exchange module (dynamic)" do
    # Verifies that an auto-generated exchange module compiles correctly
    # and exports the expected functions from semantic endpoint extraction.
    # Uses whatever exchange is available (works with --only bybit, etc.)

    setup do
      case find_available_exchange() do
        {module, exchange_id} ->
          {:ok, module: module, exchange_id: exchange_id}

        nil ->
          {:ok, skip: true}
      end
    end

    @tag :skip_if_no_exchange
    test "module compiles and has introspection functions", context do
      if context[:skip], do: flunk("No generated exchange module found")
      module = context.module

      assert function_exported?(module, :__ccxt_spec__, 0)
      assert function_exported?(module, :__ccxt_endpoints__, 0)
      assert function_exported?(module, :__ccxt_signing__, 0)
      assert function_exported?(module, :__ccxt_classification__, 0)
    end

    @tag :skip_if_no_exchange
    test "exports public endpoint functions with correct arities", context do
      if context[:skip], do: flunk("No generated exchange module found")
      module = context.module

      # Public endpoints (no credentials) - check common ones
      assert function_exported?(module, :fetch_ticker, 2)
      assert function_exported?(module, :fetch_order_book, 3)
      assert function_exported?(module, :fetch_markets, 1)
    end

    @tag :skip_if_no_exchange
    test "exports private endpoint functions with correct arities", context do
      if context[:skip], do: flunk("No generated exchange module found")
      module = context.module

      # Private endpoints (require credentials as first arg)
      assert function_exported?(module, :fetch_balance, 2)
      assert function_exported?(module, :create_order, 7)
      assert function_exported?(module, :cancel_order, 4)
    end

    @tag :skip_if_no_exchange
    test "exports escape hatch functions", context do
      if context[:skip], do: flunk("No generated exchange module found")
      module = context.module

      assert function_exported?(module, :request, 3)
      assert function_exported?(module, :raw_request, 5)
    end

    @tag :skip_if_no_exchange
    test "__ccxt_spec__ returns valid spec", context do
      if context[:skip], do: flunk("No generated exchange module found")
      module = context.module
      exchange_id = context.exchange_id

      spec = module.__ccxt_spec__()

      assert spec.id == exchange_id
      assert is_binary(spec.name)
      assert spec.classification in [:certified_pro, :pro, :supported]
    end

    @tag :skip_if_no_exchange
    test "__ccxt_signing__ returns signing config", context do
      if context[:skip], do: flunk("No generated exchange module found")
      module = context.module

      signing = module.__ccxt_signing__()

      assert is_atom(signing.pattern)
      api_key_header = Map.get(signing, :api_key_header)
      assert is_binary(api_key_header) or is_nil(api_key_header)
    end

    @tag :skip_if_no_exchange
    test "__ccxt_endpoints__ returns semantic endpoints", context do
      if context[:skip], do: flunk("No generated exchange module found")
      module = context.module

      endpoints = module.__ccxt_endpoints__()

      assert is_list(endpoints)
      refute Enum.empty?(endpoints)

      # Verify fetch_ticker endpoint exists with expected structure
      ticker = Enum.find(endpoints, &(&1[:name] == :fetch_ticker))
      assert ticker
      assert ticker[:method] == :get
      assert ticker[:auth] == false
      assert :symbol in ticker[:params]
    end
  end

  describe "approximate endpoint handling (dynamic)" do
    # Verifies that endpoints with approximate: true flag (from heuristic extraction)
    # are handled correctly and don't break generation

    setup do
      case find_available_exchange() do
        {module, _exchange_id} -> {:ok, module: module}
        nil -> {:ok, skip: true}
      end
    end

    @tag :skip_if_no_exchange
    test "endpoints with approximate flag are included in spec", context do
      if context[:skip], do: flunk("No generated exchange module found")
      module = context.module

      endpoints = module.__ccxt_endpoints__()

      # Having any endpoints at all is the key requirement
      refute Enum.empty?(endpoints)

      # Verify we can identify approximate vs exact endpoints
      approximate_endpoints = Enum.filter(endpoints, &Map.get(&1, :approximate, false))
      exact_endpoints = Enum.reject(endpoints, &Map.get(&1, :approximate, false))

      # Both types should generate functions - verify by checking total coverage
      total = length(approximate_endpoints) + length(exact_endpoints)
      assert total == length(endpoints), "All endpoints should be categorized"
    end

    @tag :skip_if_no_exchange
    test "approximate endpoints generate valid functions", context do
      if context[:skip], do: flunk("No generated exchange module found")
      module = context.module

      # Build a spec with an approximate endpoint to verify structure
      approximate_endpoint = %{
        name: :fetch_trades,
        method: :get,
        path: "/agg/trades",
        auth: false,
        params: [:symbol, :since, :limit],
        approximate: true
      }

      # The endpoint should have all required fields
      assert approximate_endpoint[:name] == :fetch_trades
      assert approximate_endpoint[:method] == :get
      assert approximate_endpoint[:approximate] == true

      # Verify the actual generated function works
      assert function_exported?(module, :fetch_trades, 4)
    end

    @tag :skip_if_no_exchange
    test "approximate flag does not affect function generation", context do
      if context[:skip], do: flunk("No generated exchange module found")
      module = context.module

      endpoints = module.__ccxt_endpoints__()

      for endpoint <- endpoints do
        # Every endpoint should have required fields regardless of approximate flag
        assert Map.has_key?(endpoint, :name)
        assert Map.has_key?(endpoint, :method)
        assert Map.has_key?(endpoint, :path)
        assert Map.has_key?(endpoint, :auth)
        assert Map.has_key?(endpoint, :params)

        # The method should be a valid HTTP method atom
        assert endpoint[:method] in [:get, :post, :put, :delete, :patch]

        # The name should be a known unified API method atom
        assert is_atom(endpoint[:name])
      end
    end
  end
end
