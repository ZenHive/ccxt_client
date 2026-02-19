defmodule CCXT.Test.WSChannelConfigTest do
  use ExUnit.Case, async: true

  alias CCXT.Test.WSChannelConfig

  describe "get/2" do
    test "returns override for configured exchange and channel (binance trades)" do
      override = WSChannelConfig.get("binance", :trades)
      assert %{url_path: [:future]} = override
    end

    test "returns override for binance orderbook" do
      override = WSChannelConfig.get("binance", :orderbook)
      assert %{url_path: [:future]} = override
    end

    test "returns nil for unconfigured channel" do
      assert is_nil(WSChannelConfig.get("binance", :ticker))
    end

    test "returns nil for unconfigured exchange" do
      assert is_nil(WSChannelConfig.get("bybit", :trades))
    end

    test "accepts both atom and string exchange IDs" do
      string_result = WSChannelConfig.get("binance", :trades)
      atom_result = WSChannelConfig.get(:binance, :trades)
      assert string_result == atom_result
      assert %{url_path: [:future]} = string_result
    end
  end

  describe "all/0" do
    test "returns map with expected keys" do
      overrides = WSChannelConfig.all()
      assert is_map(overrides)
      assert Map.has_key?(overrides, {"binance", :trades})
      assert Map.has_key?(overrides, {"binance", :orderbook})
    end
  end

  describe "resolve_url_path/3" do
    test "returns override path when configured" do
      assert [:future] = WSChannelConfig.resolve_url_path("binance", :trades, [:spot])
    end

    test "returns default when no override" do
      assert [:spot] = WSChannelConfig.resolve_url_path("binance", :ticker, [:spot])
    end
  end

  describe "resolve_symbol/3" do
    test "returns default when no symbol override" do
      assert "BTC/USDT" = WSChannelConfig.resolve_symbol("binance", :trades, "BTC/USDT")
    end
  end

  describe "resolve_timeout/3" do
    test "returns default when no timeout override" do
      assert 60_000 = WSChannelConfig.resolve_timeout("binance", :trades, 60_000)
    end
  end
end
