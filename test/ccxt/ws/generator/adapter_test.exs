defmodule CCXT.WS.Generator.AdapterTest do
  use ExUnit.Case, async: true

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

  describe "generate_adapter/3" do
    @tag :requires_ws_module
    test "generates valid AST", context do
      ws_module = context[:ws_module]
      rest_module = context[:rest_module]

      if is_nil(ws_module) do
        flunk("No WS module available - sync exchanges with `mix ccxt.sync --tier1`")
      end

      ws_config = %{urls: "wss://example.com"}

      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config)

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
      ast = Adapter.generate_adapter(ws_module, rest_module, ws_config)
      generated = Macro.to_string(ast)

      assert generated =~ "@reconnect_delay_ms"
      assert generated =~ "@max_reconnect_attempts"
      assert generated =~ "@max_backoff_ms"
      assert generated =~ "schedule_reconnect"
      assert generated =~ "handle_info(:reconnect, state)"
      assert generated =~ "handle_info(:restore_subscriptions"
      assert generated =~ "handle_info(:re_authenticate"
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

  # Helper to skip tests when no adapter module is available
  defp skip_no_adapter do
    flunk("No WS Adapter module available - sync exchanges with `mix ccxt.sync --tier1`")
  end
end
