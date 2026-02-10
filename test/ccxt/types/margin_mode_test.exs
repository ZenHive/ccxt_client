defmodule CCXT.Types.MarginModeTest do
  use ExUnit.Case, async: true

  alias CCXT.Types.MarginMode

  describe "from_map/1" do
    test "normalizes margin_mode string to atom" do
      assert MarginMode.from_map(%{marginMode: "cross"}).margin_mode == :cross
      assert MarginMode.from_map(%{marginMode: "isolated"}).margin_mode == :isolated
    end

    test "handles nil margin_mode" do
      assert MarginMode.from_map(%{marginMode: nil}).margin_mode == nil
    end

    test "preserves other fields" do
      map = %{
        symbol: "ETH/USDT",
        marginMode: "isolated"
      }

      mm = MarginMode.from_map(map)
      assert mm.symbol == "ETH/USDT"
    end
  end
end
