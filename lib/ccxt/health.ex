defmodule CCXT.Health do
  @moduledoc """
  Exchange health checks and latency monitoring.

  Provides stateless, one-shot health probes for exchanges. All functions
  accept exchange ID atoms (`:bybit`, `:binance`, etc.).

  ## Functions

  - `ping/1` — Is the exchange reachable?
  - `latency/1` — Round-trip latency in milliseconds
  - `all/1` — Bulk health check across multiple exchanges
  - `status/2` — Composite health snapshot (reachability + latency + circuit breaker)

  ## Examples

      CCXT.Health.ping(:bybit)
      # => :ok

      CCXT.Health.latency(:bybit)
      # => {:ok, 142.5}

      CCXT.Health.all([:bybit, :binance, :kraken])
      # => %{bybit: :ok, binance: :ok, kraken: {:error, %CCXT.Error{...}}}

      CCXT.Health.status(:bybit)
      # => {:ok, %{exchange: :bybit, reachable: true, latency_ms: 142.5, circuit: :ok}}

  """

  alias CCXT.CircuitBreaker
  alias CCXT.Error

  @default_timeout_ms 10_000

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Checks if an exchange is reachable.

  Calls `fetch_time/1` on the exchange module. Returns `:ok` if the exchange
  responds successfully, or `{:error, %Error{}}` on failure.

  ## Examples

      CCXT.Health.ping(:bybit)
      # => :ok

      CCXT.Health.ping(:nonexistent)
      # => {:error, %CCXT.Error{type: :not_supported}}

  """
  @spec ping(atom()) :: :ok | {:error, Error.t()}
  def ping(exchange_id) do
    with {:ok, module} <- resolve_module(exchange_id),
         {:ok, _time} <- module.fetch_time([]) do
      :ok
    end
  end

  @doc """
  Measures round-trip latency to an exchange in milliseconds.

  Wraps `fetch_time/1` with wall-clock timing. Returns the total round-trip
  duration including signing, rate-limit wait, and network time.

  ## Examples

      CCXT.Health.latency(:bybit)
      # => {:ok, 142.5}

  """
  @spec latency(atom()) :: {:ok, float()} | {:error, Error.t()}
  def latency(exchange_id) do
    with {:ok, module} <- resolve_module(exchange_id) do
      start = System.monotonic_time()
      result = module.fetch_time([])
      elapsed = System.monotonic_time() - start
      duration_ms = System.convert_time_unit(elapsed, :native, :microsecond) / 1000

      case result do
        {:ok, _time} -> {:ok, duration_ms}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Runs health checks across multiple exchanges concurrently.

  Returns a map of exchange ID to result. Uses `Task.async_stream/3` with
  `on_timeout: :kill_task` for safe concurrent execution.

  ## Options

  - `:timeout` — Per-exchange timeout in milliseconds (default: #{@default_timeout_ms})

  ## Examples

      CCXT.Health.all([:bybit, :binance])
      # => %{bybit: :ok, binance: :ok}

      CCXT.Health.all([:bybit, :nonexistent])
      # => %{bybit: :ok, nonexistent: {:error, %CCXT.Error{type: :not_supported}}}

  """
  @spec all([atom()], keyword()) :: %{atom() => :ok | {:error, term()}}
  def all(exchange_ids, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    exchange_ids
    |> Task.async_stream(&ping/1,
      timeout: timeout,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.zip(exchange_ids)
    |> Map.new(fn {result, id} ->
      case normalize_result(result) do
        {:ok, :ok} -> {id, :ok}
        {:ok, {:error, reason}} -> {id, {:error, reason}}
        {:error, reason} -> {id, {:error, reason}}
      end
    end)
  end

  @doc """
  Returns a composite health snapshot for an exchange.

  Combines reachability, latency measurement, and circuit breaker status
  into a single map.

  ## Options

  Reserved for future use (e.g., per-call timeout). Accepts a keyword list
  for forward-compatible expansion without arity changes.

  ## Return Value

  Returns `{:ok, map}` where map contains:

  - `:exchange` — Exchange atom
  - `:reachable` — Boolean indicating if exchange responded
  - `:latency_ms` — Round-trip latency in ms (float), or `nil` on failure
  - `:circuit` — Circuit breaker status: `:ok`, `:blown`, or `:not_installed`
  - `:error` — Present only on failure, contains the error reason

  ## Examples

      CCXT.Health.status(:bybit)
      # => {:ok, %{exchange: :bybit, reachable: true, latency_ms: 142.5, circuit: :ok}}

      CCXT.Health.status(:nonexistent)
      # => {:error, %CCXT.Error{type: :not_supported}}

  """
  @spec status(atom(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def status(exchange_id, _opts \\ []) do
    with {:ok, _module} <- resolve_module(exchange_id) do
      circuit = CircuitBreaker.status(exchange_id)

      case latency(exchange_id) do
        {:ok, duration_ms} ->
          {:ok,
           %{
             exchange: exchange_id,
             reachable: true,
             latency_ms: duration_ms,
             circuit: circuit
           }}

        {:error, reason} ->
          {:ok,
           %{
             exchange: exchange_id,
             reachable: false,
             latency_ms: nil,
             circuit: circuit,
             error: reason
           }}
      end
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  @doc false
  # Resolves exchange atom to its module, verifying it's a real CCXT exchange module.
  @spec resolve_module(atom()) :: {:ok, module()} | {:error, Error.t()}
  defp resolve_module(exchange_id) do
    module = Module.concat(CCXT, exchange_id |> Atom.to_string() |> Macro.camelize())

    if Code.ensure_loaded?(module) and function_exported?(module, :__ccxt_spec__, 0) do
      {:ok, module}
    else
      {:error, Error.not_supported(message: "Unknown exchange: #{exchange_id}", exchange: exchange_id)}
    end
  end

  @doc false
  # Normalizes Task.async_stream results, following the pattern from CCXT.Multi.
  @spec normalize_result({:ok, term()} | {:exit, term()}) :: {:ok, term()} | {:error, term()}
  defp normalize_result({:ok, {:ok, value}}), do: {:ok, {:ok, value}}
  defp normalize_result({:ok, {:error, reason}}), do: {:ok, {:error, reason}}
  defp normalize_result({:ok, other}), do: {:ok, other}
  defp normalize_result({:exit, :timeout}), do: {:error, :timeout}
  defp normalize_result({:exit, reason}), do: {:error, {:exit, reason}}
end
