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

    test "coerces string levels to floats" do
      map = %{
        symbol: "BTC/USDT",
        bids: [["50000.5", "1.0"], ["49999.0", "2.5"]],
        asks: [["50001.0", "0.5"]]
      }

      book = OrderBook.from_map(map)

      assert book.bids == [[50_000.5, 1.0], [49_999.0, 2.5]]
      assert book.asks == [[50_001.0, 0.5]]
    end

    test "passes through already-float levels unchanged" do
      map = %{
        symbol: "BTC/USDT",
        bids: [[50_000.0, 1.0]],
        asks: [[50_001.0, 0.5]]
      }

      book = OrderBook.from_map(map)

      assert book.bids == [[50_000.0, 1.0]]
      assert book.asks == [[50_001.0, 0.5]]
    end

    test "coerces mixed string/float levels" do
      map = %{
        symbol: "BTC/USDT",
        bids: [["50000.5", 1.0], [49_999.0, "2.5"]],
        asks: []
      }

      book = OrderBook.from_map(map)

      assert book.bids == [[50_000.5, 1.0], [49_999.0, 2.5]]
    end

    test "raw field uses info key when available" do
      original = %{"price" => "50000", "qty" => "1.0"}

      map = %{
        "symbol" => "BTC/USDT",
        "bids" => [],
        "asks" => [],
        "info" => original
      }

      book = OrderBook.from_map(map)

      assert book.raw == original
    end

    test "raw field falls back to full map when no info key" do
      map = %{
        symbol: "BTC/USDT",
        bids: [[50_000.0, 1.0]],
        asks: []
      }

      book = OrderBook.from_map(map)

      assert book.raw == map
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

  describe "helpers work after string coercion" do
    test "best_bid/best_ask/spread work with originally-string levels" do
      map = %{
        symbol: "BTC/USDT",
        bids: [["50000.0", "1.0"]],
        asks: [["50010.0", "0.5"]]
      }

      book = OrderBook.from_map(map)

      assert OrderBook.best_bid(book) == 50_000.0
      assert OrderBook.best_ask(book) == 50_010.0
      assert OrderBook.spread(book) == 10.0
    end
  end
end
