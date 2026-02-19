defmodule CCXT.WS.Auth.ListenKey do
  @moduledoc """
  Listen Key authentication pattern (Binance style).

  This pattern requires a REST API call to obtain a listen key before
  connecting to the WebSocket. The listen key is then used as part of
  the WebSocket URL.

  ## Flow

  1. Call REST endpoint (e.g., fapiPrivatePostListenKey) to get listenKey
  2. Use listenKey in the WebSocket URL
  3. No explicit WS auth message needed - connection is already authenticated
  4. Periodically refresh the listen key (every ~30 minutes)

  ## Pre-auth Endpoints by Market Type

  | Market | Endpoint |
  |--------|----------|
  | Linear (USD-M) | fapiPrivatePostListenKey |
  | Inverse (COIN-M) | dapiPrivatePostListenKey |
  | Spot | publicPostUserDataStream |
  | Margin | sapiPostUserDataStream |
  | Isolated Margin | sapiPostUserDataStreamIsolated |
  | Portfolio Margin | papiPostListenKey |

  ## Implementation Note

  This module does NOT make the REST call itself. It returns the endpoint
  configuration, and the caller (Adapter or exchange module) is responsible
  for:

  1. Calling `pre_auth/3` to get the endpoint info
  2. Making the actual REST call via the exchange's REST client
  3. Extracting the listenKey from the response
  4. Including the listenKey in the WebSocket URL
  5. Periodically refreshing the listenKey before expiry

  This separation keeps auth pattern modules pure and testable without
  network dependencies.

  """

  @behaviour CCXT.WS.Auth.Behaviour

  @impl true
  def pre_auth(credentials, config, opts) do
    # The actual REST call is made by the adapter/exchange module
    # This module just returns the config for what endpoint to call
    raw_type = opts[:market_type] || :spot
    market_type = normalize_market_type(raw_type)
    endpoints = config[:pre_auth][:endpoints] || []

    case Enum.find(endpoints, fn ep -> ep.type == market_type end) do
      nil ->
        {:error,
         {:no_endpoint_for_market_type,
          %{
            requested: raw_type,
            normalized: market_type,
            available: Enum.map(endpoints, & &1.type)
          }}}

      endpoint ->
        {:ok,
         %{
           endpoint: endpoint.endpoint,
           market_type: market_type,
           api_section: endpoint[:api_section],
           # Intentional default: all listen key endpoints are POST
           method: endpoint[:method] || "POST",
           path: endpoint[:path],
           credentials: credentials
         }}
    end
  end

  @doc false
  # Maps WS URL path keys to listen key endpoint types.
  # WS URLs use :future/:delivery but listen key endpoints use :linear/:inverse.
  defp normalize_market_type(:future), do: :linear
  defp normalize_market_type(:delivery), do: :inverse
  defp normalize_market_type(:contract), do: :linear
  defp normalize_market_type(other), do: other

  @impl true
  def build_auth_message(_credentials, _config, _opts) do
    # No WS message needed - auth is via URL
    :no_message
  end

  @impl true
  def handle_auth_response(_response, _state) do
    # No auth response expected - connection is pre-authenticated
    :ok
  end
end
