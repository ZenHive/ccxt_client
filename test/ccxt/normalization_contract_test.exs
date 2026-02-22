defmodule CCXT.NormalizationContractTest do
  @moduledoc """
  End-to-end contract tests for the normalization pipeline.

  Verifies that raw exchange responses flow correctly through:
  ResponseParser instructions → ResponseCoercer → Type.from_map/1 → typed struct

  Tests use inline fixtures with real exchange field names from P1 analysis.
  """

  use ExUnit.Case, async: true

  alias CCXT.ResponseCoercer
  alias CCXT.ResponseParser.MappingCompiler
  alias CCXT.Types.Order
  alias CCXT.Types.OrderBook
  alias CCXT.Types.Ticker
  alias CCXT.Types.Trade

  @moduletag :normalization

  @analysis MappingCompiler.load_analysis()
  @tier1 ~w(binance bybit okx deribit coinbaseexchange)

  # Guard: P1 analysis must be loaded for tests to be meaningful
  if @analysis == %{} do
    raise "P1 analysis file not found at #{MappingCompiler.analysis_path()} — cannot run normalization contract tests"
  end

  # ── Fixtures ──────────────────────────────────────────────────────────

  defp ticker_fixture("binance") do
    %{
      "askPrice" => "67500.50",
      "bidPrice" => "67499.00",
      "lastPrice" => "67500.00",
      "highPrice" => "68000.00",
      "lowPrice" => "66000.00",
      "openPrice" => "66500.00",
      "askQty" => "1.5",
      "bidQty" => "2.3",
      "baseVolume" => "12345.67",
      "quoteVolume" => "833456789.12",
      "priceChangePercent" => "1.50",
      "weightedAvgPrice" => "67200.00",
      "closeTime" => 1_704_067_200_000,
      "prevClosePrice" => "66400.00",
      "indexPrice" => "67480.00",
      "markPrice" => "67501.00",
      "symbol" => "BTC/USDT"
    }
  end

  defp ticker_fixture("bybit") do
    %{
      "ask1Price" => "67500.50",
      "bid1Price" => "67499.00",
      "lastPrice" => "67500.00",
      "highPrice24h" => "68000.00",
      "lowPrice24h" => "66000.00",
      "prevPrice24h" => "66500.00",
      "ask1Size" => "1.5",
      "bid1Size" => "2.3",
      "volume24h" => "12345.67",
      "turnover24h" => "833456789.12",
      "price24hPcnt" => "0.015",
      "indexPrice" => "67480.00",
      "markPrice" => "67501.00",
      "time" => "1704067200000",
      "symbol" => "BTC/USDT"
    }
  end

  defp ticker_fixture("okx") do
    %{
      "askPx" => "67500.50",
      "bidPx" => "67499.00",
      "last" => "67500.00",
      "high24h" => "68000.00",
      "low24h" => "66000.00",
      "open24h" => "66500.00",
      "askSz" => "1.5",
      "bidSz" => "2.3",
      "vol24h" => "12345.67",
      "quoteVolume" => "833456789.12",
      "idxPx" => "67480.00",
      "markPx" => "67501.00",
      "ts" => "1704067200000",
      "instId" => "BTC-USDT"
    }
  end

  defp ticker_fixture("deribit") do
    %{
      "best_ask_price" => 67_500.50,
      "best_bid_price" => 67_499.00,
      "last_price" => 67_500.00,
      "high" => 68_000.00,
      "low" => 66_000.00,
      "best_ask_amount" => 1.5,
      "best_bid_amount" => 2.3,
      "volume" => 12_345.67,
      "index_price" => 67_480.00,
      "mark_price" => 67_501.00,
      "timestamp" => 1_704_067_200_000,
      "instrument_name" => "BTC-PERPETUAL"
    }
  end

  defp ticker_fixture("coinbaseexchange") do
    %{
      "ask" => "67500.50",
      "bid" => "67499.00",
      "last" => "67500.00",
      "high" => "68000.00",
      "low" => "66000.00",
      "open" => "66500.00",
      "volume" => "12345.67",
      "product_id" => "BTC-USD"
    }
  end

  defp trade_fixture("binance") do
    %{
      "p" => "67000.50",
      "q" => "0.001",
      "m" => true,
      "T" => 1_704_067_200_000,
      "t" => 12_345,
      "quoteQty" => "67.0005"
    }
  end

  defp trade_fixture("bybit") do
    %{
      "side" => "Sell",
      "price" => "67717.9",
      "size" => "0.00129",
      "time" => "1704067200000",
      "id" => "trade-001",
      "isMaker" => true,
      "execValue" => "87.36"
    }
  end

  defp trade_fixture("okx") do
    %{
      "side" => "buy",
      "fillPx" => "67717.9",
      "fillSz" => "0.00129",
      "ts" => "1704067200000",
      "tradeId" => "trade-002",
      "execType" => "taker",
      "ordId" => "order-001"
    }
  end

  defp trade_fixture("deribit") do
    %{
      "direction" => "sell",
      "price" => 67_717.9,
      "amount" => 0.00129,
      "timestamp" => 1_704_067_200_000,
      "trade_id" => "trade-003",
      "liquidity" => true,
      "order_id" => "order-002",
      "order_type" => "limit"
    }
  end

  defp trade_fixture("coinbaseexchange") do
    %{
      "side" => "buy",
      "price" => "67717.9",
      "size" => "0.00129",
      "trade_id" => "trade-004",
      "liquidity" => "T",
      "order_id" => "order-003",
      "cost" => "87.36"
    }
  end

  defp order_fixture("binance") do
    %{
      "orderId" => "12345",
      "clientOrderId" => "my-order-001",
      "origQty" => "0.5",
      "executedQty" => "0.3",
      "price" => "67000.00",
      "avgPrice" => "67100.00",
      "cummulativeQuoteQty" => "20130.00",
      "status" => "open",
      "side" => "BUY",
      "timeInForce" => "GTC",
      "time" => 1_704_067_200_000,
      "updateTime" => 1_704_067_300_000,
      "reduceOnly" => false,
      "postOnly" => false,
      "triggerPrice" => "66000.00",
      "symbol" => "BTCUSDT"
    }
  end

  defp order_fixture("bybit") do
    %{
      "orderId" => "bybit-001",
      "orderLinkId" => "my-order-002",
      "amount" => "0.5",
      "cumExecQty" => "0.3",
      "leavesQty" => "0.2",
      "price" => "67000.00",
      "avgPrice" => "67100.00",
      "cost" => "20130.00",
      "status" => "open",
      "side" => "Buy",
      "orderType" => "Limit",
      "timeInForce" => "GTC",
      "createdTime" => "1704067200000",
      "updatedTime" => "1704067300000",
      "reduceOnly" => false,
      "triggerPrice" => "66000.00",
      "stopLossPrice" => "60000.00",
      "takeProfitPrice" => "75000.00",
      "symbol" => "BTCUSDT"
    }
  end

  defp order_fixture("okx") do
    %{
      "ordId" => "okx-001",
      "clOrdId" => "my-order-003",
      "amount" => "0.5",
      "accFillSz" => "0.3",
      "px" => "67000.00",
      "avgPx" => "67100.00",
      "status" => "open",
      "side" => "buy",
      "ordType" => "limit",
      "timeInForce" => "GTC",
      "cTime" => "1704067200000",
      "uTime" => "1704067300000",
      "fillTime" => "1704067250000",
      "reduceOnly" => false,
      "postOnly" => false,
      "triggerPx" => "66000.00",
      "slTriggerPx" => "60000.00",
      "tpTriggerPx" => "75000.00",
      "instId" => "BTC-USDT",
      # OKX uses "-" as the key for the unified symbol in some responses
      "-" => "BTC/USDT"
    }
  end

  defp order_fixture("deribit") do
    %{
      "order_id" => "deribit-001",
      "amount" => 0.5,
      "filled_amount" => 0.3,
      "price" => 67_000.00,
      "average_price" => 67_100.00,
      "cost" => 20_130.00,
      "status" => "open",
      "direction" => "buy",
      "type" => "limit",
      "creation_timestamp" => 1_704_067_200_000,
      "post_only" => false,
      "stop_price" => 66_000.00,
      "instrument_name" => "BTC-PERPETUAL"
    }
  end

  defp order_fixture("coinbaseexchange") do
    %{
      "id" => "coinbase-001",
      "client_oid" => "my-order-005",
      "size" => "0.5",
      "filled_size" => "0.3",
      "price" => "67000.00",
      "executed_value" => "20130.00",
      "status" => "open",
      "side" => "buy",
      "type" => "limit",
      "time_in_force" => "GTC",
      "post_only" => false,
      "stop_price" => "66000.00",
      "product_id" => "BTC-USD"
    }
  end

  defp order_book_fixture("bybit") do
    %{
      "b" => [["67499.00", "1.5"], ["67498.00", "2.3"]],
      "a" => [["67500.50", "0.8"], ["67501.00", "1.2"]],
      "ts" => 1_704_067_200_000,
      "s" => "BTCUSDT"
    }
  end

  defp order_book_fixture(_exchange) do
    # Most exchanges return unified keys — no parser mapping needed
    %{
      "bids" => [["67499.00", "1.5"], ["67498.00", "2.3"]],
      "asks" => [["67500.50", "0.8"], ["67501.00", "1.2"]],
      "timestamp" => 1_704_067_200_000,
      "symbol" => "BTC/USDT"
    }
  end

  # ── Contract assertion helpers ────────────────────────────────────────

  defp assert_number_or_nil(value, field) do
    assert is_number(value) or is_nil(value),
           "expected #{field} to be number() | nil, got: #{inspect(value)}"
  end

  defp assert_integer_or_nil(value, field) do
    assert is_integer(value) or is_nil(value),
           "expected #{field} to be integer() | nil, got: #{inspect(value)}"
  end

  defp assert_ticker_contract(%Ticker{} = ticker) do
    for field <- ~w(bid ask last high low open close base_volume quote_volume vwap percentage mark_price index_price)a do
      assert_number_or_nil(Map.get(ticker, field), field)
    end

    assert_integer_or_nil(ticker.timestamp, :timestamp)
    assert is_map(ticker.raw), "expected raw to be a map, got: #{inspect(ticker.raw)}"
  end

  defp assert_trade_contract(%Trade{} = trade) do
    assert trade.side in [:buy, :sell, nil],
           "expected side to be :buy | :sell | nil, got: #{inspect(trade.side)}"

    assert trade.taker_or_maker in [:taker, :maker, nil],
           "expected taker_or_maker to be :taker | :maker | nil, got: #{inspect(trade.taker_or_maker)}"

    for field <- ~w(price amount cost)a do
      assert_number_or_nil(Map.get(trade, field), field)
    end

    assert_integer_or_nil(trade.timestamp, :timestamp)
    assert is_map(trade.raw), "expected raw to be a map, got: #{inspect(trade.raw)}"
  end

  defp assert_order_contract(%Order{} = order) do
    assert order.side in [:buy, :sell, nil],
           "expected side to be :buy | :sell | nil, got: #{inspect(order.side)}"

    assert order.status in [:open, :closed, :canceled, nil],
           "expected status to be :open | :closed | :canceled | nil, got: #{inspect(order.status)}"

    assert is_atom(order.type) or is_nil(order.type),
           "expected type to be atom() | nil, got: #{inspect(order.type)}"

    for field <- ~w(price amount filled average cost)a do
      assert_number_or_nil(Map.get(order, field), field)
    end

    assert_integer_or_nil(order.timestamp, :timestamp)
    assert is_map(order.raw), "expected raw to be a map, got: #{inspect(order.raw)}"
  end

  defp assert_order_book_contract(%OrderBook{} = book) do
    assert is_list(book.bids), "expected bids to be a list"
    assert is_list(book.asks), "expected asks to be a list"

    for [price, amount] <- book.bids do
      assert is_number(price), "expected bid price to be a number, got: #{inspect(price)}"
      assert is_number(amount), "expected bid amount to be a number, got: #{inspect(amount)}"
    end

    for [price, amount] <- book.asks do
      assert is_number(price), "expected ask price to be a number, got: #{inspect(price)}"
      assert is_number(amount), "expected ask amount to be a number, got: #{inspect(amount)}"
    end

    assert is_map(book.raw), "expected raw to be a map, got: #{inspect(book.raw)}"
  end

  # ── Ticker contract tests ────────────────────────────────────────────

  describe "ticker normalization" do
    for exchange_id <- @tier1 do
      mapping = MappingCompiler.compile_mapping(exchange_id, "parseTicker", @analysis)

      if mapping do
        @exchange_id exchange_id
        @mapping mapping

        test "#{exchange_id}: produces %Ticker{} with correct field types" do
          raw = ticker_fixture(@exchange_id)
          result = ResponseCoercer.coerce(raw, :ticker, [], @mapping)

          assert %Ticker{} = result
          assert_ticker_contract(result)
        end

        test "#{exchange_id}: numeric fields are never strings (nil-aware)" do
          raw = ticker_fixture(@exchange_id)
          result = ResponseCoercer.coerce(raw, :ticker, [], @mapping)

          core_fields = ~w(bid ask last high low open close)a

          for field <- core_fields do
            value = Map.get(result, field)

            if not is_nil(value) do
              refute is_binary(value),
                     "#{@exchange_id} ticker.#{field} should not be a string, got: #{inspect(value)}"
            end
          end

          # At least 3 core numeric fields must be non-nil — catches regressions
          # where a mapping silently stops producing values
          non_nil_count = Enum.count(core_fields, &(not is_nil(Map.get(result, &1))))

          assert non_nil_count >= 3,
                 "#{@exchange_id} ticker has only #{non_nil_count}/#{length(core_fields)} " <>
                   "core numeric fields populated — expected at least 3"
        end
      end
    end
  end

  # ── Trade contract tests ──────────────────────────────────────────────

  describe "trade normalization" do
    for exchange_id <- @tier1 do
      mapping = MappingCompiler.compile_mapping(exchange_id, "parseTrade", @analysis)

      if mapping do
        @exchange_id exchange_id
        @mapping mapping

        test "#{exchange_id}: produces %Trade{} with correct field types" do
          raw = trade_fixture(@exchange_id)
          result = ResponseCoercer.coerce(raw, :trade, [], @mapping)

          assert %Trade{} = result
          assert_trade_contract(result)
        end

        test "#{exchange_id}: side is atom, never string or boolean" do
          raw = trade_fixture(@exchange_id)
          result = ResponseCoercer.coerce(raw, :trade, [], @mapping)

          if not is_nil(result.side) do
            refute is_binary(result.side),
                   "#{@exchange_id} trade.side should be atom, got string: #{inspect(result.side)}"

            refute is_boolean(result.side),
                   "#{@exchange_id} trade.side should be atom, got boolean: #{inspect(result.side)}"
          end

          # side should be populated for all tier1 fixtures
          assert result.side != nil,
                 "#{@exchange_id} trade.side is nil — fixture should provide a side value"
        end

        test "#{exchange_id}: taker_or_maker is atom when present, never string or boolean" do
          raw = trade_fixture(@exchange_id)
          result = ResponseCoercer.coerce(raw, :trade, [], @mapping)

          if not is_nil(result.taker_or_maker) do
            refute is_binary(result.taker_or_maker),
                   "#{@exchange_id} trade.taker_or_maker should be atom, got string: #{inspect(result.taker_or_maker)}"

            refute is_boolean(result.taker_or_maker),
                   "#{@exchange_id} trade.taker_or_maker should be atom, got boolean: #{inspect(result.taker_or_maker)}"
          end
        end
      end
    end
  end

  # ── Order contract tests ──────────────────────────────────────────────

  describe "order normalization" do
    for exchange_id <- @tier1 do
      mapping = MappingCompiler.compile_mapping(exchange_id, "parseOrder", @analysis)

      if mapping do
        @exchange_id exchange_id
        @mapping mapping

        test "#{exchange_id}: produces %Order{} with correct field types" do
          raw = order_fixture(@exchange_id)
          result = ResponseCoercer.coerce(raw, :order, [], @mapping)

          assert %Order{} = result
          assert_order_contract(result)
        end

        test "#{exchange_id}: side and status are atoms, never strings" do
          raw = order_fixture(@exchange_id)
          result = ResponseCoercer.coerce(raw, :order, [], @mapping)

          if not is_nil(result.side) do
            refute is_binary(result.side),
                   "#{@exchange_id} order.side should be atom, got string: #{inspect(result.side)}"
          end

          if not is_nil(result.status) do
            refute is_binary(result.status),
                   "#{@exchange_id} order.status should be atom, got string: #{inspect(result.status)}"
          end

          # Both side and status should be populated for all tier1 order fixtures
          assert result.side != nil,
                 "#{@exchange_id} order.side is nil — fixture should provide a side value"

          assert result.status != nil,
                 "#{@exchange_id} order.status is nil — fixture should provide a status value"
        end
      end
    end
  end

  # ── OrderBook contract tests ──────────────────────────────────────────

  describe "order_book normalization" do
    test "bybit: produces %OrderBook{} with parser mapping" do
      mapping = MappingCompiler.compile_mapping("bybit", "parseOrderBook", @analysis)
      raw = order_book_fixture("bybit")
      result = ResponseCoercer.coerce(raw, :order_book, [], mapping)

      assert %OrderBook{} = result
      assert_order_book_contract(result)
    end

    test "baseline: produces %OrderBook{} without parser mapping (unified keys)" do
      raw = order_book_fixture("baseline")
      result = ResponseCoercer.coerce(raw, :order_book, [], nil)

      assert %OrderBook{} = result
      assert_order_book_contract(result)
    end
  end

  # ── List-shape contract tests ─────────────────────────────────────────

  describe "list-shape: trades normalization" do
    for exchange_id <- @tier1 do
      mapping = MappingCompiler.compile_mapping(exchange_id, "parseTrade", @analysis)

      if mapping do
        @exchange_id exchange_id
        @mapping mapping

        test "#{exchange_id}: coerces list of raw maps to [%Trade{}]" do
          raw_list = [trade_fixture(@exchange_id), trade_fixture(@exchange_id)]
          result = ResponseCoercer.coerce(raw_list, :trades, [], @mapping)

          assert is_list(result)
          assert length(result) == 2

          for trade <- result do
            assert %Trade{} = trade
            assert_trade_contract(trade)
          end
        end
      end
    end
  end

  describe "list-shape: orders normalization" do
    for exchange_id <- @tier1 do
      mapping = MappingCompiler.compile_mapping(exchange_id, "parseOrder", @analysis)

      if mapping do
        @exchange_id exchange_id
        @mapping mapping

        test "#{exchange_id}: coerces list of raw maps to [%Order{}]" do
          raw_list = [order_fixture(@exchange_id), order_fixture(@exchange_id)]
          result = ResponseCoercer.coerce(raw_list, :orders, [], @mapping)

          assert is_list(result)
          assert length(result) == 2

          for order <- result do
            assert %Order{} = order
            assert_order_contract(order)
          end
        end
      end
    end
  end

  # ── Exchange-specific coercion tests ──────────────────────────────────

  describe "exchange-specific coercion patterns" do
    test "binance trade: boolean side (true → :sell, false → :buy)" do
      mapping = MappingCompiler.compile_mapping("binance", "parseTrade", @analysis)

      sell_raw = %{"p" => "67000.50", "q" => "0.001", "m" => true, "T" => 1_704_067_200_000}
      buy_raw = %{"p" => "67000.50", "q" => "0.001", "m" => false, "T" => 1_704_067_200_000}

      sell_result = ResponseCoercer.coerce(sell_raw, :trade, [], mapping)
      buy_result = ResponseCoercer.coerce(buy_raw, :trade, [], mapping)

      assert sell_result.side == :sell
      assert buy_result.side == :buy
    end

    test "bybit trade: isMaker boolean → taker_or_maker atom" do
      mapping = MappingCompiler.compile_mapping("bybit", "parseTrade", @analysis)

      maker_raw = %{"side" => "Buy", "price" => "67717.9", "size" => "0.001", "isMaker" => true}
      taker_raw = %{"side" => "Buy", "price" => "67717.9", "size" => "0.001", "isMaker" => false}

      maker_result = ResponseCoercer.coerce(maker_raw, :trade, [], mapping)
      taker_result = ResponseCoercer.coerce(taker_raw, :trade, [], mapping)

      assert maker_result.taker_or_maker == :maker
      assert taker_result.taker_or_maker == :taker
    end

    test "deribit trade: liquidity boolean → taker_or_maker atom" do
      mapping = MappingCompiler.compile_mapping("deribit", "parseTrade", @analysis)

      maker_raw = %{"direction" => "sell", "price" => 67_717.9, "amount" => 0.001, "liquidity" => true}
      taker_raw = %{"direction" => "sell", "price" => 67_717.9, "amount" => 0.001, "liquidity" => false}

      maker_result = ResponseCoercer.coerce(maker_raw, :trade, [], mapping)
      taker_result = ResponseCoercer.coerce(taker_raw, :trade, [], mapping)

      assert maker_result.taker_or_maker == :maker
      assert taker_result.taker_or_maker == :taker
    end

    test "bybit trade: string_lower normalizes side casing" do
      mapping = MappingCompiler.compile_mapping("bybit", "parseTrade", @analysis)

      raw = %{"side" => "Sell", "price" => "67717.9", "size" => "0.001"}
      result = ResponseCoercer.coerce(raw, :trade, [], mapping)

      assert result.side == :sell
    end

    test "bybit order: string_lower normalizes type casing" do
      mapping = MappingCompiler.compile_mapping("bybit", "parseOrder", @analysis)

      raw = order_fixture("bybit")
      result = ResponseCoercer.coerce(raw, :order, [], mapping)

      assert result.type == :limit
    end

    test "string timestamp coerced to integer" do
      mapping = MappingCompiler.compile_mapping("bybit", "parseTicker", @analysis)

      raw = %{"lastPrice" => "67500.00", "time" => "1704067200000"}
      result = ResponseCoercer.coerce(raw, :ticker, [], mapping)

      assert result.timestamp == 1_704_067_200_000
    end

    test "normalize: false returns raw data unchanged" do
      raw = ticker_fixture("binance")
      result = ResponseCoercer.coerce(raw, :ticker, normalize: false)

      assert result == raw
    end
  end
end
