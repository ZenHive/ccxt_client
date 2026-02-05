defmodule CCXT.WS.Auth.RestToken do
  @moduledoc """
  REST Token authentication pattern (Kraken style).

  This pattern requires a REST API call to obtain an authentication token
  before subscribing to private channels. The token is then included in
  subscription messages.

  ## Flow

  1. Call REST endpoint (e.g., privatePostGetWebSocketsToken) to get token
  2. Connect to WebSocket (no auth message)
  3. Include token in private subscription messages
  4. Token expires (typically ~15 minutes), re-fetch when needed

  ## Example Token Response (Kraken)

      %{
        "result" => %{
          "token" => "xeAQ/RCChBYNVh53sTv1yZ5H4wIbwDF20PiHtTF+4UI",
          "expires" => 900
        }
      }

  ## Example Subscription with Token

      %{
        "method" => "subscribe",
        "params" => %{
          "channel" => "executions",
          "token" => "xeAQ/RCChBYNVh53sTv1yZ5H4wIbwDF20PiHtTF+4UI"
        }
      }

  ## Implementation Note

  This module does NOT make the REST call itself. It returns the endpoint
  configuration, and the caller (Adapter or exchange module) is responsible
  for:

  1. Calling `pre_auth/3` to get the endpoint info
  2. Making the actual REST call via the exchange's REST client
  3. Extracting the token from the response
  4. Storing the token in auth config for use in `build_subscribe_auth/4`
  5. Refreshing the token before expiry

  This separation keeps auth pattern modules pure and testable without
  network dependencies.

  """

  @behaviour CCXT.WS.Auth.Behaviour

  @impl true
  def pre_auth(credentials, config, _opts) do
    # The actual REST call is made by the adapter/exchange module
    # This module just returns the config for what endpoint to call
    endpoint = config[:pre_auth][:endpoint]

    if endpoint do
      {:ok, %{endpoint: endpoint, credentials: credentials}}
    else
      {:error, :no_token_endpoint}
    end
  end

  @impl true
  def build_auth_message(_credentials, _config, _opts) do
    # No standalone WS auth message - token sent with subscriptions
    :no_message
  end

  @impl true
  def handle_auth_response(_response, _state) do
    # No auth response expected
    :ok
  end
end
