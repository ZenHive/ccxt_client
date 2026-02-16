defmodule CCXT.WS.MessageRouterNormalizerIntegrationTest do
  @moduledoc """
  End-to-end tests: route → normalize → Contract.validate pipeline.

  Feeds exchange-shaped raw WS envelopes through the full normalization chain
  and asserts contract compliance on the output.
  """
  use ExUnit.Case, async: true

  import CCXT.Test.WsContractHelpers

  alias CCXT.Types.OHLCVBar
  alias CCXT.WS.Contract
  alias CCXT.WS.MessageRouter
  alias CCXT.WS.Normalizer

  # -- route → normalize → validate pipeline ---------------------------------

  describe "route → normalize → validate pipeline" do
    test "Bybit topic_data ticker: full pipeline" do
      data = %{
        "symbol" => "BTCUSDT",
        "lastPrice" => "42000.5",
        "ask1Price" => "42001.0",
        "bid1Price" => "41999.0",
        "highPrice24h" => "43000.0",
        "lowPrice24h" => "41000.0"
      }

      msg = %{"topic" => "tickers.BTCUSDT", "data" => data}

      envelope = %{
        "discriminator_field" => "topic",
        "data_field" => "data",
        "pattern" => "topic_data"
      }

      assert {:routed, :watch_ticker, ^data} = MessageRouter.route(msg, envelope, "bybit")

      assert {:ok, ticker} = Normalizer.normalize(:watch_ticker, data, CCXT.Bybit)
      assert_contract_compliance(:watch_ticker, ticker)
    end

    test "Bybit topic_data orderbook: full pipeline" do
      data = %{
        "s" => "BTCUSDT",
        "b" => [["42000", "1.5"], ["41999", "2.0"]],
        "a" => [["42001", "0.5"], ["42002", "1.0"]]
      }

      msg = %{"topic" => "orderbook.500.BTCUSDT", "data" => data}

      envelope = %{
        "discriminator_field" => "topic",
        "data_field" => "data",
        "pattern" => "topic_data"
      }

      assert {:routed, :watch_order_book, ^data} = MessageRouter.route(msg, envelope, "bybit")

      # Bybit orderbook uses "b"/"a" keys — normalizer uses parser instructions to map them
      assert {:ok, book} = Normalizer.normalize(:watch_order_book, data, CCXT.Bybit)
      assert_contract_compliance(:watch_order_book, book)
    end

    test "Deribit jsonrpc ticker: full pipeline" do
      data = %{
        "best_ask_price" => 42_001.0,
        "best_bid_price" => 41_999.0,
        "last_price" => 42_000.0,
        "instrument_name" => "BTC-PERPETUAL",
        "timestamp" => 1_700_000_000_000
      }

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

      # FakeExchange has no parser instructions → instrument_name won't map to symbol
      assert {:ok, ticker} = Normalizer.normalize(:watch_ticker, data, FakeExchange)
      # Without parser, symbol is missing — contract must fail deterministically
      assert {:error, violations} = Contract.validate(:watch_ticker, ticker)
      assert {:missing_field, :symbol} in violations
    end

    test "OKX arg_data OHLCV: full pipeline produces OHLCVBar structs" do
      data = [[1_700_000_000_000, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0]]

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

      assert {:ok, [%OHLCVBar{} = bar]} = Normalizer.normalize(:watch_ohlcv, data, FakeExchange)
      assert bar.timestamp == 1_700_000_000_000
      assert bar.open == 42_000.0
      assert {:ok, _} = Contract.validate(:watch_ohlcv, [bar])
    end

    test "Gate channel_result trades: full pipeline" do
      data = [
        %{
          "symbol" => "BTC/USDT",
          "price" => "42000.0",
          "amount" => "0.5",
          "side" => "buy",
          "timestamp" => 1_700_000_000_000
        }
      ]

      msg = %{"channel" => "spot.trades", "result" => data}

      envelope = %{
        "discriminator_field" => "channel",
        "data_field" => "result",
        "pattern" => "channel_result"
      }

      assert {:routed, :watch_trades, ^data} = MessageRouter.route(msg, envelope, "gate")

      assert {:ok, trades} = Normalizer.normalize(:watch_trades, data, FakeExchange)
      assert_contract_compliance(:watch_trades, trades)
    end

    test "Binance flat ticker: symbol from exchange key 's' not mapped" do
      # Binance flat envelope uses data_field="self", so entire message is the payload.
      # The exchange uses "s" for symbol (e.g., "BTCUSDT") not "symbol" — this is a
      # documented gap: without parser instructions, "symbol" won't be populated.
      msg = %{
        "e" => "24hrTicker",
        "s" => "BTCUSDT",
        "c" => "42000.0",
        "h" => "43000.0",
        "l" => "41000.0"
      }

      envelope = %{
        "discriminator_field" => "e",
        "data_field" => "self",
        "pattern" => "flat"
      }

      assert {:routed, :watch_ticker, ^msg} = MessageRouter.route(msg, envelope, "binance")

      assert {:ok, ticker} = Normalizer.normalize(:watch_ticker, msg, FakeExchange)

      # Without Binance parser instructions, "s" → symbol mapping won't happen
      assert {:error, violations} = Contract.validate(:watch_ticker, ticker)
      assert {:missing_field, :symbol} in violations
    end
  end

  # -- System and unknown messages stop before normalization ------------------

  describe "system and unknown messages stop before normalization" do
    test "Bybit pong (system): route returns {:system, msg} unchanged" do
      msg = %{"op" => "pong", "ret_msg" => "pong"}
      envelope = %{"discriminator_field" => "op", "data_field" => "self"}

      assert {:system, result} = MessageRouter.route(msg, envelope, "bybit")
      assert result == msg
    end

    test "unknown channel: route returns {:unknown, msg} unchanged" do
      msg = %{"topic" => "totally_invented_channel", "data" => %{"x" => 1}}
      envelope = %{"discriminator_field" => "topic", "data_field" => "data"}

      assert {:unknown, result} = MessageRouter.route(msg, envelope, "bybit")
      assert result == msg
    end

    test "nil envelope: route returns {:unknown, msg} unchanged" do
      msg = %{"some" => "data"}

      assert {:unknown, result} = MessageRouter.route(msg, nil, "binance")
      assert result == msg
    end
  end

  # -- route → normalize with malformed payload -------------------------------

  describe "route → normalize with malformed payload" do
    test "single-family routed but nil payload → normalize error" do
      # Simulate an envelope that extracts nil for data_field
      msg = %{"topic" => "tickers.BTCUSDT"}

      envelope = %{
        "discriminator_field" => "topic",
        "data_field" => "data"
      }

      assert {:routed, :watch_ticker, nil} = MessageRouter.route(msg, envelope, "bybit")

      assert {:error, {:expected_map, nil}} =
               Normalizer.normalize(:watch_ticker, nil, FakeExchange)
    end

    test "list-family routed but [nil] payload → normalize error" do
      assert {:error, {:invalid_list_element, [index: 0, value: nil]}} =
               Normalizer.normalize(:watch_trades, [nil], FakeExchange)
    end

    test "valid route but empty data field → normalize handles nil" do
      # Gate envelope where "result" key is missing → extract_data returns nil
      msg = %{"channel" => "spot.trades"}
      envelope = %{"discriminator_field" => "channel", "data_field" => "result"}

      assert {:routed, :watch_trades, nil} = MessageRouter.route(msg, envelope, "gate")

      # nil is not a list, so normalize returns expected_list error
      assert {:error, {:expected_list, nil}} =
               Normalizer.normalize(:watch_trades, nil, FakeExchange)
    end
  end
end
