defmodule CCXT.Trading.TradingHelpers.VolatilityIntegrationTest do
  @moduledoc """
  Integration tests for CCXT.Volatility module using real exchange data.

  Uses Bybit to fetch OHLCV data and verify volatility calculations
  work with real market data. Uses `normalize: false` to get raw candle
  arrays (ResponseTransformer extracts the path automatically).
  """

  use ExUnit.Case, async: false

  alias CCXT.Trading.Volatility

  @moduletag :integration
  @moduletag :trading_helpers

  setup do
    # Bybit public endpoint - no credentials needed for OHLCV
    {:ok, exchange: CCXT.Bybit}
  end

  # Helper to extract OHLCV list from response
  # ResponseTransformer extracts the path (e.g. ["result", "list"]) automatically,
  # so with normalize: false the response IS the candle list already.
  # OHLCV format: [timestamp, open, high, low, close, volume, turnover]
  defp extract_ohlcv(response) when is_list(response), do: response
  defp extract_ohlcv(_), do: []

  defp parse_close(candle) when is_list(candle) do
    candle |> Enum.at(4) |> parse_float()
  end

  defp parse_high(candle) when is_list(candle) do
    candle |> Enum.at(2) |> parse_float()
  end

  defp parse_low(candle) when is_list(candle) do
    candle |> Enum.at(3) |> parse_float()
  end

  defp parse_open(candle) when is_list(candle) do
    candle |> Enum.at(1) |> parse_float()
  end

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_float(n) when is_number(n), do: n * 1.0
  defp parse_float(_), do: nil

  describe "with real Bybit OHLCV data" do
    @tag timeout: 30_000
    test "realized/2 calculates volatility from closes", %{exchange: exchange} do
      case exchange.fetch_ohlcv("BTC/USDT", "1h", nil, 100, normalize: false) do
        {:ok, raw_response} ->
          ohlcv_list = extract_ohlcv(raw_response)

          if length(ohlcv_list) >= 10 do
            closes = Enum.map(ohlcv_list, &parse_close/1)
            vol = Volatility.realized(closes)

            assert is_float(vol)
            assert vol > 0
            # Daily volatility should be reasonable (not > 100%)
            assert vol < 1.0
          else
            flunk("Expected at least 10 candles, got #{length(ohlcv_list)}")
          end

        {:error, reason} ->
          flunk("Failed to fetch OHLCV: #{inspect(reason)}")
      end
    end

    @tag timeout: 30_000
    test "realized/2 with annualize option", %{exchange: exchange} do
      case exchange.fetch_ohlcv("ETH/USDT", "1h", nil, 100, normalize: false) do
        {:ok, raw_response} ->
          ohlcv_list = extract_ohlcv(raw_response)

          if length(ohlcv_list) >= 10 do
            closes = Enum.map(ohlcv_list, &parse_close/1)

            daily_vol = Volatility.realized(closes)
            annual_vol = Volatility.realized(closes, annualize: true)

            assert is_float(daily_vol)
            assert is_float(annual_vol)
            # Annualized should be higher than daily (sqrt(365) factor)
            assert annual_vol > daily_vol
          else
            flunk("Expected at least 10 candles, got #{length(ohlcv_list)}")
          end

        {:error, reason} ->
          flunk("Failed to fetch OHLCV: #{inspect(reason)}")
      end
    end

    @tag timeout: 30_000
    test "parkinson/2 calculates from high-low range", %{exchange: exchange} do
      case exchange.fetch_ohlcv("BTC/USDT", "1h", nil, 50, normalize: false) do
        {:ok, raw_response} ->
          ohlcv_list = extract_ohlcv(raw_response)

          if length(ohlcv_list) >= 5 do
            # Convert to candle maps with high/low
            candles =
              Enum.map(ohlcv_list, fn candle ->
                %{
                  high: parse_high(candle),
                  low: parse_low(candle)
                }
              end)

            vol = Volatility.parkinson(candles)

            assert is_float(vol)
            assert vol > 0
            # Parkinson volatility should be reasonable
            assert vol < 1.0
          else
            flunk("Expected at least 5 candles, got #{length(ohlcv_list)}")
          end

        {:error, reason} ->
          flunk("Failed to fetch OHLCV: #{inspect(reason)}")
      end
    end

    @tag timeout: 30_000
    test "garman_klass/2 calculates from OHLC data", %{exchange: exchange} do
      case exchange.fetch_ohlcv("BTC/USDT", "1h", nil, 50, normalize: false) do
        {:ok, raw_response} ->
          ohlcv_list = extract_ohlcv(raw_response)

          if length(ohlcv_list) >= 5 do
            # Convert to candle maps with OHLC
            candles =
              Enum.map(ohlcv_list, fn candle ->
                %{
                  open: parse_open(candle),
                  high: parse_high(candle),
                  low: parse_low(candle),
                  close: parse_close(candle)
                }
              end)

            vol = Volatility.garman_klass(candles)

            assert is_float(vol)
            assert vol > 0
            # Garman-Klass should be reasonable
            assert vol < 1.0
          else
            flunk("Expected at least 5 candles, got #{length(ohlcv_list)}")
          end

        {:error, reason} ->
          flunk("Failed to fetch OHLCV: #{inspect(reason)}")
      end
    end

    @tag timeout: 30_000
    test "rolling/3 calculates rolling volatility series", %{exchange: exchange} do
      case exchange.fetch_ohlcv("ETH/USDT", "1h", nil, 100, normalize: false) do
        {:ok, raw_response} ->
          ohlcv_list = extract_ohlcv(raw_response)

          if length(ohlcv_list) >= 20 do
            closes = Enum.map(ohlcv_list, &parse_close/1)

            # 10-period rolling volatility
            rolling_vol = Volatility.rolling(closes, 10)

            assert is_list(rolling_vol)
            # Should have length(prices) - window + 1 values
            expected_len = length(closes) - 10 + 1
            assert length(rolling_vol) == expected_len

            # All values should be positive floats
            Enum.each(rolling_vol, fn vol ->
              assert is_float(vol)
              assert vol > 0
            end)
          else
            flunk("Expected at least 20 candles, got #{length(ohlcv_list)}")
          end

        {:error, reason} ->
          flunk("Failed to fetch OHLCV: #{inspect(reason)}")
      end
    end

    @tag timeout: 30_000
    test "cone/2 calculates volatility at different periods", %{exchange: exchange} do
      case exchange.fetch_ohlcv("BTC/USDT", "1h", nil, 100, normalize: false) do
        {:ok, raw_response} ->
          ohlcv_list = extract_ohlcv(raw_response)

          if length(ohlcv_list) >= 50 do
            closes = Enum.map(ohlcv_list, &parse_close/1)

            # Calculate vol cone at different lookback periods
            cone = Volatility.cone(closes, [10, 20, 30])

            assert is_map(cone)
            assert Map.has_key?(cone, 10)
            assert Map.has_key?(cone, 20)
            assert Map.has_key?(cone, 30)

            # Each value should be a volatility (cone values should not be nil)
            Enum.each(cone, fn {period, vol} ->
              assert vol, "cone returned nil for period #{period}"
              assert is_float(vol)
              assert vol > 0
            end)
          else
            flunk("Expected at least 50 candles, got #{length(ohlcv_list)}")
          end

        {:error, reason} ->
          flunk("Failed to fetch OHLCV: #{inspect(reason)}")
      end
    end

    @tag timeout: 30_000
    test "elevated?/3 detects elevated volatility", %{exchange: exchange} do
      case exchange.fetch_ohlcv("BTC/USDT", "1h", nil, 100, normalize: false) do
        {:ok, raw_response} ->
          ohlcv_list = extract_ohlcv(raw_response)

          assert length(ohlcv_list) >= 50, "Expected at least 50 candles, got #{length(ohlcv_list)}"

          closes = Enum.map(ohlcv_list, &parse_close/1)

          # Get recent and baseline volatility
          recent_vol = Volatility.realized(Enum.take(closes, -10))
          baseline_vol = Volatility.realized(closes)

          assert recent_vol, "realized() returned nil for recent closes"
          assert baseline_vol, "realized() returned nil for baseline closes"

          # Test with default threshold (1.5x)
          result = Volatility.elevated?(recent_vol, baseline_vol)
          assert is_boolean(result)

          # Test with custom threshold
          result2 = Volatility.elevated?(recent_vol, baseline_vol, 2.0)
          assert is_boolean(result2)

        {:error, reason} ->
          flunk("Failed to fetch OHLCV: #{inspect(reason)}")
      end
    end
  end
end
