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
  | `create_order` | `CCXT.Types.Order` |
  | `cancel_order` | `CCXT.Types.Order` |

  """

  # Maps response type atoms to their corresponding modules
  @type_modules %{
    ticker: CCXT.Types.Ticker,
    order: CCXT.Types.Order,
    position: CCXT.Types.Position,
    balance: CCXT.Types.Balance,
    order_book: CCXT.Types.OrderBook,
    trade: CCXT.Types.Trade
  }

  # List types return arrays of the singular type
  @list_types [:tickers, :orders, :positions, :trades]

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
  @spec coerce(term(), response_type(), keyword()) :: term()
  def coerce(data, nil, _opts), do: data

  def coerce(data, type, opts) do
    if Keyword.get(opts, :raw, false) do
      data
    else
      coerce_typed(data, type)
    end
  end

  # Internal typed coercion after raw check
  @doc false
  @spec coerce_typed(term(), response_type()) :: term()
  defp coerce_typed(data, type) when type in @list_types and is_list(data) do
    singular = singularize(type)
    Enum.map(data, &coerce_single(&1, singular))
  end

  defp coerce_typed(data, type) when is_map(data) do
    coerce_single(data, type)
  end

  # Handle unexpected data types gracefully - return unchanged
  defp coerce_typed(data, _type), do: data

  @doc false
  # Coerces a single map to its corresponding struct.
  # Looks up the type in @type_modules and calls from_map/1 on the module.
  # Returns data unchanged if type is not found or data is not a map.
  # The `when not is_nil(module)` guard is defensive - while currently redundant
  # (nil is caught above), it prevents silent failures if @type_modules changes
  # to include nil values in the future.
  @spec coerce_single(map(), atom()) :: struct() | map()
  defp coerce_single(data, type) when is_map(data) do
    case Map.get(@type_modules, type) do
      nil -> data
      module when not is_nil(module) -> module.from_map(data)
    end
  end

  defp coerce_single(data, _type), do: data

  @doc false
  # Converts plural list types to their singular form for struct lookup.
  # Only called for types in @list_types, so no fallback clause needed.
  @spec singularize(atom()) :: atom()
  defp singularize(:tickers), do: :ticker
  defp singularize(:orders), do: :order
  defp singularize(:positions), do: :position
  defp singularize(:trades), do: :trade

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
  @spec infer_response_type(atom()) :: response_type()
  def infer_response_type(:fetch_ticker), do: :ticker
  def infer_response_type(:fetch_tickers), do: :tickers
  def infer_response_type(:fetch_order), do: :order
  def infer_response_type(:fetch_orders), do: :orders
  def infer_response_type(:fetch_open_orders), do: :orders
  def infer_response_type(:fetch_closed_orders), do: :orders
  def infer_response_type(:fetch_my_trades), do: :trades
  def infer_response_type(:fetch_trades), do: :trades
  def infer_response_type(:fetch_position), do: :position
  def infer_response_type(:fetch_positions), do: :positions
  def infer_response_type(:fetch_balance), do: :balance
  def infer_response_type(:fetch_order_book), do: :order_book
  def infer_response_type(:create_order), do: :order
  def infer_response_type(:cancel_order), do: :order
  def infer_response_type(:edit_order), do: :order
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
end
