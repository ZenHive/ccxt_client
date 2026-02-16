defmodule CCXT.WS.Contract do
  @moduledoc """
  Declarative contracts for WS payload families.

  Defines the canonical output shape, required fields, update semantics, and
  validation rules for each WS payload family. W13-W16 implement the runtime
  normalization; this module defines **what** the output looks like.

  ## Payload Families

  | Family | Type | Shape | Auth |
  |--------|------|-------|------|
  | `:watch_ticker` | `Ticker.t()` | single | no |
  | `:watch_trades` | `[Trade.t()]` | list | no |
  | `:watch_order_book` | `OrderBook.t()` | single | no |
  | `:watch_ohlcv` | `[%OHLCVBar{}]` | list | no |
  | `:watch_orders` | `[Order.t()]` | list | yes |
  | `:watch_balance` | `Balance.t()` | single | yes |
  | `:watch_positions` | `[Position.t()]` | list | yes |

  ## Same Types as REST

  WS normalization produces the same unified types as REST. `watch_ticker`
  produces `CCXT.Types.Ticker.t()`, identical to `fetch_ticker`. The `:raw`
  field on each struct preserves the original exchange payload.

  ## Update Semantics

  Each family defines how successive messages should be interpreted:

  - `:snapshot` — Each message is a complete replacement
  - `:append` — Each message contains new items to append
  - `:snapshot_and_delta` — First message is snapshot, subsequent are deltas
  - `:update_in_place` — Each message updates the current value
  - `:update` — Each message contains changed items (merge by key)
  - `:partial_or_full` — Exchange may send partial or full updates

  ## Envelope Patterns (Reference for W13)

  Exchange messages wrap payload data in different envelope structures.
  See `@envelope_patterns` for the 5 documented patterns.
  """

  alias CCXT.Types.Balance
  alias CCXT.Types.OHLCVBar
  alias CCXT.Types.Order
  alias CCXT.Types.OrderBook
  alias CCXT.Types.Position
  alias CCXT.Types.Ticker
  alias CCXT.Types.Trade

  @typedoc "WS payload family atom"
  @type family ::
          :watch_ticker
          | :watch_trades
          | :watch_order_book
          | :watch_ohlcv
          | :watch_orders
          | :watch_balance
          | :watch_positions

  @typedoc "How successive WS messages should be interpreted"
  @type update_semantic ::
          :snapshot
          | :append
          | :snapshot_and_delta
          | :update_in_place
          | :update
          | :partial_or_full

  @typedoc "Whether the family produces a single item or a list"
  @type result_shape :: :single | :list

  @typedoc """
  Intermediate representation between envelope extraction and field parsing.
  Produced by W13's envelope extractor, consumed by W14's normalizer.
  """
  @type extracted_payload :: %{
          family: family(),
          symbol: String.t() | nil,
          data: map() | [map()] | list(),
          update_type: :snapshot | :delta | nil,
          timestamp: integer() | nil,
          raw_envelope: map()
        }

  @typedoc "Contract violation found during validation"
  @type violation ::
          {:wrong_type, expected :: module(), got :: term()}
          | {:wrong_shape, expected :: result_shape(), got :: term()}
          | {:missing_field, field :: atom()}
          | {:wrong_element_type, index :: non_neg_integer(), expected :: module(), got :: term()}
          | {:invalid_ohlcv, reason :: atom()}

  # -- Family Specifications --------------------------------------------------

  @family_specs %{
    watch_ticker: %{
      type_module: Ticker,
      result_shape: :single,
      update_semantics: :snapshot,
      coercion_type: :ticker,
      auth_required: false,
      required_fields: [:symbol],
      optional_fields: [
        :raw,
        :timestamp,
        :datetime,
        :high,
        :low,
        :bid,
        :bid_volume,
        :ask,
        :ask_volume,
        :vwap,
        :open,
        :close,
        :last,
        :previous_close,
        :change,
        :percentage,
        :average,
        :quote_volume,
        :base_volume,
        :index_price,
        :mark_price
      ]
    },
    watch_trades: %{
      type_module: Trade,
      result_shape: :list,
      update_semantics: :append,
      coercion_type: :trade,
      auth_required: false,
      required_fields: [:symbol, :price, :amount, :timestamp],
      optional_fields: [:raw, :id, :order_id, :datetime, :type, :side, :taker_or_maker, :cost, :fee]
    },
    watch_order_book: %{
      type_module: OrderBook,
      result_shape: :single,
      update_semantics: :snapshot_and_delta,
      coercion_type: :order_book,
      auth_required: false,
      required_fields: [:bids, :asks],
      optional_fields: [:symbol, :raw, :datetime, :timestamp, :nonce]
    },
    watch_ohlcv: %{
      type_module: OHLCVBar,
      result_shape: :list,
      update_semantics: :update_in_place,
      coercion_type: :ohlcv,
      auth_required: false,
      required_fields: [:timestamp],
      optional_fields: [:open, :high, :low, :close, :volume]
    },
    watch_orders: %{
      type_module: Order,
      result_shape: :list,
      update_semantics: :update,
      coercion_type: :order,
      auth_required: true,
      required_fields: [:id, :symbol, :status],
      optional_fields: [
        :raw,
        :client_order_id,
        :datetime,
        :timestamp,
        :last_trade_timestamp,
        :last_update_timestamp,
        :type,
        :time_in_force,
        :side,
        :price,
        :average,
        :amount,
        :filled,
        :remaining,
        :stop_price,
        :trigger_price,
        :take_profit_price,
        :stop_loss_price,
        :cost,
        :trades,
        :fee,
        :reduce_only,
        :post_only
      ]
    },
    watch_balance: %{
      type_module: Balance,
      result_shape: :single,
      update_semantics: :partial_or_full,
      coercion_type: :balance,
      auth_required: true,
      required_fields: [],
      optional_fields: [:free, :used, :total, :timestamp, :datetime, :raw]
    },
    watch_positions: %{
      type_module: Position,
      result_shape: :list,
      update_semantics: :update,
      coercion_type: :position,
      auth_required: true,
      required_fields: [:symbol],
      optional_fields: [
        :id,
        :raw,
        :timestamp,
        :datetime,
        :contracts,
        :contract_size,
        :side,
        :notional,
        :leverage,
        :unrealized_pnl,
        :realized_pnl,
        :collateral,
        :entry_price,
        :mark_price,
        :liquidation_price,
        :margin_mode,
        :hedged,
        :maintenance_margin,
        :maintenance_margin_percentage,
        :initial_margin,
        :initial_margin_percentage,
        :margin_ratio,
        :last_update_timestamp,
        :last_price,
        :stop_loss_price,
        :take_profit_price,
        :percentage,
        :margin
      ]
    }
  }

  @families Map.keys(@family_specs)

  # -- Envelope Patterns (Reference for W13) ----------------------------------

  @envelope_patterns [
    %{
      name: :topic_data,
      exchanges: [:bybit, :bitmex],
      family_field: "topic",
      data_field: "data"
    },
    %{
      name: :jsonrpc_subscription,
      exchanges: [:deribit],
      family_field: ["params", "channel"],
      data_field: ["params", "data"]
    },
    %{
      name: :arg_data,
      exchanges: [:okx],
      family_field: ["arg", "channel"],
      data_field: "data"
    },
    %{
      name: :channel_result,
      exchanges: [:gate],
      family_field: "channel",
      data_field: "result"
    },
    %{
      name: :flat,
      exchanges: [:binance],
      family_field: "e",
      data_field: :self
    }
  ]

  # -- Public API --------------------------------------------------------------

  @doc "Returns all 7 WS payload family atoms."
  @spec families() :: [family()]
  def families, do: @families

  @doc """
  Returns the full contract specification for a family.

  Keys: `:type_module`, `:result_shape`, `:update_semantics`, `:coercion_type`,
  `:auth_required`, `:required_fields`, `:optional_fields`.
  """
  @spec family_spec(family()) :: map()
  def family_spec(family) when family in @families do
    Map.fetch!(@family_specs, family)
  end

  @doc "Returns the fields that must be non-nil after normalization."
  @spec required_fields(family()) :: [atom()]
  def required_fields(family) when family in @families do
    @family_specs |> Map.fetch!(family) |> Map.fetch!(:required_fields)
  end

  @doc "Returns the fields that may be nil after normalization."
  @spec optional_fields(family()) :: [atom()]
  def optional_fields(family) when family in @families do
    @family_specs |> Map.fetch!(family) |> Map.fetch!(:optional_fields)
  end

  @doc "Returns the `ResponseCoercer` type atom for this family, or nil for OHLCV."
  @spec coercion_type(family()) :: atom() | nil
  def coercion_type(family) when family in @families do
    @family_specs |> Map.fetch!(family) |> Map.fetch!(:coercion_type)
  end

  @doc "Returns how successive WS messages should be interpreted."
  @spec update_semantics(family()) :: update_semantic()
  def update_semantics(family) when family in @families do
    @family_specs |> Map.fetch!(family) |> Map.fetch!(:update_semantics)
  end

  @doc "Returns whether this family requires authentication."
  @spec auth_required?(family()) :: boolean()
  def auth_required?(family) when family in @families do
    @family_specs |> Map.fetch!(family) |> Map.fetch!(:auth_required)
  end

  @doc "Returns the documented envelope patterns (reference for W13)."
  @spec envelope_patterns() :: [map()]
  def envelope_patterns, do: @envelope_patterns

  @doc """
  Validates a normalized result against its family contract.

  Returns `{:ok, result}` if valid, `{:error, violations}` with specific
  violation tuples if not. Never silently converts missing data.

  ## Examples

      iex> ticker = %CCXT.Types.Ticker{symbol: "BTC/USDT", last: 42000.0}
      iex> {:ok, ^ticker} = CCXT.WS.Contract.validate(:watch_ticker, ticker)

      iex> {:error, violations} = CCXT.WS.Contract.validate(:watch_ticker, %{})
      iex> {:wrong_type, CCXT.Types.Ticker, %{}} in violations
      true

  """
  @spec validate(family(), term()) :: {:ok, term()} | {:error, [violation()]}
  def validate(family, result) when family in @families do
    spec = Map.fetch!(@family_specs, family)
    violations = do_validate(spec, result)

    case violations do
      [] -> {:ok, result}
      _ -> {:error, violations}
    end
  end

  # -- Validation Internals ----------------------------------------------------

  defp do_validate(%{type_module: mod, result_shape: :single} = spec, result) do
    validate_single(mod, spec.required_fields, result)
  end

  defp do_validate(%{type_module: mod, result_shape: :list} = spec, result) do
    validate_list(mod, spec.required_fields, result)
  end

  defp validate_single(mod, required_fields, result) do
    type_violations = validate_struct_type(mod, result)

    if type_violations == [] do
      validate_required_fields(required_fields, result)
    else
      type_violations
    end
  end

  defp validate_list(mod, required_fields, result) when is_list(result) do
    result
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, idx} ->
      case validate_struct_type(mod, item) do
        [] ->
          validate_required_fields(required_fields, item)

        _type_violations ->
          [{:wrong_element_type, idx, mod, item}]
      end
    end)
  end

  defp validate_list(_mod, _required_fields, result) do
    [{:wrong_shape, :list, result}]
  end

  defp validate_struct_type(mod, %{__struct__: actual_mod}) when actual_mod == mod, do: []
  defp validate_struct_type(mod, result), do: [{:wrong_type, mod, result}]

  defp validate_required_fields(required_fields, struct) do
    Enum.flat_map(required_fields, fn field ->
      value = Map.get(struct, field)

      if is_nil(value) do
        [{:missing_field, field}]
      else
        []
      end
    end)
  end
end
