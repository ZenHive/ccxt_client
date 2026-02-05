defmodule CCXT.Test.Generator.Helpers.PublicResponse do
  @moduledoc """
  Public endpoint response validation for generated tests.

  Handles validation of responses from public (unauthenticated) endpoints
  like fetch_ticker, fetch_order_book, fetch_markets, etc.
  """

  import ExUnit.Assertions

  require Logger

  @doc """
  Asserts that a public endpoint response is valid.

  Handles both success and known error cases without hiding failures.
  """
  @spec assert_public_response(term(), atom(), String.t(), String.t() | nil) :: :ok
  def assert_public_response(result, method, exchange_id, symbol) do
    case result do
      {:ok, body} ->
        assert_valid_response_body(body, method)
        log_success(method, exchange_id, symbol, body)
        :ok

      {:error, %CCXT.Error{type: :rate_limited} = error} ->
        # Rate limiting means we couldn't verify the endpoint works.
        # Log prominently but don't fail - this is an infrastructure issue, not a code bug.
        Logger.warning("""
        ⚠️  INCONCLUSIVE: #{method} for #{exchange_id} was rate limited
        Error: #{inspect(error)}
        Re-run tests later or with delays between calls to verify this endpoint.
        """)

        :ok

      {:error, %CCXT.Error{type: :exchange_error, code: code, message: msg}} ->
        # Some exchange errors are expected (e.g., invalid symbol format)
        flunk("""
        Exchange error on #{method} for #{exchange_id}:
        Code: #{inspect(code)}
        Message: #{format_message(msg)}
        Symbol: #{inspect(symbol)}

        This may indicate:
        - Incorrect symbol format for this exchange
        - Endpoint requires additional parameters
        - Exchange API changed
        """)

      {:error, %CCXT.Error{} = error} ->
        flunk("#{method} failed with CCXT error: #{inspect(error)}")

      {:error, reason} ->
        flunk("#{method} failed: #{inspect(reason)}")

      other ->
        flunk("#{method} returned unexpected result: #{inspect(other)}")
    end
  end

  # ============================================================================
  # Response Body Validation
  # ============================================================================

  # Validate response body structure based on method
  defp assert_valid_response_body(body, :fetch_ticker) do
    # Most exchanges return a map with price info
    assert is_map(body) or is_list(body),
           "fetch_ticker should return map or list, got: #{inspect(body)}"
  end

  defp assert_valid_response_body(body, :fetch_tickers) do
    assert is_map(body) or is_list(body), "fetch_tickers should return map or list"
  end

  defp assert_valid_response_body(body, :fetch_order_book) do
    assert is_map(body), "fetch_order_book should return a map"
  end

  defp assert_valid_response_body(body, :fetch_trades) do
    assert is_list(body) or is_map(body), "fetch_trades should return list or map"
  end

  defp assert_valid_response_body(body, :fetch_ohlcv) do
    assert is_list(body) or is_map(body), "fetch_ohlcv should return list or map"
  end

  defp assert_valid_response_body(body, :fetch_markets) do
    assert is_list(body) or is_map(body), "fetch_markets should return list or map"
  end

  defp assert_valid_response_body(body, :fetch_currencies) do
    assert is_map(body) or is_list(body), "fetch_currencies should return map or list"
  end

  defp assert_valid_response_body(_body, _method), do: :ok

  # ============================================================================
  # Success Logging
  # ============================================================================

  # Log success information
  defp log_success(:fetch_ticker, exchange_id, symbol, body) do
    price = extract_price(body)
    Logger.info("#{exchange_id} fetch_ticker(#{symbol}): price=#{price || "N/A"}")
  end

  defp log_success(:fetch_tickers, exchange_id, _symbol, body) do
    count = if is_map(body), do: map_size(body), else: length(List.wrap(body))
    Logger.info("#{exchange_id} fetch_tickers: #{count} tickers")
  end

  defp log_success(:fetch_order_book, exchange_id, symbol, body) do
    bids = extract_list_length(body, ["bids", "b", "bid"])
    asks = extract_list_length(body, ["asks", "a", "ask"])
    Logger.info("#{exchange_id} fetch_order_book(#{symbol}): #{bids} bids, #{asks} asks")
  end

  defp log_success(:fetch_trades, exchange_id, symbol, body) do
    count = if is_list(body), do: length(body), else: 1
    Logger.info("#{exchange_id} fetch_trades(#{symbol}): #{count} trades")
  end

  defp log_success(:fetch_ohlcv, exchange_id, symbol, body) do
    count = if is_list(body), do: length(body), else: 1
    Logger.info("#{exchange_id} fetch_ohlcv(#{symbol}): #{count} candles")
  end

  defp log_success(:fetch_markets, exchange_id, _symbol, body) do
    count = if is_list(body), do: length(body), else: map_size(body)
    Logger.info("#{exchange_id} fetch_markets: #{count} markets")
  end

  defp log_success(:fetch_currencies, exchange_id, _symbol, body) do
    count = if is_map(body), do: map_size(body), else: length(List.wrap(body))
    Logger.info("#{exchange_id} fetch_currencies: #{count} currencies")
  end

  defp log_success(method, exchange_id, symbol, _body) do
    Logger.info("#{exchange_id} #{method}(#{symbol || ""}): success")
  end

  # ============================================================================
  # Data Extraction Helpers
  # ============================================================================

  # Get a field from either a struct (atom keys) or map (string keys).
  # Handles the transition from raw maps to typed structs in Task 149.
  defp get_field(body, key) when is_struct(body) do
    atom_key = safe_to_atom(key)
    if atom_key, do: Map.get(body, atom_key)
  end

  defp get_field(body, key) when is_map(body), do: body[key]
  defp get_field(_, _), do: nil

  # Safely convert string to existing atom, returns nil if atom doesn't exist
  defp safe_to_atom(key) when is_atom(key), do: key

  defp safe_to_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  # Extract price from various response formats (structs or maps)
  defp extract_price(body) when is_struct(body) or is_map(body) do
    get_field(body, "lastPrice") || get_field(body, "last") || get_field(body, "price") ||
      extract_price_from_result_list(body) ||
      extract_price_from_result(body)
  end

  defp extract_price([first | _]) when is_map(first), do: extract_price(first)
  defp extract_price(_), do: nil

  # Safely extract lastPrice from result when result is a map.
  # Some exchanges return result: "success" which is a string - we handle that gracefully.
  defp extract_price_from_result(body) do
    case get_field(body, "result") do
      result when is_map(result) -> get_field(result, "lastPrice")
      _ -> nil
    end
  end

  # Safely extract price from nested result.list structure
  # Checks that result is a map before trying to access nested keys
  # (some exchanges return result: "success" which is a string)
  defp extract_price_from_result_list(body) do
    case get_field(body, "result") do
      result when is_map(result) ->
        case get_field(result, "list") do
          [first | _] when is_map(first) -> get_field(first, "lastPrice")
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # Extract list length from response with various key names.
  # Handles both structs (atom keys) and raw maps (string keys).
  defp extract_list_length(body, keys) when is_struct(body) or is_map(body) do
    Enum.find_value(keys, 0, fn key ->
      case get_field(body, key) do
        list when is_list(list) -> length(list)
        _ -> nil
      end
    end) ||
      extract_list_length_from_result(body, keys)
  end

  defp extract_list_length(_, _), do: 0

  # Safely extract list length from nested result structure.
  # Checks that result is a map before trying to access nested keys
  # (some exchanges return result: "success" which is a string).
  defp extract_list_length_from_result(body, keys) do
    case get_field(body, "result") do
      result when is_map(result) -> find_list_length(result, keys)
      _ -> 0
    end
  end

  # Find list length in a result map by trying multiple key names
  defp find_list_length(result, keys) do
    Enum.find_value(keys, 0, fn key ->
      case get_field(result, key) do
        list when is_list(list) -> length(list)
        _ -> nil
      end
    end)
  end

  # ============================================================================
  # Error Message Formatting
  # ============================================================================

  @doc false
  # Format error message for string interpolation.
  # Safely converts non-string values (Maps, etc.) to strings via inspect.
  defp format_message(msg) when is_binary(msg), do: msg
  defp format_message(msg), do: inspect(msg)
end
