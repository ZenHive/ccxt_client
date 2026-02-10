defmodule CCXT.ResponseCoercer do
  @moduledoc """
  Coerces raw API response maps to typed structs.

  Part of the Type-Safe API Bundle (Task 149). After the HTTP client returns
  raw response data, this module converts it to typed structs for better
  developer experience and compile-time safety.

  ## Usage

  By default, API responses are coerced to typed structs:

      {:ok, %CCXT.Types.Ticker{}} = Exchange.fetch_ticker("BTC/USDT")

  To get raw maps instead (backward compatible), use the `:raw` option:

      {:ok, %{}} = Exchange.fetch_ticker("BTC/USDT", raw: true)

  ## Response Types

  The coercer maps endpoint names to type modules:

  | Endpoint | Response Type |
  |----------|---------------|
  | `fetch_ticker` | `CCXT.Types.Ticker` |
  | `fetch_tickers` | `[CCXT.Types.Ticker]` |
  | `fetch_order` | `CCXT.Types.Order` |
  | `fetch_orders` | `[CCXT.Types.Order]` |
  | `fetch_balance` | `CCXT.Types.Balance` |
  | `fetch_order_book` | `CCXT.Types.OrderBook` |
  | `fetch_trades` | `[CCXT.Types.Trade]` |
  | `fetch_positions` | `[CCXT.Types.Position]` |
  | `fetch_funding_rate` | `CCXT.Types.FundingRate` |
  | `fetch_funding_rates` | `%{symbol => CCXT.Types.FundingRate}` |
  | `fetch_funding_rate_history` | `[CCXT.Types.FundingRateHistory]` |
  | `create_order` | `CCXT.Types.Order` |
  | `cancel_order` | `CCXT.Types.Order` |
  | `fetch_deposits` | `[CCXT.Types.Transaction]` |
  | `fetch_withdrawals` | `[CCXT.Types.Transaction]` |
  | `fetch_deposit_address` | `CCXT.Types.DepositAddress` |
  | `transfer` | `CCXT.Types.TransferEntry` |
  | `fetch_transfers` | `[CCXT.Types.TransferEntry]` |
  | `fetch_ledger` | `[CCXT.Types.LedgerEntry]` |
  | `fetch_leverage` | `CCXT.Types.Leverage` |
  | `fetch_trading_fee` | `CCXT.Types.TradingFeeInterface` |
  | `fetch_trading_fees` | `%{symbol => CCXT.Types.TradingFeeInterface}` |
  | `fetch_deposit_withdraw_fees` | `%{code => CCXT.Types.DepositWithdrawFee}` |
  | `add_margin` | `CCXT.Types.MarginModification` |
  | `reduce_margin` | `CCXT.Types.MarginModification` |
  | `fetch_open_interest` | `CCXT.Types.OpenInterest` |
  | `fetch_open_interest_history` | `[CCXT.Types.OpenInterest]` |
  | `set_margin_mode` | `CCXT.Types.MarginMode` |
  | `fetch_margin_mode` | `CCXT.Types.MarginMode` |
  | `fetch_liquidations` | `[CCXT.Types.Liquidation]` |
  | `fetch_borrow_interest` | `[CCXT.Types.BorrowInterest]` |
  | `fetch_cross_borrow_rate` | `CCXT.Types.CrossBorrowRate` |
  | `fetch_convert_trade` | `CCXT.Types.Conversion` |
  | `fetch_convert_trade_history` | `[CCXT.Types.Conversion]` |
  | `fetch_greeks` | `CCXT.Types.Greeks` |
  | `fetch_accounts` | `[CCXT.Types.Account]` |
  | `fetch_option` | `CCXT.Types.Option` |
  | `fetch_option_chain` | `%{symbol => CCXT.Types.Option}` |
  | `fetch_funding_history` | `[CCXT.Types.FundingHistory]` |
  | `fetch_isolated_borrow_rate` | `CCXT.Types.IsolatedBorrowRate` |
  | `fetch_isolated_borrow_rates` | `%{symbol => CCXT.Types.IsolatedBorrowRate}` |
  | `fetch_last_prices` | `%{symbol => CCXT.Types.LastPrice}` |
  | `fetch_long_short_ratio_history` | `[CCXT.Types.LongShortRatio]` |
  | `fetch_leverage_tiers` | `%{symbol => [CCXT.Types.LeverageTier]}` |
  | `fetch_market_leverage_tiers` | `[CCXT.Types.LeverageTier]` |

  """
  require Logger

  # Maps response type atoms to their corresponding modules
  @type_modules %{
    ticker: CCXT.Types.Ticker,
    order: CCXT.Types.Order,
    position: CCXT.Types.Position,
    balance: CCXT.Types.Balance,
    order_book: CCXT.Types.OrderBook,
    trade: CCXT.Types.Trade,
    funding_rate: CCXT.Types.FundingRate,
    funding_rate_history: CCXT.Types.FundingRateHistory,
    transaction: CCXT.Types.Transaction,
    transfer: CCXT.Types.TransferEntry,
    deposit_address: CCXT.Types.DepositAddress,
    ledger_entry: CCXT.Types.LedgerEntry,
    leverage: CCXT.Types.Leverage,
    trading_fee: CCXT.Types.TradingFeeInterface,
    deposit_withdraw_fee: CCXT.Types.DepositWithdrawFee,
    margin_modification: CCXT.Types.MarginModification,
    open_interest: CCXT.Types.OpenInterest,
    margin_mode: CCXT.Types.MarginMode,
    liquidation: CCXT.Types.Liquidation,
    borrow_interest: CCXT.Types.BorrowInterest,
    borrow_rate: CCXT.Types.CrossBorrowRate,
    conversion: CCXT.Types.Conversion,
    greeks: CCXT.Types.Greeks,
    account: CCXT.Types.Account,
    option: CCXT.Types.Option,
    funding_history: CCXT.Types.FundingHistory,
    isolated_borrow_rate: CCXT.Types.IsolatedBorrowRate,
    last_price: CCXT.Types.LastPrice,
    long_short_ratio: CCXT.Types.LongShortRatio,
    leverage_tier: CCXT.Types.LeverageTier
  }

  # List types return arrays of the singular type.
  # Note: :funding_rates appears in both @list_types and @dict_types because CCXT returns
  # either a list or a dict depending on the exchange. The is_list guard matches first for
  # lists; the is_map + @dict_types clause handles dicts.
  @list_types [
    :tickers,
    :orders,
    :positions,
    :trades,
    :funding_rates,
    :funding_rate_history,
    :transactions,
    :transfers,
    :ledger_entries,
    :open_interests,
    :liquidations,
    :borrow_interests,
    :conversions,
    :trading_fees,
    :accounts,
    :funding_histories,
    :long_short_ratios,
    :market_leverage_tiers
  ]

  # Dict types return %{key => struct} maps (e.g. fetchFundingRates returns %{symbol => FundingRate})
  @dict_types [
    :funding_rates,
    :trading_fees,
    :deposit_withdraw_fees,
    :options,
    :isolated_borrow_rates,
    :last_prices
  ]

  # Dict-of-list types return %{key => [struct]} maps (e.g. fetchLeverageTiers returns %{symbol => [LeverageTier]})
  @dict_of_list_types [:leverage_tiers]

  @type response_type ::
          :ticker
          | :tickers
          | :order
          | :orders
          | :position
          | :positions
          | :balance
          | :order_book
          | :trade
          | :trades
          | :funding_rate
          | :funding_rates
          | :funding_rate_history
          | :transaction
          | :transactions
          | :transfer
          | :transfers
          | :deposit_address
          | :ledger_entry
          | :ledger_entries
          | :leverage
          | :trading_fee
          | :trading_fees
          | :deposit_withdraw_fee
          | :deposit_withdraw_fees
          | :margin_modification
          | :open_interest
          | :open_interests
          | :margin_mode
          | :liquidation
          | :liquidations
          | :borrow_interest
          | :borrow_interests
          | :borrow_rate
          | :conversion
          | :conversions
          | :greeks
          | :account
          | :accounts
          | :option
          | :options
          | :funding_history
          | :funding_histories
          | :isolated_borrow_rate
          | :isolated_borrow_rates
          | :last_price
          | :last_prices
          | :long_short_ratio
          | :long_short_ratios
          | :leverage_tier
          | :leverage_tiers
          | :market_leverage_tiers
          | nil

  @doc """
  Coerces response data to the appropriate typed struct.

  ## Parameters

  - `data` - The raw response data (map or list of maps)
  - `type` - The response type atom (e.g., `:ticker`, `:orders`)
  - `opts` - Options keyword list. If `raw: true`, returns data unchanged.

  ## Examples

      iex> data = %{"symbol" => "BTC/USDT", "last" => 50000.0}
      iex> CCXT.ResponseCoercer.coerce(data, :ticker, [])
      %CCXT.Types.Ticker{symbol: "BTC/USDT", last: 50000.0, ...}

      iex> CCXT.ResponseCoercer.coerce(data, :ticker, raw: true)
      %{"symbol" => "BTC/USDT", "last" => 50000.0}

      iex> CCXT.ResponseCoercer.coerce(data, nil, [])
      %{"symbol" => "BTC/USDT", "last" => 50000.0}

  """
  @spec coerce(term(), response_type(), keyword(), [{atom(), atom(), [String.t()]}] | nil) :: term()
  def coerce(data, type, opts, parser_mapping \\ nil)

  def coerce(data, nil, _opts, _parser_mapping), do: data

  def coerce(data, type, opts, parser_mapping) do
    if Keyword.get(opts, :raw, false) do
      data
    else
      coerce_typed(data, type, parser_mapping)
    end
  end

  # Internal typed coercion after raw check
  @doc false
  @spec coerce_typed(term(), response_type(), [{atom(), atom(), [String.t()]}] | nil) :: term()
  defp coerce_typed(data, type, parser_mapping) when type in @list_types and is_list(data) do
    singular = singularize(type)
    Enum.map(data, &coerce_single(&1, singular, parser_mapping))
  end

  defp coerce_typed(data, type, parser_mapping) when is_map(data) and type in @dict_of_list_types do
    singular = singularize(type)

    Map.new(data, fn
      {k, v} when is_list(v) ->
        {k, Enum.map(v, &coerce_single(&1, singular, parser_mapping))}

      {k, v} when is_map(v) ->
        {k, coerce_single(v, singular, parser_mapping)}

      {k, v} ->
        Logger.warning("ResponseCoercer: unexpected value for #{inspect(type)} key #{inspect(k)}: #{inspect(v)}")

        {k, v}
    end)
  end

  defp coerce_typed(data, type, parser_mapping) when is_map(data) and type in @dict_types do
    singular = singularize(type)

    Map.new(data, fn
      {k, v} when is_map(v) ->
        {k, coerce_single(v, singular, parser_mapping)}

      {k, v} ->
        Logger.warning("ResponseCoercer: unexpected non-map value for #{inspect(type)} key #{inspect(k)}: #{inspect(v)}")

        {k, v}
    end)
  end

  defp coerce_typed(data, type, parser_mapping) when is_map(data) do
    coerce_single(data, type, parser_mapping)
  end

  # Handle unexpected data types gracefully - return unchanged
  defp coerce_typed(data, _type, _parser_mapping), do: data

  @doc false
  # Coerces a single map to its corresponding struct.
  # First applies ResponseParser to convert exchange-specific keys to unified keys,
  # then calls from_map/1 on the type module.
  @spec coerce_single(map(), atom(), [{atom(), atom(), [String.t()]}] | nil) :: struct() | map()
  defp coerce_single(data, type, parser_mapping) when is_map(data) do
    case Map.get(@type_modules, type) do
      nil ->
        data

      module when not is_nil(module) ->
        parsed = CCXT.ResponseParser.parse_single(data, parser_mapping)
        module.from_map(parsed)
    end
  end

  defp coerce_single(data, _type, _parser_mapping), do: data

  # Maps plural response types to their singular form for struct/parser lookup.
  @singularizations %{
    tickers: :ticker,
    orders: :order,
    positions: :position,
    trades: :trade,
    funding_rates: :funding_rate,
    funding_rate_history: :funding_rate_history,
    transactions: :transaction,
    transfers: :transfer,
    ledger_entries: :ledger_entry,
    open_interests: :open_interest,
    liquidations: :liquidation,
    borrow_interests: :borrow_interest,
    conversions: :conversion,
    trading_fees: :trading_fee,
    deposit_withdraw_fees: :deposit_withdraw_fee,
    accounts: :account,
    options: :option,
    funding_histories: :funding_history,
    isolated_borrow_rates: :isolated_borrow_rate,
    last_prices: :last_price,
    long_short_ratios: :long_short_ratio,
    leverage_tiers: :leverage_tier,
    market_leverage_tiers: :leverage_tier
  }

  @doc false
  @spec singularize(atom()) :: atom()
  for {plural, singular} <- @singularizations do
    def singularize(unquote(plural)), do: unquote(singular)
  end

  def singularize(type), do: type

  @doc """
  Infers the response type from an endpoint name.

  Used during code generation to automatically set response types
  for known endpoint patterns.

  ## Examples

      iex> CCXT.ResponseCoercer.infer_response_type(:fetch_ticker)
      :ticker

      iex> CCXT.ResponseCoercer.infer_response_type(:fetch_orders)
      :orders

      iex> CCXT.ResponseCoercer.infer_response_type(:some_custom_endpoint)
      nil

  """
  # Maps endpoint names to their response types. Generated into function clauses at compile time.
  @endpoint_type_map %{
    # Market data
    fetch_ticker: :ticker,
    fetch_tickers: :tickers,
    fetch_order_book: :order_book,
    fetch_trades: :trades,
    fetch_my_trades: :trades,
    # Orders
    fetch_order: :order,
    fetch_orders: :orders,
    fetch_open_orders: :orders,
    fetch_closed_orders: :orders,
    create_order: :order,
    cancel_order: :order,
    edit_order: :order,
    # Positions & funding
    fetch_position: :position,
    fetch_positions: :positions,
    fetch_balance: :balance,
    fetch_funding_rate: :funding_rate,
    fetch_funding_rates: :funding_rates,
    fetch_funding_rate_history: :funding_rate_history,
    # Deposits, withdrawals, transfers
    fetch_deposits: :transactions,
    fetch_withdrawals: :transactions,
    fetch_deposit: :transaction,
    fetch_withdrawal: :transaction,
    fetch_deposit_address: :deposit_address,
    transfer: :transfer,
    fetch_transfers: :transfers,
    fetch_ledger: :ledger_entries,
    # Leverage & margin
    fetch_leverage: :leverage,
    set_leverage: :leverage,
    add_margin: :margin_modification,
    reduce_margin: :margin_modification,
    set_margin_mode: :margin_mode,
    fetch_margin_mode: :margin_mode,
    # Fees
    fetch_trading_fee: :trading_fee,
    fetch_trading_fees: :trading_fees,
    fetch_deposit_withdraw_fees: :deposit_withdraw_fees,
    # Market info
    fetch_open_interest: :open_interest,
    fetch_open_interest_history: :open_interests,
    fetch_liquidations: :liquidations,
    fetch_my_liquidations: :liquidations,
    fetch_borrow_interest: :borrow_interests,
    fetch_cross_borrow_rate: :borrow_rate,
    # Conversions & options
    fetch_convert_trade: :conversion,
    fetch_convert_trade_history: :conversions,
    fetch_greeks: :greeks,
    # Accounts
    fetch_accounts: :accounts,
    # Options
    fetch_option: :option,
    fetch_option_chain: :options,
    # Funding history
    fetch_funding_history: :funding_histories,
    # Borrow rates
    fetch_isolated_borrow_rate: :isolated_borrow_rate,
    fetch_isolated_borrow_rates: :isolated_borrow_rates,
    # Last prices
    fetch_last_prices: :last_prices,
    # Long/short ratio
    fetch_long_short_ratio_history: :long_short_ratios,
    # Leverage tiers
    fetch_leverage_tiers: :leverage_tiers,
    fetch_market_leverage_tiers: :market_leverage_tiers
  }

  @spec infer_response_type(atom()) :: response_type()
  for {endpoint, type} <- @endpoint_type_map do
    def infer_response_type(unquote(endpoint)), do: unquote(type)
  end

  def infer_response_type(_), do: nil

  @doc """
  Returns all known type modules.

  Useful for introspection and testing.
  """
  @spec type_modules() :: %{atom() => module()}
  def type_modules, do: @type_modules

  @doc """
  Returns all list types.

  Useful for introspection and testing.
  """
  @spec list_types() :: [atom()]
  def list_types, do: @list_types

  @doc """
  Returns all dict types (endpoints returning `%{key => struct}` maps).

  Useful for introspection and testing.
  """
  @spec dict_types() :: [atom()]
  def dict_types, do: @dict_types

  @doc """
  Returns all dict-of-list types (endpoints returning `%{key => [struct]}` maps).

  Useful for introspection and testing.
  """
  @spec dict_of_list_types() :: [atom()]
  def dict_of_list_types, do: @dict_of_list_types
end
