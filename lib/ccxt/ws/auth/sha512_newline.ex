defmodule CCXT.WS.Auth.Sha512Newline do
  @moduledoc """
  SHA512 Newline authentication pattern (Gate style).

  Uses newline-separated payload with SHA512 hex signature.

  ## Payload Format

      event\\nchannel\\nreq_params_json\\ntime

  ## Example Auth Message (Gate)

      %{
        "id" => "request_id",
        "time" => 1699999999,
        "channel" => "spot.login",
        "event" => "api",
        "payload" => %{
          "req_id" => "request_id",
          "timestamp" => "1699999999",
          "api_key" => "api_key",
          "signature" => "hex_signature",
          "req_param" => %{}
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

    # Timestamp in seconds
    time = Signing.timestamp_seconds()
    request_id = opts[:request_id] || to_string(System.unique_integer([:positive]))

    # Channel for login
    channel = config[:channel] || "spot.login"
    event = "api"
    req_params = %{}
    req_params_json = Jason.encode!(req_params)

    # Build payload: event\nchannel\nreq_params_json\ntime
    payload = "#{event}\n#{channel}\n#{req_params_json}\n#{time}"

    # Sign with SHA512 hex
    signature_raw = Signing.hmac_sha512(payload, secret)
    signature = Signing.encode_hex(signature_raw)

    # Build message
    message = %{
      "id" => request_id,
      "time" => time,
      "channel" => channel,
      "event" => event,
      "payload" => %{
        "req_id" => request_id,
        "timestamp" => to_string(time),
        "api_key" => api_key,
        "signature" => signature,
        "req_param" => req_params
      }
    }

    {:ok, message}
  end

  @impl true
  def handle_auth_response(response, _state) do
    cond do
      response["event"] == "api" && response["result"] && response["result"]["status"] == "success" ->
        :ok

      response["error"] ->
        {:error, {:auth_failed, response["error"]}}

      true ->
        # Gate often returns the auth result in a specific format
        if response["result"] do
          :ok
        else
          {:error, {:auth_failed, response}}
        end
    end
  end
end
