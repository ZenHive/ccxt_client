defmodule CCXT.Signing.HmacSha384Payload do
  @moduledoc """
  HMAC-SHA384 payload signing pattern (Bitfinex-style).

  Used by: Bitfinex, Gemini, and ~3 other exchanges.

  ## How it works

  1. Build request payload as JSON with path and nonce
  2. Base64-encode the payload
  3. Sign the base64 payload with HMAC-SHA384
  4. Send API key, payload, and signature in headers

  ## Configuration

      signing: %{
        pattern: :hmac_sha384_payload,
        api_key_header: "bfx-apikey",
        signature_header: "bfx-signature",
        nonce_header: "bfx-nonce",
        payload_header: "X-GEMINI-PAYLOAD"   # optional, Gemini-style
      }

  ## Payload Construction (Bitfinex v2)

  ```
  auth = "/api/" + path + nonce + body
  signature = hmac_sha384(auth, secret)
  ```

  ## Payload Construction (Gemini)

  ```
  payload = base64(json({request: path, nonce: nonce, ...params}))
  signature = hmac_sha384(payload, secret)
  ```

  """

  @behaviour CCXT.Signing.Behaviour

  alias CCXT.Credentials
  alias CCXT.Signing

  # Nonce must be unique - use unique_integer for guaranteed uniqueness

  @doc """
  Signs a request using the HMAC-SHA384 payload pattern.
  """
  @impl true
  @spec sign(Signing.request(), Credentials.t(), Signing.config()) :: Signing.signed_request()
  def sign(request, credentials, config) do
    nonce = to_string(generate_nonce())

    case Map.get(config, :variant, :bitfinex) do
      :bitfinex -> sign_bitfinex(request, credentials, config, nonce)
      :gemini -> sign_gemini(request, credentials, config, nonce)
    end
  end

  # Bitfinex v2 style: /api/path + nonce + body
  defp sign_bitfinex(request, credentials, config, nonce) do
    body = encode_body(request.params)
    auth_path = "/api" <> request.path

    # Build auth string: /api/path + nonce + body
    auth = auth_path <> nonce <> body

    # Sign with HMAC-SHA384
    signature = sign_payload(auth, credentials.secret)

    headers = build_bitfinex_headers(credentials, nonce, signature, config)

    %{
      url: request.path,
      method: request.method,
      headers: headers,
      body: body
    }
  end

  # Gemini style: base64 encoded JSON payload in header
  defp sign_gemini(request, credentials, config, nonce) do
    # Build payload with request path and nonce
    payload_map =
      request.params
      |> Map.put("request", request.path)
      |> Map.put("nonce", nonce)

    # Base64 encode the JSON payload
    payload_json = Jason.encode!(payload_map)
    payload_b64 = Signing.encode_base64(payload_json)

    # Sign the base64-encoded payload
    signature = sign_payload(payload_b64, credentials.secret)

    headers = build_gemini_headers(credentials, payload_b64, signature, config)

    %{
      url: request.path,
      method: request.method,
      headers: headers,
      body: nil
    }
  end

  defp generate_nonce do
    :erlang.unique_integer([:positive, :monotonic])
  end

  defp encode_body(params) when params == %{}, do: "{}"
  defp encode_body(params), do: Jason.encode!(params)

  defp sign_payload(data, secret) do
    data
    |> Signing.hmac_sha384(secret)
    |> Signing.encode_hex()
  end

  defp build_bitfinex_headers(credentials, nonce, signature, config) do
    api_key_header = Map.get(config, :api_key_header, "bfx-apikey")
    signature_header = Map.get(config, :signature_header, "bfx-signature")
    nonce_header = Map.get(config, :nonce_header, "bfx-nonce")

    [
      {api_key_header, credentials.api_key},
      {nonce_header, nonce},
      {signature_header, signature},
      {"Content-Type", "application/json"}
    ]
  end

  defp build_gemini_headers(credentials, payload_b64, signature, config) do
    api_key_header = Map.get(config, :api_key_header, "X-GEMINI-APIKEY")
    payload_header = Map.get(config, :payload_header, "X-GEMINI-PAYLOAD")
    signature_header = Map.get(config, :signature_header, "X-GEMINI-SIGNATURE")

    [
      {api_key_header, credentials.api_key},
      {payload_header, payload_b64},
      {signature_header, signature},
      {"Content-Type", "text/plain"}
    ]
  end
end
