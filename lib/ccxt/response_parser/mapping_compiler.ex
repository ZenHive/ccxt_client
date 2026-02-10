defmodule CCXT.ResponseParser.MappingCompiler do
  @moduledoc """
  Compiles P1 mapping analysis data into instruction lists for `CCXT.ResponseParser`.

  Loads the mapping analysis JSON (produced by P1) at compile time and converts
  exchange-specific field mappings into instruction tuples that the runtime parser
  can execute efficiently.

  ## Instruction Format

      {field_atom, coercion_atom, source_keys}

  Where:
  - `field_atom` - Unified field name (e.g., `:ask`, `:bid_volume`)
  - `coercion_atom` - Type coercion to apply (e.g., `:number`, `:string`)
  - `source_keys` - Exchange-specific key(s) to read from raw data

  ## Category Handling

  | P1 Category | Action |
  |-------------|--------|
  | `safe_accessor` | Emit instruction with `fields` as source_keys |
  | `resolved_safe_accessor` | Same as safe_accessor |
  | `variable_ref` | Emit instruction with `raw` value as source key |
  | `literal` | Skip — hardcoded value, not from raw data |
  | `iso8601` | Skip — derived from timestamp by from_map |
  | `computed` | Skip — calculated from other fields |
  | `undefined` | Skip — CCXT doesn't map this for the exchange |
  | `passthrough` | Skip — set by CCXT caller, not from raw data |
  | `parse_call` | Skip — requires calling another parse method |

  """

  # Maps parse method names to their schema modules and response type atoms
  @method_schemas %{
    "parseTicker" => {CCXT.Types.Schema.Ticker, :ticker},
    "parseTrade" => {CCXT.Types.Schema.Trade, :trade},
    "parseOrder" => {CCXT.Types.Schema.Order, :order},
    "parseFundingRate" => {CCXT.Types.Schema.FundingRate, :funding_rate},
    "parsePosition" => {CCXT.Types.Schema.Position, :position},
    "parseTransaction" => {CCXT.Types.Schema.Transaction, :transaction},
    "parseTransfer" => {CCXT.Types.Schema.TransferEntry, :transfer},
    "parseDepositAddress" => {CCXT.Types.Schema.DepositAddress, :deposit_address},
    "parseLedgerEntry" => {CCXT.Types.Schema.LedgerEntry, :ledger_entry},
    "parseLeverage" => {CCXT.Types.Schema.Leverage, :leverage},
    "parseTradingFee" => {CCXT.Types.Schema.TradingFeeInterface, :trading_fee},
    "parseDepositWithdrawFee" => {CCXT.Types.Schema.DepositWithdrawFee, :deposit_withdraw_fee},
    "parseMarginModification" => {CCXT.Types.Schema.MarginModification, :margin_modification},
    "parseOpenInterest" => {CCXT.Types.Schema.OpenInterest, :open_interest},
    "parseMarginMode" => {CCXT.Types.Schema.MarginMode, :margin_mode},
    "parseLiquidation" => {CCXT.Types.Schema.Liquidation, :liquidation},
    "parseFundingRateHistory" => {CCXT.Types.Schema.FundingRateHistory, :funding_rate_history},
    "parseBorrowInterest" => {CCXT.Types.Schema.BorrowInterest, :borrow_interest},
    "parseBorrowRate" => {CCXT.Types.Schema.CrossBorrowRate, :borrow_rate},
    "parseConversion" => {CCXT.Types.Schema.Conversion, :conversion},
    "parseGreeks" => {CCXT.Types.Schema.Greeks, :greeks},
    "parseAccount" => {CCXT.Types.Schema.Account, :account},
    "parseOption" => {CCXT.Types.Schema.Option, :option},
    "parseFundingHistory" => {CCXT.Types.Schema.FundingHistory, :funding_history},
    "parseIsolatedBorrowRate" => {CCXT.Types.Schema.IsolatedBorrowRate, :isolated_borrow_rate},
    "parseLastPrice" => {CCXT.Types.Schema.LastPrice, :last_price},
    "parseLongShortRatio" => {CCXT.Types.Schema.LongShortRatio, :long_short_ratio},
    "parseLeverageTiers" => {CCXT.Types.Schema.LeverageTier, :leverage_tier},
    "parseBalance" => {CCXT.Types.Schema.Balances, :balance}
  }

  # Categories that produce instructions (the field maps to raw exchange data)
  @generatable_categories MapSet.new(["safe_accessor", "resolved_safe_accessor", "variable_ref"])

  @doc """
  Compiles a mapping for a specific exchange and parse method.

  Returns a list of instruction tuples, or nil if no mapping data exists.

  ## Parameters

  - `exchange_id` - Exchange identifier (e.g., "binance")
  - `parse_method` - CCXT parse method name (e.g., "parseTicker")
  - `analysis` - Pre-loaded P1 analysis data

  ## Examples

      iex> analysis = CCXT.ResponseParser.MappingCompiler.load_analysis()
      iex> instructions = CCXT.ResponseParser.MappingCompiler.compile_mapping("binance", "parseTicker", analysis)
      iex> Enum.find(instructions, fn {field, _, _} -> field == :ask end)
      {:ask, :number, ["askPrice"]}

  """
  @spec compile_mapping(String.t(), String.t(), map()) :: [{atom(), atom(), [String.t()]}] | nil
  def compile_mapping(exchange_id, parse_method, analysis) do
    with {:ok, {schema_module, _type_atom}} <- Map.fetch(@method_schemas, parse_method),
         exchange_fields when is_map(exchange_fields) <-
           get_in(analysis, ["methods", parse_method, "exchange_mappings", exchange_id]) do
      schema_fields = :attributes |> schema_module.__info__() |> Keyword.get(:fields, [])
      field_type_map = build_field_type_map(schema_fields)

      instructions =
        exchange_fields
        |> Enum.map(fn {unified_key, mapping} ->
          compile_field(unified_key, mapping, field_type_map)
        end)
        |> Enum.reject(&is_nil/1)

      if instructions == [], do: nil, else: instructions
    else
      _ -> nil
    end
  end

  @doc """
  Returns the supported parse methods and their schema/type mappings.
  """
  @spec method_schemas() :: map()
  def method_schemas, do: @method_schemas

  @doc """
  Loads the P1 mapping analysis JSON.

  Intended to be called once at compile time and reused across multiple
  `compile_mapping/3` calls.
  """
  # sobelow_skip ["Traversal.FileModule"]
  @spec load_analysis() :: map()
  def load_analysis do
    path = analysis_path()

    case File.read(path) do
      {:ok, content} ->
        case JSON.decode(content) do
          {:ok, data} ->
            data

          {:error, reason} ->
            raise "MappingCompiler: failed to decode #{path}: #{inspect(reason)}"
        end

      {:error, :enoent} ->
        # File doesn't exist yet — expected during initial setup
        %{}

      {:error, reason} ->
        raise "MappingCompiler: failed to read #{path}: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the path to the P1 mapping analysis JSON file.
  """
  @spec analysis_path() :: String.t()
  def analysis_path do
    case :code.priv_dir(:ccxt_client) do
      {:error, :bad_name} ->
        [__DIR__, "..", "..", "priv", "extractor/ccxt_mapping_analysis.json"]
        |> Path.join()
        |> Path.expand()

      priv when is_list(priv) ->
        Path.join(List.to_string(priv), "extractor/ccxt_mapping_analysis.json")
    end
  end

  # Compiles a single field mapping to an instruction tuple.
  # Returns nil for categories we can't generate (computed, iso8601, etc.)
  @doc false
  @spec compile_field(String.t(), map(), %{String.t() => atom()}) ::
          {atom(), atom(), [String.t()]} | nil
  defp compile_field(unified_key, %{"category" => category} = mapping, field_type_map) do
    if MapSet.member?(@generatable_categories, category) do
      with coercion when not is_nil(coercion) <- Map.get(field_type_map, unified_key),
           field_atom when is_atom(field_atom) <- unified_key_to_field_atom(unified_key),
           source_keys when source_keys != [] <- extract_source_keys(category, mapping) do
        {field_atom, coercion, source_keys}
      else
        _ -> nil
      end
    end
  end

  defp compile_field(_unified_key, _mapping, _field_type_map), do: nil

  # Extracts source keys from the mapping based on category
  @doc false
  @spec extract_source_keys(String.t(), map()) :: [String.t()]
  defp extract_source_keys("variable_ref", %{"raw" => raw}) when is_binary(raw), do: [raw]
  defp extract_source_keys(_category, %{"fields" => fields}) when is_list(fields), do: fields
  defp extract_source_keys(_category, _mapping), do: []

  # Converts a unified key string (camelCase from CCXT) to a struct field atom.
  # E.g., "askVolume" -> :ask_volume, "bid" -> :bid
  @doc false
  # Keys come from trusted P1 analysis JSON, not user input
  @spec unified_key_to_field_atom(String.t()) :: atom()
  defp unified_key_to_field_atom(key) do
    key |> Macro.underscore() |> String.to_atom()
  end

  # Builds a map from unified key strings to coercion atoms based on schema field types.
  # E.g., %{"ask" => :number, "symbol" => :string, "timestamp" => :integer}
  @doc false
  @spec build_field_type_map([map()]) :: %{String.t() => atom()}
  defp build_field_type_map(schema_fields) do
    Map.new(schema_fields, fn %{source: source, type: type_str} ->
      {source, type_to_coercion(type_str)}
    end)
  end

  @doc """
  Converts a schema type string to a coercion atom.

  ## Examples

      iex> CCXT.ResponseParser.MappingCompiler.type_to_coercion("number() | nil")
      :number

      iex> CCXT.ResponseParser.MappingCompiler.type_to_coercion("String.t() | nil")
      :string

      iex> CCXT.ResponseParser.MappingCompiler.type_to_coercion("integer() | nil")
      :integer

  """
  @spec type_to_coercion(String.t()) :: atom()
  def type_to_coercion(type_str) do
    cond do
      String.starts_with?(type_str, "integer") -> :integer
      String.starts_with?(type_str, "number") -> :number
      String.starts_with?(type_str, "String") -> :string
      String.starts_with?(type_str, "boolean") -> :bool
      true -> :value
    end
  end
end
