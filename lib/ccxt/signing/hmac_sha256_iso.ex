defmodule CCXT.Signing.HmacSha256Iso do
  @moduledoc """
  HMAC-SHA256 with ISO timestamp and passphrase (OKX-style).

  Used by: OKX, Coinbase, and ~10 other exchanges.

  ## How it works

  1. Create ISO8601 timestamp
  2. Build payload: `timestamp + method + path + body`
  3. Sign with HMAC-SHA256, encode as Base64
  4. Send signature, API key, timestamp, and passphrase in headers

  ## Configuration

      signing: %{
        pattern: :hmac_sha256_iso_passphrase,
        api_key_header: "OK-ACCESS-KEY",
        timestamp_header: "OK-ACCESS-TIMESTAMP",
        signature_header: "OK-ACCESS-SIGN",
        passphrase_header: "OK-ACCESS-PASSPHRASE",
        signature_encoding: :base64
      }

  ## Payload Construction

  `timestamp + METHOD + /path + body`

  Example: `2024-01-15T10:30:00.000ZGET/api/v5/account/balance`

  """

  @behaviour CCXT.Signing.Behaviour

  alias CCXT.Credentials
  alias CCXT.Signing

  @doc """
  Signs a request using the HMAC-SHA256 ISO timestamp + passphrase pattern.
  """
  @impl true
  @spec sign(Signing.request(), Credentials.t(), Signing.config()) :: Signing.signed_request()
  def sign(request, credentials, config) do
    timestamp = Signing.timestamp_iso8601()
    method_string = request.method |> Atom.to_string() |> String.upcase()

    # Build path with query string for GET
    {path, body} = build_path_and_body(request)

    # Build payload: timestamp + METHOD + path + body
    payload = timestamp <> method_string <> path <> (body || "")

    # Sign the payload
    signature = sign_payload(payload, credentials.secret, config)

    # Build headers
    headers = build_headers(credentials, timestamp, signature, config)

    %{
      url: path,
      method: request.method,
      headers: headers,
      body: body
    }
  end

  defp build_path_and_body(%{method: method, path: path, params: params, body: body}) do
    cond do
      method in [:get, :delete] and params != %{} ->
        query = Signing.urlencode(params)
        {path <> "?" <> query, nil}

      method in [:get, :delete] ->
        {path, nil}

      body != nil ->
        {path, body}

      params != %{} ->
        {path, Jason.encode!(params)}

      true ->
        {path, nil}
    end
  end

  defp sign_payload(payload, secret, config) do
    signature_bytes = Signing.hmac_sha256(payload, secret)

    case Map.get(config, :signature_encoding, :base64) do
      :hex -> Signing.encode_hex(signature_bytes)
      :base64 -> Signing.encode_base64(signature_bytes)
    end
  end

  defp build_headers(credentials, timestamp, signature, config) do
    api_key_header = Map.get(config, :api_key_header, "OK-ACCESS-KEY")
    timestamp_header = Map.get(config, :timestamp_header, "OK-ACCESS-TIMESTAMP")
    signature_header = Map.get(config, :signature_header, "OK-ACCESS-SIGN")
    passphrase_header = Map.get(config, :passphrase_header, "OK-ACCESS-PASSPHRASE")

    passphrase = credentials.password || ""

    [
      {api_key_header, credentials.api_key},
      {timestamp_header, timestamp},
      {signature_header, signature},
      {passphrase_header, passphrase},
      {"Content-Type", "application/json"}
    ]
  end
end
