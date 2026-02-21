defmodule CCXT.Types.OrderBook do
  @moduledoc """
  Unified order book (market depth) data from an exchange.

  Contains sorted bid and ask price levels, each as `[price, amount]` pairs.
  Bids are sorted highest-first, asks lowest-first.
  See `CCXT.Types.Schema.OrderBook` for fields with descriptions.

  ## Helpers

  - `best_bid/1` - Highest bid price
  - `best_ask/1` - Lowest ask price
  - `spread/1` - Difference between best ask and best bid

  ## Example

      {:ok, book} = MyExchange.fetch_order_book("BTC/USDT")
      OrderBook.best_bid(book)  # 49999.0
      OrderBook.best_ask(book)  # 50001.0
      OrderBook.spread(book)    # 2.0
  """

  use CCXT.Types.Schema.OrderBook

  alias CCXT.Safe

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    book = super(map)
    bids = coerce_levels(book.bids)
    asks = coerce_levels(book.asks)
    raw = book.raw || Map.get(map, "info") || Map.get(map, :info) || map

    %{book | bids: bids, asks: asks, raw: raw}
  end

  @doc false
  # Converts string price/amount values to numbers in bid/ask level pairs.
  defp coerce_levels(nil), do: []

  defp coerce_levels(levels) when is_list(levels) do
    Enum.map(levels, fn
      [price, amount] -> [Safe.to_number(price), Safe.to_number(amount)]
      other -> other
    end)
  end

  defp coerce_levels(_), do: []

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
