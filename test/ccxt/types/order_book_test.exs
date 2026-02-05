defmodule CCXT.Types.OrderBookTest do
  use ExUnit.Case, async: true

  alias CCXT.Types.OrderBook

  describe "from_map/1" do
    test "creates order book from map" do
      map = %{
        symbol: "BTC/USDT",
        bids: [[50_000.0, 1.0], [49_999.0, 2.0]],
        asks: [[50_001.0, 0.5], [50_002.0, 1.5]],
        timestamp: 1_234_567_890
      }

      book = OrderBook.from_map(map)

      assert book.symbol == "BTC/USDT"
      assert book.bids == [[50_000.0, 1.0], [49_999.0, 2.0]]
      assert book.asks == [[50_001.0, 0.5], [50_002.0, 1.5]]
      assert book.raw == map
    end

    test "defaults to empty lists" do
      book = OrderBook.from_map(%{symbol: "ETH/USDT"})

      assert book.bids == []
      assert book.asks == []
    end
  end

  describe "best_bid/1" do
    test "returns best bid price" do
      book = %OrderBook{bids: [[50_000.0, 1.0], [49_999.0, 2.0]], asks: []}
      assert OrderBook.best_bid(book) == 50_000.0
    end

    test "returns nil for empty bids" do
      book = %OrderBook{bids: [], asks: []}
      assert OrderBook.best_bid(book) == nil
    end
  end

  describe "best_ask/1" do
    test "returns best ask price" do
      book = %OrderBook{bids: [], asks: [[50_001.0, 0.5]]}
      assert OrderBook.best_ask(book) == 50_001.0
    end

    test "returns nil for empty asks" do
      book = %OrderBook{bids: [], asks: []}
      assert OrderBook.best_ask(book) == nil
    end
  end

  describe "spread/1" do
    test "calculates spread" do
      book = %OrderBook{
        bids: [[50_000.0, 1.0]],
        asks: [[50_010.0, 0.5]]
      }

      assert OrderBook.spread(book) == 10.0
    end

    test "returns nil when bids empty" do
      book = %OrderBook{bids: [], asks: [[50_001.0, 0.5]]}
      assert OrderBook.spread(book) == nil
    end
  end
end
