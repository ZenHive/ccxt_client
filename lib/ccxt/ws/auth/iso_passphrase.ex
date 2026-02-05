defmodule CCXT.WS.Auth.IsoPassphrase do
  @moduledoc """
  ISO Passphrase authentication pattern (OKX, Bitget style).

  Uses ISO timestamp, passphrase, and SHA256 base64 signature.
  3-factor auth: apiKey, passphrase, signature

  ## Payload Format

      timestamp + method + path
      e.g., "1699999999GET/users/self/verify"

  ## Example Auth Message (OKX)

      %{
        "op" => "login",
        "args" => [
          %{
            "apiKey" => "api_key_here",
            "passphrase" => "passphrase_here",
            "timestamp" => "1699999999",
            "sign" => "base64_signature"
          }
        ]
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
    passphrase = credentials.password

    if is_nil(passphrase) do
      {:error, :passphrase_required}
    else
      # Timestamp in seconds
      timestamp =
        case config[:timestamp_unit] do
          :milliseconds -> to_string(Signing.timestamp_ms())
          _ -> to_string(Signing.timestamp_seconds())
        end

      # Build payload: timestamp + method + path
      method = "GET"
      path = "/users/self/verify"
      payload = timestamp <> method <> path

      # Sign with SHA256 base64
      signature_raw = Signing.hmac_sha256(payload, secret)
      signature = Signing.encode_base64(signature_raw)

      # Build message
      op_field = config[:op_field] || "op"
      op_value = config[:op_value] || "login"

      message = %{
        op_field => op_value,
        "args" => [
          %{
            "apiKey" => api_key,
            "passphrase" => passphrase,
            "timestamp" => timestamp,
            "sign" => signature
          }
        ]
      }

      {:ok, message}
    end
  end

  @impl true
  def handle_auth_response(response, _state) do
    cond do
      response["event"] == "login" && response["code"] == "0" ->
        :ok

      response["event"] == "error" ->
        {:error, {:auth_failed, response["msg"]}}

      true ->
        {:error, {:auth_failed, response}}
    end
  end
end
