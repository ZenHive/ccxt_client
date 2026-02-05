defmodule CCXT.Recovery do
  @moduledoc """
  Order recovery helpers for finding orders after timeout/error.

  Essential for market makers after timeout/error - did my order execute?
  Provides methods to search recent orders by time window, symbol, side,
  amount, and client order ID.

  ## Usage

      # Find recent orders after a timeout
      {:ok, orders} = Recovery.find_recent_orders(CCXT.Bybit, credentials,
        symbol: "BTC/USDT",
        since: System.os_time(:millisecond) - 60_000,
        side: :buy
      )

      # Find order by client_order_id (most reliable)
      {:ok, order} = Recovery.find_by_client_id(CCXT.Bybit, credentials,
        "my-order-123",
        symbol: "BTC/USDT"
      )

  ## Recovery Strategy

  1. **Best**: Use `client_order_id` when creating orders, then recover with `find_by_client_id/4`
  2. **Good**: Search by symbol + side + time window with `find_recent_orders/3`
  3. **Fallback**: Search by amount tolerance if you know the expected order size

  ## Notes

  - Always set `client_order_id` on order creation for reliable recovery
  - Time windows should account for network latency and exchange processing
  - Amount tolerance matching is fuzzy - use with caution
  """

  alias CCXT.Credentials

  @default_time_window_ms 60_000

  @typedoc "Order status filter"
  @type status_filter :: :open | :closed | :all

  @typedoc "Order side filter"
  @type side_filter :: :buy | :sell

  @doc """
  Find orders matching criteria within a time window.

  Essential for market makers after timeout/error - did my order execute?

  ## Parameters

  - `exchange_module` - Exchange module (e.g., `CCXT.Bybit`)
  - `credentials` - API credentials
  - `opts` - Filter options:
    - `:symbol` - Filter by symbol (required)
    - `:side` - Filter by side (`:buy` or `:sell`)
    - `:since` - Start time in ms timestamp or DateTime (default: 60s ago)
    - `:until` - End time in ms timestamp or DateTime (default: now)
    - `:status` - Filter by status (`:open`, `:closed`, `:all`) (default: `:all`)
    - `:amount` - Expected order amount for fuzzy matching
    - `:amount_tolerance` - Match orders within X% of expected amount (default: 0.01 = 1%)

  ## Examples

      # Find recent buy orders for BTC/USDT
      {:ok, orders} = CCXT.Recovery.find_recent_orders(CCXT.Bybit, credentials,
        symbol: "BTC/USDT",
        side: :buy,
        since: System.os_time(:millisecond) - 60_000
      )

      # Find orders matching expected amount (within 1%)
      {:ok, orders} = CCXT.Recovery.find_recent_orders(CCXT.Bybit, credentials,
        symbol: "BTC/USDT",
        amount: 0.5,
        amount_tolerance: 0.01
      )

  """
  @spec find_recent_orders(module(), Credentials.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def find_recent_orders(exchange_module, credentials, opts \\ []) do
    symbol = Keyword.fetch!(opts, :symbol)
    side = Keyword.get(opts, :side)
    status = Keyword.get(opts, :status, :all)
    since = normalize_timestamp(Keyword.get(opts, :since, default_since()))
    until_time = normalize_timestamp(Keyword.get(opts, :until, System.os_time(:millisecond)))
    amount = Keyword.get(opts, :amount)
    amount_tolerance = Keyword.get(opts, :amount_tolerance, 0.01)

    with {:ok, orders} <- fetch_orders_by_status(exchange_module, credentials, symbol, status, since) do
      filtered =
        orders
        |> filter_by_time(since, until_time)
        |> filter_by_side(side)
        |> filter_by_amount(amount, amount_tolerance)

      {:ok, filtered}
    end
  end

  @doc """
  Check if an order with given client_order_id exists.

  Most reliable recovery method if you set client_order_id on create.
  Exchange support varies - some exchanges require symbol, others don't.

  ## Parameters

  - `exchange_module` - Exchange module (e.g., `CCXT.Bybit`)
  - `credentials` - API credentials
  - `client_order_id` - The client order ID you set when creating the order
  - `opts` - Options:
    - `:symbol` - Symbol to search (may be required by some exchanges)
    - `:since` - Start time to limit search (optional)

  ## Examples

      # Find order by client ID
      {:ok, order} = CCXT.Recovery.find_by_client_id(CCXT.Bybit, credentials,
        "my-order-123",
        symbol: "BTC/USDT"
      )

      # Handle all possible outcomes
      case CCXT.Recovery.find_by_client_id(CCXT.Bybit, credentials, "my-order-123") do
        {:ok, order} -> Logger.info("Order found: \#{order["status"]}")
        {:error, :not_found} -> Logger.warning("Order not found")
        {:error, reason} -> Logger.error("Recovery failed: \#{inspect(reason)}")
      end

  """
  @spec find_by_client_id(module(), Credentials.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, :not_found | term()}
  def find_by_client_id(exchange_module, credentials, client_order_id, opts \\ []) do
    symbol = Keyword.get(opts, :symbol)
    since = normalize_timestamp(Keyword.get(opts, :since, default_since()))

    # First try fetch_order if exchange supports fetching by client ID
    # Fall back to searching recent orders
    case try_fetch_by_client_id(exchange_module, credentials, client_order_id, symbol) do
      {:ok, order} ->
        {:ok, order}

      {:error, :not_supported} ->
        # Fall back to searching through recent orders
        search_orders_for_client_id(exchange_module, credentials, client_order_id, symbol, since)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  @doc false
  @spec default_since() :: integer()
  defp default_since do
    System.os_time(:millisecond) - @default_time_window_ms
  end

  @doc false
  @spec normalize_timestamp(integer() | DateTime.t() | nil) :: integer()
  defp normalize_timestamp(nil), do: default_since()
  defp normalize_timestamp(ts) when is_integer(ts), do: ts

  defp normalize_timestamp(%DateTime{} = dt) do
    DateTime.to_unix(dt, :millisecond)
  end

  @doc false
  @spec fetch_orders_by_status(module(), Credentials.t(), String.t(), status_filter(), integer()) ::
          {:ok, [map()]} | {:error, term()}
  defp fetch_orders_by_status(exchange_module, credentials, symbol, status, since) do
    case status do
      :open ->
        call_if_exported(exchange_module, :fetch_open_orders, [credentials, symbol, since: since])

      :closed ->
        call_if_exported(exchange_module, :fetch_closed_orders, [credentials, symbol, since: since])

      :all ->
        # Try fetch_orders first, fall back to combining open + closed
        case call_if_exported(exchange_module, :fetch_orders, [credentials, symbol, since: since]) do
          {:ok, orders} ->
            {:ok, orders}

          {:error, {:function_not_exported, _}} ->
            combine_open_and_closed(exchange_module, credentials, symbol, since)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc false
  @spec combine_open_and_closed(module(), Credentials.t(), String.t(), integer()) ::
          {:ok, [map()]} | {:error, term()}
  defp combine_open_and_closed(exchange_module, credentials, symbol, since) do
    with {:ok, open} <-
           call_if_exported(exchange_module, :fetch_open_orders, [credentials, symbol, since: since]),
         {:ok, closed} <-
           call_if_exported(exchange_module, :fetch_closed_orders, [credentials, symbol, since: since]) do
      {:ok, open ++ closed}
    end
  end

  @doc false
  @spec call_if_exported(module(), atom(), list()) :: {:ok, term()} | {:error, term()}
  defp call_if_exported(module, function, args) do
    if function_exported?(module, function, length(args)) do
      apply(module, function, args)
    else
      {:error, {:function_not_exported, {module, function, length(args)}}}
    end
  rescue
    e -> {:error, {:exception, Exception.message(e)}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  @doc false
  @spec filter_by_time([map()], integer(), integer()) :: [map()]
  defp filter_by_time(orders, since, until_time) do
    Enum.filter(orders, fn order ->
      timestamp = get_order_timestamp(order)
      timestamp >= since and timestamp <= until_time
    end)
  end

  @doc false
  @spec get_order_timestamp(map()) :: integer()
  defp get_order_timestamp(order) do
    # Orders may have timestamp as integer or DateTime
    case Map.get(order, "timestamp") || Map.get(order, :timestamp) do
      nil -> 0
      ts when is_integer(ts) -> ts
      %DateTime{} = dt -> DateTime.to_unix(dt, :millisecond)
      _ -> 0
    end
  end

  @doc false
  @spec filter_by_side([map()], side_filter() | nil) :: [map()]
  defp filter_by_side(orders, nil), do: orders

  defp filter_by_side(orders, side) do
    side_string = Atom.to_string(side)

    Enum.filter(orders, fn order ->
      order_side = Map.get(order, "side") || Map.get(order, :side)
      order_side == side_string or order_side == side
    end)
  end

  @doc false
  @spec filter_by_amount([map()], number() | nil, number()) :: [map()]
  defp filter_by_amount(orders, nil, _tolerance), do: orders

  defp filter_by_amount(orders, expected_amount, tolerance) do
    min_amount = expected_amount * (1 - tolerance)
    max_amount = expected_amount * (1 + tolerance)

    Enum.filter(orders, fn order ->
      amount = get_order_amount(order)
      amount >= min_amount and amount <= max_amount
    end)
  end

  @doc false
  @spec get_order_amount(map()) :: number()
  defp get_order_amount(order) do
    case Map.get(order, "amount") || Map.get(order, :amount) do
      nil -> 0
      amount when is_number(amount) -> amount
      _ -> 0
    end
  end

  @doc false
  @spec try_fetch_by_client_id(module(), Credentials.t(), String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, :not_supported | term()}
  defp try_fetch_by_client_id(exchange_module, credentials, client_order_id, symbol) do
    # Some exchanges support fetching order directly by client ID
    # This is exchange-specific - most use fetch_order with the client ID
    cond do
      function_exported?(exchange_module, :fetch_order_by_client_id, 3) ->
        exchange_module.fetch_order_by_client_id(credentials, client_order_id, symbol)

      function_exported?(exchange_module, :fetch_order, 3) ->
        # Try using client_order_id as the order ID (some exchanges support this)
        case exchange_module.fetch_order(credentials, client_order_id, symbol) do
          {:ok, order} -> {:ok, order}
          {:error, _} -> {:error, :not_supported}
        end

      true ->
        {:error, :not_supported}
    end
  rescue
    _ -> {:error, :not_supported}
  end

  @doc false
  @spec search_orders_for_client_id(module(), Credentials.t(), String.t(), String.t() | nil, integer()) ::
          {:ok, map()} | {:error, :not_found | term()}
  defp search_orders_for_client_id(_exchange_module, _credentials, _client_order_id, nil, _since) do
    {:error, {:symbol_required, "Symbol is required to search orders on this exchange"}}
  end

  defp search_orders_for_client_id(exchange_module, credentials, client_order_id, symbol, since) do
    search_opts = [symbol: symbol, since: since, status: :all]

    with {:ok, orders} <- find_recent_orders(exchange_module, credentials, search_opts) do
      case find_order_with_client_id(orders, client_order_id) do
        nil -> {:error, :not_found}
        order -> {:ok, order}
      end
    end
  end

  @doc false
  @spec find_order_with_client_id([map()], String.t()) :: map() | nil
  defp find_order_with_client_id(orders, client_order_id) do
    Enum.find(orders, fn order ->
      order_client_id =
        Map.get(order, "clientOrderId") ||
          Map.get(order, :clientOrderId) ||
          Map.get(order, "client_order_id") ||
          Map.get(order, :client_order_id)

      order_client_id == client_order_id
    end)
  end
end
