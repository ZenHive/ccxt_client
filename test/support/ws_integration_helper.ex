defmodule CCXT.Test.WSIntegrationHelper do
  @moduledoc """
  Helper functions for WebSocket integration tests.

  Provides utilities for:
  - Connecting to WS adapters and waiting for connection
  - Subscribing to channels and receiving messages
  - Authenticating and verifying auth state
  - Building test handlers that route to the test process
  - Asserting message structure

  ## Usage

      defmodule MyWSIntegrationTest do
        use ExUnit.Case, async: false
        import CCXT.Test.WSIntegrationHelper

        test "public ticker subscription" do
          adapter = start_adapter_and_wait!(@adapter_module, [
            url_path: [:public, :spot],
            sandbox: true
          ])

          {:ok, sub} = @ws_module.watch_ticker_subscription("BTC/USDT")
          message = subscribe_and_receive!(adapter, sub)

          assert is_map(message)
          close_adapter(adapter)
        end
      end
  """

  import ExUnit.Assertions

  alias CCXT.WS.Helpers

  require Logger

  # Default timeouts for WS operations
  @connect_timeout_ms 15_000
  @message_timeout_ms 30_000
  @auth_timeout_ms 15_000
  @state_poll_interval_ms 100

  @doc """
  Starts an adapter and waits for connected state.

  ## Parameters

  - `adapter_module` - The adapter module (e.g., `CCXT.Bybit.WS.Adapter`)
  - `opts` - Options passed to adapter's `start_link/1`:
    - `:url_path` - Path to WS URL (e.g., `[:public, :spot]`)
    - `:sandbox` - Use testnet URLs (default: false)
    - `:credentials` - API credentials (for private channels)
    - `:handler` - Custom message handler (defaults to test process handler)

  ## Returns

  The adapter pid on success, or raises on timeout/failure.

  ## Examples

      adapter = start_adapter_and_wait!(CCXT.Bybit.WS.Adapter, [
        url_path: [:public, :spot],
        sandbox: true
      ])

  """
  @spec start_adapter_and_wait!(module(), keyword(), non_neg_integer()) :: pid()
  def start_adapter_and_wait!(adapter_module, opts, timeout \\ @connect_timeout_ms) do
    # Build handler that sends to test process
    test_pid = self()
    handler = Keyword.get(opts, :handler, build_test_handler(test_pid))
    opts = Keyword.put(opts, :handler, handler)

    {:ok, adapter} = adapter_module.start_link(opts)

    # Wait for connected state
    wait_for_connected!(adapter_module, adapter, timeout)

    adapter
  end

  @doc """
  Waits for the adapter to reach connected state.

  Uses `connection_state/1` when available (never-raising), falls back to
  `connected?/1` with catch for older adapters. Reports diagnostic info on timeout.
  """
  @spec wait_for_connected!(module(), pid(), non_neg_integer()) :: :ok
  def wait_for_connected!(adapter_module, adapter, timeout \\ @connect_timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_loop(adapter_module, adapter, deadline, timeout)
  end

  @doc false
  defp wait_loop(adapter_module, adapter, deadline, timeout) do
    state = poll_connection_state(adapter_module, adapter)

    if state == :connected do
      :ok
    else
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining <= 0 do
        flunk("""
        Adapter failed to connect within #{timeout}ms.
        Last state: #{inspect(state)}
        Adapter alive: #{Process.alive?(adapter)}
        Module: #{inspect(adapter_module)}
        """)
      else
        Process.sleep(@state_poll_interval_ms)
        wait_loop(adapter_module, adapter, deadline, timeout)
      end
    end
  end

  @doc false
  # Polls connection state using connection_state/1 (preferred) or connected?/1 (fallback)
  defp poll_connection_state(adapter_module, adapter) do
    if function_exported?(adapter_module, :connection_state, 1) do
      adapter_module.connection_state(adapter)
    else
      poll_connected_legacy(adapter_module, adapter)
    end
  end

  @doc false
  # Fallback for adapters without connection_state/1 — wraps connected?/1
  # with implicit try/catch (bare catch on defp body)
  defp poll_connected_legacy(adapter_module, adapter) do
    if adapter_module.connected?(adapter), do: :connected, else: :disconnected
  catch
    :exit, {:timeout, _} -> :connecting
    :exit, {:noproc, _} -> :disconnected
  end

  @doc """
  Subscribes to a channel and waits for the first message.

  ## Parameters

  - `adapter_module` - The adapter module
  - `adapter` - The adapter pid
  - `subscription` - Subscription map from WS module
  - `timeout` - Timeout in ms (default: 30s)

  ## Returns

  The first received message, or flunks on timeout.

  ## Examples

      {:ok, sub} = CCXT.Bybit.WS.watch_ticker_subscription("BTC/USDT")
      message = subscribe_and_receive!(CCXT.Bybit.WS.Adapter, adapter, sub)
      assert is_map(message)

  """
  @spec subscribe_and_receive!(module(), pid(), map(), non_neg_integer()) :: map() | list()
  def subscribe_and_receive!(adapter_module, adapter, subscription, timeout \\ @message_timeout_ms) do
    case adapter_module.subscribe(adapter, subscription) do
      :ok -> :ok
      {:ok, _response} -> :ok
      {:error, reason} -> flunk("Subscribe failed: #{inspect(reason)}")
    end

    receive_data_message(timeout)
  end

  @doc false
  # Public for testability. Receives messages, skipping :system-tagged and
  # shape-matched system messages, returning the first data payload.
  # Uses a deadline so skipped system messages don't extend the total wait.
  def receive_data_message(timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_receive_data_message(deadline, timeout)
  end

  @doc false
  defp do_receive_data_message(deadline, original_timeout) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      flunk("No data message received within #{original_timeout}ms (only system messages)")
    end

    case receive_tagged_message(remaining) do
      {:system, _data} ->
        do_receive_data_message(deadline, original_timeout)

      {_family, data} ->
        cond do
          error_message?(data) ->
            ExUnit.Assertions.flunk("Received error from exchange: #{inspect(data)}")

          system_message?(data) ->
            do_receive_data_message(deadline, original_timeout)

          true ->
            data
        end
    end
  end

  @doc false
  # Preserves family tags so receive_data_message/1 can distinguish
  # :system messages (subscription acks) from data payloads.
  # Untagged messages get {:untagged, data} for backward compatibility.
  defp receive_tagged_message(timeout) do
    receive do
      {:ws_message, {:system, _} = tagged} ->
        tagged

      {:ws_message, {family, data} = _tagged} when is_map(data) or is_list(data) ->
        {family, data}

      {:ws_message, {family, data}} when is_binary(data) ->
        case Jason.decode(data) do
          {:ok, decoded} -> {family, decoded}
          {:error, _} -> {family, data}
        end

      {:ws_message, data} when is_map(data) ->
        {:untagged, data}

      {:ws_message, data} when is_list(data) ->
        {:untagged, data}

      {:ws_message, data} when is_binary(data) ->
        case Jason.decode(data) do
          {:ok, decoded} -> {:untagged, decoded}
          {:error, _} -> {:untagged, data}
        end
    after
      timeout ->
        flunk("No message received within #{timeout}ms")
    end
  end

  @doc false
  # Detects error payloads that should fail the test immediately (not be swallowed).
  defp error_message?(%{"type" => "error"}), do: true
  defp error_message?(%{"event" => "error"}), do: true
  defp error_message?(%{"error" => err}) when is_binary(err) or is_map(err), do: true
  defp error_message?(_), do: false

  @doc false
  # Filters out system messages (confirmations, heartbeats, pongs) so
  # receive_data_message/1 only returns actual data payloads.

  # JSON-RPC confirmation: has "jsonrpc" and "result" but no "method" (not a notification)
  defp system_message?(%{"jsonrpc" => "2.0", "result" => _} = msg) when not is_map_key(msg, "method"), do: true

  # Topic-based confirmation (Bybit): {"op": "subscribe", "success": true}
  defp system_message?(%{"op" => "subscribe", "success" => true}), do: true

  # Channel confirmation (Coinbase): {"type": "subscriptions", "channels": [...]}
  defp system_message?(%{"type" => "subscriptions", "channels" => c}) when is_list(c), do: true

  # Heartbeat messages (various exchange formats)
  defp system_message?(%{"type" => "heartbeat"}), do: true
  defp system_message?(%{"event" => "heartbeat"}), do: true

  # Pong responses
  defp system_message?(%{"op" => "pong"}), do: true
  defp system_message?(%{"ret_msg" => "pong"}), do: true

  defp system_message?(_), do: false

  @doc """
  Receives a message from the test handler.

  The test handler sends messages as `{:ws_message, data}`.
  """
  @spec receive_message(non_neg_integer()) :: map() | list()
  def receive_message(timeout \\ @message_timeout_ms) do
    receive do
      # Tagged tuple from W14/W14b normalization layer: {family, payload}
      {:ws_message, {_family, data}} when is_map(data) ->
        data

      {:ws_message, {_family, data}} when is_list(data) ->
        data

      # Raw map (pre-normalization or direct handler)
      {:ws_message, data} when is_map(data) ->
        data

      # Raw list (e.g., trades)
      {:ws_message, data} when is_list(data) ->
        data

      # Binary JSON
      {:ws_message, data} when is_binary(data) ->
        case Jason.decode(data) do
          {:ok, decoded} -> decoded
          {:error, _} -> data
        end
    after
      timeout ->
        flunk("No message received within #{timeout}ms")
    end
  end

  @doc """
  Authenticates the adapter and verifies success.

  ## Parameters

  - `adapter_module` - The adapter module
  - `adapter` - The adapter pid
  - `timeout` - Timeout in ms (default: 15s)

  ## Returns

  `:ok` on success, or flunks on failure/timeout.

  """
  @spec authenticate_and_wait!(module(), pid(), non_neg_integer()) :: :ok
  def authenticate_and_wait!(adapter_module, adapter, timeout \\ @auth_timeout_ms) do
    task =
      Task.async(fn ->
        adapter_module.authenticate(adapter)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, :ok} ->
        :ok

      {:ok, {:error, reason}} ->
        flunk("Authentication failed: #{inspect(reason)}")

      nil ->
        flunk("Authentication timed out after #{timeout}ms")
    end
  end

  @doc """
  Builds a handler function that sends messages to the test process.

  Messages are sent as `{:ws_message, data}`.
  """
  @spec build_test_handler(pid()) :: (term() -> :ok)
  def build_test_handler(test_pid) do
    fn msg ->
      send(test_pid, {:ws_message, msg})
      :ok
    end
  end

  @doc """
  Asserts that a message has the expected keys.

  ## Parameters

  - `message` - The message map to check
  - `expected_keys` - List of keys that should be present

  ## Examples

      assert_message_structure(message, [:symbol, :last, :bid, :ask])

  """
  @spec assert_message_structure(map(), [atom() | String.t()]) :: :ok
  def assert_message_structure(message, expected_keys) do
    for key <- expected_keys do
      string_key = to_string(key)
      atom_key = if is_atom(key), do: key, else: String.to_atom(key)

      assert Map.has_key?(message, key) or Map.has_key?(message, string_key) or Map.has_key?(message, atom_key),
             "Expected message to have key #{inspect(key)}, got: #{inspect(Map.keys(message))}"
    end

    :ok
  end

  @doc """
  Returns a test symbol for an exchange.

  Uses BTC/USDT as the default since it's widely supported.
  """
  @spec test_symbol(String.t()) :: String.t()
  def test_symbol("deribit") do
    "BTC-PERPETUAL"
  end

  def test_symbol("coinbaseexchange") do
    "BTC/USD"
  end

  def test_symbol(_exchange_id) do
    "BTC/USDT"
  end

  @doc """
  Closes the adapter gracefully.
  """
  @spec close_adapter(pid()) :: :ok
  def close_adapter(adapter) when is_pid(adapter) do
    if Process.alive?(adapter) do
      GenServer.stop(adapter, :normal, 5_000)
    end

    :ok
  rescue
    # Ignore errors during cleanup
    _ -> :ok
  end

  @doc """
  Returns the testnet URL for an exchange based on spec.

  ## Parameters

  - `rest_module` - The REST module (e.g., `CCXT.Bybit`)
  - `url_path` - Path to resolve (e.g., `[:public, :spot]`)

  """
  @spec sandbox_url(module(), term()) :: {:ok, String.t()} | {:error, term()}
  def sandbox_url(rest_module, url_path) do
    spec = rest_module.__ccxt_spec__()
    Helpers.resolve_url(spec, url_path, sandbox: true)
  end

  @doc """
  Checks if an exchange has WS support in sandbox mode.
  """
  @spec has_ws_sandbox?(module()) :: boolean()
  def has_ws_sandbox?(rest_module) do
    spec = rest_module.__ccxt_spec__()
    ws_config = Map.get(spec, :ws)

    if ws_config && ws_config != %{} do
      test_urls = Map.get(ws_config, :test_urls)
      test_urls != nil && test_urls != %{}
    else
      false
    end
  end

  @doc """
  Checks if an exchange has private WS channels.
  """
  @spec has_private_channels?(module()) :: boolean()
  def has_private_channels?(rest_module) do
    spec = rest_module.__ccxt_spec__()
    ws_config = Map.get(spec, :ws) || %{}
    auth_config = Map.get(ws_config, :auth)

    auth_config != nil && auth_config != %{}
  end

  @doc false
  # Logs a warning when private channels exist but credentials are missing.
  # Called from generated setup_all; separate function to avoid nesting depth.
  @spec warn_if_missing_credentials(String.t(), boolean(), term()) :: :ok
  def warn_if_missing_credentials(exchange_id, true = _has_private, nil = _credentials) do
    Logger.warning("No testnet credentials for #{exchange_id} - private channel tests will be skipped")
  end

  def warn_if_missing_credentials(_exchange_id, _has_private, _credentials), do: :ok

  @doc """
  Missing credentials message for WS integration tests.
  """
  @spec missing_ws_credentials_message(String.t(), keyword()) :: String.t()
  def missing_ws_credentials_message(exchange_id, opts \\ []) do
    passphrase = Keyword.get(opts, :passphrase, false)
    sandbox_key = Keyword.get(opts, :sandbox_key, :default)

    # Use Testnet.env_var_prefix for correct env var names (e.g., BINANCE_FUTURES_TESTNET)
    exchange_atom = String.to_existing_atom(exchange_id)
    prefix = CCXT.Testnet.env_var_prefix(exchange_atom, sandbox_key)

    env_vars =
      if passphrase do
        exchange_prefix = String.upcase(exchange_id)

        """
          export #{prefix}_API_KEY="your_key"
          export #{prefix}_API_SECRET="your_secret"
          export #{exchange_prefix}_PASSPHRASE="your_passphrase"
        """
      else
        """
          export #{prefix}_API_KEY="your_key"
          export #{prefix}_API_SECRET="your_secret"
        """
      end

    """
    Missing testnet credentials for #{exchange_id} WS integration tests!

    Set these environment variables:
    #{String.trim(env_vars)}
    """
  end
end
