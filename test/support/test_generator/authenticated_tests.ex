defmodule CCXT.Test.Generator.AuthenticatedTests do
  @moduledoc """
  Compile-time generation of authenticated endpoint tests.

  This module generates test cases for private endpoints that require API credentials.
  Each test validates that the endpoint returns valid data when proper authentication
  is provided.
  """

  @doc """
  Generates all authenticated endpoint test cases.

  Returns AST for a describe block containing tests for each private method.
  """
  @spec generate(map(), boolean()) :: Macro.t() | nil
  def generate(private_methods, _has_passphrase) when map_size(private_methods) == 0, do: nil

  def generate(private_methods, has_passphrase) do
    test_cases = generate_test_cases(private_methods)

    # Add passphrase tag if required
    passphrase_tag =
      if has_passphrase do
        quote do
          @tag :passphrase
        end
      end

    quote do
      alias CCXT.Test.Generator.Helpers, as: GeneratorHelpers

      describe "authenticated endpoints (requires credentials)" do
        unquote(passphrase_tag)

        (unquote_splicing(test_cases))
      end
    end
  end

  # Generate individual test cases for each authenticated method
  # The private_methods map contains {method => {arity, needs_symbol, read_only, endpoint_params}}
  defp generate_test_cases(private_methods) do
    Enum.map(private_methods, fn {method, {_arity, needs_symbol, _read_only, endpoint_params}} ->
      generate_test_case(method, needs_symbol, endpoint_params)
    end)
  end

  # Generate a test case for fetch_balance
  # Balance endpoints need account type derived from spec (e.g., "UNIFIED" for Bybit)
  # Exchange-level params (accountType) are now in endpoint default_params via extractor enrichment
  defp generate_test_case(:fetch_balance, false, _endpoint_params) do
    quote do
      @tag :authenticated
      test "fetch_balance returns account balances", %{
        exchange_atom: exchange_atom,
        api_url: default_url,
        sandbox_urls: sandbox_urls
      } do
        {api_url, credentials} =
          setup_endpoint_credentials!(:fetch_balance, exchange_atom, default_url, sandbox_urls)

        opts = build_test_opts(:fetch_balance) ++ [base_url: api_url]
        result = @module.fetch_balance(credentials, opts)

        GeneratorHelpers.assert_authenticated_response(
          result,
          :fetch_balance,
          @exchange_id,
          nil,
          @credential_opts
        )
      end
    end
  end

  # Generate a test case for fetch_open_orders
  defp generate_test_case(:fetch_open_orders, true, _endpoint_params) do
    quote do
      @tag :authenticated
      test "fetch_open_orders returns open orders list", %{
        exchange_atom: exchange_atom,
        api_url: default_url,
        sandbox_urls: sandbox_urls
      } do
        {api_url, credentials} =
          setup_endpoint_credentials!(:fetch_open_orders, exchange_atom, default_url, sandbox_urls)

        # Use per-endpoint symbol based on market_type (raw exchange format)
        symbol = test_symbol_for(:fetch_open_orders)

        opts = build_test_opts(:fetch_open_orders) ++ [base_url: api_url]
        # fetch_open_orders(credentials, symbol, since, limit, opts)
        result = @module.fetch_open_orders(credentials, symbol, nil, nil, opts)

        GeneratorHelpers.assert_authenticated_response(
          result,
          :fetch_open_orders,
          @exchange_id,
          symbol,
          @credential_opts
        )
      end
    end
  end

  # Generate a test case for fetch_closed_orders
  defp generate_test_case(:fetch_closed_orders, true, _endpoint_params) do
    quote do
      @tag :authenticated
      test "fetch_closed_orders returns closed orders list", %{
        exchange_atom: exchange_atom,
        api_url: default_url,
        sandbox_urls: sandbox_urls
      } do
        {api_url, credentials} =
          setup_endpoint_credentials!(:fetch_closed_orders, exchange_atom, default_url, sandbox_urls)

        # Use per-endpoint symbol based on market_type (raw exchange format)
        symbol = test_symbol_for(:fetch_closed_orders)

        opts = build_test_opts(:fetch_closed_orders) ++ [base_url: api_url]
        # fetch_closed_orders(credentials, symbol, since, limit, opts)
        result = @module.fetch_closed_orders(credentials, symbol, nil, nil, opts)

        GeneratorHelpers.assert_authenticated_response(
          result,
          :fetch_closed_orders,
          @exchange_id,
          symbol,
          @credential_opts
        )
      end
    end
  end

  # Generate a test case for fetch_my_trades
  defp generate_test_case(:fetch_my_trades, true, _endpoint_params) do
    quote do
      @tag :authenticated
      test "fetch_my_trades returns user trades", %{
        exchange_atom: exchange_atom,
        api_url: default_url,
        sandbox_urls: sandbox_urls
      } do
        {api_url, credentials} =
          setup_endpoint_credentials!(:fetch_my_trades, exchange_atom, default_url, sandbox_urls)

        # Use per-endpoint symbol based on market_type (raw exchange format)
        symbol = test_symbol_for(:fetch_my_trades)

        opts = build_test_opts(:fetch_my_trades) ++ [base_url: api_url]
        # fetch_my_trades(credentials, symbol, since, limit, opts)
        result = @module.fetch_my_trades(credentials, symbol, nil, nil, opts)

        GeneratorHelpers.assert_authenticated_response(
          result,
          :fetch_my_trades,
          @exchange_id,
          symbol,
          @credential_opts
        )
      end
    end
  end

  # Generate a test case for fetch_order
  # Use numeric invalid ID because some exchanges (Binance) require numeric order IDs
  defp generate_test_case(:fetch_order, true, _endpoint_params) do
    quote do
      @tag :authenticated
      test "fetch_order returns order not found for invalid ID", %{
        exchange_atom: exchange_atom,
        api_url: default_url,
        sandbox_urls: sandbox_urls
      } do
        {api_url, credentials} =
          setup_endpoint_credentials!(:fetch_order, exchange_atom, default_url, sandbox_urls)

        opts = build_test_opts(:fetch_order) ++ [base_url: api_url]
        # fetch_order(credentials, order_id, symbol, opts) - use a format-flexible invalid ID
        # Some exchanges use numeric IDs (Binance), others use UUIDs (OKX)
        # Use a large numeric string that most exchanges will accept as a valid format
        # but won't find. For UUID exchanges, this may return "invalid format" which is acceptable.
        # Note: Binance order IDs are 64-bit integers (max ~18 digits). 19 digits causes "malformed".
        invalid_order_id = "123456789012345678"
        result = @module.fetch_order(credentials, invalid_order_id, @test_symbol, opts)

        # This should return an error (order not found or invalid format) or success with nil
        # We're testing the API call works, not that the order exists
        GeneratorHelpers.assert_authenticated_response(
          result,
          :fetch_order,
          @exchange_id,
          @test_symbol,
          @credential_opts,
          allow_not_found: true,
          allow_invalid_order: true
        )
      end
    end
  end

  # Generate a test case for fetch_orders
  defp generate_test_case(:fetch_orders, true, _endpoint_params) do
    quote do
      @tag :authenticated
      test "fetch_orders returns orders list", %{
        exchange_atom: exchange_atom,
        api_url: default_url,
        sandbox_urls: sandbox_urls
      } do
        {api_url, credentials} =
          setup_endpoint_credentials!(:fetch_orders, exchange_atom, default_url, sandbox_urls)

        opts = build_test_opts(:fetch_orders) ++ [base_url: api_url]
        # fetch_orders(credentials, symbol, since, limit, opts)
        result = @module.fetch_orders(credentials, @test_symbol, nil, nil, opts)

        GeneratorHelpers.assert_authenticated_response(
          result,
          :fetch_orders,
          @exchange_id,
          @test_symbol,
          @credential_opts
        )
      end
    end
  end

  # Generate a test case for fetch_deposits
  # Uses endpoint_params from spec to determine correct arity
  # Passes @test_currency for the :code param if present
  defp generate_test_case(:fetch_deposits, false, endpoint_params) do
    # Build args based on actual params from spec
    # Use @test_currency for :code param, nil for others
    args =
      Enum.map(endpoint_params, fn
        :code -> quote(do: @test_currency)
        _ -> nil
      end)

    quote do
      @tag :authenticated
      test "fetch_deposits returns deposit history", %{
        exchange_atom: exchange_atom,
        api_url: default_url,
        sandbox_urls: sandbox_urls
      } do
        {api_url, credentials} =
          setup_endpoint_credentials!(:fetch_deposits, exchange_atom, default_url, sandbox_urls)

        opts = build_test_opts(:fetch_deposits) ++ [base_url: api_url]
        # Dynamic arity based on spec params
        result = apply(@module, :fetch_deposits, [credentials | unquote(args)] ++ [opts])

        GeneratorHelpers.assert_authenticated_response(
          result,
          :fetch_deposits,
          @exchange_id,
          nil,
          @credential_opts
        )
      end
    end
  end

  # Generate a test case for fetch_withdrawals
  # Uses endpoint_params from spec to determine correct arity
  # Passes @test_currency for the :code param if present
  defp generate_test_case(:fetch_withdrawals, false, endpoint_params) do
    # Build args based on actual params from spec
    # Use @test_currency for :code param, nil for others
    args =
      Enum.map(endpoint_params, fn
        :code -> quote(do: @test_currency)
        _ -> nil
      end)

    quote do
      @tag :authenticated
      test "fetch_withdrawals returns withdrawal history", %{
        exchange_atom: exchange_atom,
        api_url: default_url,
        sandbox_urls: sandbox_urls
      } do
        {api_url, credentials} =
          setup_endpoint_credentials!(:fetch_withdrawals, exchange_atom, default_url, sandbox_urls)

        opts = build_test_opts(:fetch_withdrawals) ++ [base_url: api_url]
        # Dynamic arity based on spec params
        result = apply(@module, :fetch_withdrawals, [credentials | unquote(args)] ++ [opts])

        GeneratorHelpers.assert_authenticated_response(
          result,
          :fetch_withdrawals,
          @exchange_id,
          nil,
          @credential_opts
        )
      end
    end
  end

  # Generate a test case for fetch_positions
  # Exchange-level params (category, settleCoin) are now in endpoint default_params via extractor enrichment
  defp generate_test_case(:fetch_positions, false, _endpoint_params) do
    quote do
      @tag :authenticated
      test "fetch_positions returns positions list", %{
        exchange_atom: exchange_atom,
        api_url: default_url,
        sandbox_urls: sandbox_urls
      } do
        {api_url, credentials} =
          setup_endpoint_credentials!(:fetch_positions, exchange_atom, default_url, sandbox_urls)

        opts = build_test_opts(:fetch_positions) ++ [base_url: api_url]
        # fetch_positions(credentials, symbols, opts)
        result = @module.fetch_positions(credentials, nil, opts)

        GeneratorHelpers.assert_authenticated_response(
          result,
          :fetch_positions,
          @exchange_id,
          nil,
          @credential_opts
        )
      end
    end
  end

  # Generate a test case for fetch_position
  # Exchange-level params (category) are now in endpoint default_params via extractor enrichment
  # Uses per-endpoint symbol based on market_type (options use different symbol format)
  # Note: allow_invalid_instrument handles testnet/mainnet symbol differences
  defp generate_test_case(:fetch_position, true, _endpoint_params) do
    quote do
      @tag :authenticated
      test "fetch_position returns position for symbol", %{
        exchange_atom: exchange_atom,
        api_url: default_url,
        sandbox_urls: sandbox_urls
      } do
        {api_url, credentials} =
          setup_endpoint_credentials!(:fetch_position, exchange_atom, default_url, sandbox_urls)

        # Use per-endpoint symbol based on market_type (options use different format)
        symbol = test_symbol_for(:fetch_position)

        opts = build_test_opts(:fetch_position) ++ [base_url: api_url]
        # fetch_position(credentials, symbol, opts)
        result = @module.fetch_position(credentials, symbol, opts)

        GeneratorHelpers.assert_authenticated_response(
          result,
          :fetch_position,
          @exchange_id,
          symbol,
          @credential_opts,
          allow_invalid_instrument: true,
          allow_no_position: true
        )
      end
    end
  end

  # Catch-all clause for unhandled authenticated methods
  # Fails at compile time with actionable message
  defp generate_test_case(method, needs_symbol, _endpoint_params) do
    raise CompileError,
      description: """
      No test generator for authenticated method :#{method} (needs_symbol=#{needs_symbol}).

      Add a generate_test_case/3 clause in #{__MODULE__} to handle this method.

      Example:
        defp generate_test_case(:#{method}, #{needs_symbol}, _endpoint_params) do
          quote do
            @tag :authenticated
            test "#{method} works", %{...} do
              # Implementation
            end
          end
        end
      """
  end
end
