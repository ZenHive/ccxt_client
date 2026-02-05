defmodule CCXT.WS.Auth.Sha384Nonce do
  @moduledoc """
  SHA384 Nonce authentication pattern (Bitfinex style).

  Uses AUTH + nonce payload with SHA384 hex signature.

  ## Payload Format

      AUTH{nonce}
      e.g., "AUTH1699999999999"

  ## Example Auth Message (Bitfinex)

      %{
        "event" => "auth",
        "apiKey" => "api_key",
        "authSig" => "hex_signature",
        "authNonce" => 1699999999999,
        "authPayload" => "AUTH1699999999999"
      }

  """

  @behaviour CCXT.WS.Auth.Behaviour

  alias CCXT.Signing

  @impl true
  def pre_auth(_credentials, _config, _opts) do
    {:ok, %{}}
  end

  @impl true
  def build_auth_message(credentials, config, _opts) do
    api_key = credentials.api_key
    secret = credentials.secret

    # Nonce (timestamp in milliseconds)
    nonce = Signing.timestamp_ms()

    # Build payload: AUTH{nonce}
    payload = "AUTH#{nonce}"

    # Sign with SHA384 hex
    signature_raw = Signing.hmac_sha384(payload, secret)
    signature = Signing.encode_hex(signature_raw)

    # Build message
    event_value = config[:event_value] || "auth"

    message = %{
      "event" => event_value,
      "apiKey" => api_key,
      "authSig" => signature,
      "authNonce" => nonce,
      "authPayload" => payload
    }

    {:ok, message}
  end

  @impl true
  def handle_auth_response(response, _state) do
    cond do
      response["event"] == "auth" && response["status"] == "OK" ->
        :ok

      response["event"] == "auth" && response["status"] == "FAILED" ->
        {:error, {:auth_failed, response["msg"]}}

      true ->
        {:error, {:auth_failed, response}}
    end
  end
end
