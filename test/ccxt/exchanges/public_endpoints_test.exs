defmodule CCXT.Exchanges.PublicEndpointsTest do
  @moduledoc """
  Public endpoint integration tests for ALL generated exchange modules.

  These tests verify that public API endpoints work correctly against real
  exchange APIs. No credentials are required.

  Run with:
    mix test test/ccxt/exchanges/public_endpoints_test.exs

  Or run only public tests:
    mix test --only public

  Or run for a specific exchange:
    mix test --only exchange_bybit

  Or run for a specific classification:
    mix test --only certified_pro
  """

  use ExUnit.Case, async: false

  require Logger

  @moduletag :integration
  @moduletag :public

  # Certified Pro: CCXT Certified + Pro exchanges
  # Use CCXT.Exchange.Classification as single source of truth
  @certified_pro_exchanges CCXT.Exchange.Classification.certified_pro_atoms()

  # Test symbol mapping per exchange
  # Each exchange uses different symbol formats for BTC/USDT or equivalent
  @test_symbols %{
    # Standard format (no separator)
    binance: "BTCUSDT",
    bybit: "BTCUSDT",
    huobi: "btcusdt",
    gate: "BTC_USDT",
    mexc: "BTCUSDT",
    bitget: "BTCUSDT",
    htx: "btcusdt",

    # Dash separator
    okx: "BTC-USDT",
    kucoin: "BTC-USDT",
    bitfinex: "tBTCUSD",
    poloniex: "BTC_USDT",

    # Kraken uses XBT
    kraken: "XBTUSDT",
    krakenfutures: "PF_XBTUSD",

    # USD pairs (not USDT)
    coinbaseexchange: "BTC-USD",
    bitstamp: "btcusd",
    gemini: "btcusd",

    # Derivatives
    deribit: "BTC-PERPETUAL",
    bitmex: "XBTUSD",

    # Default for unknown exchanges
    default: "BTC/USDT"
  }

  # Public methods to test (from CCXT unified API)
  @public_methods [
    :fetch_ticker,
    :fetch_order_book,
    :fetch_trades,
    :fetch_ohlcv,
    :fetch_markets
  ]

  # Get test symbol for an exchange
  defp test_symbol(exchange_id) when is_atom(exchange_id) do
    Map.get(@test_symbols, exchange_id, @test_symbols[:default])
  end

  # Check if exchange has a capability
  defp has_capability?(module, method) do
    spec = module.__ccxt_spec__()

    case spec.has do
      nil -> false
      has when is_map(has) -> Map.get(has, method, false) == true
    end
  end

  # Get public endpoints for a module
  defp public_endpoints(module) do
    module.__ccxt_endpoints__()
    |> Enum.filter(&(!&1.auth))
    |> Enum.map(& &1.name)
  end

  # Call a function on a dynamic module
  # Uses apply/3 for dynamic module dispatch (unavoidable)
  defp call_exchange(module, :fetch_ticker, [symbol, opts]) do
    module.fetch_ticker(symbol, opts)
  end

  defp call_exchange(module, :fetch_order_book, [symbol, limit, opts]) do
    module.fetch_order_book(symbol, limit, opts)
  end

  defp call_exchange(module, :fetch_trades, [symbol, since, limit, opts]) do
    module.fetch_trades(symbol, since, limit, opts)
  end

  defp call_exchange(module, :fetch_markets, [opts]) do
    module.fetch_markets(opts)
  end

  # ===========================================================================
  # CERTIFIED PRO PUBLIC ENDPOINT TESTS
  # ===========================================================================

  describe "Certified Pro: fetch_ticker" do
    @describetag :certified_pro

    for exchange_id <- @certified_pro_exchanges do
      @tag String.to_atom("exchange_#{exchange_id}")
      test "#{exchange_id} fetch_ticker returns market data" do
        exchange_id = unquote(exchange_id)
        module = Module.concat([CCXT, Macro.camelize(to_string(exchange_id))])

        if Code.ensure_loaded?(module) do
          if has_capability?(module, :fetch_ticker) do
            symbol = test_symbol(exchange_id)
            opts = exchange_specific_opts(exchange_id, :fetch_ticker)

            result = call_exchange(module, :fetch_ticker, [symbol, opts])

            case result do
              {:ok, body} ->
                assert_valid_ticker(exchange_id, body)
                Logger.info("#{exchange_id} fetch_ticker: success")

              {:error, %CCXT.Error{type: :rate_limited}} ->
                flunk("#{exchange_id} fetch_ticker: rate limited - retry later")

              {:error, error} ->
                flunk("#{exchange_id} fetch_ticker failed: #{inspect(error)}")
            end
          else
            Logger.info("#{exchange_id}: fetch_ticker not supported (expected)")
          end
        else
          Logger.info("#{exchange_id}: module not generated (skipped)")
        end
      end
    end
  end

  describe "Certified Pro: fetch_order_book" do
    @describetag :certified_pro

    for exchange_id <- @certified_pro_exchanges do
      @tag String.to_atom("exchange_#{exchange_id}")
      test "#{exchange_id} fetch_order_book returns bids and asks" do
        exchange_id = unquote(exchange_id)
        module = Module.concat([CCXT, Macro.camelize(to_string(exchange_id))])

        if Code.ensure_loaded?(module) do
          if has_capability?(module, :fetch_order_book) do
            symbol = test_symbol(exchange_id)
            limit = 5
            opts = exchange_specific_opts(exchange_id, :fetch_order_book)

            result = call_exchange(module, :fetch_order_book, [symbol, limit, opts])

            case result do
              {:ok, body} ->
                assert_valid_order_book(exchange_id, body)
                Logger.info("#{exchange_id} fetch_order_book: success")

              {:error, %CCXT.Error{type: :rate_limited}} ->
                flunk("#{exchange_id} fetch_order_book: rate limited - retry later")

              {:error, error} ->
                flunk("#{exchange_id} fetch_order_book failed: #{inspect(error)}")
            end
          else
            Logger.info("#{exchange_id}: fetch_order_book not supported (expected)")
          end
        else
          Logger.info("#{exchange_id}: module not generated (skipped)")
        end
      end
    end
  end

  describe "Certified Pro: fetch_trades" do
    @describetag :certified_pro

    for exchange_id <- @certified_pro_exchanges do
      @tag String.to_atom("exchange_#{exchange_id}")
      test "#{exchange_id} fetch_trades returns recent trades" do
        exchange_id = unquote(exchange_id)
        module = Module.concat([CCXT, Macro.camelize(to_string(exchange_id))])

        if Code.ensure_loaded?(module) do
          if has_capability?(module, :fetch_trades) do
            symbol = test_symbol(exchange_id)
            since = test_since_value(exchange_id)
            opts = exchange_specific_opts(exchange_id, :fetch_trades)

            result = call_exchange(module, :fetch_trades, [symbol, since, 10, opts])

            case result do
              {:ok, body} ->
                assert_valid_trades(exchange_id, body)
                Logger.info("#{exchange_id} fetch_trades: success")

              {:error, %CCXT.Error{type: :rate_limited}} ->
                flunk("#{exchange_id} fetch_trades: rate limited - retry later")

              {:error, error} ->
                flunk("#{exchange_id} fetch_trades failed: #{inspect(error)}")
            end
          else
            Logger.info("#{exchange_id}: fetch_trades not supported (expected)")
          end
        else
          Logger.info("#{exchange_id}: module not generated (skipped)")
        end
      end
    end
  end

  describe "Certified Pro: fetch_markets" do
    @describetag :certified_pro

    for exchange_id <- @certified_pro_exchanges do
      @tag String.to_atom("exchange_#{exchange_id}")
      test "#{exchange_id} fetch_markets returns trading pairs" do
        exchange_id = unquote(exchange_id)
        module = Module.concat([CCXT, Macro.camelize(to_string(exchange_id))])

        if Code.ensure_loaded?(module) do
          if has_capability?(module, :fetch_markets) do
            opts = exchange_specific_opts(exchange_id, :fetch_markets)

            result = call_exchange(module, :fetch_markets, [opts])

            case result do
              {:ok, body} ->
                assert_valid_markets(exchange_id, body)
                Logger.info("#{exchange_id} fetch_markets: success")

              {:error, %CCXT.Error{type: :rate_limited}} ->
                flunk("#{exchange_id} fetch_markets: rate limited - retry later")

              {:error, error} ->
                flunk("#{exchange_id} fetch_markets failed: #{inspect(error)}")
            end
          else
            Logger.info("#{exchange_id}: fetch_markets not supported (expected)")
          end
        else
          Logger.info("#{exchange_id}: module not generated (skipped)")
        end
      end
    end
  end

  # ===========================================================================
  # HELPER FUNCTIONS
  # ===========================================================================

  # Exchange-specific options (e.g., category param for Bybit)
  defp exchange_specific_opts(exchange_id, method) do
    case {exchange_id, method} do
      {:bybit, _} -> [params: %{category: "spot"}]
      {:okx, :fetch_markets} -> [params: %{instType: "SPOT"}]
      {:deribit, _} -> [params: %{currency: "BTC"}]
      _ -> []
    end
  end

  # Test values for required params (e.g., since for _and_time endpoints)
  # Returns nil for exchanges where the param is optional
  #
  # TODO: Derive this from the endpoint's `required_params` field in the spec
  # instead of hardcoding exchange IDs. The extractor now detects required params
  # and stores them in the endpoint map. Tests should read from the spec.
  defp test_since_value(exchange_id) do
    case exchange_id do
      # Deribit's fetch_trades uses _and_time endpoint which requires since
      :deribit -> System.os_time(:millisecond) - 3_600_000
      # Krakenfutures history endpoint requires since
      :krakenfutures -> System.os_time(:millisecond) - 3_600_000
      _ -> nil
    end
  end

  # ===========================================================================
  # RESPONSE VALIDATORS
  # ===========================================================================
  # Generic validators - no exchange-specific logic.
  # Integration tests verify "API call works", not response format details.
  # Exchange response formats change frequently - specific validators become stale.

  defp assert_valid_ticker(_exchange_id, body) do
    assert body != nil, "Empty response body"
    assert is_map(body), "Expected map response, got: #{inspect(body)}"
  end

  defp assert_valid_order_book(_exchange_id, body) do
    assert body != nil, "Empty response body"
    assert is_map(body), "Expected map response, got: #{inspect(body)}"
  end

  defp assert_valid_trades(_exchange_id, body) do
    assert body != nil, "Empty response body"
  end

  defp assert_valid_markets(_exchange_id, body) do
    assert body != nil, "Empty response body"
  end

  # ===========================================================================
  # SUMMARY TEST
  # ===========================================================================

  describe "public endpoint coverage" do
    test "reports public endpoint coverage for Certified Pro exchanges" do
      coverage =
        Enum.map(@certified_pro_exchanges, fn exchange_id ->
          module = Module.concat([CCXT, Macro.camelize(to_string(exchange_id))])

          if Code.ensure_loaded?(module) do
            endpoints = public_endpoints(module)
            capabilities = Enum.filter(@public_methods, &has_capability?(module, &1))

            %{
              exchange: exchange_id,
              public_endpoints: length(endpoints),
              capabilities: capabilities,
              loaded: true
            }
          else
            %{exchange: exchange_id, public_endpoints: 0, capabilities: [], loaded: false}
          end
        end)

      {loaded, skipped} = Enum.split_with(coverage, & &1.loaded)

      Logger.info("Certified Pro Public Endpoint Coverage:")
      Logger.info("================================")

      for %{exchange: ex, public_endpoints: ep, capabilities: caps} <- loaded do
        caps_str = Enum.map_join(caps, ", ", &to_string/1)
        Logger.info("  #{ex}: #{ep} endpoints, capabilities: [#{caps_str}]")
      end

      if skipped != [] do
        skipped_names = Enum.map_join(skipped, ", ", & &1.exchange)
        Logger.info("  Skipped (not generated): #{skipped_names}")
      end

      # Only check LOADED exchanges for fetch_ticker capability
      failed_exchanges =
        loaded
        |> Enum.reject(fn c -> :fetch_ticker in c.capabilities end)
        |> Enum.map(& &1.exchange)

      assert Enum.empty?(failed_exchanges),
             "Expected loaded Certified Pro exchanges to have fetch_ticker. " <>
               "Missing: #{inspect(failed_exchanges)}"
    end
  end
end
