defmodule CCXT.Order.BuilderTest.MockExchange do
  @moduledoc false
  # Mock exchange module for testing submit/3
  def create_order(credentials, symbol, type, side, amount, price, opts) do
    {:ok,
     %{
       credentials: credentials,
       symbol: symbol,
       type: type,
       side: side,
       amount: amount,
       price: price,
       opts: opts
     }}
  end
end

defmodule CCXT.Order.BuilderTest do
  use ExUnit.Case, async: true

  alias CCXT.Order.Builder
  alias CCXT.Order.BuilderTest.MockExchange

  describe "new/3" do
    test "creates a market order builder" do
      builder = Builder.new("BTC/USDT", :buy, 0.1)

      assert builder.symbol == "BTC/USDT"
      assert builder.side == :buy
      assert builder.amount == 0.1
      assert builder.order_type == :market
      assert builder.price == nil
    end

    test "accepts sell side" do
      builder = Builder.new("ETH/USDT", :sell, 1.0)

      assert builder.side == :sell
    end
  end

  describe "limit/2" do
    test "converts to limit order with price" do
      builder =
        "BTC/USDT"
        |> Builder.new(:buy, 0.1)
        |> Builder.limit(50_000.0)

      assert builder.order_type == :limit
      assert builder.price == 50_000.0
    end
  end

  describe "stop_loss/2" do
    test "sets stop-loss price" do
      builder =
        "BTC/USDT"
        |> Builder.new(:buy, 0.1)
        |> Builder.stop_loss(48_000.0)

      assert builder.stop_loss == 48_000.0
    end
  end

  describe "take_profit/2" do
    test "sets take-profit price" do
      builder =
        "BTC/USDT"
        |> Builder.new(:buy, 0.1)
        |> Builder.take_profit(55_000.0)

      assert builder.take_profit == 55_000.0
    end
  end

  describe "client_id/2" do
    test "sets client order ID" do
      builder =
        "BTC/USDT"
        |> Builder.new(:buy, 0.1)
        |> Builder.client_id("my-order-123")

      assert builder.client_order_id == "my-order-123"
    end
  end

  describe "params/2" do
    test "adds extra parameters" do
      builder =
        "BTC/USDT"
        |> Builder.new(:buy, 0.1)
        |> Builder.params(timeInForce: "GTC")

      assert builder.params == [timeInForce: "GTC"]
    end

    test "merges multiple params calls" do
      builder =
        "BTC/USDT"
        |> Builder.new(:buy, 0.1)
        |> Builder.params(timeInForce: "GTC")
        |> Builder.params(reduceOnly: true)

      assert builder.params == [timeInForce: "GTC", reduceOnly: true]
    end

    test "later params override earlier ones" do
      builder =
        "BTC/USDT"
        |> Builder.new(:buy, 0.1)
        |> Builder.params(timeInForce: "GTC")
        |> Builder.params(timeInForce: "IOC")

      assert builder.params == [timeInForce: "IOC"]
    end
  end

  describe "to_map/1" do
    test "returns builder as map" do
      builder =
        "BTC/USDT"
        |> Builder.new(:buy, 0.1)
        |> Builder.limit(50_000.0)
        |> Builder.stop_loss(48_000.0)

      map = Builder.to_map(builder)

      assert map.symbol == "BTC/USDT"
      assert map.side == :buy
      assert map.amount == 0.1
      assert map.order_type == :limit
      assert map.price == 50_000.0
      assert map.stop_loss == 48_000.0
    end
  end

  describe "chaining" do
    test "supports full chain of operations" do
      builder =
        "BTC/USDT"
        |> Builder.new(:buy, 0.1)
        |> Builder.limit(50_000.0)
        |> Builder.stop_loss(48_000.0)
        |> Builder.take_profit(55_000.0)
        |> Builder.client_id("order-001")
        |> Builder.params(timeInForce: "GTC")

      assert builder.symbol == "BTC/USDT"
      assert builder.side == :buy
      assert builder.amount == 0.1
      assert builder.order_type == :limit
      assert builder.price == 50_000.0
      assert builder.stop_loss == 48_000.0
      assert builder.take_profit == 55_000.0
      assert builder.client_order_id == "order-001"
      assert builder.params == [timeInForce: "GTC"]
    end
  end

  describe "submit/3" do
    test "calls exchange module with correct arguments for market order" do
      credentials = %CCXT.Credentials{api_key: "key", secret: "secret"}

      {:ok, result} =
        "BTC/USDT"
        |> Builder.new(:buy, 0.1)
        |> Builder.submit(MockExchange, credentials)

      assert result.credentials == credentials
      assert result.symbol == "BTC/USDT"
      assert result.type == "market"
      assert result.side == "buy"
      assert result.amount == 0.1
      assert result.price == nil
      assert result.opts == []
    end

    test "calls exchange module with correct arguments for limit order" do
      credentials = %CCXT.Credentials{api_key: "key", secret: "secret"}

      {:ok, result} =
        "BTC/USDT"
        |> Builder.new(:buy, 0.1)
        |> Builder.limit(50_000.0)
        |> Builder.submit(MockExchange, credentials)

      assert result.type == "limit"
      assert result.price == 50_000.0
    end

    test "passes stop-loss and take-profit in params" do
      credentials = %CCXT.Credentials{api_key: "key", secret: "secret"}

      {:ok, result} =
        "BTC/USDT"
        |> Builder.new(:buy, 0.1)
        |> Builder.stop_loss(48_000.0)
        |> Builder.take_profit(55_000.0)
        |> Builder.submit(MockExchange, credentials)

      params = Keyword.get(result.opts, :params)
      assert Keyword.get(params, :stopLoss) == 48_000.0
      assert Keyword.get(params, :takeProfit) == 55_000.0
    end

    test "passes client order ID in params" do
      credentials = %CCXT.Credentials{api_key: "key", secret: "secret"}

      {:ok, result} =
        "BTC/USDT"
        |> Builder.new(:buy, 0.1)
        |> Builder.client_id("my-order")
        |> Builder.submit(MockExchange, credentials)

      assert result.opts == [params: [clientOrderId: "my-order"]]
    end

    test "merges all params together" do
      credentials = %CCXT.Credentials{api_key: "key", secret: "secret"}

      {:ok, result} =
        "BTC/USDT"
        |> Builder.new(:buy, 0.1)
        |> Builder.stop_loss(48_000.0)
        |> Builder.client_id("my-order")
        |> Builder.params(timeInForce: "GTC")
        |> Builder.submit(MockExchange, credentials)

      params = Keyword.get(result.opts, :params)

      assert Keyword.get(params, :stopLoss) == 48_000.0
      assert Keyword.get(params, :clientOrderId) == "my-order"
      assert Keyword.get(params, :timeInForce) == "GTC"
    end
  end
end
