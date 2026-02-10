defmodule CCXT.ResponseParser do
  @moduledoc """
  Parses raw exchange responses using compiled mapping tables.

  Converts exchange-specific field names (e.g., `"askPrice"`) to unified field names
  (e.g., `"ask"`) that `from_map/1` expects, applying type coercion via `CCXT.Safe`.

  ## How It Works

  Each mapping is a list of instruction tuples:

      [{:ask, :number, ["askPrice"]}, {:bid, :number, ["bidPrice"]}, ...]

  For each instruction, `parse_single/2`:
  1. Looks up the source key(s) in the raw exchange data
  2. Applies the coercion function (via `CCXT.Safe`)
  3. Writes the result using the unified key name that `from_map/1` expects

  The parsed fields are merged into the original data, so unmapped fields
  pass through unchanged.

  ## Integration

  Called by `CCXT.ResponseCoercer.coerce/4` before `from_map/1`:

      Raw exchange data → parse_single → Unified map → from_map/1 → Struct

  """

  alias CCXT.Safe

  @type instruction :: {atom(), atom(), [String.t()]}

  # Schema modules whose fields need snake_case -> camelCase key mapping
  @parser_schemas [
    CCXT.Types.Schema.Ticker,
    CCXT.Types.Schema.Trade,
    CCXT.Types.Schema.Order,
    CCXT.Types.Schema.Position,
    CCXT.Types.Schema.FundingRate,
    CCXT.Types.Schema.Transaction,
    CCXT.Types.Schema.TransferEntry,
    CCXT.Types.Schema.DepositAddress,
    CCXT.Types.Schema.LedgerEntry,
    CCXT.Types.Schema.Leverage,
    CCXT.Types.Schema.TradingFeeInterface,
    CCXT.Types.Schema.DepositWithdrawFee,
    CCXT.Types.Schema.MarginModification,
    CCXT.Types.Schema.OpenInterest,
    CCXT.Types.Schema.MarginMode,
    CCXT.Types.Schema.Liquidation,
    CCXT.Types.Schema.FundingRateHistory,
    CCXT.Types.Schema.BorrowInterest,
    CCXT.Types.Schema.CrossBorrowRate,
    CCXT.Types.Schema.Conversion,
    CCXT.Types.Schema.Greeks,
    CCXT.Types.Schema.Account,
    CCXT.Types.Schema.Option,
    CCXT.Types.Schema.FundingHistory,
    CCXT.Types.Schema.IsolatedBorrowRate,
    CCXT.Types.Schema.LastPrice,
    CCXT.Types.Schema.LongShortRatio,
    CCXT.Types.Schema.LeverageTier
  ]

  # Derived at compile time from schema @fields attributes.
  # Maps field atoms to their source strings where they differ
  # (e.g., :bid_volume -> "bidVolume"). Simple names like :ask -> "ask"
  # are handled by the Atom.to_string fallback in to_unified_key/1.
  @field_to_source (for schema <- @parser_schemas,
                        %{name: name, source: source} <-
                          :attributes |> schema.__info__() |> Keyword.get(:fields, []),
                        Atom.to_string(name) != source,
                        into: %{} do
                      {name, source}
                    end)

  @doc """
  Parses a single response map using an instruction list.

  Applies each instruction's coercion to extract and convert values from the
  raw exchange data, then merges results into the original map.

  Returns data unchanged if mapping is nil or empty.

  ## Parameters

  - `data` - Raw exchange response map
  - `instructions` - List of `{field, coercion, source_keys}` tuples, or nil

  ## Examples

      iex> instructions = [{:ask, :number, ["askPrice"]}, {:bid, :number, ["bidPrice"]}]
      iex> CCXT.ResponseParser.parse_single(%{"askPrice" => "42000.5", "bidPrice" => "41999.0"}, instructions)
      %{"askPrice" => "42000.5", "bidPrice" => "41999.0", "ask" => 42000.5, "bid" => 41999.0}

  """
  @spec parse_single(map(), [instruction()] | nil) :: map()
  def parse_single(data, nil), do: data
  def parse_single(data, []), do: data

  def parse_single(data, instructions) when is_map(data) and is_list(instructions) do
    parsed =
      for {field, coercion, source_keys} <- instructions,
          source_keys != [],
          value = apply_coercion(data, coercion, source_keys),
          value != nil,
          into: %{} do
        {to_unified_key(field), value}
      end

    Map.merge(data, parsed)
  end

  def parse_single(data, _instructions), do: data

  # Applies the coercion function from CCXT.Safe based on the coercion atom.
  @doc false
  @spec apply_coercion(map(), atom(), [String.t()] | String.t()) :: any()
  defp apply_coercion(data, :number, keys), do: Safe.number(data, keys)
  defp apply_coercion(data, :integer, keys), do: Safe.integer(data, keys)
  defp apply_coercion(data, :string, keys), do: Safe.string(data, keys)
  defp apply_coercion(data, :string_lower, keys), do: Safe.string_lower(data, keys)
  defp apply_coercion(data, :bool, keys), do: Safe.bool(data, keys)
  defp apply_coercion(data, :timestamp, keys), do: Safe.timestamp(data, keys)
  defp apply_coercion(data, :value, keys), do: Safe.value(data, keys)
  defp apply_coercion(_data, _coercion, _keys), do: nil

  @doc false
  # Converts a struct field atom to the string key that from_map/1 expects.
  # Uses @field_to_source (derived from schema @fields at compile time).
  # Falls back to Atom.to_string for simple names like :ask -> "ask".
  @spec to_unified_key(atom()) :: String.t()
  defp to_unified_key(field) do
    Map.get(@field_to_source, field, Atom.to_string(field))
  end
end
