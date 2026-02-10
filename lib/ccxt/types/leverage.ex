defmodule CCXT.Types.Leverage do
  @moduledoc "Auto-generated from priv/ccxt/ts/src/base/types.ts."

  use CCXT.Types.Schema.Leverage

  alias CCXT.Types.Helpers

  @doc false
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    result = super(map)

    %{result | margin_mode: Helpers.normalize_margin_mode(result.margin_mode)}
  end
end
