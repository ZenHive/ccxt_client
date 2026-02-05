defmodule CCXT.WS.Client do
  @moduledoc """
  WebSocket client wrapper for CCXT exchanges.

  This module provides a thin wrapper around ZenWebsocket.Client that:
  - Resolves URLs from exchange specs
  - Uses exchange WS modules for subscription building
  - Tracks subscriptions for restoration after reconnection

  ## Usage

  The client works with any generated CCXT exchange module:

      # Get the spec from a generated exchange module
      spec = CCXT.Bybit.__ccxt_spec__()

      # Connect to public spot endpoint
      {:ok, client} = CCXT.WS.Client.connect(spec, [:public, :spot])

      # Subscribe using the exchange's WS module
      {:ok, sub} = CCXT.Bybit.WS.watch_ticker_subscription("BTC/USDT")
      :ok = CCXT.WS.Client.subscribe(client, sub)

      # Messages are sent to the calling process
      receive do
        {:websocket_message, data} -> Jason.decode!(data)
      end

      # Close when done
      :ok = CCXT.WS.Client.close(client)

  ## Layers

  This is Layer 2 in the WebSocket architecture:

  - **Layer 1** (CCXT.WS.Helpers): Pure functions for URL resolution
  - **Layer 2** (CCXT.WS.Client): This module - thin wrapper with subscription tracking
  - **Layer 3** (CCXT.{Exchange}.WS.Adapter): GenServer with auth + reconnection (opt-in)

  ## Handler Options

  Messages can be routed via:

  1. **Default** - Sent to calling process as `{:websocket_message, data}`
  2. **Custom handler** - Function passed via `:handler` option

  """

  alias CCXT.WS.Helpers
  alias CCXT.WS.Subscription
  alias ZenWebsocket.Client, as: ZenClient

  @type subscription :: %{
          channel: String.t() | [String.t()],
          message: map(),
          method: atom(),
          auth_required: boolean()
        }

  @type t :: %__MODULE__{
          zen_client: ZenClient.t(),
          spec: map(),
          url: String.t(),
          url_path: term(),
          subscriptions: [subscription()]
        }

  defstruct [:zen_client, :spec, :url, :url_path, subscriptions: []]

  @doc """
  Connects to a WebSocket endpoint using the exchange spec.

  ## Parameters

  - `spec` - Exchange specification (from `CCXT.{Exchange}.__ccxt_spec__()`)
  - `url_path` - Path to resolve URL (e.g., `[:public, :spot]`, `:private`)
  - `opts` - Options:
    - `:sandbox` - Use testnet URLs (default: false)
    - `:handler` - Message handler function
    - `:timeout` - Connection timeout in ms (default: 5000)
    - `:debug` - Enable debug logging

  ## Examples

      # Connect to public spot endpoint
      {:ok, client} = CCXT.WS.Client.connect(spec, [:public, :spot])

      # Connect to testnet
      {:ok, client} = CCXT.WS.Client.connect(spec, [:public, :spot], sandbox: true)

      # With custom handler (requires `require Logger`)
      {:ok, client} = CCXT.WS.Client.connect(spec, :public, handler: fn msg ->
        Logger.info("WS Message: \#{inspect(msg)}")
      end)

  """
  @spec connect(map(), term(), keyword()) :: {:ok, t()} | {:error, term()}
  def connect(spec, url_path, opts \\ []) do
    with {:ok, url} <- Helpers.resolve_url(spec, url_path, opts),
         zen_opts = Helpers.build_client_config(spec, opts),
         {:ok, zen_client} <- ZenClient.connect(url, zen_opts) do
      client = %__MODULE__{
        zen_client: zen_client,
        spec: spec,
        url: url,
        url_path: url_path,
        subscriptions: []
      }

      {:ok, client}
    end
  end

  @doc """
  Subscribes to a channel using a subscription map.

  The subscription map should come from an exchange's WS module:

      {:ok, sub} = CCXT.Bybit.WS.watch_ticker_subscription("BTC/USDT")
      :ok = CCXT.WS.Client.subscribe(client, sub)

  ## Parameters

  - `client` - The CCXT.WS.Client struct
  - `subscription` - Subscription map with `:channel` and `:message` keys

  ## Returns

  - `:ok` - Fire-and-forget success
  - `{:ok, response}` - JSON-RPC correlated response
  - `{:error, reason}` - Failure

  """
  @spec subscribe(t(), subscription()) :: :ok | {:ok, map()} | {:error, term()}
  def subscribe(%__MODULE__{} = client, %{message: message} = _subscription) do
    json = Jason.encode!(message)

    # Note: Subscription tracking is handled by the Adapter GenServer (W6c),
    # not by this stateless client wrapper. This client only sends the message.
    ZenClient.send_message(client.zen_client, json)
  end

  @doc """
  Unsubscribes from a channel.

  Builds an unsubscribe message using the exchange's subscription config.

  ## Parameters

  - `client` - The CCXT.WS.Client struct
  - `subscription` - The subscription to remove (same format as subscribe)

  """
  @spec unsubscribe(t(), subscription()) :: :ok | {:ok, map()} | {:error, term()}
  def unsubscribe(%__MODULE__{spec: spec} = client, %{channel: channel} = _subscription) do
    ws_config = Map.get(spec, :ws) || %{}

    # Build unsubscribe message
    channels = if is_list(channel), do: channel, else: [channel]
    message = Subscription.build_unsubscribe(channels, ws_config)
    json = Jason.encode!(message)

    ZenClient.send_message(client.zen_client, json)
  end

  @doc """
  Sends a raw message through the WebSocket.

  Use this for custom messages that don't fit the subscription pattern.

  ## Parameters

  - `client` - The CCXT.WS.Client struct
  - `message` - Map to JSON-encode, or binary to send directly

  """
  @spec send_message(t(), map() | binary()) :: :ok | {:ok, map()} | {:error, term()}
  def send_message(%__MODULE__{zen_client: zen_client}, message) when is_map(message) do
    ZenClient.send_message(zen_client, Jason.encode!(message))
  end

  def send_message(%__MODULE__{zen_client: zen_client}, message) when is_binary(message) do
    ZenClient.send_message(zen_client, message)
  end

  @doc """
  Closes the WebSocket connection.

  ## Parameters

  - `client` - The CCXT.WS.Client struct

  """
  @spec close(t()) :: :ok
  def close(%__MODULE__{zen_client: zen_client}) do
    ZenClient.close(zen_client)
  end

  @doc """
  Returns the current connection state.

  ## Returns

  - `:connecting` - Connection in progress
  - `:connected` - Connected and ready
  - `:disconnected` - Not connected

  """
  @spec get_state(t()) :: :connecting | :connected | :disconnected
  def get_state(%__MODULE__{zen_client: zen_client}) do
    ZenClient.get_state(zen_client)
  end

  @doc """
  Returns the WebSocket URL this client is connected to.
  """
  @spec get_url(t()) :: String.t()
  def get_url(%__MODULE__{url: url}), do: url

  @doc """
  Returns the list of active subscriptions.

  Useful for debugging and for restoring subscriptions after reconnection.
  """
  @spec get_subscriptions(t()) :: [subscription()]
  def get_subscriptions(%__MODULE__{subscriptions: subs}), do: subs

  @doc """
  Returns the underlying ZenWebsocket.Client struct.

  Use this for advanced operations like accessing heartbeat health.
  """
  @spec get_zen_client(t()) :: ZenClient.t()
  def get_zen_client(%__MODULE__{zen_client: client}), do: client

  @doc """
  Restores subscriptions from a previous session.

  Call this after reconnecting to restore all previous subscriptions.

  ## Parameters

  - `client` - The reconnected client
  - `subscriptions` - List of subscriptions from previous session

  """
  @spec restore_subscriptions(t(), [subscription()]) :: :ok | {:error, term()}
  def restore_subscriptions(%__MODULE__{spec: spec} = client, subscriptions) do
    case Helpers.build_restore_message(spec, subscriptions) do
      nil ->
        :ok

      {:ok, message} ->
        case send_message(client, message) do
          :ok -> :ok
          {:ok, _response} -> :ok
          error -> error
        end
    end
  end
end
