defmodule CCXT.Error.RecoverabilityTest do
  @moduledoc """
  Tests for error recoverability classification.
  """
  use ExUnit.Case, async: true

  alias CCXT.Error.Recoverability

  describe "for_type/1" do
    test "classifies rate_limited as recoverable" do
      assert Recoverability.for_type(:rate_limited) == true
    end

    test "classifies network_error as recoverable" do
      assert Recoverability.for_type(:network_error) == true
    end

    test "classifies market_closed as recoverable" do
      assert Recoverability.for_type(:market_closed) == true
    end

    test "classifies insufficient_balance as non-recoverable" do
      assert Recoverability.for_type(:insufficient_balance) == false
    end

    test "classifies invalid_credentials as non-recoverable" do
      assert Recoverability.for_type(:invalid_credentials) == false
    end

    test "classifies invalid_parameters as non-recoverable" do
      assert Recoverability.for_type(:invalid_parameters) == false
    end

    test "classifies invalid_order as non-recoverable" do
      assert Recoverability.for_type(:invalid_order) == false
    end

    test "classifies order_not_found as non-recoverable" do
      assert Recoverability.for_type(:order_not_found) == false
    end

    test "classifies access_restricted as non-recoverable" do
      assert Recoverability.for_type(:access_restricted) == false
    end

    test "classifies not_supported as non-recoverable" do
      assert Recoverability.for_type(:not_supported) == false
    end

    test "classifies exchange_error as nil (unknown)" do
      assert Recoverability.for_type(:exchange_error) == nil
    end

    test "classifies unknown types as nil" do
      assert Recoverability.for_type(:some_unknown_error) == nil
    end
  end

  describe "recoverable_types/0" do
    test "returns list of recoverable error types" do
      types = Recoverability.recoverable_types()
      assert is_list(types)
      assert :rate_limited in types
      assert :network_error in types
      assert :market_closed in types
    end
  end

  describe "non_recoverable_types/0" do
    test "returns list of non-recoverable error types" do
      types = Recoverability.non_recoverable_types()
      assert is_list(types)
      assert :insufficient_balance in types
      assert :invalid_credentials in types
      assert :invalid_parameters in types
    end
  end

  describe "recoverable?/1" do
    test "returns true for recoverable types" do
      assert Recoverability.recoverable?(:rate_limited) == true
      assert Recoverability.recoverable?(:network_error) == true
    end

    test "returns false for non-recoverable types" do
      assert Recoverability.recoverable?(:invalid_credentials) == false
      assert Recoverability.recoverable?(:insufficient_balance) == false
    end

    test "returns false for unknown types" do
      assert Recoverability.recoverable?(:exchange_error) == false
      assert Recoverability.recoverable?(:unknown) == false
    end
  end
end
