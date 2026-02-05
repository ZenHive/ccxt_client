defmodule CCXT.Signing.HmacSha256Query do
  @moduledoc """
  HMAC-SHA256 query string signing pattern (Binance-style).

  Used by: Binance, MEXC, Huobi, and ~40 other exchanges.

  ## How it works

  1. Add timestamp to query parameters
  2. URL-encode all parameters (sorted alphabetically)
  3. Sign the query string with HMAC-SHA256
  4. Append signature to URL as `&signature=...`
  5. API key sent in header

  ## Configuration

      signing: %{
        pattern: :hmac_sha256_query,
        api_key_header: "X-MBX-APIKEY",
        timestamp_key: "timestamp",        # query param name
        signature_key: "signature",        # appended to query
        recv_window_key: "recvWindow",     # optional
        recv_window: 5000,                 # optional
        signature_encoding: :hex           # or :base64
      }

  ## URL Construction

  For all requests:
  1. Add timestamp and recvWindow to params
  2. Sort and URL-encode: `param1=val1&param2=val2&timestamp=...`
  3. Sign query string
  4. Append: `&signature=...`

  """

  @behaviour CCXT.Signing.Behaviour

  alias CCXT.Credentials
  alias CCXT.Defaults
  alias CCXT.Signing

  @doc """
  Signs a request using the HMAC-SHA256 query string pattern.
  """
  @impl true
  @spec sign(Signing.request(), Credentials.t(), Signing.config()) :: Signing.signed_request()
  def sign(request, credentials, config) do
    timestamp_key = Map.get(config, :timestamp_key, "timestamp")
    signature_key = Map.get(config, :signature_key, "signature")

    # Build params with timestamp
    params = build_params(request.params, timestamp_key, config)

    # Create query string (sorted, URL-encoded)
    query_string = Signing.urlencode(params)

    # Sign the query string
    signature = sign_payload(query_string, credentials.secret, config)

    # Build final URL with signature
    final_query = query_string <> "&" <> signature_key <> "=" <> signature

    # Build URL based on method
    {url, body} =
      case request.method do
        method when method in [:get, :delete] ->
          {request.path <> "?" <> final_query, nil}

        _post_or_put ->
          # For POST, params go in body as form-urlencoded or JSON
          if Map.get(config, :post_as_json, false) do
            {request.path, Jason.encode!(Map.put(params, signature_key, signature))}
          else
            {request.path <> "?" <> final_query, request.body}
          end
      end

    # Build headers
    headers = build_headers(credentials, config)

    %{
      url: url,
      method: request.method,
      headers: headers,
      body: body
    }
  end

  @doc false
  # Builds params with timestamp and optional recvWindow.
  defp build_params(params, timestamp_key, config) do
    params
    |> Map.put(timestamp_key, Signing.timestamp_ms())
    |> maybe_add_recv_window(config)
  end

  @doc false
  # Adds recvWindow only if user provided it OR auto_recv_window is true.
  # Matches CCXT behavior - Binance strictly validates that all sent params are used.
  # sobelow_skip ["DOS.StringToAtom"]
  defp maybe_add_recv_window(params, config) do
    case Map.get(config, :recv_window_key) do
      nil ->
        params

      recv_window_key ->
        # Safe: recv_window_key comes from trusted spec config, not user input
        recv_window_key_atom = String.to_atom(recv_window_key)

        cond do
          has_recv_window?(params, recv_window_key, recv_window_key_atom) ->
            params

          Map.get(config, :auto_recv_window, false) ->
            recv_window = Map.get(config, :recv_window, Defaults.recv_window_ms())
            Map.put(params, recv_window_key, recv_window)

          true ->
            params
        end
    end
  end

  @doc false
  # Checks if params already contains recvWindow (as string or atom key).
  defp has_recv_window?(params, string_key, atom_key) do
    Map.has_key?(params, string_key) or Map.has_key?(params, atom_key)
  end

  @doc false
  # Signs the query string with HMAC-SHA256 and encodes as hex or base64.
  defp sign_payload(query_string, secret, config) do
    signature_bytes = Signing.hmac_sha256(query_string, secret)

    case Map.get(config, :signature_encoding, :hex) do
      :hex -> Signing.encode_hex(signature_bytes)
      :base64 -> Signing.encode_base64(signature_bytes)
    end
  end

  @doc false
  # Builds headers with API key.
  defp build_headers(credentials, config) do
    api_key_header = Map.get(config, :api_key_header, "X-MBX-APIKEY")

    [
      {api_key_header, credentials.api_key},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]
  end
end
