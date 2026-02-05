defmodule CCXT.Signing.HmacSha512Nonce do
  @moduledoc """
  HMAC-SHA512 with nonce signing pattern (Kraken-style).

  Used by: Kraken, Gate.io, and ~20 other exchanges.

  ## How it works

  1. Generate incrementing nonce
  2. Add nonce to request body
  3. Hash: `sha256(nonce + body)`
  4. Concat: `url_bytes + hash`
  5. Sign: `hmac_sha512(concat, base64_decode(secret))`
  6. Encode as Base64

  ## Configuration

      signing: %{
        pattern: :hmac_sha512_nonce,
        api_key_header: "API-Key",
        signature_header: "API-Sign",
        nonce_key: "nonce"
      }

  ## Payload Construction (Kraken-specific)

  ```
  nonce_bytes = nonce.to_string + body
  hash = sha256(nonce_bytes)
  message = url_path_bytes + hash
  signature = base64(hmac_sha512(message, base64_decode(secret)))
  ```

  """

  @behaviour CCXT.Signing.Behaviour

  alias CCXT.Credentials
  alias CCXT.Signing

  # Nonce must be incrementing - use microsecond timestamps for guaranteed uniqueness

  @doc """
  Signs a request using the HMAC-SHA512 with nonce pattern.
  """
  @impl true
  @spec sign(Signing.request(), Credentials.t(), Signing.config()) :: Signing.signed_request()
  def sign(request, credentials, config) do
    nonce = generate_nonce()
    nonce_key = Map.get(config, :nonce_key, "nonce")

    # Build body with nonce
    body_params = Map.put(request.params, nonce_key, nonce)
    body = encode_body(body_params, config)

    # Build the signature
    # Step 1: sha256(nonce_string + body)
    nonce_string = to_string(nonce)
    hash = Signing.sha256(nonce_string <> body)

    # Step 2: Concat URL path bytes with hash
    url_bytes = request.path
    message = url_bytes <> hash

    # Step 3: Decode secret from base64 (Kraken stores secrets as base64)
    secret_decoded = Signing.decode_base64(credentials.secret)

    # Step 4: HMAC-SHA512 and encode as base64
    signature =
      message
      |> Signing.hmac_sha512(secret_decoded)
      |> Signing.encode_base64()

    # Build headers
    headers = build_headers(credentials, signature, config)

    %{
      url: request.path,
      method: request.method,
      headers: headers,
      body: body
    }
  end

  @doc false
  # Generates a timestamp-based nonce for Kraken-style authentication.
  # Uses microseconds for guaranteed uniqueness even in rapid requests.
  # Kraken and similar exchanges expect millisecond timestamps (13+ digits).
  defp generate_nonce do
    System.system_time(:microsecond)
  end

  defp encode_body(params, config) do
    case Map.get(config, :body_encoding, :urlencoded) do
      :urlencoded -> Signing.urlencode(params)
      :json -> Jason.encode!(params)
    end
  end

  defp build_headers(credentials, signature, config) do
    api_key_header = Map.get(config, :api_key_header, "API-Key")
    signature_header = Map.get(config, :signature_header, "API-Sign")

    content_type =
      case Map.get(config, :body_encoding, :urlencoded) do
        :urlencoded -> "application/x-www-form-urlencoded"
        :json -> "application/json"
      end

    [
      {api_key_header, credentials.api_key},
      {signature_header, signature},
      {"Content-Type", content_type}
    ]
  end
end
