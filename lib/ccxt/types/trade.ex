defmodule CCXT.Types.Trade do
  @moduledoc """
  Unified trade/fill data from an exchange.

  Represents a single trade execution. Side is normalized to atoms (`:buy`, `:sell`)
  and taker_or_maker to (`:taker`, `:maker`). Cost is auto-computed if missing.
  See `CCXT.Types.Schema.Trade` for fields with descriptions.

  ## Example

      {:ok, trades} = MyExchange.fetch_trades("BTC/USDT")
      trade = hd(trades)
      trade.price  # execution price
      trade.side   # :buy or :sell
      trade.cost   # price * amount
  """

  use CCXT.Types.Schema.Trade

  alias CCXT.Types.Helpers

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    trade = super(map)

    side = Helpers.normalize_side(trade.side)
    taker_or_maker = Helpers.normalize_taker_or_maker(trade.taker_or_maker)
    order_id = trade.order_id || Helpers.get_camel_value(map, :order_id, :orderId)
    cost = trade.cost || compute_cost(trade.price, trade.amount)
    fee = normalize_fee(trade.fee)

    %{
      trade
      | side: side,
        taker_or_maker: taker_or_maker,
        order_id: order_id,
        cost: cost,
        fee: fee
    }
  end

  defp compute_cost(price, amount) when is_number(price) and is_number(amount), do: price * amount
  defp compute_cost(_, _), do: nil

  defp normalize_fee(nil), do: nil

  defp normalize_fee(fee) when is_map(fee) do
    currency = Map.get(fee, :currency) || Map.get(fee, "currency")
    cost = Map.get(fee, :cost) || Map.get(fee, "cost")
    rate = Map.get(fee, :rate) || Map.get(fee, "rate")

    if is_nil(currency) and is_nil(cost) and is_nil(rate) do
      fee
    else
      %{currency: currency, cost: cost, rate: rate}
    end
  end
end
