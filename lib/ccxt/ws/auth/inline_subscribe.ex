defmodule CCXT.WS.Auth.InlineSubscribe do
  @moduledoc """
  Inline Subscribe authentication pattern (Coinbase style).

  This pattern includes authentication data directly in subscribe messages
  rather than sending a separate authentication message.

  ## Flow

  1. Connect to WebSocket (no auth message)
  2. Include auth fields (api_key, timestamp, signature) in each private subscribe
  3. Auth is per-subscription, not per-connection

  ## Example Subscribe with Auth (Coinbase)

      %{
        "type" => "subscribe",
        "product_ids" => ["BTC-USD"],
        "channel" => "user",
        "api_key" => "api_key_here",
        "timestamp" => "1699999999",
        "signature" => "hex_signature"
      }

  ## Payload Format

      timestamp + channel + product_ids
      e.g., "1699999999userBTC-USD,ETH-USD"

  """

  @behaviour CCXT.WS.Auth.Behaviour

  alias CCXT.Signing

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
  Builds auth data to include in subscribe messages.
  """
  @impl true
  def build_subscribe_auth(credentials, _config, channel, symbols) do
    api_key = credentials.api_key
    secret = credentials.secret

    # Timestamp in seconds
    timestamp = to_string(Signing.timestamp_seconds())

    # Build payload: timestamp + channel + symbols joined
    symbols_str = Enum.join(symbols, ",")
    payload = timestamp <> channel <> symbols_str

    # Sign with SHA256 hex
    signature_raw = Signing.hmac_sha256(payload, secret)
    signature = Signing.encode_hex(signature_raw)

    %{
      "api_key" => api_key,
      "timestamp" => timestamp,
      "signature" => signature
    }
  end
end
