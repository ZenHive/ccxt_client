defmodule CCXT.Order.Builder do
  @moduledoc """
  Fluent API for building and submitting orders.

  Provides a chainable interface for constructing orders with optional
  stop-loss, take-profit, and other parameters.

  ## Example

      alias CCXT.Order.Builder

      # Build and submit a limit order with stop-loss and take-profit
      Builder.new("BTC/USDT", :buy, 0.1)
      |> Builder.limit(50_000.0)
      |> Builder.stop_loss(48_000.0)
      |> Builder.take_profit(55_000.0)
      |> Builder.client_id("my-order-123")
      |> Builder.submit(CCXT.Bybit, credentials)

      # Simple market order
      Builder.new("ETH/USDT", :sell, 1.0)
      |> Builder.submit(CCXT.Binance, credentials)

  ## How It Works

  The builder accumulates configuration in a struct, then calls the
  exchange module's `create_order/7` function when `submit/3` is called.
  Stop-loss and take-profit are passed through the `params` option,
  letting the exchange's param_mappings handle exchange-specific naming.

  """

  @type side :: :buy | :sell
  @type order_type :: :market | :limit

  @type t :: %__MODULE__{
          symbol: String.t(),
          side: side(),
          amount: number(),
          order_type: order_type(),
          price: number() | nil,
          stop_loss: number() | nil,
          take_profit: number() | nil,
          client_order_id: String.t() | nil,
          params: keyword()
        }

  defstruct [
    :symbol,
    :side,
    :amount,
    :price,
    :stop_loss,
    :take_profit,
    :client_order_id,
    order_type: :market,
    params: []
  ]

  @doc """
  Creates a new order builder with the required fields.

  Defaults to a market order. Use `limit/2` to change to a limit order.

  ## Parameters

  - `symbol` - Trading pair in unified format (e.g., "BTC/USDT")
  - `side` - `:buy` or `:sell`
  - `amount` - Order quantity

  ## Example

      Builder.new("BTC/USDT", :buy, 0.1)

  """
  @spec new(String.t(), side(), number()) :: t()
  def new(symbol, side, amount) when side in [:buy, :sell] and is_number(amount) do
    %__MODULE__{
      symbol: symbol,
      side: side,
      amount: amount
    }
  end

  @doc """
  Converts the order to a limit order with the specified price.

  ## Example

      Builder.new("BTC/USDT", :buy, 0.1)
      |> Builder.limit(50_000.0)

  """
  @spec limit(t(), number()) :: t()
  def limit(%__MODULE__{} = builder, price) when is_number(price) and price > 0 do
    %{builder | order_type: :limit, price: price}
  end

  @doc """
  Sets a stop-loss price for the order.

  The stop-loss is passed through the `params` option. Exchange-specific
  parameter naming is handled by the exchange's param_mappings.

  ## Example

      Builder.new("BTC/USDT", :buy, 0.1)
      |> Builder.stop_loss(48_000.0)

  """
  @spec stop_loss(t(), number()) :: t()
  def stop_loss(%__MODULE__{} = builder, price) when is_number(price) and price > 0 do
    %{builder | stop_loss: price}
  end

  @doc """
  Sets a take-profit price for the order.

  The take-profit is passed through the `params` option. Exchange-specific
  parameter naming is handled by the exchange's param_mappings.

  ## Example

      Builder.new("BTC/USDT", :buy, 0.1)
      |> Builder.take_profit(55_000.0)

  """
  @spec take_profit(t(), number()) :: t()
  def take_profit(%__MODULE__{} = builder, price) when is_number(price) and price > 0 do
    %{builder | take_profit: price}
  end

  @doc """
  Sets a client order ID for the order.

  Client order IDs allow you to track orders with your own identifiers.

  ## Example

      Builder.new("BTC/USDT", :buy, 0.1)
      |> Builder.client_id("my-order-123")

  """
  @spec client_id(t(), String.t()) :: t()
  def client_id(%__MODULE__{} = builder, id) when is_binary(id) do
    %{builder | client_order_id: id}
  end

  @doc """
  Merges additional parameters into the order.

  Use this for exchange-specific parameters not covered by the builder.

  ## Example

      Builder.new("BTC/USDT", :buy, 0.1)
      |> Builder.params(timeInForce: "GTC", reduceOnly: true)

  """
  @spec params(t(), keyword()) :: t()
  def params(%__MODULE__{} = builder, extra_params) when is_list(extra_params) do
    merged = Keyword.merge(builder.params, extra_params)
    %{builder | params: merged}
  end

  @doc """
  Submits the order to the exchange.

  Calls the exchange module's `create_order` function with the accumulated
  configuration.

  ## Parameters

  - `builder` - The order builder struct
  - `exchange_module` - The exchange module (e.g., `CCXT.Bybit`)
  - `credentials` - `CCXT.Credentials` struct for authentication

  ## Returns

  - `{:ok, order}` - The created order
  - `{:error, error}` - An error occurred

  ## Example

      Builder.new("BTC/USDT", :buy, 0.1)
      |> Builder.limit(50_000.0)
      |> Builder.submit(CCXT.Bybit, credentials)

  """
  @spec submit(t(), module(), CCXT.Credentials.t()) :: {:ok, map()} | {:error, CCXT.Error.t()}
  def submit(%__MODULE__{} = builder, exchange_module, credentials) do
    # Build the params keyword list with SL/TP and extra params
    opts = build_opts(builder)

    # Call create_order with the accumulated configuration
    # Signature: create_order(credentials, symbol, type, side, amount, price \\ nil, opts \\ [])
    exchange_module.create_order(
      credentials,
      builder.symbol,
      Atom.to_string(builder.order_type),
      Atom.to_string(builder.side),
      builder.amount,
      builder.price,
      opts
    )
  end

  @doc """
  Returns the order configuration as a map (for inspection/debugging).

  ## Example

      Builder.new("BTC/USDT", :buy, 0.1)
      |> Builder.limit(50_000.0)
      |> Builder.to_map()
      # => %{symbol: "BTC/USDT", side: :buy, amount: 0.1, ...}

  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = builder) do
    Map.from_struct(builder)
  end

  # Build the opts keyword list for create_order
  @doc false
  defp build_opts(%__MODULE__{} = builder) do
    # Collect SL/TP/clientOrderId, filter nils, merge with user params
    # Keys use camelCase to match exchange API naming conventions (stopLoss, takeProfit, etc.)
    params =
      [
        {:stopLoss, builder.stop_loss},
        {:takeProfit, builder.take_profit},
        {:clientOrderId, builder.client_order_id}
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Keyword.merge(builder.params)

    case params do
      [] -> []
      params -> [params: params]
    end
  end
end
