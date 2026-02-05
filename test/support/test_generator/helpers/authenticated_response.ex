defmodule CCXT.Test.Generator.Helpers.AuthenticatedResponse do
  @moduledoc """
  Authenticated endpoint response validation for generated tests.

  Handles validation of responses from private (authenticated) endpoints
  like fetch_balance, fetch_orders, create_order, etc.
  """

  import ExUnit.Assertions

  require Logger

  @doc """
  Asserts that an authenticated endpoint response is valid.

  Handles both success and known error cases without hiding failures.
  Similar to public response handling but with auth-specific error handling.

  ## Options

    * `:allow_not_found` - If true, treats "order not found" errors as acceptable (for fetch_order tests)
    * `:allow_invalid_order` - If true, treats "invalid order format" errors as acceptable (for invalid ID tests)
    * `:allow_invalid_instrument` - If true, treats "invalid instrument/symbol" errors as acceptable (testnet may have fewer instruments)
    * `:allow_no_position` - If true, treats "no position" or empty errors as acceptable (testnet with no open positions)
  """
  @spec assert_authenticated_response(term(), atom(), String.t(), String.t() | nil, keyword(), keyword()) ::
          :ok
  def assert_authenticated_response(result, method, exchange_id, symbol, credential_opts, opts \\ []) do
    allow_opts = %{
      not_found: Keyword.get(opts, :allow_not_found, false),
      invalid_order: Keyword.get(opts, :allow_invalid_order, false),
      invalid_instrument: Keyword.get(opts, :allow_invalid_instrument, false),
      no_position: Keyword.get(opts, :allow_no_position, false)
    }

    context = %{method: method, exchange_id: exchange_id, symbol: symbol, credential_opts: credential_opts}

    handle_auth_result(result, context, allow_opts)
  end

  # ============================================================================
  # Result Handlers
  # ============================================================================

  # Handle successful response
  defp handle_auth_result({:ok, body}, context, _allow_opts) do
    assert_valid_auth_response_body(body, context.method)
    log_auth_success(context.method, context.exchange_id, context.symbol, body)
    :ok
  end

  # Handle rate limiting (inconclusive, not failure)
  defp handle_auth_result({:error, %CCXT.Error{type: :rate_limited} = error}, context, _allow_opts) do
    Logger.warning("""
    ⚠️  INCONCLUSIVE: #{context.method} for #{context.exchange_id} was rate limited
    Error: #{inspect(error)}
    Re-run tests later or with delays between calls to verify this endpoint.
    """)

    :ok
  end

  # Handle expected "not found" or "invalid order" errors when allow_opts permits
  defp handle_auth_result({:error, %CCXT.Error{type: type}}, context, allow_opts)
       when type in [:invalid_order, :order_not_found] do
    if allow_opts.not_found or allow_opts.invalid_order do
      Logger.info("#{context.exchange_id} #{context.method}: order not found (expected for invalid ID test)")
      :ok
    else
      flunk("#{context.method} returned #{type} but this wasn't expected")
    end
  end

  # Handle bad request errors (may indicate invalid order format)
  defp handle_auth_result({:error, %CCXT.Error{type: :bad_request, message: msg}}, context, allow_opts) do
    if allow_opts.invalid_order && message_indicates_invalid_format?(msg) do
      Logger.info("#{context.exchange_id} #{context.method}: invalid order format (expected for invalid ID test)")
      :ok
    else
      flunk("#{context.method} failed with bad request: #{format_message(msg)}")
    end
  end

  # Handle authentication failures
  defp handle_auth_result({:error, %CCXT.Error{type: :invalid_credentials}}, context, _allow_opts) do
    flunk_invalid_credentials(context.exchange_id, context.credential_opts)
  end

  defp handle_auth_result({:error, %CCXT.Error{type: :authentication_error, message: msg}}, context, _allow_opts) do
    flunk_auth_error(context.exchange_id, msg, context.credential_opts)
  end

  defp handle_auth_result({:error, %CCXT.Error{type: :permission_denied, message: msg}}, context, _allow_opts) do
    flunk("""
    Permission denied on #{context.method} for #{context.exchange_id}:
    Message: #{format_message(msg)}

    This may indicate:
    - API key doesn't have required permissions
    - IP whitelist restrictions
    - Account-level restrictions
    """)
  end

  # Handle exchange errors (may contain "not found", "invalid format", "invalid instrument", or "no position")
  defp handle_auth_result({:error, %CCXT.Error{type: :exchange_error, code: code, message: msg}}, context, allow_opts) do
    case check_allowed_exchange_error(msg, allow_opts) do
      {:allowed, reason} ->
        Logger.info("#{context.exchange_id} #{context.method}: #{reason}")
        :ok

      :not_allowed ->
        flunk_exchange_error(context, code, msg)
    end
  end

  # Handle other CCXT errors
  defp handle_auth_result({:error, %CCXT.Error{} = error}, context, _allow_opts) do
    flunk("#{context.method} failed with CCXT error: #{inspect(error)}")
  end

  # Handle non-CCXT errors
  defp handle_auth_result({:error, reason}, context, _allow_opts) do
    flunk("#{context.method} failed: #{inspect(reason)}")
  end

  # Handle unexpected results
  defp handle_auth_result(other, context, _allow_opts) do
    flunk("#{context.method} returned unexpected result: #{inspect(other)}")
  end

  # ============================================================================
  # Allowed Error Checking
  # ============================================================================

  # Check if an exchange error should be allowed based on message and options
  # Returns {:allowed, reason} or :not_allowed
  defp check_allowed_exchange_error(msg, allow_opts) do
    Enum.find_value(allowed_error_checks(), :not_allowed, fn {flag, check_fn, reason} ->
      if Map.get(allow_opts, flag) && check_fn.(msg), do: {:allowed, reason}
    end)
  end

  # Define checks as a function to avoid module attribute ordering issues
  defp allowed_error_checks do
    [
      {:not_found, &message_indicates_not_found?/1, "order not found (expected for invalid ID test)"},
      {:invalid_order, &message_indicates_invalid_format?/1, "invalid order format (expected for invalid ID test)"},
      {:invalid_instrument, &message_indicates_invalid_instrument?/1,
       "instrument not available (testnet may have fewer instruments)"},
      {:no_position, &message_indicates_no_position?/1, "no position (testnet with no open positions)"}
    ]
  end

  # ============================================================================
  # Message Pattern Matching
  # ============================================================================

  # Check if error message indicates "not found"
  # Only matches on binary strings - returns false for nil, Maps, or other types
  defp message_indicates_not_found?(msg) when is_binary(msg) do
    not_found_patterns = [
      ~r/order.*not.*found/i,
      ~r/not.*exist/i,
      ~r/invalid.*order/i,
      ~r/no.*record/i
    ]

    Enum.any?(not_found_patterns, &Regex.match?(&1, msg))
  end

  defp message_indicates_not_found?(_), do: false

  # Check if error message indicates invalid format (for order IDs)
  # Only matches on binary strings - returns false for nil, Maps, or other types
  defp message_indicates_invalid_format?(msg) when is_binary(msg) do
    invalid_format_patterns = [
      ~r/invalid.*format/i,
      ~r/invalid.*id/i,
      ~r/malformed/i,
      ~r/must.*be.*uuid/i,
      ~r/must.*be.*numeric/i,
      ~r/invalid.*parameter/i,
      ~r/invalid.*order.*id/i
    ]

    Enum.any?(invalid_format_patterns, &Regex.match?(&1, msg))
  end

  defp message_indicates_invalid_format?(_), do: false

  # Check if error message indicates invalid instrument/symbol (testnet may have fewer instruments)
  # Handles both binary messages and Map messages (like Deribit's error format)
  defp message_indicates_invalid_instrument?(msg) when is_binary(msg) do
    invalid_instrument_patterns = [
      ~r/invalid.*instrument/i,
      ~r/instrument.*not.*found/i,
      ~r/symbol.*not.*found/i,
      ~r/wrong.*format/i,
      ~r/invalid.*symbol/i,
      ~r/unknown.*instrument/i
    ]

    Enum.any?(invalid_instrument_patterns, &Regex.match?(&1, msg))
  end

  # Handle Map-based error messages (e.g., Deribit returns %{"param" => "instrument_name", "reason" => "wrong format"})
  defp message_indicates_invalid_instrument?(%{"param" => param, "reason" => reason})
       when param in ["instrument_name", "symbol"] and reason in ["wrong format", "not found", "invalid"] do
    true
  end

  defp message_indicates_invalid_instrument?(_), do: false

  # Check if error message indicates "no position" (testnet with no open positions)
  # Also handles empty messages which some exchanges return for missing positions
  defp message_indicates_no_position?(msg) when is_binary(msg) do
    # Empty message is common for "no position" on testnets
    msg == "" ||
      Enum.any?(
        [
          ~r/no.*position/i,
          ~r/position.*not.*found/i,
          ~r/position.*not.*exist/i,
          ~r/position.*empty/i
        ],
        &Regex.match?(&1, msg)
      )
  end

  defp message_indicates_no_position?(nil), do: true
  defp message_indicates_no_position?(_), do: false

  # ============================================================================
  # Response Body Validation
  # ============================================================================

  defp assert_valid_auth_response_body(body, :fetch_balance) do
    assert is_map(body) or is_list(body), "fetch_balance should return map or list"
  end

  defp assert_valid_auth_response_body(body, :fetch_open_orders) do
    assert is_list(body) or is_map(body), "fetch_open_orders should return list or map"
  end

  defp assert_valid_auth_response_body(body, :fetch_closed_orders) do
    assert is_list(body) or is_map(body), "fetch_closed_orders should return list or map"
  end

  defp assert_valid_auth_response_body(body, :fetch_my_trades) do
    assert is_list(body) or is_map(body), "fetch_my_trades should return list or map"
  end

  defp assert_valid_auth_response_body(body, :fetch_order) do
    assert is_map(body) or is_nil(body), "fetch_order should return map or nil"
  end

  defp assert_valid_auth_response_body(body, :fetch_orders) do
    assert is_list(body) or is_map(body), "fetch_orders should return list or map"
  end

  defp assert_valid_auth_response_body(body, :fetch_deposits) do
    assert is_list(body) or is_map(body), "fetch_deposits should return list or map"
  end

  defp assert_valid_auth_response_body(body, :fetch_withdrawals) do
    assert is_list(body) or is_map(body), "fetch_withdrawals should return list or map"
  end

  defp assert_valid_auth_response_body(body, :fetch_positions) do
    assert is_list(body) or is_map(body), "fetch_positions should return list or map"
  end

  defp assert_valid_auth_response_body(body, :fetch_position) do
    assert is_map(body) or is_list(body) or is_nil(body), "fetch_position should return map, list, or nil"
  end

  defp assert_valid_auth_response_body(_body, _method), do: :ok

  # ============================================================================
  # Success Logging
  # ============================================================================

  defp log_auth_success(:fetch_balance, exchange_id, _symbol, body) do
    currencies =
      cond do
        is_map(body) && Map.has_key?(body, "info") -> map_size(body) - 1
        is_map(body) -> map_size(body)
        is_list(body) -> length(body)
        true -> "?"
      end

    Logger.info("#{exchange_id} fetch_balance: #{currencies} currencies")
  end

  defp log_auth_success(:fetch_open_orders, exchange_id, symbol, body) do
    count = if is_list(body), do: length(body), else: 1
    Logger.info("#{exchange_id} fetch_open_orders(#{symbol}): #{count} orders")
  end

  defp log_auth_success(:fetch_closed_orders, exchange_id, symbol, body) do
    count = if is_list(body), do: length(body), else: 1
    Logger.info("#{exchange_id} fetch_closed_orders(#{symbol}): #{count} orders")
  end

  defp log_auth_success(:fetch_my_trades, exchange_id, symbol, body) do
    count = if is_list(body), do: length(body), else: 1
    Logger.info("#{exchange_id} fetch_my_trades(#{symbol}): #{count} trades")
  end

  defp log_auth_success(:fetch_order, exchange_id, symbol, _body) do
    Logger.info("#{exchange_id} fetch_order(#{symbol}): order retrieved")
  end

  defp log_auth_success(:fetch_orders, exchange_id, symbol, body) do
    count = if is_list(body), do: length(body), else: 1
    Logger.info("#{exchange_id} fetch_orders(#{symbol}): #{count} orders")
  end

  defp log_auth_success(:fetch_deposits, exchange_id, _symbol, body) do
    count = if is_list(body), do: length(body), else: 1
    Logger.info("#{exchange_id} fetch_deposits: #{count} deposits")
  end

  defp log_auth_success(:fetch_withdrawals, exchange_id, _symbol, body) do
    count = if is_list(body), do: length(body), else: 1
    Logger.info("#{exchange_id} fetch_withdrawals: #{count} withdrawals")
  end

  defp log_auth_success(:fetch_positions, exchange_id, _symbol, body) do
    count = if is_list(body), do: length(body), else: 1
    Logger.info("#{exchange_id} fetch_positions: #{count} positions")
  end

  defp log_auth_success(:fetch_position, exchange_id, symbol, _body) do
    Logger.info("#{exchange_id} fetch_position(#{symbol}): position retrieved")
  end

  defp log_auth_success(method, exchange_id, nil, _body) do
    Logger.info("#{exchange_id} #{method}(): success")
  end

  defp log_auth_success(method, exchange_id, symbol, _body) do
    Logger.info("#{exchange_id} #{method}(#{symbol}): success")
  end

  # ============================================================================
  # Error Formatting
  # ============================================================================

  # Flunk with exchange error details
  defp flunk_exchange_error(context, code, msg) do
    flunk("""
    Exchange error on #{context.method} for #{context.exchange_id}:
    Code: #{inspect(code)}
    Message: #{format_message(msg)}
    Symbol: #{inspect(context.symbol)}

    This may indicate:
    - Incorrect symbol format for this exchange
    - Endpoint requires additional parameters
    - Exchange API changed
    - Account restrictions
    """)
  end

  # Flunk with helpful message for invalid credentials
  defp flunk_invalid_credentials(exchange_id, credential_opts) do
    testnet = Keyword.get(credential_opts, :testnet, false)
    passphrase = Keyword.get(credential_opts, :passphrase, false)
    url = Keyword.get(credential_opts, :url)

    prefix = String.upcase(exchange_id)
    testnet_part = if testnet, do: "_TESTNET", else: ""

    env_vars =
      if passphrase do
        """
        export #{prefix}#{testnet_part}_API_KEY="your_key"
        export #{prefix}#{testnet_part}_API_SECRET="your_secret"
        export #{prefix}_PASSPHRASE="your_passphrase"
        """
      else
        """
        export #{prefix}#{testnet_part}_API_KEY="your_key"
        export #{prefix}#{testnet_part}_API_SECRET="your_secret"
        """
      end

    url_line = if url, do: "\nGet credentials at: #{url}", else: ""

    flunk("""
    Invalid credentials for #{exchange_id}!

    The API key or secret appears to be invalid.
    Check these environment variables:
    #{String.trim(env_vars)}#{url_line}
    """)
  end

  # Flunk with helpful message for authentication errors
  defp flunk_auth_error(exchange_id, message, credential_opts) do
    passphrase = Keyword.get(credential_opts, :passphrase, false)

    passphrase_hint =
      if passphrase do
        "\n- Missing or incorrect passphrase"
      else
        ""
      end

    flunk("""
    Authentication error for #{exchange_id}:
    Message: #{format_message(message)}

    This may indicate:
    - Invalid API key or secret
    - Expired API key#{passphrase_hint}
    - IP address not whitelisted
    - Timestamp sync issues (check system clock)
    """)
  end

  # ============================================================================
  # Message Formatting
  # ============================================================================

  @doc false
  # Format error message for string interpolation.
  # Safely converts non-string values (Maps, etc.) to strings via inspect.
  defp format_message(msg) when is_binary(msg), do: msg
  defp format_message(msg), do: inspect(msg)
end
