defmodule CCXT.Test.WSIntegrationGeneratorTest do
  @moduledoc """
  Unit tests for WSIntegrationGenerator Config and compile-time sandbox filtering.

  Verifies that Config.build/2 correctly detects has_ws_sandbox for exchanges,
  which gates whether the macro emits a full test module or a no-op tagged module.
  """
  use ExUnit.Case, async: true

  alias CCXT.Test.WSIntegrationGenerator.Config

  describe "Config.build/2 — has_ws_sandbox detection" do
    # Tier 1 exchanges with sandbox
    test "Binance has WS sandbox" do
      config = Config.build(:binance, [])
      assert config.has_ws_sandbox
    end

    test "Bybit has WS sandbox" do
      config = Config.build(:bybit, [])
      assert config.has_ws_sandbox
    end

    test "OKX has WS sandbox" do
      config = Config.build(:okx, [])
      assert config.has_ws_sandbox
    end

    test "Deribit has WS sandbox" do
      config = Config.build(:deribit, [])
      assert config.has_ws_sandbox
    end

    # Tier 2 exchanges without sandbox
    test "Gate has no WS sandbox" do
      config = Config.build(:gate, [])
      refute config.has_ws_sandbox
    end

    test "Kraken has no WS sandbox" do
      config = Config.build(:kraken, [])
      refute config.has_ws_sandbox
    end

    test "HTX has no WS sandbox" do
      config = Config.build(:htx, [])
      refute config.has_ws_sandbox
    end

    test "KuCoin has no WS sandbox" do
      config = Config.build(:kucoin, [])
      refute config.has_ws_sandbox
    end
  end

  describe "Config.build/2 — module derivation" do
    test "derives correct module names for exchange" do
      config = Config.build(:bybit, [])
      assert config.rest_module == CCXT.Bybit
      assert config.ws_module == CCXT.Bybit.WS
      assert config.adapter_module == CCXT.Bybit.WS.Adapter
    end

    test "derives correct exchange tag" do
      config = Config.build(:binance, [])
      assert config.exchange_tag == :exchange_binance
    end
  end

  describe "Config.build/2 — watch methods" do
    test "sandbox exchanges include watch methods" do
      config = Config.build(:bybit, [])
      assert is_list(config.watch_methods)
      assert :watch_ticker in config.watch_methods
    end

    test "no-sandbox exchanges still report watch methods" do
      config = Config.build(:gate, [])
      assert is_list(config.watch_methods)
      # Gate has WS support, just no sandbox
      assert config.has_ws_support
    end
  end
end
