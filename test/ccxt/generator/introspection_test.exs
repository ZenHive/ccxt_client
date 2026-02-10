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
      spec = build_spec(options: %{accounts_by_type: %{"spot" => "SPOT"}})
      assert Introspection.default_account_type(spec) == nil
    end
  end

  describe "with spec with no options" do
    test "default_account_type returns nil" do
      spec = build_spec(options: nil)
      assert Introspection.default_account_type(spec) == nil
    end

    test "default_derivatives_category returns nil" do
      spec = build_spec(options: %{})
      assert Introspection.default_derivatives_category(spec) == nil
    end
  end

  # ===========================================================================
  # Task 21: uses_category_param?, uses_account_type_param?, default_settle_coin
  # ===========================================================================

  describe "uses_category_param?/1" do
    test "returns true when option set" do
      spec = build_spec(options: %{uses_category_param: true})
      assert Introspection.uses_category_param?(spec) == true
    end

    test "returns false when option absent" do
      spec = build_spec(options: %{})
      assert Introspection.uses_category_param?(spec) == false
    end

    test "returns false when options nil" do
      spec = build_spec(options: nil)
      assert Introspection.uses_category_param?(spec) == false
    end
  end

  describe "uses_account_type_param?/1" do
    test "returns true when option set" do
      spec = build_spec(options: %{uses_account_type_param: true})
      assert Introspection.uses_account_type_param?(spec) == true
    end

    test "returns false when option absent" do
      spec = build_spec(options: %{})
      assert Introspection.uses_account_type_param?(spec) == false
    end
  end

  describe "default_settle_coin/1" do
    test "returns value when set" do
      spec = build_spec(options: %{default_settle: "USDT"})
      assert Introspection.default_settle_coin(spec) == "USDT"
    end

    test "returns nil when absent" do
      spec = build_spec(options: %{})
      assert Introspection.default_settle_coin(spec) == nil
    end
  end

  # ===========================================================================
  # Task 108: Feature limits and fee info in endpoint_info
  # ===========================================================================

  describe "endpoint_info with feature_limits" do
    test "includes feature_limits for fetch_my_trades when features present" do
      spec =
        build_spec(
          endpoints: [%{name: :fetch_my_trades, method: :get, path: "/trades", auth: true, params: []}],
          has: %{fetch_my_trades: true},
          features: %{
            spot: %{fetch_my_trades: %{limit: 1000}},
            swap: %{fetch_my_trades: %{limit: 500}}
          }
        )

      info = Introspection.endpoint_info(spec, :fetch_my_trades)
      assert info
      assert info.hints.feature_limits.spot == %{limit: 1000}
      assert info.hints.feature_limits.swap == %{limit: 500}
    end

    test "does not include feature_limits when features nil" do
      spec =
        build_spec(
          endpoints: [%{name: :fetch_my_trades, method: :get, path: "/trades", auth: true, params: []}],
          has: %{fetch_my_trades: true}
        )

      info = Introspection.endpoint_info(spec, :fetch_my_trades)
      assert info
      refute Map.has_key?(info.hints, :feature_limits)
    end
  end

  describe "endpoint_info with fee_info" do
    test "includes fee_info for create_order when fees present" do
      spec =
        build_spec(
          endpoints: [%{name: :create_order, method: :post, path: "/order", auth: true, params: [:symbol]}],
          has: %{create_order: true},
          fees: %{
            trading: %{maker: 0.001, taker: 0.002, tier_based: false},
            swap: %{maker: 0.0002, taker: 0.0005}
          }
        )

      info = Introspection.endpoint_info(spec, :create_order)
      assert info
      assert info.hints.fee_info.maker == 0.001
      assert info.hints.fee_info.taker == 0.002
      assert info.hints.fee_info.tier_based == false
      assert info.hints.fee_info.swap == %{maker: 0.0002, taker: 0.0005}
    end

    test "does not include fee_info when fees nil" do
      spec =
        build_spec(
          endpoints: [%{name: :create_order, method: :post, path: "/order", auth: true, params: [:symbol]}],
          has: %{create_order: true}
        )

      info = Introspection.endpoint_info(spec, :create_order)
      assert info
      refute Map.has_key?(info.hints, :fee_info)
    end

    test "does not include fee_info for non-order endpoints" do
      spec =
        build_spec(
          endpoints: [%{name: :fetch_ticker, method: :get, path: "/ticker", auth: false, params: [:symbol]}],
          has: %{fetch_ticker: true},
          fees: %{trading: %{maker: 0.001, taker: 0.002}}
        )

      info = Introspection.endpoint_info(spec, :fetch_ticker)
      assert info
      refute Map.has_key?(info.hints, :fee_info)
    end
  end

  # ===========================================================================
  # Task 21: Additional feature limits and fee info edge cases
  # ===========================================================================

  describe "feature limits with integer values" do
    test "wraps direct integer limit into %{limit: N}" do
      spec =
        build_spec(
          endpoints: [%{name: :fetch_my_trades, method: :get, path: "/trades", auth: true, params: []}],
          features: %{spot: %{fetch_my_trades: 1000}}
        )

      info = Introspection.endpoint_info(spec, :fetch_my_trades)
      assert info.hints.feature_limits.spot == %{limit: 1000}
    end
  end

  describe "feature limits with empty result" do
    test "no feature_limits key when method has no limits in features" do
      spec =
        build_spec(
          endpoints: [%{name: :fetch_my_trades, method: :get, path: "/trades", auth: true, params: []}],
          features: %{spot: %{fetch_ticker: true}}
        )

      info = Introspection.endpoint_info(spec, :fetch_my_trades)
      refute Map.has_key?(info.hints, :feature_limits)
    end
  end

  describe "fee info with nested trading wrapper" do
    test "extracts fees from %{trading: %{maker: ..., taker: ...}}" do
      spec =
        build_spec(
          endpoints: [%{name: :create_order, method: :post, path: "/order", auth: true, params: [:symbol]}],
          fees: %{
            trading: %{maker: 0.001, taker: 0.002},
            swap: %{trading: %{maker: 0.0002, taker: 0.0005}}
          }
        )

      info = Introspection.endpoint_info(spec, :create_order)
      assert info.hints.fee_info.maker == 0.001
      assert info.hints.fee_info.swap == %{maker: 0.0002, taker: 0.0005}
    end
  end

  describe "fee info with map missing maker/taker" do
    test "skips market type with irrelevant map keys" do
      spec =
        build_spec(
          endpoints: [%{name: :create_order, method: :post, path: "/order", auth: true, params: [:symbol]}],
          fees: %{
            trading: %{maker: 0.001, taker: 0.002},
            spot: %{other: "value"}
          }
        )

      info = Introspection.endpoint_info(spec, :create_order)
      # spot should not appear since it has no maker/taker
      refute Map.has_key?(info.hints.fee_info, :spot)
    end
  end

  describe "fee info with non-map market type value" do
    test "skips non-map values" do
      spec =
        build_spec(
          endpoints: [%{name: :create_order, method: :post, path: "/order", auth: true, params: [:symbol]}],
          fees: %{
            trading: %{maker: 0.001, taker: 0.002},
            spot: "invalid"
          }
        )

      info = Introspection.endpoint_info(spec, :create_order)
      refute Map.has_key?(info.hints.fee_info, :spot)
    end
  end

  describe "fee info with nil market type" do
    test "skips nil market type value" do
      spec =
        build_spec(
          endpoints: [%{name: :create_order, method: :post, path: "/order", auth: true, params: [:symbol]}],
          fees: %{
            trading: %{maker: 0.001, taker: 0.002},
            spot: nil
          }
        )

      info = Introspection.endpoint_info(spec, :create_order)
      refute Map.has_key?(info.hints.fee_info, :spot)
    end
  end

  # ===========================================================================
  # Task 21 (extra): Cover remaining uncovered lines
  # ===========================================================================

  describe "required_params/2 returns non-empty list" do
    test "returns required_extra_params for account_type method with default_account_type" do
      spec =
        build_spec(
          endpoints: [%{name: :fetch_balance, method: :get, path: "/balance", auth: true, params: []}],
          options: %{
            default_account_type: "unified",
            accounts_by_type: %{"unified" => "UNIFIED"}
          }
        )

      params = Introspection.required_params(spec, :fetch_balance)
      assert :accountType in params
    end
  end

  describe "derivatives category hints" do
    test "includes derivatives_category for derivatives method with default_sub_type" do
      spec =
        build_spec(
          endpoints: [%{name: :fetch_positions, method: :get, path: "/positions", auth: true, params: []}],
          options: %{default_sub_type: "linear"}
        )

      info = Introspection.endpoint_info(spec, :fetch_positions)
      assert info.hints.derivatives_category == "linear"
      assert :category in info.hints.required_extra_params
    end
  end

  describe "param mappings hints" do
    test "includes param_mappings when spec has non-empty param_mappings" do
      spec =
        build_spec(
          endpoints: [%{name: :fetch_ticker, method: :get, path: "/ticker", auth: false, params: [:symbol]}],
          param_mappings: %{symbol: "instId"}
        )

      info = Introspection.endpoint_info(spec, :fetch_ticker)
      assert info.hints.param_mappings == %{symbol: "instId"}
    end
  end

  describe "OHLCV timestamp resolution hints" do
    test "includes timestamp_resolution for fetch_ohlcv with milliseconds" do
      spec =
        build_spec(
          endpoints: [%{name: :fetch_ohlcv, method: :get, path: "/ohlcv", auth: false, params: [:symbol]}],
          ohlcv_timestamp_resolution: :milliseconds
        )

      info = Introspection.endpoint_info(spec, :fetch_ohlcv)
      assert info.hints.timestamp_resolution == :milliseconds
      assert info.hints.timestamp_note =~ "milliseconds (standard)"
    end

    test "includes seconds note for seconds resolution" do
      spec =
        build_spec(
          endpoints: [%{name: :fetch_ohlcv, method: :get, path: "/ohlcv", auth: false, params: [:symbol]}],
          ohlcv_timestamp_resolution: :seconds
        )

      info = Introspection.endpoint_info(spec, :fetch_ohlcv)
      assert info.hints.timestamp_resolution == :seconds
      assert info.hints.timestamp_note =~ "converts to seconds"
    end

    test "includes unknown note for unknown resolution" do
      spec =
        build_spec(
          endpoints: [%{name: :fetch_ohlcv, method: :get, path: "/ohlcv", auth: false, params: [:symbol]}],
          ohlcv_timestamp_resolution: :unknown
        )

      info = Introspection.endpoint_info(spec, :fetch_ohlcv)
      assert info.hints.timestamp_resolution == :unknown
      assert info.hints.timestamp_note =~ "resolution not detected"
    end
  end

  describe "fee info with empty result" do
    test "no fee_info key when fees has no trading and no market-type fees" do
      spec =
        build_spec(
          endpoints: [%{name: :create_order, method: :post, path: "/order", auth: true, params: [:symbol]}],
          fees: %{trading: nil}
        )

      info = Introspection.endpoint_info(spec, :create_order)
      refute Map.has_key?(info.hints, :fee_info)
    end
  end

  # Helper to build synthetic specs with minimal boilerplate
  defp build_spec(overrides) do
    %Spec{
      id: :test_exchange,
      name: "Test",
      classification: :supported,
      urls: %{api: "https://api.test.com"},
      signing: %{pattern: :none},
      endpoints: Keyword.get(overrides, :endpoints, []),
      has: Keyword.get(overrides, :has, %{}),
      options: Keyword.get(overrides, :options, %{}),
      features: Keyword.get(overrides, :features, nil),
      fees: Keyword.get(overrides, :fees, nil),
      param_mappings: Keyword.get(overrides, :param_mappings, nil),
      ohlcv_timestamp_resolution: Keyword.get(overrides, :ohlcv_timestamp_resolution, nil)
    }
  end
end
