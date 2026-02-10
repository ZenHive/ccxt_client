defmodule CCXT.Types.Ticker do
  @moduledoc """
  Unified ticker/price data from an exchange.

  Contains the latest price, volume, and 24h change data for a trading pair.
  See `CCXT.Types.Schema.Ticker` for the full field list with descriptions.

  ## Example

      {:ok, ticker} = MyExchange.fetch_ticker("BTC/USDT")
      ticker.last        # last traded price
      ticker.percentage  # 24h price change %
      ticker.base_volume # 24h volume in base currency
  """

  use CCXT.Types.Schema.Ticker

  alias CCXT.Types.Helpers

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    ticker = super(map)

    bid_volume = ticker.bid_volume || Helpers.get_camel_value(map, :bid_volume, :bidVolume)
    ask_volume = ticker.ask_volume || Helpers.get_camel_value(map, :ask_volume, :askVolume)
    base_volume = ticker.base_volume || Helpers.get_camel_value(map, :base_volume, :baseVolume)
    quote_volume = ticker.quote_volume || Helpers.get_camel_value(map, :quote_volume, :quoteVolume)
    raw = ticker.raw || map

    %{
      ticker
      | bid_volume: bid_volume,
        ask_volume: ask_volume,
        base_volume: base_volume,
        quote_volume: quote_volume,
        raw: raw
    }
  end
end
