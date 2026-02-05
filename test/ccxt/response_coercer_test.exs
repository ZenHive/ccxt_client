defmodule CCXT.ResponseCoercerTest do
  @moduledoc """
  Tests for response type coercion.
  """
  use ExUnit.Case, async: true

  alias CCXT.ResponseCoercer
  alias CCXT.Types.Balance
  alias CCXT.Types.Order
  alias CCXT.Types.OrderBook
  alias CCXT.Types.Position
  alias CCXT.Types.Ticker
  alias CCXT.Types.Trade

  describe "coerce/3 with nil type" do
    test "returns data unchanged" do
      data = %{"symbol" => "BTC/USDT", "last" => 50_000.0}
      assert ResponseCoercer.coerce(data, nil, []) == data
    end
  end

  describe "coerce/3 with raw: true" do
    test "returns data unchanged for ticker type" do
      data = %{"symbol" => "BTC/USDT", "last" => 50_000.0}
      assert ResponseCoercer.coerce(data, :ticker, raw: true) == data
    end

    test "returns data unchanged for order type" do
      data = %{"id" => "123", "symbol" => "BTC/USDT"}
      assert ResponseCoercer.coerce(data, :order, raw: true) == data
    end

    test "returns list unchanged for tickers type" do
      data = [%{"symbol" => "BTC/USDT"}, %{"symbol" => "ETH/USDT"}]
      assert ResponseCoercer.coerce(data, :tickers, raw: true) == data
    end
  end

  describe "coerce/3 for :ticker" do
    test "coerces map to Ticker struct" do
      data = %{
        "symbol" => "BTC/USDT",
        "last" => 50_000.0,
        "bid" => 49_999.0,
        "ask" => 50_001.0,
        "high" => 51_000.0,
        "low" => 49_000.0,
        "open" => 49_500.0,
        "close" => 50_000.0,
        "baseVolume" => 1000.0,
        "quoteVolume" => 50_000_000.0
      }

      result = ResponseCoercer.coerce(data, :ticker, [])

      assert %Ticker{} = result
      assert result.symbol == "BTC/USDT"
      assert result.last == 50_000.0
    end
  end

  describe "coerce/3 for :tickers (list)" do
    test "coerces list of maps to list of Ticker structs" do
      data = [
        %{"symbol" => "BTC/USDT", "last" => 50_000.0},
        %{"symbol" => "ETH/USDT", "last" => 3000.0}
      ]

      result = ResponseCoercer.coerce(data, :tickers, [])

      assert is_list(result)
      assert length(result) == 2
      assert %Ticker{symbol: "BTC/USDT"} = Enum.at(result, 0)
      assert %Ticker{symbol: "ETH/USDT"} = Enum.at(result, 1)
    end
  end

  describe "coerce/3 for :order" do
    test "coerces map to Order struct" do
      data = %{
        "id" => "order123",
        "symbol" => "BTC/USDT",
        "side" => "buy",
        "type" => "limit",
        "amount" => 1.0,
        "price" => 50_000.0,
        "status" => "open"
      }

      result = ResponseCoercer.coerce(data, :order, [])

      assert %Order{} = result
      assert result.id == "order123"
      assert result.symbol == "BTC/USDT"
    end
  end

  describe "coerce/3 for :orders (list)" do
    test "coerces list of maps to list of Order structs" do
      data = [
        %{"id" => "order1", "symbol" => "BTC/USDT"},
        %{"id" => "order2", "symbol" => "ETH/USDT"}
      ]

      result = ResponseCoercer.coerce(data, :orders, [])

      assert is_list(result)
      assert length(result) == 2
      assert %Order{id: "order1"} = Enum.at(result, 0)
      assert %Order{id: "order2"} = Enum.at(result, 1)
    end
  end

  describe "coerce/3 for :position" do
    test "coerces map to Position struct" do
      data = %{
        "symbol" => "BTC/USDT",
        "side" => "long",
        "contracts" => 10.0,
        "notional" => 500_000.0
      }

      result = ResponseCoercer.coerce(data, :position, [])

      assert %Position{} = result
      assert result.symbol == "BTC/USDT"
    end
  end

  describe "coerce/3 for :positions (list)" do
    test "coerces list of maps to list of Position structs" do
      data = [
        %{"symbol" => "BTC/USDT", "side" => "long"},
        %{"symbol" => "ETH/USDT", "side" => "short"}
      ]

      result = ResponseCoercer.coerce(data, :positions, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%Position{}, &1))
    end
  end

  describe "coerce/3 for :balance" do
    test "coerces map to Balance struct" do
      data = %{
        "info" => %{},
        "timestamp" => 1_640_000_000_000,
        "datetime" => "2021-12-20T00:00:00.000Z",
        "free" => %{"BTC" => 1.0, "USDT" => 10_000.0},
        "used" => %{"BTC" => 0.5, "USDT" => 5000.0},
        "total" => %{"BTC" => 1.5, "USDT" => 15_000.0}
      }

      result = ResponseCoercer.coerce(data, :balance, [])

      assert %Balance{} = result
    end
  end

  describe "coerce/3 for :order_book" do
    test "coerces map to OrderBook struct" do
      data = %{
        "symbol" => "BTC/USDT",
        "bids" => [[50_000.0, 1.0], [49_999.0, 2.0]],
        "asks" => [[50_001.0, 1.5], [50_002.0, 0.5]],
        "timestamp" => 1_640_000_000_000,
        "nonce" => 12_345
      }

      result = ResponseCoercer.coerce(data, :order_book, [])

      assert %OrderBook{} = result
      assert result.symbol == "BTC/USDT"
    end
  end

  describe "coerce/3 for :trade" do
    test "coerces map to Trade struct" do
      data = %{
        "id" => "trade123",
        "symbol" => "BTC/USDT",
        "side" => "buy",
        "price" => 50_000.0,
        "amount" => 0.1
      }

      result = ResponseCoercer.coerce(data, :trade, [])

      assert %Trade{} = result
      assert result.id == "trade123"
    end
  end

  describe "coerce/3 for :trades (list)" do
    test "coerces list of maps to list of Trade structs" do
      data = [
        %{"id" => "trade1", "symbol" => "BTC/USDT"},
        %{"id" => "trade2", "symbol" => "BTC/USDT"}
      ]

      result = ResponseCoercer.coerce(data, :trades, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%Trade{}, &1))
    end
  end

  describe "coerce/3 with unexpected data types" do
    test "returns nil unchanged" do
      assert ResponseCoercer.coerce(nil, :ticker, []) == nil
    end

    test "returns string unchanged" do
      assert ResponseCoercer.coerce("unexpected", :ticker, []) == "unexpected"
    end
  end

  describe "infer_response_type/1" do
    test "infers :ticker from :fetch_ticker" do
      assert ResponseCoercer.infer_response_type(:fetch_ticker) == :ticker
    end

    test "infers :tickers from :fetch_tickers" do
      assert ResponseCoercer.infer_response_type(:fetch_tickers) == :tickers
    end

    test "infers :order from :fetch_order" do
      assert ResponseCoercer.infer_response_type(:fetch_order) == :order
    end

    test "infers :orders from :fetch_orders" do
      assert ResponseCoercer.infer_response_type(:fetch_orders) == :orders
    end

    test "infers :orders from :fetch_open_orders" do
      assert ResponseCoercer.infer_response_type(:fetch_open_orders) == :orders
    end

    test "infers :orders from :fetch_closed_orders" do
      assert ResponseCoercer.infer_response_type(:fetch_closed_orders) == :orders
    end

    test "infers :trades from :fetch_trades" do
      assert ResponseCoercer.infer_response_type(:fetch_trades) == :trades
    end

    test "infers :trades from :fetch_my_trades" do
      assert ResponseCoercer.infer_response_type(:fetch_my_trades) == :trades
    end

    test "infers :position from :fetch_position" do
      assert ResponseCoercer.infer_response_type(:fetch_position) == :position
    end

    test "infers :positions from :fetch_positions" do
      assert ResponseCoercer.infer_response_type(:fetch_positions) == :positions
    end

    test "infers :balance from :fetch_balance" do
      assert ResponseCoercer.infer_response_type(:fetch_balance) == :balance
    end

    test "infers :order_book from :fetch_order_book" do
      assert ResponseCoercer.infer_response_type(:fetch_order_book) == :order_book
    end

    test "infers :order from :create_order" do
      assert ResponseCoercer.infer_response_type(:create_order) == :order
    end

    test "infers :order from :cancel_order" do
      assert ResponseCoercer.infer_response_type(:cancel_order) == :order
    end

    test "infers :order from :edit_order" do
      assert ResponseCoercer.infer_response_type(:edit_order) == :order
    end

    test "returns nil for unknown endpoints" do
      assert ResponseCoercer.infer_response_type(:some_custom_endpoint) == nil
      assert ResponseCoercer.infer_response_type(:fetch_unknown) == nil
    end
  end

  describe "type_modules/0" do
    test "returns map of type atoms to modules" do
      modules = ResponseCoercer.type_modules()
      assert is_map(modules)
      assert modules[:ticker] == Ticker
      assert modules[:order] == Order
    end
  end

  describe "list_types/0" do
    test "returns list of plural type atoms" do
      types = ResponseCoercer.list_types()
      assert is_list(types)
      assert :tickers in types
      assert :orders in types
      assert :positions in types
      assert :trades in types
    end
  end
end
