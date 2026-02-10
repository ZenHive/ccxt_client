defmodule CCXT.Trading.TradingHelpers.FundingIntegrationTest do
  @moduledoc """
  Integration tests for CCXT.Funding module using real exchange data.

  Uses Bybit to fetch actual funding rates and verify the funding rate
  analysis functions work with real data.

  Note: `fetch_funding_rates` returns raw exchange JSON until Task 169
  (FundingRate Response Coercion) is complete. Tests manually construct
  FundingRate structs from raw data.
  """

  use ExUnit.Case, async: false

  alias CCXT.Trading.Funding
  alias CCXT.Types.FundingRate

  @moduletag :integration
  @moduletag :trading_helpers

  # Symbols to fetch funding rates for (linear perpetuals)
  @test_symbols ["BTC/USDT:USDT", "ETH/USDT:USDT", "SOL/USDT:USDT", "XRP/USDT:USDT", "DOGE/USDT:USDT"]

  setup do
    # Bybit public endpoint - no credentials needed for funding rates
    {:ok, exchange: CCXT.Bybit}
  end

  # Helper to fetch funding rates for multiple symbols
  # fetch_funding_rates(nil) only returns 1 rate on Bybit, so we fetch individually
  # TODO: Remove when Task 169 (FundingRate Response Coercion) is complete
  defp fetch_multiple_funding_rates(exchange, symbols) do
    symbols
    |> Enum.map(fn symbol ->
      case exchange.fetch_funding_rates(symbol) do
        {:ok, raw} -> extract_single_funding_rate(raw, symbol)
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_single_funding_rate(raw_response, symbol) when is_map(raw_response) do
    # fetch_funding_rates returns result.list array with one item
    case get_in(raw_response, ["result", "list"]) do
      [item | _] -> parse_bybit_funding_rate(item, symbol)
      _ -> nil
    end
  end

  defp extract_single_funding_rate(_, _), do: nil

  defp parse_bybit_funding_rate(item, symbol_override) do
    %FundingRate{
      symbol: symbol_override || item["symbol"],
      funding_rate: parse_float(item["fundingRate"]),
      mark_price: parse_float(item["markPrice"]),
      index_price: parse_float(item["indexPrice"]),
      timestamp: parse_int(item["nextFundingTime"]),
      raw: item
    }
  end

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil
  defp parse_float(s) when is_binary(s), do: String.to_float(s)
  defp parse_float(n) when is_number(n), do: n * 1.0

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(s) when is_binary(s), do: String.to_integer(s)
  defp parse_int(n) when is_integer(n), do: n

  describe "with real Bybit funding rates" do
    @tag timeout: 60_000
    test "average/1 calculates mean funding rate", %{exchange: exchange} do
      # Fetch multiple funding rates by querying individual symbols
      rates = fetch_multiple_funding_rates(exchange, @test_symbols)
      valid_rates = Enum.filter(rates, &(not is_nil(&1.funding_rate)))

      assert length(valid_rates) >= 2,
             "Expected at least 2 funding rates, got #{length(valid_rates)} from #{length(@test_symbols)} symbols"

      avg = Funding.average(valid_rates)

      assert is_float(avg)
      # Funding rates are typically small percentages
      assert avg > -0.01 and avg < 0.01
    end

    @tag timeout: 60_000
    test "compare/1 ranks funding rates by rate descending", %{exchange: exchange} do
      rates =
        exchange
        |> fetch_multiple_funding_rates(@test_symbols)
        |> Enum.filter(&(not is_nil(&1.funding_rate)))

      assert length(rates) >= 2,
             "Expected at least 2 funding rates, got #{length(rates)} from #{length(@test_symbols)} symbols"

      compared = Funding.compare(rates)

      assert is_list(compared)
      assert length(compared) == length(rates)

      # Verify sorted descending by rate
      rates_only = Enum.map(compared, & &1.rate)
      assert rates_only == Enum.sort(rates_only, :desc)

      # Each entry should have symbol, rate, and apr
      first = List.first(compared)
      assert is_binary(first.symbol)
      assert is_number(first.rate)
      assert is_number(first.apr)
    end

    @tag timeout: 30_000
    test "favorable?/2 correctly identifies favorable funding", %{exchange: exchange} do
      case exchange.fetch_funding_rates("BTC/USDT:USDT") do
        {:ok, raw_response} when is_map(raw_response) ->
          btc_rate = extract_single_funding_rate(raw_response, "BTC/USDT:USDT")

          assert btc_rate, "Expected to get BTC funding rate"
          assert is_number(btc_rate.funding_rate), "BTC funding rate should be a number"

          # Positive funding = favorable for shorts
          # Negative funding = favorable for longs
          if btc_rate.funding_rate > 0 do
            assert Funding.favorable?(btc_rate, :short) == true
            assert Funding.favorable?(btc_rate, :long) == false
          else
            assert Funding.favorable?(btc_rate, :long) == true
            assert Funding.favorable?(btc_rate, :short) == false
          end

        {:error, reason} ->
          flunk("Failed to fetch BTC funding rate: #{inspect(reason)}")
      end
    end

    @tag timeout: 30_000
    test "annualize/1 converts periodic rate to APR", %{exchange: exchange} do
      case exchange.fetch_funding_rates("ETH/USDT:USDT") do
        {:ok, raw_response} when is_map(raw_response) ->
          eth_rate = extract_single_funding_rate(raw_response, "ETH/USDT:USDT")

          assert eth_rate, "Expected to get ETH funding rate"
          assert is_number(eth_rate.funding_rate), "ETH funding rate should be a number"

          apr = Funding.annualize(eth_rate.funding_rate)

          assert is_float(apr)
          # APR should be ~1095x the 8-hour rate (365 * 3 periods/day)
          expected_multiplier = 365 * 3
          assert_in_delta apr, eth_rate.funding_rate * expected_multiplier, 0.001

        {:error, reason} ->
          flunk("Failed to fetch ETH funding rate: #{inspect(reason)}")
      end
    end

    @tag timeout: 30_000
    test "FundingRate struct fields are populated from raw data", %{exchange: exchange} do
      case exchange.fetch_funding_rates("BTC/USDT:USDT") do
        {:ok, raw_response} when is_map(raw_response) ->
          rate = extract_single_funding_rate(raw_response, "BTC/USDT:USDT")

          assert rate, "Expected to get funding rate"

          # Symbol should be present
          assert is_binary(rate.symbol)

          # Raw data should be present
          assert is_map(rate.raw)

          # Funding rate should be a number (may be negative)
          assert is_number(rate.funding_rate), "Funding rate should be a number"

        {:error, reason} ->
          flunk("Failed to fetch funding rate: #{inspect(reason)}")
      end
    end

    @tag timeout: 60_000
    test "detect_spikes/2 identifies abnormal funding rates", %{exchange: exchange} do
      rates =
        exchange
        |> fetch_multiple_funding_rates(@test_symbols)
        |> Enum.filter(&(not is_nil(&1.funding_rate)))

      assert length(rates) >= 5,
             "Expected at least 5 funding rates, got #{length(rates)} from #{length(@test_symbols)} symbols"

      # detect_spikes requires at least 3 rates
      spikes = Funding.detect_spikes(rates, threshold: 2.0)

      # Result should be a list of {direction, rate} tuples
      assert is_list(spikes)

      Enum.each(spikes, fn {direction, rate} ->
        assert direction in [:high, :low]
        assert %FundingRate{} = rate
      end)
    end

    @tag timeout: 60_000
    test "cumulative/1 sums funding rates", %{exchange: exchange} do
      rates =
        exchange
        |> fetch_multiple_funding_rates(@test_symbols)
        |> Enum.filter(&(not is_nil(&1.funding_rate)))

      assert length(rates) >= 2,
             "Expected at least 2 funding rates, got #{length(rates)} from #{length(@test_symbols)} symbols"

      total = Funding.cumulative(rates)

      assert is_number(total)
      # Sum of funding rates (could be positive or negative)
      expected = rates |> Enum.map(& &1.funding_rate) |> Enum.sum()
      assert_in_delta total, expected, 0.0000001
    end
  end
end
