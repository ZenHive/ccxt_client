defmodule CCXT.Types.OrderBook do
  @moduledoc "Auto-generated from priv/ccxt/ts/src/base/types.ts."

  use CCXT.Types.Schema.OrderBook

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    book = super(map)
    bids = book.bids || []
    asks = book.asks || []
    raw = book.raw || map

    %{book | bids: bids, asks: asks, raw: raw}
  end

  @spec best_bid(t()) :: number() | nil
  def best_bid(%__MODULE__{bids: [[price | _] | _]}), do: price
  def best_bid(_), do: nil

  @spec best_ask(t()) :: number() | nil
  def best_ask(%__MODULE__{asks: [[price | _] | _]}), do: price
  def best_ask(_), do: nil

  @spec spread(t()) :: number() | nil
  def spread(book) do
    case {best_bid(book), best_ask(book)} do
      {bid, ask} when is_number(bid) and is_number(ask) -> ask - bid
      _ -> nil
    end
  end
end
