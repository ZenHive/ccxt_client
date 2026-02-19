defmodule CCXT.WS.Auth.InlineSubscribe do
  @moduledoc """
  Inline Subscribe authentication pattern (Coinbase style).

  This pattern includes authentication data directly in subscribe messages
  rather than sending a separate authentication message.

  ## Flow

  1. Connect to WebSocket (no auth message)
  2. Include auth fields (key, timestamp, signature, passphrase) in each private subscribe
  3. Auth is per-subscription, not per-connection

  ## Example Subscribe with Auth (Coinbase)

      %{
        "type" => "subscribe",
        "product_ids" => ["BTC-USD"],
        "channels" => ["level2"],
        "key" => "api_key_here",
        "timestamp" => "1699999999",
        "signature" => "base64_signature",
        "passphrase" => "my_passphrase"
      }

  ## Payload Format (matches CCXT's authenticate())

      timestamp + "GET" + "/users/self/verify"

  The secret is base64-decoded before signing, and the signature is base64-encoded.

  """

  @behaviour CCXT.WS.Auth.Behaviour

  alias CCXT.Signing

  @verify_path "/users/self/verify"

  @impl true
  def pre_auth(_credentials, _config, _opts) do
    {:ok, %{}}
  end

  @impl true
  def build_auth_message(_credentials, _config, _opts) do
    # No standalone auth message - auth is inline with subscribe
    :no_message
  end

  @impl true
  def handle_auth_response(_response, _state) do
    # No standalone auth response
    :ok
  end

  @doc """
  Builds auth data to merge into subscribe messages.

  Matches CCXT's `coinbaseexchange.authenticate()`:
  - Payload: `timestamp + "GET" + "/users/self/verify"`
  - Secret: base64-decoded before HMAC-SHA256
  - Signature: base64-encoded
  - Fields: `key`, `timestamp`, `signature`, `passphrase`
  """
  @impl true
  def build_subscribe_auth(credentials, _config, _channel, _symbols) do
    api_key = credentials.api_key
    secret = credentials.secret
    passphrase = credentials.password

    timestamp = to_string(Signing.timestamp_seconds())
    payload = timestamp <> "GET" <> @verify_path

    # Secret is base64-encoded; decode before signing
    secret_binary = Base.decode64!(secret)
    signature_raw = Signing.hmac_sha256(payload, secret_binary)
    signature = Base.encode64(signature_raw)

    result = %{
      "key" => api_key,
      "timestamp" => timestamp,
      "signature" => signature
    }

    if passphrase, do: Map.put(result, "passphrase", passphrase), else: result
  end
end
