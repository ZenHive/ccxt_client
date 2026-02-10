defmodule CCXT.Types.Transaction do
  @moduledoc "Auto-generated from priv/ccxt/ts/src/base/types.ts."

  use CCXT.Types.Schema.Transaction

  alias CCXT.Types.Helpers

  @doc false
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    result = super(map)

    %{
      result
      | status: Helpers.normalize_transfer_status(result.status),
        type: Helpers.normalize_transaction_type(result.type)
    }
  end

  @doc false
  @spec deposit?(t()) :: boolean()
  def deposit?(%__MODULE__{type: :deposit}), do: true
  def deposit?(_), do: false

  @doc false
  @spec withdrawal?(t()) :: boolean()
  def withdrawal?(%__MODULE__{type: :withdrawal}), do: true
  def withdrawal?(_), do: false

  @doc false
  @spec pending?(t()) :: boolean()
  def pending?(%__MODULE__{status: :pending}), do: true
  def pending?(_), do: false
end
