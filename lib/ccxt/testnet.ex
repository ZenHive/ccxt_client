defmodule CCXT.Testnet do
  @moduledoc """
  Multi-credential registry for integration testing.

  Supports multiple credential sets per exchange for multi-API exchanges
  (e.g., Binance spot vs futures testnets require separate credentials).

  Credentials are registered once at test startup (in test_helper.exs),
  then retrieved by generated tests via `setup_all`.

  ## Usage

      # In test_helper.exs - register credentials for each sandbox
      CCXT.Testnet.register_from_env(:bybit, testnet: true)
      CCXT.Testnet.register_from_env(:binance, testnet: true)  # spot
      CCXT.Testnet.register_from_env(:binance, :futures, testnet: true)  # futures

      # In tests - retrieve credentials for specific sandbox
      creds = CCXT.Testnet.creds(:bybit)  # default sandbox
      creds = CCXT.Testnet.creds(:binance, :futures)  # futures sandbox

  ## Sandbox Keys

  Multi-API exchanges have different testnets per API section:

  | Sandbox Key | Env Var Infix | Example Hostname |
  |-------------|---------------|------------------|
  | `:default`  | (none)        | testnet.binance.vision |
  | `:futures`  | `_FUTURES`    | testnet.binancefuture.com |
  | `:coinm`    | `_COINM`      | testnet.binancefuture.com/dapi |

  ## Benefits

  - **Fail once, not N times** - `setup_all` means credential check happens once per module
  - **Clear error messages** - Shows exactly which env vars to set
  - **Per-sandbox credentials** - Different API sections can use different credentials
  - **Auto-skip** - Tests skip gracefully when no credentials for their sandbox
  """

  use Agent

  @typedoc "Options for register_from_env/2"
  @type register_opts :: [
          testnet: boolean(),
          passphrase: boolean(),
          sandbox: boolean(),
          secret_suffix: String.t()
        ]

  @doc """
  Starts the credential registry Agent.

  Added to the application supervision tree automatically.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Register credentials directly.

  ## Arguments

  - `exchange` - Exchange atom (e.g., `:binance`)
  - `sandbox_key` - Optional. Sandbox key (`:default`, `:futures`, `:coinm`). Defaults to `:default`.
  - `opts` - Credential options

  ## Options

  - `:api_key` - Required. The API key.
  - `:secret` - Required. The API secret.
  - `:password` - Optional. API password/passphrase.
  - `:sandbox` - Optional. Whether to use sandbox/testnet URLs.

  ## Returns

  - `:ok` - Credentials were registered successfully
  - `:skipped` - Credentials were incomplete (missing api_key or secret)

  ## Examples

      # Default sandbox (spot)
      CCXT.Testnet.register(:bybit, api_key: "key", secret: "secret", sandbox: true)

      # Specific sandbox (futures)
      CCXT.Testnet.register(:binance, :futures, api_key: "key", secret: "secret", sandbox: true)
  """
  @spec register(atom(), atom() | keyword(), keyword()) :: :ok | :skipped
  def register(exchange, sandbox_key_or_opts, opts \\ [])

  def register(exchange, sandbox_key, opts) when is_atom(exchange) and is_atom(sandbox_key) and is_list(opts) do
    case CCXT.Credentials.new(opts) do
      {:ok, credentials} ->
        Agent.update(__MODULE__, &Map.put(&1, {exchange, sandbox_key}, credentials))
        :ok

      {:error, _reason} ->
        :skipped
    end
  end

  def register(exchange, opts, []) when is_atom(exchange) and is_list(opts) do
    # Backward compatible: register(exchange, opts) -> register(exchange, :default, opts)
    register(exchange, :default, opts)
  end

  @doc """
  Register credentials from environment variables.

  Environment variable names follow the pattern:
  - `{EXCHANGE}[_{SANDBOX}]_TESTNET_API_KEY` (if testnet: true)
  - `{EXCHANGE}[_{SANDBOX}]_TESTNET_API_SECRET` (if testnet: true)
  - `{EXCHANGE}_PASSPHRASE` (if passphrase: true)

  Where `{SANDBOX}` is empty for `:default`, `FUTURES` for `:futures`, `COINM` for `:coinm`.

  ## Arguments

  - `exchange` - Exchange atom (e.g., `:binance`)
  - `sandbox_key` - Optional. Sandbox key (`:default`, `:futures`, `:coinm`). Defaults to `:default`.
  - `opts` - Options

  ## Options

  - `:testnet` - If true, env var names include TESTNET suffix (default: false)
  - `:passphrase` - If true, also loads passphrase from env (default: false)
  - `:sandbox` - Value for `credentials.sandbox` (default: value of `:testnet`)
  - `:secret_suffix` - Override the secret env var suffix (default: "API_SECRET")

  ## Examples

      # Bybit default testnet (BYBIT_TESTNET_API_KEY, BYBIT_TESTNET_API_SECRET)
      CCXT.Testnet.register_from_env(:bybit, testnet: true)

      # Binance spot testnet (BINANCE_TESTNET_API_KEY, BINANCE_TESTNET_API_SECRET)
      CCXT.Testnet.register_from_env(:binance, testnet: true)

      # Binance futures testnet (BINANCE_FUTURES_TESTNET_API_KEY, BINANCE_FUTURES_TESTNET_API_SECRET)
      CCXT.Testnet.register_from_env(:binance, :futures, testnet: true)

      # OKX with passphrase (OKX_TESTNET_API_KEY, OKX_TESTNET_API_SECRET, OKX_PASSPHRASE)
      CCXT.Testnet.register_from_env(:okx, testnet: true, passphrase: true)

  ## Returns

  - `:ok` - Credentials were registered successfully
  - `:skipped` - Environment variables were not set (no registration)
  """
  @spec register_from_env(atom(), atom() | register_opts(), register_opts()) :: :ok | :skipped
  def register_from_env(exchange, sandbox_key_or_opts \\ :default, opts \\ [])

  def register_from_env(exchange, sandbox_key, opts) when is_atom(exchange) and is_atom(sandbox_key) and is_list(opts) do
    prefix = exchange |> Atom.to_string() |> String.upcase()
    sandbox_infix = sandbox_key_to_infix(sandbox_key)
    testnet = Keyword.get(opts, :testnet, false)
    testnet_part = if testnet, do: "_TESTNET", else: ""
    secret_suffix = Keyword.get(opts, :secret_suffix, "API_SECRET")
    passphrase_opt = Keyword.get(opts, :passphrase, false)
    sandbox = Keyword.get(opts, :sandbox, testnet)

    # Pattern: {EXCHANGE}_{SANDBOX_INFIX}_TESTNET_API_KEY
    # e.g., BINANCE_FUTURES_TESTNET_API_KEY or BINANCE_TESTNET_API_KEY (default)
    api_key = System.get_env("#{prefix}#{sandbox_infix}#{testnet_part}_API_KEY")
    secret = System.get_env("#{prefix}#{sandbox_infix}#{testnet_part}_#{secret_suffix}")
    password = if passphrase_opt, do: System.get_env("#{prefix}_PASSPHRASE")

    if api_key && secret do
      register(exchange, sandbox_key, api_key: api_key, secret: secret, password: password, sandbox: sandbox)
    else
      :skipped
    end
  end

  def register_from_env(exchange, opts, []) when is_atom(exchange) and is_list(opts) do
    # Backward compatible: register_from_env(exchange, opts) -> register_from_env(exchange, :default, opts)
    register_from_env(exchange, :default, opts)
  end

  # Convert sandbox_key to env var infix
  @doc false
  defp sandbox_key_to_infix(:default), do: ""
  defp sandbox_key_to_infix(:futures), do: "_FUTURES"
  defp sandbox_key_to_infix(:coinm), do: "_COINM"
  defp sandbox_key_to_infix(key) when is_atom(key), do: "_#{key |> Atom.to_string() |> String.upcase()}"

  @doc """
  Register credentials for multiple exchanges from environment variables.

  Convenience function that calls `register_from_env/2` or `register_from_env/3` for each config.
  Returns list of successfully registered `{exchange, sandbox_key}` tuples.

  ## Example

      # In test_helper.exs
      configs = [
        {:bybit, testnet: true},
        {:binance, testnet: true},
        {:binance, :futures, testnet: true},
        {:okx, testnet: true, passphrase: true}
      ]

      registered = CCXT.Testnet.register_all_from_env(configs)
      # => [{:bybit, :default}, {:binance, :default}, {:binance, :futures}]  (okx skipped if env vars not set)
  """
  @spec register_all_from_env([{atom(), register_opts()} | {atom(), atom(), register_opts()}]) :: [{atom(), atom()}]
  def register_all_from_env(configs) when is_list(configs) do
    for config <- configs,
        result = register_config(config),
        result != :skipped do
      result
    end
  end

  defp register_config({exchange, sandbox_key, opts}) when is_atom(sandbox_key) do
    case register_from_env(exchange, sandbox_key, opts) do
      :ok -> {exchange, sandbox_key}
      :skipped -> :skipped
    end
  end

  defp register_config({exchange, opts}) when is_list(opts) do
    case register_from_env(exchange, :default, opts) do
      :ok -> {exchange, :default}
      :skipped -> :skipped
    end
  end

  @doc """
  Get credentials for an exchange and sandbox.

  Returns `nil` if no credentials are registered for the exchange/sandbox combination.

  ## Arguments

  - `exchange` - Exchange atom (e.g., `:binance`)
  - `sandbox_key` - Optional. Sandbox key (`:default`, `:futures`, `:coinm`). Defaults to `:default`.

  ## Examples

      # Default sandbox
      case CCXT.Testnet.creds(:bybit) do
        nil -> IO.puts("No credentials for bybit")
        creds -> CCXT.Bybit.fetch_balance(creds)
      end

      # Specific sandbox
      case CCXT.Testnet.creds(:binance, :futures) do
        nil -> IO.puts("No futures credentials for binance")
        creds -> CCXT.Binance.fetch_positions(creds, nil, [])
      end
  """
  @spec creds(atom(), atom()) :: CCXT.Credentials.t() | nil
  def creds(exchange, sandbox_key \\ :default) when is_atom(exchange) and is_atom(sandbox_key) do
    Agent.get(__MODULE__, &Map.get(&1, {exchange, sandbox_key}))
  end

  @doc """
  Get credentials or raise with helpful message.

  ## Examples

      creds = CCXT.Testnet.creds!(:bybit)
      CCXT.Bybit.fetch_balance(creds)

      creds = CCXT.Testnet.creds!(:binance, :futures)
      CCXT.Binance.fetch_positions(creds, nil, [])
  """
  @spec creds!(atom(), atom()) :: CCXT.Credentials.t()
  def creds!(exchange, sandbox_key \\ :default) when is_atom(exchange) and is_atom(sandbox_key) do
    case creds(exchange, sandbox_key) do
      nil ->
        key_str = if sandbox_key == :default, do: "#{exchange}", else: "#{exchange}/#{sandbox_key}"
        raise ArgumentError, "No credentials registered for #{key_str}"

      creds ->
        creds
    end
  end

  @doc """
  Check if exchange has credentials registered for a sandbox.

  ## Examples

      if CCXT.Testnet.registered?(:bybit) do
        run_authenticated_tests()
      end

      if CCXT.Testnet.registered?(:binance, :futures) do
        run_futures_tests()
      end
  """
  @spec registered?(atom(), atom()) :: boolean()
  def registered?(exchange, sandbox_key \\ :default) when is_atom(exchange) and is_atom(sandbox_key) do
    Agent.get(__MODULE__, &Map.has_key?(&1, {exchange, sandbox_key}))
  end

  @doc """
  Clear all credentials (for test isolation).

  ## Example

      setup do
        CCXT.Testnet.clear()
        :ok
      end
  """
  @spec clear() :: :ok
  def clear do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end

  @doc """
  List all registered exchange/sandbox combinations.

  Returns list of `{exchange, sandbox_key}` tuples.

  ## Example

      registered = CCXT.Testnet.registered_exchanges()
      # => [{:binance, :default}, {:binance, :futures}, {:bybit, :default}]
  """
  @spec registered_exchanges() :: [{atom(), atom()}]
  def registered_exchanges do
    Agent.get(__MODULE__, &Map.keys(&1))
  end

  @doc """
  List all unique exchange atoms that have any credentials registered.

  ## Example

      exchanges = CCXT.Testnet.exchanges_with_creds()
      # => [:binance, :bybit]
  """
  @spec exchanges_with_creds() :: [atom()]
  def exchanges_with_creds do
    Agent.get(__MODULE__, fn state ->
      state
      |> Map.keys()
      |> Enum.map(fn {exchange, _sandbox_key} -> exchange end)
      |> Enum.uniq()
    end)
  end

  # ===========================================================================
  # Sandbox Key Detection
  # ===========================================================================

  @doc """
  Derive sandbox_key from a sandbox URL.

  Analyzes the hostname to determine which credential set to use.

  ## Examples

      iex> CCXT.Testnet.sandbox_key_from_url("https://testnet.binance.vision/api/v3")
      :default

      iex> CCXT.Testnet.sandbox_key_from_url("https://testnet.binancefuture.com/fapi/v1")
      :futures

      iex> CCXT.Testnet.sandbox_key_from_url("https://testnet.binancefuture.com/dapi/v1")
      :coinm
  """
  @spec sandbox_key_from_url(String.t() | nil) :: atom()
  def sandbox_key_from_url(nil), do: :default

  def sandbox_key_from_url(url) when is_binary(url) do
    uri = URI.parse(url)
    host = uri.host || ""
    path = uri.path || ""

    cond do
      # COIN-M futures (inverse contracts) - check path first
      String.contains?(path, "/dapi") -> :coinm
      # USD-M futures (linear contracts)
      String.contains?(host, "future") -> :futures
      # Default (spot)
      true -> :default
    end
  end

  @doc """
  Get the environment variable prefix for a sandbox key.

  ## Examples

      iex> CCXT.Testnet.env_var_prefix(:binance, :default)
      "BINANCE_TESTNET"

      iex> CCXT.Testnet.env_var_prefix(:binance, :futures)
      "BINANCE_FUTURES_TESTNET"
  """
  @spec env_var_prefix(atom(), atom()) :: String.t()
  def env_var_prefix(exchange, sandbox_key) do
    prefix = exchange |> Atom.to_string() |> String.upcase()
    infix = sandbox_key_to_infix(sandbox_key)
    "#{prefix}#{infix}_TESTNET"
  end
end
