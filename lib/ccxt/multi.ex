defmodule CCXT.Multi do
  @moduledoc """
  Parallel fetch operations across multiple exchanges.

  Enables fetching data from multiple exchanges concurrently with graceful
  handling of partial failures. Essential for dashboards, price comparison,
  and arbitrage detection.

  ## Key Features

  - **Partial failure handling**: One exchange failing doesn't kill the whole request
  - **Concurrent execution**: Uses Task.async_stream for efficient parallel fetching
  - **Configurable timeouts**: Per-exchange timeout with sensible defaults
  - **Result helpers**: Easy extraction of successes and failures

  ## Usage

      # Fetch tickers from multiple exchanges
      result = Multi.fetch_tickers([CCXT.Bybit, CCXT.Binance], "BTC/USDT")
      # => %{CCXT.Bybit => {:ok, %{...}}, CCXT.Binance => {:ok, %{...}}}

      # Get only successful results
      tickers = Multi.successes(result)
      # => %{CCXT.Bybit => %{...}, CCXT.Binance => %{...}}

      # Check which exchanges failed
      failures = Multi.failures(result)
      # => %{}  (empty if all succeeded)

      # Generic parallel call for any function
      result = Multi.parallel_call(exchanges, :fetch_balance, [credentials], timeout: 15_000)

  ## Notes

  - All functions are public endpoint calls (no authentication required)
  - For authenticated calls, use `parallel_call/4` with credentials as args
  - Timeout is per-exchange, not total (total time ≈ max(individual timeouts))
  """

  @default_timeout_ms 10_000

  @typedoc "Result map with exchange module as key and {:ok, value} | {:error, reason} as value"
  @type result(t) :: %{module() => {:ok, t} | {:error, term()}}

  @doc """
  Fetches tickers from multiple exchanges in parallel.

  Returns partial results - one exchange failing doesn't kill the whole request.
  Essential for dashboards and price comparison.

  ## Parameters

  - `exchange_modules` - List of exchange modules (e.g., `[CCXT.Bybit, CCXT.Binance]`)
  - `symbol` - Unified symbol (e.g., `"BTC/USDT"`)
  - `opts` - Options:
    - `:timeout` - Timeout per exchange in ms (default: #{@default_timeout_ms})

  ## Examples

      iex> result = CCXT.Multi.fetch_tickers([CCXT.Bybit, CCXT.Binance], "BTC/USDT")
      iex> is_map(result)
      true

  """
  @spec fetch_tickers([module()], String.t(), keyword()) :: result(map())
  def fetch_tickers(exchange_modules, symbol, opts \\ []) do
    parallel_call(exchange_modules, :fetch_ticker, [symbol], opts)
  end

  @doc """
  Fetches order books from multiple exchanges in parallel.

  ## Parameters

  - `exchange_modules` - List of exchange modules
  - `symbol` - Unified symbol (e.g., `"BTC/USDT"`)
  - `opts` - Options:
    - `:timeout` - Timeout per exchange in ms (default: #{@default_timeout_ms})
    - `:limit` - Order book depth limit (passed to exchange)

  ## Examples

      iex> result = CCXT.Multi.fetch_order_books([CCXT.Bybit, CCXT.Binance], "BTC/USDT")
      iex> is_map(result)
      true

  """
  @spec fetch_order_books([module()], String.t(), keyword()) :: result(map())
  def fetch_order_books(exchange_modules, symbol, opts \\ []) do
    {call_opts, fetch_opts} = Keyword.split(opts, [:timeout])
    parallel_call(exchange_modules, :fetch_order_book, [symbol, fetch_opts], call_opts)
  end

  @doc """
  Fetches OHLCV candles from multiple exchanges in parallel.

  ## Parameters

  - `exchange_modules` - List of exchange modules
  - `symbol` - Unified symbol (e.g., `"BTC/USDT"`)
  - `timeframe` - Candle timeframe (e.g., `"1h"`, `"1d"`)
  - `opts` - Options:
    - `:timeout` - Timeout per exchange in ms (default: #{@default_timeout_ms})
    - `:since` - Start time in milliseconds
    - `:limit` - Number of candles

  ## Examples

      iex> result = CCXT.Multi.fetch_ohlcv([CCXT.Bybit, CCXT.Binance], "BTC/USDT", "1h")
      iex> is_map(result)
      true

  """
  @spec fetch_ohlcv([module()], String.t(), String.t(), keyword()) :: result(list())
  def fetch_ohlcv(exchange_modules, symbol, timeframe, opts \\ []) do
    {call_opts, fetch_opts} = Keyword.split(opts, [:timeout])
    parallel_call(exchange_modules, :fetch_ohlcv, [symbol, timeframe, fetch_opts], call_opts)
  end

  @doc """
  Fetches recent trades from multiple exchanges in parallel.

  ## Parameters

  - `exchange_modules` - List of exchange modules
  - `symbol` - Unified symbol (e.g., `"BTC/USDT"`)
  - `opts` - Options:
    - `:timeout` - Timeout per exchange in ms (default: #{@default_timeout_ms})
    - `:limit` - Number of trades to fetch

  ## Examples

      iex> result = CCXT.Multi.fetch_trades([CCXT.Bybit, CCXT.Binance], "BTC/USDT")
      iex> is_map(result)
      true

  """
  @spec fetch_trades([module()], String.t(), keyword()) :: result(list())
  def fetch_trades(exchange_modules, symbol, opts \\ []) do
    {call_opts, fetch_opts} = Keyword.split(opts, [:timeout])
    parallel_call(exchange_modules, :fetch_trades, [symbol, fetch_opts], call_opts)
  end

  @doc """
  Generic parallel call - call any function on multiple exchanges.

  This is the core function that other specialized functions use.
  Can be used for any exchange method.

  ## Parameters

  - `exchange_modules` - List of exchange modules
  - `function_name` - Function atom (e.g., `:fetch_ticker`, `:fetch_balance`)
  - `args` - List of arguments to pass to the function
  - `opts` - Options:
    - `:timeout` - Timeout per exchange in ms (default: #{@default_timeout_ms})

  ## Examples

      # Public endpoint
      iex> result = CCXT.Multi.parallel_call([CCXT.Bybit], :fetch_ticker, ["BTC/USDT"])
      iex> is_map(result)
      true

      # Authenticated endpoint (pass credentials as first arg)
      # result = CCXT.Multi.parallel_call([CCXT.Bybit], :fetch_balance, [credentials])

  """
  @spec parallel_call([module()], atom(), [term()], keyword()) :: result(term())
  def parallel_call(exchange_modules, function_name, args, opts \\ [])

  def parallel_call([], _function_name, _args, _opts), do: %{}

  def parallel_call(exchange_modules, function_name, args, opts) when is_list(exchange_modules) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    exchange_modules
    |> Task.async_stream(
      fn module -> call_exchange(module, function_name, args) end,
      timeout: timeout,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.zip(exchange_modules)
    |> Map.new(fn {result, module} ->
      {module, normalize_result(result)}
    end)
  end

  @doc """
  Returns only successful results, discarding errors.

  Unwraps `{:ok, value}` tuples to just values.

  ## Examples

      iex> results = %{CCXT.Bybit => {:ok, %{price: 100}}, CCXT.Binance => {:error, :timeout}}
      iex> CCXT.Multi.successes(results)
      %{CCXT.Bybit => %{price: 100}}

  """
  @spec successes(result(t)) :: %{module() => t} when t: var
  def successes(results) when is_map(results) do
    results
    |> Enum.filter(fn {_module, result} -> match?({:ok, _}, result) end)
    |> Map.new(fn {module, {:ok, value}} -> {module, value} end)
  end

  @doc """
  Returns only failed results.

  Unwraps `{:error, reason}` tuples to just reasons.

  ## Examples

      iex> results = %{CCXT.Bybit => {:ok, %{price: 100}}, CCXT.Binance => {:error, :timeout}}
      iex> CCXT.Multi.failures(results)
      %{CCXT.Binance => :timeout}

  """
  @spec failures(result(term())) :: %{module() => term()}
  def failures(results) when is_map(results) do
    results
    |> Enum.filter(fn {_module, result} -> match?({:error, _}, result) end)
    |> Map.new(fn {module, {:error, reason}} -> {module, reason} end)
  end

  @doc """
  Returns the count of successful results.

  ## Examples

      iex> results = %{CCXT.Bybit => {:ok, %{}}, CCXT.Binance => {:error, :timeout}}
      iex> CCXT.Multi.success_count(results)
      1

  """
  @spec success_count(result(term())) :: non_neg_integer()
  def success_count(results) when is_map(results) do
    Enum.count(results, fn {_module, result} -> match?({:ok, _}, result) end)
  end

  @doc """
  Returns the count of failed results.

  ## Examples

      iex> results = %{CCXT.Bybit => {:ok, %{}}, CCXT.Binance => {:error, :timeout}}
      iex> CCXT.Multi.failure_count(results)
      1

  """
  @spec failure_count(result(term())) :: non_neg_integer()
  def failure_count(results) when is_map(results) do
    Enum.count(results, fn {_module, result} -> match?({:error, _}, result) end)
  end

  @doc """
  Checks if all calls succeeded.

  ## Examples

      iex> results = %{CCXT.Bybit => {:ok, %{}}, CCXT.Binance => {:ok, %{}}}
      iex> CCXT.Multi.all_succeeded?(results)
      true

      iex> results = %{CCXT.Bybit => {:ok, %{}}, CCXT.Binance => {:error, :timeout}}
      iex> CCXT.Multi.all_succeeded?(results)
      false

  """
  @spec all_succeeded?(result(term())) :: boolean()
  def all_succeeded?(results) when is_map(results) do
    Enum.all?(results, fn {_module, result} -> match?({:ok, _}, result) end)
  end

  @doc """
  Checks if any call succeeded.

  ## Examples

      iex> results = %{CCXT.Bybit => {:ok, %{}}, CCXT.Binance => {:error, :timeout}}
      iex> CCXT.Multi.any_succeeded?(results)
      true

      iex> results = %{CCXT.Bybit => {:error, :a}, CCXT.Binance => {:error, :b}}
      iex> CCXT.Multi.any_succeeded?(results)
      false

  """
  @spec any_succeeded?(result(term())) :: boolean()
  def any_succeeded?(results) when is_map(results) do
    Enum.any?(results, fn {_module, result} -> match?({:ok, _}, result) end)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  @doc false
  # Calls the exchange function and wraps result in {:ok, _} | {:error, _}
  @spec call_exchange(module(), atom(), [term()]) :: {:ok, term()} | {:error, term()}
  defp call_exchange(module, function_name, args) do
    if function_exported?(module, function_name, length(args)) do
      apply(module, function_name, args)
    else
      {:error, {:function_not_exported, {module, function_name, length(args)}}}
    end
  rescue
    e -> {:error, {:exception, Exception.message(e)}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  @doc false
  # Normalizes Task.async_stream result to {:ok, _} | {:error, _}.
  # Functions returning {:ok, value} or {:error, reason} are passed through.
  # Functions returning raw values (not tuples) are auto-wrapped in {:ok, value}.
  @spec normalize_result({:ok, term()} | {:exit, term()}) :: {:ok, term()} | {:error, term()}
  defp normalize_result({:ok, {:ok, value}}), do: {:ok, value}
  defp normalize_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_result({:ok, other}), do: {:ok, other}
  defp normalize_result({:exit, :timeout}), do: {:error, :timeout}
  defp normalize_result({:exit, reason}), do: {:error, {:exit, reason}}
end
