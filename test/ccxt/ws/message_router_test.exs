defmodule CCXT.WS.MessageRouterTest do
  use ExUnit.Case, async: true

  alias CCXT.WS.MessageRouter

  # -- get_nested/2 -----------------------------------------------------------

  describe "get_nested/2" do
    test "resolves single-level key" do
      assert MessageRouter.get_nested(%{"e" => "trade"}, "e") == "trade"
    end

    test "resolves dot-notation path" do
      msg = %{"params" => %{"channel" => "ticker.BTC-PERPETUAL"}}
      assert MessageRouter.get_nested(msg, "params.channel") == "ticker.BTC-PERPETUAL"
    end

    test "resolves deeply nested path" do
      msg = %{"a" => %{"b" => %{"c" => "deep"}}}
      assert MessageRouter.get_nested(msg, "a.b.c") == "deep"
    end

    test "returns nil for missing intermediate key" do
      assert MessageRouter.get_nested(%{"a" => %{}}, "a.b.c") == nil
    end

    test "returns nil for nil path" do
      assert MessageRouter.get_nested(%{"a" => 1}, nil) == nil
    end

    test "returns nil for non-map input" do
      assert MessageRouter.get_nested("not a map", "a") == nil
    end

    test "returns non-string values" do
      msg = %{"data" => [1, 2, 3]}
      assert MessageRouter.get_nested(msg, "data") == [1, 2, 3]
    end
  end

  # -- extract_channel/2 ------------------------------------------------------

  describe "extract_channel/2" do
    test "flat pattern (Binance): extracts from top-level key" do
      msg = %{"e" => "depthUpdate", "s" => "BTCUSDT"}
      envelope = %{"discriminator_field" => "e", "data_field" => "self", "pattern" => "flat"}

      assert MessageRouter.extract_channel(msg, envelope) == "depthUpdate"
    end

    test "topic_data pattern (Bybit): extracts from topic" do
      msg = %{"topic" => "orderbook.500.BTCUSDT", "data" => %{"a" => []}}
      envelope = %{"discriminator_field" => "topic", "data_field" => "data", "pattern" => "topic_data"}

      assert MessageRouter.extract_channel(msg, envelope) == "orderbook.500.BTCUSDT"
    end

    test "jsonrpc_subscription pattern (Deribit): extracts nested channel" do
      msg = %{
        "jsonrpc" => "2.0",
        "method" => "subscription",
        "params" => %{
          "channel" => "ticker.BTC-PERPETUAL.raw",
          "data" => %{"best_ask_price" => 42_000}
        }
      }

      envelope = %{
        "discriminator_field" => "params.channel",
        "data_field" => "params.data",
        "pattern" => "jsonrpc_subscription"
      }

      assert MessageRouter.extract_channel(msg, envelope) == "ticker.BTC-PERPETUAL.raw"
    end

    test "arg_data pattern (OKX): extracts from arg.channel" do
      msg = %{
        "arg" => %{"channel" => "candle1m", "instId" => "BTC-USDT"},
        "data" => [%{"o" => "42000"}]
      }

      envelope = %{
        "discriminator_field" => "arg.channel",
        "data_field" => "data",
        "pattern" => "arg_data"
      }

      assert MessageRouter.extract_channel(msg, envelope) == "candle1m"
    end

    test "channel_result pattern (Gate): extracts from channel" do
      msg = %{"channel" => "spot.trades", "result" => %{"price" => "42000"}}
      envelope = %{"discriminator_field" => "channel", "data_field" => "result", "pattern" => "channel_result"}

      assert MessageRouter.extract_channel(msg, envelope) == "spot.trades"
    end

    test "returns nil when discriminator field not found" do
      msg = %{"other_field" => "value"}
      envelope = %{"discriminator_field" => "e", "data_field" => "self"}

      assert MessageRouter.extract_channel(msg, envelope) == nil
    end
  end

  # -- extract_data/2 ---------------------------------------------------------

  describe "extract_data/2" do
    test "self data_field returns entire message" do
      msg = %{"e" => "trade", "s" => "BTCUSDT", "p" => "42000"}
      envelope = %{"data_field" => "self"}

      assert MessageRouter.extract_data(msg, envelope) == msg
    end

    test "simple data_field extracts nested data" do
      data = %{"bids" => [], "asks" => []}
      msg = %{"topic" => "orderbook", "data" => data}
      envelope = %{"data_field" => "data"}

      assert MessageRouter.extract_data(msg, envelope) == data
    end

    test "dot-notation data_field extracts deeply nested data" do
      data = %{"best_ask_price" => 42_000}

      msg = %{
        "params" => %{"channel" => "ticker.BTC", "data" => data}
      }

      envelope = %{"data_field" => "params.data"}

      assert MessageRouter.extract_data(msg, envelope) == data
    end

    test "returns nil when data field not found" do
      msg = %{"channel" => "trades"}
      envelope = %{"data_field" => "result"}

      assert MessageRouter.extract_data(msg, envelope) == nil
    end

    test "unwraps single-element list when unwrap_list is true" do
      msg = %{"data" => [%{"price" => "42000", "symbol" => "BTC-USDT"}]}
      envelope = %{"data_field" => "data", "unwrap_list" => true}

      assert MessageRouter.extract_data(msg, envelope) == %{"price" => "42000", "symbol" => "BTC-USDT"}
    end

    test "does NOT unwrap multi-element list when unwrap_list is true" do
      items = [%{"price" => "42000"}, %{"price" => "43000"}]
      msg = %{"data" => items}
      envelope = %{"data_field" => "data", "unwrap_list" => true}

      assert MessageRouter.extract_data(msg, envelope) == items
    end

    test "does NOT unwrap when unwrap_list is false" do
      msg = %{"data" => [%{"price" => "42000"}]}
      envelope = %{"data_field" => "data", "unwrap_list" => false}

      assert MessageRouter.extract_data(msg, envelope) == [%{"price" => "42000"}]
    end

    test "does NOT unwrap when unwrap_list key absent (backward compat)" do
      msg = %{"data" => [%{"price" => "42000"}]}
      envelope = %{"data_field" => "data"}

      assert MessageRouter.extract_data(msg, envelope) == [%{"price" => "42000"}]
    end

    test "passes through non-list data when unwrap_list is true" do
      msg = %{"data" => %{"price" => "42000"}}
      envelope = %{"data_field" => "data", "unwrap_list" => true}

      assert MessageRouter.extract_data(msg, envelope) == %{"price" => "42000"}
    end
  end

  # -- route/3 ----------------------------------------------------------------

  describe "route/3" do
    test "returns {:unknown, msg} when envelope is nil" do
      msg = %{"e" => "trade"}
      assert MessageRouter.route(msg, nil, "binance") == {:unknown, msg}
    end

    test "returns {:unknown, msg} when discriminator field not found" do
      msg = %{"random" => "data"}
      envelope = %{"discriminator_field" => "e", "data_field" => "self"}

      assert MessageRouter.route(msg, envelope, "binance") == {:unknown, msg}
    end

    test "routes Binance depthUpdate to :watch_order_book" do
      msg = %{"e" => "depthUpdate", "b" => [["42000", "1.5"]], "a" => [["42001", "0.5"]]}
      envelope = %{"discriminator_field" => "e", "data_field" => "self", "pattern" => "flat"}

      assert {:routed, :watch_order_book, ^msg} = MessageRouter.route(msg, envelope, "binance")
    end

    test "routes Binance trade to :watch_trades" do
      msg = %{"e" => "trade", "s" => "BTCUSDT", "p" => "42000"}
      envelope = %{"discriminator_field" => "e", "data_field" => "self", "pattern" => "flat"}

      assert {:routed, :watch_trades, ^msg} = MessageRouter.route(msg, envelope, "binance")
    end

    test "routes Bybit orderbook with substring matching" do
      data = %{"b" => [["42000", "1"]], "a" => [["42001", "1"]]}
      msg = %{"topic" => "orderbook.500.BTCUSDT", "data" => data}
      envelope = %{"discriminator_field" => "topic", "data_field" => "data", "pattern" => "topic_data"}

      assert {:routed, :watch_order_book, ^data} = MessageRouter.route(msg, envelope, "bybit")
    end

    test "routes Deribit ticker with split matching" do
      data = %{"best_ask_price" => 42_000}

      msg = %{
        "jsonrpc" => "2.0",
        "method" => "subscription",
        "params" => %{"channel" => "ticker.BTC-PERPETUAL.raw", "data" => data}
      }

      envelope = %{
        "discriminator_field" => "params.channel",
        "data_field" => "params.data",
        "pattern" => "jsonrpc_subscription"
      }

      assert {:routed, :watch_ticker, ^data} = MessageRouter.route(msg, envelope, "deribit")
    end

    test "routes OKX candle with prefix matching" do
      data = [%{"o" => "42000", "h" => "42500"}]

      msg = %{
        "arg" => %{"channel" => "candle1m", "instId" => "BTC-USDT"},
        "data" => data
      }

      envelope = %{
        "discriminator_field" => "arg.channel",
        "data_field" => "data",
        "pattern" => "arg_data"
      }

      assert {:routed, :watch_ohlcv, ^data} = MessageRouter.route(msg, envelope, "okx")
    end

    test "routes Gate spot.trades with split matching" do
      data = [%{"price" => "42000", "amount" => "0.5"}]
      msg = %{"channel" => "spot.trades", "result" => data}
      envelope = %{"discriminator_field" => "channel", "data_field" => "result", "pattern" => "channel_result"}

      # gate uses split matching, "spot.trades" splits on "." -> tries "spot", "trades"
      # "trades" maps to handleTrades -> :watch_trades
      assert {:routed, :watch_trades, ^data} = MessageRouter.route(msg, envelope, "gate")
    end

    test "returns {:system, msg} for non-family handler (Bybit pong)" do
      # Bybit has "pong" mapped to handlePong which is a non-family handler
      msg = %{"op" => "pong", "ret_msg" => "pong"}
      envelope = %{"discriminator_field" => "op", "data_field" => "self"}

      assert {:system, ^msg} = MessageRouter.route(msg, envelope, "bybit")
    end

    test "returns {:unknown, msg} for unmapped channel on known exchange" do
      # Bybit is a known exchange, but "totally_invented_channel" has no handler
      msg = %{"topic" => "totally_invented_channel", "data" => %{}}
      envelope = %{"discriminator_field" => "topic", "data_field" => "data"}

      assert {:unknown, ^msg} = MessageRouter.route(msg, envelope, "bybit")
    end

    test "returns {:unknown, msg} for unrecognized exchange" do
      msg = %{"e" => "trade"}
      envelope = %{"discriminator_field" => "e", "data_field" => "self"}

      assert {:unknown, ^msg} = MessageRouter.route(msg, envelope, "nonexistent_exchange")
    end

    # -- response/ack detection (nil discriminator) --

    test "Binance subscription ack (nil id, nil result) routes to :system" do
      msg = %{"id" => nil, "result" => nil}
      envelope = %{"discriminator_field" => "e", "data_field" => "self", "pattern" => "flat"}

      assert {:system, ^msg} = MessageRouter.route(msg, envelope, "binance")
    end

    test "non-nil result ack routes to :system" do
      msg = %{"id" => 1, "result" => true}
      envelope = %{"discriminator_field" => "e", "data_field" => "self", "pattern" => "flat"}

      assert {:system, ^msg} = MessageRouter.route(msg, envelope, "binance")
    end

    test "no discriminator + no result key routes to :unknown" do
      msg = %{"random" => "data", "other" => "field"}
      envelope = %{"discriminator_field" => "e", "data_field" => "self"}

      assert {:unknown, ^msg} = MessageRouter.route(msg, envelope, "binance")
    end

    test "discriminator present + result key routes normally (not :system)" do
      msg = %{"e" => "trade", "result" => "extra", "s" => "BTCUSDT"}
      envelope = %{"discriminator_field" => "e", "data_field" => "self", "pattern" => "flat"}

      assert {:routed, :watch_trades, ^msg} = MessageRouter.route(msg, envelope, "binance")
    end

    test "OKX ticker routing with unwrap_list unwraps single-element list" do
      ticker_data = %{"instType" => "SPOT", "instId" => "BTC-USDT", "last" => "42000"}

      msg = %{
        "arg" => %{"channel" => "tickers", "instId" => "BTC-USDT"},
        "data" => [ticker_data]
      }

      envelope = %{
        "discriminator_field" => "arg.channel",
        "data_field" => "data",
        "pattern" => "arg_data",
        "unwrap_list" => true
      }

      assert {:routed, :watch_ticker, ^ticker_data} = MessageRouter.route(msg, envelope, "okx")
    end
  end
end
