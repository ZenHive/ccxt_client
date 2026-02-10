defmodule CCXT.Types.Order do
  @moduledoc """
  Unified order data from an exchange.

  Represents an order's full lifecycle including placement, fills, and status.
  Status is normalized to atoms (`:open`, `:closed`, `:canceled`), and side/type
  are also normalized. See `CCXT.Types.Schema.Order` for fields with descriptions.

  ## Helpers

  - `open?/1` - Whether the order is still open
  - `filled?/1` - Whether the order is fully filled (status = :closed)
  - `fill_percentage/1` - Percentage of the order that has been filled

  ## Example

      {:ok, order} = MyExchange.create_order("BTC/USDT", "limit", "buy", 0.001, 50000.0)
      order.status       # :open
      Order.open?(order)  # true
  """

  use CCXT.Types.Schema.Order

  alias CCXT.Types.Helpers

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    order = super(map)

    %{
      order
      | type: Helpers.normalize_order_type(order.type),
        side: Helpers.normalize_side(order.side),
        status: Helpers.normalize_status(order.status)
    }
  end

  @spec open?(t()) :: boolean()
  def open?(%__MODULE__{status: :open}), do: true
  def open?(_), do: false

  @spec filled?(t()) :: boolean()
  def filled?(%__MODULE__{status: :closed}), do: true
  def filled?(_), do: false

  @spec fill_percentage(t()) :: float()
  def fill_percentage(%__MODULE__{amount: amount, filled: filled}) when is_number(amount) and amount > 0 do
    (filled || 0) / amount * 100
  end

  def fill_percentage(_), do: 0.0
end
