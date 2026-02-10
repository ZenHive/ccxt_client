defmodule CCXT.Generator.ConfigSelectionTest do
  use ExUnit.Case, async: true

  alias CCXT.Exchange.Discovery
  alias CCXT.Generator

  describe "exchange_enabled?/2" do
    test "returns true for :all config" do
      assert Generator.exchange_enabled?("bybit", :all)
      assert Generator.exchange_enabled?("anything", :all)
    end

    test "returns true when spec_id is in string list" do
      assert Generator.exchange_enabled?("bybit", ["bybit", "binance"])
    end

    test "returns false when spec_id is not in string list" do
      refute Generator.exchange_enabled?("kraken", ["bybit", "binance"])
    end

    test "accepts atom lists and matches against string spec_id" do
      assert Generator.exchange_enabled?("bybit", [:bybit, :binance])
      refute Generator.exchange_enabled?("kraken", [:bybit, :binance])
    end

    test "accepts mixed atom and string lists" do
      assert Generator.exchange_enabled?("bybit", [:bybit, "binance"])
      assert Generator.exchange_enabled?("binance", [:bybit, "binance"])
      refute Generator.exchange_enabled?("kraken", [:bybit, "binance"])
    end

    test "returns false for empty list" do
      refute Generator.exchange_enabled?("bybit", [])
    end
  end

  describe "stub modules (disabled exchanges)" do
    test "stub module without __ccxt_spec__ is excluded from Discovery" do
      # A module with just @moduledoc false won't have __ccxt_spec__/0,
      # so Discovery.all_exchanges/0 naturally excludes it
      exchanges = Discovery.all_exchanges()

      for module <- exchanges do
        assert function_exported?(module, :__ccxt_spec__, 0),
               "#{inspect(module)} in all_exchanges() must have __ccxt_spec__/0"
      end
    end
  end
end
