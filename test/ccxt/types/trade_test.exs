defmodule CCXT.Types.TradeTest do
  use ExUnit.Case, async: true

  alias CCXT.Types.Trade

  describe "from_map/1" do
    test "creates trade from map" do
      map = %{
        id: "t123",
        order_id: "o456",
        symbol: "BTC/USDT",
        side: "buy",
        price: 50_000.0,
        amount: 0.1,
        taker_or_maker: "taker"
      }

      trade = Trade.from_map(map)

      assert trade.id == "t123"
      assert trade.order_id == "o456"
      assert trade.symbol == "BTC/USDT"
      assert trade.side == :buy
      assert trade.price == 50_000.0
      assert trade.amount == 0.1
      assert trade.taker_or_maker == :taker
    end

    test "calculates cost when not provided" do
      map = %{price: 100.0, amount: 2.0}
      trade = Trade.from_map(map)
      assert trade.cost == 200.0
    end

    test "uses provided cost over calculated" do
      map = %{price: 100.0, amount: 2.0, cost: 199.5}
      trade = Trade.from_map(map)
      assert trade.cost == 199.5
    end

    test "handles camelCase order_id" do
      map = %{orderId: "order123"}
      trade = Trade.from_map(map)
      assert trade.order_id == "order123"
    end

    test "parses fee correctly" do
      map = %{fee: %{"currency" => "BTC", "cost" => 0.0001}}
      trade = Trade.from_map(map)
      assert trade.fee.currency == "BTC"
      assert trade.fee.cost == 0.0001
    end
  end
end
