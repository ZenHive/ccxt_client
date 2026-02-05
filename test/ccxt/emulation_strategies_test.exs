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
  @code "BTC"
  @network "ERC20"

  @timestamp_old 1_600_000_000_000
  @timestamp_new 1_700_000_000_000
  @min_amount 1
  @max_amount 10

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
               Emulation.dispatch(
                 spec,
                 :fetch_closed_orders,
                 :rest,
                 %{
                   exchange_module: ExchangeStub,
                   params: %{symbol: @symbol, since: @timestamp_new, limit: nil},
                   opts: [],
                   credentials: @credentials
                 }
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
               Emulation.dispatch(
                 spec,
                 :fetch_ticker,
                 :rest,
                 %{
                   exchange_module: ExchangeStub,
                   params: %{symbol: @symbol},
                   opts: [],
                   credentials: nil
                 }
               )
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
               Emulation.dispatch(
                 spec,
                 :fetch_trading_limits,
                 :rest,
                 %{
                   exchange_module: ExchangeStub,
                   params: %{symbols: [@symbol]},
                   opts: [],
                   credentials: nil
                 }
               )
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
               Emulation.dispatch(
                 spec,
                 :fetch_deposit_address,
                 :rest,
                 %{
                   exchange_module: ExchangeStub,
                   params: %{code: @code, network: @network},
                   opts: [],
                   credentials: @credentials
                 }
               )
    end

    test "fetch_order returns not_found when missing" do
      exchange_id = exchange_for_method("fetchOrder")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      Process.put(:orders, [%{id: @order_id, status: "open", timestamp: @timestamp_new}])

      assert {:error, %CCXT.Error{type: :order_not_found}} =
               Emulation.dispatch(
                 spec,
                 :fetch_order,
                 :rest,
                 %{
                   exchange_module: ExchangeStub,
                   params: %{id: @missing_order_id, symbol: @symbol},
                   opts: [],
                   credentials: @credentials
                 }
               )
    end

    test "fetch_my_trades flattens trades from orders" do
      exchange_id = exchange_for_method("fetchMyTrades")
      spec = build_spec(exchange_id, [:fetch_orders], auth_methods: [:fetch_orders])

      Process.put(:orders, [
        %{id: @order_id, trades: [%{id: @trade_id, order_id: @order_id, symbol: @symbol}]}
      ])

      assert {:ok, [%{id: @trade_id, order_id: @order_id}]} =
               Emulation.dispatch(
                 spec,
                 :fetch_my_trades,
                 :rest,
                 %{
                   exchange_module: ExchangeStub,
                   params: %{symbol: @symbol},
                   opts: [],
                   credentials: @credentials
                 }
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
               Emulation.dispatch(
                 spec,
                 :fetch_order_trades,
                 :rest,
                 %{
                   exchange_module: ExchangeStub,
                   params: %{id: @order_id, symbol: @symbol},
                   opts: [],
                   credentials: @credentials
                 }
               )
    end

    test "fetch_leverage selects a symbol entry from fetch_leverages" do
      exchange_id = exchange_for_method("fetchLeverage")
      spec = build_spec(exchange_id, [:fetch_leverages], auth_methods: [:fetch_leverages])

      Process.put(:leverages, %{@symbol => %{symbol: @symbol, leverage: "5"}})

      assert {:ok, %{symbol: @symbol}} =
               Emulation.dispatch(
                 spec,
                 :fetch_leverage,
                 :rest,
                 %{
                   exchange_module: ExchangeStub,
                   params: %{symbol: @symbol},
                   opts: [],
                   credentials: @credentials
                 }
               )
    end
  end

  @doc false
  # Builds a minimal Spec struct for emulation testing.
  @spec build_spec(String.t(), [atom()], keyword()) :: Spec.t()
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

  @doc false
  # Finds an exchange id that marks a method as emulated.
  @spec exchange_for_method(String.t()) :: String.t()
  defp exchange_for_method(method_name) do
    EmulatedMethods.exchanges()
    |> Enum.find_value(fn exchange_id ->
      case EmulatedMethods.method_for(exchange_id, method_name) do
        nil -> nil
        _ -> exchange_id
      end
    end)
    |> case do
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
