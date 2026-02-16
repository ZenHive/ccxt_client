defmodule CCXT.OHLCVTest do
  use ExUnit.Case, async: true

  alias CCXT.OHLCV
  alias CCXT.Types.OHLCVBar

  # -- normalize/1 -------------------------------------------------------------

  describe "normalize/1" do
    test "canonical numeric input produces OHLCVBar structs" do
      candles = [[1_704_153_600_000, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0]]

      assert {:ok, [%OHLCVBar{} = bar]} = OHLCV.normalize(candles)
      assert bar.timestamp == 1_704_153_600_000
      assert bar.open == 42_000.0
      assert bar.high == 42_500.0
      assert bar.low == 41_500.0
      assert bar.close == 42_100.0
      assert bar.volume == 1000.0
    end

    test "reverse-sorted candles are sorted ascending by timestamp" do
      candles = [
        [1_704_153_660_000, 42_100.0, 42_600.0, 42_000.0, 42_400.0, 800.0],
        [1_704_153_600_000, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0]
      ]

      assert {:ok, [bar1, bar2]} = OHLCV.normalize(candles)
      assert bar1.timestamp == 1_704_153_600_000
      assert bar2.timestamp == 1_704_153_660_000
    end

    test "duplicate timestamps preserve input order (stable sort)" do
      ts = 1_704_153_600_000

      candles = [
        [ts, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0],
        [ts, 42_100.0, 42_600.0, 42_000.0, 42_400.0, 800.0]
      ]

      assert {:ok, [bar1, bar2]} = OHLCV.normalize(candles)
      assert bar1.open == 42_000.0
      assert bar2.open == 42_100.0
    end

    test "string values are coerced to numbers" do
      candles = [["1704153600000", "42000", "42500", "41500", "42100", "1000"]]

      assert {:ok, [%OHLCVBar{} = bar]} = OHLCV.normalize(candles)
      assert bar.timestamp == 1_704_153_600_000
      assert bar.open == 42_000.0
      assert bar.high == 42_500.0
      assert bar.close == 42_100.0
      assert bar.volume == 1000.0
    end

    test "mixed string/number values are coerced" do
      candles = [[1_704_153_600_000, "42000.5", 42_500.0, "41500", 42_100, "1000.0"]]

      assert {:ok, [%OHLCVBar{} = bar]} = OHLCV.normalize(candles)
      assert bar.timestamp == 1_704_153_600_000
      assert bar.open == 42_000.5
      assert bar.high == 42_500.0
      assert bar.low == 41_500.0
      assert bar.close == 42_100.0
      assert bar.volume == 1000.0
    end

    test "float timestamp is truncated to integer" do
      candles = [[1_704_153_600_000.0, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0]]

      assert {:ok, [%OHLCVBar{} = bar]} = OHLCV.normalize(candles)
      assert bar.timestamp == 1_704_153_600_000
      assert is_integer(bar.timestamp)
    end

    test "string timestamp is parsed to integer" do
      candles = [["1704153600000", 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0]]

      assert {:ok, [%OHLCVBar{} = bar]} = OHLCV.normalize(candles)
      assert bar.timestamp == 1_704_153_600_000
      assert is_integer(bar.timestamp)
    end

    test "string float timestamp is parsed and truncated" do
      candles = [["1704153600000.0", 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0]]

      assert {:ok, [%OHLCVBar{} = bar]} = OHLCV.normalize(candles)
      assert bar.timestamp == 1_704_153_600_000
    end

    test "nil timestamp returns error" do
      candles = [[nil, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0]]

      assert {:error, {:nil_timestamp, 0}} = OHLCV.normalize(candles)
    end

    test "nil volume is kept as nil (allowed for OHLCV values)" do
      candles = [[1_704_153_600_000, 42_000.0, 42_500.0, 41_500.0, 42_100.0, nil]]

      assert {:ok, [%OHLCVBar{} = bar]} = OHLCV.normalize(candles)
      assert is_nil(bar.volume)
    end

    test "nil open/high/low/close are kept as nil" do
      candles = [[1_704_153_600_000, nil, nil, nil, nil, nil]]

      assert {:ok, [%OHLCVBar{} = bar]} = OHLCV.normalize(candles)
      assert is_nil(bar.open)
      assert is_nil(bar.high)
      assert is_nil(bar.low)
      assert is_nil(bar.close)
      assert is_nil(bar.volume)
    end

    test "extra candle fields are ignored (e.g. Bybit turnover)" do
      # Bybit returns 7 values: [ts, open, high, low, close, volume, turnover]
      candles = [[1_704_153_600_000, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0, 42_050_000.0]]

      assert {:ok, [%OHLCVBar{} = bar]} = OHLCV.normalize(candles)
      assert bar.timestamp == 1_704_153_600_000
      assert bar.volume == 1000.0
    end

    test "too-short candle returns error" do
      candles = [[1_704_153_600_000, 42_000.0, 42_500.0, 41_500.0, 42_100.0]]

      assert {:error, {:wrong_candle_length, [expected: 6, got: 5]}} = OHLCV.normalize(candles)
    end

    test "non-numeric value returns error with field name" do
      candles = [[1_704_153_600_000, :bad, 42_500.0, 41_500.0, 42_100.0, 1000.0]]

      assert {:error, {:invalid_value, :open, :bad, 0}} = OHLCV.normalize(candles)
    end

    test "non-list input returns error" do
      assert {:error, {:expected_list, "not a list"}} = OHLCV.normalize("not a list")
      assert {:error, {:invalid_ohlcv_format, _}} = OHLCV.normalize(%{})
      assert {:error, {:expected_list, 42}} = OHLCV.normalize(42)
    end

    test "empty list returns ok with empty list" do
      assert {:ok, []} = OHLCV.normalize([])
    end

    test "multi-candle input with various orderings" do
      candles = [
        [1_704_153_720_000, 42_200.0, 42_700.0, 42_100.0, 42_500.0, 600.0],
        [1_704_153_600_000, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0],
        [1_704_153_660_000, 42_100.0, 42_600.0, 42_000.0, 42_400.0, 800.0]
      ]

      assert {:ok, bars} = OHLCV.normalize(candles)
      assert length(bars) == 3
      timestamps = Enum.map(bars, & &1.timestamp)
      assert timestamps == Enum.sort(timestamps)
    end

    test "integer OHLCV values are promoted to float" do
      candles = [[1_704_153_600_000, 42_000, 42_500, 41_500, 42_100, 1000]]

      assert {:ok, [%OHLCVBar{} = bar]} = OHLCV.normalize(candles)
      assert is_float(bar.open)
      assert is_float(bar.high)
      assert is_float(bar.low)
      assert is_float(bar.close)
      assert is_float(bar.volume)
    end

    test "non-list element in candles returns error" do
      candles = [%{"timestamp" => 1_704_153_600_000}]

      assert {:error, {:expected_candle_list, _}} = OHLCV.normalize(candles)
    end

    test "invalid timestamp (non-numeric string) returns error" do
      candles = [["not-a-number", 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0]]

      assert {:error, {:invalid_timestamp, "not-a-number"}} = OHLCV.normalize(candles)
    end
  end

  # -- normalize/1 columnar format ---------------------------------------------

  describe "normalize/1 columnar format" do
    test "pivots columnar map to row-based OHLCV bars (Deribit-style)" do
      data = %{
        "ticks" => [1_704_153_600_000, 1_704_153_660_000],
        "open" => [42_000.0, 42_100.0],
        "high" => [42_500.0, 42_600.0],
        "low" => [41_500.0, 42_000.0],
        "close" => [42_100.0, 42_400.0],
        "volume" => [1000.0, 800.0]
      }

      assert {:ok, [bar1, bar2]} = OHLCV.normalize(data)
      assert bar1.timestamp == 1_704_153_600_000
      assert bar1.open == 42_000.0
      assert bar1.close == 42_100.0
      assert bar2.timestamp == 1_704_153_660_000
      assert bar2.open == 42_100.0
    end

    test "returns error for missing required columns" do
      data = %{
        "ticks" => [1_704_153_600_000],
        "open" => [42_000.0]
        # missing high, low, close, volume
      }

      assert {:error, {:missing_ohlcv_columns, missing}} = OHLCV.normalize(data)
      assert "high" in missing
      assert "low" in missing
      assert "close" in missing
      assert "volume" in missing
    end

    test "returns error for mismatched column lengths" do
      data = %{
        "ticks" => [1_704_153_600_000, 1_704_153_660_000],
        "open" => [42_000.0],
        "high" => [42_500.0, 42_600.0],
        "low" => [41_500.0, 42_000.0],
        "close" => [42_100.0, 42_400.0],
        "volume" => [1000.0, 800.0]
      }

      assert {:error, {:mismatched_ohlcv_column_lengths, _pairs}} = OHLCV.normalize(data)
    end

    test "empty map without OHLCV keys returns invalid format error" do
      assert {:error, {:invalid_ohlcv_format, _}} = OHLCV.normalize(%{})
    end

    test "map with unrelated keys returns invalid format error" do
      assert {:error, {:invalid_ohlcv_format, _}} = OHLCV.normalize(%{"foo" => "bar"})
    end

    test "nil column value returns error instead of raising" do
      data = %{
        "ticks" => [1],
        "open" => nil,
        "high" => [1],
        "low" => [1],
        "close" => [1],
        "volume" => [1]
      }

      assert {:error, {:invalid_ohlcv_column_type, bad}} = OHLCV.normalize(data)
      assert {"open", "nil"} in bad
    end

    test "single-candle columnar format works" do
      data = %{
        "ticks" => [1_704_153_600_000],
        "open" => [42_000.0],
        "high" => [42_500.0],
        "low" => [41_500.0],
        "close" => [42_100.0],
        "volume" => [1000.0]
      }

      assert {:ok, [%OHLCVBar{} = bar]} = OHLCV.normalize(data)
      assert bar.timestamp == 1_704_153_600_000
      assert bar.volume == 1000.0
    end
  end

  # -- OHLCVBar.from_list/1 ---------------------------------------------------

  describe "OHLCVBar.from_list/1" do
    test "builds struct from 6-element list" do
      bar = OHLCVBar.from_list([1_704_153_600_000, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0])

      assert %OHLCVBar{} = bar
      assert bar.timestamp == 1_704_153_600_000
      assert bar.open == 42_000.0
      assert bar.close == 42_100.0
    end
  end

  # -- to_tradingview/1 --------------------------------------------------------

  describe "to_tradingview/1" do
    test "converts bars to TradingView format with seconds timestamps" do
      bars = [
        %OHLCVBar{
          timestamp: 1_704_153_600_000,
          open: 42_000.0,
          high: 42_500.0,
          low: 41_500.0,
          close: 42_100.0,
          volume: 1000.0
        }
      ]

      assert [tv] = OHLCV.to_tradingview(bars)
      assert tv.time == 1_704_153_600
      assert tv.open == 42_000.0
      assert tv.high == 42_500.0
      assert tv.low == 41_500.0
      assert tv.close == 42_100.0
      assert tv.volume == 1000.0
    end

    test "empty list returns empty list" do
      assert [] = OHLCV.to_tradingview([])
    end

    test "multiple bars preserve order" do
      bars = [
        %OHLCVBar{
          timestamp: 1_704_153_600_000,
          open: 42_000.0,
          high: 42_500.0,
          low: 41_500.0,
          close: 42_100.0,
          volume: 1000.0
        },
        %OHLCVBar{
          timestamp: 1_704_153_660_000,
          open: 42_100.0,
          high: 42_600.0,
          low: 42_000.0,
          close: 42_400.0,
          volume: 800.0
        }
      ]

      assert [tv1, tv2] = OHLCV.to_tradingview(bars)
      assert tv1.time == 1_704_153_600
      assert tv2.time == 1_704_153_660
    end
  end

  # -- to_lightweight_charts/1 ------------------------------------------------

  describe "to_lightweight_charts/1" do
    test "same output as TradingView" do
      bars = [
        %OHLCVBar{
          timestamp: 1_704_153_600_000,
          open: 42_000.0,
          high: 42_500.0,
          low: 41_500.0,
          close: 42_100.0,
          volume: 1000.0
        }
      ]

      assert OHLCV.to_lightweight_charts(bars) == OHLCV.to_tradingview(bars)
    end
  end

  # -- to_adapter/2 -----------------------------------------------------------

  describe "to_adapter/2" do
    test "custom SciChart-style adapter returns tuples" do
      bars = [
        %OHLCVBar{
          timestamp: 1_704_153_600_000,
          open: 42_000.0,
          high: 42_500.0,
          low: 41_500.0,
          close: 42_100.0,
          volume: 1000.0
        }
      ]

      result =
        OHLCV.to_adapter(bars, fn bar ->
          {bar.timestamp, bar.open, bar.high, bar.low, bar.close}
        end)

      assert [{1_704_153_600_000, 42_000.0, 42_500.0, 41_500.0, 42_100.0}] = result
    end

    test "custom adapter with string keys for JSON" do
      bars = [
        %OHLCVBar{
          timestamp: 1_704_153_600_000,
          open: 42_000.0,
          high: 42_500.0,
          low: 41_500.0,
          close: 42_100.0,
          volume: 1000.0
        }
      ]

      result =
        OHLCV.to_adapter(bars, fn bar ->
          %{"t" => bar.timestamp, "c" => bar.close}
        end)

      assert [%{"t" => 1_704_153_600_000, "c" => 42_100.0}] = result
    end

    test "empty list returns empty list" do
      assert [] = OHLCV.to_adapter([], fn bar -> bar.close end)
    end
  end

  # -- ResponseCoercer integration --------------------------------------------

  describe "ResponseCoercer OHLCV integration" do
    test "infer_response_type for fetch_ohlcv returns :ohlcv" do
      assert CCXT.ResponseCoercer.infer_response_type(:fetch_ohlcv) == :ohlcv
    end

    test "coerce with :ohlcv type returns {:ok, [%OHLCVBar{}]}" do
      data = [[1_704_153_600_000, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0]]

      assert {:ok, [%OHLCVBar{}]} = CCXT.ResponseCoercer.coerce(data, :ohlcv, [])
    end

    test "coerce with :ohlcv and malformed data returns {:error, _}" do
      data = [[nil, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0]]

      assert {:error, _} = CCXT.ResponseCoercer.coerce(data, :ohlcv, [])
    end

    test "coerce with normalize: false returns raw data unchanged" do
      data = [[1_704_153_600_000, 42_000.0, 42_500.0, 41_500.0, 42_100.0, 1000.0]]

      assert ^data = CCXT.ResponseCoercer.coerce(data, :ohlcv, normalize: false)
    end

    test "coerce for non-OHLCV types still returns plain values (regression)" do
      data = %{"symbol" => "BTC/USDT", "last" => 42_000.0}
      result = CCXT.ResponseCoercer.coerce(data, :ticker, [])

      assert %CCXT.Types.Ticker{} = result
      refute match?({:ok, _}, result)
      refute match?({:error, _}, result)
    end
  end
end
