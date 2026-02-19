defmodule CCXT.Generator.Functions.EndpointsTest do
  @moduledoc """
  Tests for endpoint function AST generation.

  Exercises generate_endpoints/1 by constructing Spec structs that trigger
  different code paths (public/private, path interpolation, failure stubs,
  emulated methods, OHLCV conversion, prefix handling).
  """
  use ExUnit.Case, async: true

  alias CCXT.Generator.Functions.Endpoints
  alias CCXT.Spec

  # ===========================================================================
  # Basic endpoint generation
  # ===========================================================================

  describe "generate_endpoints/1 basic generation" do
    test "single public GET endpoint generates def" do
      spec = build_spec(endpoints: [ticker_endpoint()])
      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "def fetch_ticker"
      assert code =~ "@spec fetch_ticker"
      assert code =~ "@doc"
    end

    test "authenticated endpoint takes credentials argument" do
      spec = build_spec(endpoints: [balance_endpoint()])
      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "def fetch_balance"
      assert code =~ "credentials"
    end

    test "endpoint with optional :limit param gets default nil" do
      endpoint = %{
        name: :fetch_trades,
        method: :get,
        path: "/trades",
        auth: false,
        params: [:symbol, :limit]
      }

      spec = build_spec(endpoints: [endpoint])
      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "def fetch_trades"
      # :limit is optional so should have \\ nil default
      assert code =~ "nil"
    end

    test "endpoint with has: false generates unsupported stub" do
      spec =
        build_spec(
          endpoints: [ticker_endpoint()],
          has: %{fetch_ticker: false}
        )

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "def fetch_ticker"
      assert code =~ "not supported"
      assert code =~ ":exchange_error"
    end

    test "endpoint with required_params does not add nil default" do
      endpoint = %{
        name: :fetch_trades,
        method: :get,
        path: "/trades",
        auth: false,
        params: [:symbol, :limit],
        required_params: [:symbol, :limit]
      }

      spec = build_spec(endpoints: [endpoint])
      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "def fetch_trades"
      # :limit is normally optional (\\ nil), but required_params overrides that
      refute code =~ ~S(\\ nil)
    end

    test "endpoint without required_params generates all arities including /1" do
      # Task 176 regression: when since/limit are optional, the function
      # must be callable with just symbol (arity 1).
      # Compile a real module and check arities from __info__(:functions).
      endpoint = %{
        name: :fetch_trades,
        method: :get,
        path: "/trades",
        auth: false,
        params: [:symbol, :since, :limit]
      }

      spec = build_spec(endpoints: [endpoint])
      mod = compile_endpoint_module(spec)

      arities =
        :functions
        |> mod.__info__()
        |> Enum.filter(fn {name, _} -> name == :fetch_trades end)
        |> Enum.map(fn {_, arity} -> arity end)
        |> Enum.sort()

      # symbol-only (/1) must exist alongside /2, /3, /4
      assert 1 in arities, "fetch_trades/1 (symbol-only) must be generated"
      assert 2 in arities
      assert 3 in arities
      assert 4 in arities
    end

    test "endpoint with required_params omits lower arities" do
      endpoint = %{
        name: :fetch_trades,
        method: :get,
        path: "/trades",
        auth: false,
        params: [:symbol, :since, :limit],
        required_params: [:symbol, :since, :limit]
      }

      spec = build_spec(endpoints: [endpoint])
      mod = compile_endpoint_module(spec)

      arities =
        :functions
        |> mod.__info__()
        |> Enum.filter(fn {name, _} -> name == :fetch_trades end)
        |> Enum.map(fn {_, arity} -> arity end)
        |> Enum.sort()

      # All params required — no defaults, so only full arity + opts
      refute 1 in arities, "fetch_trades/1 should NOT exist when all params required"
    end

    test "endpoint response_type is nil after normalization removal (RN-2)" do
      endpoint = Map.put(ticker_endpoint(), :response_type, :ticker)
      spec = build_spec(endpoints: [endpoint])
      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "def fetch_ticker"
      # response_type is always nil now — normalization moved to ccxt_client
      refute code =~ ":ticker"
    end
  end

  # ===========================================================================
  # Path interpolation
  # ===========================================================================

  describe "generate_endpoints/1 path interpolation" do
    test "colon-style path :symbol generates Regex.replace" do
      endpoint = %{
        name: :fetch_ticker,
        method: :get,
        path: "/ticker/:symbol",
        auth: false,
        params: [:symbol]
      }

      spec = build_spec(endpoints: [endpoint])
      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "Regex.replace"
      assert code =~ ":symbol"
    end

    test "curly-brace path {id} without param_mappings generates simple interpolation" do
      endpoint = %{
        name: :fetch_order,
        method: :get,
        path: "/orders/{id}",
        auth: true,
        params: [:id]
      }

      spec = build_spec(endpoints: [endpoint])
      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "Regex.replace"
      assert code =~ "{id}"
    end

    test "curly-brace path with param_mappings generates alias interpolation" do
      endpoint = %{
        name: :cancel_order,
        method: :delete,
        path: "/orders/{order-id}",
        auth: true,
        params: [:id],
        param_mappings: %{"id" => "order-id"}
      }

      spec = build_spec(endpoints: [endpoint])
      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "aliases"
      assert code =~ "Regex.replace"
    end

    test "authenticated endpoint with path placeholder combines both" do
      endpoint = %{
        name: :cancel_order,
        method: :delete,
        path: "/orders/:id",
        auth: true,
        params: [:id]
      }

      spec = build_spec(endpoints: [endpoint])
      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "def cancel_order"
      assert code =~ "credentials"
      assert code =~ "Regex.replace"
      assert code =~ ":id"
    end

    test "no-placeholder path returns path as-is" do
      endpoint = %{
        name: :fetch_balance,
        method: :get,
        path: "/account/balance",
        auth: true,
        params: []
      }

      spec = build_spec(endpoints: [endpoint])
      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "/account/balance"
      # Should not have Regex.replace for this path
    end
  end

  # ===========================================================================
  # build_prefixed_path_ast
  # ===========================================================================

  describe "generate_endpoints/1 path prefix handling" do
    test "empty prefix does not alter path" do
      spec =
        build_spec(
          endpoints: [ticker_endpoint()],
          path_prefix: ""
        )

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      # Should have base_path reference but no prefix concatenation
      assert code =~ "base_path"
    end

    test "prefix gets concatenated with path" do
      spec =
        build_spec(
          endpoints: [ticker_endpoint()],
          path_prefix: "/api/v3"
        )

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "/api/v3"
    end

    test "prefix with trailing slash and path with leading slash avoids double slash" do
      endpoint = %{
        name: :fetch_ticker,
        method: :get,
        path: "/ticker",
        auth: false,
        params: [:symbol]
      }

      spec =
        build_spec(
          endpoints: [endpoint],
          path_prefix: "/api/v3/"
        )

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      # Should use String.slice to strip leading "/" from path
      assert code =~ "String.slice"
    end

    test "path already starting with prefix does not re-prefix" do
      endpoint = %{
        name: :fetch_ticker,
        method: :get,
        path: "/api/v3/ticker",
        auth: false,
        params: [:symbol]
      }

      spec =
        build_spec(
          endpoints: [endpoint],
          path_prefix: "/api/v3"
        )

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      # Should just use base_path (path already includes prefix)
      assert code =~ "base_path"
    end
  end

  # ===========================================================================
  # Version override in path prefix
  # ===========================================================================

  describe "generate_endpoints/1 version override path prefix" do
    test "version override replaces prefix version (KuCoin /v2/ symbols)" do
      endpoint = %{
        name: :fetch_markets,
        method: :get,
        path: "/v2/symbols",
        auth: false,
        params: []
      }

      spec =
        build_spec(
          endpoints: [endpoint],
          path_prefix: "/api/v1/"
        )

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      # The generated code should reference "/api/v2/" (version replaced)
      assert code =~ "/api/v2/",
             "Expected version-replaced prefix '/api/v2/' in generated code, got:\n#{code}"

      # Should NOT have the double-version pattern
      refute code =~ "/api/v1/v2/",
             "Must not have double-versioned path '/api/v1/v2/' in generated code"
    end

    test "matching versions still handled by starts_with clause" do
      endpoint = %{
        name: :fetch_ticker,
        method: :get,
        path: "/v5/market/tickers",
        auth: false,
        params: [:symbol]
      }

      spec =
        build_spec(
          endpoints: [endpoint],
          path_prefix: "/v5/"
        )

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      # Path starts with prefix → should use base_path directly
      assert code =~ "base_path"
    end

    test "no version in prefix passes through normally" do
      endpoint = %{
        name: :fetch_ticker,
        method: :get,
        path: "/v2/symbols",
        auth: false,
        params: []
      }

      spec =
        build_spec(
          endpoints: [endpoint],
          path_prefix: ""
        )

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      # Empty prefix → just base_path
      assert code =~ "base_path"
    end

    test "version override with /v3/ path and /v1/ prefix" do
      endpoint = %{
        name: :fetch_currencies,
        method: :get,
        path: "/v3/currencies",
        auth: false,
        params: []
      }

      spec =
        build_spec(
          endpoints: [endpoint],
          path_prefix: "/api/v1/"
        )

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "/api/v3/",
             "Expected version-replaced prefix '/api/v3/' for /v3/ path"

      refute code =~ "/api/v1/v3/"
    end
  end

  # ===========================================================================
  # OHLCV timestamp conversion
  # ===========================================================================

  describe "generate_endpoints/1 OHLCV timestamp conversion" do
    test "fetch_ohlcv endpoint includes timestamp conversion" do
      endpoint = %{
        name: :fetch_ohlcv,
        method: :get,
        path: "/ohlcv",
        auth: false,
        params: [:symbol, :timeframe, :since, :limit]
      }

      spec = build_spec(endpoints: [endpoint])
      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "convert_ohlcv_timestamps"
    end

    test "non-OHLCV endpoint does not include timestamp conversion" do
      spec = build_spec(endpoints: [ticker_endpoint()])
      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      refute code =~ "convert_ohlcv_timestamps"
    end
  end

  # ===========================================================================
  # Extraction failure stubs
  # ===========================================================================

  describe "generate_endpoints/1 extraction failure stubs" do
    test "generates stub for extraction failure" do
      spec =
        build_spec(
          endpoints: [],
          endpoint_extraction_stats: %{
            "failures" => [
              %{"method" => "fetchPosition", "error" => "supports option markets only"}
            ]
          }
        )

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "def fetch_position"
      assert code =~ "supports option markets only"
      assert code =~ "not_supported"
    end

    test "skips failure for method already in endpoints" do
      spec =
        build_spec(
          endpoints: [ticker_endpoint()],
          endpoint_extraction_stats: %{
            "failures" => [
              %{"method" => "fetchTicker", "error" => "some error"}
            ]
          }
        )

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      # Should have fetch_ticker from endpoints, not the failure stub
      assert code =~ "def fetch_ticker"
      # Should NOT have the error message from the failure
      refute code =~ "some error"
    end

    test "skips failure with invalid entry (missing method key)" do
      spec =
        build_spec(
          endpoints: [],
          endpoint_extraction_stats: %{
            "failures" => [
              %{"invalid" => "no method key"}
            ]
          }
        )

      ast = Endpoints.generate_endpoints(spec)
      # Should not crash, just skip the invalid entry
      assert is_list(ast)
    end

    test "handles empty failures list" do
      spec =
        build_spec(
          endpoints: [],
          endpoint_extraction_stats: %{"failures" => []}
        )

      ast = Endpoints.generate_endpoints(spec)
      assert is_list(ast)
    end
  end

  # ===========================================================================
  # Emulated method stubs
  # ===========================================================================

  describe "generate_endpoints/1 emulated method stubs" do
    test "generates emulated stubs for exchange with emulated methods" do
      # Use "binance" which has emulated methods in the JSON
      spec = build_spec(id: "binance", endpoints: [])

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      # binance has fetchCanceledAndClosedOrders as emulated
      assert code =~ "Emulated method"
    end

    test "emulated method already in endpoints is excluded" do
      # Create an endpoint for fetch_canceled_and_closed_orders
      endpoint = %{
        name: :fetch_canceled_and_closed_orders,
        method: :get,
        path: "/orders/closed",
        auth: true,
        params: [:symbol, :since, :limit]
      }

      spec = build_spec(id: "binance", endpoints: [endpoint])

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      # Should NOT have an emulated stub for this method (it's a real endpoint)
      # The method should appear exactly once as a real endpoint
      matches = Regex.scan(~r/def fetch_canceled_and_closed_orders/, code)
      assert length(matches) == 1
    end

    test "emulated method already in failure stubs is excluded" do
      spec =
        build_spec(
          id: "binance",
          endpoints: [],
          endpoint_extraction_stats: %{
            "failures" => [
              %{"method" => "fetchCanceledAndClosedOrders", "error" => "some error"}
            ]
          }
        )

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      # Should have the failure stub, not the emulated stub
      matches = Regex.scan(~r/def fetch_canceled_and_closed_orders/, code)
      assert length(matches) == 1
      assert code =~ "some error"
    end

    test "entry with reasons list includes reason suffix in doc" do
      # binance entries have reasons like ["has_emulated"]
      spec = build_spec(id: "binance", endpoints: [])

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      assert code =~ "has_emulated"
    end

    test "exchange with no emulated methods generates no stubs" do
      spec = build_spec(id: "nonexistent_exchange_xyz", endpoints: [])

      ast = Endpoints.generate_endpoints(spec)
      code = ast_to_string(ast)

      refute code =~ "Emulated method"
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp build_spec(overrides) do
    %Spec{
      id: Keyword.get(overrides, :id, "test_exchange"),
      name: Keyword.get(overrides, :name, "Test Exchange"),
      classification: :supported,
      urls: %{api: "https://api.test.com"},
      signing: %{pattern: :hmac_sha256_query},
      endpoints: Keyword.get(overrides, :endpoints, []),
      has: Keyword.get(overrides, :has, %{}),
      options: %{},
      timeframes: %{},
      path_prefix: Keyword.get(overrides, :path_prefix, ""),
      endpoint_extraction_stats: Keyword.get(overrides, :endpoint_extraction_stats, nil)
    }
  end

  defp ticker_endpoint do
    %{
      name: :fetch_ticker,
      method: :get,
      path: "/ticker",
      auth: false,
      params: [:symbol]
    }
  end

  defp balance_endpoint do
    %{
      name: :fetch_balance,
      method: :get,
      path: "/balance",
      auth: true,
      params: []
    }
  end

  # Compile endpoint AST into a real module and return the module name.
  # This lets us assert on actual arities via __info__(:functions)
  # rather than pattern-matching generated source text.
  defp compile_endpoint_module(spec) do
    ast = Endpoints.generate_endpoints(spec)
    unique = :erlang.unique_integer([:positive])
    module_name = Module.concat(__MODULE__, "Compiled#{unique}")

    {:module, module, _bytecode, _exports} =
      Module.create(
        module_name,
        quote do
          @ccxt_spec unquote(Macro.escape(spec))
          unquote_splicing(List.flatten(ast))
        end,
        Macro.Env.location(__ENV__)
      )

    module
  end

  # Convert AST list to a single string for assertion
  defp ast_to_string(ast) when is_list(ast) do
    ast
    |> List.flatten()
    |> Enum.map_join("\n", &Macro.to_string/1)
  end

  defp ast_to_string(ast), do: Macro.to_string(ast)
end
