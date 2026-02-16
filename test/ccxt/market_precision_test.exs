defmodule CCXT.MarketPrecisionTest do
  @moduledoc """
  Tests for CCXT.MarketPrecision — normalizes precision metadata across modes.
  """
  use ExUnit.Case, async: true

  alias CCXT.MarketPrecision

  @precision_mode_tick_size 4
  @precision_mode_decimals 0
  @precision_mode_significant_digits 1

  describe "from_market/2 with TICK_SIZE mode" do
    test "converts tick size to decimal places" do
      market = %{
        "symbol" => "BTC/USDT",
        "precision" => %{"amount" => 0.01, "price" => 0.05},
        "limits" => %{
          "price" => %{"min" => 0.05},
          "amount" => %{"min" => 0.001},
          "cost" => %{"min" => 10.0}
        }
      }

      mp = MarketPrecision.from_market(market, @precision_mode_tick_size)

      assert %MarketPrecision{} = mp
      assert mp.symbol == "BTC/USDT"
      assert mp.precision_mode == @precision_mode_tick_size
      assert mp.price_increment == 0.05
      assert mp.price_precision == 2
      assert mp.amount_increment == 0.01
      assert mp.amount_precision == 2
      assert mp.price_min == 0.05
      assert mp.amount_min == 0.001
      assert mp.cost_min == 10.0
    end

    test "handles fine-grained tick sizes" do
      market = %{
        "symbol" => "ETH/USDT",
        "precision" => %{"amount" => 0.001, "price" => 0.0001},
        "limits" => %{}
      }

      mp = MarketPrecision.from_market(market, @precision_mode_tick_size)

      assert mp.price_increment == 0.0001
      assert mp.price_precision == 4
      assert mp.amount_increment == 0.001
      assert mp.amount_precision == 3
    end

    test "handles Bybit swap data" do
      market = %{
        "symbol" => "BTC/USDT:USDT",
        "precision" => %{"amount" => 0.001, "price" => 0.1},
        "limits" => %{
          "amount" => %{"min" => 0.001, "max" => 100.0},
          "price" => %{"min" => 0.5},
          "cost" => %{"min" => 5.0, "max" => 2_000_000.0}
        }
      }

      mp = MarketPrecision.from_market(market, @precision_mode_tick_size)

      assert mp.price_increment == 0.1
      assert mp.price_precision == 1
      assert mp.amount_max == 100.0
      assert mp.cost_max == 2_000_000.0
    end
  end

  describe "from_market/2 with DECIMALS mode" do
    test "converts decimal places to tick size" do
      market = %{
        "symbol" => "BTC/USDT",
        "precision" => %{"amount" => 3, "price" => 2},
        "limits" => %{}
      }

      mp = MarketPrecision.from_market(market, @precision_mode_decimals)

      assert mp.precision_mode == @precision_mode_decimals
      assert mp.price_increment == 0.01
      assert mp.price_precision == 2
      assert mp.amount_increment == 0.001
      assert mp.amount_precision == 3
    end

    test "handles zero decimal places" do
      market = %{
        "symbol" => "BTC/JPY",
        "precision" => %{"amount" => 4, "price" => 0},
        "limits" => %{}
      }

      mp = MarketPrecision.from_market(market, @precision_mode_decimals)

      assert mp.price_increment == 1.0
      assert mp.price_precision == 0
    end
  end

  describe "from_market/2 with SIGNIFICANT_DIGITS mode" do
    test "returns error tuple" do
      market = %{
        "symbol" => "BTC/USDT",
        "precision" => %{"price" => 5},
        "limits" => %{}
      }

      assert {:error, :unsupported_precision_mode} =
               MarketPrecision.from_market(market, @precision_mode_significant_digits)
    end
  end

  describe "from_market/2 with nil precision" do
    test "returns nil fields for missing precision" do
      market = %{
        "symbol" => "BTC/USDT",
        "precision" => nil,
        "limits" => nil
      }

      mp = MarketPrecision.from_market(market, @precision_mode_tick_size)

      assert mp.symbol == "BTC/USDT"
      assert mp.price_increment == nil
      assert mp.price_precision == nil
      assert mp.amount_increment == nil
      assert mp.amount_precision == nil
      assert mp.price_min == nil
      assert mp.price_max == nil
    end

    test "returns nil fields for missing precision fields" do
      market = %{
        "symbol" => "BTC/USDT",
        "precision" => %{},
        "limits" => %{}
      }

      mp = MarketPrecision.from_market(market, @precision_mode_tick_size)

      assert mp.price_increment == nil
      assert mp.price_precision == nil
    end
  end

  describe "from_market/2 with struct input" do
    test "handles MarketInterface struct" do
      market = %CCXT.Types.MarketInterface{
        symbol: "BTC/USDT",
        precision: %{"amount" => 0.01, "price" => 0.05},
        limits: %{"price" => %{"min" => 0.05}, "amount" => %{"min" => 0.01}}
      }

      mp = MarketPrecision.from_market(market, @precision_mode_tick_size)

      assert mp.symbol == "BTC/USDT"
      assert mp.price_increment == 0.05
      assert mp.price_precision == 2
      assert mp.price_min == 0.05
      assert mp.amount_min == 0.01
    end
  end

  describe "from_markets/2" do
    test "builds symbol-keyed map" do
      markets = [
        %{
          "symbol" => "BTC/USDT",
          "precision" => %{"price" => 0.01, "amount" => 0.001},
          "limits" => %{}
        },
        %{
          "symbol" => "ETH/USDT",
          "precision" => %{"price" => 0.05, "amount" => 0.01},
          "limits" => %{}
        }
      ]

      result = MarketPrecision.from_markets(markets, @precision_mode_tick_size)

      assert is_map(result)
      assert map_size(result) == 2
      assert %MarketPrecision{price_precision: 2} = result["BTC/USDT"]
      assert %MarketPrecision{price_precision: 2} = result["ETH/USDT"]
    end

    test "returns error for SIGNIFICANT_DIGITS mode" do
      assert {:error, :unsupported_precision_mode} =
               MarketPrecision.from_markets([], @precision_mode_significant_digits)
    end
  end

  describe "tradingview_price_format/1" do
    test "returns TradingView-compatible format" do
      mp = %MarketPrecision{
        symbol: "BTC/USDT",
        price_increment: 0.01,
        price_precision: 2
      }

      result = MarketPrecision.tradingview_price_format(mp)

      assert result == %{type: "price", precision: 2, minMove: 0.01}
    end

    test "handles nil values" do
      mp = %MarketPrecision{symbol: "BTC/USDT"}

      result = MarketPrecision.tradingview_price_format(mp)

      assert result == %{type: "price", precision: nil, minMove: nil}
    end
  end

  describe "decimal_places/1" do
    test "standard tick sizes" do
      assert MarketPrecision.decimal_places(0.01) == 2
      assert MarketPrecision.decimal_places(0.001) == 3
      assert MarketPrecision.decimal_places(0.0001) == 4
    end

    test "non-standard tick sizes" do
      assert MarketPrecision.decimal_places(0.05) == 2
      assert MarketPrecision.decimal_places(0.25) == 2
      assert MarketPrecision.decimal_places(0.5) == 1
    end

    test "whole number" do
      assert MarketPrecision.decimal_places(1.0) == 0
    end

    test "very small tick size" do
      assert MarketPrecision.decimal_places(1.0e-8) == 8
    end

    test "nil returns nil" do
      assert MarketPrecision.decimal_places(nil) == nil
    end
  end

  describe "increment_from_decimals/1" do
    test "standard decimal counts" do
      assert MarketPrecision.increment_from_decimals(0) == 1.0
      assert MarketPrecision.increment_from_decimals(1) == 0.1
      assert MarketPrecision.increment_from_decimals(2) == 0.01
      assert MarketPrecision.increment_from_decimals(4) == 0.0001
    end

    test "nil returns nil" do
      assert MarketPrecision.increment_from_decimals(nil) == nil
    end
  end
end
