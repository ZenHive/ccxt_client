defmodule CCXT.CircuitBreaker do
  @moduledoc """
  Per-exchange circuit breakers using req_fuse.

  Prevents cascade failures when exchanges are down. Each exchange has isolated
  state - binance down does not affect bybit.

  ## How It Works

  1. Each exchange gets its own fuse named `:ccxt_fuse_<exchange_id>`
  2. Fuses are installed lazily on first request
  3. After N failures within M milliseconds, the circuit opens
  4. Opened circuits reject requests immediately (fast fail)
  5. After reset timeout, circuit closes and allows requests again

  ## What Triggers the Circuit (Melt Function)

  | Response | Melts? | Reason |
  |----------|--------|--------|
  | HTTP 500+ | Yes | Server error |
  | Timeouts | Yes | Server unresponsive |
  | Connection refused | Yes | Server unavailable |
  | HTTP 429 | **No** | Already handled by RateLimiter |
  | HTTP 400 | **No** | Client error, not server issue |

  ## Configuration

      config :ccxt_client, :circuit_breaker,
        enabled: true,
        max_failures: 5,       # Failures before circuit opens (0 = disabled)
        window_ms: 10_000,     # Time window for counting failures
        reset_ms: 15_000       # Time before circuit resets (closes)

  Note: Setting `max_failures: 0` effectively disables the circuit breaker
  (equivalent to `enabled: false`).

  ## Telemetry Events

  See `CCXT.Telemetry` for the full event contract.

  ## Usage

      # Check status
      CCXT.CircuitBreaker.status(:binance)
      # => :ok | :blown | :not_installed

      # Reset a blown circuit manually
      CCXT.CircuitBreaker.reset(:binance)
      # => :ok | {:error, :not_found}

      # Get all circuit statuses
      CCXT.CircuitBreaker.all_statuses()
      # => %{binance: :ok, bybit: :blown}

  """

  require Logger

  @fuse_prefix :ccxt_fuse_
  @fuse_mode :sync

  # Track which fuses we've installed (for all_statuses)
  @installed_fuses_key {__MODULE__, :installed_fuses}

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Returns the status of a circuit breaker for an exchange.

  ## Returns

  - `:ok` - Circuit is closed, requests allowed
  - `:blown` - Circuit is open, requests will be rejected
  - `:not_installed` - No fuse installed yet (no requests made)

  ## Example

      CCXT.CircuitBreaker.status(:binance)
      # => :ok

  """
  @spec status(atom()) :: :ok | :blown | :not_installed
  def status(exchange_id) do
    fuse_name = fuse_name(exchange_id)

    case :fuse.ask(fuse_name, @fuse_mode) do
      :ok -> :ok
      :blown -> :blown
      {:error, :not_found} -> :not_installed
    end
  end

  @doc """
  Resets a circuit breaker for an exchange.

  ## Returns

  - `:ok` - Circuit was reset successfully
  - `{:error, :not_found}` - No fuse installed for this exchange

  ## Example

      CCXT.CircuitBreaker.reset(:binance)
      # => :ok

  """
  @spec reset(atom()) :: :ok | {:error, :not_found}
  def reset(exchange_id) do
    fuse_name = fuse_name(exchange_id)

    case :fuse.reset(fuse_name) do
      :ok ->
        emit_closed(exchange_id)
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Resets a circuit breaker for an exchange, raising on error.

  ## Raises

  - `ArgumentError` if no fuse is installed for this exchange

  ## Example

      CCXT.CircuitBreaker.reset!(:binance)
      # => :ok

  """
  @spec reset!(atom()) :: :ok
  def reset!(exchange_id) do
    case reset(exchange_id) do
      :ok -> :ok
      {:error, :not_found} -> raise ArgumentError, "No circuit breaker found for #{exchange_id}"
    end
  end

  @doc """
  Returns status of all installed circuit breakers.

  Only returns exchanges with active fuses (excludes any that were uninstalled).

  ## Example

      CCXT.CircuitBreaker.all_statuses()
      # => %{binance: :ok, bybit: :blown, okx: :ok}

  """
  @spec all_statuses() :: %{atom() => :ok | :blown}
  def all_statuses do
    Enum.reduce(installed_fuses(), %{}, fn exchange_id, acc ->
      case status(exchange_id) do
        # Only include active fuses, skip any that were uninstalled
        :not_installed -> acc
        status -> Map.put(acc, exchange_id, status)
      end
    end)
  end

  @doc """
  Checks if requests are allowed for an exchange.

  Installs the fuse lazily if not already installed.

  ## Returns

  - `:ok` - Requests allowed
  - `:blown` - Circuit is open, requests should be rejected

  """
  @spec check(atom()) :: :ok | :blown
  def check(exchange_id) do
    config = config()

    if enabled?(config) do
      ensure_installed(exchange_id, config)
      fuse_name = fuse_name(exchange_id)

      case :fuse.ask(fuse_name, @fuse_mode) do
        :ok ->
          :ok

        :blown ->
          emit_rejected(exchange_id)
          :blown

        {:error, :not_found} ->
          # Shouldn't happen after ensure_installed, but handle gracefully
          :ok
      end
    else
      :ok
    end
  end

  @doc """
  Records a successful request for an exchange.

  Success doesn't actively heal the fuse, but prevents further melts.
  The fuse heals automatically after the reset timeout.
  """
  @spec record_success(atom()) :: :ok
  def record_success(_exchange_id) do
    # Fuse library doesn't have a "heal" function - it auto-resets after timeout
    # Success just means we don't melt
    :ok
  end

  @doc """
  Records a failed request for an exchange.

  This "melts" the fuse a little. After enough melts within the time window,
  the circuit opens.
  """
  @spec record_failure(atom()) :: :ok
  def record_failure(exchange_id) do
    config = config()

    if enabled?(config) do
      ensure_installed(exchange_id, config)
      fuse_name = fuse_name(exchange_id)
      previous_status = :fuse.ask(fuse_name, @fuse_mode)
      :fuse.melt(fuse_name)
      current_status = :fuse.ask(fuse_name, @fuse_mode)

      # Emit open event if circuit just opened
      if previous_status == :ok and current_status == :blown do
        emit_open(exchange_id)
      end
    end

    :ok
  end

  @doc """
  Records the result of a request, using `should_melt?/1` to determine action.

  This is the recommended way to record circuit breaker results from HTTP responses.
  Pass the raw result from Req (either `{:ok, %Req.Response{}}` or `{:error, reason}`).

  ## Examples

      result = Req.request(opts)
      CCXT.CircuitBreaker.record_result(:binance, result)

  """
  @spec record_result(atom(), term()) :: :ok
  def record_result(exchange_id, result) do
    if should_melt?(result) do
      record_failure(exchange_id)
    else
      record_success(exchange_id)
    end
  end

  @doc """
  Determines if a response should trip the circuit breaker.

  ## What Melts the Fuse

  - HTTP 500+ server errors
  - Transport errors (timeout, connection refused)
  - Other unexpected errors

  ## What Does NOT Melt

  - HTTP 429 rate limits (handled by RateLimiter)
  - HTTP 4xx client errors (not server's fault)
  - Successful responses (2xx, 3xx)

  """
  @spec should_melt?(term()) :: boolean()
  # Note: Use map pattern matching instead of struct syntax to avoid compile-time
  # struct expansion issues when ccxt_ex is used as a dependency (Req may not be
  # compiled yet). The __struct__ field is just an atom, no expansion needed.
  def should_melt?({:ok, %{__struct__: Req.Response, status: status}}) when status >= 500, do: true
  def should_melt?({:ok, %{__struct__: Req.Response}}), do: false

  def should_melt?({:error, %{__struct__: Req.TransportError, reason: :timeout}}), do: true
  def should_melt?({:error, %{__struct__: Req.TransportError, reason: :econnrefused}}), do: true
  def should_melt?({:error, %{__struct__: Req.TransportError, reason: :closed}}), do: true
  def should_melt?({:error, %{__struct__: Req.TransportError, reason: :nxdomain}}), do: true

  # Catch-all for other transport errors
  def should_melt?({:error, %{__struct__: Req.TransportError}}), do: true

  # Generic errors - be conservative and melt
  def should_melt?({:error, _reason}), do: true

  # Anything else (nil, bare :ok, unexpected values) - don't melt
  # This is the safe default: only trip circuit on known failure patterns
  def should_melt?(_), do: false

  # =============================================================================
  # Configuration
  # =============================================================================

  @default_enabled true
  @default_max_failures 5
  @default_window_ms 10_000
  @default_reset_ms 15_000

  @doc """
  Returns circuit breaker configuration.
  """
  @spec config() :: %{
          enabled: boolean(),
          max_failures: pos_integer(),
          window_ms: pos_integer(),
          reset_ms: pos_integer()
        }
  def config do
    app_config = Application.get_env(:ccxt_client, :circuit_breaker, %{})

    # Handle both map and keyword list configs
    get_config = fn key, default ->
      cond do
        is_map(app_config) -> Map.get(app_config, key, default)
        is_list(app_config) -> Keyword.get(app_config, key, default)
        true -> default
      end
    end

    %{
      enabled: get_config.(:enabled, @default_enabled),
      max_failures: get_config.(:max_failures, @default_max_failures),
      window_ms: get_config.(:window_ms, @default_window_ms),
      reset_ms: get_config.(:reset_ms, @default_reset_ms)
    }
  end

  # =============================================================================
  # Internal Helpers
  # =============================================================================

  @doc false
  # Returns fuse name for an exchange
  @spec fuse_name(atom()) :: atom()
  def fuse_name(exchange_id) do
    :"#{@fuse_prefix}#{exchange_id}"
  end

  @doc false
  # Checks if circuit breaker is effectively enabled
  # Disabled if enabled: false OR max_failures: 0
  @spec enabled?(map()) :: boolean()
  defp enabled?(config) do
    config.enabled and config.max_failures > 0
  end

  @doc false
  # Ensures fuse is installed for exchange, installs if not present
  defp ensure_installed(exchange_id, config) do
    fuse_name = fuse_name(exchange_id)

    case :fuse.ask(fuse_name, @fuse_mode) do
      {:error, :not_found} ->
        install_fuse(exchange_id, fuse_name, config)

      _ ->
        :ok
    end
  end

  @doc false
  # Installs a new fuse with configured options
  defp install_fuse(exchange_id, fuse_name, config) do
    # Fuse options: {{:standard, N, M}, {:reset, R}}
    # The fuse library "permits N failures" then blows on N+1.
    # We subtract 1 so max_failures: 5 means "blow after 5 failures" (user expectation)
    permitted_failures = max(config.max_failures - 1, 0)
    fuse_opts = {{:standard, permitted_failures, config.window_ms}, {:reset, config.reset_ms}}

    case :fuse.install(fuse_name, fuse_opts) do
      :ok ->
        track_installed(exchange_id)
        :ok

      :reset ->
        # Fuse already existed but was reset
        track_installed(exchange_id)
        :ok

      {:error, reason} ->
        Logger.warning("[CCXT.CircuitBreaker] Failed to install fuse for #{exchange_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc false
  # Tracks exchange in persistent_term for all_statuses/0 enumeration.
  # Race condition on concurrent first requests is handled by Enum.uniq in installed_fuses/0.
  defp track_installed(exchange_id) do
    current = installed_fuses()

    if exchange_id not in current do
      :persistent_term.put(@installed_fuses_key, [exchange_id | current])
    end
  end

  @doc false
  # Returns list of exchanges with installed fuses.
  # Dedupes via Enum.uniq/1 to handle race condition where concurrent first
  # requests to the same exchange both call track_installed/1.
  defp installed_fuses do
    @installed_fuses_key
    |> :persistent_term.get([])
    |> Enum.uniq()
  end

  # =============================================================================
  # Telemetry
  # =============================================================================

  @doc false
  defp emit_open(exchange_id) do
    :telemetry.execute(
      CCXT.Telemetry.circuit_breaker_open(),
      %{system_time: System.system_time()},
      %{exchange: exchange_id}
    )

    Logger.warning("[CCXT.CircuitBreaker] Circuit OPEN for #{exchange_id} - requests will be rejected")
  end

  @doc false
  defp emit_closed(exchange_id) do
    :telemetry.execute(
      CCXT.Telemetry.circuit_breaker_closed(),
      %{system_time: System.system_time()},
      %{exchange: exchange_id}
    )

    Logger.info("[CCXT.CircuitBreaker] Circuit CLOSED for #{exchange_id} - requests allowed")
  end

  @doc false
  defp emit_rejected(exchange_id) do
    :telemetry.execute(
      CCXT.Telemetry.circuit_breaker_rejected(),
      %{system_time: System.system_time()},
      %{exchange: exchange_id}
    )
  end

  # =============================================================================
  # Raw Default Accessors (for CCXT.Config spec generation)
  # =============================================================================

  @doc false
  # Returns raw default values for config spec generation.
  # Used by CCXT.Config to avoid duplication of default values.
  @spec raw_defaults() :: %{
          enabled: boolean(),
          max_failures: pos_integer(),
          window_ms: pos_integer(),
          reset_ms: pos_integer()
        }
  def raw_defaults do
    %{
      enabled: @default_enabled,
      max_failures: @default_max_failures,
      window_ms: @default_window_ms,
      reset_ms: @default_reset_ms
    }
  end
end
