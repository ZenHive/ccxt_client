defmodule CCXT.WS.Auth.Behaviour do
  @moduledoc """
  Behaviour for WebSocket authentication pattern implementations.

  All WS auth patterns must implement callbacks for building auth messages
  and handling auth responses. Patterns reuse existing REST signing primitives
  where possible.

  ## Auth Flow

  1. User calls `Adapter.authenticate/1`
  2. Adapter retrieves auth config from spec
  3. Dispatcher routes to appropriate pattern module
  4. Pattern builds auth message using credentials
  5. Message sent via WS client
  6. Response handler updates auth state

  ## Pattern Types

  - **Direct HMAC** - Sign payload, send auth message (Bybit, OKX, Bitfinex, etc.)
  - **Pre-auth** - REST call first, then WS (Binance listen_key, Kraken token)
  - **Inline** - Auth included in subscribe messages (Coinbase)

  ## Implementing a Pattern

      defmodule CCXT.WS.Auth.DirectHmacExpiry do
        @behaviour CCXT.WS.Auth.Behaviour

        @impl true
        def build_auth_message(credentials, config, opts) do
          # Build the auth message using credentials and config
          {:ok, %{"op" => "auth", "args" => [api_key, expires, signature]}}
        end

        @impl true
        def handle_auth_response(response, state) do
          # Check response and return auth result
          if response["success"], do: :ok, else: {:error, :auth_failed}
        end
      end

  ## Pre-auth Pattern Example

  For patterns like Binance's listen_key that require REST calls:

      @impl true
      def pre_auth(credentials, config, opts) do
        # Make REST call to get listen key
        {:ok, %{listen_key: "abc123", refresh_interval_ms: 1_800_000}}
      end

      @impl true
      def build_auth_message(_credentials, config, opts) do
        # No WS auth message needed - listen key is in URL
        :no_message
      end

  """

  alias CCXT.Credentials

  @type auth_config :: map()
  @type auth_message :: map()
  @type auth_response :: map()
  @type auth_state :: map()
  @type opts :: keyword()

  @type pre_auth_result :: {:ok, map()} | {:error, term()}
  @type build_result :: {:ok, auth_message()} | :no_message | {:error, term()}
  @type handle_result :: :ok | {:error, term()}

  @doc """
  Performs pre-authentication if required (REST call for token/listen key).

  Only implemented by patterns that require REST calls before WS auth.
  Returns `{:ok, data}` with pre-auth data, or `{:error, reason}`.

  For patterns that don't need pre-auth, implement as:
      def pre_auth(_credentials, _config, _opts), do: {:ok, %{}}
  """
  @callback pre_auth(
              credentials :: Credentials.t(),
              config :: auth_config(),
              opts :: opts()
            ) :: pre_auth_result()

  @doc """
  Builds the WebSocket authentication message.

  Returns `{:ok, message}` with the message to send, `:no_message` if no
  WS message is needed (e.g., listen_key pattern), or `{:error, reason}`.

  The message should be a map that will be JSON-encoded before sending.
  """
  @callback build_auth_message(
              credentials :: Credentials.t(),
              config :: auth_config(),
              opts :: opts()
            ) :: build_result()

  @doc """
  Handles the authentication response from the server.

  Returns `:ok` on successful authentication, `{:error, reason}` on failure.

  This callback is used to:
  1. Check if auth was successful
  2. Extract any tokens/data from the response
  3. Update internal auth state if needed
  """
  @callback handle_auth_response(
              response :: auth_response(),
              state :: auth_state()
            ) :: handle_result()

  @doc """
  Optional: Build auth data to include in subscribe messages.

  For inline auth patterns (Coinbase), auth data is included in each subscribe
  message rather than sent as a separate auth message.

  Default implementation returns nil (no inline auth needed).
  """
  @callback build_subscribe_auth(
              credentials :: Credentials.t(),
              config :: auth_config(),
              channel :: String.t(),
              symbols :: list(String.t())
            ) :: map() | nil

  @optional_callbacks [build_subscribe_auth: 4]
end
