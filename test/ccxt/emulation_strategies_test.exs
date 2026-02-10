defmodule CCXT.EmulationStrategiesTest do
  use ExUnit.Case, async: true

  alias CCXT.Emulation
  alias CCXT.Extract.EmulatedMethods
  alias CCXT.Spec

  @symbol "BTC/USDT"
  @other_symbol "ETH/USDT"
  @order_id "order-123"
  @missing_order_id "order-missing"
  @trade_id "trade-1"
  @trade_id_extra "trade-2"
  @code "BTC"
  @network "ERC20"

  @timestamp_old 1_600_000_000_000
  @timestamp_new 1_700_000_000_000
  @timestamp_latest 1_800_000_000_000
  @limit_one 1
  @min_amount 1
  @max_amount 10
  @fee_value "0.0001"

  @credentials %CCXT.Credentials{api_key: "key", secret: "secret"}

  defmodule ExchangeStub do
    @moduledoc false

    @doc false
    # Returns orders from process dictionary for emulation tests
    def fetch_orders(_creds, _symbol, _since, _limit, _opts) do
      {:ok, Process.get(:orders, [])}
    end

    @doc false
    # Returns tickers from process dictionary for emulation tests
    def fetch_tickers(_symbols, _opts) do
      {:ok, Process.get(:tickers, %{})}
    end

    @doc false
    # Returns markets from process dictionary for emulation tests
    def fetch_markets(_opts) do
      {:ok, Process.get(:markets, [])}
    end

    @doc false
    # Returns deposit address map from process dictionary for emulation tests
    def fetch_deposit_addresses_by_network(_creds, _code, _opts) do
      {:ok, Process.get(:deposit_addresses_by_network, %{})}
    end

    @doc false
    # Returns trades from process dictionary for emulation tests
    def fetch_my_trades(_creds, _symbol, _since, _limit, _opts) do
      {:ok, Process.get(:my_trades, [])}
    end

    @doc false
    # Returns leverage map from process dictionary for emulation tests
    def fetch_leverages(_creds, _symbols, _opts) do
      {:ok, Process.get(:leverages, %{})}
    end

    @doc false
    # Returns trading fees map from process dictionary for emulation tests
    def fetch_trading_fees(_creds, _opts) do
      {:ok, Process.get(:trading_fees, %{})}
    end

    @doc false
    # Returns deposit/withdraw fee map from process dictionary for emulation tests
    def fetch_deposit_withdraw_fees(_creds, _codes, _opts) do
      {:ok, Process.get(:deposit_withdraw_fees, %{})}
    end

    @doc false
    # Returns transaction fee map from process dictionary for emulation tests
    def fetch_transaction_fees(_creds, _codes, _opts) do
      {:ok, Process.get(:transaction_fees, %{})}
    end

    @doc false
    # Returns ledger entries from process dictionary for emulation tests
    def fetch_ledger(_creds, _code, _since, _limit, _opts) do
      {:ok, Process.get(:ledger, [])}
    end

    @doc false
    # Returns deposit address map from process dictionary for emulation tests
    def fetch_deposit_addresses(_creds, _codes, _opts) do
      {:ok, Process.get(:deposit_addresses, %{})}
    end

    @doc false
    # Returns deposits list from process dictionary for emulation tests
    def fetch_deposits(_creds, _code, _since, _limit, _opts) do
      {:ok, Process.get(:deposits, [])}
    end

    @doc false
    # Returns withdrawals list from process dictionary for emulation tests
    def fetch_withdrawals(_creds, _code, _since, _limit, _opts) do
      {:ok, Process.get(:withdrawals, [])}
    end

    @doc false
    # Returns funding rates map from process dictionary for emulation tests
    def fetch_funding_rates(_creds, _symbols, _opts) do
      {:ok, Process.get(:funding_rates, %{})}
    end

    @doc false
    # Returns leverage tiers map from process dictionary for emulation tests
    def fetch_leverage_tiers(_creds, _symbols, _opts) do
      {:ok, Process.get(:leverage_tiers, %{})}
    end

    @doc false
    # Returns isolated borrow rates map from process dictionary for emulation tests
    def fetch_isolated_borrow_rates(_creds, _opts) do
      {:ok, Process.get(:isolated_borrow_rates, %{})}
    end

    @doc false
    # Returns positions list from process dictionary for emulation tests
    def fetch_positions(_creds, _symbols, _opts) do
      {:ok, Process.get(:positions, [])}
    end

    @doc false
    # Returns positions history from process dictionary for emulation tests
    def fetch_positions_history(_creds, _symbols, _since, _limit, _opts) do
      {:ok, Process.get(:positions_history, [])}
    end

    @doc false
    # Returns margin modes map from process dictionary for emulation tests
    def fetch_margin_modes(_creds, _symbols, _opts) do
      {:ok, Process.get(:margin_modes, %{})}
    end

    @doc false
    # Returns funding intervals map from process dictionary for emulation tests
    def fetch_funding_intervals(_creds, _symbols, _opts) do
      {:ok, Process.get(:funding_intervals, %{})}
    end

    @doc false
    # Returns open orders from process dictionary for emulation tests
    def fetch_open_orders(_creds, _symbol, _since, _limit, _opts) do
      {:ok, Process.get(:open_orders, [])}
    end

    @doc false
    # Returns closed orders from process dictionary for emulation tests
    def fetch_closed_orders(_creds, _symbol, _since, _limit, _opts) do
      {:ok, Process.get(:closed_orders, [])}
    end

    @doc false
    # Returns canceled orders from process dictionary for emulation tests
    def fetch_canceled_orders(_creds, _symbol, _since, _limit, _opts) do
      {:ok, Process.get(:canceled_orders, [])}
    end
  end

  describe "core emulation strategies" do
    test "fetch_closed_orders filters by status and since/limit" do
      exchange_id = exchange_for_method("fetchClosedOrders")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      Process.put(:orders, [
        %{id: @order_id, status: "closed", timestamp: @timestamp_new},
        %{id: "open-order", status: "open", timestamp: @timestamp_new},
        %{id: "old-closed", status: "closed", timestamp: @timestamp_old}
      ])

      assert {:ok, [%{id: @order_id}]} =
               dispatch(spec, :fetch_closed_orders,
                 params: %{symbol: @symbol, since: @timestamp_new, limit: nil},
                 credentials: @credentials
               )
    end

    test "fetch_ticker selects a single ticker from fetch_tickers" do
      exchange_id = exchange_for_method("fetchTicker")
      spec = build_spec(exchange_id, [:fetch_tickers])

      Process.put(:tickers, %{
        @symbol => %{symbol: @symbol, last: "42000"},
        @other_symbol => %{symbol: @other_symbol, last: "2500"}
      })

      assert {:ok, %{symbol: @symbol}} =
               dispatch(spec, :fetch_ticker, params: %{symbol: @symbol})
    end

    test "fetch_ticker returns error when symbol is missing" do
      exchange_id = exchange_for_method("fetchTicker")
      spec = build_spec(exchange_id, [:fetch_tickers])

      assert {:error, %CCXT.Error{type: :invalid_parameters, message: message}} =
               dispatch(spec, :fetch_ticker)

      assert String.contains?(message, "requires a symbol argument")
    end

    test "fetch_trading_limits derives limits from markets" do
      exchange_id = exchange_for_method("fetchTradingLimits")
      spec = build_spec(exchange_id, [:fetch_markets])

      Process.put(:markets, [
        %{
          symbol: @symbol,
          limits: %{amount: %{min: @min_amount, max: @max_amount}}
        },
        %{
          symbol: @other_symbol,
          limits: %{amount: %{min: @min_amount, max: @max_amount}}
        }
      ])

      assert {:ok, %{@symbol => %{min: @min_amount, max: @max_amount}}} =
               dispatch(spec, :fetch_trading_limits, params: %{symbols: [@symbol]})
    end

    test "fetch_trading_fee selects a symbol entry from fetch_trading_fees" do
      exchange_id = exchange_for_method("fetchTradingFee")
      spec = build_spec(exchange_id, [:fetch_trading_fees], auth_methods: [:fetch_trading_fees])

      Process.put(:trading_fees, %{@symbol => %{symbol: @symbol, maker: @fee_value}})

      assert {:ok, %{symbol: @symbol, maker: @fee_value}} =
               dispatch(spec, :fetch_trading_fee,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_trading_fee returns not_supported when endpoint missing" do
      exchange_id = exchange_for_method("fetchTradingFee")
      spec = build_spec(exchange_id, [])

      assert {:error, %CCXT.Error{type: :not_supported, message: message}} =
               dispatch(spec, :fetch_trading_fee,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )

      assert String.contains?(message, "fetch_trading_fees")
    end

    test "fetch_deposit_address selects network address when provided" do
      exchange_id = exchange_for_method("fetchDepositAddress")

      spec =
        build_spec(exchange_id, [:fetch_deposit_addresses_by_network],
          auth_methods: [:fetch_deposit_addresses_by_network]
        )

      Process.put(:deposit_addresses_by_network, %{
        @network => %{address: "0xabc"}
      })

      assert {:ok, %{address: "0xabc"}} =
               dispatch(spec, :fetch_deposit_address,
                 params: %{code: @code, network: @network},
                 credentials: @credentials
               )
    end

    test "fetch_deposit_address selects an address from fetch_deposit_addresses" do
      exchange_id = exchange_for_method("fetchDepositAddress")

      spec =
        build_spec(exchange_id, [:fetch_deposit_addresses], auth_methods: [:fetch_deposit_addresses])

      Process.put(:deposit_addresses, %{@code => %{address: "addr-1"}})

      assert {:ok, %{address: "addr-1"}} =
               dispatch(spec, :fetch_deposit_address,
                 params: %{code: @code},
                 credentials: @credentials
               )
    end

    test "fetch_deposit_address returns not_supported when endpoints missing" do
      exchange_id = exchange_for_method("fetchDepositAddress")
      spec = build_spec(exchange_id, [])

      assert {:error, %CCXT.Error{type: :not_supported, message: message}} =
               dispatch(spec, :fetch_deposit_address,
                 params: %{code: @code},
                 credentials: @credentials
               )

      assert String.contains?(message, "fetchDepositAddress() is not supported yet")
    end

    test "fetch_order returns not_found when missing" do
      exchange_id = exchange_for_method("fetchOrder")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      Process.put(:orders, [%{id: @order_id, status: "open", timestamp: @timestamp_new}])

      assert {:error, %CCXT.Error{type: :order_not_found}} =
               dispatch(spec, :fetch_order,
                 params: %{id: @missing_order_id, symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_order_trades uses trade ids from params" do
      exchange_id = exchange_for_method("fetchOrderTrades")
      spec = build_spec(exchange_id, [:fetch_my_trades], auth_methods: [:fetch_my_trades])

      Process.put(:my_trades, [
        %{id: @trade_id, order_id: @order_id, symbol: @symbol},
        %{id: @trade_id_extra, order_id: @order_id, symbol: @symbol},
        %{id: "ignored-trade", order_id: @order_id, symbol: @symbol}
      ])

      assert {:ok, trades} =
               dispatch(spec, :fetch_order_trades,
                 params: %{id: @order_id, symbol: @symbol, trades: [@trade_id, @trade_id_extra]},
                 credentials: @credentials
               )

      assert Enum.map(trades, & &1.id) == [@trade_id, @trade_id_extra]
    end

    test "fetch_my_trades flattens trades from orders" do
      exchange_id = exchange_for_method("fetchMyTrades")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      Process.put(:orders, [
        %{id: @order_id, trades: [%{id: @trade_id, order_id: @order_id, symbol: @symbol}]}
      ])

      assert {:ok, [%{id: @trade_id, order_id: @order_id}]} =
               dispatch(spec, :fetch_my_trades,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_order_trades filters fetch_my_trades by order id" do
      exchange_id = exchange_for_method("fetchOrderTrades")
      spec = build_spec(exchange_id, [:fetch_my_trades], auth_methods: [:fetch_my_trades])

      Process.put(:my_trades, [
        %{id: @trade_id, order_id: @order_id, symbol: @symbol},
        %{id: "other-trade", order_id: "other", symbol: @symbol}
      ])

      assert {:ok, [%{id: @trade_id}]} =
               dispatch(spec, :fetch_order_trades,
                 params: %{id: @order_id, symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_leverage returns invalid_credentials when auth required" do
      exchange_id = exchange_for_method("fetchLeverage")
      spec = build_spec(exchange_id, [:fetch_leverages], auth_methods: [:fetch_leverages])

      assert {:error, %CCXT.Error{type: :invalid_credentials, message: message}} =
               dispatch(spec, :fetch_leverage, params: %{symbol: @symbol})

      assert String.contains?(message, "Credentials required")
    end

    test "fetch_leverage selects a symbol entry from fetch_leverages" do
      exchange_id = exchange_for_method("fetchLeverage")
      spec = build_spec(exchange_id, [:fetch_leverages], auth_methods: [:fetch_leverages])

      Process.put(:leverages, %{@symbol => %{symbol: @symbol, leverage: "5"}})

      assert {:ok, %{symbol: @symbol}} =
               dispatch(spec, :fetch_leverage,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_deposit_withdraw_fee selects a code entry" do
      exchange_id = exchange_for_method("fetchDepositWithdrawFee")

      spec =
        build_spec(exchange_id, [:fetch_deposit_withdraw_fees], auth_methods: [:fetch_deposit_withdraw_fees])

      Process.put(:deposit_withdraw_fees, %{@code => %{code: @code, fee: @fee_value}})

      assert {:ok, %{code: @code, fee: @fee_value}} =
               dispatch(spec, :fetch_deposit_withdraw_fee,
                 params: %{code: @code},
                 credentials: @credentials
               )
    end

    test "fetch_transaction_fee returns fees when code is provided" do
      exchange_id = exchange_for_method("fetchTransactionFee")
      spec = build_spec(exchange_id, [:fetch_transaction_fees], auth_methods: [:fetch_transaction_fees])

      Process.put(:transaction_fees, %{@code => %{code: @code, fee: @fee_value}})

      assert {:ok, fees} =
               dispatch(spec, :fetch_transaction_fee,
                 params: %{code: @code},
                 credentials: @credentials
               )

      assert fees[@code][:fee] == @fee_value
    end

    test "fetch_transaction_fee requires a code argument" do
      exchange_id = exchange_for_method("fetchTransactionFee")
      spec = build_spec(exchange_id, [:fetch_transaction_fees])

      assert {:error, %CCXT.Error{type: :invalid_parameters, message: message}} =
               dispatch(spec, :fetch_transaction_fee)

      assert String.contains?(message, "requires a code argument")
    end

    test "fetch_deposits_withdrawals combines deposits and withdrawals when available" do
      exchange_id = exchange_for_method("fetchDepositsWithdrawals")

      spec =
        build_spec(exchange_id, [:fetch_deposits, :fetch_withdrawals],
          auth_methods: [:fetch_deposits, :fetch_withdrawals]
        )

      Process.put(:deposits, [
        %{id: "deposit-old", type: "deposit", timestamp: @timestamp_old},
        %{id: "deposit-new", type: "deposit", timestamp: @timestamp_new}
      ])

      Process.put(:withdrawals, [
        %{id: "withdraw-new", type: "withdrawal", timestamp: @timestamp_latest}
      ])

      assert {:ok, [%{id: "deposit-new"}]} =
               dispatch(spec, :fetch_deposits_withdrawals,
                 params: %{since: @timestamp_new, limit: @limit_one},
                 credentials: @credentials
               )
    end

    test "fetch_deposits_withdrawals filters ledger by type and since/limit" do
      exchange_id = exchange_for_method("fetchDepositsWithdrawals")
      spec = build_spec(exchange_id, [:fetch_ledger], auth_methods: [:fetch_ledger])

      Process.put(:ledger, [
        %{id: "ledger-old", type: "deposit", timestamp: @timestamp_old},
        %{id: "ledger-new", transact_type: "withdrawal", timestamp: @timestamp_new},
        %{id: "ledger-trade", type: "trade", timestamp: @timestamp_latest},
        %{id: "ledger-late", type: "deposit", timestamp: @timestamp_latest}
      ])

      assert {:ok, [%{id: "ledger-new"}]} =
               dispatch(spec, :fetch_deposits_withdrawals,
                 params: %{since: @timestamp_new, limit: @limit_one},
                 credentials: @credentials
               )
    end

    test "fetch_funding_rate rejects non-contract markets" do
      exchange_id = exchange_for_method("fetchFundingRate")

      spec =
        build_spec(exchange_id, [:fetch_markets, :fetch_funding_rates], auth_methods: [:fetch_funding_rates])

      Process.put(:markets, [
        %{symbol: @symbol, contract: false}
      ])

      assert {:error, %CCXT.Error{type: :invalid_parameters, message: message}} =
               dispatch(spec, :fetch_funding_rate,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )

      assert String.contains?(message, "contract markets only")
    end

    test "fetch_market_leverage_tiers returns tiers for a contract market" do
      exchange_id = exchange_for_method("fetchMarketLeverageTiers")

      spec =
        build_spec(exchange_id, [:fetch_markets, :fetch_leverage_tiers], auth_methods: [:fetch_leverage_tiers])

      Process.put(:markets, [
        %{symbol: @symbol, contract: true}
      ])

      Process.put(:leverage_tiers, %{@symbol => %{symbol: @symbol, tiers: []}})

      assert {:ok, %{symbol: @symbol, tiers: []}} =
               dispatch(spec, :fetch_market_leverage_tiers,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_isolated_borrow_rate selects a symbol entry" do
      exchange_id = exchange_for_method("fetchIsolatedBorrowRate")

      spec =
        build_spec(exchange_id, [:fetch_isolated_borrow_rates], auth_methods: [:fetch_isolated_borrow_rates])

      Process.put(:isolated_borrow_rates, %{@symbol => %{symbol: @symbol, rate: "0.1"}})

      assert {:ok, %{symbol: @symbol, rate: "0.1"}} =
               dispatch(spec, :fetch_isolated_borrow_rate,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )
    end
  end

  describe "untested strategy handlers" do
    test "fetch_bids_asks delegates to fetch_tickers" do
      exchange_id = exchange_for_method("fetchBidsAsks")
      spec = build_spec(exchange_id, [:fetch_tickers])

      Process.put(:tickers, %{
        @symbol => %{symbol: @symbol, bid: "41999", ask: "42001"},
        @other_symbol => %{symbol: @other_symbol, bid: "2499", ask: "2501"}
      })

      assert {:ok, %{@symbol => %{symbol: @symbol}, @other_symbol => %{symbol: @other_symbol}}} =
               dispatch(spec, :fetch_bids_asks)
    end

    test "fetch_currencies derives currencies from markets" do
      # fetchCurrencies handler exists but no exchange currently marks it as emulated,
      # so we test the handler directly instead of going through dispatch.
      spec = build_spec("test_exchange", [:fetch_markets])

      Process.put(:markets, [
        %{
          symbol: @symbol,
          base: "BTC",
          quote: "USDT",
          base_id: "btc",
          quote_id: "usdt",
          precision: %{base: 8, quote: 2}
        }
      ])

      assert {:ok, currencies} =
               Emulation.handle_fetch_currencies(spec, ExchangeStub, %{}, [], nil)

      assert Map.has_key?(currencies, "BTC")
      assert Map.has_key?(currencies, "USDT")
      assert currencies["BTC"][:code] == "BTC"
      assert currencies["USDT"][:code] == "USDT"
    end

    test "fetch_transactions delegates to fetch_deposits_withdrawals" do
      exchange_id = exchange_for_method("fetchTransactions")

      spec =
        build_spec(exchange_id, [:fetch_deposits, :fetch_withdrawals],
          auth_methods: [:fetch_deposits, :fetch_withdrawals]
        )

      Process.put(:deposits, [%{id: "dep-1", type: "deposit", timestamp: @timestamp_new}])
      Process.put(:withdrawals, [%{id: "wd-1", type: "withdrawal", timestamp: @timestamp_latest}])

      assert {:ok, results} =
               dispatch(spec, :fetch_transactions, credentials: @credentials)

      ids = Enum.map(results, & &1.id)
      assert "dep-1" in ids
      assert "wd-1" in ids
    end

    test "fetch_position selects by symbol from positions list" do
      exchange_id = exchange_for_method("fetchPosition")
      spec = build_spec(exchange_id, [:fetch_positions], auth_methods: [:fetch_positions])

      Process.put(:positions, [
        %{symbol: @symbol, side: "long", contracts: 5},
        %{symbol: @other_symbol, side: "short", contracts: 3}
      ])

      assert {:ok, %{symbol: @symbol, side: "long"}} =
               dispatch(spec, :fetch_position,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_position_history delegates to fetch_positions_history" do
      exchange_id = exchange_for_method("fetchPositionHistory")

      spec =
        build_spec(exchange_id, [:fetch_positions_history], auth_methods: [:fetch_positions_history])

      Process.put(:positions_history, [
        %{symbol: @symbol, timestamp: @timestamp_old},
        %{symbol: @symbol, timestamp: @timestamp_new}
      ])

      assert {:ok, positions} =
               dispatch(spec, :fetch_position_history,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )

      assert length(positions) == 2
    end

    test "fetch_margin_mode selects by symbol from margin modes" do
      exchange_id = exchange_for_method("fetchMarginMode")
      spec = build_spec(exchange_id, [:fetch_margin_modes], auth_methods: [:fetch_margin_modes])

      Process.put(:margin_modes, %{
        @symbol => %{symbol: @symbol, marginMode: "cross"},
        @other_symbol => %{symbol: @other_symbol, marginMode: "isolated"}
      })

      assert {:ok, %{symbol: @symbol, marginMode: "cross"}} =
               dispatch(spec, :fetch_margin_mode,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_funding_interval success for contract market" do
      exchange_id = exchange_for_method("fetchFundingInterval")

      spec =
        build_spec(exchange_id, [:fetch_markets, :fetch_funding_intervals], auth_methods: [:fetch_funding_intervals])

      Process.put(:markets, [%{symbol: @symbol, contract: true}])
      Process.put(:funding_intervals, %{@symbol => %{symbol: @symbol, interval: 8}})

      assert {:ok, %{symbol: @symbol, interval: 8}} =
               dispatch(spec, :fetch_funding_interval,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_funding_interval returns error when not found" do
      exchange_id = exchange_for_method("fetchFundingInterval")

      spec =
        build_spec(exchange_id, [:fetch_markets, :fetch_funding_intervals], auth_methods: [:fetch_funding_intervals])

      Process.put(:markets, [%{symbol: @symbol, contract: true}])
      Process.put(:funding_intervals, %{})

      assert {:error, %CCXT.Error{type: :exchange_error, message: message}} =
               dispatch(spec, :fetch_funding_interval,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )

      assert String.contains?(message, "fetchFundingInterval()")
      assert String.contains?(message, @symbol)
    end

    test "fetch_open_orders filters orders by open status" do
      exchange_id = exchange_for_method("fetchOpenOrders")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      Process.put(:orders, [
        %{id: "open-1", status: "open", timestamp: @timestamp_new},
        %{id: "closed-1", status: "closed", timestamp: @timestamp_new},
        %{id: "open-2", status: "open", timestamp: @timestamp_latest}
      ])

      assert {:ok, orders} =
               dispatch(spec, :fetch_open_orders,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )

      assert length(orders) == 2
      assert Enum.all?(orders, fn o -> o.status == "open" end)
    end

    test "fetch_canceled_orders filters orders by canceled status" do
      exchange_id = exchange_for_method("fetchCanceledOrders")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      Process.put(:orders, [
        %{id: "open-1", status: "open", timestamp: @timestamp_new},
        %{id: "canceled-1", status: "canceled", timestamp: @timestamp_new},
        %{id: "canceled-2", status: "canceled", timestamp: @timestamp_latest}
      ])

      assert {:ok, orders} =
               dispatch(spec, :fetch_canceled_orders,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )

      assert length(orders) == 2
    end

    test "fetch_canceled_and_closed_orders merges and sorts" do
      exchange_id = exchange_for_method("fetchCanceledAndClosedOrders")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      Process.put(:orders, [
        %{id: "open-1", status: "open", timestamp: @timestamp_new},
        %{id: "closed-1", status: "closed", timestamp: @timestamp_old},
        %{id: "canceled-1", status: "canceled", timestamp: @timestamp_latest}
      ])

      assert {:ok, orders} =
               dispatch(spec, :fetch_canceled_and_closed_orders,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )

      ids = Enum.map(orders, & &1.id)
      assert "closed-1" in ids
      assert "canceled-1" in ids
      refute "open-1" in ids
    end
  end

  describe "additional code paths in tested handlers" do
    test "fetch_order returns matching order when found" do
      exchange_id = exchange_for_method("fetchOrder")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      Process.put(:orders, [
        %{id: @order_id, status: "open", symbol: @symbol, timestamp: @timestamp_new},
        %{id: "other-order", status: "closed", symbol: @symbol, timestamp: @timestamp_old}
      ])

      assert {:ok, %{id: @order_id, status: "open"}} =
               dispatch(spec, :fetch_order,
                 params: %{id: @order_id, symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_order via combine_order_endpoints when fetch_orders unavailable" do
      exchange_id = exchange_for_method("fetchOrder")

      spec =
        build_spec(exchange_id, [:fetch_open_orders, :fetch_closed_orders, :fetch_canceled_orders],
          auth_methods: [:fetch_open_orders, :fetch_closed_orders, :fetch_canceled_orders]
        )

      Process.put(:open_orders, [%{id: "open-1", status: "open", timestamp: @timestamp_new}])
      Process.put(:closed_orders, [%{id: @order_id, status: "closed", timestamp: @timestamp_old}])
      Process.put(:canceled_orders, [])

      assert {:ok, %{id: @order_id, status: "closed"}} =
               dispatch(spec, :fetch_order,
                 params: %{id: @order_id, symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_order_trades fetches and filters by order_id when no trades param" do
      exchange_id = exchange_for_method("fetchOrderTrades")
      spec = build_spec(exchange_id, [:fetch_my_trades], auth_methods: [:fetch_my_trades])

      Process.put(:my_trades, [
        %{id: @trade_id, order_id: @order_id, symbol: @symbol, timestamp: @timestamp_new},
        %{id: "other-trade", order_id: "other-order", symbol: @symbol, timestamp: @timestamp_new}
      ])

      assert {:ok, [%{id: @trade_id}]} =
               dispatch(spec, :fetch_order_trades,
                 params: %{id: @order_id, symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_order_trades extracts trades from order object in params" do
      exchange_id = exchange_for_method("fetchOrderTrades")
      spec = build_spec(exchange_id, [:fetch_my_trades], auth_methods: [:fetch_my_trades])

      order_trades = [
        %{id: @trade_id, order_id: @order_id, symbol: @symbol, timestamp: @timestamp_new},
        %{id: @trade_id_extra, order_id: @order_id, symbol: @symbol, timestamp: @timestamp_latest}
      ]

      assert {:ok, trades} =
               dispatch(spec, :fetch_order_trades,
                 params: %{
                   id: @order_id,
                   symbol: @symbol,
                   order: %{id: @order_id, trades: order_trades}
                 },
                 credentials: @credentials
               )

      assert length(trades) == 2
      assert Enum.map(trades, & &1.id) == [@trade_id, @trade_id_extra]
    end

    test "fetch_funding_rate success for contract market with rate" do
      exchange_id = exchange_for_method("fetchFundingRate")

      spec =
        build_spec(exchange_id, [:fetch_markets, :fetch_funding_rates], auth_methods: [:fetch_funding_rates])

      Process.put(:markets, [%{symbol: @symbol, contract: true}])
      Process.put(:funding_rates, %{@symbol => %{symbol: @symbol, fundingRate: "0.0001"}})

      assert {:ok, %{symbol: @symbol, fundingRate: "0.0001"}} =
               dispatch(spec, :fetch_funding_rate,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_funding_rate not found for contract market" do
      exchange_id = exchange_for_method("fetchFundingRate")

      spec =
        build_spec(exchange_id, [:fetch_markets, :fetch_funding_rates], auth_methods: [:fetch_funding_rates])

      Process.put(:markets, [%{symbol: @symbol, contract: true}])
      Process.put(:funding_rates, %{})

      assert {:error, %CCXT.Error{type: :exchange_error, message: message}} =
               dispatch(spec, :fetch_funding_rate,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )

      assert String.contains?(message, "fetchFundingRate()")
      assert String.contains?(message, @symbol)
    end

    test "fetch_isolated_borrow_rate returns error when not found" do
      exchange_id = exchange_for_method("fetchIsolatedBorrowRate")

      spec =
        build_spec(exchange_id, [:fetch_isolated_borrow_rates], auth_methods: [:fetch_isolated_borrow_rates])

      Process.put(:isolated_borrow_rates, %{})

      assert {:error, %CCXT.Error{type: :exchange_error, message: message}} =
               dispatch(spec, :fetch_isolated_borrow_rate,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )

      assert String.contains?(message, "fetchIsolatedBorrowRate()")
      assert String.contains?(message, @symbol)
    end

    test "fetch_deposit_address returns error when code is missing" do
      exchange_id = exchange_for_method("fetchDepositAddress")

      spec =
        build_spec(exchange_id, [:fetch_deposit_addresses], auth_methods: [:fetch_deposit_addresses])

      assert {:error, %CCXT.Error{type: :invalid_parameters, message: message}} =
               dispatch(spec, :fetch_deposit_address, credentials: @credentials)

      assert String.contains?(message, "requires a code argument")
    end
  end

  describe "currency derivation edge cases" do
    test "fetch_currencies picks highest precision when multiple markets share base" do
      spec = build_spec("test_exchange", [:fetch_markets])

      Process.put(:markets, [
        %{
          symbol: "BTC/USDT",
          base: "BTC",
          quote: "USDT",
          base_id: "btc",
          quote_id: "usdt",
          precision: %{base: 4, quote: 2}
        },
        %{
          symbol: "BTC/EUR",
          base: "BTC",
          quote: "EUR",
          base_id: "btc",
          quote_id: "eur",
          precision: %{base: 8, quote: 4}
        }
      ])

      assert {:ok, currencies} =
               Emulation.handle_fetch_currencies(spec, ExchangeStub, %{}, [], nil)

      # BTC appears in both markets - should pick highest precision (8)
      assert currencies["BTC"][:precision] == 8
    end

    test "fetch_currencies uses fallback precision when market has nil precision" do
      spec = build_spec("test_exchange", [:fetch_markets])

      Process.put(:markets, [
        %{
          symbol: "XYZ/USDT",
          base: "XYZ",
          quote: "USDT",
          base_id: "xyz",
          quote_id: "usdt",
          precision: %{}
        }
      ])

      assert {:ok, currencies} =
               Emulation.handle_fetch_currencies(spec, ExchangeStub, %{}, [], nil)

      # Default precision fallback is 1.0e-8
      assert currencies["XYZ"][:precision] == 1.0e-8
    end

    test "fetch_currencies handles market with nil base gracefully" do
      spec = build_spec("test_exchange", [:fetch_markets])

      Process.put(:markets, [
        %{
          symbol: "BTC/USDT",
          base: nil,
          quote: "USDT",
          base_id: nil,
          quote_id: "usdt",
          precision: %{quote: 2}
        }
      ])

      assert {:ok, currencies} =
               Emulation.handle_fetch_currencies(spec, ExchangeStub, %{}, [], nil)

      # nil base should be skipped, but USDT from quote should exist
      refute Map.has_key?(currencies, nil)
      assert Map.has_key?(currencies, "USDT")
    end
  end

  describe "fetch_market and ensure_contract_market edge cases" do
    test "fetch_funding_rate returns error for unknown symbol" do
      exchange_id = exchange_for_method("fetchFundingRate")

      spec =
        build_spec(exchange_id, [:fetch_markets, :fetch_funding_rates], auth_methods: [:fetch_funding_rates])

      Process.put(:markets, [%{symbol: @other_symbol, contract: true}])
      Process.put(:funding_rates, %{})

      assert {:error, %CCXT.Error{type: :invalid_parameters, message: message}} =
               dispatch(spec, :fetch_funding_rate,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )

      assert String.contains?(message, "Unknown market symbol")
    end

    test "fetch_market_leverage_tiers returns error for unknown symbol" do
      exchange_id = exchange_for_method("fetchMarketLeverageTiers")

      spec =
        build_spec(exchange_id, [:fetch_markets, :fetch_leverage_tiers], auth_methods: [:fetch_leverage_tiers])

      Process.put(:markets, [])

      assert {:error, %CCXT.Error{type: :invalid_parameters, message: message}} =
               dispatch(spec, :fetch_market_leverage_tiers,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )

      assert String.contains?(message, "Unknown market symbol")
    end

    test "ensure_contract_market returns error when symbol is nil" do
      exchange_id = exchange_for_method("fetchFundingRate")

      spec =
        build_spec(exchange_id, [:fetch_markets, :fetch_funding_rates], auth_methods: [:fetch_funding_rates])

      assert {:error, %CCXT.Error{type: :invalid_parameters, message: message}} =
               dispatch(spec, :fetch_funding_rate,
                 params: %{},
                 credentials: @credentials
               )

      assert String.contains?(message, "requires a symbol argument")
    end
  end

  describe "fetch_deposits_withdrawals edge cases" do
    test "returns not_supported when no deposit/withdrawal/ledger endpoints" do
      exchange_id = exchange_for_method("fetchDepositsWithdrawals")
      spec = build_spec(exchange_id, [])

      assert {:error, %CCXT.Error{type: :not_supported, message: message}} =
               dispatch(spec, :fetch_deposits_withdrawals, credentials: @credentials)

      assert String.contains?(message, "fetchDepositsWithdrawals() is not supported yet")
    end
  end

  describe "fetch_order edge cases" do
    test "returns not_supported when no order endpoints at all" do
      exchange_id = exchange_for_method("fetchOrder")
      spec = build_spec(exchange_id, [])

      assert {:error, %CCXT.Error{type: :not_supported, message: message}} =
               dispatch(spec, :fetch_order,
                 params: %{id: @order_id, symbol: @symbol},
                 credentials: @credentials
               )

      assert String.contains?(message, "fetchOrder() is not supported yet")
    end

    test "returns error when id is nil" do
      exchange_id = exchange_for_method("fetchOrder")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      assert {:error, %CCXT.Error{type: :invalid_parameters, message: message}} =
               dispatch(spec, :fetch_order,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )

      assert String.contains?(message, "requires an id argument")
    end
  end

  describe "empty result edge cases" do
    test "fetch_ticker returns error when tickers map is empty" do
      exchange_id = exchange_for_method("fetchTicker")
      spec = build_spec(exchange_id, [:fetch_tickers])

      Process.put(:tickers, %{})

      assert {:error, %CCXT.Error{type: :exchange_error, message: message}} =
               dispatch(spec, :fetch_ticker, params: %{symbol: @symbol})

      assert String.contains?(message, "could not find a ticker for")
    end

    test "fetch_my_trades returns empty when orders have no trades" do
      exchange_id = exchange_for_method("fetchMyTrades")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      Process.put(:orders, [
        %{id: @order_id, trades: nil},
        %{id: "order-2", trades: []}
      ])

      assert {:ok, []} =
               dispatch(spec, :fetch_my_trades,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_position returns nil when positions list is empty" do
      exchange_id = exchange_for_method("fetchPosition")
      spec = build_spec(exchange_id, [:fetch_positions], auth_methods: [:fetch_positions])

      Process.put(:positions, [])

      assert {:ok, nil} =
               dispatch(spec, :fetch_position,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )
    end
  end

  describe "infer_ascending and since/limit edge cases" do
    test "fetch_closed_orders handles single-element list with since/limit" do
      exchange_id = exchange_for_method("fetchClosedOrders")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      Process.put(:orders, [
        %{id: @order_id, status: "closed", timestamp: @timestamp_new}
      ])

      assert {:ok, [%{id: @order_id}]} =
               dispatch(spec, :fetch_closed_orders,
                 params: %{symbol: @symbol, since: @timestamp_old, limit: @limit_one},
                 credentials: @credentials
               )
    end

    test "fetch_closed_orders handles entries with nil timestamps" do
      exchange_id = exchange_for_method("fetchClosedOrders")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      Process.put(:orders, [
        %{id: "no-ts", status: "closed", timestamp: nil},
        %{id: @order_id, status: "closed", timestamp: @timestamp_new}
      ])

      # With since filter, nil timestamps are excluded
      assert {:ok, [%{id: @order_id}]} =
               dispatch(spec, :fetch_closed_orders,
                 params: %{symbol: @symbol, since: @timestamp_old},
                 credentials: @credentials
               )
    end
  end

  describe "normalize_status with atom input" do
    test "fetch_open_orders filters orders with atom status" do
      exchange_id = exchange_for_method("fetchOpenOrders")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      Process.put(:orders, [
        %{id: "atom-open", status: :open, timestamp: @timestamp_new},
        %{id: "atom-closed", status: :closed, timestamp: @timestamp_new}
      ])

      assert {:ok, [%{id: "atom-open"}]} =
               dispatch(spec, :fetch_open_orders,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )
    end
  end

  describe "dispatch_entry edge cases" do
    test "dispatch returns error when exchange_module is nil" do
      exchange_id = exchange_for_method("fetchTicker")
      spec = build_spec(exchange_id, [:fetch_tickers])

      Process.put(:tickers, %{@symbol => %{symbol: @symbol}})

      assert {:error, %CCXT.Error{type: :invalid_parameters, message: message}} =
               Emulation.dispatch(spec, :fetch_ticker, :rest, %{
                 exchange_module: nil,
                 params: %{symbol: @symbol}
               })

      assert String.contains?(message, "missing exchange module")
    end

    test "dispatch returns error when exchange_module key is missing" do
      exchange_id = exchange_for_method("fetchTicker")
      spec = build_spec(exchange_id, [:fetch_tickers])

      assert {:error, %CCXT.Error{type: :invalid_parameters, message: message}} =
               Emulation.dispatch(spec, :fetch_ticker, :rest, %{
                 params: %{symbol: @symbol}
               })

      assert String.contains?(message, "missing exchange module")
    end
  end

  describe "fetch_order_trades edge cases" do
    test "fetch_order_trades returns error when id is nil" do
      exchange_id = exchange_for_method("fetchOrderTrades")
      spec = build_spec(exchange_id, [:fetch_my_trades], auth_methods: [:fetch_my_trades])

      assert {:error, %CCXT.Error{type: :invalid_parameters, message: message}} =
               dispatch(spec, :fetch_order_trades,
                 params: %{symbol: @symbol},
                 credentials: @credentials
               )

      assert String.contains?(message, "requires an id argument")
    end
  end

  describe "helper edge cases" do
    test "fetch_order_trades finds trades by camelCase orderId field" do
      exchange_id = exchange_for_method("fetchOrderTrades")
      spec = build_spec(exchange_id, [:fetch_my_trades], auth_methods: [:fetch_my_trades])

      Process.put(:my_trades, [
        %{"id" => @trade_id, "orderId" => @order_id, "symbol" => @symbol},
        %{"id" => "other-trade", "orderId" => "other-order", "symbol" => @symbol}
      ])

      assert {:ok, [%{"id" => @trade_id}]} =
               dispatch(spec, :fetch_order_trades,
                 params: %{id: @order_id, symbol: @symbol},
                 credentials: @credentials
               )
    end

    test "fetch_deposit_address resolves first network when network is nil" do
      exchange_id = exchange_for_method("fetchDepositAddress")

      spec =
        build_spec(exchange_id, [:fetch_deposit_addresses_by_network],
          auth_methods: [:fetch_deposit_addresses_by_network]
        )

      Process.put(:deposit_addresses_by_network, %{
        "ERC20" => %{address: "0xfirst", network: "ERC20"},
        "TRC20" => %{address: "Tsecond", network: "TRC20"}
      })

      assert {:ok, %{address: address}} =
               dispatch(spec, :fetch_deposit_address,
                 params: %{code: @code},
                 credentials: @credentials
               )

      assert address in ["0xfirst", "Tsecond"]
    end

    test "fetch_canceled_and_closed_orders with since and limit" do
      exchange_id = exchange_for_method("fetchCanceledAndClosedOrders")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      Process.put(:orders, [
        %{id: "closed-old", status: "closed", timestamp: @timestamp_old},
        %{id: "canceled-new", status: "canceled", timestamp: @timestamp_new},
        %{id: "closed-latest", status: "closed", timestamp: @timestamp_latest},
        %{id: "open-1", status: "open", timestamp: @timestamp_new}
      ])

      assert {:ok, orders} =
               dispatch(spec, :fetch_canceled_and_closed_orders,
                 params: %{symbol: @symbol, since: @timestamp_new, limit: @limit_one},
                 credentials: @credentials
               )

      assert length(orders) == 1
      refute "open-1" in Enum.map(orders, & &1.id)
    end
  end

  # Dispatches an emulation method with sensible defaults for ExchangeStub.
  defp dispatch(spec, method, opts \\ []) do
    Emulation.dispatch(
      spec,
      method,
      :rest,
      %{
        exchange_module: ExchangeStub,
        params: Keyword.get(opts, :params, %{}),
        opts: Keyword.get(opts, :extra_opts, []),
        credentials: Keyword.get(opts, :credentials)
      }
    )
  end

  # Builds a minimal Spec struct for emulation testing.
  defp build_spec(exchange_id, endpoint_names, opts \\ []) do
    auth_methods = Keyword.get(opts, :auth_methods, [])

    endpoints =
      Enum.map(endpoint_names, fn name ->
        %{name: name, auth: name in auth_methods}
      end)

    %Spec{
      id: exchange_id,
      name: "emulation_strategies_test",
      urls: %{},
      endpoints: endpoints
    }
  end

  # Finds an exchange id that marks a method as emulated.
  defp exchange_for_method(method_name) do
    result =
      Enum.find_value(EmulatedMethods.exchanges(), fn exchange_id ->
        case EmulatedMethods.method_for(exchange_id, method_name) do
          nil -> nil
          _ -> exchange_id
        end
      end)

    case result do
      nil ->
        flunk("""
        No exchange found with emulated method #{method_name}.

        Run: mix ccxt.sync --check --emulated-methods --force
        """)

      exchange_id ->
        exchange_id
    end
  end
end
