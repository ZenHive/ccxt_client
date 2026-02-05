defmodule CCXT.Types.TickerTest do
  use ExUnit.Case, async: true

  alias CCXT.Types.Ticker

  describe "from_map/1" do
    test "creates ticker from atom-keyed map" do
      map = %{
        symbol: "BTC/USDT",
        last: 50_000.0,
        bid: 49_999.0,
        ask: 50_001.0,
        high: 51_000.0,
        low: 49_000.0,
        base_volume: 1000.0
      }

      ticker = Ticker.from_map(map)

      assert ticker.symbol == "BTC/USDT"
      assert ticker.last == 50_000.0
      assert ticker.bid == 49_999.0
      assert ticker.ask == 50_001.0
      assert ticker.raw == map
    end

    test "creates ticker from string-keyed map" do
      map = %{
        "symbol" => "ETH/USDT",
        "last" => 3000.0,
        "baseVolume" => 500.0
      }

      ticker = Ticker.from_map(map)

      assert ticker.symbol == "ETH/USDT"
      assert ticker.last == 3000.0
      assert ticker.base_volume == 500.0
    end

    test "handles camelCase volume fields" do
      map = %{
        symbol: "BTC/USDT",
        bidVolume: 10.0,
        askVolume: 20.0,
        quoteVolume: 50_000_000.0
      }

      ticker = Ticker.from_map(map)

      assert ticker.bid_volume == 10.0
      assert ticker.ask_volume == 20.0
      assert ticker.quote_volume == 50_000_000.0
    end
  end
end
