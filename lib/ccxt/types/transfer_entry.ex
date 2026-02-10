defmodule CCXT.Types.TransferEntry do
  @moduledoc "Auto-generated from priv/ccxt/ts/src/base/types.ts."

  use CCXT.Types.Schema.TransferEntry

  alias CCXT.Types.Helpers

  @doc false
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    result = super(map)

    %{result | status: Helpers.normalize_transfer_status(result.status)}
  end
end
