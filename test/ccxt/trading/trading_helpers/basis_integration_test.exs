defmodule CCXT.Trading.TradingHelpers.BasisIntegrationTest do
  @moduledoc """
  Integration tests for CCXT.Basis module using real exchange data.

  Uses Bybit to fetch spot and perpetual tickers and verify
  the basis calculation functions work with real market data.
  Uses `normalize: false` to get raw ticker maps
  (ResponseTransformer extracts and unwraps the path automatically).
  """

  use ExUnit.Case, async: false

  alias CCXT.Trading.Basis

  @moduletag :integration
  @moduletag :trading_helpers

  setup do
    # Bybit public endpoint - no credentials needed for tickers
    {:ok, exchange: CCXT.Bybit}
  end

  # Helper to extract last price from ticker response
  # ResponseTransformer extracts path and unwraps single items automatically,
  # so with normalize: false the response IS the ticker map.
  defp extract_last_price(%{"lastPrice" => price}) when is_binary(price), do: parse_float(price)
  defp extract_last_price(_), do: nil

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_float(_), do: nil

  describe "with real Bybit spot and perp tickers" do
    @tag timeout: 30_000
    test "spot_perp/2 calculates basis from real prices", %{exchange: exchange} do
      with {:ok, spot_ticker} <- exchange.fetch_ticker("BTC/USDT", normalize: false),
           {:ok, perp_ticker} <- exchange.fetch_ticker("BTC/USDT:USDT", normalize: false) do
        spot_price = extract_last_price(spot_ticker)
        perp_price = extract_last_price(perp_ticker)

        if spot_price && perp_price do
          result = Basis.spot_perp(spot_price, perp_price)

          assert is_map(result)
          assert is_number(result.absolute)
          assert is_number(result.percent)
          assert result.direction in [:contango, :backwardation, :flat]

          # Absolute should be perp - spot
          assert_in_delta result.absolute, perp_price - spot_price, 0.01

          # Direction should match sign of absolute
          cond do
            result.absolute > 0 -> assert result.direction == :contango
            result.absolute < 0 -> assert result.direction == :backwardation
            true -> assert result.direction == :flat
          end
        else
          flunk("Tickers missing 'last' price")
        end
      else
        {:error, reason} ->
          flunk("Failed to fetch tickers: #{inspect(reason)}")
      end
    end

    @tag timeout: 30_000
    test "implied_funding/3 calculates implied rate from basis", %{exchange: exchange} do
      with {:ok, spot_ticker} <- exchange.fetch_ticker("ETH/USDT", normalize: false),
           {:ok, perp_ticker} <- exchange.fetch_ticker("ETH/USDT:USDT", normalize: false) do
        spot_price = extract_last_price(spot_ticker)
        perp_price = extract_last_price(perp_ticker)

        if spot_price && perp_price do
          # Default 8-hour funding interval
          implied_rate = Basis.implied_funding(spot_price, perp_price)

          assert is_float(implied_rate)
          # Implied rate should be small (similar to actual funding rates)
          assert abs(implied_rate) < 0.01

          # Test with custom interval
          implied_rate_4h = Basis.implied_funding(spot_price, perp_price, 4)
          assert is_float(implied_rate_4h)
          # 4h rate should be roughly half the 8h rate (more periods per day = smaller rate per period)
          assert_in_delta implied_rate_4h, implied_rate / 2, abs(implied_rate * 0.1) + 0.0001
        else
          flunk("Tickers missing 'last' price")
        end
      else
        {:error, reason} ->
          flunk("Failed to fetch tickers: #{inspect(reason)}")
      end
    end

    @tag timeout: 30_000
    test "arbitrage_opportunity?/3 detects significant basis", %{exchange: exchange} do
      with {:ok, spot_ticker} <- exchange.fetch_ticker("BTC/USDT", normalize: false),
           {:ok, perp_ticker} <- exchange.fetch_ticker("BTC/USDT:USDT", normalize: false) do
        spot_price = extract_last_price(spot_ticker)
        perp_price = extract_last_price(perp_ticker)

        if spot_price && perp_price do
          # Test with default threshold (0.1%)
          result = Basis.arbitrage_opportunity?(spot_price, perp_price)
          assert is_boolean(result)

          # Test with tighter threshold
          result_tight = Basis.arbitrage_opportunity?(spot_price, perp_price, 0.01)
          assert is_boolean(result_tight)

          # Tighter threshold should be >= to default threshold result
          # (more sensitive means more likely to find opportunity)
          if result do
            assert result_tight
          end
        else
          flunk("Tickers missing 'last' price")
        end
      else
        {:error, reason} ->
          flunk("Failed to fetch tickers: #{inspect(reason)}")
      end
    end

    @tag timeout: 30_000
    test "compare/1 ranks exchanges by basis", %{exchange: exchange} do
      # Simulate comparison with same exchange (different symbols)
      with {:ok, btc_spot} <- exchange.fetch_ticker("BTC/USDT", normalize: false),
           {:ok, btc_perp} <- exchange.fetch_ticker("BTC/USDT:USDT", normalize: false),
           {:ok, eth_spot} <- exchange.fetch_ticker("ETH/USDT", normalize: false),
           {:ok, eth_perp} <- exchange.fetch_ticker("ETH/USDT:USDT", normalize: false) do
        btc_spot_price = extract_last_price(btc_spot)
        btc_perp_price = extract_last_price(btc_perp)
        eth_spot_price = extract_last_price(eth_spot)
        eth_perp_price = extract_last_price(eth_perp)

        if btc_spot_price && btc_perp_price && eth_spot_price && eth_perp_price do
          exchanges = [
            %{exchange: :btc_bybit, spot: btc_spot_price, perp: btc_perp_price},
            %{exchange: :eth_bybit, spot: eth_spot_price, perp: eth_perp_price}
          ]

          compared = Basis.compare(exchanges)

          assert is_list(compared)
          assert length(compared) == 2

          # Should be sorted by basis descending
          bases = Enum.map(compared, & &1.basis)
          assert bases == Enum.sort(bases, :desc)

          # Each entry should have required fields
          Enum.each(compared, fn entry ->
            assert Map.has_key?(entry, :exchange)
            assert is_number(entry.basis)
            assert is_number(entry.basis_pct)
            assert is_number(entry.implied_apr)
          end)
        else
          flunk("Some tickers missing 'last' price")
        end
      else
        {:error, reason} ->
          flunk("Failed to fetch tickers: #{inspect(reason)}")
      end
    end

    @tag timeout: 30_000
    test "annualized/3 calculates annualized yield", %{exchange: exchange} do
      with {:ok, spot_ticker} <- exchange.fetch_ticker("BTC/USDT", normalize: false),
           {:ok, perp_ticker} <- exchange.fetch_ticker("BTC/USDT:USDT", normalize: false) do
        spot_price = extract_last_price(spot_ticker)
        perp_price = extract_last_price(perp_ticker)

        if spot_price && perp_price do
          # Assume 30 days to expiry (simulating a futures contract)
          annualized = Basis.annualized(spot_price, perp_price, 30)

          assert is_float(annualized)
          # Annualized rate should be reasonable (< 100% APR typically)
          # But allow for extreme market conditions
          assert abs(annualized) < 10.0
        else
          flunk("Tickers missing 'last' price")
        end
      else
        {:error, reason} ->
          flunk("Failed to fetch tickers: #{inspect(reason)}")
      end
    end

    @tag timeout: 30_000
    test "futures_curve/2 builds curve from contracts", %{exchange: exchange} do
      case exchange.fetch_ticker("BTC/USDT", normalize: false) do
        {:ok, spot_ticker} ->
          spot_price = extract_last_price(spot_ticker)

          if spot_price do
            # Create synthetic futures data based on spot
            # (Real futures would require fetch_markets to find delivery contracts)
            today = Date.utc_today()

            futures = [
              %{expiry: Date.add(today, 30), price: spot_price * 1.002},
              %{expiry: Date.add(today, 60), price: spot_price * 1.004},
              %{expiry: Date.add(today, 90), price: spot_price * 1.006}
            ]

            curve = Basis.futures_curve(spot_price, futures)

            assert is_list(curve)
            assert length(curve) == 3

            # Should be sorted by expiry
            expiries = Enum.map(curve, & &1.expiry)
            assert expiries == Enum.sort(expiries, Date)

            # Each point should have calculated fields
            Enum.each(curve, fn point ->
              assert %Date{} = point.expiry
              assert is_number(point.price)
              assert is_integer(point.days_to_expiry)
              assert point.days_to_expiry > 0
              assert is_number(point.basis)
              assert is_number(point.basis_pct)
              assert is_number(point.annualized)
            end)
          else
            flunk("Ticker missing 'last' price")
          end

        {:error, reason} ->
          flunk("Failed to fetch ticker: #{inspect(reason)}")
      end
    end
  end
end
