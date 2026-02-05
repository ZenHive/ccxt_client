defmodule CCXT.Types.PositionTest do
  use ExUnit.Case, async: true

  alias CCXT.Types.Position

  describe "from_map/1" do
    test "creates position from map" do
      map = %{
        symbol: "BTC/USDT:USDT",
        side: "long",
        contracts: 10.0,
        entry_price: 50_000.0,
        leverage: 5.0,
        unrealized_pnl: 1000.0
      }

      position = Position.from_map(map)

      assert position.symbol == "BTC/USDT:USDT"
      assert position.side == :long
      assert position.contracts == 10.0
      assert position.entry_price == 50_000.0
      assert position.leverage == 5.0
      assert position.unrealized_pnl == 1000.0
    end

    test "handles camelCase fields" do
      map = %{
        entryPrice: 50_000.0,
        markPrice: 51_000.0,
        liquidationPrice: 40_000.0,
        unrealizedPnl: 500.0,
        marginMode: "isolated"
      }

      position = Position.from_map(map)

      assert position.entry_price == 50_000.0
      assert position.mark_price == 51_000.0
      assert position.liquidation_price == 40_000.0
      assert position.unrealized_pnl == 500.0
      assert position.margin_mode == :isolated
    end

    test "converts buy/sell to long/short" do
      assert Position.from_map(%{side: "buy"}).side == :long
      assert Position.from_map(%{side: "sell"}).side == :short
    end
  end

  describe "long?/1" do
    test "returns true for long positions" do
      assert Position.long?(%Position{side: :long})
    end

    test "returns false for short positions" do
      refute Position.long?(%Position{side: :short})
    end
  end

  describe "short?/1" do
    test "returns true for short positions" do
      assert Position.short?(%Position{side: :short})
    end

    test "returns false for long positions" do
      refute Position.short?(%Position{side: :long})
    end
  end

  describe "profitable?/1" do
    test "returns true when unrealized_pnl is positive" do
      assert Position.profitable?(%Position{unrealized_pnl: 100.0})
    end

    test "returns false when unrealized_pnl is negative" do
      refute Position.profitable?(%Position{unrealized_pnl: -100.0})
    end

    test "returns false when unrealized_pnl is zero" do
      refute Position.profitable?(%Position{unrealized_pnl: 0.0})
    end

    test "returns false when unrealized_pnl is nil" do
      refute Position.profitable?(%Position{unrealized_pnl: nil})
    end
  end
end
