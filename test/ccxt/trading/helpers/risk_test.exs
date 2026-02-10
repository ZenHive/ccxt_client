defmodule CCXT.Trading.Helpers.RiskTest do
  use ExUnit.Case, async: true

  alias CCXT.Trading.Helpers.Risk
  alias CCXT.Types.Position

  describe "margin_headroom/1" do
    test "calculates headroom as percentage of mark price" do
      position = %Position{mark_price: 50_000.0, liquidation_price: 40_000.0}
      assert Risk.margin_headroom(position) == 0.2
    end

    test "handles short position (liquidation above mark)" do
      position = %Position{mark_price: 50_000.0, liquidation_price: 60_000.0}
      assert Risk.margin_headroom(position) == 0.2
    end

    test "returns nil when mark_price is nil" do
      position = %Position{mark_price: nil, liquidation_price: 40_000.0}
      assert Risk.margin_headroom(position) == nil
    end

    test "returns nil when liquidation_price is nil" do
      position = %Position{mark_price: 50_000.0, liquidation_price: nil}
      assert Risk.margin_headroom(position) == nil
    end

    test "returns nil when both prices are nil" do
      position = %Position{mark_price: nil, liquidation_price: nil}
      assert Risk.margin_headroom(position) == nil
    end

    test "returns nil when mark_price is zero" do
      position = %Position{mark_price: 0.0, liquidation_price: 40_000.0}
      assert Risk.margin_headroom(position) == nil
    end
  end

  describe "liquidation_distance/1" do
    test "calculates absolute price distance" do
      position = %Position{mark_price: 50_000.0, liquidation_price: 40_000.0}
      assert Risk.liquidation_distance(position) == 10_000.0
    end

    test "handles short position (liquidation above mark)" do
      position = %Position{mark_price: 50_000.0, liquidation_price: 60_000.0}
      assert Risk.liquidation_distance(position) == 10_000.0
    end

    test "returns nil when mark_price is nil" do
      position = %Position{mark_price: nil, liquidation_price: 40_000.0}
      assert Risk.liquidation_distance(position) == nil
    end

    test "returns nil when liquidation_price is nil" do
      position = %Position{mark_price: 50_000.0, liquidation_price: nil}
      assert Risk.liquidation_distance(position) == nil
    end

    test "returns zero when prices are equal" do
      position = %Position{mark_price: 50_000.0, liquidation_price: 50_000.0}
      assert Risk.liquidation_distance(position) == 0.0
    end
  end
end
