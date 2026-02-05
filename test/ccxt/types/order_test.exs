defmodule CCXT.Types.OrderTest do
  use ExUnit.Case, async: true

  alias CCXT.Types.Order

  describe "from_map/1" do
    test "creates order from map" do
      map = %{
        id: "12345",
        symbol: "BTC/USDT",
        type: "limit",
        side: "buy",
        price: 50_000.0,
        amount: 0.1,
        filled: 0.05,
        remaining: 0.05,
        status: "open"
      }

      order = Order.from_map(map)

      assert order.id == "12345"
      assert order.symbol == "BTC/USDT"
      assert order.type == :limit
      assert order.side == :buy
      assert order.price == 50_000.0
      assert order.amount == 0.1
      assert order.filled == 0.05
      assert order.status == :open
    end

    test "parses fee correctly" do
      map = %{
        id: "123",
        symbol: "BTC/USDT",
        fee: %{currency: "USDT", cost: 1.5, rate: 0.001}
      }

      order = Order.from_map(map)

      assert order.fee == %{currency: "USDT", cost: 1.5, rate: 0.001}
    end

    test "handles cancelled spelling variants" do
      assert Order.from_map(%{status: "canceled"}).status == :canceled
      assert Order.from_map(%{status: "cancelled"}).status == :canceled
    end
  end

  describe "open?/1" do
    test "returns true for open orders" do
      assert Order.open?(%Order{status: :open})
    end

    test "returns false for closed orders" do
      refute Order.open?(%Order{status: :closed})
    end
  end

  describe "filled?/1" do
    test "returns true for closed orders" do
      assert Order.filled?(%Order{status: :closed})
    end

    test "returns false for open orders" do
      refute Order.filled?(%Order{status: :open})
    end
  end

  describe "fill_percentage/1" do
    test "calculates fill percentage" do
      order = %Order{amount: 1.0, filled: 0.5}
      assert Order.fill_percentage(order) == 50.0
    end

    test "returns 0 for zero amount" do
      order = %Order{amount: 0, filled: 0}
      assert Order.fill_percentage(order) == 0.0
    end
  end
end
