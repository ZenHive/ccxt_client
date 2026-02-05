defmodule CCXT.Defaults do
  @moduledoc """
  Centralized default configuration values for ccxt_ex.

  All defaults can be overridden via application config:

      config :ccxt_client,
        recv_window_ms: 10_000,
        request_timeout_ms: 60_000

  ## Available Defaults

  | Config Key | Default | Description |
  |------------|---------|-------------|
  | `:recv_window_ms` | 5000 | Request timestamp validity window (exchanges reject stale requests) |
  | `:request_timeout_ms` | 30000 | HTTP request timeout |
  | `:extraction_timeout_ms` | 30000 | Per-exchange extraction timeout in mix tasks |
  | `:rate_limit_cleanup_interval_ms` | 60000 | Interval for cleaning up old rate limit timestamps |
  | `:rate_limit_max_age_ms` | 60000 | Maximum age for rate limit request timestamps |
  | `:retry_policy` | `:safe_transient` (prod), `false` (test) | HTTP retry strategy |

  ## Usage

  These functions are used internally by ccxt_ex modules. You typically don't
  need to call them directly - just set the config values.

      # In config/config.exs
      config :ccxt_client,
        recv_window_ms: 10_000,       # More lenient for high-latency connections
        request_timeout_ms: 60_000    # Longer timeout for slow exchanges

  """

  # Default values (module attributes for compile-time optimization)
  @default_recv_window_ms 5_000
  @default_request_timeout_ms 30_000
  @default_extraction_timeout_ms 30_000
  @default_rate_limit_cleanup_interval_ms 60_000
  @default_rate_limit_max_age_ms 60_000
  @default_retry_policy :safe_transient

  @doc """
  Returns the recv_window value in milliseconds.

  The recv_window (receive window) defines how long a signed request is valid.
  Exchanges reject requests with timestamps outside this window to prevent
  replay attacks.

  Default: #{@default_recv_window_ms}ms

  Override via:

      config :ccxt_client, recv_window_ms: 10_000

  """
  @spec recv_window_ms() :: pos_integer()
  def recv_window_ms do
    Application.get_env(:ccxt_client, :recv_window_ms, @default_recv_window_ms)
  end

  @doc """
  Returns the HTTP request timeout in milliseconds.

  This is the maximum time to wait for a response from an exchange API.

  Default: #{@default_request_timeout_ms}ms

  Override via:

      config :ccxt_client, request_timeout_ms: 60_000

  """
  @spec request_timeout_ms() :: pos_integer()
  def request_timeout_ms do
    Application.get_env(:ccxt_client, :request_timeout_ms, @default_request_timeout_ms)
  end

  @doc """
  Returns the per-exchange extraction timeout in milliseconds.

  Used by mix tasks when extracting exchange specs in bulk. Each exchange
  extraction must complete within this timeout.

  Default: #{@default_extraction_timeout_ms}ms

  Override via:

      config :ccxt_client, extraction_timeout_ms: 60_000

  """
  @spec extraction_timeout_ms() :: pos_integer()
  def extraction_timeout_ms do
    Application.get_env(:ccxt_client, :extraction_timeout_ms, @default_extraction_timeout_ms)
  end

  @doc """
  Returns the rate limiter cleanup interval in milliseconds.

  The rate limiter periodically cleans up old request timestamps that are
  no longer relevant for rate calculation.

  Default: #{@default_rate_limit_cleanup_interval_ms}ms

  Override via:

      config :ccxt_client, rate_limit_cleanup_interval_ms: 120_000

  """
  @spec rate_limit_cleanup_interval_ms() :: pos_integer()
  def rate_limit_cleanup_interval_ms do
    Application.get_env(
      :ccxt_client,
      :rate_limit_cleanup_interval_ms,
      @default_rate_limit_cleanup_interval_ms
    )
  end

  @doc """
  Returns the maximum age for rate limit request timestamps in milliseconds.

  Request timestamps older than this are removed during cleanup.

  Default: #{@default_rate_limit_max_age_ms}ms

  Override via:

      config :ccxt_client, rate_limit_max_age_ms: 120_000

  """
  @spec rate_limit_max_age_ms() :: pos_integer()
  def rate_limit_max_age_ms do
    Application.get_env(:ccxt_client, :rate_limit_max_age_ms, @default_rate_limit_max_age_ms)
  end

  @doc """
  Returns the HTTP retry policy.

  ## Trading Safety (CRITICAL)

  This library uses `:safe_transient` by default because it only retries
  GET/HEAD requests. **Never use `:transient` for trading APIs.**

  **Why this matters:**

  - Using `:transient` on POST order submissions could duplicate orders
  - Example: Order succeeds but response times out → retry → duplicate order
  - This can cause significant financial loss

  **The `:safe_transient` policy:**

  - Retries: GET, HEAD on 408/429/500/502/503/504, timeouts, connection refused
  - Does NOT retry: POST, PUT, DELETE, PATCH

  For idempotent POST endpoints (with idempotency keys), consumers can
  override with `retry: :transient` at the call site.

  ## Defaults

  - Test environment: `false` (no retries) for fast feedback
  - Other environments: `:safe_transient` which retries safe HTTP methods
    on transient errors (502, 503, 504, timeouts)

  Override via:

      config :ccxt_client, retry_policy: false

  """
  @spec retry_policy() :: :safe_transient | :transient | false
  def retry_policy do
    case Application.get_env(:ccxt_client, :retry_policy) do
      nil ->
        if Mix.env() == :test, do: false, else: @default_retry_policy

      value ->
        value
    end
  end

  # =============================================================================
  # Raw Default Accessors (for CCXT.Config spec generation)
  # =============================================================================

  @doc false
  # Returns raw default values for config spec generation.
  # Used by CCXT.Config to avoid duplication of default values.
  @spec raw_defaults() :: %{
          recv_window_ms: pos_integer(),
          request_timeout_ms: pos_integer(),
          extraction_timeout_ms: pos_integer(),
          rate_limit_cleanup_interval_ms: pos_integer(),
          rate_limit_max_age_ms: pos_integer(),
          retry_policy: atom(),
          retry_policy_test: boolean()
        }
  def raw_defaults do
    %{
      recv_window_ms: @default_recv_window_ms,
      request_timeout_ms: @default_request_timeout_ms,
      extraction_timeout_ms: @default_extraction_timeout_ms,
      rate_limit_cleanup_interval_ms: @default_rate_limit_cleanup_interval_ms,
      rate_limit_max_age_ms: @default_rate_limit_max_age_ms,
      retry_policy: @default_retry_policy,
      retry_policy_test: false
    }
  end
end
