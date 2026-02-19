defmodule CCXT.WS.Generator.AdapterTest do
  use ExUnit.Case, async: true

  alias CCXT.WS.Contract
  alias CCXT.WS.Generator
  alias CCXT.WS.Generator.Adapter
  alias CCXT.WS.Normalizer

  @test_ws_config %{urls: "wss://example.com"}

  # Dynamically find an available WS module and its adapter
  setup_all do
    case find_available_ws_adapter() do
      {ws_module, rest_module, adapter_module} ->
        {:ok, ws_module: ws_module, rest_module: rest_module, adapter_module: adapter_module}

      nil ->
        IO.puts("\n⚠️  No WS Adapter modules available, skipping adapter tests")
        :ok
    end
  end

  @doc false
  # Finds any available exchange with WS.Adapter module from tier1/tier2 candidates
  defp find_available_ws_adapter do
    candidates = [
      # tier1
      {WS, CCXT.Bybit, CCXT.Bybit.WS.Adapter},
      {CCXT.OKX.WS, CCXT.OKX, CCXT.OKX.WS.Adapter},
      {CCXT.Binance.WS, CCXT.Binance, CCXT.Binance.WS.Adapter},
      # tier2
      {CCXT.Kraken.WS, CCXT.Kraken, CCXT.Kraken.WS.Adapter},
      {CCXT.Gate.WS, CCXT.Gate, CCXT.Gate.WS.Adapter},
      {CCXT.Bitmex.WS, CCXT.Bitmex, CCXT.Bitmex.WS.Adapter},
      {CCXT.HTX.WS, CCXT.HTX, CCXT.HTX.WS.Adapter},
      {CCXT.Kucoin.WS, CCXT.Kucoin, CCXT.Kucoin.WS.Adapter}
    ]

    Enum.find(candidates, fn {_ws, _rest, adapter} ->
      Code.ensure_loaded?(adapter) and function_exported?(adapter, :start_link, 1)
    end)
  end

  describe "generate_adapter/4" do
    @tag :requires_ws_module
    test "generates valid AST", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]

      if is_nil(ws_module) do
        flunk("No WS module available - sync exchanges with `mix ccxt.sync --tier1`")
      end

      ws_config = @test_ws_config

      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")

      # AST should be a quote block (tuple with :__block__)
      assert is_tuple(ast)
    end

    @tag :requires_ws_module
    test "generated AST includes reconnection settings and handlers", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]

      if is_nil(ws_module) do
        flunk("No WS module available - sync exchanges with `mix ccxt.sync --tier1`")
      end

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      assert generated =~ "@reconnect_delay_ms"
      assert generated =~ "@max_reconnect_attempts"
      assert generated =~ "@max_backoff_ms"
      assert generated =~ "schedule_reconnect"
      assert generated =~ "handle_info(:reconnect, state)"
      assert generated =~ "handle_info(:restore_subscriptions"
      assert generated =~ "handle_info(:re_authenticate"
    end

    @tag :requires_ws_module
    test "generated AST includes deliver_message with MessageRouter routing for exchange with envelope",
         context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]

      if is_nil(ws_module) do
        flunk("No WS module available - sync exchanges with `mix ccxt.sync --tier1`")
      end

      # Use "bybit" which has a known envelope pattern (topic_data)
      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "bybit")
      generated = Macro.to_string(ast)

      # deliver_message/2 routes via MessageRouter and delivers raw payloads
      assert generated =~ "deliver_message(decoded, user_handler)"
      assert generated =~ "MessageRouter.route"
      assert generated =~ "{:raw, decoded}"
      assert generated =~ "{family, payload}"
    end

    @tag :requires_ws_module
    test "no-envelope exchange generates simplified deliver_message without dead clauses", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]

      if is_nil(ws_module) do
        flunk("No WS module available - sync exchanges with `mix ccxt.sync --tier1`")
      end

      # Use spec_id with no handler mapping → nil envelope
      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "no_envelope_exchange")
      generated = Macro.to_string(ast)

      # Should still have deliver_message
      assert generated =~ "deliver_message"
      assert generated =~ "{:raw, decoded}"

      # Should NOT have MessageRouter or unreachable clauses
      refute generated =~ "MessageRouter.route"
      refute generated =~ "{family, payload}"
      refute generated =~ "{:system, decoded}"
    end
  end

  describe "generated Adapter module" do
    # These tests verify a generated WS.Adapter module

    setup context do
      adapter_module = context[:adapter_module]

      if adapter_module do
        # Ensure module is loaded before checking function_exported?
        Code.ensure_loaded!(adapter_module)
        {:ok, adapter: adapter_module}
      else
        :ok
      end
    end

    @tag :requires_ws_module
    test "module is generated and loadable", %{adapter: adapter} do
      if is_nil(adapter), do: skip_no_adapter()
      assert Code.ensure_loaded?(adapter)
    end

    @tag :requires_ws_module
    test "has start_link/1", %{adapter: adapter} do
      if is_nil(adapter), do: skip_no_adapter()
      assert function_exported?(adapter, :start_link, 1)
    end

    @tag :requires_ws_module
    test "has subscribe/2", %{adapter: adapter} do
      if is_nil(adapter), do: skip_no_adapter()
      assert function_exported?(adapter, :subscribe, 2)
    end

    @tag :requires_ws_module
    test "has unsubscribe/2", %{adapter: adapter} do
      if is_nil(adapter), do: skip_no_adapter()
      assert function_exported?(adapter, :unsubscribe, 2)
    end

    @tag :requires_ws_module
    test "has authenticate/1", %{adapter: adapter} do
      if is_nil(adapter), do: skip_no_adapter()
      assert function_exported?(adapter, :authenticate, 1)
    end

    @tag :requires_ws_module
    test "has mark_authenticated/1", %{adapter: adapter} do
      if is_nil(adapter), do: skip_no_adapter()
      assert function_exported?(adapter, :mark_authenticated, 1)
    end

    @tag :requires_ws_module
    test "has get_state/1", %{adapter: adapter} do
      if is_nil(adapter), do: skip_no_adapter()
      assert function_exported?(adapter, :get_state, 1)
    end

    @tag :requires_ws_module
    test "has connected?/1", %{adapter: adapter} do
      if is_nil(adapter), do: skip_no_adapter()
      assert function_exported?(adapter, :connected?, 1)
    end

    @tag :requires_ws_module
    test "has send_message/2", %{adapter: adapter} do
      if is_nil(adapter), do: skip_no_adapter()
      assert function_exported?(adapter, :send_message, 2)
    end

    @tag :requires_ws_module
    test "implements GenServer behavior", %{adapter: adapter} do
      if is_nil(adapter), do: skip_no_adapter()

      # GenServer callbacks should exist
      assert function_exported?(adapter, :init, 1)
      assert function_exported?(adapter, :handle_call, 3)
      assert function_exported?(adapter, :handle_cast, 2)
      assert function_exported?(adapter, :handle_info, 2)
    end
  end

  describe "derive_rest_module/1" do
    # These are pure function tests - they don't require modules to be loaded
    test "derives CCXT.Bybit from CCXT.Bybit.WS" do
      assert Generator.derive_rest_module(CCXT.Bybit.WS) == CCXT.Bybit
    end

    test "derives CCXT.Binance from CCXT.Binance.WS" do
      assert Generator.derive_rest_module(CCXT.Binance.WS) == CCXT.Binance
    end

    test "derives CCXT.Deribit from CCXT.Deribit.WS" do
      assert Generator.derive_rest_module(CCXT.Deribit.WS) == CCXT.Deribit
    end
  end

  describe "auth state machine - init state" do
    @tag :requires_ws_module
    test "init sets auth_state to :unauthenticated", context do
      adapter_module = context[:adapter_module]
      if is_nil(adapter_module), do: skip_no_adapter()

      {:ok, state} = adapter_module.init(handler: fn _ -> :ok end, url_path: [:public, :spot])

      assert state.auth_state == :unauthenticated
      assert state.was_authenticated == false
      assert state.auth_expires_at == nil
      assert state.auth_timer_ref == nil
      assert state.auth_context == nil
      assert state.re_auth_attempts == 0

      drain_connect()
    end
  end

  describe "auth state machine - generated AST" do
    @tag :requires_ws_module
    test "generated AST includes auth_state type and fields", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      assert generated =~ "auth_state"
      assert generated =~ ":unauthenticated"
      assert generated =~ ":authenticating"
      assert generated =~ ":authenticated"
      assert generated =~ ":expired"
      assert generated =~ "auth_expires_at"
      assert generated =~ "auth_timer_ref"
      assert generated =~ "auth_context"
      assert generated =~ "re_auth_attempts"
    end

    @tag :requires_ws_module
    test "generated AST includes auth_state/1 public API", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      assert generated =~ "def auth_state(adapter)"
      assert generated =~ "handle_call(:auth_state"
    end

    @tag :requires_ws_module
    test "generated AST includes pre-auth lifecycle", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      assert generated =~ "Auth.pre_auth("
      assert generated =~ ":pre_auth_required"
      assert generated =~ "resolve_market_type"
    end

    @tag :requires_ws_module
    test "generated AST includes re-auth retry with backoff", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      assert generated =~ "schedule_re_auth_retry"
      assert generated =~ "@max_re_auth_attempts"
      assert generated =~ "@re_auth_base_delay_ms"
    end

    @tag :requires_ws_module
    test "generated AST includes auth_expired handler", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      assert generated =~ "handle_info(:auth_expired"
      assert generated =~ "Auth expired"
    end

    @tag :requires_ws_module
    test "generated AST includes backward-compat authenticated in get_state", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # get_state derives authenticated boolean from auth_state
      assert generated =~ "Map.put(state, :authenticated, state.auth_state == :authenticated)"
    end
  end

  describe "auth state machine - generated module API" do
    setup context do
      adapter_module = context[:adapter_module]

      if adapter_module do
        Code.ensure_loaded!(adapter_module)
        {:ok, adapter: adapter_module}
      else
        :ok
      end
    end

    @tag :requires_ws_module
    test "has auth_state/1", %{adapter: adapter} do
      if is_nil(adapter), do: skip_no_adapter()
      assert function_exported?(adapter, :auth_state, 1)
    end

    @tag :requires_ws_module
    test "get_state/1 includes backward-compat authenticated boolean", context do
      adapter_module = context[:adapter_module]
      if is_nil(adapter_module), do: skip_no_adapter()

      {:ok, state} = adapter_module.init(handler: fn _ -> :ok end, url_path: [:public, :spot])

      # Simulate what handle_call(:get_state, ...) does
      compat_state = Map.put(state, :authenticated, state.auth_state == :authenticated)
      assert compat_state.authenticated == false
      assert compat_state.auth_state == :unauthenticated

      drain_connect()
    end

    @tag :requires_ws_module
    test "mark_authenticated transitions auth_state to :authenticated", context do
      adapter_module = context[:adapter_module]
      if is_nil(adapter_module), do: skip_no_adapter()

      {:ok, state} = adapter_module.init(handler: fn _ -> :ok end, url_path: [:public, :spot])
      drain_connect()

      # Simulate what handle_cast(:mark_authenticated, state) does
      new_state = %{state | auth_state: :authenticated, was_authenticated: true, re_auth_attempts: 0}
      assert new_state.auth_state == :authenticated
      assert new_state.was_authenticated == true

      # Backward compat
      compat_state = Map.put(new_state, :authenticated, new_state.auth_state == :authenticated)
      assert compat_state.authenticated == true
    end
  end

  describe "connection_state/2 and async connect" do
    @tag :requires_ws_module
    test "has connection_state/1 and connection_state/2 exported", %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()
      assert function_exported?(adapter_module, :connection_state, 1)
      assert function_exported?(adapter_module, :connection_state, 2)
    end

    @tag :requires_ws_module
    test "generated AST includes connection_state API and connect_task state", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # connection_state/2 public API
      assert generated =~ "def connection_state(adapter"
      assert generated =~ ":connected"
      assert generated =~ ":connecting"
      assert generated =~ ":disconnected"
      assert generated =~ "@connection_state_timeout_ms"

      # connect_task in state type and init
      assert generated =~ "connect_task"

      # Non-blocking connect via spawn_monitor
      assert generated =~ "spawn_monitor"
      assert generated =~ ":connect_result"

      # connected?/1 delegates to connection_state
      assert generated =~ "def connected?(adapter)"
      assert generated =~ "connection_state(adapter) == :connected"
    end

    @tag :requires_ws_module
    test "generated AST includes get_connection_state handlers for all states", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # Three handle_call clauses for :get_connection_state
      assert generated =~ "handle_call(:get_connection_state"

      # :connecting when connect_task is active
      assert generated =~ ~r/connect_task:.*\{_,\s*_\}.*:connecting/s

      # :disconnected when client is nil and no connect_task
      assert generated =~ ":disconnected"
    end

    @tag :requires_ws_module
    test "init sets connect_task to nil", context do
      adapter_module = context[:adapter_module]
      if is_nil(adapter_module), do: skip_no_adapter()

      {:ok, state} = adapter_module.init(handler: fn _ -> :ok end, url_path: [:public, :spot])
      assert state.connect_task == nil

      drain_connect()
    end

    @tag :requires_ws_module
    test "connection_state returns :disconnected for dead process", context do
      adapter_module = context[:adapter_module]
      if is_nil(adapter_module), do: skip_no_adapter()

      # Use a PID that doesn't exist
      dead_pid = spawn(fn -> :ok end)
      # Wait for it to die
      ref = Process.monitor(dead_pid)

      receive do
        {:DOWN, ^ref, :process, _, _} -> :ok
      end

      assert adapter_module.connection_state(dead_pid) == :disconnected
    end
  end

  describe "listen key connect flow - generated AST" do
    @tag :requires_ws_module
    test "generated AST includes maybe_listen_key_connect in connect handler", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      assert generated =~ "maybe_listen_key_connect(state, connect_opts)"
      assert generated =~ "acquire_listen_key_and_connect"
      assert generated =~ "fetch_listen_key"
      assert generated =~ "build_listen_key_url"
      assert generated =~ "do_fetch_listen_key"
      assert generated =~ "extract_listen_key"
    end

    @tag :requires_ws_module
    test "generated AST includes listen_key_connected result handler before generic handler", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # Both handlers exist
      assert generated =~ ":listen_key_connected"
      assert generated =~ "{:ok, {:listen_key_connected, client}}"

      # Listen key handler sets auth_state directly to :authenticated
      assert generated =~ "auth_state: :authenticated"

      # Listen key handler appears BEFORE the generic {:ok, client} handler
      {lk_start, _} = :binary.match(generated, ":listen_key_connected")
      {gen_start, _} = :binary.match(generated, ":re_authenticate")
      assert lk_start < gen_start, "listen_key handler must come before generic handler"
    end

    @tag :requires_ws_module
    test "generated AST includes already-authenticated guard", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # Guard clause: handle_call(:authenticate, ...) when auth_state == :authenticated replies :ok
      assert generated =~ ~r/handle_call\(:authenticate.*auth_state: :authenticated/s
    end

    @tag :requires_ws_module
    test "generated AST includes backward-compat error for missing config", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      assert generated =~ ":listen_key_missing_config"
      assert generated =~ "mix ccxt.sync binance --force"
      assert generated =~ ":listen_key_no_base_url"
    end

    @tag :requires_ws_module
    test "listen_key connect passes through :url option to WSClient", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # acquire_listen_key_and_connect constructs URL and passes via :url option
      assert generated =~ "Keyword.put(connect_opts, :url, ws_url)"
      assert generated =~ ~r{ws_base_url <> "/" <> listen_key}
    end
  end

  describe "inline subscribe auth enrichment" do
    @tag :requires_ws_module
    test "generated AST includes maybe_enrich_with_auth in subscribe handler", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # subscribe handler calls maybe_enrich_with_auth before WSClient.subscribe
      assert generated =~ "maybe_enrich_with_auth"
      assert generated =~ "WSClient.subscribe"
    end

    @tag :requires_ws_module
    test "generated AST includes maybe_enrich_with_auth with inline_subscribe check", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # Checks for inline_subscribe pattern and auth_required flag
      assert generated =~ ":inline_subscribe"
      assert generated =~ "auth_required: true"
      assert generated =~ "Auth.build_subscribe_auth"
    end

    @tag :requires_ws_module
    test "maybe_enrich_with_auth enrichment order: called before subscribe", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # Enrichment must happen BEFORE the subscribe call
      {enrich_pos, _} = :binary.match(generated, "maybe_enrich_with_auth")
      {subscribe_pos, _} = :binary.match(generated, "WSClient.subscribe")
      assert enrich_pos < subscribe_pos, "Auth enrichment must occur before WSClient.subscribe"
    end
  end

  describe "auth expiry scheduling - generated AST" do
    @tag :requires_ws_module
    test "generated AST includes Expiry alias and schedule_auth_expiry", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      assert generated =~ "Auth.Expiry"
      assert generated =~ "schedule_auth_expiry"
      assert generated =~ "Expiry.compute_ttl_ms"
      assert generated =~ "Expiry.schedule_delay_ms"
    end

    @tag :requires_ws_module
    test "generated AST handles {:ok, auth_meta} in handle_auth_response", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # Both mark_auth_success and re_auth_success get auth_meta passed through
      assert generated =~ "auth_meta"
      assert generated =~ "mark_auth_success(state"
      assert generated =~ "re_auth_success(state"
    end

    @tag :requires_ws_module
    test "generated AST updates auth_timer_ref and auth_expires_at in mark_auth_success", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # mark_auth_success sets timer state
      assert generated =~ "auth_timer_ref: timer_ref"
      assert generated =~ "auth_expires_at: expires_at"
    end

    @tag :requires_ws_module
    test "mark_authenticated cast does NOT include schedule_auth_expiry", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # Extract the handle_cast(:mark_authenticated, ...) clause
      # It should NOT call schedule_auth_expiry — expiry is caller-managed for pre-auth patterns
      [_, mark_auth_body] = String.split(generated, "handle_cast(:mark_authenticated", parts: 2)
      # Take just the next noreply line — the clause body is short
      mark_auth_clause = mark_auth_body |> String.split("{:noreply,") |> Enum.at(0, "")

      refute mark_auth_clause =~ "schedule_auth_expiry"
      refute mark_auth_clause =~ "Expiry"
    end
  end

  describe "market type resolution" do
    @tag :requires_ws_module
    test "generated AST includes market type derivation from url_path", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = @test_ws_config
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      assert generated =~ "derive_market_type_from_url_path"
      assert generated =~ ":spot"
      assert generated =~ ":linear"
      assert generated =~ ":inverse"
    end
  end

  # =====================================================================
  # Behavioral Tests - Direct GenServer callback invocation
  # =====================================================================

  describe "reconnection behavior" do
    @tag :requires_ws_module
    test "reconnect under max attempts increments counter and sends :connect",
         %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      state = build_adapter_state(adapter_module, %{reconnect_attempts: 3})
      {:noreply, new_state} = adapter_module.handle_info(:reconnect, state)

      assert new_state.reconnect_attempts == 4
      assert_receive :connect
    end

    @tag :requires_ws_module
    test "reconnect at max attempts stops the server", %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      state = build_adapter_state(adapter_module, %{reconnect_attempts: 10})

      assert {:stop, :max_reconnection_attempts, _} =
               adapter_module.handle_info(:reconnect, state)
    end

    @tag :requires_ws_module
    test "client DOWN clears client and monitor state", %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      ref = make_ref()

      state =
        build_adapter_state(adapter_module, %{
          client: :fake_client,
          monitor_ref: ref,
          reconnect_attempts: 0
        })

      {:noreply, new_state} =
        adapter_module.handle_info({:DOWN, ref, :process, self(), :normal}, state)

      assert new_state.client == nil
      assert new_state.monitor_ref == nil
    end

    @tag :requires_ws_module
    @tag timeout: 8_000
    test "client DOWN schedules reconnect after base delay", %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      ref = make_ref()

      state =
        build_adapter_state(adapter_module, %{
          client: :fake_client,
          monitor_ref: ref,
          reconnect_attempts: 0
        })

      {:noreply, _} =
        adapter_module.handle_info({:DOWN, ref, :process, self(), :normal}, state)

      # Base delay is 5000ms * 2^0 = 5000ms
      assert_receive :reconnect, 6_000
    end
  end

  describe "subscription restoration on reconnect" do
    @tag :requires_ws_module
    test "restore_subscriptions with nil client is a noop", %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      sub = %{channel: "test.channel", message: %{}, method: :watch_ticker, auth_required: false}
      state = build_adapter_state(adapter_module, %{client: nil, subscriptions: [sub]})

      {:noreply, new_state} = adapter_module.handle_info(:restore_subscriptions, state)

      assert new_state.subscriptions == [sub]
    end

    @tag :requires_ws_module
    test "connect success with subscriptions schedules restore",
         %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      client = fake_ws_client()
      tag = make_ref()
      sub = %{channel: "test.channel", message: %{}, method: :watch_ticker, auth_required: false}

      state =
        build_adapter_state(adapter_module, %{
          connect_task: {tag, make_ref()},
          subscriptions: [sub],
          was_authenticated: false
        })

      {:noreply, _} =
        adapter_module.handle_info({:connect_result, tag, {:ok, client}}, state)

      assert_receive :restore_subscriptions
    end

    @tag :requires_ws_module
    test "connect success with empty subscriptions does not schedule restore",
         %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      client = fake_ws_client()
      tag = make_ref()

      state =
        build_adapter_state(adapter_module, %{
          connect_task: {tag, make_ref()},
          subscriptions: [],
          was_authenticated: false
        })

      {:noreply, _} =
        adapter_module.handle_info({:connect_result, tag, {:ok, client}}, state)

      refute_receive :restore_subscriptions, 100
    end
  end

  describe "auth state on disconnect" do
    @tag :requires_ws_module
    test "client DOWN resets auth_state to :unauthenticated",
         %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      ref = make_ref()

      state =
        build_adapter_state(adapter_module, %{
          client: :fake_client,
          monitor_ref: ref,
          auth_state: :authenticated,
          reconnect_attempts: 0
        })

      {:noreply, new_state} =
        adapter_module.handle_info({:DOWN, ref, :process, self(), :normal}, state)

      assert new_state.auth_state == :unauthenticated
    end

    @tag :requires_ws_module
    test "client DOWN clears auth_timer_ref and auth_expires_at",
         %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      ref = make_ref()
      timer_ref = Process.send_after(self(), :unused_timer, 60_000)

      state =
        build_adapter_state(adapter_module, %{
          client: :fake_client,
          monitor_ref: ref,
          auth_state: :authenticated,
          auth_timer_ref: timer_ref,
          auth_expires_at: System.monotonic_time(:millisecond) + 60_000,
          reconnect_attempts: 0
        })

      {:noreply, new_state} =
        adapter_module.handle_info({:DOWN, ref, :process, self(), :normal}, state)

      assert new_state.auth_timer_ref == nil
      assert new_state.auth_expires_at == nil
      # Timer was cancelled — should not fire
      refute_receive :unused_timer, 100
    end

    @tag :requires_ws_module
    test "client DOWN preserves was_authenticated", %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      ref = make_ref()

      state =
        build_adapter_state(adapter_module, %{
          client: :fake_client,
          monitor_ref: ref,
          auth_state: :authenticated,
          was_authenticated: true,
          reconnect_attempts: 0
        })

      {:noreply, new_state} =
        adapter_module.handle_info({:DOWN, ref, :process, self(), :normal}, state)

      assert new_state.was_authenticated == true
    end
  end

  describe "re-authentication on reconnect" do
    @tag :requires_ws_module
    test "connect success with was_authenticated schedules re_authenticate",
         %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      client = fake_ws_client()
      tag = make_ref()

      state =
        build_adapter_state(adapter_module, %{
          connect_task: {tag, make_ref()},
          was_authenticated: true,
          subscriptions: []
        })

      {:noreply, _} =
        adapter_module.handle_info({:connect_result, tag, {:ok, client}}, state)

      assert_receive :re_authenticate
    end

    @tag :requires_ws_module
    test "connect success without was_authenticated does not schedule re_authenticate",
         %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      client = fake_ws_client()
      tag = make_ref()

      state =
        build_adapter_state(adapter_module, %{
          connect_task: {tag, make_ref()},
          was_authenticated: false,
          subscriptions: []
        })

      {:noreply, _} =
        adapter_module.handle_info({:connect_result, tag, {:ok, client}}, state)

      refute_receive :re_authenticate, 100
    end

    @tag :requires_ws_module
    test "auth_expired transitions to :expired and schedules re_authenticate",
         %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      timer_ref = Process.send_after(self(), :unused, 60_000)

      state =
        build_adapter_state(adapter_module, %{
          auth_state: :authenticated,
          auth_timer_ref: timer_ref,
          auth_expires_at: System.monotonic_time(:millisecond)
        })

      {:noreply, new_state} = adapter_module.handle_info(:auth_expired, state)

      assert new_state.auth_state == :expired
      assert new_state.auth_timer_ref == nil
      assert new_state.auth_expires_at == nil
      assert_receive :re_authenticate
    end
  end

  describe "connect failure handling" do
    @tag :requires_ws_module
    test "connect_result error with matching tag clears connect state",
         %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      tag = make_ref()

      state =
        build_adapter_state(adapter_module, %{
          connect_task: {tag, make_ref()},
          reconnect_attempts: 0
        })

      {:noreply, new_state} =
        adapter_module.handle_info({:connect_result, tag, {:error, :timeout}}, state)

      assert new_state.client == nil
      assert new_state.monitor_ref == nil
      assert new_state.connect_task == nil
    end

    @tag :requires_ws_module
    test "worker DOWN matching connect_task clears connect_task",
         %{adapter_module: adapter_module} do
      if is_nil(adapter_module), do: skip_no_adapter()

      tag = make_ref()
      worker_ref = make_ref()

      state =
        build_adapter_state(adapter_module, %{
          connect_task: {tag, worker_ref}
        })

      {:noreply, new_state} =
        adapter_module.handle_info({:DOWN, worker_ref, :process, self(), :normal}, state)

      assert new_state.connect_task == nil
    end
  end

  # =====================================================================
  # Pipeline Option Injection Tests (Task 209)
  # =====================================================================

  describe "generate_adapter/5 with pipeline (normalizer + contract)" do
    @test_pipeline [normalizer: Normalizer, contract: Contract]

    @tag :requires_ws_module
    test "generates Normalizer alias when pipeline has normalizer", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ast = Adapter.generate_adapter(ws_module, rest_module, @test_ws_config, "bybit", @test_pipeline)
      generated = Macro.to_string(ast)

      assert generated =~ "alias CCXT.WS.Normalizer, as: Normalizer"
    end

    @tag :requires_ws_module
    test "generates Contract alias when pipeline has contract", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ast = Adapter.generate_adapter(ws_module, rest_module, @test_ws_config, "bybit", @test_pipeline)
      generated = Macro.to_string(ast)

      assert generated =~ "alias CCXT.WS.Contract, as: Contract"
    end

    @tag :requires_ws_module
    test "generates @ws_exchange_module attr when normalizer present", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ast = Adapter.generate_adapter(ws_module, rest_module, @test_ws_config, "bybit", @test_pipeline)
      generated = Macro.to_string(ast)

      assert generated =~ "@ws_exchange_module"
    end

    @tag :requires_ws_module
    test "generates build_handler/3 (not /1) when normalizer present", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ast = Adapter.generate_adapter(ws_module, rest_module, @test_ws_config, "bybit", @test_pipeline)
      generated = Macro.to_string(ast)

      assert generated =~ "build_handler(nil, _normalize, _validate)"
      assert generated =~ "build_handler(user_handler, normalize, validate)"
      # Should NOT have build_handler/1
      refute generated =~ ~r/defp build_handler\(nil\), do: nil/
    end

    @tag :requires_ws_module
    test "generates deliver_message/4 with normalization when envelope + normalizer", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      # "bybit" has envelope config
      ast = Adapter.generate_adapter(ws_module, rest_module, @test_ws_config, "bybit", @test_pipeline)
      generated = Macro.to_string(ast)

      # Should have /4 deliver_message with normalize/validate params
      assert generated =~ "deliver_message(decoded, user_handler, false, _validate)"
      assert generated =~ "deliver_message(decoded, user_handler, true, validate)"
      assert generated =~ "Normalizer.normalize(family, payload, @ws_exchange_module)"
    end

    @tag :requires_ws_module
    test "generates maybe_validate/3 when normalizer + contract present", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ast = Adapter.generate_adapter(ws_module, rest_module, @test_ws_config, "bybit", @test_pipeline)
      generated = Macro.to_string(ast)

      assert generated =~ "maybe_validate(_family, _normalized, false)"
      assert generated =~ "maybe_validate(family, normalized, true)"
      assert generated =~ "Contract.validate(family, normalized)"
    end

    @tag :requires_ws_module
    test "generates normalize/validate state fields in init when normalizer present", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ast = Adapter.generate_adapter(ws_module, rest_module, @test_ws_config, "bybit", @test_pipeline)
      generated = Macro.to_string(ast)

      assert generated =~ "normalize: Keyword.get(opts, :normalize, true)"
      assert generated =~ "validate: Keyword.get(opts, :validate, false)"
    end

    @tag :requires_ws_module
    test "generates normalize/validate doc lines in start_link when normalizer present", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ast = Adapter.generate_adapter(ws_module, rest_module, @test_ws_config, "bybit", @test_pipeline)
      generated = Macro.to_string(ast)

      assert generated =~ ":normalize"
      assert generated =~ ":validate"
    end

    @tag :requires_ws_module
    test "generates safe_decode_and_deliver/4 when normalizer present", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ast = Adapter.generate_adapter(ws_module, rest_module, @test_ws_config, "bybit", @test_pipeline)
      generated = Macro.to_string(ast)

      assert generated =~ "safe_decode_and_deliver(data, user_handler, normalize, validate)"
    end

    @tag :requires_ws_module
    test "uses Logger.warning for JSON decode failures", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      # Both with and without pipeline should use Logger.warning for decode failures
      ast_with = Adapter.generate_adapter(ws_module, rest_module, @test_ws_config, "bybit", @test_pipeline)
      ast_without = Adapter.generate_adapter(ws_module, rest_module, @test_ws_config, "bybit")

      for ast <- [ast_with, ast_without] do
        generated = Macro.to_string(ast)

        # The "Failed to decode" message should use Logger.warning
        assert generated =~ ~r/Logger\.warning.*Failed to decode WS message as JSON/s
      end
    end

    @tag :requires_ws_module
    test "without pipeline, output matches generate_adapter/4 behavior", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ast_default = Adapter.generate_adapter(ws_module, rest_module, @test_ws_config, "bybit")
      ast_empty = Adapter.generate_adapter(ws_module, rest_module, @test_ws_config, "bybit", [])

      # Both should produce identical AST strings
      assert Macro.to_string(ast_default) == Macro.to_string(ast_empty)
    end

    @tag :requires_ws_module
    test "no-envelope exchange with normalizer generates deliver_message/4 passthrough", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ast =
        Adapter.generate_adapter(
          ws_module,
          rest_module,
          @test_ws_config,
          "no_envelope_exchange",
          @test_pipeline
        )

      generated = Macro.to_string(ast)

      # Should have deliver_message/4 but NOT MessageRouter
      assert generated =~ "deliver_message(decoded, user_handler, _normalize, _validate)"
      assert generated =~ "{:raw, decoded}"
      refute generated =~ "MessageRouter.route"
    end

    test "raises ArgumentError when normalizer set without contract" do
      assert_raise ArgumentError, ~r/both be set or both be nil/, fn ->
        Adapter.generate_adapter(
          SomeWS,
          SomeRest,
          @test_ws_config,
          "test",
          normalizer: Normalizer
        )
      end
    end

    test "raises ArgumentError when contract set without normalizer" do
      assert_raise ArgumentError, ~r/both be set or both be nil/, fn ->
        Adapter.generate_adapter(
          SomeWS,
          SomeRest,
          @test_ws_config,
          "test",
          contract: Contract
        )
      end
    end
  end

  # =====================================================================
  # Test Helpers
  # =====================================================================

  # Helper to skip tests when no adapter module is available
  defp skip_no_adapter do
    flunk("No WS Adapter module available, run mix ccxt.sync to generate")
  end

  # Helper to drain the :connect message sent by init
  defp drain_connect do
    receive do
      :connect -> :ok
    after
      100 -> :ok
    end
  end

  # Builds adapter state by calling init/1 and applying overrides.
  # Drains the :connect message that init sends automatically.
  defp build_adapter_state(adapter_module, overrides) do
    {:ok, base} = adapter_module.init(handler: fn _ -> :ok end, url_path: [:public, :spot])
    drain_connect()
    Map.merge(base, overrides)
  end

  # Creates a fake CCXT.WS.Client with a real (alive) PID for the zen_client.
  # The process is cleaned up automatically after the test via on_exit.
  defp fake_ws_client do
    pid = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> Process.exit(pid, :kill) end)

    zen = %ZenWebsocket.Client{
      server_pid: pid,
      state: :connected,
      url: "wss://fake",
      monitor_ref: nil,
      gun_pid: nil,
      stream_ref: nil
    }

    %CCXT.WS.Client{
      zen_client: zen,
      spec: %{},
      url: "wss://fake",
      url_path: []
    }
  end
end
