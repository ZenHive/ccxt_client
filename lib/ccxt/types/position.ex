defmodule CCXT.Types.Position do
  @moduledoc "Auto-generated from priv/ccxt/ts/src/base/types.ts."

  use CCXT.Types.Schema.Position

  alias CCXT.Types.Helpers

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    position = super(map)

    entry_price = position.entry_price || Helpers.get_camel_value(map, :entry_price, :entryPrice)
    mark_price = position.mark_price || Helpers.get_camel_value(map, :mark_price, :markPrice)

    liquidation_price =
      position.liquidation_price || Helpers.get_camel_value(map, :liquidation_price, :liquidationPrice)

    unrealized_pnl = position.unrealized_pnl || Helpers.get_camel_value(map, :unrealized_pnl, :unrealizedPnl)

    margin_mode =
      position.margin_mode
      |> Kernel.||(Helpers.get_camel_value(map, :margin_mode, :marginMode))
      |> Helpers.normalize_margin_mode()

    side = Helpers.normalize_position_side(position.side)

    %{
      position
      | entry_price: entry_price,
        mark_price: mark_price,
        liquidation_price: liquidation_price,
        unrealized_pnl: unrealized_pnl,
        margin_mode: margin_mode,
        side: side
    }
  end

  @spec long?(t()) :: boolean()
  def long?(%__MODULE__{side: :long}), do: true
  def long?(_), do: false

  @spec short?(t()) :: boolean()
  def short?(%__MODULE__{side: :short}), do: true
  def short?(_), do: false

  @spec profitable?(t()) :: boolean()
  def profitable?(%__MODULE__{unrealized_pnl: pnl}) when is_number(pnl) and pnl > 0, do: true
  def profitable?(_), do: false
end
