defmodule CCXT.Types.Liquidation do
  @moduledoc "Auto-generated from priv/ccxt/ts/src/base/types.ts."

  use CCXT.Types.Schema.Liquidation

  alias CCXT.Types.Helpers

  @doc false
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    result = super(map)

    %{result | side: Helpers.normalize_side(result.side)}
  end
end
