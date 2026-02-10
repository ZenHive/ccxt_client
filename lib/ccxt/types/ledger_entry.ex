defmodule CCXT.Types.LedgerEntry do
  @moduledoc "Auto-generated from priv/ccxt/ts/src/base/types.ts."

  use CCXT.Types.Schema.LedgerEntry

  alias CCXT.Types.Helpers

  @doc false
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    result = super(map)

    %{
      result
      | status: Helpers.normalize_transfer_status(result.status),
        type: Helpers.to_atom_safe(result.type),
        direction: Helpers.normalize_direction(result.direction)
    }
  end
end
