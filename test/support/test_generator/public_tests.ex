defmodule CCXT.Test.Generator.PublicTests do
  @moduledoc """
  Compile-time generation of public endpoint tests.

  This module generates test cases for public endpoints (no authentication required).
  Each test validates that the endpoint returns valid data in the expected format.
  """

  # Default test parameters - avoid magic numbers
  @default_order_book_limit 5
  @default_trades_limit 10
  @default_ohlcv_limit 5

  # Default since offset for endpoints that require timestamps (7 days)
  @default_since_offset_ms to_timeout(week: 1)

  # ===========================================================================
  # Timestamp Unit Note
  # ===========================================================================
  #
  # Users always pass milliseconds. The library converts internally based on
  # ohlcv_timestamp_resolution extracted from each exchange's spec.
  #
  # See: lib/ccxt/extract/timestamp_resolution.ex
  #

  @doc """
  Generates all public endpoint test cases.

  Returns AST for a describe block containing tests for each public method.
  """
  @spec generate(map()) :: Macro.t() | nil
  def generate(public_methods) when map_size(public_methods) == 0, do: nil

  def generate(public_methods) do
    test_cases = generate_test_cases(public_methods)

    quote do
      alias CCXT.Test.Generator.Helpers, as: GeneratorHelpers

      describe "public endpoints (no auth)" do
        (unquote_splicing(test_cases))
      end
    end
  end

  # Generate individual test cases for each public method
  defp generate_test_cases(public_methods) do
    Enum.map(public_methods, fn {method, {_arity, needs_symbol, required_params}} ->
      generate_test_case(method, needs_symbol, required_params)
    end)
  end

  # Generate a test case for fetch_ticker
  defp generate_test_case(:fetch_ticker, true, _required_params) do
    quote do
      @tag :public
      test "fetch_ticker returns market data", %{api_url: default_url, sandbox_urls: sandbox_urls} do
        # Per-endpoint sandbox URL routing for multi-API exchanges
        api_url = sandbox_url_for(:fetch_ticker, sandbox_urls, default_url)
        opts = build_test_opts(:fetch_ticker) ++ [base_url: api_url]
        symbol = test_symbol_for(:fetch_ticker)
        result = @module.fetch_ticker(symbol, opts)

        GeneratorHelpers.assert_public_response(result, :fetch_ticker, @exchange_id, symbol)
      end
    end
  end

  # Generate a test case for fetch_tickers
  defp generate_test_case(:fetch_tickers, false, _required_params) do
    quote do
      @tag :public
      test "fetch_tickers returns multiple tickers", %{api_url: default_url, sandbox_urls: sandbox_urls} do
        # Per-endpoint sandbox URL routing for multi-API exchanges
        api_url = sandbox_url_for(:fetch_tickers, sandbox_urls, default_url)
        opts = build_test_opts(:fetch_tickers) ++ [base_url: api_url]
        result = @module.fetch_tickers(nil, opts)

        GeneratorHelpers.assert_public_response(result, :fetch_tickers, @exchange_id, nil)
      end
    end
  end

  # Generate a test case for fetch_order_book
  defp generate_test_case(:fetch_order_book, true, _required_params) do
    limit = @default_order_book_limit

    quote do
      @tag :public
      test "fetch_order_book returns bids and asks", %{api_url: default_url, sandbox_urls: sandbox_urls} do
        # Per-endpoint sandbox URL routing for multi-API exchanges
        api_url = sandbox_url_for(:fetch_order_book, sandbox_urls, default_url)
        opts = build_test_opts(:fetch_order_book) ++ [base_url: api_url]
        symbol = test_symbol_for(:fetch_order_book)
        # fetch_order_book(symbol, limit, opts)
        result = @module.fetch_order_book(symbol, unquote(limit), opts)

        GeneratorHelpers.assert_public_response(result, :fetch_order_book, @exchange_id, symbol)
      end
    end
  end

  # Generate a test case for fetch_trades
  # Handles required_params: [:since] for exchanges like Deribit
  defp generate_test_case(:fetch_trades, true, required_params) do
    limit = @default_trades_limit
    since_required = :since in required_params
    since_offset = @default_since_offset_ms

    quote do
      @tag :public
      test "fetch_trades returns recent trades", %{api_url: default_url, sandbox_urls: sandbox_urls} do
        # Per-endpoint sandbox URL routing for multi-API exchanges
        api_url = sandbox_url_for(:fetch_trades, sandbox_urls, default_url)
        opts = build_test_opts(:fetch_trades) ++ [base_url: api_url]
        symbol = test_symbol_for(:fetch_trades)

        # Use timestamp if since is required (e.g., Deribit), otherwise nil
        since =
          if unquote(since_required) do
            System.system_time(:millisecond) - unquote(since_offset)
          end

        # fetch_trades(symbol, since, limit, opts)
        result = @module.fetch_trades(symbol, since, unquote(limit), opts)

        GeneratorHelpers.assert_public_response(result, :fetch_trades, @exchange_id, symbol)
      end
    end
  end

  # Generate a test case for fetch_ohlcv
  # Always provides fresh `since` timestamp - stale extraction-time defaults would cause
  # "time range too large" errors on exchanges like Coinbase
  defp generate_test_case(:fetch_ohlcv, true, _required_params) do
    limit = @default_ohlcv_limit

    quote do
      @tag :public
      test "fetch_ohlcv returns candlestick data", %{api_url: default_url, sandbox_urls: sandbox_urls} do
        # Use timeframe extracted from spec (not hardcoded)
        # Pattern match to avoid type comparison warning (compiler knows value at compile time)
        case @default_timeframe do
          nil ->
            flunk("No timeframes extracted from spec for #{@exchange_id}")

          timeframe ->
            # Per-endpoint sandbox URL routing for multi-API exchanges
            api_url = sandbox_url_for(:fetch_ohlcv, sandbox_urls, default_url)
            opts = build_test_opts(:fetch_ohlcv) ++ [base_url: api_url]
            symbol = test_symbol_for(:fetch_ohlcv)
            # Always pass milliseconds - library converts internally based on spec
            since = System.system_time(:millisecond) - @timestamp_lookback_ms
            # fetch_ohlcv(symbol, timeframe, since, limit, opts)
            result = @module.fetch_ohlcv(symbol, timeframe, since, unquote(limit), opts)

            GeneratorHelpers.assert_public_response(result, :fetch_ohlcv, @exchange_id, symbol)
        end
      end
    end
  end

  # Generate a test case for fetch_markets
  defp generate_test_case(:fetch_markets, false, _required_params) do
    quote do
      @tag :public
      test "fetch_markets returns trading pairs", %{api_url: default_url, sandbox_urls: sandbox_urls} do
        # Per-endpoint sandbox URL routing for multi-API exchanges
        api_url = sandbox_url_for(:fetch_markets, sandbox_urls, default_url)
        opts = build_test_opts(:fetch_markets) ++ [base_url: api_url]
        result = @module.fetch_markets(opts)

        GeneratorHelpers.assert_public_response(result, :fetch_markets, @exchange_id, nil)
      end
    end
  end

  # Generate a test case for fetch_currencies
  defp generate_test_case(:fetch_currencies, false, _required_params) do
    quote do
      @tag :public
      test "fetch_currencies returns currency info", %{api_url: default_url, sandbox_urls: sandbox_urls} do
        # Per-endpoint sandbox URL routing for multi-API exchanges
        api_url = sandbox_url_for(:fetch_currencies, sandbox_urls, default_url)
        opts = build_test_opts(:fetch_currencies) ++ [base_url: api_url]
        result = @module.fetch_currencies(opts)

        GeneratorHelpers.assert_public_response(result, :fetch_currencies, @exchange_id, nil)
      end
    end
  end

  # Fallback for unknown methods - FAIL LOUD so we know to implement a test case
  defp generate_test_case(method, needs_symbol, required_params) do
    quote do
      @tag :public
      test "#{unquote(method)} returns data", %{api_url: default_url, sandbox_urls: sandbox_urls} do
        # Per-endpoint sandbox URL routing for multi-API exchanges
        _api_url = sandbox_url_for(unquote(method), sandbox_urls, default_url)

        flunk("""
        No test case implemented for public method: #{unquote(method)}

        Method signature:
          needs_symbol: #{unquote(needs_symbol)}
          required_params: #{inspect(unquote(required_params))}

        Add a test case in CCXT.Test.Generator.PublicTests.generate_test_case/3
        """)
      end
    end
  end
end
