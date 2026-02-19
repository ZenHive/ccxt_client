defmodule CCXT.Telemetry do
  @moduledoc """
  Centralized telemetry contract for CCXT.

  This module is the single source of truth for all telemetry events emitted by
  the CCXT library. Both `CCXT.HTTP.Client` and `CCXT.CircuitBreaker` delegate
  their event names to this module.

  ## Contract Version

  The contract version (`contract_version/0`) is bumped on breaking changes to
  event names, measurements, or metadata shapes. This allows consumers to assert
  compatibility at startup.

  ## Request Events

  Emitted by `CCXT.HTTP.Client` during HTTP request lifecycle.

  ### `[:ccxt, :request, :start]`

  Emitted before the HTTP request is sent.

  - **Measurements:** `%{system_time: integer()}`
  - **Metadata:** `%{exchange: atom(), method: atom(), path: String.t()}`

  ### `[:ccxt, :request, :stop]`

  Emitted after a successful HTTP response (any status code).

  - **Measurements:** `%{duration: integer()}` (native time units)
  - **Metadata:** `%{exchange: atom(), method: atom(), path: String.t(), status: integer()}`
  - **Optional metadata:** `rate_limit: %CCXT.HTTP.RateLimitInfo{}` when the
    exchange returns rate limit headers

  ### `[:ccxt, :request, :exception]`

  Emitted when the request raises or returns a transport/request error.

  - **Measurements:** `%{duration: integer()}` (native time units)
  - **Metadata:** `%{exchange: atom(), method: atom(), path: String.t(), kind: atom(), reason: term()}`

  ## Circuit Breaker Events

  Emitted by `CCXT.CircuitBreaker` on state transitions.

  ### `[:ccxt, :circuit_breaker, :open]`

  Emitted when a circuit breaker opens after exceeding the failure threshold.

  - **Measurements:** `%{system_time: integer()}`
  - **Metadata:** `%{exchange: atom()}`

  ### `[:ccxt, :circuit_breaker, :closed]`

  Emitted when a circuit breaker resets (closes) after the reset timeout.

  - **Measurements:** `%{system_time: integer()}`
  - **Metadata:** `%{exchange: atom()}`

  ### `[:ccxt, :circuit_breaker, :rejected]`

  Emitted when a request is rejected because the circuit is open.

  - **Measurements:** `%{system_time: integer()}`
  - **Metadata:** `%{exchange: atom()}`
  """

  @contract_version 1

  @request_start_event [:ccxt, :request, :start]
  @request_stop_event [:ccxt, :request, :stop]
  @request_exception_event [:ccxt, :request, :exception]
  @circuit_breaker_open_event [:ccxt, :circuit_breaker, :open]
  @circuit_breaker_closed_event [:ccxt, :circuit_breaker, :closed]
  @circuit_breaker_rejected_event [:ccxt, :circuit_breaker, :rejected]

  @request_events [@request_start_event, @request_stop_event, @request_exception_event]
  @circuit_breaker_events [
    @circuit_breaker_open_event,
    @circuit_breaker_closed_event,
    @circuit_breaker_rejected_event
  ]
  @all_events @request_events ++ @circuit_breaker_events

  # ============================================================================
  # Contract Version
  # ============================================================================

  @doc """
  Returns the telemetry contract version.

  Bumped on breaking changes to event names, measurements, or metadata shapes.
  Consumers can assert compatibility at startup:

      if CCXT.Telemetry.contract_version() != 1 do
        raise "Incompatible CCXT telemetry contract"
      end

  """
  @spec contract_version() :: pos_integer()
  def contract_version, do: @contract_version

  # ============================================================================
  # Event Name Functions
  # ============================================================================

  @doc "Event name for request start: `[:ccxt, :request, :start]`."
  @spec request_start() :: [atom()]
  def request_start, do: @request_start_event

  @doc "Event name for request stop: `[:ccxt, :request, :stop]`."
  @spec request_stop() :: [atom()]
  def request_stop, do: @request_stop_event

  @doc "Event name for request exception: `[:ccxt, :request, :exception]`."
  @spec request_exception() :: [atom()]
  def request_exception, do: @request_exception_event

  @doc "Event name for circuit breaker open: `[:ccxt, :circuit_breaker, :open]`."
  @spec circuit_breaker_open() :: [atom()]
  def circuit_breaker_open, do: @circuit_breaker_open_event

  @doc "Event name for circuit breaker closed: `[:ccxt, :circuit_breaker, :closed]`."
  @spec circuit_breaker_closed() :: [atom()]
  def circuit_breaker_closed, do: @circuit_breaker_closed_event

  @doc "Event name for circuit breaker rejected: `[:ccxt, :circuit_breaker, :rejected]`."
  @spec circuit_breaker_rejected() :: [atom()]
  def circuit_breaker_rejected, do: @circuit_breaker_rejected_event

  # ============================================================================
  # Event Lists
  # ============================================================================

  @doc "Returns all 6 telemetry event names."
  @spec events() :: [[atom()]]
  def events, do: @all_events

  @doc "Returns the 3 HTTP request event names."
  @spec request_events() :: [[atom()]]
  def request_events, do: @request_events

  @doc "Returns the 3 circuit breaker event names."
  @spec circuit_breaker_events() :: [[atom()]]
  def circuit_breaker_events, do: @circuit_breaker_events

  # ============================================================================
  # Convenience API
  # ============================================================================

  @doc """
  Attaches a handler to all CCXT telemetry events.

  Wraps `:telemetry.attach_many/4` with `events/0` as the event list.

  ## Parameters

  - `handler_id` - Unique string identifying this handler (for later detach)
  - `handler_fn` - Function of arity 4: `(event, measurements, metadata, config)`
  - `config` - Optional handler config passed as the 4th argument to `handler_fn` (default: `nil`)

  ## Example

      CCXT.Telemetry.attach("my-logger", fn event, measurements, metadata, _config ->
        Logger.info("CCXT event: \#{inspect(event)}")
      end)

  """
  @spec attach(String.t(), (list(), map(), map(), term() -> any()), term()) ::
          :ok | {:error, :already_exists}
  def attach(handler_id, handler_fn, config \\ nil) when is_binary(handler_id) and is_function(handler_fn, 4) do
    :telemetry.attach_many(handler_id, events(), handler_fn, config)
  end

  @doc """
  Detaches a previously attached handler by ID.

  Wraps `:telemetry.detach/1`.
  """
  @spec detach(String.t()) :: :ok | {:error, :not_found}
  def detach(handler_id) when is_binary(handler_id) do
    :telemetry.detach(handler_id)
  end
end
