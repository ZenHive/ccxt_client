defmodule CCXT.Types.LeverageTest do
  use ExUnit.Case, async: true

  alias CCXT.Types.Leverage

  describe "from_map/1" do
    test "normalizes margin_mode string to atom" do
      assert Leverage.from_map(%{marginMode: "cross"}).margin_mode == :cross
      assert Leverage.from_map(%{marginMode: "isolated"}).margin_mode == :isolated
    end

    test "handles nil margin_mode" do
      assert Leverage.from_map(%{marginMode: nil}).margin_mode == nil
    end

    test "preserves other fields" do
      map = %{
        symbol: "BTC/USDT",
        longLeverage: 10,
        marginMode: "cross"
      }

      lev = Leverage.from_map(map)
      assert lev.symbol == "BTC/USDT"
      assert lev.long_leverage == 10
    end
  end
end
