defmodule CCXT.Types.Ticker do
  @moduledoc "Auto-generated from priv/ccxt/ts/src/base/types.ts."

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
