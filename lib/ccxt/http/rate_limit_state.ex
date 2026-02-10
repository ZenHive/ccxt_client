defmodule CCXT.HTTP.RateLimitState do
  @moduledoc """
  ETS-backed store for rate limit status across exchanges.

  Stores the latest `RateLimitInfo` from each exchange response, keyed by
  `{exchange, api_key | :public}`. This allows consumers to query current
  rate limit pressure at any time.

  ## Architecture

  A GenServer owns the ETS table (OTP-idiomatic — handles restarts cleanly).
  The table is `:public` with `read_concurrency: true` so any process can
  read without going through the GenServer.

  ## Usage

      # Query current rate limit status for an exchange's public endpoints
      case RateLimitState.status(:binance) do
        %RateLimitInfo{remaining: remaining} -> remaining
        nil -> :unknown
      end

      # Query for a specific API key
      RateLimitState.status(:binance, "my_api_key")

  """

  use GenServer

  alias CCXT.HTTP.RateLimitInfo

  @table :ccxt_rate_limit_state

  @doc """
  Starts the RateLimitState GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Updates the rate limit info for a given key.

  Key is typically `{exchange, api_key | :public}` — the same shape as
  `build_rate_key/2` in `CCXT.HTTP.Client`.
  """
  @spec update({atom(), term()}, RateLimitInfo.t()) :: :ok
  def update(key, %RateLimitInfo{} = info) do
    :ets.insert(@table, {key, info, System.monotonic_time()})
    :ok
  end

  @doc """
  Returns the latest rate limit info for an exchange's public endpoints.
  """
  @spec status(atom()) :: RateLimitInfo.t() | nil
  def status(exchange) when is_atom(exchange) do
    status(exchange, :public)
  end

  @doc """
  Returns the latest rate limit info for a specific exchange + credential key.
  """
  @spec status(atom(), term()) :: RateLimitInfo.t() | nil
  def status(exchange, credential_key) when is_atom(exchange) do
    case :ets.lookup(@table, {exchange, credential_key}) do
      [{_key, info, _timestamp}] -> info
      [] -> nil
    end
  end

  @doc """
  Returns all rate limit entries for an exchange.
  """
  @spec all(atom()) :: [RateLimitInfo.t()]
  def all(exchange) when is_atom(exchange) do
    # Match all keys starting with {exchange, _}
    match_spec = [{{{exchange, :_}, :"$1", :_}, [], [:"$1"]}]
    :ets.select(@table, match_spec)
  end

  # =============================================================================
  # GenServer Callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end
end
