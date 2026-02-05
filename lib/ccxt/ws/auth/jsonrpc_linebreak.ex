defmodule CCXT.WS.Auth.JsonrpcLinebreak do
  @moduledoc """
  JSON-RPC Linebreak authentication pattern (Deribit style).

  Uses JSON-RPC 2.0 format with linebreak-separated payload signature.

  ## Payload Format

      timestamp\\nnonce\\n

  ## Example Auth Message (Deribit)

      %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "public/auth",
        "params" => %{
          "grant_type" => "client_signature",
          "client_id" => "api_key",
          "timestamp" => 1699999999999,
          "signature" => "hex_signature",
          "nonce" => "1699999999999",
          "data" => ""
        }
      }

  """

  @behaviour CCXT.WS.Auth.Behaviour

  alias CCXT.Signing

  @impl true
  def pre_auth(_credentials, _config, _opts) do
    {:ok, %{}}
  end

  @impl true
  def build_auth_message(credentials, config, opts) do
    api_key = credentials.api_key
    secret = credentials.secret

    # Timestamp and nonce
    timestamp = Signing.timestamp_ms()
    nonce = opts[:nonce] || to_string(timestamp)

    # Build payload: timestamp\nnonce\n
    payload = "#{timestamp}\n#{nonce}\n"

    # Sign with SHA256 hex
    signature_raw = Signing.hmac_sha256(payload, secret)
    signature = Signing.encode_hex(signature_raw)

    # Request ID
    request_id = opts[:request_id] || System.unique_integer([:positive])

    # Build JSON-RPC message
    message = %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "method" => config[:method_value] || "public/auth",
      "params" => %{
        "grant_type" => "client_signature",
        "client_id" => api_key,
        "timestamp" => timestamp,
        "signature" => signature,
        "nonce" => nonce,
        "data" => ""
      }
    }

    {:ok, message}
  end

  @impl true
  def handle_auth_response(response, _state) do
    cond do
      response["result"] && response["result"]["access_token"] ->
        :ok

      response["error"] ->
        {:error, {:auth_failed, response["error"]}}

      true ->
        {:error, {:auth_failed, response}}
    end
  end
end
