defmodule CCXT.Emulation do
  @moduledoc """
  Runtime emulation dispatch for CCXT unified methods.

  Uses extracted emulated method metadata to decide when a method should be
  derived at runtime instead of issuing HTTP or WebSocket requests.
  """

  alias CCXT.Error
  alias CCXT.Extract.EmulatedMethods
  alias CCXT.Spec

  @type scope :: :rest | :ws
  @type entry :: map()
  @type dispatch_result :: :passthrough | {:ok, term()} | {:error, Error.t()}

  @cache_key {__MODULE__, :index}
  @default_currency_precision 1.0e-8
  @zero 0

  @doc "Returns true if a method is emulated for the exchange and scope."
  @spec emulated?(Spec.t(), atom(), scope()) :: boolean()
  def emulated?(%Spec{} = spec, method, scope) when is_atom(method) do
    entry(spec, method, scope) != nil
  end

  @doc "Returns emulated metadata for a method (or nil if not emulated)."
  @spec entry(Spec.t(), atom(), scope()) :: entry() | nil
  def entry(%Spec{} = spec, method, scope) when is_atom(method) do
    normalized_scope = normalize_scope(scope)
    exchange_id = spec.id

    load_index()
    |> Map.get(exchange_id, %{})
    |> Map.get(normalized_scope, %{})
    |> Map.get(method)
  end

  @doc """
  Dispatches emulated method calls.

  Returns `:passthrough` when the method is not emulated for this exchange,
  `{:ok, result}` when emulation succeeds, or `{:error, reason}` on failure.
  """
  @spec dispatch(Spec.t(), atom(), scope(), map()) :: dispatch_result()
  def dispatch(%Spec{} = spec, method, scope, context) when is_atom(method) and is_map(context) do
    case entry(spec, method, scope) do
      nil -> :passthrough
      entry -> dispatch_entry(spec, method, entry, context)
    end
  end

  @doc "Reloads emulation index (bypasses cache)."
  @spec reload!() :: map()
  def reload! do
    index = build_index()
    :persistent_term.put(@cache_key, index)
    index
  end

  # ===========================================================================
  # Index Building
  # ===========================================================================

  @doc false
  # Loads the emulation index from persistent_term or builds it from JSON.
  @spec load_index() :: map()
  defp load_index do
    case :persistent_term.get(@cache_key, :missing) do
      :missing ->
        index = build_index()
        :persistent_term.put(@cache_key, index)
        index

      index ->
        index
    end
  end

  @doc false
  # Builds a lookup table: exchange_id -> scope -> method_atom -> entry.
  @spec build_index() :: map()
  defp build_index do
    EmulatedMethods.load()
    |> Map.get("emulated_methods", %{})
    |> Enum.reduce(%{}, fn {exchange_id, entries}, acc ->
      Map.put(acc, exchange_id, build_scoped_index(entries))
    end)
  end

  @doc false
  # Groups emulated entries by scope and method.
  @spec build_scoped_index([map()]) :: map()
  defp build_scoped_index(entries) do
    Enum.reduce(entries, %{rest: %{}, ws: %{}}, fn entry, acc ->
      index_entry(acc, entry)
    end)
  end

  @doc false
  # Indexes a single emulated entry by scope and method.
  @spec index_entry(map(), map()) :: map()
  defp index_entry(acc, entry) do
    scope = normalize_scope(Map.get(entry, "scope"))
    method = to_method_atom(Map.get(entry, "name"))

    if scope in [:rest, :ws] and is_atom(method) do
      Map.update!(acc, scope, fn scope_map -> Map.put(scope_map, method, entry) end)
    else
      acc
    end
  end

  # ===========================================================================
  # Dispatch Routing
  # ===========================================================================

  @doc false
  # Dispatches an emulated entry to its strategy handler - missing exchange_module case.
  @spec dispatch_entry(Spec.t(), atom(), map(), map()) :: dispatch_result()
  defp dispatch_entry(spec, _method, _entry, %{exchange_module: nil}) do
    {:error,
     Error.invalid_parameters(
       message: "Emulation context missing exchange module",
       exchange: exchange_atom(spec)
     )}
  end

  defp dispatch_entry(spec, _method, _entry, context) when not is_map_key(context, :exchange_module) do
    {:error,
     Error.invalid_parameters(
       message: "Emulation context missing exchange module",
       exchange: exchange_atom(spec)
     )}
  end

  defp dispatch_entry(spec, method, entry, context) do
    %{exchange_module: exchange_module} = context
    params = Map.get(context, :params, %{})
    opts = Map.get(context, :opts, [])
    credentials = Map.get(context, :credentials)

    dispatch_method(spec, exchange_module, method, entry, params, opts, credentials)
  end

  # Dispatch map for routing methods to their handlers.
  # Using a map lookup instead of a large case statement reduces cyclomatic complexity.
  @dispatch_handlers %{
    fetch_bids_asks: :handle_fetch_bids_asks,
    fetch_ticker: :handle_fetch_ticker,
    fetch_trading_fee: :handle_fetch_trading_fee,
    fetch_transaction_fee: :handle_fetch_transaction_fee,
    fetch_deposit_withdraw_fee: :handle_fetch_deposit_withdraw_fee,
    fetch_deposit_address: :handle_fetch_deposit_address,
    fetch_currencies: :handle_fetch_currencies,
    fetch_open_orders: :handle_fetch_open_orders,
    fetch_closed_orders: :handle_fetch_closed_orders,
    fetch_canceled_orders: :handle_fetch_canceled_orders,
    fetch_canceled_and_closed_orders: :handle_fetch_canceled_and_closed_orders,
    fetch_order: :handle_fetch_order,
    fetch_order_trades: :handle_fetch_order_trades,
    fetch_my_trades: :handle_fetch_my_trades,
    fetch_position: :handle_fetch_position,
    fetch_position_history: :handle_fetch_position_history,
    fetch_leverage: :handle_fetch_leverage,
    fetch_margin_mode: :handle_fetch_margin_mode,
    fetch_market_leverage_tiers: :handle_fetch_market_leverage_tiers,
    fetch_funding_rate: :handle_fetch_funding_rate,
    fetch_funding_interval: :handle_fetch_funding_interval,
    fetch_isolated_borrow_rate: :handle_fetch_isolated_borrow_rate,
    fetch_trading_limits: :handle_fetch_trading_limits,
    fetch_transactions: :handle_fetch_transactions,
    fetch_deposits_withdrawals: :handle_fetch_deposits_withdrawals
  }

  @doc "Returns the set of emulated methods with runtime handlers implemented."
  @spec implemented_methods() :: MapSet.t(atom())
  def implemented_methods do
    MapSet.new(Map.keys(@dispatch_handlers))
  end

  @doc false
  # Routes emulated methods to their concrete strategy implementations via dispatch map.
  @spec dispatch_method(Spec.t(), module(), atom(), map(), map(), keyword(), term()) ::
          dispatch_result()
  defp dispatch_method(spec, exchange_module, method, entry, params, opts, credentials) do
    case Map.fetch(@dispatch_handlers, method) do
      {:ok, handler} ->
        apply(__MODULE__, handler, [spec, exchange_module, params, opts, credentials])

      :error ->
        not_supported_entry(spec, method, entry)
    end
  end

  @doc false
  # Returns a standardized not_supported error for unhandled emulation entries.
  @spec not_supported_entry(Spec.t(), atom(), map()) :: {:error, Error.t()}
  defp not_supported_entry(spec, method, entry) do
    exchange = exchange_atom(spec)
    method_name = Atom.to_string(method)
    reason_suffix = emulation_reason_suffix(entry)

    {:error,
     Error.not_supported(
       message: "Emulated method not implemented: #{method_name}#{reason_suffix}",
       exchange: exchange
     )}
  end

  # ===========================================================================
  # Strategy Handlers - Simple Delegations
  # ===========================================================================

  @doc false
  # Emulates fetchBidsAsks by delegating to fetchTickers.
  @spec handle_fetch_bids_asks(Spec.t(), module(), map(), keyword(), term()) :: dispatch_result()
  def handle_fetch_bids_asks(spec, exchange_module, params, opts, credentials) do
    symbols =
      normalize_symbols(extract_param(params, :symbols) || extract_param(params, :symbol))

    call_method(spec, exchange_module, :fetch_tickers, [symbols], opts, credentials)
  end

  @doc false
  # Emulates fetchCurrencies by deriving currencies from fetchMarkets output.
  @spec handle_fetch_currencies(Spec.t(), module(), map(), keyword(), term()) :: dispatch_result()
  def handle_fetch_currencies(spec, exchange_module, _params, opts, credentials) do
    with {:ok, markets} <- call_method(spec, exchange_module, :fetch_markets, [], opts, credentials) do
      {:ok, derive_currencies_from_markets(markets)}
    end
  end

  @doc false
  # Emulates fetchTradingLimits by deriving limits from fetchMarkets output.
  @spec handle_fetch_trading_limits(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_trading_limits(spec, exchange_module, params, opts, credentials) do
    symbols = normalize_symbols(extract_param(params, :symbols))

    with {:ok, markets} <- call_method(spec, exchange_module, :fetch_markets, [], opts, credentials) do
      {:ok, derive_trading_limits(markets, symbols)}
    end
  end

  @doc false
  # Emulates fetchTransactions by delegating to fetchDepositsWithdrawals.
  @spec handle_fetch_transactions(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_transactions(spec, exchange_module, params, opts, credentials) do
    handle_fetch_deposits_withdrawals(spec, exchange_module, params, opts, credentials)
  end

  @doc false
  # Emulates fetchTradingFee by selecting a symbol entry from fetchTradingFees.
  @spec handle_fetch_trading_fee(Spec.t(), module(), map(), keyword(), term()) :: dispatch_result()
  def handle_fetch_trading_fee(spec, exchange_module, params, opts, credentials) do
    symbol = extract_param(params, :symbol)

    with {:ok, fees} <- call_method(spec, exchange_module, :fetch_trading_fees, [], opts, credentials) do
      {:ok, pick_symbol_entry(fees, symbol)}
    end
  end

  @doc false
  # Emulates fetchPosition by selecting a single position from fetchPositions.
  @spec handle_fetch_position(Spec.t(), module(), map(), keyword(), term()) :: dispatch_result()
  def handle_fetch_position(spec, exchange_module, params, opts, credentials) do
    symbol = extract_param(params, :symbol)
    symbols = normalize_symbols(symbol)

    with {:ok, positions} <- call_method(spec, exchange_module, :fetch_positions, [symbols], opts, credentials) do
      {:ok, pick_symbol_entry(positions, symbol)}
    end
  end

  @doc false
  # Emulates fetchPositionHistory by delegating to fetchPositionsHistory.
  @spec handle_fetch_position_history(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_position_history(spec, exchange_module, params, opts, credentials) do
    symbol = extract_param(params, :symbol)
    since = extract_param(params, :since)
    limit = extract_param(params, :limit)
    symbols = normalize_symbols(symbol)

    call_method(spec, exchange_module, :fetch_positions_history, [symbols, since, limit], opts, credentials)
  end

  # ===========================================================================
  # Strategy Handlers - Require Symbol (early return pattern)
  # ===========================================================================

  @doc false
  # Emulates fetchTicker by selecting a single ticker from fetchTickers output.
  @spec handle_fetch_ticker(Spec.t(), module(), map(), keyword(), term()) :: dispatch_result()
  def handle_fetch_ticker(spec, exchange_module, params, opts, credentials) do
    symbol = extract_param(params, :symbol)

    if is_nil(symbol) do
      require_symbol_error(spec, "fetch_ticker")
    else
      with {:ok, tickers} <- call_method(spec, exchange_module, :fetch_tickers, [[symbol]], opts, credentials) do
        require_symbol_result(tickers, symbol, spec, "fetchTickers() could not find a ticker for")
      end
    end
  end

  @doc false
  # Emulates fetchTransactionFee by delegating to fetchTransactionFees.
  @spec handle_fetch_transaction_fee(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_transaction_fee(spec, exchange_module, params, opts, credentials) do
    code = extract_param(params, :code)

    if is_nil(code) do
      require_code_error(spec, "fetch_transaction_fee")
    else
      call_method(spec, exchange_module, :fetch_transaction_fees, [[code]], opts, credentials)
    end
  end

  @doc false
  # Emulates fetchDepositWithdrawFee by selecting a code entry from fetchDepositWithdrawFees.
  @spec handle_fetch_deposit_withdraw_fee(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_deposit_withdraw_fee(spec, exchange_module, params, opts, credentials) do
    code = extract_param(params, :code)

    if is_nil(code) do
      require_code_error(spec, "fetch_deposit_withdraw_fee")
    else
      with {:ok, fees} <-
             call_method(
               spec,
               exchange_module,
               :fetch_deposit_withdraw_fees,
               [[code]],
               opts,
               credentials
             ) do
        {:ok, pick_code_entry(fees, code)}
      end
    end
  end

  @doc false
  # Emulates fetchDepositAddress using fetchDepositAddresses or fetchDepositAddressesByNetwork.
  @spec handle_fetch_deposit_address(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_deposit_address(spec, exchange_module, params, opts, credentials) do
    code = extract_param(params, :code)

    if is_nil(code) do
      require_code_error(spec, "fetch_deposit_address")
    else
      do_fetch_deposit_address(spec, exchange_module, code, params, opts, credentials)
    end
  end

  @doc false
  # Emulates fetchLeverage by selecting a single symbol from fetchLeverages.
  @spec handle_fetch_leverage(Spec.t(), module(), map(), keyword(), term()) :: dispatch_result()
  def handle_fetch_leverage(spec, exchange_module, params, opts, credentials) do
    symbol = extract_param(params, :symbol)

    if is_nil(symbol) do
      require_symbol_error(spec, "fetch_leverage")
    else
      with {:ok, leverages} <-
             call_method(
               spec,
               exchange_module,
               :fetch_leverages,
               [[symbol]],
               opts,
               credentials
             ) do
        {:ok, pick_symbol_entry(leverages, symbol)}
      end
    end
  end

  @doc false
  # Emulates fetchMarginMode by selecting a single symbol from fetchMarginModes.
  @spec handle_fetch_margin_mode(Spec.t(), module(), map(), keyword(), term()) :: dispatch_result()
  def handle_fetch_margin_mode(spec, exchange_module, params, opts, credentials) do
    symbol = extract_param(params, :symbol)

    if is_nil(symbol) do
      require_symbol_error(spec, "fetch_margin_mode")
    else
      with {:ok, modes} <-
             call_method(
               spec,
               exchange_module,
               :fetch_margin_modes,
               [[symbol]],
               opts,
               credentials
             ) do
        {:ok, pick_symbol_entry(modes, symbol)}
      end
    end
  end

  @doc false
  # Emulates fetchMarketLeverageTiers by selecting a single symbol from fetchLeverageTiers.
  @spec handle_fetch_market_leverage_tiers(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_market_leverage_tiers(spec, exchange_module, params, opts, credentials) do
    symbol = extract_param(params, :symbol)

    if is_nil(symbol) do
      require_symbol_error(spec, "fetch_market_leverage_tiers")
    else
      with {:ok, _market} <- ensure_contract_market(spec, exchange_module, symbol, opts, credentials),
           {:ok, tiers} <-
             call_method(
               spec,
               exchange_module,
               :fetch_leverage_tiers,
               [[symbol]],
               opts,
               credentials
             ) do
        {:ok, pick_symbol_entry(tiers, symbol)}
      end
    end
  end

  @doc false
  # Emulates fetchFundingRate by selecting a single symbol from fetchFundingRates.
  @spec handle_fetch_funding_rate(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_funding_rate(spec, exchange_module, params, opts, credentials) do
    symbol = extract_param(params, :symbol)

    if is_nil(symbol) do
      require_symbol_error(spec, "fetch_funding_rate")
    else
      with {:ok, _market} <- ensure_contract_market(spec, exchange_module, symbol, opts, credentials),
           {:ok, rates} <-
             call_method(
               spec,
               exchange_module,
               :fetch_funding_rates,
               [[symbol]],
               opts,
               credentials
             ) do
        require_symbol_result(rates, symbol, spec, "fetchFundingRate() returned no data for")
      end
    end
  end

  @doc false
  # Emulates fetchFundingInterval by selecting a single symbol from fetchFundingIntervals.
  @spec handle_fetch_funding_interval(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_funding_interval(spec, exchange_module, params, opts, credentials) do
    symbol = extract_param(params, :symbol)

    if is_nil(symbol) do
      require_symbol_error(spec, "fetch_funding_interval")
    else
      with {:ok, _market} <- ensure_contract_market(spec, exchange_module, symbol, opts, credentials),
           {:ok, rates} <-
             call_method(
               spec,
               exchange_module,
               :fetch_funding_intervals,
               [[symbol]],
               opts,
               credentials
             ) do
        require_symbol_result(rates, symbol, spec, "fetchFundingInterval() returned no data for")
      end
    end
  end

  @doc false
  # Emulates fetchIsolatedBorrowRate by selecting a symbol from fetchIsolatedBorrowRates.
  @spec handle_fetch_isolated_borrow_rate(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_isolated_borrow_rate(spec, exchange_module, params, opts, credentials) do
    symbol = extract_param(params, :symbol)

    if is_nil(symbol) do
      require_symbol_error(spec, "fetch_isolated_borrow_rate")
    else
      do_fetch_isolated_borrow_rate(spec, exchange_module, symbol, opts, credentials)
    end
  end

  defp do_fetch_isolated_borrow_rate(spec, exchange_module, symbol, opts, credentials) do
    with {:ok, rates} <-
           call_method(spec, exchange_module, :fetch_isolated_borrow_rates, [], opts, credentials) do
      require_borrow_rate_result(rates, symbol, spec)
    end
  end

  defp require_borrow_rate_result(rates, symbol, spec) do
    case pick_symbol_entry(rates, symbol) do
      nil ->
        {:error,
         Error.exchange_error(
           "fetchIsolatedBorrowRate() could not find borrow rate for #{symbol}",
           exchange: exchange_atom(spec)
         )}

      rate ->
        {:ok, rate}
    end
  end

  # ===========================================================================
  # Strategy Handlers - Order Filtering
  # ===========================================================================

  @doc false
  # Emulates fetchOpenOrders by filtering fetchOrders.
  @spec handle_fetch_open_orders(Spec.t(), module(), map(), keyword(), term()) :: dispatch_result()
  def handle_fetch_open_orders(spec, exchange_module, params, opts, credentials) do
    handle_fetch_filtered_orders(spec, exchange_module, params, opts, credentials, :open)
  end

  @doc false
  # Emulates fetchClosedOrders by filtering fetchOrders.
  @spec handle_fetch_closed_orders(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_closed_orders(spec, exchange_module, params, opts, credentials) do
    handle_fetch_filtered_orders(spec, exchange_module, params, opts, credentials, :closed)
  end

  @doc false
  # Emulates fetchCanceledOrders by filtering fetchOrders.
  @spec handle_fetch_canceled_orders(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_canceled_orders(spec, exchange_module, params, opts, credentials) do
    handle_fetch_filtered_orders(spec, exchange_module, params, opts, credentials, :canceled)
  end

  @doc false
  # Common implementation for order status filtering.
  @spec handle_fetch_filtered_orders(Spec.t(), module(), map(), keyword(), term(), atom()) ::
          dispatch_result()
  defp handle_fetch_filtered_orders(spec, exchange_module, params, opts, credentials, status) do
    symbol = extract_param(params, :symbol)
    since = extract_param(params, :since)
    limit = extract_param(params, :limit)
    args = [symbol, since, limit]

    with {:ok, orders} <- call_method(spec, exchange_module, :fetch_orders, args, opts, credentials) do
      filtered =
        orders
        |> filter_by_status(status)
        |> filter_by_since_limit(since, limit, :timestamp)

      {:ok, filtered}
    end
  end

  @doc false
  # Emulates fetchCanceledAndClosedOrders by merging filtered fetchOrders results.
  @spec handle_fetch_canceled_and_closed_orders(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_canceled_and_closed_orders(spec, exchange_module, params, opts, credentials) do
    symbol = extract_param(params, :symbol)
    since = extract_param(params, :since)
    limit = extract_param(params, :limit)
    args = [symbol, since, limit]

    with {:ok, orders} <- call_method(spec, exchange_module, :fetch_orders, args, opts, credentials) do
      canceled = filter_by_status(orders, :canceled)
      closed = filter_by_status(orders, :closed)
      merged = canceled ++ closed
      sorted = sort_by(merged, :timestamp, false)
      {:ok, filter_by_since_limit(sorted, since, limit, :timestamp)}
    end
  end

  @doc false
  # Emulates fetchOrder by searching orders from supported order list methods.
  @spec handle_fetch_order(Spec.t(), module(), map(), keyword(), term()) :: dispatch_result()
  def handle_fetch_order(spec, exchange_module, params, opts, credentials) do
    id = extract_param(params, :id)

    if is_nil(id) do
      require_id_error(spec, "fetch_order")
    else
      symbol = extract_param(params, :symbol)
      since = extract_param(params, :since)
      limit = extract_param(params, :limit)
      do_fetch_order(spec, exchange_module, id, symbol, since, limit, opts, credentials)
    end
  end

  defp do_fetch_order(spec, exchange_module, id, symbol, since, limit, opts, credentials) do
    with {:ok, orders} <-
           fetch_orders_for_lookup(spec, exchange_module, symbol, since, limit, opts, credentials) do
      require_order_result(orders, id, spec)
    end
  end

  defp require_order_result(orders, id, spec) do
    case pick_order_by_id(orders, id) do
      nil ->
        {:error,
         Error.order_not_found(
           message: "No order found with id #{id}",
           exchange: exchange_atom(spec)
         )}

      order ->
        {:ok, order}
    end
  end

  @doc false
  # Emulates fetchOrderTrades by filtering fetchMyTrades output.
  @spec handle_fetch_order_trades(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_order_trades(spec, exchange_module, params, opts, credentials) do
    id = extract_param(params, :id)

    if is_nil(id) do
      require_id_error(spec, "fetch_order_trades")
    else
      do_fetch_order_trades(spec, exchange_module, params, opts, credentials, id)
    end
  end

  defp do_fetch_order_trades(spec, exchange_module, params, opts, credentials, id) do
    symbol = extract_param(params, :symbol)
    since = extract_param(params, :since)
    limit = extract_param(params, :limit)

    case trades_from_params(params) do
      {:trades, trades} ->
        filter_trades_by_order(trades, id, since, limit)

      {:trade_ids, trade_ids} ->
        fetch_and_filter_by_trade_ids(
          spec,
          exchange_module,
          symbol,
          since,
          limit,
          opts,
          credentials,
          trade_ids
        )

      :no_trades_param ->
        fetch_and_filter_by_order_id(
          spec,
          exchange_module,
          symbol,
          since,
          limit,
          opts,
          credentials,
          id
        )
    end
  end

  defp filter_trades_by_order(trades, id, since, limit) do
    filtered =
      trades
      |> filter_by_order_id(id)
      |> filter_by_since_limit(since, limit, :timestamp)

    {:ok, filtered}
  end

  defp fetch_and_filter_by_trade_ids(spec, module, symbol, since, limit, opts, creds, trade_ids) do
    args = [symbol, since, limit]

    with {:ok, trades} <- call_method(spec, module, :fetch_my_trades, args, opts, creds) do
      filtered =
        trades
        |> filter_by_trade_ids(trade_ids)
        |> filter_by_since_limit(since, limit, :timestamp)

      {:ok, filtered}
    end
  end

  defp fetch_and_filter_by_order_id(spec, module, symbol, since, limit, opts, creds, id) do
    args = [symbol, since, limit]

    with {:ok, trades} <- call_method(spec, module, :fetch_my_trades, args, opts, creds) do
      filtered =
        trades
        |> filter_by_order_id(id)
        |> filter_by_since_limit(since, limit, :timestamp)

      {:ok, filtered}
    end
  end

  @doc false
  # Emulates fetchMyTrades by extracting trades from fetchOrders output.
  @spec handle_fetch_my_trades(Spec.t(), module(), map(), keyword(), term()) :: dispatch_result()
  def handle_fetch_my_trades(spec, exchange_module, params, opts, credentials) do
    symbol = extract_param(params, :symbol)
    since = extract_param(params, :since)
    limit = extract_param(params, :limit)
    args = [symbol, since, limit]

    with {:ok, orders} <- call_method(spec, exchange_module, :fetch_orders, args, opts, credentials) do
      trades =
        orders
        |> orders_to_trades()
        |> filter_by_symbol(symbol)
        |> filter_by_since_limit(since, limit, :timestamp)

      {:ok, trades}
    end
  end

  # ===========================================================================
  # Strategy Handlers - Deposits/Withdrawals
  # ===========================================================================

  @doc false
  # Emulates fetchDepositsWithdrawals via deposits+withdrawals or ledger fallback.
  @spec handle_fetch_deposits_withdrawals(Spec.t(), module(), map(), keyword(), term()) ::
          dispatch_result()
  def handle_fetch_deposits_withdrawals(spec, exchange_module, params, opts, credentials) do
    code = extract_param(params, :code)
    since = extract_param(params, :since)
    limit = extract_param(params, :limit)

    cond do
      endpoint_available?(spec, :fetch_deposits) or endpoint_available?(spec, :fetch_withdrawals) ->
        fetch_deposits_and_withdrawals(spec, exchange_module, code, since, limit, opts, credentials)

      endpoint_available?(spec, :fetch_ledger) ->
        fetch_transactions_from_ledger(spec, exchange_module, code, since, limit, opts, credentials)

      true ->
        {:error,
         Error.not_supported(
           message: "fetchDepositsWithdrawals() is not supported yet",
           exchange: exchange_atom(spec)
         )}
    end
  end

  defp fetch_deposits_and_withdrawals(spec, module, code, since, limit, opts, creds) do
    args = [code, since, limit]

    with {:ok, deposits} <- call_optional_method(spec, module, :fetch_deposits, args, opts, creds),
         {:ok, withdrawals} <- call_optional_method(spec, module, :fetch_withdrawals, args, opts, creds) do
      combined = ensure_list(deposits) ++ ensure_list(withdrawals)
      {:ok, filter_by_since_limit(combined, since, limit, :timestamp)}
    end
  end

  defp fetch_transactions_from_ledger(spec, module, code, since, limit, opts, creds) do
    args = [code, since, limit]

    with {:ok, ledger} <- call_method(spec, module, :fetch_ledger, args, opts, creds) do
      filtered =
        ledger
        |> ensure_list()
        |> filter_ledger_transactions()
        |> filter_by_since_limit(since, limit, :timestamp)

      {:ok, filtered}
    end
  end

  @doc false
  # Performs fetchDepositAddress resolution based on available address methods.
  @spec do_fetch_deposit_address(Spec.t(), module(), String.t(), map(), keyword(), term()) ::
          dispatch_result()
  defp do_fetch_deposit_address(spec, exchange_module, code, params, opts, credentials) do
    cond do
      endpoint_available?(spec, :fetch_deposit_addresses) ->
        fetch_deposit_address_from_addresses(spec, exchange_module, code, opts, credentials)

      endpoint_available?(spec, :fetch_deposit_addresses_by_network) ->
        network = extract_param(params, :network)
        fetch_deposit_address_by_network(spec, exchange_module, code, network, opts, credentials)

      true ->
        {:error,
         Error.not_supported(
           message: "fetchDepositAddress() is not supported yet",
           exchange: exchange_atom(spec)
         )}
    end
  end

  defp fetch_deposit_address_from_addresses(spec, module, code, opts, creds) do
    with {:ok, addresses} <- call_method(spec, module, :fetch_deposit_addresses, [[code]], opts, creds) do
      case pick_code_entry(addresses, code) do
        nil -> deposit_address_not_found_error(spec, code)
        address -> {:ok, address}
      end
    end
  end

  defp fetch_deposit_address_by_network(spec, module, code, network, opts, creds) do
    cleaned_opts = drop_params(opts, [:network])

    with {:ok, address_map} <-
           call_method(
             spec,
             module,
             :fetch_deposit_addresses_by_network,
             [code],
             cleaned_opts,
             creds
           ) do
      case resolve_network_address(address_map, network) do
        nil -> deposit_address_not_found_error(spec, code)
        address -> {:ok, address}
      end
    end
  end

  defp deposit_address_not_found_error(spec, code) do
    {:error,
     Error.invalid_parameters(
       message: "fetchDepositAddress() could not find a deposit address for #{code}",
       exchange: exchange_atom(spec)
     )}
  end

  # ===========================================================================
  # Error Helpers (reduces nesting in handlers)
  # ===========================================================================

  defp require_symbol_error(spec, method_name) do
    {:error,
     Error.invalid_parameters(
       message: "#{method_name} requires a symbol argument",
       exchange: exchange_atom(spec)
     )}
  end

  defp require_code_error(spec, method_name) do
    {:error,
     Error.invalid_parameters(
       message: "#{method_name} requires a code argument",
       exchange: exchange_atom(spec)
     )}
  end

  defp require_id_error(spec, method_name) do
    {:error,
     Error.invalid_parameters(
       message: "#{method_name} requires an id argument",
       exchange: exchange_atom(spec)
     )}
  end

  defp require_symbol_result(entries, symbol, spec, error_prefix) do
    case pick_symbol_entry(entries, symbol) do
      nil ->
        {:error, Error.exchange_error("#{error_prefix} #{symbol}", exchange: exchange_atom(spec))}

      result ->
        {:ok, result}
    end
  end

  # ===========================================================================
  # Contract Market Validation
  # ===========================================================================

  @doc false
  # Ensures a market is a contract market before returning it.
  @spec ensure_contract_market(Spec.t(), module(), String.t() | nil, keyword(), term()) ::
          {:ok, map()} | {:error, Error.t()}
  defp ensure_contract_market(spec, _module, nil, _opts, _creds) do
    {:error,
     Error.invalid_parameters(
       message: "Method requires a symbol argument",
       exchange: exchange_atom(spec)
     )}
  end

  defp ensure_contract_market(spec, exchange_module, symbol, opts, credentials) do
    with {:ok, market} <- fetch_market(spec, exchange_module, symbol, opts, credentials),
         :ok <- validate_contract_market(market, spec) do
      {:ok, market}
    end
  end

  defp validate_contract_market(market, spec) do
    if truthy?(get_field(market, :contract)) do
      :ok
    else
      {:error,
       Error.invalid_parameters(
         message: "Method supports contract markets only",
         exchange: exchange_atom(spec)
       )}
    end
  end

  @doc false
  # Fetches a single market by symbol using fetchMarkets.
  @spec fetch_market(Spec.t(), module(), String.t(), keyword(), term()) ::
          {:ok, map()} | {:error, Error.t()}
  defp fetch_market(spec, exchange_module, symbol, opts, credentials) do
    with {:ok, markets} <- call_method(spec, exchange_module, :fetch_markets, [], opts, credentials) do
      case pick_symbol_entry(markets, symbol) do
        nil ->
          {:error,
           Error.invalid_parameters(
             message: "Unknown market symbol #{symbol}",
             exchange: exchange_atom(spec)
           )}

        market ->
          {:ok, market}
      end
    end
  end

  # ===========================================================================
  # Method Calling Infrastructure
  # ===========================================================================

  @doc false
  # Calls a unified method, injecting credentials when required by spec endpoints.
  @spec call_method(Spec.t(), module(), atom(), list(), keyword(), term()) :: dispatch_result()
  defp call_method(spec, exchange_module, method, args, opts, credentials) do
    with :ok <- validate_endpoint_available(spec, method),
         :ok <- validate_credentials_if_required(spec, method, credentials) do
      execute_method(exchange_module, method, args, opts, credentials, auth_required?(spec, method))
    end
  end

  defp validate_endpoint_available(spec, method) do
    if endpoint_available?(spec, method) do
      :ok
    else
      {:error,
       Error.not_supported(
         message: "#{method} is not supported by this exchange",
         exchange: exchange_atom(spec)
       )}
    end
  end

  defp validate_credentials_if_required(spec, method, credentials) do
    if auth_required?(spec, method) and is_nil(credentials) do
      {:error,
       Error.invalid_credentials(
         message: "Credentials required for #{method}",
         exchange: exchange_atom(spec)
       )}
    else
      :ok
    end
  end

  defp execute_method(module, method, args, opts, credentials, true = _auth_required) do
    apply(module, method, [credentials | args] ++ [opts])
  end

  defp execute_method(module, method, args, opts, _credentials, false = _auth_required) do
    apply(module, method, args ++ [opts])
  end

  @doc false
  # Calls a method if available, otherwise returns {:ok, []}.
  @spec call_optional_method(Spec.t(), module(), atom(), list(), keyword(), term()) ::
          {:ok, list()} | {:error, Error.t()}
  defp call_optional_method(spec, exchange_module, method, args, opts, credentials) do
    if endpoint_available?(spec, method) do
      case call_method(spec, exchange_module, method, args, opts, credentials) do
        {:ok, result} -> {:ok, ensure_list(result)}
        {:error, _} = error -> error
      end
    else
      {:ok, []}
    end
  end

  @doc false
  # Checks whether an endpoint exists for the method in the spec.
  @spec endpoint_available?(Spec.t(), atom()) :: boolean()
  defp endpoint_available?(%Spec{endpoints: endpoints}, method) do
    Enum.any?(endpoints, fn endpoint -> endpoint[:name] == method end)
  end

  @doc false
  # Determines whether an endpoint requires authentication.
  @spec auth_required?(Spec.t(), atom()) :: boolean()
  defp auth_required?(%Spec{endpoints: endpoints}, method) do
    case Enum.find(endpoints, fn endpoint -> endpoint[:name] == method end) do
      %{auth: true} -> true
      _ -> false
    end
  end

  @doc false
  # Fetches orders for lookup, preferring fetchOrders if available.
  @spec fetch_orders_for_lookup(Spec.t(), module(), String.t() | nil, term(), term(), keyword(), term()) ::
          {:ok, list()} | {:error, Error.t()}
  defp fetch_orders_for_lookup(spec, module, symbol, since, limit, opts, creds) do
    args = [symbol, since, limit]

    cond do
      endpoint_available?(spec, :fetch_orders) ->
        call_method(spec, module, :fetch_orders, args, opts, creds)

      has_any_order_endpoint?(spec) ->
        combine_order_endpoints(spec, module, args, opts, creds)

      true ->
        {:error,
         Error.not_supported(
           message: "fetchOrder() is not supported yet",
           exchange: exchange_atom(spec)
         )}
    end
  end

  defp has_any_order_endpoint?(spec) do
    endpoint_available?(spec, :fetch_open_orders) or
      endpoint_available?(spec, :fetch_closed_orders) or
      endpoint_available?(spec, :fetch_canceled_orders)
  end

  defp combine_order_endpoints(spec, module, args, opts, creds) do
    with {:ok, open} <- call_optional_method(spec, module, :fetch_open_orders, args, opts, creds),
         {:ok, closed} <- call_optional_method(spec, module, :fetch_closed_orders, args, opts, creds),
         {:ok, canceled} <- call_optional_method(spec, module, :fetch_canceled_orders, args, opts, creds) do
      {:ok, open ++ closed ++ canceled}
    end
  end

  # ===========================================================================
  # Trade Extraction Helpers
  # ===========================================================================

  @doc false
  # Extracts trades from params or returns trade IDs when provided.
  @spec trades_from_params(map()) :: {:trades, list()} | {:trade_ids, list()} | :no_trades_param
  defp trades_from_params(params) do
    trades = extract_param(params, :trades)
    extract_trades_or_ids(trades, params)
  end

  defp extract_trades_or_ids(trades, _params) when is_list(trades) do
    if Enum.all?(trades, &is_map/1) do
      {:trades, trades}
    else
      {:trade_ids, extract_trade_ids(trades)}
    end
  end

  defp extract_trades_or_ids(_trades, params) do
    order = extract_param(params, :order)
    extract_trades_from_order(order)
  end

  defp extract_trades_from_order(order) when is_map(order) do
    case get_field(order, :trades) do
      order_trades when is_list(order_trades) -> {:trades, order_trades}
      _ -> :no_trades_param
    end
  end

  defp extract_trades_from_order(_order), do: :no_trades_param

  @doc false
  # Extracts trade IDs from trade maps or strings.
  @spec extract_trade_ids(list()) :: list()
  defp extract_trade_ids(trades) do
    trades
    |> Enum.map(&extract_single_trade_id/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_single_trade_id(trade) when is_binary(trade), do: trade
  defp extract_single_trade_id(trade) when is_map(trade), do: get_field(trade, :id)
  defp extract_single_trade_id(_trade), do: nil

  @doc false
  # Filters trades by order id.
  @spec filter_by_order_id(list(), String.t()) :: list()
  defp filter_by_order_id(trades, id) do
    trades
    |> ensure_list()
    |> Enum.filter(fn trade ->
      get_field(trade, :order_id) == id or get_field(trade, :order) == id
    end)
  end

  @doc false
  # Filters trades by trade IDs list.
  @spec filter_by_trade_ids(list(), list()) :: list()
  defp filter_by_trade_ids(trades, trade_ids) do
    trade_id_set = MapSet.new(trade_ids)

    trades
    |> ensure_list()
    |> Enum.filter(fn trade ->
      trade_id = get_field(trade, :id)
      MapSet.member?(trade_id_set, trade_id)
    end)
  end

  @doc false
  # Extracts trades from orders, flattening order trade lists.
  @spec orders_to_trades(list()) :: list()
  defp orders_to_trades(orders) do
    orders
    |> ensure_list()
    |> Enum.flat_map(&extract_order_trades/1)
  end

  defp extract_order_trades(order) do
    case get_field(order, :trades) do
      trades when is_list(trades) -> trades
      _ -> []
    end
  end

  # ===========================================================================
  # Filtering Helpers
  # ===========================================================================

  @doc false
  # Filters entries by symbol if symbol is present.
  @spec filter_by_symbol(list(), String.t() | nil) :: list()
  defp filter_by_symbol(entries, nil), do: ensure_list(entries)

  defp filter_by_symbol(entries, symbol) do
    entries
    |> ensure_list()
    |> Enum.filter(fn entry -> get_field(entry, :symbol) == symbol end)
  end

  @doc false
  # Filters orders by normalized status.
  @spec filter_by_status(list(), atom()) :: list()
  defp filter_by_status(orders, status) do
    target = normalize_status(status)

    orders
    |> ensure_list()
    |> Enum.filter(fn order ->
      normalize_status(get_field(order, :status)) == target
    end)
  end

  @doc false
  # Filters ledger entries to deposit/withdrawal transactions.
  @spec filter_ledger_transactions(list()) :: list()
  defp filter_ledger_transactions(ledger) do
    ledger
    |> ensure_list()
    |> Enum.filter(&deposit_or_withdrawal?/1)
  end

  defp deposit_or_withdrawal?(entry) do
    type = entry |> extract_transaction_type() |> normalize_status()
    type in ["deposit", "withdrawal"]
  end

  defp extract_transaction_type(entry) do
    case get_field(entry, :type) do
      nil -> extract_transact_type(entry)
      value -> value
    end
  end

  defp extract_transact_type(entry) do
    case get_field(entry, :transact_type) do
      nil -> Map.get(entry, "transactType")
      value -> value
    end
  end

  @doc false
  # Applies CCXT-style since/limit filtering.
  @spec filter_by_since_limit(list(), term(), term(), atom()) :: list()
  defp filter_by_since_limit(entries, since, limit, key) do
    filtered = filter_by_since(entries, since, key)
    apply_limit(filtered, since, limit, key)
  end

  defp filter_by_since(entries, nil, _key), do: ensure_list(entries)

  defp filter_by_since(entries, since, key) do
    entries
    |> ensure_list()
    |> Enum.filter(fn entry ->
      case get_field(entry, key) do
        nil -> false
        value -> value >= since
      end
    end)
  end

  defp apply_limit(filtered, since, limit, key) do
    from_start = not is_nil(since)
    filter_by_limit(filtered, limit, key, from_start)
  end

  @doc false
  # Limits a list while respecting sort order of the key field.
  @spec filter_by_limit(list(), term(), atom(), boolean()) :: list()
  defp filter_by_limit(entries, nil, _key, _from_start), do: entries
  defp filter_by_limit([], _limit, _key, _from_start), do: []

  defp filter_by_limit(entries, limit, key, from_start) do
    ascending = infer_ascending(entries, key)
    take_with_direction(entries, limit, from_start, ascending)
  end

  defp take_with_direction(entries, limit, true, true), do: Enum.take(entries, limit)
  defp take_with_direction(entries, limit, true, false), do: Enum.take(entries, -limit)
  defp take_with_direction(entries, limit, false, true), do: Enum.take(entries, -limit)
  defp take_with_direction(entries, limit, false, false), do: Enum.take(entries, limit)

  @doc false
  # Infers whether a list is sorted ascending by the given key.
  @spec infer_ascending(list(), atom()) :: boolean()
  defp infer_ascending(entries, key) do
    first = entries |> List.first() |> get_field(key)
    last = entries |> List.last() |> get_field(key)

    is_nil(first) or is_nil(last) or first <= last
  end

  @doc false
  # Sorts entries by a key, defaulting missing values to zero.
  @spec sort_by(list(), atom(), boolean()) :: list()
  defp sort_by(entries, key, descending) do
    direction = if descending, do: :desc, else: :asc

    Enum.sort_by(entries, fn entry -> get_field(entry, key) || @zero end, direction)
  end

  # ===========================================================================
  # Entry Picking Helpers
  # ===========================================================================

  @doc false
  # Returns the matching entry for a symbol from a list or map.
  @spec pick_symbol_entry(term(), String.t() | nil) :: term()
  defp pick_symbol_entry(_entries, nil), do: nil
  defp pick_symbol_entry(entries, symbol) when is_map(entries), do: Map.get(entries, symbol)

  defp pick_symbol_entry(entries, symbol) when is_list(entries) do
    Enum.find(entries, fn entry -> get_field(entry, :symbol) == symbol end)
  end

  defp pick_symbol_entry(_entries, _symbol), do: nil

  @doc false
  # Returns the matching entry for a currency code from a map.
  @spec pick_code_entry(term(), String.t() | nil) :: term()
  defp pick_code_entry(_entries, nil), do: nil
  defp pick_code_entry(entries, code) when is_map(entries), do: Map.get(entries, code)
  defp pick_code_entry(_entries, _code), do: nil

  @doc false
  # Finds an order by id within a list of orders.
  @spec pick_order_by_id(list(), String.t()) :: term()
  defp pick_order_by_id(orders, id) do
    orders
    |> ensure_list()
    |> Enum.find(fn order -> get_field(order, :id) == id end)
  end

  # ===========================================================================
  # Normalization Helpers
  # ===========================================================================

  @doc false
  # Normalizes symbols input to a list.
  @spec normalize_symbols(term()) :: list() | nil
  defp normalize_symbols(nil), do: nil
  defp normalize_symbols(symbols) when is_list(symbols), do: symbols
  defp normalize_symbols(symbol) when is_binary(symbol), do: [symbol]
  defp normalize_symbols(_), do: nil

  @doc false
  # Normalizes status values to lowercase strings.
  @spec normalize_status(term()) :: String.t() | nil
  defp normalize_status(status) when is_atom(status) do
    status |> Atom.to_string() |> String.downcase()
  end

  defp normalize_status(status) when is_binary(status), do: String.downcase(status)
  defp normalize_status(_), do: nil

  # ===========================================================================
  # Field Access Helpers
  # ===========================================================================

  @doc false
  # Extracts a field from maps or structs, supporting string keys.
  @spec get_field(term(), atom()) :: term()
  defp get_field(%{} = data, key) do
    Map.get(data, key) || Map.get(data, Atom.to_string(key)) || Map.get(data, camelize_key(key))
  end

  defp get_field(_data, _key), do: nil

  @doc false
  # Converts snake_case atom keys to camelCase strings for lookup.
  @spec camelize_key(atom()) :: String.t()
  defp camelize_key(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map_join(fn
      {segment, 0} -> segment
      {segment, _} -> String.capitalize(segment)
    end)
  end

  @doc false
  # Extracts a param from map, supporting string keys.
  @spec extract_param(map(), atom()) :: term()
  defp extract_param(params, key) when is_map(params) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end

  @doc false
  # Drops param keys from opts[:params] if present.
  @spec drop_params(keyword(), [atom()]) :: keyword()
  defp drop_params(opts, keys) do
    params = opts |> Keyword.get(:params, %{}) |> Map.new()

    pruned =
      Enum.reduce(keys, params, fn key, acc ->
        acc
        |> Map.delete(key)
        |> Map.delete(Atom.to_string(key))
      end)

    Keyword.put(opts, :params, pruned)
  end

  @doc false
  # Resolves network-specific deposit addresses.
  @spec resolve_network_address(term(), String.t() | nil) :: term()
  defp resolve_network_address(address_map, nil) when is_map(address_map) do
    address_map |> Map.values() |> List.first()
  end

  defp resolve_network_address(address_map, network) when is_map(address_map) do
    Map.get(address_map, network) || Map.get(address_map, String.downcase(to_string(network)))
  end

  defp resolve_network_address(_address_map, _network), do: nil

  @doc false
  # Ensures a value is returned as a list.
  @spec ensure_list(term()) :: list()
  defp ensure_list(list) when is_list(list), do: list
  defp ensure_list(nil), do: []
  defp ensure_list(value), do: [value]

  @doc false
  # Returns true for truthy values (non-nil and not false).
  @spec truthy?(term()) :: boolean()
  defp truthy?(value), do: value not in [nil, false]

  # ===========================================================================
  # Currency Derivation
  # ===========================================================================

  @doc false
  # Derives trading limits from markets data.
  @spec derive_trading_limits(list(), list() | nil) :: map()
  defp derive_trading_limits(markets, symbols) do
    markets
    |> ensure_list()
    |> Enum.reduce(%{}, fn market, acc ->
      symbol = get_field(market, :symbol)

      if symbol_filter_match?(symbol, symbols) do
        limits = get_nested_field(market, [:limits, :amount])
        Map.put(acc, symbol, limits)
      else
        acc
      end
    end)
  end

  @doc false
  # Derives currencies map from market list (base + quote currencies).
  @spec derive_currencies_from_markets(list()) :: map()
  defp derive_currencies_from_markets(markets) do
    currencies =
      markets
      |> ensure_list()
      |> Enum.flat_map(fn market ->
        [
          currency_from_market(market, :base),
          currency_from_market(market, :quote)
        ]
      end)
      |> Enum.reject(&is_nil/1)

    currencies
    |> Enum.group_by(&get_field(&1, :code))
    |> Enum.map(fn {_code, entries} -> pick_highest_precision(entries) end)
    |> Enum.reject(&is_nil/1)
    |> Map.new(fn currency -> {get_field(currency, :code), currency} end)
  end

  @doc false
  # Builds a currency map from a market entry.
  @spec currency_from_market(map(), :base | :quote) :: map() | nil
  defp currency_from_market(market, side) do
    {code_key, id_key, numeric_id_key, precision_keys} = currency_keys_for_side(side)
    code = get_field(market, code_key)

    if is_nil(code) do
      nil
    else
      precision =
        precision_keys
        |> Enum.find_value(fn key -> get_nested_field(market, [:precision, key]) end)
        |> fallback_precision()

      %{
        id: get_field(market, id_key),
        code: code,
        numeric_id: get_field(market, numeric_id_key),
        precision: precision,
        networks: %{},
        raw: nil
      }
    end
  end

  defp currency_keys_for_side(:base), do: {:base, :base_id, :base_numeric_id, [:base, :amount]}
  defp currency_keys_for_side(:quote), do: {:quote, :quote_id, :quote_numeric_id, [:quote, :price]}

  @doc false
  # Picks the currency entry with the highest precision value.
  @spec pick_highest_precision(list()) :: map() | nil
  defp pick_highest_precision([]), do: nil

  defp pick_highest_precision(entries) do
    Enum.max_by(entries, fn entry -> precision_value(get_field(entry, :precision)) end, fn -> nil end)
  end

  @doc false
  # Returns numeric precision value for comparisons.
  @spec precision_value(term()) :: number()
  defp precision_value(value) when is_number(value), do: value
  defp precision_value(_), do: @zero

  @doc false
  # Returns fallback precision when market precision is missing.
  @spec fallback_precision(term()) :: number()
  defp fallback_precision(nil), do: @default_currency_precision
  defp fallback_precision(value), do: value

  @doc false
  # Matches symbol filter if symbols list is provided.
  @spec symbol_filter_match?(String.t() | nil, list() | nil) :: boolean()
  defp symbol_filter_match?(_symbol, nil), do: true
  defp symbol_filter_match?(nil, _symbols), do: false
  defp symbol_filter_match?(symbol, symbols), do: symbol in symbols

  @doc false
  # Retrieves nested values with atom/string keys.
  @spec get_nested_field(term(), list()) :: term()
  defp get_nested_field(value, []), do: value

  defp get_nested_field(%{} = map, [key | rest]) do
    result = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    get_nested_field(result, rest)
  end

  defp get_nested_field(_value, _rest), do: nil

  # ===========================================================================
  # Scope and Method Name Helpers
  # ===========================================================================

  @doc false
  # Normalizes scope from string to atom for indexing.
  @spec normalize_scope(atom() | String.t()) :: atom()
  defp normalize_scope(:rest), do: :rest
  defp normalize_scope(:ws), do: :ws
  defp normalize_scope("rest"), do: :rest
  defp normalize_scope("ws"), do: :ws
  defp normalize_scope(_), do: :unknown

  @doc false
  # Converts a camelCase method name to snake_case atom.
  @spec to_method_atom(String.t() | nil) :: atom() | nil
  # sobelow_skip ["DOS.StringToAtom"]
  defp to_method_atom(name) when is_binary(name) do
    name
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp to_method_atom(_), do: nil

  @doc false
  # Formats reasons as a message suffix.
  @spec emulation_reason_suffix(map()) :: String.t()
  defp emulation_reason_suffix(entry) do
    case Map.get(entry, "reasons", []) do
      [] -> ""
      reasons -> " (#{Enum.join(reasons, ", ")})"
    end
  end

  @doc false
  # Resolves exchange atom for error reporting.
  # sobelow_skip ["DOS.StringToAtom"]
  # Safe: spec.id comes from trusted extraction data, not user input
  @spec exchange_atom(Spec.t()) :: atom()
  defp exchange_atom(%Spec{exchange_id: exchange_id, id: id}) do
    exchange_id || String.to_atom(id)
  end
end
