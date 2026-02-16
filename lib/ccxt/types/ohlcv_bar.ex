defmodule CCXT.Types.OHLCVBar do
  @moduledoc """
  Canonical OHLCV bar struct.

  Canonical OHLCV bar struct used by ccxt_client's normalization layer.
  In ccxt_ex, REST/WS outputs return raw maps; ccxt_client coerces to this struct.

  ## Fields

  - `timestamp` — Bar open time in milliseconds (integer, required)
  - `open` — Opening price (float or nil)
  - `high` — Highest price (float or nil)
  - `low` — Lowest price (float or nil)
  - `close` — Closing price (float or nil)
  - `volume` — Trading volume (float or nil)
  """

  @type t :: %__MODULE__{
          timestamp: integer(),
          open: float() | nil,
          high: float() | nil,
          low: float() | nil,
          close: float() | nil,
          volume: float() | nil
        }

  defstruct [:timestamp, :open, :high, :low, :close, :volume]

  @doc """
  Builds an OHLCVBar from a pre-coerced 6-element list.

  Expects exactly `[timestamp, open, high, low, close, volume]` where
  timestamp is an integer and OHLCV values are floats or nil.
  Called internally after coercion (OHLCV module moved to ccxt_client).
  """
  @spec from_list([integer() | float() | nil]) :: t()
  def from_list([ts, o, h, l, c, v]) when is_integer(ts) do
    %__MODULE__{timestamp: ts, open: o, high: h, low: l, close: c, volume: v}
  end
end
