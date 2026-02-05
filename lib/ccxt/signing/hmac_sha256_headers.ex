defmodule CCXT.Signing.HmacSha256Headers do
  @moduledoc """
  HMAC-SHA256 headers signing pattern (Bybit-style).

  Used by: Bybit, Bitget, Phemex, Poloniex, and ~30 other exchanges.

  ## How it works

  1. Create a payload string: `timestamp + apiKey + recvWindow + body_or_query`
  2. Sign with HMAC-SHA256 using the secret
  3. Add signature and auth headers to request

  ## Configuration

      signing: %{
        pattern: :hmac_sha256_headers,
        api_key_header: "X-BAPI-API-KEY",
        timestamp_header: "X-BAPI-TIMESTAMP",
        signature_header: "X-BAPI-SIGN",
        recv_window_header: "X-BAPI-RECV-WINDOW",  # optional
        recv_window: 5000,                          # optional, default 5000ms
        signature_encoding: :hex                    # or :base64
      }

  ## Payload Construction

  For GET requests: `timestamp + apiKey + recvWindow + queryString`
  For POST requests: `timestamp + apiKey + recvWindow + body`

  """

  @behaviour CCXT.Signing.Behaviour

  alias CCXT.Credentials
  alias CCXT.Defaults
  alias CCXT.Signing

  @doc """
  Signs a request using the HMAC-SHA256 headers pattern.
  """
  @impl true
  @spec sign(Signing.request(), Credentials.t(), Signing.config()) :: Signing.signed_request()
  def sign(request, credentials, config) do
    timestamp = to_string(Signing.timestamp_ms())
    recv_window = config |> Map.get(:recv_window, Defaults.recv_window_ms()) |> to_string()

    # Build the payload to sign
    {query_string, body} = build_query_and_body(request)

    payload =
      case request.method do
        :get -> timestamp <> credentials.api_key <> recv_window <> query_string
        :delete -> timestamp <> credentials.api_key <> recv_window <> query_string
        _post_or_put -> timestamp <> credentials.api_key <> recv_window <> (body || "")
      end

    # Sign the payload
    signature = sign_payload(payload, credentials.secret, config)

    # Build headers
    headers = build_headers(credentials, timestamp, signature, recv_window, config)

    # Build URL
    url =
      case request.method do
        method when method in [:get, :delete] and query_string != "" ->
          request.path <> "?" <> query_string

        _ ->
          request.path
      end

    %{
      url: url,
      method: request.method,
      headers: headers,
      body: body
    }
  end

  defp build_query_and_body(%{params: params, body: body, method: method}) do
    cond do
      method in [:get, :delete] ->
        query_string = Signing.urlencode_raw(params)
        {query_string, nil}

      body != nil ->
        # Body already provided (e.g., JSON string)
        {"", body}

      params != %{} ->
        # Convert params to JSON body
        json_body = Jason.encode!(params)
        {"", json_body}

      true ->
        {"", nil}
    end
  end

  defp sign_payload(payload, secret, config) do
    signature_bytes = Signing.hmac_sha256(payload, secret)

    case Map.get(config, :signature_encoding, :hex) do
      :hex -> Signing.encode_hex(signature_bytes)
      :base64 -> Signing.encode_base64(signature_bytes)
    end
  end

  defp build_headers(credentials, timestamp, signature, recv_window, config) do
    api_key_header = Map.get(config, :api_key_header, "X-BAPI-API-KEY")
    timestamp_header = Map.get(config, :timestamp_header, "X-BAPI-TIMESTAMP")
    signature_header = Map.get(config, :signature_header, "X-BAPI-SIGN")

    headers = [
      {api_key_header, credentials.api_key},
      {timestamp_header, timestamp},
      {signature_header, signature},
      {"Content-Type", "application/json"}
    ]

    # Add recv_window header if configured
    case Map.get(config, :recv_window_header) do
      nil -> headers
      header_name -> [{header_name, recv_window} | headers]
    end
  end
end
