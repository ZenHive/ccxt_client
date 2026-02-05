defmodule CCXT.HTTP.RateLimiter do
  @moduledoc """
  Per-credential weighted rate limiter for exchange API requests.

  Tracks request costs per `{exchange, credential_key}` using a sliding window.
  Costs are summed (not counted) to handle weighted endpoints correctly.

  ## Usage

  Start the rate limiter in your application supervision tree:

      children = [
        CCXT.HTTP.RateLimiter
      ]

  Then use `check_rate/4` before making requests:

      # Authenticated request (per-API-key tracking)
      key = {:binance, api_key}
      case CCXT.HTTP.RateLimiter.check_rate(key, rate_limit, cost) do
        :ok -> make_request()
        {:delay, ms} -> Process.sleep(ms); make_request()
      end

      # Public request (shared :public pool)
      key = {:binance, :public}
      CCXT.HTTP.RateLimiter.check_rate(key, rate_limit, cost)

  Or use `wait_for_capacity/4` which blocks until capacity is available:

      :ok = CCXT.HTTP.RateLimiter.wait_for_capacity(key, rate_limit, cost)
      make_request()

  ## Configuration

  Rate limits are defined per exchange in the spec:

      rate_limits: %{
        requests: 10,   # Max request weight per period
        period: 1000    # Period in milliseconds
      }

  ## Credential Keys

  The key is a tuple `{exchange, credential_key}` where:
  - `exchange` is the exchange atom (`:binance`, `:bybit`, etc.)
  - `credential_key` is either:
    - The API key string (for authenticated requests) - isolates per-user limits
    - `:public` atom (for public requests) - shared pool for unauthenticated requests

  This design ensures that:
  - User A's API calls don't affect User B's rate limits
  - Public endpoints share a common pool per exchange
  - Each exchange maintains separate buckets

  """

  use GenServer

  alias CCXT.Defaults

  @typedoc "Rate limit configuration with max weight and period in milliseconds"
  @type rate_limit :: %{requests: pos_integer(), period: pos_integer()}

  @typedoc """
  Rate limiter key: `{exchange, api_key | :public}`.

  Authenticated requests use the API key string for per-user tracking.
  Public requests use `:public` atom to share a common pool per exchange.
  """
  @type key :: {atom(), String.t() | :public}

  # Default period of 1 second if not specified
  @default_period_ms 1000

  # Default cost if not specified
  @default_cost 1

  # Maximum idle time before a key is evicted entirely (24 hours)
  # Keys with no activity for this duration are removed to prevent memory growth
  # from accumulating many unique API keys over time
  @key_eviction_age_ms 24 * 60 * 60 * 1000

  # Client API

  @doc """
  Returns a child specification for starting the rate limiter under a supervisor.

  ## Options

  - `:name` - GenServer name (default: `CCXT.HTTP.RateLimiter`)

  ## Examples

      # In your application supervision tree
      children = [
        CCXT.HTTP.RateLimiter,
        # Or with a custom name:
        {CCXT.HTTP.RateLimiter, name: :my_rate_limiter}
      ]

  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc """
  Starts the rate limiter.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Checks if a request can be made within rate limits.

  Returns `:ok` if within limits (and records the request), or `{:delay, milliseconds}`
  if the caller should wait before making the request.

  ## Parameters

  - `key` - `{exchange, api_key}` or `{exchange, :public}` tuple
  - `rate_limit` - `%{requests: max_weight, period: period_ms}` or nil (no limiting)
  - `cost` - Request weight/cost (default: 1)
  - `name` - GenServer name (default: `CCXT.HTTP.RateLimiter`)

  ## Examples

      # Authenticated request with cost
      check_rate({:binance, "my_api_key"}, %{requests: 1200, period: 60_000}, 4)

      # Public request (default cost of 1)
      check_rate({:binance, :public}, %{requests: 10, period: 1000})

  """
  @spec check_rate(key(), rate_limit() | nil, number(), GenServer.name()) ::
          :ok | {:delay, pos_integer()}
  def check_rate(key, rate_limit, cost \\ @default_cost, name \\ __MODULE__)

  def check_rate(_key, nil, _cost, _name), do: :ok

  def check_rate(key, %{requests: max_weight, period: period}, cost, name) do
    GenServer.call(name, {:check_rate, key, max_weight, period, cost})
  end

  def check_rate(key, %{requests: max_weight}, cost, name) do
    GenServer.call(name, {:check_rate, key, max_weight, @default_period_ms, cost})
  end

  @doc """
  Blocks until rate limit capacity is available, then records the request.

  Use this for simpler code when you don't need to handle delays yourself.

  ## Parameters

  - `key` - `{exchange, api_key}` or `{exchange, :public}` tuple
  - `rate_limit` - `%{requests: max_weight, period: period_ms}` or nil
  - `cost` - Request weight/cost (default: 1)
  - `name` - GenServer name (default: `CCXT.HTTP.RateLimiter`)

  ## Examples

      # Wait for capacity then make request
      :ok = wait_for_capacity({:binance, api_key}, rate_limit, 4)
      make_authenticated_request()

  """
  @spec wait_for_capacity(key(), rate_limit() | nil, number(), GenServer.name()) :: :ok
  def wait_for_capacity(key, rate_limit, cost \\ @default_cost, name \\ __MODULE__)

  def wait_for_capacity(_key, nil, _cost, _name), do: :ok

  def wait_for_capacity(key, rate_limit, cost, name) do
    case check_rate(key, rate_limit, cost, name) do
      :ok ->
        :ok

      {:delay, ms} ->
        Process.sleep(ms)
        wait_for_capacity(key, rate_limit, cost, name)
    end
  end

  @doc """
  Records a request for a key with specified cost.

  Called automatically by `check_rate/4` when it returns `:ok`.
  Exposed for manual tracking if needed.
  """
  @spec record_request(key(), number(), GenServer.name()) :: :ok
  def record_request(key, cost \\ @default_cost, name \\ __MODULE__) do
    GenServer.cast(name, {:record_request, key, cost})
  end

  @doc """
  Gets current total cost for a key within a time window.

  Useful for debugging and monitoring. Returns the sum of costs for requests
  made within the specified period.

  ## Parameters

  - `key` - `{exchange, api_key}` or `{exchange, :public}` tuple
  - `period` - Window period in milliseconds (requests older than this are excluded)
  - `name` - GenServer name (default: `CCXT.HTTP.RateLimiter`)

  ## Examples

      # Get cost within a 1-second window
      get_cost({:binance, :public}, 1000)

      # Get cost within a 1-minute window (like Binance's rate limit)
      get_cost({:binance, "api_key"}, 60_000)

  """
  @spec get_cost(key(), pos_integer(), GenServer.name()) :: number()
  def get_cost(key, period, name \\ __MODULE__) do
    GenServer.call(name, {:get_cost, key, period})
  end

  @doc """
  Resets rate limit tracking for a key.
  """
  @spec reset(key(), GenServer.name()) :: :ok
  def reset(key, name \\ __MODULE__) do
    GenServer.cast(name, {:reset, key})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    schedule_cleanup()
    # State: %{key => [{timestamp, cost}, ...]}
    {:ok, %{}}
  end

  @impl true
  def handle_call({:check_rate, key, max_weight, period, cost}, _from, state) do
    now = System.monotonic_time(:millisecond)
    window_start = now - period

    # Get and filter to recent requests only
    requests = Map.get(state, key, [])
    recent_requests = Enum.filter(requests, fn {ts, _cost} -> ts > window_start end)

    # Sum the costs of recent requests
    current_weight = Enum.reduce(recent_requests, 0, fn {_ts, c}, acc -> acc + c end)

    if current_weight + cost <= max_weight do
      # Within limit - record this request with its cost
      new_requests = [{now, cost} | recent_requests]
      new_state = Map.put(state, key, new_requests)
      {:reply, :ok, new_state}
    else
      # Over limit - calculate delay until enough weight expires
      delay = calculate_delay(recent_requests, current_weight, max_weight, cost, period, now)
      {:reply, {:delay, max(delay, 1)}, state}
    end
  end

  @impl true
  def handle_call({:get_cost, key, period}, _from, state) do
    now = System.monotonic_time(:millisecond)
    window_start = now - period

    total_cost =
      state
      |> Map.get(key, [])
      |> Enum.filter(fn {ts, _cost} -> ts > window_start end)
      |> Enum.reduce(0, fn {_ts, cost}, acc -> acc + cost end)

    {:reply, total_cost, state}
  end

  @impl true
  def handle_cast({:record_request, key, cost}, state) do
    now = System.monotonic_time(:millisecond)
    requests = Map.get(state, key, [])
    new_state = Map.put(state, key, [{now, cost} | requests])
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:reset, key}, state) do
    new_state = Map.delete(state, key)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)
    request_cutoff = now - Defaults.rate_limit_max_age_ms()
    eviction_cutoff = now - @key_eviction_age_ms

    # Remove expired timestamps from all keys and track last activity per key
    cleaned_state =
      Map.new(state, fn {key, requests} ->
        recent = Enum.filter(requests, fn {ts, _cost} -> ts > request_cutoff end)
        {key, recent}
      end)

    # Remove keys with no recent requests (normal cleanup)
    # Also evict keys where the most recent request is older than eviction threshold
    # This prevents memory growth from accumulating many unique API keys
    final_state =
      Map.filter(cleaned_state, fn {_key, requests} ->
        case requests do
          [] ->
            false

          [{newest_ts, _} | _] ->
            # Keep key if its most recent activity is within eviction window
            newest_ts > eviction_cutoff
        end
      end)

    schedule_cleanup()
    {:noreply, final_state}
  end

  # Calculate delay needed until we have enough capacity for the requested cost.
  # Finds how long we need to wait for old requests to expire to free up space.
  @spec calculate_delay([{integer(), number()}], number(), number(), number(), integer(), integer()) ::
          integer()
  defp calculate_delay(requests, current_weight, max_weight, cost, period, now) do
    # Sort by timestamp (oldest first)
    sorted = Enum.sort_by(requests, fn {ts, _cost} -> ts end)

    # Find how much weight needs to expire
    weight_to_free = current_weight + cost - max_weight

    # Accumulate oldest requests until we've freed enough weight
    {freed_weight, last_ts} =
      Enum.reduce_while(sorted, {0, now}, fn {ts, c}, {acc_weight, _last_ts} ->
        new_weight = acc_weight + c

        if new_weight >= weight_to_free do
          {:halt, {new_weight, ts}}
        else
          {:cont, {new_weight, ts}}
        end
      end)

    if freed_weight >= weight_to_free do
      # Add 1ms to ensure we're past the window boundary when we retry
      last_ts + period - now + 1
    else
      # Edge case: sorted is empty or total weight is less than weight_to_free.
      # This shouldn't happen in normal operation since we only call calculate_delay
      # when current_weight + cost > max_weight, but we fall back to a full period
      # wait as a safe default.
      period
    end
  end

  @spec schedule_cleanup() :: reference()
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, Defaults.rate_limit_cleanup_interval_ms())
  end
end
