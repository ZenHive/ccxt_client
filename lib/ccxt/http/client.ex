defmodule CCXT.HTTP.Client do
  @moduledoc """
  HTTP client for exchange API requests.

  This module wraps Req with signing middleware and telemetry. It provides
  a consistent interface for making signed and unsigned requests to exchanges.

  ## Debug Mode

  Two debug options are available:

  - `config :ccxt_client, :debug, true` - Log exceptions with full stack traces
  - Pass `debug_request: true` to any request - Log full request details before sending

  **Security Warning**: Both modes may log sensitive data including API credentials.
  Only use in development environments. Never enable in production.

  ## Why Manual Query Encoding?

  This module uses `URI.encode_query/1` instead of Req's `:params` step because:

  1. **Signing requires raw params** - Signing patterns need access to params
     before URL encoding to construct the signature string
  2. **Sorted encoding** - Some exchanges require alphabetically sorted params
     for signature verification. The signing module handles this sorting.
  3. **Consistency** - Both public and private requests use the same encoding
     approach, avoiding subtle bugs from different code paths.

  The "manual" encoding is intentional architecture, not technical debt.

  ## Features

  - **Signing middleware** - Automatically signs requests using the pattern library
  - **Telemetry events** - Emits `[:ccxt, :request, :start | :stop | :exception]`
  - **Error normalization** - Converts HTTP/exchange errors to `CCXT.Error` structs
  - **Retry support** - Uses Req's built-in retry with configurable attempts

  ## Usage

      spec = %CCXT.Spec{...}
      credentials = %CCXT.Credentials{api_key: "...", secret: "..."}

      # Signed request (private endpoint)
      {:ok, response} = CCXT.HTTP.Client.request(
        spec,
        :get,
        "/v5/account/wallet-balance",
        params: %{accountType: "UNIFIED"},
        credentials: credentials
      )

      # Unsigned request (public endpoint)
      {:ok, response} = CCXT.HTTP.Client.request(
        spec,
        :get,
        "/v5/market/tickers",
        params: %{category: "spot"}
      )

  ## Telemetry Events

  The following telemetry events are emitted:

  - `[:ccxt, :request, :start]` - Before request
    - Measurements: `%{system_time: integer()}`
    - Metadata: `%{exchange: atom(), method: atom(), path: String.t()}`

  - `[:ccxt, :request, :stop]` - After successful request
    - Measurements: `%{duration: integer()}`
    - Metadata: `%{exchange: atom(), method: atom(), path: String.t(), status: integer()}`
    - Optional: `rate_limit: %CCXT.HTTP.RateLimitInfo{}` when exchange returns rate limit headers

  - `[:ccxt, :request, :exception]` - On error
    - Measurements: `%{duration: integer()}`
    - Metadata: `%{exchange: atom(), method: atom(), path: String.t(), kind: atom(), reason: term()}`

  """

  alias CCXT.CircuitBreaker
  alias CCXT.Credentials
  alias CCXT.Defaults
  alias CCXT.Error
  alias CCXT.HTTP.RateLimiter
  alias CCXT.HTTP.RateLimitHeaders
  alias CCXT.HTTP.RateLimitState
  alias CCXT.Signing
  alias CCXT.Spec

  require Logger

  @default_cost 1
  @html_preview_length 200
  @base_client_key {__MODULE__, :base_client}
  @debug_body_inspect_limit 500

  @typedoc "HTTP response with status, headers, and decoded body"
  @type response_headers :: %{optional(String.t()) => [String.t()]}
  @type response :: %{status: integer(), headers: response_headers(), body: term()}

  @doc """
  Makes an HTTP request to an exchange API.

  ## Parameters

  - `spec` - Exchange specification struct
  - `method` - HTTP method (`:get`, `:post`, `:put`, `:delete`)
  - `path` - API endpoint path (e.g., "/v5/market/tickers")

  ## Options

  - `:params` - Query parameters or request body (default: `%{}`)
  - `:credentials` - `CCXT.Credentials` for authenticated endpoints
  - `:timeout` - Request timeout in milliseconds (default: see `CCXT.Defaults.request_timeout_ms/0`)
  - `:retry` - Retry strategy (default: `:safe_transient` - retries on safe, transient errors)
  - `:cost` - Request weight/cost for rate limiting (default: 1)
  - `:rate_limit` - Override rate limit config (default: uses spec.rate_limits)

  ## Returns

  - `{:ok, response}` - Successful response with `:status`, `:headers`, `:body`
  - `{:error, %CCXT.Error{}}` - Normalized error

  """
  @spec request(Spec.t(), atom(), String.t(), keyword()) ::
          {:ok, response()} | {:error, Error.t()}
  def request(%Spec{} = spec, method, path, opts \\ []) do
    # Note: Param mappings are applied at endpoint level in the generator (endpoints.ex:125)
    # Spec-level mappings caused conflicts (e.g., KuCoin symbol→symbols applied to fetch_ticker)
    params = Keyword.get(opts, :params, %{})
    credentials = Keyword.get(opts, :credentials)
    timeout = Keyword.get(opts, :timeout, Defaults.request_timeout_ms())
    retry = Keyword.get(opts, :retry, Defaults.retry_policy())
    cost = Keyword.get(opts, :cost, @default_cost)
    rate_limit = Keyword.get(opts, :rate_limit, spec.rate_limits)
    # Custom base URL for endpoints using different API sections (e.g., Kraken Futures history)
    custom_base_url = Keyword.get(opts, :base_url)
    # Debug request logging (logs full request details before sending)
    debug_request = Keyword.get(opts, :debug_request, false)
    # Extra opts for testing (e.g., plug: {Req.Test, :stub_name})
    extra_opts =
      Keyword.drop(opts, [:params, :credentials, :timeout, :retry, :cost, :rate_limit, :base_url, :debug_request])

    # exchange_id is pre-computed at compile time by the generator macro
    exchange = spec.exchange_id
    sandbox = credentials && credentials.sandbox

    # Circuit breaker check FIRST: fast fail if exchange is down
    # This must come before rate limiting to avoid consuming capacity for requests
    # that will be rejected anyway
    case CircuitBreaker.check(exchange) do
      :blown ->
        {:error, Error.circuit_open(exchange: exchange)}

      :ok ->
        # Rate limiting: key is {exchange, api_key} for auth, {exchange, :public} for public
        rate_key = build_rate_key(exchange, credentials)
        :ok = RateLimiter.wait_for_capacity(rate_key, rate_limit, cost)

        # Use custom base URL if provided (for endpoints with different API sections),
        # otherwise use spec's default URL (with sandbox support)
        base_url = custom_base_url || Spec.api_url(spec, sandbox || false)

        request_opts = %{
          base_url: base_url,
          timeout: timeout,
          retry: retry,
          extra_opts: extra_opts,
          debug_request: debug_request
        }

        do_request(spec, method, path, params, credentials, request_opts)
    end
  end

  # Performs the actual HTTP request after rate limiting and circuit breaker checks pass
  @doc false
  defp do_request(spec, method, path, params, credentials, request_opts) do
    %{base_url: base_url, timeout: timeout, retry: retry, extra_opts: extra_opts, debug_request: debug_request} =
      request_opts

    exchange = spec.exchange_id
    start_time = System.monotonic_time()

    emit_start(exchange, method, path)

    result =
      try do
        req_opts = build_request(spec, method, path, params, credentials, base_url)
        req_opts = Keyword.merge(req_opts, receive_timeout: timeout, retry: retry)
        req_opts = Keyword.merge(req_opts, extra_opts)

        maybe_log_debug_request(debug_request, exchange, method, req_opts, timeout, retry)

        base_client = get_base_client()

        result = Req.request(base_client, req_opts)

        # Record circuit breaker result using should_melt?/1 logic
        CircuitBreaker.record_result(exchange, result)

        case result do
          {:ok, %Req.Response{status: status, headers: headers, body: body}} ->
            rate_limit_info = maybe_parse_rate_limit(exchange, credentials, headers, spec.rate_limits)
            emit_stop(exchange, method, path, status, start_time, rate_limit_info)
            handle_response(status, headers, body, spec)

          {:error, %Req.TransportError{reason: reason}} ->
            emit_exception(exchange, method, path, :transport, reason, start_time)
            {:error, Error.network_error(message: "Transport error: #{inspect(reason)}", exchange: exchange)}

          {:error, reason} ->
            emit_exception(exchange, method, path, :request, reason, start_time)
            {:error, Error.network_error(message: "Request failed: #{inspect(reason)}", exchange: exchange)}
        end
      rescue
        e ->
          if Application.get_env(:ccxt_client, :debug, false) do
            Logger.error("""
            CCXT request exception:
            Exchange: #{exchange}
            Method: #{method}
            Path: #{path}
            #{Exception.format(:error, e, __STACKTRACE__)}
            """)
          end

          emit_exception(exchange, method, path, :exception, e, start_time)
          # Exceptions trip the circuit breaker
          CircuitBreaker.record_failure(exchange)
          {:error, Error.network_error(message: "Exception: #{Exception.message(e)}", exchange: exchange)}
      end

    result
  end

  @doc """
  Makes a raw HTTP request without signing or error normalization.

  Use this for debugging or when you need full control over the request.

  ## Parameters

  - `method` - HTTP method
  - `url` - Full URL to request
  - `headers` - Request headers
  - `body` - Request body (or nil)

  ## Options

  - `:timeout` - Request timeout in milliseconds

  """
  @spec raw_request(atom(), String.t(), [{String.t(), String.t()}], String.t() | nil, keyword()) ::
          {:ok, response()} | {:error, term()}
  def raw_request(method, url, headers, body, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, Defaults.request_timeout_ms())
    extra_opts = Keyword.delete(opts, :timeout)

    req_opts =
      [
        method: method,
        url: url,
        headers: headers,
        body: body,
        receive_timeout: timeout,
        retry: false
      ] ++ extra_opts

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: resp_body}} ->
        {:ok, %{status: status, headers: resp_headers, body: resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Build request options, applying signing if credentials provided

  @doc false
  # Builds request options for public (unsigned) requests
  defp build_request(spec, method, path, params, nil, base_url) do
    # Public request - no signing
    query_string = if params == %{}, do: "", else: "?" <> URI.encode_query(params)
    url = base_url <> path <> query_string

    # Base headers with Content-Type
    headers = [{"Content-Type", "application/json"}]

    # Apply static headers and user agent from spec.http_config (Task 16d)
    headers = apply_http_config(headers, spec.http_config)

    [
      method: method,
      url: url,
      headers: headers
    ]
  end

  defp build_request(spec, method, path, params, %Credentials{} = credentials, base_url) do
    # Private request - apply signing
    signing_config = spec.signing || %{}
    pattern = Map.get(signing_config, :pattern, :hmac_sha256_headers)

    request = %{
      method: method,
      path: path,
      body: if(method in [:post, :put] && params != %{}, do: Jason.encode!(params)),
      params: params
    }

    signed = Signing.sign(pattern, request, credentials, signing_config)

    url = base_url <> signed.url

    # Apply static headers and user agent from spec.http_config (Task 16d)
    # These are merged after signing to ensure required headers are always present
    headers = apply_http_config(signed.headers, spec.http_config)

    # Apply broker header for volume attribution (Task 100)
    headers = apply_broker_header(headers, signing_config[:broker_config], spec.options)

    body_opts = if signed.body, do: [body: signed.body], else: []

    [
      method: signed.method,
      url: url,
      headers: headers
    ] ++ body_opts
  end

  # Apply static headers and user agent from http_config (Task 16d)
  # Some exchanges require specific headers (partner IDs, API versions) or user agents
  @spec apply_http_config([{String.t(), String.t()}], map() | nil) :: [{String.t(), String.t()}]
  defp apply_http_config(headers, nil), do: headers

  defp apply_http_config(headers, http_config) when is_map(http_config) do
    headers
    |> apply_static_headers(http_config[:headers])
    |> apply_user_agent(http_config[:user_agent])
  end

  # Apply static headers from http_config (e.g., partner IDs, API versions)
  @spec apply_static_headers([{String.t(), String.t()}], map() | nil) :: [{String.t(), String.t()}]
  defp apply_static_headers(headers, nil), do: headers

  defp apply_static_headers(headers, static_headers) when is_map(static_headers) do
    # Convert map to list of tuples and append to existing headers
    static_list = Enum.map(static_headers, fn {k, v} -> {to_string(k), to_string(v)} end)
    headers ++ static_list
  end

  # Apply custom User-Agent from http_config
  @spec apply_user_agent([{String.t(), String.t()}], String.t() | nil) :: [{String.t(), String.t()}]
  defp apply_user_agent(headers, nil), do: headers

  defp apply_user_agent(headers, user_agent) when is_binary(user_agent) do
    # Only add User-Agent if not already present
    if Enum.any?(headers, fn {k, _} -> String.downcase(k) == "user-agent" end) do
      headers
    else
      headers ++ [{"User-Agent", user_agent}]
    end
  end

  # Apply broker header for volume attribution (Task 100)
  # Exchanges inject broker headers for referral program volume tracking.
  # Priority: 1) Application config override, 2) spec.options default from CCXT
  @spec apply_broker_header([{String.t(), String.t()}], map() | nil, map() | nil) ::
          [{String.t(), String.t()}]
  defp apply_broker_header(headers, nil, _options), do: headers

  defp apply_broker_header(headers, broker_config, options) when is_map(broker_config) do
    header_name = broker_config[:header]
    option_key = broker_config[:option_key]

    # Priority 1: Global application config override
    broker_id = Application.get_env(:ccxt_client, :broker_id)

    # Priority 2: Default from spec.options (extracted from CCXT)
    broker_id =
      if is_nil(broker_id) and is_map(options) do
        # Try both string and atom keys since options may have either
        options[option_key] || options[String.to_atom(option_key)]
      else
        broker_id
      end

    if broker_id && header_name do
      headers ++ [{header_name, to_string(broker_id)}]
    else
      headers
    end
  end

  # Handle response, normalizing errors
  # Task 37: Also check for body-level errors in 2xx responses

  @spec handle_response(integer(), response_headers(), term(), Spec.t()) ::
          {:ok, response()} | {:error, Error.t()}
  defp handle_response(status, headers, body, spec) when status >= 200 and status < 300 do
    # First check for HTML responses (indicates geo-blocking or access restriction)
    case detect_html_response(body, headers) do
      {:html, context} ->
        {:error, build_access_restricted_error(status, context, spec.exchange_id)}

      :not_html ->
        # Ensure body is decoded as JSON (some exchanges return text/plain with JSON content)
        decoded_body = ensure_json_decoded(body)

        # Check for body-level errors (many exchanges return HTTP 200 with error in body)
        case check_body_error(
               decoded_body,
               spec.response_error,
               spec.error_codes,
               spec.error_code_details,
               spec.exchange_id
             ) do
          nil -> {:ok, %{status: status, headers: headers, body: decoded_body}}
          error -> {:error, error}
        end
    end
  end

  defp handle_response(status, headers, body, spec) do
    # Check for HTML responses first (403/404 with HTML error pages)
    case detect_html_response(body, headers) do
      {:html, context} ->
        {:error, build_access_restricted_error(status, context, spec.exchange_id)}

      :not_html ->
        # exchange_id is pre-computed at compile time by the generator macro
        error =
          normalize_error(
            status,
            body,
            spec.error_codes,
            spec.error_code_details,
            spec.exchange_id,
            headers
          )

        {:error, error}
    end
  end

  # =============================================================================
  # HTML Response Detection (Geographic/Access Restrictions)
  #
  # When exchanges block access (geo-restrictions, IP blocks, Cloudflare),
  # they often return HTML instead of JSON. This detects such responses
  # and provides clear error messages instead of dumping raw HTML.
  # =============================================================================

  @doc false
  # Detects if response body is HTML (indicates geo-blocking or access restriction)
  @spec detect_html_response(term(), response_headers()) :: {:html, map()} | :not_html
  defp detect_html_response(body, headers) when is_binary(body) do
    content_type = get_content_type(headers)

    cond do
      String.contains?(content_type, "text/html") ->
        {:html, extract_html_context(body)}

      html_body?(body) ->
        {:html, extract_html_context(body)}

      true ->
        :not_html
    end
  end

  defp detect_html_response(_body, _headers), do: :not_html

  # =============================================================================
  # JSON Decoding Fallback
  #
  # Some exchanges return JSON with Content-Type: text/plain (e.g., BitMEX orderBook).
  # Req only auto-decodes when Content-Type is application/json, so we need to
  # handle this case manually.
  # =============================================================================

  @doc false
  # Ensures body is decoded as JSON, handling text/plain responses with JSON content
  @spec ensure_json_decoded(term()) :: term()
  defp ensure_json_decoded(body) when is_map(body) or is_list(body), do: body

  defp ensure_json_decoded(body) when is_binary(body) do
    trimmed = String.trim_leading(body)

    if String.starts_with?(trimmed, "{") or String.starts_with?(trimmed, "[") do
      case Jason.decode(body) do
        {:ok, decoded} -> decoded
        {:error, _} -> body
      end
    else
      body
    end
  end

  defp ensure_json_decoded(body), do: body

  @doc false
  # Checks if body starts with HTML markers
  defp html_body?(body) do
    trimmed = String.trim_leading(body)

    String.starts_with?(trimmed, "<!DOCTYPE") or
      String.starts_with?(trimmed, "<html") or
      String.starts_with?(trimmed, "<HTML") or
      String.starts_with?(trimmed, "<!doctype")
  end

  @doc false
  # Extracts useful context from HTML for error message
  defp extract_html_context(body) do
    %{
      page_title: extract_html_title(body),
      body_preview: String.slice(body, 0, @html_preview_length)
    }
  end

  @doc false
  # Extracts <title> content from HTML
  defp extract_html_title(html) do
    case Regex.run(~r/<title[^>]*>([^<]+)<\/title>/i, html) do
      [_, title] -> String.trim(title)
      _ -> nil
    end
  end

  @doc false
  # Gets Content-Type header value (Req returns headers as %{String.t() => [String.t()]})
  @spec get_content_type(response_headers()) :: String.t()
  defp get_content_type(headers) when is_map(headers) do
    case Map.get(headers, "content-type") do
      [value | _] -> String.downcase(value)
      _ -> ""
    end
  end

  @doc false
  # Builds access restricted error with helpful hints
  @spec build_access_restricted_error(integer(), map(), atom()) :: Error.t()
  defp build_access_restricted_error(status, context, exchange) do
    page_title = context[:page_title]
    preview = context[:body_preview]

    message =
      if page_title do
        "Received HTML page '#{page_title}' instead of JSON API response"
      else
        "Received HTML instead of JSON API response"
      end

    hints = [
      "Verify the API URL is correct (check path_prefix in spec)",
      "Test with curl: curl \"<base_url><path>\" to confirm",
      "Could also be geographic/IP blocking - try VPN if curl works"
    ]

    Error.access_restricted(
      message: message,
      code: status,
      exchange: exchange,
      raw: %{status: status, page_title: page_title, body_preview: preview},
      hints: hints
    )
  end

  # =============================================================================
  # Task 37: Body-level error detection
  #
  # Many exchanges return HTTP 200 with error information in the response body.
  # These functions detect such errors using the spec's response_error config.
  #
  # Pattern types:
  # - :success_code       - Error if code field != expected values (Bybit, OKX)
  # - :error_present      - Error if specific field exists (Gate.io, Deribit)
  # - :error_array        - Error if array field non-empty (Kraken)
  # - :error_field_present - Error if code field exists (Binance)
  # - :success_bool       - Error if boolean field is false
  # =============================================================================

  @spec check_body_error(map() | term(), map() | nil, map(), map(), atom()) :: Error.t() | nil
  defp check_body_error(_body, nil, _error_codes, _error_code_details, _exchange), do: nil
  defp check_body_error(body, _config, _error_codes, _error_code_details, _exchange) when not is_map(body), do: nil

  defp check_body_error(body, config, error_codes, error_code_details, exchange) do
    if body_indicates_error?(body, config) do
      build_body_error(body, config, error_codes, error_code_details, exchange)
    end
  end

  # Check if body indicates an error based on response_error config
  @spec body_indicates_error?(map(), Spec.response_error_config()) :: boolean()
  defp body_indicates_error?(body, %{type: :success_code} = config) do
    field = config[:field]
    success_values = config[:success_values] || []

    # Get the value from body, supporting multiple field names
    value = get_body_value(body, field)

    # Error if field not present or value not in success_values
    # Compare as strings since CCXT does string comparison
    value != nil and to_string(value) not in success_values
  end

  defp body_indicates_error?(body, %{type: :error_present} = config) do
    field = config[:field]
    # Error if the field exists
    get_body_value(body, field) != nil
  end

  defp body_indicates_error?(body, %{type: :error_array} = config) do
    field = config[:field]
    value = get_body_value(body, field)
    # Error if array is non-empty
    is_list(value) and value != []
  end

  defp body_indicates_error?(body, %{type: :error_field_present} = config) do
    field = config[:field]
    # Error if the field exists (success responses don't have this field)
    get_body_value(body, field) != nil
  end

  defp body_indicates_error?(body, %{type: :success_bool} = config) do
    field = config[:field]
    value = get_body_value(body, field)
    # Error if field is false
    value == false
  end

  # Get value from body, supporting single field or list of field names (first match)
  @spec get_body_value(map(), String.t() | [String.t()]) :: term()
  defp get_body_value(body, fields) when is_list(fields) do
    Enum.find_value(fields, fn field -> Map.get(body, field) end)
  end

  defp get_body_value(body, field) when is_binary(field) do
    Map.get(body, field)
  end

  # Build error from body using config's code_field and message_field
  @spec build_body_error(map(), map(), map(), map(), atom()) :: Error.t()
  defp build_body_error(body, config, error_codes, error_code_details, exchange) do
    code = get_error_code_from_body(body, config)
    message = get_error_message_from_body(body, config)

    # Try to map the code to a known error type
    error_type = lookup_error_type(code, error_codes)
    description = lookup_error_description(code, error_code_details)
    build_typed_error(error_type, %{"message" => message}, code, exchange, description)
  end

  # Extract error code from body using config
  @spec get_error_code_from_body(map(), map()) :: term()
  defp get_error_code_from_body(body, %{code_field: code_field}) when not is_nil(code_field) do
    get_body_value(body, code_field)
  end

  defp get_error_code_from_body(body, %{field: field}) do
    # Fall back to the detection field
    get_body_value(body, field)
  end

  # Extract error message from body using config
  @spec get_error_message_from_body(map(), map()) :: String.t()
  defp get_error_message_from_body(body, %{message_field: msg_field}) when not is_nil(msg_field) do
    case get_body_value(body, msg_field) do
      nil -> extract_message(body)
      value when is_list(value) -> Enum.join(value, ", ")
      value -> to_string(value)
    end
  end

  defp get_error_message_from_body(body, _config) do
    extract_message(body)
  end

  # =============================================================================
  # HTTP Status Code Error Normalization
  # =============================================================================

  # Normalize HTTP/exchange errors to CCXT.Error

  defp normalize_error(429, body, _error_codes, _error_code_details, exchange, headers) do
    retry_after = extract_retry_after(headers)

    Error.rate_limited(
      message: extract_message(body),
      retry_after: retry_after,
      exchange: exchange,
      raw: body
    )
  end

  defp normalize_error(401, body, _error_codes, _error_code_details, exchange, _headers) do
    Error.invalid_credentials(
      message: extract_message(body),
      exchange: exchange,
      raw: body
    )
  end

  defp normalize_error(403, body, _error_codes, _error_code_details, exchange, _headers) do
    Error.invalid_credentials(
      message: extract_message(body),
      exchange: exchange,
      raw: body
    )
  end

  defp normalize_error(_status, body, error_codes, error_code_details, exchange, _headers) when is_map(body) do
    code = extract_error_code(body)
    error_type = lookup_error_type(code, error_codes)
    description = lookup_error_description(code, error_code_details)
    build_typed_error(error_type, body, code, exchange, description)
  end

  defp normalize_error(_status, body, _error_codes, _error_code_details, exchange, _headers) do
    Error.exchange_error(extract_message(body), exchange: exchange, raw: body)
  end

  defp extract_error_code(body) do
    body["code"] || body["ret_code"] || body["retCode"] || body["error_code"]
  end

  defp lookup_error_type(nil, _error_codes), do: nil

  defp lookup_error_type(code, error_codes) do
    Map.get(error_codes, code) || Map.get(error_codes, to_string(code))
  end

  defp lookup_error_description(nil, _error_code_details), do: nil

  defp lookup_error_description(code, error_code_details) do
    detail =
      case Map.get(error_code_details, code) do
        nil -> Map.get(error_code_details, to_string(code))
        value -> value
      end

    case detail do
      %{description: description} when is_binary(description) and description != "" -> description
      _other -> nil
    end
  end

  defp build_typed_error(:rate_limited, body, code, exchange, description) do
    message = resolve_error_message(body, description)
    Error.rate_limited(message: message, code: code, exchange: exchange, raw: body)
  end

  defp build_typed_error(:insufficient_balance, body, code, exchange, description) do
    message = resolve_error_message(body, description)
    Error.insufficient_balance(message: message, code: code, exchange: exchange, raw: body)
  end

  defp build_typed_error(:invalid_credentials, body, code, exchange, description) do
    message = resolve_error_message(body, description)
    Error.invalid_credentials(message: message, code: code, exchange: exchange, raw: body)
  end

  defp build_typed_error(:order_not_found, body, code, exchange, description) do
    message = resolve_error_message(body, description)
    Error.order_not_found(message: message, code: code, exchange: exchange, raw: body)
  end

  defp build_typed_error(:invalid_order, body, code, exchange, description) do
    message = resolve_error_message(body, description)
    Error.invalid_order(message: message, code: code, exchange: exchange, raw: body)
  end

  defp build_typed_error(:invalid_parameters, body, code, exchange, description) do
    message = resolve_error_message(body, description)
    Error.invalid_parameters(message: message, code: code, exchange: exchange, raw: body)
  end

  defp build_typed_error(:market_closed, body, code, exchange, description) do
    message = resolve_error_message(body, description)
    Error.market_closed(message: message, code: code, exchange: exchange, raw: body)
  end

  defp build_typed_error(_unknown, body, code, exchange, description) do
    message = resolve_error_message(body, description)
    Error.exchange_error(message, code: code, exchange: exchange, raw: body)
  end

  defp resolve_error_message(body, description) do
    message = extract_message(body)
    augment_message(message, description)
  end

  defp augment_message(message, nil), do: message

  defp augment_message(message, description) do
    cond do
      message == description ->
        message

      message == "Unknown error" ->
        description

      true ->
        "#{message} (#{description})"
    end
  end

  # Safely extracts error message from response body, handling various exchange formats.
  # Some exchanges (e.g., Deribit) return nested error objects in JSON-RPC format
  # where the "message" field is a Map rather than a string - we use inspect/1 for those.
  defp extract_message(body) when is_map(body) do
    case body["message"] || body["msg"] || body["retMsg"] || body["error"] do
      nil -> "Unknown error"
      msg when is_binary(msg) -> msg
      msg -> inspect(msg)
    end
  end

  defp extract_message(body) when is_binary(body), do: body
  defp extract_message(_), do: "Unknown error"

  # Req returns headers as a map: %{String.t() => [String.t()]}
  @spec extract_retry_after(response_headers()) :: non_neg_integer() | nil
  defp extract_retry_after(headers) when is_map(headers) do
    case Map.get(headers, "retry-after") do
      [value | _] -> parse_retry_after(value)
      _ -> nil
    end
  end

  defp parse_retry_after(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, _} -> seconds * 1000
      :error -> nil
    end
  end

  defp parse_retry_after(_), do: nil

  # Build rate limiter key: {exchange, api_key} for auth, {exchange, :public} for public
  @spec build_rate_key(atom(), Credentials.t() | nil) :: RateLimiter.key()
  defp build_rate_key(exchange, nil), do: {exchange, :public}
  defp build_rate_key(exchange, %Credentials{api_key: api_key}), do: {exchange, api_key}

  @doc false
  # Parses rate limit headers from response and stores in ETS.
  # Returns the parsed info (for telemetry enrichment) or nil.
  defp maybe_parse_rate_limit(exchange, credentials, headers, spec_rate_limits) do
    case RateLimitHeaders.parse(exchange, headers, spec_rate_limits) do
      {:ok, info} ->
        rate_key = build_rate_key(exchange, credentials)
        RateLimitState.update(rate_key, info)
        info

      :none ->
        nil
    end
  end

  @doc false
  # Logs full request details when debug_request: true is passed.
  # Uses Logger.info (not debug) since this is opt-in and users explicitly want output.
  defp maybe_log_debug_request(false, _exchange, _method, _req_opts, _timeout, _retry), do: :ok

  defp maybe_log_debug_request(true, exchange, method, req_opts, timeout, retry) do
    Logger.info("""
    [CCXT] Request Debug
    Exchange: #{exchange}
    Method: #{method}
    URL: #{Keyword.get(req_opts, :url)}
    Headers: #{inspect(Keyword.get(req_opts, :headers, []), pretty: true)}
    Body: #{inspect(Keyword.get(req_opts, :body), limit: @debug_body_inspect_limit)}
    Timeout: #{timeout}ms
    Retry: #{inspect(retry)}
    """)
  end

  # Telemetry helpers

  defp emit_start(exchange, method, path) do
    :telemetry.execute(
      [:ccxt, :request, :start],
      %{system_time: System.system_time()},
      %{exchange: exchange, method: method, path: path}
    )
  end

  defp emit_stop(exchange, method, path, status, start_time, rate_limit_info) do
    duration = System.monotonic_time() - start_time

    metadata = %{exchange: exchange, method: method, path: path, status: status}

    metadata =
      if rate_limit_info do
        Map.put(metadata, :rate_limit, rate_limit_info)
      else
        metadata
      end

    :telemetry.execute(
      [:ccxt, :request, :stop],
      %{duration: duration},
      metadata
    )
  end

  defp emit_exception(exchange, method, path, kind, reason, start_time) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:ccxt, :request, :exception],
      %{duration: duration},
      %{exchange: exchange, method: method, path: path, kind: kind, reason: reason}
    )
  end

  # =============================================================================
  # Base Client Caching
  #
  # Reuses a single Req.Request struct across all requests. This avoids
  # rebuilding the client configuration on every request while still allowing
  # per-request overrides (timeout, retry, etc.).
  #
  # Uses :persistent_term for fast reads with rare writes (client is built once).
  # =============================================================================

  @doc false
  # Returns cached Req client, creating it on first call via persistent_term.
  @spec get_base_client() :: Req.Request.t()
  defp get_base_client do
    case :persistent_term.get(@base_client_key, nil) do
      nil ->
        client = build_base_client()
        :persistent_term.put(@base_client_key, client)
        client

      client ->
        client
    end
  end

  @doc false
  # Builds the base Req client with decode_body and compression enabled.
  @spec build_base_client() :: Req.Request.t()
  defp build_base_client do
    Req.new(
      decode_body: true,
      compressed: true,
      # Note: timeout and retry are set per-request, not here
      # This allows per-call overrides
      retry: false
    )
  end
end
