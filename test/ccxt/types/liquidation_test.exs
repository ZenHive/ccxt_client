defmodule CCXT.Types.LiquidationTest do
  use ExUnit.Case, async: true

  alias CCXT.Types.Liquidation

  describe "from_map/1" do
    test "normalizes side string to atom" do
      assert Liquidation.from_map(%{side: "buy"}).side == :buy
      assert Liquidation.from_map(%{side: "sell"}).side == :sell
    end

    test "handles nil side" do
      assert Liquidation.from_map(%{side: nil}).side == nil
    end

    test "preserves other fields" do
      map = %{
        symbol: "BTC/USDT",
        price: 50_000.0,
        contracts: 0.5,
        side: "sell"
      }

      liq = Liquidation.from_map(map)
      assert liq.symbol == "BTC/USDT"
      assert liq.price == 50_000.0
      assert liq.contracts == 0.5
    end
  end
end
