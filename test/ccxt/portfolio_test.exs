defmodule CCXT.PortfolioTest do
  use ExUnit.Case, async: true

  alias CCXT.Portfolio
  alias CCXT.Types.Position

  describe "total_exposure/1" do
    test "groups and sums notional by base asset" do
      positions = [
        %Position{symbol: "BTC/USDT:USDT", notional: 50_000.0},
        %Position{symbol: "BTC/USDT:USDT", notional: 25_000.0},
        %Position{symbol: "ETH/USDT:USDT", notional: 10_000.0}
      ]

      result = Portfolio.total_exposure(positions)

      assert result == %{"BTC" => 75_000.0, "ETH" => 10_000.0}
    end

    test "handles spot symbols (no settle currency)" do
      positions = [
        %Position{symbol: "BTC/USDT", notional: 50_000.0},
        %Position{symbol: "ETH/USD", notional: 10_000.0}
      ]

      result = Portfolio.total_exposure(positions)

      assert result == %{"BTC" => 50_000.0, "ETH" => 10_000.0}
    end

    test "skips positions with nil notional" do
      positions = [
        %Position{symbol: "BTC/USDT", notional: 50_000.0},
        %Position{symbol: "BTC/USDT", notional: nil},
        %Position{symbol: "ETH/USDT", notional: 10_000.0}
      ]

      result = Portfolio.total_exposure(positions)

      assert result == %{"BTC" => 50_000.0, "ETH" => 10_000.0}
    end

    test "returns empty map for empty list" do
      assert Portfolio.total_exposure([]) == %{}
    end

    test "returns empty map when all notionals are nil" do
      positions = [
        %Position{symbol: "BTC/USDT", notional: nil},
        %Position{symbol: "ETH/USDT", notional: nil}
      ]

      assert Portfolio.total_exposure(positions) == %{}
    end

    test "skips positions with nil symbol" do
      positions = [
        %Position{symbol: "BTC/USDT", notional: 50_000.0},
        %Position{symbol: nil, notional: 25_000.0}
      ]

      assert Portfolio.total_exposure(positions) == %{"BTC" => 50_000.0}
    end

    test "skips positions with invalid symbol format" do
      positions = [
        %Position{symbol: "BTC/USDT", notional: 50_000.0},
        %Position{symbol: "INVALID", notional: 25_000.0},
        %Position{symbol: "", notional: 10_000.0}
      ]

      assert Portfolio.total_exposure(positions) == %{"BTC" => 50_000.0}
    end
  end

  describe "unrealized_pnl/1" do
    test "sums unrealized PnL across positions" do
      positions = [
        %Position{unrealized_pnl: 1000.0},
        %Position{unrealized_pnl: -500.0},
        %Position{unrealized_pnl: 200.0}
      ]

      assert Portfolio.unrealized_pnl(positions) == 700.0
    end

    test "skips positions with nil unrealized_pnl" do
      positions = [
        %Position{unrealized_pnl: 1000.0},
        %Position{unrealized_pnl: nil},
        %Position{unrealized_pnl: -500.0}
      ]

      assert Portfolio.unrealized_pnl(positions) == 500.0
    end

    test "returns 0.0 for empty list" do
      assert Portfolio.unrealized_pnl([]) == 0.0
    end

    test "returns 0.0 when all unrealized_pnl are nil" do
      positions = [
        %Position{unrealized_pnl: nil},
        %Position{unrealized_pnl: nil}
      ]

      assert Portfolio.unrealized_pnl(positions) == 0.0
    end

    test "handles negative total" do
      positions = [
        %Position{unrealized_pnl: -1000.0},
        %Position{unrealized_pnl: -500.0}
      ]

      assert Portfolio.unrealized_pnl(positions) == -1500.0
    end
  end

  describe "realized_pnl/1" do
    test "sums realized PnL across positions" do
      positions = [
        %Position{realized_pnl: 500.0},
        %Position{realized_pnl: -100.0}
      ]

      assert Portfolio.realized_pnl(positions) == 400.0
    end

    test "skips positions with nil realized_pnl" do
      positions = [
        %Position{realized_pnl: 500.0},
        %Position{realized_pnl: nil}
      ]

      assert Portfolio.realized_pnl(positions) == 500.0
    end

    test "returns 0.0 for empty list" do
      assert Portfolio.realized_pnl([]) == 0.0
    end
  end
end
