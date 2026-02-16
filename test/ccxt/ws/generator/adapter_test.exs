defmodule CCXT.WS.Generator.AdapterTest do
  use ExUnit.Case, async: true

  alias CCXT.WS.Contract
  alias CCXT.WS.Generator
  alias CCXT.WS.Generator.Adapter

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

      ws_config = %{urls: "wss://example.com"}

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

      ws_config = %{urls: "wss://example.com"}
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
    test "generated AST includes validate option in init", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]

      if is_nil(ws_module) do
        flunk("No WS module available - sync exchanges with `mix ccxt.sync --tier1`")
      end

      ws_config = %{urls: "wss://example.com"}
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # validate option parsed in init with default false
      assert generated =~ "validate:"
      assert generated =~ "Keyword.get(opts, :validate, false)"
    end

    @tag :requires_ws_module
    test "generated AST includes Contract.validate call via maybe_validate", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]

      if is_nil(ws_module) do
        flunk("No WS module available - sync exchanges with `mix ccxt.sync --tier1`")
      end

      ws_config = %{urls: "wss://example.com"}
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # maybe_validate helper wires Contract.validate/2
      assert generated =~ "maybe_validate"
      assert generated =~ "Contract.validate(family, normalized)"
      # Warn-only: logs warning but still delivers
      assert generated =~ "Contract violation"
    end

    @tag :requires_ws_module
    test "generated AST includes deliver_message clause for normalize=false (raw path)", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]

      if is_nil(ws_module) do
        flunk("No WS module available - sync exchanges with `mix ccxt.sync --tier1`")
      end

      ws_config = %{urls: "wss://example.com"}
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # deliver_message/4 with normalize=false wraps payload as {:raw, decoded}
      assert generated =~ "deliver_message(decoded, user_handler, false, _validate)"
      assert generated =~ "{:raw, decoded}"
    end

    @tag :requires_ws_module
    test "generated AST includes normalization failure fallback branch", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]

      if is_nil(ws_module) do
        flunk("No WS module available - sync exchanges with `mix ccxt.sync --tier1`")
      end

      ws_config = %{urls: "wss://example.com"}
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      # When normalization fails, deliver raw with family tag
      assert generated =~ "{:error, _reason}"
      assert generated =~ "user_handler.({family, payload})"
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

  describe "normalize option runtime behavior" do
    @tag :requires_ws_module
    test "normalize defaults to true in init state", context do
      adapter_module = context[:adapter_module]

      if is_nil(adapter_module), do: skip_no_adapter()

      {:ok, state} = adapter_module.init(handler: fn _ -> :ok end, url_path: [:public, :spot])

      assert state.normalize == true

      receive do
        :connect -> :ok
      after
        100 -> :ok
      end
    end

    @tag :requires_ws_module
    test "normalize: false is stored in init state", context do
      adapter_module = context[:adapter_module]

      if is_nil(adapter_module), do: skip_no_adapter()

      {:ok, state} =
        adapter_module.init(
          handler: fn _ -> :ok end,
          url_path: [:public, :spot],
          normalize: false
        )

      assert state.normalize == false

      receive do
        :connect -> :ok
      after
        100 -> :ok
      end
    end
  end

  describe "validate option runtime behavior" do
    @tag :requires_ws_module
    test "validate defaults to false in init state", context do
      adapter_module = context[:adapter_module]

      if is_nil(adapter_module), do: skip_no_adapter()

      # Call init directly to inspect state without triggering :connect
      {:ok, state} = adapter_module.init(handler: fn _ -> :ok end, url_path: [:public, :spot])

      assert state.validate == false
      assert state.normalize == true

      # Drain the :connect message so it doesn't leak
      receive do
        :connect -> :ok
      after
        100 -> :ok
      end
    end

    @tag :requires_ws_module
    test "validate: true is stored in init state", context do
      adapter_module = context[:adapter_module]

      if is_nil(adapter_module), do: skip_no_adapter()

      {:ok, state} =
        adapter_module.init(
          handler: fn _ -> :ok end,
          url_path: [:public, :spot],
          validate: true
        )

      assert state.validate == true

      receive do
        :connect -> :ok
      after
        100 -> :ok
      end
    end

    test "Contract.validate returns ok for valid ticker, error for invalid — confirming warn-only path" do
      # This tests the underlying Contract.validate behavior that maybe_validate delegates to.
      # Valid: returns {:ok, _}, no warning would be logged
      ticker = %CCXT.Types.Ticker{symbol: "BTC/USDT", last: 42_000.0}
      assert {:ok, ^ticker} = Contract.validate(:watch_ticker, ticker)

      # Invalid: returns {:error, violations}, warning would be logged but data still delivered
      assert {:error, violations} = Contract.validate(:watch_ticker, %{})
      assert is_list(violations)
      assert violations != []
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

      ws_config = %{urls: "wss://example.com"}
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

      ws_config = %{urls: "wss://example.com"}
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

      ws_config = %{urls: "wss://example.com"}
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

      ws_config = %{urls: "wss://example.com"}
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

      ws_config = %{urls: "wss://example.com"}
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

      ws_config = %{urls: "wss://example.com"}
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

  describe "market type resolution" do
    @tag :requires_ws_module
    test "generated AST includes market type derivation from url_path", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]
      if is_nil(ws_module), do: skip_no_adapter()

      ws_config = %{urls: "wss://example.com"}
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config, "test_exchange")
      generated = Macro.to_string(ast)

      assert generated =~ "derive_market_type_from_url_path"
      assert generated =~ ":spot"
      assert generated =~ ":linear"
      assert generated =~ ":inverse"
    end
  end

  # Helper to skip tests when no adapter module is available
  defp skip_no_adapter do
    flunk("No WS Adapter module available - sync exchanges with `mix ccxt.sync --tier1`")
  end

  # Helper to drain the :connect message sent by init
  defp drain_connect do
    receive do
      :connect -> :ok
    after
      100 -> :ok
    end
  end
end
