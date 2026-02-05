defmodule CCXT.Types.Order do
  @moduledoc "Auto-generated from priv/ccxt/ts/src/base/types.ts."

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
