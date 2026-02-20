defmodule CCXT.WS.Generator.Adapter do
  @moduledoc """
  Generates WebSocket Adapter GenServer modules at compile time.

  The Adapter provides a managed WebSocket connection with:
  - Automatic reconnection with exponential backoff
  - Subscription tracking and restoration
  - Authentication state machine (unauthenticated → authenticating → authenticated → expired)
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

  alias CCXT.Extract.WsHandlerMappings

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
  @spec generate_adapter(module(), module(), map(), String.t(), keyword()) :: Macro.t()
  def generate_adapter(ws_module, rest_module, _ws_config, spec_id, pipeline \\ []) do
    normalizer = pipeline[:normalizer]
    contract = pipeline[:contract]

    # Guard: normalizer and contract must both be set or both be nil
    if !!normalizer != !!contract do
      raise ArgumentError,
            "pipeline[:normalizer] and pipeline[:contract] must both be set or both be nil"
    end

    moduledoc = generate_adapter_moduledoc(rest_module)

    quote do
      @moduledoc unquote(moduledoc)

      use GenServer

      alias CCXT.WS.Auth
      alias CCXT.WS.Auth.Expiry
      alias CCXT.WS.Client, as: WSClient
      alias CCXT.WS.Helpers
      alias CCXT.WS.MessageRouter

      require Logger

      unquote(if contract, do: quote(do: alias(unquote(contract), as: Contract)))
      unquote(if normalizer, do: quote(do: alias(unquote(normalizer), as: Normalizer)))

      unquote(generate_module_attrs(rest_module, spec_id, normalizer))
      unquote(generate_types())
      unquote(generate_client_api(ws_module, normalizer))
      unquote(generate_init_callback(rest_module, normalizer))
      unquote(generate_handle_call_callbacks())
      unquote(generate_handle_cast_callbacks())
      unquote(generate_connect_info_ast(normalizer))
      unquote(generate_monitor_info_ast())
      unquote(generate_auth_info_ast())
      unquote(generate_private_helpers(spec_id, normalizer, contract))
      unquote(generate_initial_auth_ast())
      unquote(generate_re_auth_ast())
      unquote(generate_auth_expiry_ast())
    end
  end

  # ===========================================================================
  # AST Generation Helpers
  # ===========================================================================

  @doc false
  # Generates module attributes for reconnection timing and WS normalization config
  defp generate_module_attrs(rest_module, spec_id, normalizer) do
    reconnect_delay = @reconnect_delay_ms
    max_attempts = @max_reconnect_attempts
    max_backoff = @max_backoff_ms

    # Look up envelope pattern at compile time (nil if exchange not in W13 data)
    envelope = WsHandlerMappings.envelope_pattern(spec_id)

    quote do
      @reconnect_delay_ms unquote(reconnect_delay)
      @max_reconnect_attempts unquote(max_attempts)
      @max_backoff_ms unquote(max_backoff)
      @max_re_auth_attempts 3
      @re_auth_base_delay_ms 2_000

      # WS normalization config
      @ws_exchange_id unquote(spec_id)
      unquote(if normalizer, do: quote(do: @ws_exchange_module(unquote(rest_module))))
      @ws_envelope unquote(Macro.escape(envelope))
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

      @type auth_state :: :unauthenticated | :authenticating | :authenticated | :expired

      @type state :: %{
              client: WSClient.t() | nil,
              monitor_ref: reference() | nil,
              # {tag, monitor_ref} — correlates async connect results
              connect_task: {reference(), reference()} | nil,
              auth_state: auth_state(),
              was_authenticated: boolean(),
              auth_expires_at: integer() | nil,
              auth_timer_ref: reference() | nil,
              auth_context: map() | nil,
              re_auth_attempts: non_neg_integer(),
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
  defp generate_client_api(ws_module, normalizer) do
    start_link_doc =
      if normalizer do
        """
        Starts the WebSocket adapter.

        ## Options

        - `:name` - GenServer name (optional)
        - `:url_path` - Path to WS URL in spec (e.g., `[:public, :spot]`)
        - `:credentials` - API credentials map (optional, for authenticated endpoints)
        - `:handler` - Message handler function `fn msg -> ... end`
        - `:normalize` - Normalize WS payloads to typed structs (default: true)
        - `:validate` - Validate normalized payloads against W12 contracts (default: false)
        - `:sandbox` - Use testnet URLs (default: false)
        - `:debug` - Enable debug logging (default: false)

        ## Examples

            {:ok, adapter} = Adapter.start_link(
              name: :bybit_public,
              url_path: [:public, :spot],
              handler: fn msg -> msg end
            )

        """
      else
        """
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
      end

    quote do
      # =====================================================================
      # Client API
      # =====================================================================

      @doc unquote(start_link_doc)
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
      Returns the current authentication state.

      ## Returns

      - `:unauthenticated` - Not authenticated
      - `:authenticating` - Authentication in progress
      - `:authenticated` - Successfully authenticated
      - `:expired` - Authentication expired (will auto re-auth for WS-native patterns)

      """
      @spec auth_state(GenServer.server()) :: :unauthenticated | :authenticating | :authenticated | :expired
      def auth_state(adapter) do
        GenServer.call(adapter, :auth_state)
      end

      @doc """
      Returns the current adapter state.
      """
      @spec get_state(GenServer.server()) :: {:ok, map()}
      def get_state(adapter) do
        GenServer.call(adapter, :get_state)
      end

      @doc """
      Returns the connection state without raising on timeout.

      Unlike `connected?/1`, this function never crashes — if the GenServer
      is busy (e.g., during a blocking connect), it returns `:connecting`
      instead of raising a timeout error.

      ## Returns

      - `:connected` - WebSocket is connected
      - `:connecting` - Connection attempt in progress
      - `:disconnected` - Not connected (or process dead)

      """
      @connection_state_timeout_ms 200

      @spec connection_state(GenServer.server(), non_neg_integer()) ::
              :connected | :connecting | :disconnected
      def connection_state(adapter, timeout \\ @connection_state_timeout_ms) do
        GenServer.call(adapter, :get_connection_state, timeout)
      catch
        :exit, {:timeout, _} ->
          if Process.alive?(adapter), do: :connecting, else: :disconnected

        :exit, {:noproc, _} ->
          :disconnected

        :exit, reason ->
          Logger.debug("[connection_state] Unexpected exit: #{inspect(reason)}")
          :disconnected
      end

      @doc """
      Returns the connection status.

      Delegates to `connection_state/1` — never raises on timeout.
      """
      @spec connected?(GenServer.server()) :: boolean()
      def connected?(adapter) do
        connection_state(adapter) == :connected
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
  defp generate_init_callback(rest_module, normalizer) do
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
          connect_task: nil,
          auth_state: :unauthenticated,
          was_authenticated: false,
          auth_expires_at: nil,
          auth_timer_ref: nil,
          auth_context: nil,
          re_auth_attempts: 0,
          subscriptions: [],
          credentials: Keyword.get(opts, :credentials),
          spec: spec,
          url_path: url_path,
          opts: opts,
          handler: Keyword.get(opts, :handler),
          reconnect_attempts: 0
        }

        unquote(
          if normalizer do
            quote do
              state =
                Map.merge(state, %{
                  normalize: Keyword.get(opts, :normalize, true),
                  validate: Keyword.get(opts, :validate, false)
                })
            end
          end
        )

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
        # For inline_subscribe: merge auth data into subscribe message
        enriched_sub = maybe_enrich_with_auth(subscription, state)

        case WSClient.subscribe(client, enriched_sub) do
          :ok ->
            new_subs = [enriched_sub | state.subscriptions]
            {:reply, :ok, %{state | subscriptions: new_subs}}

          {:ok, _response} ->
            new_subs = [enriched_sub | state.subscriptions]
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
        # Backward compat: derive authenticated boolean from auth_state
        compat_state = Map.put(state, :authenticated, state.auth_state == :authenticated)
        {:reply, {:ok, compat_state}, state}
      end

      def handle_call(:auth_state, _from, state) do
        {:reply, state.auth_state, state}
      end

      def handle_call(:get_connection_state, _from, %{client: nil, connect_task: {_, _}} = state) do
        {:reply, :connecting, state}
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
      # Already authenticated — no-op
      def handle_call(:authenticate, _from, %{auth_state: :authenticated} = state) do
        {:reply, :ok, state}
      end

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
  # Generates initial authentication functions (do_authenticate, send_auth_message, etc.)
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp generate_initial_auth_ast do
    quote do
      @doc false
      defp do_authenticate(config, state) do
        pattern = config[:pattern]
        market_type = resolve_market_type(state)
        opts = [market_type: market_type]
        context = %{pattern: pattern, market_type: market_type}

        # Step 1: Pre-auth (REST token/listen key metadata if needed)
        case Auth.pre_auth(pattern, state.credentials, config, opts) do
          {:ok, pre_auth_data} when pre_auth_data == %{} ->
            # WS-native pattern (no external pre-auth needed)
            state = %{state | auth_state: :authenticating}

            case Auth.build_auth_message(pattern, state.credentials, config, opts) do
              {:ok, message} -> send_auth_message(message, context, state)
              :no_message -> mark_auth_success(state, context)
              {:error, _} = error -> {:reply, error, %{state | auth_state: :unauthenticated}}
            end

          {:ok, pre_auth_data} ->
            # External pre-auth required (listen_key, rest_token).
            # State stays :authenticating until caller completes via mark_authenticated/1.
            # If the caller never follows through, a subsequent authenticate/1 call
            # or disconnect will reset state. No automatic timeout — caller owns the flow.
            ctx = Map.put(context, :pre_auth, pre_auth_data)

            state = %{state | auth_state: :authenticating, auth_context: ctx}
            {:reply, {:error, {:pre_auth_required, pre_auth_data}}, state}

          {:error, _} = error ->
            {:reply, error, state}
        end
      end

      @doc false
      defp send_auth_message(message, context, state) do
        case WSClient.send_message(state.client, Jason.encode!(message)) do
          :ok ->
            mark_auth_success(state, context)

          {:ok, response} ->
            handle_auth_response(response, context, state)

          {:error, _} = error ->
            {:reply, error, %{state | auth_state: :unauthenticated}}
        end
      end

      @doc false
      defp handle_auth_response(response, context, state) do
        case Auth.handle_auth_response(context.pattern, response, state) do
          :ok ->
            mark_auth_success(state, context)

          {:ok, auth_meta} ->
            mark_auth_success(state, context, auth_meta)

          {:error, _} = error ->
            {:reply, error, %{state | auth_state: :unauthenticated}}
        end
      end

      @doc false
      defp mark_auth_success(state, context, auth_meta \\ nil) do
        # Cancel any existing auth expiry timer
        if state.auth_timer_ref, do: Process.cancel_timer(state.auth_timer_ref)

        auth_config = get_in(state.spec.ws, [:auth])
        {timer_ref, expires_at} = schedule_auth_expiry(auth_meta, auth_config)

        new_state = %{
          state
          | auth_state: :authenticated,
            was_authenticated: true,
            auth_context: context,
            re_auth_attempts: 0,
            auth_timer_ref: timer_ref,
            auth_expires_at: expires_at
        }

        {:reply, :ok, new_state}
      end
    end
  end

  @doc false
  # Generates re-authentication functions (do_re_authenticate, send_re_auth_message, etc.)
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp generate_re_auth_ast do
    quote do
      # For re-authentication (async from handle_info)
      @doc false
      defp do_re_authenticate(config, state) do
        pattern = config[:pattern]
        market_type = resolve_market_type(state)
        opts = [market_type: market_type]
        context = %{pattern: pattern, market_type: market_type}

        case Auth.pre_auth(pattern, state.credentials, config, opts) do
          {:ok, pre_auth_data} when pre_auth_data == %{} ->
            # WS-native: build and send auth message
            case Auth.build_auth_message(pattern, state.credentials, config, opts) do
              {:ok, message} -> send_re_auth_message(message, context, state)
              :no_message -> re_auth_success(state, context)
              {:error, _} = error -> error
            end

          {:ok, _pre_auth_data} ->
            # External pre-auth: can't re-auth automatically
            {:error, :pre_auth_required}

          {:error, _} = error ->
            error
        end
      end

      @doc false
      defp send_re_auth_message(message, context, state) do
        case WSClient.send_message(state.client, Jason.encode!(message)) do
          :ok ->
            re_auth_success(state, context)

          {:ok, response} ->
            handle_re_auth_response(response, context, state)

          {:error, _} = error ->
            error
        end
      end

      @doc false
      defp handle_re_auth_response(response, context, state) do
        case Auth.handle_auth_response(context.pattern, response, state) do
          :ok ->
            re_auth_success(state, context)

          {:ok, auth_meta} ->
            re_auth_success(state, context, auth_meta)

          {:error, _} = error ->
            error
        end
      end

      @doc false
      defp re_auth_success(state, context, auth_meta \\ nil) do
        # Cancel any existing auth expiry timer
        if state.auth_timer_ref, do: Process.cancel_timer(state.auth_timer_ref)

        auth_config = get_in(state.spec.ws, [:auth])
        {timer_ref, expires_at} = schedule_auth_expiry(auth_meta, auth_config)

        {:ok,
         %{
           state
           | auth_state: :authenticated,
             auth_context: context,
             re_auth_attempts: 0,
             auth_timer_ref: timer_ref,
             auth_expires_at: expires_at
         }}
      end
    end
  end

  @doc false
  # Generates auth expiry scheduling function
  defp generate_auth_expiry_ast do
    quote do
      @doc false
      # Computes and schedules auth expiry timer via Expiry pure functions.
      # Returns {timer_ref, expires_at} or {nil, nil} when no TTL available.
      defp schedule_auth_expiry(auth_meta, auth_config) do
        ttl_ms = Expiry.compute_ttl_ms(auth_meta, auth_config)

        case Expiry.schedule_delay_ms(ttl_ms) do
          nil ->
            {nil, nil}

          delay_ms ->
            ref = Process.send_after(self(), :auth_expired, delay_ms)
            {ref, System.monotonic_time(:millisecond) + delay_ms}
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
      # External pre-auth path (listen_key/rest_token) — expiry is caller-managed,
      # so no auth_expired timer is scheduled here intentionally.
      def handle_cast(:mark_authenticated, state) do
        {:noreply, %{state | auth_state: :authenticated, was_authenticated: true, re_auth_attempts: 0}}
      end
    end
  end

  @doc false
  # Generates handle_info callbacks for :connect and connect_result messages
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp generate_connect_info_ast(normalizer) do
    build_handler_ast =
      if normalizer do
        quote do: build_handler(state.handler, state.normalize, state.validate)
      else
        quote do: build_handler(state.handler)
      end

    quote do
      # =====================================================================
      # GenServer Callbacks - handle_info
      # =====================================================================

      @impl true
      # Guard: already connecting — don't spawn a second task
      def handle_info(:connect, %{connect_task: {_, _}} = state) do
        {:noreply, state}
      end

      def handle_info(:connect, state) do
        connect_opts = Keyword.put(state.opts, :handler, unquote(build_handler_ast))
        parent = self()

        # Non-blocking connect via spawn_monitor (no link — crash won't kill GenServer)
        # Use a unique tag so the spawned fn can reference it (avoiding macro hygiene issues
        # with the monitor ref which isn't available until spawn_monitor returns).
        tag = make_ref()

        {_pid, monitor_ref} =
          spawn_monitor(fn ->
            result = maybe_listen_key_connect(state, connect_opts)
            send(parent, {:connect_result, tag, result})
          end)

        {:noreply, %{state | connect_task: {tag, monitor_ref}}}
      end

      # Listen-key connect completed: already authenticated via URL
      def handle_info({:connect_result, tag, {:ok, {:listen_key_connected, client}}}, state) do
        case state.connect_task do
          {^tag, monitor_ref} ->
            Process.demonitor(monitor_ref, [:flush])

            zen_client = WSClient.get_zen_client(client)
            ws_monitor_ref = Process.monitor(zen_client.server_pid)

            new_state = %{
              state
              | client: client,
                monitor_ref: ws_monitor_ref,
                connect_task: nil,
                reconnect_attempts: 0,
                auth_state: :authenticated,
                was_authenticated: true,
                re_auth_attempts: 0
            }

            # Restore subscriptions (skip re_authenticate — already done via URL)
            if state.subscriptions != [], do: send(self(), :restore_subscriptions)

            {:noreply, new_state}

          _ ->
            {:noreply, state}
        end
      end

      # Async connect completed successfully
      def handle_info({:connect_result, tag, {:ok, client}}, state) do
        case state.connect_task do
          {^tag, monitor_ref} ->
            Process.demonitor(monitor_ref, [:flush])

            zen_client = WSClient.get_zen_client(client)
            ws_monitor_ref = Process.monitor(zen_client.server_pid)

            new_state = %{
              state
              | client: client,
                monitor_ref: ws_monitor_ref,
                connect_task: nil,
                reconnect_attempts: 0
            }

            # W11: Re-authenticate if was previously authenticated
            if state.was_authenticated, do: send(self(), :re_authenticate)

            # Restore subscriptions if any
            if state.subscriptions != [], do: send(self(), :restore_subscriptions)

            {:noreply, new_state}

          _ ->
            # Stale result from a previous connect attempt — ignore
            {:noreply, state}
        end
      end

      # Async connect returned an error
      def handle_info({:connect_result, tag, {:error, reason}}, state) do
        case state.connect_task do
          {^tag, monitor_ref} ->
            Process.demonitor(monitor_ref, [:flush])
            Logger.warning("[#{inspect(__MODULE__)}] Connect failed: #{inspect(reason)}")
            schedule_reconnect(state)
            {:noreply, %{state | client: nil, monitor_ref: nil, connect_task: nil}}

          _ ->
            {:noreply, state}
        end
      end
    end
  end

  @doc false
  # Generates handle_info callbacks for :DOWN, :restore_subscriptions, :reconnect
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp generate_monitor_info_ast do
    quote do
      # Connect worker crashed before sending result
      def handle_info({:DOWN, down_ref, :process, _pid, reason}, %{connect_task: {_tag, down_ref}} = state) do
        Logger.warning("[#{inspect(__MODULE__)}] Connect worker crashed: #{inspect(reason)}")
        schedule_reconnect(state)
        {:noreply, %{state | connect_task: nil}}
      end

      # WS client process died (monitored zen_client)
      def handle_info({:DOWN, ref, :process, _pid, reason}, %{monitor_ref: ref} = state) do
        Logger.warning("[#{inspect(__MODULE__)}] Client died: #{inspect(reason)}")

        # Cancel auth expiry timer if active
        if state.auth_timer_ref, do: Process.cancel_timer(state.auth_timer_ref)

        new_state = %{
          state
          | client: nil,
            monitor_ref: nil,
            auth_state: :unauthenticated,
            auth_timer_ref: nil,
            auth_expires_at: nil
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
    end
  end

  @doc false
  # Generates handle_info callbacks for :re_authenticate, :auth_expired, catch-all
  defp generate_auth_info_ast do
    quote do
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
            state = %{state | auth_state: :authenticating}

            case do_re_authenticate(config, state) do
              {:ok, new_state} ->
                Logger.debug("[#{inspect(__MODULE__)}] Re-authenticated successfully")
                {:noreply, new_state}

              {:error, reason} ->
                Logger.warning("[#{inspect(__MODULE__)}] Re-auth failed: #{inspect(reason)}")
                schedule_re_auth_retry(state)
            end
        end
      end

      # Auth expiry handler — transitions to :expired, triggers re-auth
      def handle_info(:auth_expired, state) do
        Logger.info("[#{inspect(__MODULE__)}] Auth expired, triggering re-authentication")

        new_state = %{state | auth_state: :expired, auth_timer_ref: nil, auth_expires_at: nil}
        send(self(), :re_authenticate)
        {:noreply, new_state}
      end

      def handle_info(_msg, state) do
        {:noreply, state}
      end
    end
  end

  @doc false
  # Assembles private helper functions from sub-generators.
  # Conditionally generates deliver_message/N based on envelope config.
  defp generate_private_helpers(spec_id, normalizer, _contract) do
    envelope = WsHandlerMappings.envelope_pattern(spec_id)
    deliver_message_ast = generate_deliver_message_ast(envelope, normalizer)

    quote do
      unquote(generate_reconnect_helpers_ast())
      unquote(generate_market_type_helpers_ast())
      unquote(generate_listen_key_helpers_ast())
      unquote(generate_auth_enrichment_ast())
      unquote(deliver_message_ast)
      unquote(generate_build_handler_ast(normalizer))
    end
  end

  @doc false
  # Generates the appropriate deliver_message/N variant based on envelope and normalizer config
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp generate_deliver_message_ast(envelope, normalizer) do
    case {envelope != nil, normalizer != nil} do
      {true, true} ->
        # Full routing + normalization + validation pipeline
        quote do
          @doc false
          # Bypass normalization when normalize=false — raw passthrough
          defp deliver_message(decoded, user_handler, false, _validate) do
            user_handler.({:raw, decoded})
          end

          defp deliver_message(decoded, user_handler, true, validate) do
            case MessageRouter.route(decoded, @ws_envelope, @ws_exchange_id) do
              {:routed, family, payload} ->
                normalize_and_deliver(family, payload, user_handler, validate)

              {:system, _msg} ->
                user_handler.({:system, decoded})

              {:unknown, _msg} ->
                user_handler.({:raw, decoded})
            end
          end

          @doc false
          defp normalize_and_deliver(family, payload, user_handler, validate) do
            case Normalizer.normalize(family, payload, @ws_exchange_module) do
              {:ok, normalized} ->
                maybe_validate(family, normalized, validate)
                user_handler.({family, normalized})

              {:error, _reason} ->
                user_handler.({family, payload})
            end
          end

          @doc false
          defp maybe_validate(_family, _normalized, false), do: :ok

          defp maybe_validate(family, normalized, true) do
            case Contract.validate(family, normalized) do
              {:ok, _} ->
                :ok

              {:error, violations} ->
                Logger.warning("[WS.Adapter] Contract violation for #{family}: #{inspect(violations)}")
            end
          end
        end

      {true, false} ->
        # Routing only, raw family+payload delivery (current ccxt_ex default)
        quote do
          @doc false
          # Routes via MessageRouter when envelope config is available
          defp deliver_message(decoded, user_handler) do
            case MessageRouter.route(decoded, @ws_envelope, @ws_exchange_id) do
              {:routed, family, payload} ->
                user_handler.({family, payload})

              {:system, _msg} ->
                user_handler.({:system, decoded})

              {:unknown, _msg} ->
                user_handler.({:raw, decoded})
            end
          end
        end

      {false, true} ->
        # No envelope, but normalizer present — passthrough with /4 arity
        quote do
          @doc false
          defp deliver_message(decoded, user_handler, _normalize, _validate) do
            user_handler.({:raw, decoded})
          end
        end

      {false, false} ->
        # No envelope, no normalizer — simple passthrough
        quote do
          @doc false
          # No envelope config — pass raw decoded messages directly
          defp deliver_message(decoded, user_handler) do
            user_handler.({:raw, decoded})
          end
        end
    end
  end

  @doc false
  # Generates schedule_reconnect and schedule_re_auth_retry helpers
  defp generate_reconnect_helpers_ast do
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
      # Schedules a re-auth retry with exponential backoff, or gives up after max attempts
      defp schedule_re_auth_retry(state) do
        attempts = state.re_auth_attempts + 1

        if attempts > @max_re_auth_attempts do
          Logger.error("[#{inspect(__MODULE__)}] Max re-auth attempts (#{@max_re_auth_attempts}) reached")
          {:noreply, %{state | auth_state: :unauthenticated, re_auth_attempts: attempts}}
        else
          delay = min(@re_auth_base_delay_ms * :math.pow(2, attempts - 1), @max_backoff_ms)
          Process.send_after(self(), :re_authenticate, trunc(delay))
          {:noreply, %{state | auth_state: :unauthenticated, re_auth_attempts: attempts}}
        end
      end
    end
  end

  @doc false
  # Generates resolve_market_type and derive_market_type_from_url_path helpers
  defp generate_market_type_helpers_ast do
    quote do
      @doc false
      # Resolves market type from auth_context, url_path derivation, or :spot default
      defp resolve_market_type(state) do
        (state.auth_context && state.auth_context[:market_type]) ||
          derive_market_type_from_url_path(state.url_path) ||
          :spot
      end

      @doc false
      defp derive_market_type_from_url_path(path) when is_list(path) do
        Enum.find(path, fn
          t when t in [:spot, :linear, :inverse, :option, :swap, :future, :contract] -> true
          _ -> false
        end)
      end

      defp derive_market_type_from_url_path(_), do: nil
    end
  end

  @doc false
  # Generates listen key acquisition functions (maybe_listen_key_connect, etc.)
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp generate_listen_key_helpers_ast do
    quote do
      @doc false
      # Checks if auth pattern is :listen_key with credentials, and if so,
      # acquires listen key via REST before connecting. Otherwise, normal connect.
      defp maybe_listen_key_connect(state, connect_opts) do
        auth_config = get_in(state.spec.ws, [:auth])

        if auth_config[:pattern] == :listen_key && state.credentials do
          acquire_listen_key_and_connect(state, connect_opts, auth_config)
        else
          WSClient.connect(state.spec, state.url_path, connect_opts)
        end
      end

      @doc false
      # Acquires a listen key via REST, appends it to the WS URL, and connects.
      # Returns {:ok, {:listen_key_connected, client}} on success.
      defp acquire_listen_key_and_connect(state, connect_opts, auth_config) do
        market_type = resolve_market_type(state)

        with {:ok, pre_auth_data} <-
               Auth.pre_auth(:listen_key, state.credentials, auth_config, market_type: market_type),
             {:ok, listen_key} <- fetch_listen_key(pre_auth_data, state),
             {:ok, ws_base_url} <- Helpers.resolve_url(state.spec, state.url_path, connect_opts),
             ws_url = ws_base_url <> "/" <> listen_key,
             {:ok, client} <-
               WSClient.connect(state.spec, state.url_path, Keyword.put(connect_opts, :url, ws_url)) do
          {:ok, {:listen_key_connected, client}}
        end
      end

      @doc false
      # Makes the REST call to acquire a listen key from Binance-style endpoints.
      # Requires api_section and path in pre_auth_data (from enriched extractor).
      defp fetch_listen_key(pre_auth_data, state) do
        with {:ok, url} <- build_listen_key_url(pre_auth_data, state) do
          # TODO: Header is Binance-specific. If another exchange adopts :listen_key,
          # extract header name to spec metadata.
          headers = [{"X-MBX-APIKEY", state.credentials.api_key}]
          do_fetch_listen_key(url, headers)
        end
      end

      @doc false
      defp build_listen_key_url(pre_auth_data, state) do
        api_section = pre_auth_data[:api_section]
        path = pre_auth_data[:path]

        if is_nil(api_section) or is_nil(path) do
          {:error,
           {:listen_key_missing_config,
            %{api_section: api_section, path: path, hint: "Spec may need re-sync: mix ccxt.sync binance --force"}}}
        else
          sandbox? = state.credentials.sandbox == true
          base_url = CCXT.Spec.rest_api_url(state.spec, api_section, sandbox?)

          if base_url,
            do: {:ok, base_url <> path},
            else: {:error, {:listen_key_no_base_url, %{api_section: api_section, sandbox: sandbox?}}}
        end
      end

      @doc false
      defp do_fetch_listen_key(url, headers) do
        case CCXT.HTTP.Client.raw_request(:post, url, headers, "", []) do
          {:ok, %{status: 200, body: body}} -> extract_listen_key(body)
          {:ok, %{status: status, body: body}} -> {:error, {:listen_key_http_error, %{status: status, body: body}}}
          {:error, reason} -> {:error, {:listen_key_request_failed, reason}}
        end
      end

      @doc false
      defp extract_listen_key(body) when is_map(body) do
        case body["listenKey"] do
          key when is_binary(key) -> {:ok, key}
          _ -> {:error, {:listen_key_missing_in_response, body}}
        end
      end

      defp extract_listen_key(body) when is_binary(body) do
        case Jason.decode(body) do
          {:ok, %{"listenKey" => key}} -> {:ok, key}
          _ -> {:error, {:listen_key_parse_error, body}}
        end
      end
    end
  end

  @doc false
  # Generates maybe_enrich_with_auth for inline_subscribe pattern
  defp generate_auth_enrichment_ast do
    quote do
      @doc false
      # For inline_subscribe pattern: merge auth data into subscribe message
      # when the subscription requires authentication.
      defp maybe_enrich_with_auth(%{auth_required: true, message: message} = sub, state) do
        auth_config = get_in(state.spec.ws, [:auth])
        pattern = auth_config && auth_config[:pattern]

        if pattern == :inline_subscribe && state.credentials do
          case Auth.build_subscribe_auth(pattern, state.credentials, auth_config, nil, nil) do
            nil -> sub
            auth_data -> %{sub | message: Map.merge(message, auth_data)}
          end
        else
          sub
        end
      end

      defp maybe_enrich_with_auth(sub, _state), do: sub
    end
  end

  @doc false
  # Generates build_handler and safe_decode_and_deliver, conditioned on normalizer
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp generate_build_handler_ast(normalizer) do
    if normalizer do
      quote do
        @doc false
        defp build_handler(nil, _normalize, _validate), do: nil

        defp build_handler(user_handler, normalize, validate)
             when is_function(user_handler, 1) do
          # Wrap the user handler to decode, optionally route+normalize, then deliver
          fn
            {:message, {:text, data}} ->
              safe_decode_and_deliver(data, user_handler, normalize, validate)

            {:message, {:binary, data}} ->
              user_handler.(data)

            {:message, data} when is_binary(data) ->
              safe_decode_and_deliver(data, user_handler, normalize, validate)

            {:message, data} when is_map(data) ->
              deliver_message(data, user_handler, normalize, validate)

            other ->
              user_handler.(other)
          end
        end

        @doc false
        # Decodes JSON safely, falling back to raw delivery on malformed data
        defp safe_decode_and_deliver(data, user_handler, normalize, validate) do
          case Jason.decode(data) do
            {:ok, decoded} ->
              deliver_message(decoded, user_handler, normalize, validate)

            {:error, _reason} ->
              Logger.warning("[#{inspect(__MODULE__)}] Failed to decode WS message as JSON")

              user_handler.({:raw, data})
          end
        end
      end
    else
      quote do
        @doc false
        defp build_handler(nil), do: nil

        defp build_handler(user_handler) when is_function(user_handler, 1) do
          # Wrap the user handler to decode, route via MessageRouter, then deliver
          fn
            {:message, {:text, data}} ->
              safe_decode_and_deliver(data, user_handler)

            {:message, {:binary, data}} ->
              user_handler.(data)

            {:message, data} when is_binary(data) ->
              safe_decode_and_deliver(data, user_handler)

            {:message, data} when is_map(data) ->
              deliver_message(data, user_handler)

            other ->
              user_handler.(other)
          end
        end

        @doc false
        # Decodes JSON safely, falling back to raw delivery on malformed data
        defp safe_decode_and_deliver(data, user_handler) do
          case Jason.decode(data) do
            {:ok, decoded} ->
              deliver_message(decoded, user_handler)

            {:error, _reason} ->
              Logger.warning("[#{inspect(__MODULE__)}] Failed to decode WS message as JSON")

              user_handler.({:raw, data})
          end
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
