defmodule CCXT.WS.Generator.Adapter do
  @moduledoc """
  Generates WebSocket Adapter GenServer modules at compile time.

  The Adapter provides a managed WebSocket connection with:
  - Automatic reconnection with exponential backoff
  - Subscription tracking and restoration
  - Authentication state tracking (TODO: auth logic deferred to W11)
  - Process monitoring

  ## Generated Module

  For each exchange with WS support, generates `CCXT.{Exchange}.WS.Adapter`:

      defmodule CCXT.Bybit.WS.Adapter do
        use GenServer
        # ... generated code
      end

  ## Usage

      # Start the adapter
      {:ok, adapter} = CCXT.Bybit.WS.Adapter.start_link(
        name: :bybit_ws,
        url_path: [:public, :spot],
        handler: fn msg -> handle_message(msg) end
      )

      # Subscribe to channels
      {:ok, sub} = CCXT.Bybit.WS.watch_ticker_subscription("BTC/USDT")
      :ok = CCXT.Bybit.WS.Adapter.subscribe(adapter, sub)

      # Reconnection happens automatically
      # Subscriptions are restored on reconnect

  """

  @reconnect_delay_ms 5_000
  @max_reconnect_attempts 10
  @max_backoff_ms 60_000

  @doc """
  Generates the Adapter module AST for an exchange.

  ## Parameters

  - `ws_module` - The WS subscription module (e.g., `CCXT.Bybit.WS`)
  - `rest_module` - The REST module (e.g., `CCXT.Bybit`)
  - `ws_config` - The WS configuration from spec

  """
  @spec generate_adapter(module(), module(), map()) :: Macro.t()
  def generate_adapter(ws_module, rest_module, _ws_config) do
    moduledoc = generate_adapter_moduledoc(rest_module)

    quote do
      @moduledoc unquote(moduledoc)

      use GenServer

      alias CCXT.WS.Auth
      alias CCXT.WS.Client, as: WSClient
      alias CCXT.WS.Helpers

      require Logger

      unquote(generate_module_attrs())
      unquote(generate_types())
      unquote(generate_client_api(ws_module))
      unquote(generate_init_callback(rest_module))
      unquote(generate_handle_call_callbacks())
      unquote(generate_handle_cast_callbacks())
      unquote(generate_handle_info_callbacks())
      unquote(generate_private_helpers())
      unquote(generate_authenticate_logic())
    end
  end

  # ===========================================================================
  # AST Generation Helpers
  # ===========================================================================

  @doc false
  # Generates module attributes for reconnection timing configuration
  defp generate_module_attrs do
    reconnect_delay = @reconnect_delay_ms
    max_attempts = @max_reconnect_attempts
    max_backoff = @max_backoff_ms

    quote do
      @reconnect_delay_ms unquote(reconnect_delay)
      @max_reconnect_attempts unquote(max_attempts)
      @max_backoff_ms unquote(max_backoff)
    end
  end

  @doc false
  # Generates type definitions for subscription and state maps
  defp generate_types do
    quote do
      @type subscription :: %{
              channel: String.t() | [String.t()],
              message: map(),
              method: atom(),
              auth_required: boolean()
            }

      @type state :: %{
              client: WSClient.t() | nil,
              monitor_ref: reference() | nil,
              authenticated: boolean(),
              was_authenticated: boolean(),
              subscriptions: [subscription()],
              credentials: map() | nil,
              spec: map(),
              url_path: term(),
              opts: keyword(),
              handler: (term() -> any()) | nil,
              reconnect_attempts: non_neg_integer()
            }
    end
  end

  @doc false
  # Generates the public client API (start_link, subscribe, unsubscribe, etc.)
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp generate_client_api(ws_module) do
    quote do
      # =====================================================================
      # Client API
      # =====================================================================

      @doc """
      Starts the WebSocket adapter.

      ## Options

      - `:name` - GenServer name (optional)
      - `:url_path` - Path to WS URL in spec (e.g., `[:public, :spot]`)
      - `:credentials` - API credentials map (optional, for authenticated endpoints)
      - `:handler` - Message handler function `fn msg -> ... end`
      - `:sandbox` - Use testnet URLs (default: false)
      - `:debug` - Enable debug logging (default: false)

      ## Examples

          {:ok, adapter} = Adapter.start_link(
            name: :bybit_public,
            url_path: [:public, :spot],
            handler: fn msg -> msg end
          )

      """
      @spec start_link(keyword()) :: GenServer.on_start()
      def start_link(opts) do
        name = Keyword.get(opts, :name)

        if name do
          GenServer.start_link(__MODULE__, opts, name: name)
        else
          GenServer.start_link(__MODULE__, opts)
        end
      end

      @doc """
      Subscribes to a channel.

      The subscription should come from the exchange's WS module:

          {:ok, sub} = #{inspect(unquote(ws_module))}.watch_ticker_subscription("BTC/USDT")
          :ok = Adapter.subscribe(adapter, sub)

      """
      @spec subscribe(GenServer.server(), subscription()) :: :ok | {:error, term()}
      def subscribe(adapter, subscription) do
        GenServer.call(adapter, {:subscribe, subscription})
      end

      @doc """
      Unsubscribes from a channel.
      """
      @spec unsubscribe(GenServer.server(), subscription()) :: :ok | {:error, term()}
      def unsubscribe(adapter, subscription) do
        GenServer.call(adapter, {:unsubscribe, subscription})
      end

      @doc """
      Authenticates the WebSocket connection.

      Builds and sends an authentication message based on the exchange's
      auth pattern (from spec.ws.auth). On success, the adapter is marked
      as authenticated and will re-authenticate on reconnection.

      ## Returns

      - `:ok` - Authentication successful
      - `{:error, :no_auth_config}` - Exchange doesn't have WS auth configured
      - `{:error, :no_credentials}` - No credentials provided at start_link
      - `{:error, :not_connected}` - Not connected to WebSocket
      - `{:error, :no_message}` - Auth pattern doesn't use WS messages (e.g., listen_key)
      - `{:error, reason}` - Authentication failed

      ## Example

          :ok = Adapter.authenticate(adapter)
          :ok = Adapter.subscribe(adapter, watch_balance_subscription)

      """
      @spec authenticate(GenServer.server()) :: :ok | {:error, term()}
      def authenticate(adapter) do
        GenServer.call(adapter, :authenticate, 30_000)
      end

      @doc """
      Marks the adapter as authenticated (manual mode).

      Use this after performing authentication externally (e.g., via REST
      pre-auth for listen_key pattern). The adapter will track this state
      and attempt to re-authenticate on reconnection.
      """
      @spec mark_authenticated(GenServer.server()) :: :ok
      def mark_authenticated(adapter) do
        GenServer.cast(adapter, :mark_authenticated)
      end

      @doc """
      Returns the current adapter state.
      """
      @spec get_state(GenServer.server()) :: {:ok, map()}
      def get_state(adapter) do
        GenServer.call(adapter, :get_state)
      end

      @doc """
      Returns the connection status.
      """
      @spec connected?(GenServer.server()) :: boolean()
      def connected?(adapter) do
        case GenServer.call(adapter, :get_connection_state) do
          :connected -> true
          _ -> false
        end
      end

      @doc """
      Sends a raw message through the WebSocket.
      """
      @spec send_message(GenServer.server(), map() | binary()) :: :ok | {:ok, map()} | {:error, term()}
      def send_message(adapter, message) do
        GenServer.call(adapter, {:send_message, message})
      end
    end
  end

  @doc false
  # Generates GenServer init/1 callback with initial state setup
  defp generate_init_callback(rest_module) do
    quote do
      # =====================================================================
      # GenServer Callbacks - Init
      # =====================================================================

      @impl true
      def init(opts) do
        spec = unquote(rest_module).__ccxt_spec__()
        url_path = Keyword.fetch!(opts, :url_path)

        state = %{
          client: nil,
          monitor_ref: nil,
          authenticated: false,
          was_authenticated: false,
          subscriptions: [],
          credentials: Keyword.get(opts, :credentials),
          spec: spec,
          url_path: url_path,
          opts: opts,
          handler: Keyword.get(opts, :handler),
          reconnect_attempts: 0
        }

        # Connect async
        send(self(), :connect)

        {:ok, state}
      end
    end
  end

  @doc false
  # Generates GenServer handle_call/3 callbacks for subscribe/unsubscribe/state queries
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp generate_handle_call_callbacks do
    quote do
      # =====================================================================
      # GenServer Callbacks - handle_call
      # =====================================================================

      @impl true
      def handle_call({:subscribe, _subscription}, _from, %{client: nil} = state) do
        {:reply, {:error, :not_connected}, state}
      end

      def handle_call({:subscribe, subscription}, _from, %{client: client} = state) do
        case WSClient.subscribe(client, subscription) do
          :ok ->
            new_subs = [subscription | state.subscriptions]
            {:reply, :ok, %{state | subscriptions: new_subs}}

          {:ok, _response} ->
            new_subs = [subscription | state.subscriptions]
            {:reply, :ok, %{state | subscriptions: new_subs}}

          {:error, _} = error ->
            {:reply, error, state}
        end
      end

      def handle_call({:unsubscribe, _subscription}, _from, %{client: nil} = state) do
        {:reply, {:error, :not_connected}, state}
      end

      def handle_call({:unsubscribe, subscription}, _from, %{client: client} = state) do
        case WSClient.unsubscribe(client, subscription) do
          :ok ->
            new_subs = Enum.reject(state.subscriptions, &(&1.channel == subscription.channel))
            {:reply, :ok, %{state | subscriptions: new_subs}}

          {:ok, _response} ->
            new_subs = Enum.reject(state.subscriptions, &(&1.channel == subscription.channel))
            {:reply, :ok, %{state | subscriptions: new_subs}}

          {:error, _} = error ->
            {:reply, error, state}
        end
      end

      def handle_call(:get_state, _from, state) do
        {:reply, {:ok, state}, state}
      end

      def handle_call(:get_connection_state, _from, %{client: nil} = state) do
        {:reply, :disconnected, state}
      end

      def handle_call(:get_connection_state, _from, %{client: client} = state) do
        {:reply, WSClient.get_state(client), state}
      end

      def handle_call({:send_message, _message}, _from, %{client: nil} = state) do
        {:reply, {:error, :not_connected}, state}
      end

      def handle_call({:send_message, message}, _from, %{client: client} = state) do
        {:reply, WSClient.send_message(client, message), state}
      end

      # W11: Authentication handler
      def handle_call(:authenticate, _from, %{client: nil} = state) do
        {:reply, {:error, :not_connected}, state}
      end

      def handle_call(:authenticate, _from, %{credentials: nil} = state) do
        {:reply, {:error, :no_credentials}, state}
      end

      def handle_call(:authenticate, _from, state) do
        auth_config = get_in(state.spec.ws, [:auth])

        case auth_config do
          nil ->
            {:reply, {:error, :no_auth_config}, state}

          config ->
            do_authenticate(config, state)
        end
      end
    end
  end

  @doc false
  # Generates authentication logic as private functions
  # The complexity warning is for the generator, not the generated code
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp generate_authenticate_logic do
    quote do
      @doc false
      defp do_authenticate(config, state) do
        pattern = config[:pattern]

        case Auth.build_auth_message(pattern, state.credentials, config, []) do
          {:ok, message} -> send_auth_message(message, pattern, state)
          :no_message -> mark_auth_success(state)
          {:error, _} = error -> {:reply, error, state}
        end
      end

      @doc false
      defp send_auth_message(message, pattern, state) do
        case WSClient.send_message(state.client, Jason.encode!(message)) do
          :ok -> mark_auth_success(state)
          {:ok, response} -> handle_auth_response(response, pattern, state)
          {:error, _} = error -> {:reply, error, state}
        end
      end

      @doc false
      defp handle_auth_response(response, pattern, state) do
        case Auth.handle_auth_response(pattern, response, state) do
          :ok -> mark_auth_success(state)
          {:error, _} = error -> {:reply, error, state}
        end
      end

      @doc false
      defp mark_auth_success(state) do
        {:reply, :ok, %{state | authenticated: true, was_authenticated: true}}
      end

      # For re-authentication (async from handle_info)
      @doc false
      defp do_re_authenticate(config, state) do
        pattern = config[:pattern]

        case Auth.build_auth_message(pattern, state.credentials, config, []) do
          {:ok, message} -> send_re_auth_message(message, pattern, state)
          :no_message -> {:ok, %{state | authenticated: true}}
          {:error, _} = error -> error
        end
      end

      @doc false
      defp send_re_auth_message(message, pattern, state) do
        case WSClient.send_message(state.client, Jason.encode!(message)) do
          :ok -> {:ok, %{state | authenticated: true}}
          {:ok, response} -> handle_re_auth_response(response, pattern, state)
          {:error, _} = error -> error
        end
      end

      @doc false
      defp handle_re_auth_response(response, pattern, state) do
        case Auth.handle_auth_response(pattern, response, state) do
          :ok -> {:ok, %{state | authenticated: true}}
          {:error, _} = error -> error
        end
      end
    end
  end

  @doc false
  # Generates GenServer handle_cast/2 callbacks for authentication marking
  defp generate_handle_cast_callbacks do
    quote do
      # =====================================================================
      # GenServer Callbacks - handle_cast
      # =====================================================================

      @impl true
      def handle_cast(:mark_authenticated, state) do
        {:noreply, %{state | authenticated: true, was_authenticated: true}}
      end
    end
  end

  @doc false
  # Generates GenServer handle_info/2 callbacks for connect, reconnect, monitor DOWN
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp generate_handle_info_callbacks do
    quote do
      # =====================================================================
      # GenServer Callbacks - handle_info
      # =====================================================================

      @impl true
      def handle_info(:connect, state) do
        connect_opts = Keyword.put(state.opts, :handler, build_handler(state.handler))

        case WSClient.connect(state.spec, state.url_path, connect_opts) do
          {:ok, client} ->
            # Monitor the ZenWebsocket.Client GenServer
            zen_client = WSClient.get_zen_client(client)
            ref = Process.monitor(zen_client.server_pid)

            new_state = %{
              state
              | client: client,
                monitor_ref: ref,
                reconnect_attempts: 0
            }

            # W11: Re-authenticate if was previously authenticated
            if state.was_authenticated do
              send(self(), :re_authenticate)
            end

            # Restore subscriptions if any
            if state.subscriptions != [] do
              send(self(), :restore_subscriptions)
            end

            {:noreply, new_state}

          {:error, reason} ->
            Logger.warning("[#{inspect(__MODULE__)}] Connect failed: #{inspect(reason)}")
            schedule_reconnect(state)
            {:noreply, %{state | client: nil, monitor_ref: nil}}
        end
      end

      def handle_info({:DOWN, ref, :process, _pid, reason}, %{monitor_ref: ref} = state) do
        Logger.warning("[#{inspect(__MODULE__)}] Client died: #{inspect(reason)}")

        new_state = %{
          state
          | client: nil,
            monitor_ref: nil,
            authenticated: false
        }

        schedule_reconnect(new_state)
        {:noreply, new_state}
      end

      def handle_info(:restore_subscriptions, %{client: nil} = state) do
        # Not connected yet, will be called again after connect
        {:noreply, state}
      end

      def handle_info(:restore_subscriptions, %{client: client, subscriptions: subs} = state) do
        case WSClient.restore_subscriptions(client, subs) do
          :ok ->
            Logger.debug("[#{inspect(__MODULE__)}] Restored #{Enum.count(subs)} subscriptions")

          {:error, reason} ->
            Logger.warning("[#{inspect(__MODULE__)}] Failed to restore subscriptions: #{inspect(reason)}")
        end

        {:noreply, state}
      end

      def handle_info(:reconnect, state) do
        if state.reconnect_attempts < @max_reconnect_attempts do
          Logger.info("[#{inspect(__MODULE__)}] Reconnecting (attempt #{state.reconnect_attempts + 1})")
          send(self(), :connect)
          {:noreply, %{state | reconnect_attempts: state.reconnect_attempts + 1}}
        else
          Logger.error("[#{inspect(__MODULE__)}] Max reconnection attempts reached")
          {:stop, :max_reconnection_attempts, state}
        end
      end

      # W11: Re-authenticate after reconnect
      def handle_info(:re_authenticate, %{client: nil} = state) do
        # Not connected yet, will be triggered again on next connect
        {:noreply, state}
      end

      def handle_info(:re_authenticate, state) do
        auth_config = get_in(state.spec.ws, [:auth])

        case auth_config do
          nil ->
            Logger.warning("[#{inspect(__MODULE__)}] Re-auth requested but no auth config")
            {:noreply, state}

          config ->
            case do_re_authenticate(config, state) do
              {:ok, new_state} ->
                Logger.debug("[#{inspect(__MODULE__)}] Re-authenticated successfully")
                {:noreply, new_state}

              {:error, reason} ->
                Logger.warning("[#{inspect(__MODULE__)}] Re-auth failed: #{inspect(reason)}")
                {:noreply, state}
            end
        end
      end

      def handle_info(_msg, state) do
        {:noreply, state}
      end
    end
  end

  @doc false
  # Generates private helper functions for reconnection and message handling
  defp generate_private_helpers do
    quote do
      # =====================================================================
      # Private Helpers
      # =====================================================================

      @doc false
      # Schedules a reconnection attempt with exponential backoff
      defp schedule_reconnect(state) do
        # Exponential backoff: delay * 2^attempts, capped at max_backoff_ms
        delay = min(@reconnect_delay_ms * :math.pow(2, state.reconnect_attempts), @max_backoff_ms)
        Process.send_after(self(), :reconnect, trunc(delay))
      end

      @doc false
      defp build_handler(nil), do: nil

      defp build_handler(user_handler) when is_function(user_handler, 1) do
        # Wrap the user handler to handle the message format
        fn
          {:message, {:text, data}} -> user_handler.(Jason.decode!(data))
          {:message, {:binary, data}} -> user_handler.(data)
          {:message, data} when is_binary(data) -> user_handler.(Jason.decode!(data))
          {:message, data} when is_map(data) -> user_handler.(data)
          other -> user_handler.(other)
        end
      end
    end
  end

  @doc false
  # Generates the @moduledoc string for the adapter module with usage examples
  @spec generate_adapter_moduledoc(module()) :: String.t()
  defp generate_adapter_moduledoc(rest_module) do
    """
    Managed WebSocket adapter for #{inspect(rest_module)}.

    This adapter provides:
    - Automatic reconnection with exponential backoff
    - Subscription tracking and restoration
    - Authentication state tracking

    ## Usage

        # Start the adapter
        {:ok, adapter} = Adapter.start_link(
          name: :my_ws,
          url_path: [:public, :spot],
          handler: fn msg -> handle_message(msg) end
        )

        # Subscribe to channels
        :ok = Adapter.subscribe(adapter, subscription)

        # Check connection status
        if Adapter.connected?(adapter) do
          # Send message
          Adapter.send_message(adapter, %{"action" => "ping"})
        end

    ## Authentication

    For private endpoints, authentication logic is implemented separately.
    After authenticating, call `mark_authenticated/1` so the adapter knows
    to re-authenticate on reconnection.
    """
  end
end
