defmodule CCXT.Signing.HmacSha256Kucoin do
  @moduledoc """
  HMAC-SHA256 with HMAC-signed passphrase (KuCoin-style).

  Used by: KuCoin, KuCoin Futures, and ~3 other exchanges.

  ## How it works

  1. Create millisecond timestamp
  2. Build payload: `timestamp + method + endpoint + body`
  3. Sign payload with HMAC-SHA256, encode as Base64
  4. **Also sign the passphrase** with HMAC-SHA256, encode as Base64 (v2 API key)
  5. Send all in headers

  ## Configuration

      signing: %{
        pattern: :hmac_sha256_passphrase_signed,
        api_key_header: "KC-API-KEY",
        timestamp_header: "KC-API-TIMESTAMP",
        signature_header: "KC-API-SIGN",
        passphrase_header: "KC-API-PASSPHRASE",
        api_key_version_header: "KC-API-KEY-VERSION",
        api_key_version: "2"                        # "2" = signed passphrase
      }

  ## Special Feature

  KuCoin API v2 requires the passphrase itself to be HMAC-signed:
  `signed_passphrase = base64(hmac_sha256(passphrase, secret))`

  """

  @behaviour CCXT.Signing.Behaviour

  alias CCXT.Credentials
  alias CCXT.Signing

  @doc """
  Signs a request using the HMAC-SHA256 with signed passphrase pattern.
  """
  @impl true
  @spec sign(Signing.request(), Credentials.t(), Signing.config()) :: Signing.signed_request()
  def sign(request, credentials, config) do
    timestamp = to_string(Signing.timestamp_ms())
    method_string = request.method |> Atom.to_string() |> String.upcase()

    # Build path and body
    {endpoint, body} = build_endpoint_and_body(request)

    # Build payload: timestamp + METHOD + endpoint + body
    payload = timestamp <> method_string <> endpoint <> (body || "")

    # Sign the payload
    signature = sign_payload(payload, credentials.secret)

    # Sign the passphrase (v2 API key feature)
    signed_passphrase = sign_passphrase(credentials, config)

    # Build headers
    headers = build_headers(credentials, timestamp, signature, signed_passphrase, config)

    %{
      url: endpoint,
      method: request.method,
      headers: headers,
      body: body
    }
  end

  defp build_endpoint_and_body(%{method: method, path: path, params: params, body: body}) do
    cond do
      method in [:get, :delete] and params != %{} ->
        query = Signing.urlencode_raw(params)
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

  defp sign_payload(payload, secret) do
    payload
    |> Signing.hmac_sha256(secret)
    |> Signing.encode_base64()
  end

  defp sign_passphrase(credentials, config) do
    api_key_version = Map.get(config, :api_key_version, "2")
    passphrase = credentials.password || ""

    if api_key_version == "2" do
      # v2 API keys: passphrase is HMAC-signed
      passphrase
      |> Signing.hmac_sha256(credentials.secret)
      |> Signing.encode_base64()
    else
      # v1 API keys: passphrase sent as-is
      passphrase
    end
  end

  defp build_headers(credentials, timestamp, signature, signed_passphrase, config) do
    api_key_header = Map.get(config, :api_key_header, "KC-API-KEY")
    timestamp_header = Map.get(config, :timestamp_header, "KC-API-TIMESTAMP")
    signature_header = Map.get(config, :signature_header, "KC-API-SIGN")
    passphrase_header = Map.get(config, :passphrase_header, "KC-API-PASSPHRASE")
    version_header = Map.get(config, :api_key_version_header, "KC-API-KEY-VERSION")
    api_key_version = Map.get(config, :api_key_version, "2")

    [
      {api_key_header, credentials.api_key},
      {timestamp_header, timestamp},
      {signature_header, signature},
      {passphrase_header, signed_passphrase},
      {version_header, api_key_version},
      {"Content-Type", "application/json"}
    ]
  end
end
