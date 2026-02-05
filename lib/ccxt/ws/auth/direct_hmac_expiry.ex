defmodule CCXT.WS.Auth.DirectHmacExpiry do
  @moduledoc """
  Direct HMAC Expiry authentication pattern (Bybit, Bitmex style).

  Signs payload: GET/realtime + expires timestamp
  Message format: op/args with apiKey, expires, signature

  ## Example Auth Message (Bybit)

      %{
        "op" => "auth",
        "args" => ["apiKey123", 1699999999999, "signature_hex"]
      }

  """

  @behaviour CCXT.WS.Auth.Behaviour

  alias CCXT.Signing

  @default_expires_offset_ms 10_000

  @impl true
  def pre_auth(_credentials, _config, _opts) do
    {:ok, %{}}
  end

  @impl true
  def build_auth_message(credentials, config, _opts) do
    api_key = credentials.api_key
    secret = credentials.secret

    # Calculate expires timestamp
    expires_offset = config[:expires_offset_ms] || @default_expires_offset_ms
    expires = Signing.timestamp_ms() + expires_offset

    # Build payload: GET/realtime{expires}
    payload = "GET/realtime#{expires}"

    # Sign and encode
    signature_raw = Signing.hmac_sha256(payload, secret)

    signature =
      case config[:encoding] do
        :base64 -> Signing.encode_base64(signature_raw)
        _ -> Signing.encode_hex(signature_raw)
      end

    # Build message
    op_field = config[:op_field] || "op"
    op_value = config[:op_value] || "auth"

    message = %{
      op_field => op_value,
      "args" => [api_key, expires, signature]
    }

    {:ok, message}
  end

  @impl true
  def handle_auth_response(response, _state) do
    cond do
      response["success"] == true ->
        :ok

      response["ret_msg"] && String.contains?(response["ret_msg"], "error") ->
        {:error, {:auth_failed, response["ret_msg"]}}

      true ->
        {:error, {:auth_failed, response}}
    end
  end
end
