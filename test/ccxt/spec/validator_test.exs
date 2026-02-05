defmodule CCXT.Spec.ValidatorTest do
  use ExUnit.Case, async: true

  alias CCXT.Spec
  alias CCXT.Spec.Validator

  @valid_spec %{
    id: "test_exchange",
    name: "Test Exchange",
    urls: %{api: "https://api.test.com"},
    endpoints: []
  }

  describe "validate/1" do
    test "accepts valid spec with no endpoints" do
      spec = Spec.from_map(@valid_spec)
      assert {:ok, ^spec} = Validator.validate(spec)
    end

    test "accepts spec with valid endpoint using :get method" do
      spec = build_spec_with_endpoint(:get)
      assert {:ok, _} = Validator.validate(spec)
    end

    test "accepts spec with valid endpoint using :post method" do
      spec = build_spec_with_endpoint(:post)
      assert {:ok, _} = Validator.validate(spec)
    end

    test "accepts spec with valid endpoint using :put method" do
      spec = build_spec_with_endpoint(:put)
      assert {:ok, _} = Validator.validate(spec)
    end

    test "accepts spec with valid endpoint using :patch method" do
      spec = build_spec_with_endpoint(:patch)
      assert {:ok, _} = Validator.validate(spec)
    end

    test "accepts spec with valid endpoint using :delete method" do
      spec = build_spec_with_endpoint(:delete)
      assert {:ok, _} = Validator.validate(spec)
    end

    test "rejects invalid HTTP method" do
      spec = build_spec_with_endpoint(:invalid_method)
      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "method must be"))
    end

    test "rejects endpoint with non-atom name" do
      # Note: nil is an atom in Elixir, so missing name passes validation
      # This tests that string names are rejected
      endpoint = %{name: "string_name", method: :get, path: "/test", auth: false, params: []}
      spec = build_spec_with_raw_endpoint(endpoint)
      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "name must be an atom"))
    end

    test "rejects endpoint with missing path" do
      endpoint = %{name: :test, method: :get, auth: false, params: []}
      spec = build_spec_with_raw_endpoint(endpoint)
      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "path must be a string"))
    end

    test "rejects endpoint with missing auth" do
      endpoint = %{name: :test, method: :get, path: "/test", params: []}
      spec = build_spec_with_raw_endpoint(endpoint)
      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "auth must be a boolean"))
    end

    test "rejects endpoint with missing params" do
      endpoint = %{name: :test, method: :get, path: "/test", auth: false}
      spec = build_spec_with_raw_endpoint(endpoint)
      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "params must be a list"))
    end

    test "rejects spec with empty id" do
      spec = Spec.from_map(%{@valid_spec | id: ""})
      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "id is required"))
    end

    test "rejects spec with empty name" do
      spec = Spec.from_map(%{@valid_spec | name: ""})
      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "name is required"))
    end

    test "rejects spec with missing api url" do
      spec = Spec.from_map(%{@valid_spec | urls: %{}})
      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "urls.api is required"))
    end

    test "rejects spec with invalid classification" do
      spec = Spec.from_map(Map.put(@valid_spec, :classification, :invalid))
      assert {:error, errors} = Validator.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "classification must be"))
    end
  end

  describe "validate!/2" do
    test "returns :ok for valid spec" do
      spec = Spec.from_map(@valid_spec)
      assert :ok = Validator.validate!(spec, "test.exs")
    end

    test "raises CompileError for invalid spec" do
      spec = Spec.from_map(%{@valid_spec | id: ""})

      assert_raise CompileError, ~r/id is required/, fn ->
        Validator.validate!(spec, "test.exs")
      end
    end
  end

  # Helper to build a spec with a single valid endpoint using given method
  defp build_spec_with_endpoint(method) do
    endpoint = %{
      name: :test_endpoint,
      method: method,
      path: "/test",
      auth: false,
      params: []
    }

    Spec.from_map(Map.put(@valid_spec, :endpoints, [endpoint]))
  end

  # Helper to build a spec with a raw endpoint map (for testing validation)
  defp build_spec_with_raw_endpoint(endpoint) do
    Spec.from_map(Map.put(@valid_spec, :endpoints, [endpoint]))
  end

  # ===========================================================================
  # Task 111: Semantic Validation Tests
  # ===========================================================================

  describe "semantic_warnings/1" do
    test "returns empty list for spec with consistent capabilities and endpoints" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"},
          has: %{fetch_ticker: true},
          endpoints: [%{name: :fetch_ticker, method: :get, path: "/ticker", auth: false, params: [:symbol]}]
        })

      assert Validator.semantic_warnings(spec) == []
    end

    test "warns when has.X is true but no endpoint X exists" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"},
          has: %{fetch_ticker: true, fetch_balance: true},
          endpoints: [%{name: :fetch_ticker, method: :get, path: "/ticker", auth: false, params: [:symbol]}]
        })

      warnings = Validator.semantic_warnings(spec)
      assert Enum.any?(warnings, &String.contains?(&1, "has.fetch_balance: true but no endpoint"))
    end

    test "does not warn for non-method capabilities (CORS, spot, swap)" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"},
          has: %{CORS: true, spot: true, swap: false},
          endpoints: []
        })

      warnings = Validator.semantic_warnings(spec)
      assert warnings == []
    end

    test "warns when endpoint market_type not in features" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"},
          has: %{},
          endpoints: [
            %{name: :fetch_position, method: :get, path: "/position", auth: true, params: [], market_type: :swap}
          ],
          features: %{spot: %{margin_mode: false}}
        })

      warnings = Validator.semantic_warnings(spec)
      assert Enum.any?(warnings, &String.contains?(&1, "market_type :swap but features does not include :swap"))
    end

    test "does not warn when endpoint market_type is in features" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"},
          has: %{},
          endpoints: [
            %{name: :fetch_position, method: :get, path: "/position", auth: true, params: [], market_type: :swap}
          ],
          features: %{swap: %{margin_mode: true}}
        })

      warnings = Validator.semantic_warnings(spec)
      refute Enum.any?(warnings, &String.contains?(&1, "market_type"))
    end

    test "does not warn about market_type when features is nil" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"},
          has: %{},
          endpoints: [
            %{name: :fetch_position, method: :get, path: "/position", auth: true, params: [], market_type: :swap}
          ],
          features: nil
        })

      warnings = Validator.semantic_warnings(spec)
      refute Enum.any?(warnings, &String.contains?(&1, "market_type"))
    end

    test "warns when fees present but missing trading.maker and trading.taker" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"},
          has: %{},
          endpoints: [],
          fees: %{funding: %{rate: 0.0001}}
        })

      warnings = Validator.semantic_warnings(spec)
      assert Enum.any?(warnings, &String.contains?(&1, "missing trading.maker and trading.taker"))
    end

    test "does not warn when fees have trading.maker" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"},
          has: %{},
          endpoints: [],
          fees: %{trading: %{maker: 0.001}}
        })

      warnings = Validator.semantic_warnings(spec)
      refute Enum.any?(warnings, &String.contains?(&1, "trading.maker"))
    end

    test "does not warn when fees have trading.taker" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"},
          has: %{},
          endpoints: [],
          fees: %{trading: %{taker: 0.002}}
        })

      warnings = Validator.semantic_warnings(spec)
      refute Enum.any?(warnings, &String.contains?(&1, "trading.taker"))
    end

    test "does not warn when fees is nil" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"},
          has: %{},
          endpoints: [],
          fees: nil
        })

      warnings = Validator.semantic_warnings(spec)
      assert warnings == []
    end
  end
end
