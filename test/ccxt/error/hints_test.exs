defmodule CCXT.Error.HintsTest do
  @moduledoc """
  Tests for spec-driven error hints and static type-based hints.
  """
  use ExUnit.Case, async: true

  alias CCXT.Error.Hints
  alias CCXT.Spec
  alias CCXT.Test.ExchangeHelper

  # =============================================================================
  # Static Hints (for_type/2)
  # =============================================================================

  describe "for_type/2 - static hints by error type" do
    test "rate_limited includes retry_after hint when provided" do
      hints = Hints.for_type(:rate_limited, retry_after: 1000)
      assert "Wait 1000ms before retrying" in hints
      assert "Too many requests - implement exponential backoff" in hints
    end

    test "rate_limited without retry_after skips wait hint" do
      hints = Hints.for_type(:rate_limited, [])
      refute Enum.any?(hints, &String.contains?(&1, "Wait"))
      assert "Too many requests - implement exponential backoff" in hints
    end

    test "insufficient_balance returns balance hints" do
      hints = Hints.for_type(:insufficient_balance, [])
      assert "Check account balance" in hints
      assert Enum.any?(hints, &String.contains?(&1, "account type"))
    end

    test "invalid_credentials returns auth hints" do
      hints = Hints.for_type(:invalid_credentials, [])
      assert Enum.any?(hints, &String.contains?(&1, "API key"))
      assert Enum.any?(hints, &String.contains?(&1, "permissions"))
    end

    test "invalid_parameters returns parameter hints" do
      hints = Hints.for_type(:invalid_parameters, [])
      assert Enum.any?(hints, &String.contains?(&1, "parameter"))
    end

    test "order_not_found returns order hints" do
      hints = Hints.for_type(:order_not_found, [])
      assert Enum.any?(hints, &String.contains?(&1, "order"))
    end

    test "invalid_order returns order parameter hints" do
      hints = Hints.for_type(:invalid_order, [])
      assert Enum.any?(hints, &String.contains?(&1, "price"))
    end

    test "market_closed returns market hints" do
      hints = Hints.for_type(:market_closed, [])
      assert Enum.any?(hints, &String.contains?(&1, "closed"))
    end

    test "network_error returns connectivity hints" do
      hints = Hints.for_type(:network_error, [])
      assert Enum.any?(hints, &(String.contains?(&1, "network") or String.contains?(&1, "connectivity")))
    end

    test "access_restricted returns access hints" do
      hints = Hints.for_type(:access_restricted, [])
      assert Enum.any?(hints, &(String.contains?(&1, "geo") or String.contains?(&1, "VPN")))
    end

    test "not_supported returns alternative hints" do
      hints = Hints.for_type(:not_supported, [])
      assert Enum.any?(hints, &String.contains?(&1, "not available"))
    end

    test "exchange_error returns generic hints" do
      hints = Hints.for_type(:exchange_error, [])
      assert Enum.any?(hints, &String.contains?(&1, "error code"))
    end

    test "unknown type returns empty list" do
      hints = Hints.for_type(:unknown_type, [])
      assert hints == []
    end
  end

  describe "merge_hints/3" do
    test "user hints come before auto hints" do
      user_hints = ["Custom hint 1", "Custom hint 2"]
      merged = Hints.merge_hints(user_hints, :rate_limited, retry_after: 500)

      assert Enum.at(merged, 0) == "Custom hint 1"
      assert Enum.at(merged, 1) == "Custom hint 2"
      # Auto hints come after
      assert "Wait 500ms before retrying" in merged
    end

    test "empty user hints returns only auto hints" do
      merged = Hints.merge_hints([], :insufficient_balance, [])

      assert "Check account balance" in merged
    end

    test "merges with unknown type returns only user hints" do
      user_hints = ["My hint"]
      merged = Hints.merge_hints(user_hints, :unknown_type, [])

      assert merged == ["My hint"]
    end
  end

  # Dynamically find an available spec for testing
  @spec_path ExchangeHelper.first_available_spec_path()

  if @spec_path do
    @exchange_id ExchangeHelper.exchange_id_from_path(@spec_path)

    setup_all do
      spec = Spec.load!(@spec_path)
      {:ok, spec: spec, exchange_id: @exchange_id}
    end

    describe "for_endpoint/2" do
      test "returns hints for fetch_balance when spec has account types", %{spec: spec} do
        hints = Hints.for_endpoint(spec, :fetch_balance)

        # Behavior depends on whether this exchange has account_types configured
        if spec.options[:accounts_by_type] && Map.has_key?(spec.options[:accounts_by_type], "unified") do
          assert hints != []
          assert Enum.any?(hints, &String.contains?(&1, "accountType"))
        else
          # Exchange may not have account type requirements
          assert is_list(hints)
        end
      end

      test "returns list for fetch_positions", %{spec: spec} do
        hints = Hints.for_endpoint(spec, :fetch_positions)
        assert is_list(hints)
      end

      test "returns list for fetch_funding_rate", %{spec: spec} do
        hints = Hints.for_endpoint(spec, :fetch_funding_rate)
        assert is_list(hints)
      end

      test "returns list for fetch_ticker", %{spec: spec} do
        hints = Hints.for_endpoint(spec, :fetch_ticker)
        assert is_list(hints)
      end
    end

    describe "for_invalid_params/3" do
      test "returns same hints as for_endpoint", %{spec: spec} do
        endpoint_hints = Hints.for_endpoint(spec, :fetch_balance)
        error_hints = Hints.for_invalid_params(spec, :fetch_balance, "Invalid params")

        assert endpoint_hints == error_hints
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

  describe "with spec without special options" do
    setup do
      spec = %Spec{
        id: "test_exchange",
        name: "Test Exchange",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [],
        has: %{},
        options: %{}
      }

      {:ok, spec: spec}
    end

    test "returns empty hints for fetch_balance", %{spec: spec} do
      hints = Hints.for_endpoint(spec, :fetch_balance)

      assert hints == []
    end

    test "returns empty hints for fetch_positions", %{spec: spec} do
      hints = Hints.for_endpoint(spec, :fetch_positions)

      assert hints == []
    end
  end

  describe "with param_mappings" do
    setup do
      spec = %Spec{
        id: "test_exchange",
        name: "Test Exchange",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [],
        has: %{},
        options: %{},
        param_mappings: %{
          "symbol" => "instId",
          "orderId" => "ordId"
        }
      }

      {:ok, spec: spec}
    end

    test "includes param mapping hints", %{spec: spec} do
      hints = Hints.for_endpoint(spec, :fetch_order)

      assert Enum.any?(hints, &String.contains?(&1, "instId"))
      assert Enum.any?(hints, &String.contains?(&1, "ordId"))
    end
  end
end
