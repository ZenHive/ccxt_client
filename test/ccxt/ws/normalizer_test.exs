defmodule CCXT.WS.NormalizerTest do
  use ExUnit.Case, async: true

  import CCXT.Test.WsContractHelpers

  alias CCXT.Types.Balance
  alias CCXT.Types.OHLCVBar
  alias CCXT.Types.Order
  alias CCXT.Types.OrderBook
  alias CCXT.Types.Position
  alias CCXT.Types.Ticker
  alias CCXT.Types.Trade
  alias CCXT.WS.Contract
  alias CCXT.WS.Normalizer

  # -- Ticker normalization ---------------------------------------------------

  describe "normalize/3 :watch_ticker" do
    test "normalizes ticker payload to Ticker struct" do
      payload = %{
        "symbol" => "BTC/USDT",
        "last" => "42000.5",
        "ask" => "42001.0",
        "bid" => "41999.0",
        "high" => "43000.0",
        "low" => "41000.0",
        "timestamp" => 1_700_000_000_000
      }

      assert {:ok, %Ticker{} = ticker} =
               Normalizer.normalize(:watch_ticker, payload, FakeExchange)

      assert ticker.symbol == "BTC/USDT"
      assert ticker.raw == payload
    end

    test "normalizes with exchange-specific parser instructions" do
      # Bybit uses ask1Price/bid1Price instead of ask/bid
      payload = %{
        "symbol" => "BTCUSDT",
        "ask1Price" => "42001.0",
        "bid1Price" => "41999.0",
        "lastPrice" => "42000.0"
      }

      assert {:ok, %Ticker{} = ticker} =
               Normalizer.normalize(:watch_ticker, payload, CCXT.Bybit)

      # Parser instructions should map ask1Price -> ask
      assert ticker.ask == 42_001.0
      assert ticker.bid == 41_999.0
    end

    test "returns error for non-map payload" do
      assert {:error, {:expected_map, "not a map"}} =
               Normalizer.normalize(:watch_ticker, "not a map", FakeExchange)
    end
  end

  # -- Ticker coercion depth -------------------------------------------------

  describe "normalize/3 :watch_ticker coercion" do
    test "numeric fields pass through as numbers (FakeExchange, no parser)" do
      # FakeExchange has no parser instructions — already-numeric values stay numeric
      payload = %{
        "symbol" => "BTC/USDT",
        "last" => 42_000.5,
        "ask" => 42_001.0,
        "bid" => 41_999.0,
        "high" => 43_000.0,
        "low" => 41_000.0
      }

      assert {:ok, %Ticker{} = ticker} =
               Normalizer.normalize(:watch_ticker, payload, FakeExchange)

      assert_coercion_applied(ticker, [:last, :ask, :bid, :high, :low])
    end

    test "string-to-float coercion requires parser instructions (Bybit)" do
      payload = %{
        "symbol" => "BTCUSDT",
        "ask1Price" => "42001.0",
        "bid1Price" => "41999.0",
        "lastPrice" => "42000.0",
        "highPrice24h" => "43000.0",
        "lowPrice24h" => "41000.0"
      }

      assert {:ok, %Ticker{} = ticker} =
               Normalizer.normalize(:watch_ticker, payload, CCXT.Bybit)

      assert_coercion_applied(ticker, [:ask, :bid, :last])
      assert ticker.ask == 42_001.0
      assert ticker.bid == 41_999.0
      assert ticker.last == 42_000.0
    end

    test "timestamp preserved as integer" do
      payload = %{
        "symbol" => "BTC/USDT",
        "last" => 42_000.0,
        "timestamp" => 1_700_000_000_000
      }

      assert {:ok, %Ticker{} = ticker} =
               Normalizer.normalize(:watch_ticker, payload, FakeExchange)

      assert ticker.timestamp == 1_700_000_000_000
    end

    test "nil fields remain nil (not coerced to 0)" do
      payload = %{
        "symbol" => "BTC/USDT",
        "last" => 42_000.0,
        "ask" => nil,
        "bid" => nil
      }

      assert {:ok, %Ticker{} = ticker} =
               Normalizer.normalize(:watch_ticker, payload, FakeExchange)

      assert is_nil(ticker.ask)
      assert is_nil(ticker.bid)
    end

    test "raw field preserves original payload" do
      payload = %{
        "symbol" => "BTC/USDT",
        "last" => 42_000.5,
        "ask" => 42_001.0,
        "bid" => 41_999.0
      }

      assert {:ok, %Ticker{} = ticker} =
               Normalizer.normalize(:watch_ticker, payload, FakeExchange)

      assert_raw_preserved(ticker, payload)
    end

    test "contract compliance after normalization" do
      payload = %{
        "symbol" => "BTC/USDT",
        "last" => 42_000.5,
        "ask" => 42_001.0,
        "bid" => 41_999.0
      }

      assert {:ok, %Ticker{} = ticker} =
               Normalizer.normalize(:watch_ticker, payload, FakeExchange)

      assert_contract_compliance(:watch_ticker, ticker)
    end
  end

  # -- Trade normalization ----------------------------------------------------

  describe "normalize/3 :watch_trades" do
    test "normalizes list of trade maps" do
      payload = [
        %{
          "symbol" => "BTC/USDT",
          "price" => "42000.0",
          "amount" => "0.5",
          "side" => "buy",
          "timestamp" => 1_700_000_000_000
        },
        %{
          "symbol" => "BTC/USDT",
          "price" => "42001.0",
          "amount" => "0.3",
          "side" => "sell",
          "timestamp" => 1_700_000_001_000
        }
      ]

      assert {:ok, trades} = Normalizer.normalize(:watch_trades, payload, FakeExchange)
      assert length(trades) == 2
      assert %Trade{} = hd(trades)
      assert hd(trades).symbol == "BTC/USDT"
    end

    test "wraps single map in list" do
      payload = %{
        "symbol" => "BTC/USDT",
        "price" => "42000.0",
        "amount" => "0.5",
        "timestamp" => 1_700_000_000_000
      }

      assert {:ok, [%Trade{}]} =
               Normalizer.normalize(:watch_trades, payload, FakeExchange)
    end

    test "returns error for non-map elements in list payload" do
      payload = [%{"symbol" => "BTC/USDT", "price" => "42000"}, "not_a_map"]

      assert {:error, {:invalid_list_element, [index: 1, value: "not_a_map"]}} =
               Normalizer.normalize(:watch_trades, payload, FakeExchange)
    end

    test "returns error for invalid payload type" do
      assert {:error, {:expected_list, 42}} =
               Normalizer.normalize(:watch_trades, 42, FakeExchange)
    end
  end

  # -- Trades preservation + contract compliance ------------------------------

  describe "normalize/3 :watch_trades preservation" do
    test "normalized result passes contract validation" do
      payload = [
        %{
          "symbol" => "BTC/USDT",
          "price" => "42000.0",
          "amount" => "0.5",
          "timestamp" => 1_700_000_000_000
        }
      ]

      assert {:ok, trades} = Normalizer.normalize(:watch_trades, payload, FakeExchange)
      assert_contract_compliance(:watch_trades, trades)
    end

    test "raw field on each trade preserves original" do
      trade_map = %{
        "symbol" => "BTC/USDT",
        "price" => "42000.0",
        "amount" => "0.5",
        "side" => "buy",
        "timestamp" => 1_700_000_000_000
      }

      assert {:ok, [%Trade{} = trade]} =
               Normalizer.normalize(:watch_trades, [trade_map], FakeExchange)

      assert_raw_preserved(trade, trade_map)
    end

    test "required fields present" do
      payload = [
        %{
          "symbol" => "BTC/USDT",
          "price" => "42000.0",
          "amount" => "0.5",
          "timestamp" => 1_700_000_000_000
        }
      ]

      assert {:ok, trades} = Normalizer.normalize(:watch_trades, payload, FakeExchange)
      assert_required_fields(:watch_trades, trades)
    end

    test "multiple trades each independently normalized" do
      payload = [
        %{
          "symbol" => "BTC/USDT",
          "price" => "42000.0",
          "amount" => "0.5",
          "timestamp" => 1_700_000_000_000
        },
        %{
          "symbol" => "ETH/USDT",
          "price" => "2200.0",
          "amount" => "10.0",
          "timestamp" => 1_700_000_001_000
        }
      ]

      assert {:ok, [trade1, trade2]} =
               Normalizer.normalize(:watch_trades, payload, FakeExchange)

      assert %Trade{} = trade1
      assert %Trade{} = trade2
      assert trade1.symbol == "BTC/USDT"
      assert trade2.symbol == "ETH/USDT"
    end
  end

  # -- OrderBook normalization ------------------------------------------------

  describe "normalize/3 :watch_order_book" do
    test "normalizes order book payload" do
      payload = %{
        "symbol" => "BTC/USDT",
        "bids" => [["42000", "1.5"], ["41999", "2.0"]],
        "asks" => [["42001", "0.5"], ["42002", "1.0"]],
        "timestamp" => 1_700_000_000_000
      }

      assert {:ok, %OrderBook{} = book} =
               Normalizer.normalize(:watch_order_book, payload, FakeExchange)

      assert book.symbol == "BTC/USDT"
      # raw contains the payload-with-info (info key added by normalizer)
      assert book.raw["symbol"] == "BTC/USDT"
      assert book.raw["bids"] == payload["bids"]
      assert book.raw["asks"] == payload["asks"]
    end
  end

  # -- OrderBook preservation + contract compliance --------------------------

  describe "normalize/3 :watch_order_book preservation" do
    test "bids/asks arrays coerced to floats through normalization" do
      payload = %{
        "symbol" => "BTC/USDT",
        "bids" => [["42000", "1.5"], ["41999", "2.0"]],
        "asks" => [["42001", "0.5"], ["42002", "1.0"]],
        "timestamp" => 1_700_000_000_000
      }

      assert {:ok, %OrderBook{} = book} =
               Normalizer.normalize(:watch_order_book, payload, FakeExchange)

      assert book.bids == [[42_000.0, 1.5], [41_999.0, 2.0]]
      assert book.asks == [[42_001.0, 0.5], [42_002.0, 1.0]]
    end

    test "empty bids/asks (delta update) normalizes without error" do
      payload = %{
        "symbol" => "BTC/USDT",
        "bids" => [],
        "asks" => [],
        "timestamp" => 1_700_000_000_000
      }

      assert {:ok, %OrderBook{} = book} =
               Normalizer.normalize(:watch_order_book, payload, FakeExchange)

      assert book.bids == []
      assert book.asks == []
    end

    test "contract compliance after normalization" do
      payload = %{
        "symbol" => "BTC/USDT",
        "bids" => [["42000", "1.5"]],
        "asks" => [["42001", "0.5"]],
        "timestamp" => 1_700_000_000_000
      }

      assert {:ok, %OrderBook{} = book} =
               Normalizer.normalize(:watch_order_book, payload, FakeExchange)

      assert_contract_compliance(:watch_order_book, book)
    end

    test "raw field contains targeted fields (bids, asks, symbol)" do
      payload = %{
        "symbol" => "BTC/USDT",
        "bids" => [["42000", "1.5"]],
        "asks" => [["42001", "0.5"]]
      }

      assert {:ok, %OrderBook{} = book} =
               Normalizer.normalize(:watch_order_book, payload, FakeExchange)

      # OrderBook.raw includes "info" wrapper added by normalizer — don't use assert_raw_preserved
      assert book.raw["bids"] == payload["bids"]
      assert book.raw["asks"] == payload["asks"]
      assert book.raw["symbol"] == "BTC/USDT"
    end
  end

  # -- OHLCV normalization ----------------------------------------------------

  describe "normalize/3 :watch_ohlcv" do
    test "normalizes OHLCV arrays to OHLCVBar structs" do
      payload = [[1_700_000_000_000, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0]]

      assert {:ok, [%OHLCVBar{} = bar]} =
               Normalizer.normalize(:watch_ohlcv, payload, FakeExchange)

      assert bar.timestamp == 1_700_000_000_000
      assert bar.open == 42_000.0
      assert bar.close == 42_100.0
    end

    test "returns error for non-list payload" do
      assert {:error, {:expected_list, %{}}} =
               Normalizer.normalize(:watch_ohlcv, %{}, FakeExchange)
    end
  end

  # -- OHLCV variants --------------------------------------------------------

  describe "normalize/3 :watch_ohlcv variants" do
    test "multi-candle list produces sorted OHLCVBar structs" do
      payload = [
        [1_700_000_060_000, 42_100.0, 42_600.0, 42_000.0, 42_400.0, 800.0],
        [1_700_000_000_000, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0]
      ]

      assert {:ok, [bar1, bar2]} = Normalizer.normalize(:watch_ohlcv, payload, FakeExchange)
      assert %OHLCVBar{} = bar1
      assert %OHLCVBar{} = bar2
      assert bar1.timestamp < bar2.timestamp
    end

    test "empty list returns ok" do
      assert {:ok, []} = Normalizer.normalize(:watch_ohlcv, [], FakeExchange)
    end

    test "string values in candles get coerced to numbers" do
      payload = [["1700000000000", "42000", "42500", "41500", "42100", "1000"]]

      assert {:ok, [%OHLCVBar{} = bar]} =
               Normalizer.normalize(:watch_ohlcv, payload, FakeExchange)

      assert bar.timestamp == 1_700_000_000_000
      assert bar.open == 42_000.0
    end

    test "contract validation returns ok for normalized candles" do
      payload = [[1_700_000_000_000, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0]]

      assert {:ok, candles} = Normalizer.normalize(:watch_ohlcv, payload, FakeExchange)
      assert {:ok, _} = Contract.validate(:watch_ohlcv, candles)
    end
  end

  # -- Balance normalization --------------------------------------------------

  describe "normalize/3 :watch_balance" do
    test "normalizes balance payload" do
      payload = %{
        "free" => %{"BTC" => "1.5", "USDT" => "50000"},
        "used" => %{"BTC" => "0.5"},
        "total" => %{"BTC" => "2.0", "USDT" => "50000"}
      }

      assert {:ok, %Balance{}} =
               Normalizer.normalize(:watch_balance, payload, FakeExchange)
    end
  end

  # -- Orders normalization ---------------------------------------------------

  describe "normalize/3 :watch_orders" do
    test "normalizes list of order updates" do
      payload = [
        %{
          "id" => "order-123",
          "symbol" => "BTC/USDT",
          "status" => "open",
          "type" => "limit",
          "side" => "buy",
          "price" => "42000.0",
          "amount" => "1.0"
        }
      ]

      assert {:ok, [%Order{} = order]} =
               Normalizer.normalize(:watch_orders, payload, FakeExchange)

      assert order.id == "order-123"
      assert order.symbol == "BTC/USDT"
    end
  end

  # -- Positions normalization ------------------------------------------------

  describe "normalize/3 :watch_positions" do
    test "normalizes list of position updates" do
      payload = [
        %{
          "symbol" => "BTC/USDT",
          "side" => "long",
          "contracts" => "5.0",
          "entryPrice" => "42000.0"
        }
      ]

      assert {:ok, [%Position{}]} =
               Normalizer.normalize(:watch_positions, payload, FakeExchange)
    end
  end

  # -- Malformed payloads: deterministic error tuples per family ---------------

  describe "normalize/3 malformed payloads — single families" do
    for {family, label} <- [
          {:watch_ticker, "ticker"},
          {:watch_order_book, "order_book"},
          {:watch_balance, "balance"}
        ] do
      test "#{label}: nil → {:error, {:expected_map, nil}}" do
        assert {:error, {:expected_map, nil}} =
                 Normalizer.normalize(unquote(family), nil, FakeExchange)
      end

      test "#{label}: integer → {:error, {:expected_map, 42}}" do
        assert {:error, {:expected_map, 42}} =
                 Normalizer.normalize(unquote(family), 42, FakeExchange)
      end

      test "#{label}: atom → {:error, {:expected_map, :bad}}" do
        assert {:error, {:expected_map, :bad}} =
                 Normalizer.normalize(unquote(family), :bad, FakeExchange)
      end
    end
  end

  describe "normalize/3 malformed payloads — list families" do
    for {family, label} <- [
          {:watch_trades, "trades"},
          {:watch_orders, "orders"},
          {:watch_positions, "positions"}
        ] do
      test "#{label}: nil → {:error, {:expected_list, nil}}" do
        assert {:error, {:expected_list, nil}} =
                 Normalizer.normalize(unquote(family), nil, FakeExchange)
      end

      test "#{label}: integer → {:error, {:expected_list, 42}}" do
        assert {:error, {:expected_list, 42}} =
                 Normalizer.normalize(unquote(family), 42, FakeExchange)
      end

      test "#{label}: [nil, nil] → {:error, {:invalid_list_element, ...}}" do
        assert {:error, {:invalid_list_element, [index: 0, value: nil]}} =
                 Normalizer.normalize(unquote(family), [nil, nil], FakeExchange)
      end
    end
  end

  describe "normalize/3 malformed payloads — OHLCV" do
    test "nil → {:error, {:expected_list, nil}}" do
      assert {:error, {:expected_list, nil}} =
               Normalizer.normalize(:watch_ohlcv, nil, FakeExchange)
    end

    test "map → {:error, {:expected_list, %{}}}" do
      assert {:error, {:expected_list, %{}}} =
               Normalizer.normalize(:watch_ohlcv, %{}, FakeExchange)
    end

    test "atom → {:error, {:expected_list, :bad}}" do
      assert {:error, {:expected_list, :bad}} =
               Normalizer.normalize(:watch_ohlcv, :bad, FakeExchange)
    end
  end

  # -- Graceful degradation ---------------------------------------------------

  describe "graceful degradation" do
    test "works without parser instructions (unknown exchange module)" do
      # FakeExchange doesn't have __ccxt_parsers__/0
      payload = %{"symbol" => "BTC/USDT", "last" => 42_000.0}

      assert {:ok, %Ticker{}} =
               Normalizer.normalize(:watch_ticker, payload, FakeExchange)
    end

    test "populates raw field with original payload" do
      payload = %{"symbol" => "BTC/USDT", "ask" => "42001"}

      assert {:ok, %Ticker{raw: raw}} =
               Normalizer.normalize(:watch_ticker, payload, FakeExchange)

      assert raw == payload
    end
  end
end
