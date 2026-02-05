defmodule CCXT.Generator.IntrospectionTest do
  @moduledoc """
  Tests for the introspection helpers that provide parameter discoverability.

  These tests verify that introspection functions work correctly with any
  available exchange spec, supporting `--only` mode development.
  """
  use ExUnit.Case, async: true

  alias CCXT.Generator.Introspection
  alias CCXT.Spec
  alias CCXT.Test.ExchangeHelper

  # Dynamically find an available spec for testing
  @spec_path ExchangeHelper.first_available_spec_path()

  if @spec_path do
    @exchange_id ExchangeHelper.exchange_id_from_path(@spec_path)

    setup_all do
      spec = Spec.load!(@spec_path)
      {:ok, spec: spec, exchange_id: @exchange_id}
    end

    describe "endpoint_info/2" do
      test "returns nil for unknown endpoint", %{spec: spec} do
        assert Introspection.endpoint_info(spec, :unknown_endpoint) == nil
      end

      test "returns endpoint info for fetch_balance if available", %{spec: spec} do
        info = Introspection.endpoint_info(spec, :fetch_balance)

        if info do
          assert info.name == :fetch_balance
          assert is_map(info.hints)
        end
      end

      test "endpoint info includes hints map when available", %{spec: spec} do
        # Find any endpoint that exists in the spec
        endpoint_name =
          case spec.endpoints do
            [first | _] -> first.name
            [] -> nil
          end

        if endpoint_name do
          info = Introspection.endpoint_info(spec, endpoint_name)

          if info do
            assert is_map(info.hints)
          end
        end
      end
    end

    describe "required_params/2" do
      test "returns empty list for unknown endpoint", %{spec: spec} do
        assert Introspection.required_params(spec, :unknown_endpoint) == []
      end

      test "returns list for known endpoints", %{spec: spec} do
        # Test with fetch_balance if it exists
        params = Introspection.required_params(spec, :fetch_balance)
        assert is_list(params)
      end
    end

    describe "default_account_type/1" do
      test "returns string or nil", %{spec: spec} do
        result = Introspection.default_account_type(spec)
        assert is_nil(result) or is_binary(result)
      end
    end

    describe "default_derivatives_category/1" do
      test "returns string or nil", %{spec: spec} do
        result = Introspection.default_derivatives_category(spec)
        assert is_nil(result) or is_binary(result)
      end
    end
  else
    @tag :skip
    test "skipped - no spec files available" do
      flunk("""
      No exchange specs found!

      Run `mix ccxt.sync <exchange> --only` to generate specs.
      Example: mix ccxt.sync bybit --only --force
      """)
    end
  end

  # Tests with synthetic specs (always run)
  describe "with spec without unified accounts" do
    test "default_account_type returns nil" do
      spec_without_unified = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [],
        has: %{},
        options: %{accounts_by_type: %{"spot" => "SPOT"}}
      }

      assert Introspection.default_account_type(spec_without_unified) == nil
    end
  end

  describe "with spec with no options" do
    test "default_account_type returns nil" do
      spec_no_options = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [],
        has: %{},
        options: nil
      }

      assert Introspection.default_account_type(spec_no_options) == nil
    end

    test "default_derivatives_category returns nil" do
      spec_no_derivatives = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [],
        has: %{},
        options: %{}
      }

      assert Introspection.default_derivatives_category(spec_no_derivatives) == nil
    end
  end

  # ===========================================================================
  # Task 108: Feature limits and fee info in endpoint_info
  # ===========================================================================

  describe "endpoint_info with feature_limits" do
    test "includes feature_limits for fetch_my_trades when features present" do
      spec_with_features = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [%{name: :fetch_my_trades, method: :get, path: "/trades", auth: true, params: []}],
        has: %{fetch_my_trades: true},
        options: %{},
        features: %{
          spot: %{fetch_my_trades: %{limit: 1000}},
          swap: %{fetch_my_trades: %{limit: 500}}
        }
      }

      info = Introspection.endpoint_info(spec_with_features, :fetch_my_trades)
      assert info
      assert info.hints.feature_limits.spot == %{limit: 1000}
      assert info.hints.feature_limits.swap == %{limit: 500}
    end

    test "does not include feature_limits when features nil" do
      spec_no_features = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [%{name: :fetch_my_trades, method: :get, path: "/trades", auth: true, params: []}],
        has: %{fetch_my_trades: true},
        options: %{},
        features: nil
      }

      info = Introspection.endpoint_info(spec_no_features, :fetch_my_trades)
      assert info
      refute Map.has_key?(info.hints, :feature_limits)
    end
  end

  describe "endpoint_info with fee_info" do
    test "includes fee_info for create_order when fees present" do
      spec_with_fees = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [%{name: :create_order, method: :post, path: "/order", auth: true, params: [:symbol]}],
        has: %{create_order: true},
        options: %{},
        fees: %{
          trading: %{maker: 0.001, taker: 0.002, tier_based: false},
          swap: %{maker: 0.0002, taker: 0.0005}
        }
      }

      info = Introspection.endpoint_info(spec_with_fees, :create_order)
      assert info
      assert info.hints.fee_info.maker == 0.001
      assert info.hints.fee_info.taker == 0.002
      assert info.hints.fee_info.tier_based == false
      assert info.hints.fee_info.swap == %{maker: 0.0002, taker: 0.0005}
    end

    test "does not include fee_info when fees nil" do
      spec_no_fees = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [%{name: :create_order, method: :post, path: "/order", auth: true, params: [:symbol]}],
        has: %{create_order: true},
        options: %{},
        fees: nil
      }

      info = Introspection.endpoint_info(spec_no_fees, :create_order)
      assert info
      refute Map.has_key?(info.hints, :fee_info)
    end

    test "does not include fee_info for non-order endpoints" do
      spec_with_fees = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [%{name: :fetch_ticker, method: :get, path: "/ticker", auth: false, params: [:symbol]}],
        has: %{fetch_ticker: true},
        options: %{},
        fees: %{trading: %{maker: 0.001, taker: 0.002}}
      }

      info = Introspection.endpoint_info(spec_with_fees, :fetch_ticker)
      assert info
      refute Map.has_key?(info.hints, :fee_info)
    end
  end
end
