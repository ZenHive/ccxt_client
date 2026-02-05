defmodule CCXT.Signing.HmacSha512Gate do
  @moduledoc """
  HMAC-SHA512 Gate.io-style signing pattern.

  Used by: Gate.io

  ## How it works

  1. Hash the body with SHA512 (empty string if no body)
  2. Generate timestamp (seconds)
  3. Build payload as newline-separated string:
     `METHOD\\npath\\nquery_string\\nbody_hash\\ntimestamp`
  4. Sign with HMAC-SHA512 using raw secret (NOT base64 decoded)
  5. Signature is hex-encoded

  ## Configuration

      signing: %{
        pattern: :hmac_sha512_gate,
        api_key_header: "KEY",
        signature_header: "SIGN",
        timestamp_header: "Timestamp"
      }

  ## Payload Construction

  ```
  method = "GET" or "POST"
  path = "/spot/orders" (with /api/v4 prefix for signing)
  query_string = "currency_pair=BTC_USDT" (sorted, urlencoded)
  body_hash = sha512(body) or sha512("") if no body
  timestamp = unix_seconds

  payload = method + "\\n" + signing_path + "\\n" + query + "\\n" + body_hash + "\\n" + timestamp
  signature = hex(hmac_sha512(payload, secret))
  ```

  """

  @behaviour CCXT.Signing.Behaviour

  alias CCXT.Credentials
  alias CCXT.Signing

  @doc """
  Signs a request using the Gate.io HMAC-SHA512 pattern.
  """
  @impl true
  @spec sign(Signing.request(), Credentials.t(), Signing.config()) :: Signing.signed_request()
  def sign(request, credentials, config) do
    timestamp = Signing.timestamp_seconds()
    timestamp_string = to_string(timestamp)

    # Build query string from params
    query_string = Signing.urlencode(request.params)

    # Hash the body (empty string if no body)
    # Gate.io requires hashing even when body is empty - sha512("") is a valid hash
    body = request.body || ""
    body_hash = hash_sha512(body)

    # Build the signing path (Gate.io uses /api/v4 prefix for signing)
    signing_path = Map.get(config, :signing_path_prefix, "/api/v4") <> request.path

    # Build payload as newline-separated string
    method = request.method |> to_string() |> String.upcase()

    payload = Enum.join([method, signing_path, query_string, body_hash, timestamp_string], "\n")

    # Sign with HMAC-SHA512 (secret is used directly, NOT base64 decoded)
    signature =
      payload
      |> Signing.hmac_sha512(credentials.secret)
      |> Signing.encode_hex()

    # Build URL with query string
    url =
      if query_string == "" do
        request.path
      else
        request.path <> "?" <> query_string
      end

    headers = build_headers(credentials, signature, timestamp_string, config)

    %{
      url: url,
      method: request.method,
      headers: headers,
      # Normalize: empty string body becomes nil in the signed request
      # (the hash was computed above; we don't need to send empty string over the wire)
      body: if(body == "", do: nil, else: body)
    }
  end

  defp hash_sha512(data) do
    :sha512
    |> :crypto.hash(data)
    |> Signing.encode_hex()
  end

  defp build_headers(credentials, signature, timestamp, config) do
    api_key_header = Map.get(config, :api_key_header, "KEY")
    signature_header = Map.get(config, :signature_header, "SIGN")
    timestamp_header = Map.get(config, :timestamp_header, "Timestamp")

    [
      {api_key_header, credentials.api_key},
      {signature_header, signature},
      {timestamp_header, timestamp},
      {"Content-Type", "application/json"}
    ]
  end
end
