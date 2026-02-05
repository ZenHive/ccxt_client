defmodule CCXT.Symbol do
  @moduledoc """
  Bidirectional symbol normalization between unified and exchange-specific formats.

  CCXT uses a unified symbol format: `BASE/QUOTE` (e.g., "BTC/USDT").
  Different exchanges use different formats:

  - Binance: "BTCUSDT" (no separator)
  - Coinbase: "BTC-USD" (dash separator)
  - Gate.io: "BTC_USDT" (underscore separator)
  - Bitstamp: "btcusd" (lowercase)
  - Some derivatives: "BTC/USDT:USDT" (with settle currency)
  - Kraken: "XXBTZUSD" (X/Z prefixes for currencies)
  - KrakenFutures: "PI_XBTUSD" (PI_/PF_/FI_ prefixes for contract types)

  ## Usage

  Use with a spec's `symbol_format` for automatic normalization:

      spec = CCXT.Bybit.__ccxt_spec__()
      CCXT.Symbol.normalize("BTCUSDT", spec)
      # => "BTC/USDT"

      CCXT.Symbol.denormalize("BTC/USDT", spec)
      # => "BTCUSDT"

  Or use with a format map directly:

      format = %{separator: "-", case: :upper}
      CCXT.Symbol.normalize("BTC-USD", format)
      # => "BTC/USD"

  ## Validation

  Use bang functions for explicit error handling:

      # Raises CCXT.Symbol.Error on failure
      CCXT.Symbol.to_exchange_id!("BTC/USDT", spec)

      # Check if conversion will work
      case CCXT.Symbol.validate_symbol_conversion("BTC/USDT", spec) do
        :ok -> CCXT.Symbol.to_exchange_id("BTC/USDT", spec)
        {:error, reason} -> handle_error(reason)
      end

  """

  alias CCXT.Symbol.Error, as: SymbolError

  require Logger

  # Default quote currencies - used when spec doesn't provide known_quote_currencies
  @default_quote_currencies ~w(USDT USDC USD EUR GBP JPY BTC ETH BUSD TUSD DAI USDD FDUSD)

  # KrakenFutures contract prefixes that should be stripped before parsing
  # Note: Kraken currency prefixes (X for crypto, Z for fiat) are handled separately
  # in strip_currency_prefix/1 with more nuanced logic (XX→X, Z+4char only)
  @known_contract_prefixes ["PI_", "PF_", "FI_", "FF_", "PV_"]

  @type symbol_format :: %{separator: String.t(), case: :upper | :lower | :mixed}

  @doc """
  Converts an exchange-specific symbol to unified format.

  ## Parameters

  - `symbol` - The exchange-specific symbol (e.g., "BTCUSDT")
  - `spec_or_format` - A CCXT.Spec struct, or map with `:symbol_format`, or symbol_format map directly

  ## Returns

  The unified symbol (e.g., "BTC/USDT") or the original if cannot parse.

  ## Examples

      # With a spec
      spec = CCXT.Bybit.__ccxt_spec__()
      CCXT.Symbol.normalize("BTCUSDT", spec)
      # => "BTC/USDT"

      # With a format map
      CCXT.Symbol.normalize("BTC-USD", %{separator: "-", case: :upper})
      # => "BTC/USD"

  """
  @spec normalize(String.t(), map()) :: String.t()
  def normalize(symbol, spec_or_format) when is_binary(symbol) and is_map(spec_or_format) do
    {format, aliases} = extract_format_and_aliases(spec_or_format)
    do_normalize(symbol, format, aliases)
  end

  @doc """
  Converts a unified symbol to exchange-specific format.

  ## Parameters

  - `symbol` - The unified symbol (e.g., "BTC/USDT")
  - `spec_or_format` - A CCXT.Spec struct, or map with `:symbol_format`, or symbol_format map directly
  - `market_type` - Optional market type (:spot, :swap, :future, :option) for per-market-type formats

  ## Returns

  The exchange-specific symbol (e.g., "BTCUSDT").

  ## Examples

      # With a spec
      spec = CCXT.Coinbase.__ccxt_spec__()
      CCXT.Symbol.denormalize("BTC/USD", spec)
      # => "BTC-USD"

      # With a format map
      CCXT.Symbol.denormalize("BTC/USDT", %{separator: "_", case: :upper})
      # => "BTC_USDT"

      # With market type for per-market-type exchanges
      spec = CCXT.HTX.__ccxt_spec__()
      CCXT.Symbol.denormalize("BTC/USDT", spec, :spot)
      # => "btcusdt"

  """
  @spec denormalize(String.t(), map(), atom() | nil) :: String.t()
  def denormalize(symbol, spec_or_format, market_type \\ nil)

  def denormalize(symbol, spec_or_format, market_type) when is_binary(symbol) and is_map(spec_or_format) do
    {format, _aliases} = extract_format_and_aliases(spec_or_format, market_type)
    do_denormalize(symbol, format)
  end

  @doc false
  # Extracts symbol format and currency aliases from spec or format map.
  # When market_type is provided, checks symbol_formats (plural) first.
  @spec extract_format_and_aliases(map(), atom() | nil) :: {symbol_format(), map()}
  defp extract_format_and_aliases(spec_or_format, market_type \\ nil) do
    # Get symbol_formats value - must be a map, not just key existence
    # (Spec struct defines the key but value may be nil)
    symbol_formats = Map.get(spec_or_format, :symbol_formats)

    cond do
      # Check symbol_formats (plural) first when market_type is provided
      market_type != nil and is_map(symbol_formats) ->
        formats = symbol_formats

        case Map.get(formats, market_type) do
          %{separator: _, case: _} = format ->
            aliases = Map.get(spec_or_format, :currency_aliases, %{})
            {format, aliases}

          _ ->
            # No format for this market type, try symbol_format (singular)
            extract_format_and_aliases(spec_or_format, nil)
        end

      # It's a spec with symbol_format field
      Map.has_key?(spec_or_format, :symbol_format) ->
        format = spec_or_format.symbol_format || default_format()
        aliases = Map.get(spec_or_format, :currency_aliases, %{})
        {format, aliases}

      # It's a format map directly (has :separator and :case)
      Map.has_key?(spec_or_format, :separator) ->
        {spec_or_format, %{}}

      # Unknown format, use defaults
      true ->
        {default_format(), %{}}
    end
  end

  @spec default_format() :: symbol_format()
  defp default_format, do: %{separator: "", case: :upper}

  # Internal normalize implementation
  @spec do_normalize(String.t(), symbol_format(), map()) :: String.t()
  defp do_normalize(symbol, %{separator: sep, case: sym_case}, currency_aliases) do
    # First apply case normalization
    symbol = if sym_case == :lower, do: String.upcase(symbol), else: symbol

    # Apply currency alias mapping (reverse: exchange code -> unified code)
    # commonCurrencies is unified -> exchange, we need exchange -> unified
    reverse_aliases = Map.new(currency_aliases, fn {unified, exchange} -> {exchange, unified} end)
    symbol = apply_currency_aliases(symbol, reverse_aliases)

    # Split by separator
    case sep do
      "" -> find_and_split(symbol)
      "/" -> symbol
      _ -> String.replace(symbol, sep, "/")
    end
  end

  # Internal denormalize implementation
  @spec do_denormalize(String.t(), symbol_format()) :: String.t()
  defp do_denormalize(symbol, %{separator: sep, case: sym_case}) do
    # Handle settle currency (e.g., "BTC/USDT:USDT" -> just use "BTC/USDT" part)
    pair = symbol |> String.split(":") |> hd()

    # Replace unified separator with exchange separator
    result = String.replace(pair, "/", sep)

    # Apply case transformation
    case sym_case do
      :lower -> String.downcase(result)
      :upper -> String.upcase(result)
      _ -> result
    end
  end

  # Apply currency aliases to symbol (e.g., XBT -> BTC)
  @spec apply_currency_aliases(String.t(), map()) :: String.t()
  defp apply_currency_aliases(symbol, aliases) when map_size(aliases) == 0, do: symbol

  defp apply_currency_aliases(symbol, aliases) do
    Enum.reduce(aliases, symbol, fn {from, to}, acc ->
      String.replace(acc, from, to)
    end)
  end

  # Split symbol without separator by finding known quote currency
  @spec find_and_split(String.t()) :: String.t()
  defp find_and_split(symbol) do
    # Already has separator
    if String.contains?(symbol, "/") do
      symbol
    else
      # Try to find a known quote currency at the end
      case Enum.find(@default_quote_currencies, &String.ends_with?(symbol, &1)) do
        nil ->
          symbol

        quote_currency ->
          base = String.replace_suffix(symbol, quote_currency, "")
          "#{base}/#{quote_currency}"
      end
    end
  end

  # =============================================================================
  # PARSING UTILITIES
  # =============================================================================

  @type parsed_symbol :: %{base: String.t(), quote: String.t(), settle: String.t() | nil}

  @doc """
  Parses a unified symbol into its components.

  ## Example

      CCXT.Symbol.parse("BTC/USDT")
      # => {:ok, %{base: "BTC", quote: "USDT", settle: nil}}

      CCXT.Symbol.parse("BTC/USDT:USDT")
      # => {:ok, %{base: "BTC", quote: "USDT", settle: "USDT"}}

  """
  @spec parse(String.t()) :: {:ok, parsed_symbol()} | {:error, :invalid_format}
  def parse(symbol) when is_binary(symbol) do
    case String.split(symbol, ":") do
      [pair, settle] -> parse_pair(pair, settle)
      [pair] -> parse_pair(pair, nil)
      _ -> {:error, :invalid_format}
    end
  end

  defp parse_pair(pair, settle) do
    case String.split(pair, "/") do
      [base, quote_currency] when base != "" and quote_currency != "" ->
        {:ok, %{base: base, quote: quote_currency, settle: settle}}

      _ ->
        {:error, :invalid_format}
    end
  end

  @doc """
  Parses a unified symbol into its components, raising on error.
  """
  @spec parse!(String.t()) :: parsed_symbol()
  def parse!(symbol) when is_binary(symbol) do
    case parse(symbol) do
      {:ok, result} -> result
      {:error, :invalid_format} -> raise ArgumentError, "invalid symbol format: #{inspect(symbol)}"
    end
  end

  @doc """
  Builds a unified symbol from components.

  ## Example

      CCXT.Symbol.build("BTC", "USDT")
      # => "BTC/USDT"

      CCXT.Symbol.build("BTC", "USDT", "USDT")
      # => "BTC/USDT:USDT"

  """
  @spec build(String.t(), String.t(), String.t() | nil) :: String.t()
  def build(base, quote_currency, settle \\ nil)

  def build(base, quote_currency, nil), do: "#{base}/#{quote_currency}"
  def build(base, quote_currency, settle), do: "#{base}/#{quote_currency}:#{settle}"

  # =============================================================================
  # WEBSOCKET SYMBOL DENORMALIZATION
  # =============================================================================

  @type ws_symbol_format :: :dash_separated | :lowercase_no_slash | :uppercase_no_slash | :slash | :unknown

  @doc """
  Converts a unified symbol to WebSocket channel format.

  WebSocket channels often use different symbol formats than REST APIs.
  This function converts unified symbols to the format detected from
  captured WebSocket subscribe messages.

  ## Parameters

  - `symbol` - The unified symbol (e.g., "BTC/USDT")
  - `format` - The WS symbol format
  - `opts` - Reserved for future extensibility (e.g., exchange-specific overrides)

  ## Returns

  The WebSocket-formatted symbol.

  ## Examples

      iex> CCXT.Symbol.denormalize_ws("BTC/USDT", :dash_separated)
      "BTC-USDT"

      iex> CCXT.Symbol.denormalize_ws("BTC/USDT", :lowercase_no_slash)
      "btcusdt"

      iex> CCXT.Symbol.denormalize_ws("BTC/USDT", :uppercase_no_slash)
      "BTCUSDT"

      iex> CCXT.Symbol.denormalize_ws("BTC/USDT", :slash)
      "BTC/USDT"

  """
  @spec denormalize_ws(String.t(), ws_symbol_format(), keyword()) :: String.t()
  def denormalize_ws(symbol, format, _opts \\ [])

  def denormalize_ws(symbol, :dash_separated, _opts), do: String.replace(symbol, "/", "-")

  def denormalize_ws(symbol, :lowercase_no_slash, _opts) do
    symbol |> String.replace("/", "") |> String.downcase()
  end

  def denormalize_ws(symbol, :uppercase_no_slash, _opts), do: String.replace(symbol, "/", "")

  def denormalize_ws(symbol, :slash, _opts), do: symbol

  # Safe default for unknown formats - log and remove slash
  def denormalize_ws(symbol, format, _opts) do
    Logger.debug("[CCXT.Symbol] Unknown WS symbol format #{inspect(format)} for #{symbol}, using uppercase_no_slash")
    String.replace(symbol, "/", "")
  end

  # =============================================================================
  # PATTERN-BASED SYMBOL CONVERSION (R6)
  # =============================================================================
  # Uses detected patterns from R5 (SymbolPatternDetector) to convert symbols
  # without requiring loadMarkets() API calls.

  # Month abbreviations for DDMMMYY format parsing
  @month_abbrevs %{
    1 => "JAN",
    2 => "FEB",
    3 => "MAR",
    4 => "APR",
    5 => "MAY",
    6 => "JUN",
    7 => "JUL",
    8 => "AUG",
    9 => "SEP",
    10 => "OCT",
    11 => "NOV",
    12 => "DEC"
  }

  @month_numbers %{
    "JAN" => 1,
    "FEB" => 2,
    "MAR" => 3,
    "APR" => 4,
    "MAY" => 5,
    "JUN" => 6,
    "JUL" => 7,
    "AUG" => 8,
    "SEP" => 9,
    "OCT" => 10,
    "NOV" => 11,
    "DEC" => 12
  }

  @type parsed_extended :: %{
          base: String.t(),
          quote: String.t(),
          settle: String.t() | nil,
          expiry: String.t() | nil,
          strike: String.t() | nil,
          option_type: String.t() | nil
        }

  @type pattern_config :: %{
          pattern: atom(),
          separator: String.t(),
          case: :upper | :lower | :mixed,
          date_format: :yymmdd | :ddmmmyy | :yyyymmdd | nil,
          suffix: String.t() | nil,
          component_order: [atom()] | nil
        }

  @doc """
  Converts a unified symbol to exchange-specific ID using detected patterns.

  This function uses the `symbol_patterns` field from a spec (detected by R5)
  to perform static symbol conversion without requiring `loadMarkets()` API calls.

  ## Parameters

  - `unified_symbol` - The unified symbol (e.g., "BTC/USDT:USDT-260327")
  - `spec` - A CCXT.Spec struct containing `symbol_patterns`
  - `opts` - Options:
    - `:market_type` - Override auto-detected market type (:spot, :swap, :future, :option)

  ## Returns

  The exchange-specific ID (e.g., "BTCUSDT_260327")

  ## Examples

      # Spot conversion
      CCXT.Symbol.to_exchange_id("BTC/USDT", binance_spec)
      # => "BTCUSDT"

      # Perpetual/swap conversion
      CCXT.Symbol.to_exchange_id("BTC/USDT:USDT", binance_spec)
      # => "BTCUSDT"

      CCXT.Symbol.to_exchange_id("BTC/USD:BTC", deribit_spec)
      # => "BTC-PERPETUAL"

      # Future conversion
      CCXT.Symbol.to_exchange_id("BTC/USDT:USDT-260327", binance_spec)
      # => "BTCUSDT_260327"

      CCXT.Symbol.to_exchange_id("BTC/USD:BTC-260116", deribit_spec)
      # => "BTC-16JAN26"

      # Option conversion
      CCXT.Symbol.to_exchange_id("BTC/USD:BTC-260112-84000-C", deribit_spec)
      # => "BTC-12JAN26-84000-C"

  """
  @spec to_exchange_id(String.t(), map(), keyword()) :: String.t()
  def to_exchange_id(unified_symbol, spec, opts \\ [])

  def to_exchange_id(unified_symbol, spec, opts) when is_binary(unified_symbol) and is_map(spec) do
    case parse_extended(unified_symbol) do
      {:ok, parsed} ->
        market_type = opts[:market_type] || detect_market_type(parsed)
        pattern_config = get_pattern_config(spec, market_type)

        if pattern_config do
          apply_pattern(parsed, pattern_config, spec)
        else
          # Fall back to legacy denormalize
          denormalize(unified_symbol, spec, market_type)
        end

      {:error, _} ->
        # Invalid symbol, return as-is
        unified_symbol
    end
  end

  @doc """
  Converts an exchange-specific ID to unified symbol format.

  Requires `market_type` since it cannot be auto-detected from the exchange ID alone.

  ## Parameters

  - `exchange_id` - The exchange-specific ID (e.g., "BTCUSDT_260327")
  - `spec` - A CCXT.Spec struct containing `symbol_patterns`
  - `market_type` - The market type (:spot, :swap, :future, :option)

  ## Returns

  The unified symbol (e.g., "BTC/USDT:USDT-260327")

  ## Examples

      CCXT.Symbol.from_exchange_id("BTCUSDT", binance_spec, :spot)
      # => "BTC/USDT"

      CCXT.Symbol.from_exchange_id("BTC-PERPETUAL", deribit_spec, :swap)
      # => "BTC/USD:BTC"

      CCXT.Symbol.from_exchange_id("BTCUSDT_260327", binance_spec, :future)
      # => "BTC/USDT:USDT-260327"

  """
  @spec from_exchange_id(String.t(), map(), atom()) :: String.t()
  def from_exchange_id(exchange_id, spec, market_type)
      when is_binary(exchange_id) and is_map(spec) and is_atom(market_type) do
    pattern_config = get_pattern_config(spec, market_type)

    if pattern_config do
      reverse_pattern(exchange_id, pattern_config, market_type, spec)
    else
      # Fall back to normalize
      normalize(exchange_id, spec)
    end
  end

  # =============================================================================
  # VALIDATION FUNCTIONS (R7 - Explicit Error Handling)
  # =============================================================================

  @doc """
  Converts a unified symbol to exchange-specific ID, raising on failure.

  Unlike `to_exchange_id/3`, this function raises `CCXT.Symbol.Error` when:
  - The symbol format is invalid and cannot be parsed
  - No pattern configuration is found for the market type

  ## Parameters

  Same as `to_exchange_id/3`.

  ## Returns

  The exchange-specific ID string.

  ## Raises

  - `CCXT.Symbol.Error` with reason `:invalid_format` if symbol cannot be parsed
  - `CCXT.Symbol.Error` with reason `:pattern_not_found` if no pattern for market type

  ## Examples

      CCXT.Symbol.to_exchange_id!("BTC/USDT", binance_spec)
      # => "BTCUSDT"

      CCXT.Symbol.to_exchange_id!("INVALID", binance_spec)
      # ** (CCXT.Symbol.Error) Invalid symbol format: "INVALID"

  """
  @spec to_exchange_id!(String.t(), map(), keyword()) :: String.t()
  def to_exchange_id!(unified_symbol, spec, opts \\ [])

  def to_exchange_id!(unified_symbol, spec, opts) when is_binary(unified_symbol) and is_map(spec) do
    case parse_extended(unified_symbol) do
      {:ok, parsed} ->
        market_type = opts[:market_type] || detect_market_type(parsed)
        pattern_config = get_pattern_config(spec, market_type)

        if pattern_config do
          apply_pattern(parsed, pattern_config, spec)
        else
          spec_name = Map.get(spec, :name) || Map.get(spec, :id)
          raise SymbolError.pattern_not_found(unified_symbol, market_type, spec_name)
        end

      {:error, :invalid_format} ->
        raise SymbolError.invalid_format(unified_symbol)
    end
  end

  @doc """
  Converts an exchange-specific ID to unified symbol format, raising on failure.

  Unlike `from_exchange_id/3`, this function raises `CCXT.Symbol.Error` when:
  - No pattern configuration is found for the market type

  ## Parameters

  Same as `from_exchange_id/3`.

  ## Returns

  The unified symbol string.

  ## Raises

  - `CCXT.Symbol.Error` with reason `:pattern_not_found` if no pattern for market type

  ## Examples

      CCXT.Symbol.from_exchange_id!("BTCUSDT", binance_spec, :spot)
      # => "BTC/USDT"

      CCXT.Symbol.from_exchange_id!("BTCUSDT", %{}, :spot)
      # ** (CCXT.Symbol.Error) No symbol pattern found for market type :spot

  """
  @spec from_exchange_id!(String.t(), map(), atom()) :: String.t()
  def from_exchange_id!(exchange_id, spec, market_type)
      when is_binary(exchange_id) and is_map(spec) and is_atom(market_type) do
    pattern_config = get_pattern_config(spec, market_type)

    if pattern_config do
      reverse_pattern(exchange_id, pattern_config, market_type, spec)
    else
      spec_name = Map.get(spec, :name) || Map.get(spec, :id)
      raise SymbolError.pattern_not_found(exchange_id, market_type, spec_name)
    end
  end

  @doc """
  Validates that a symbol conversion will succeed without actually performing it.

  Use this to check whether `to_exchange_id/3` will use pattern matching or
  fall back to legacy denormalization.

  ## Parameters

  - `unified_symbol` - The unified symbol (e.g., "BTC/USDT")
  - `spec` - A CCXT.Spec struct containing `symbol_patterns`
  - `opts` - Options:
    - `:market_type` - Override auto-detected market type

  ## Returns

  - `:ok` - Pattern will match
  - `{:error, :invalid_format}` - Symbol cannot be parsed
  - `{:error, {:pattern_not_found, market_type}}` - No pattern for market type
  - `{:error, {:unknown_quote_currency, symbol}}` - Quote currency not recognized

  ## Examples

      CCXT.Symbol.validate_symbol_conversion("BTC/USDT", spec)
      # => :ok

      CCXT.Symbol.validate_symbol_conversion("BTC/UNKNOWN", spec)
      # => {:error, {:unknown_quote_currency, "BTC/UNKNOWN"}}

  """
  @spec validate_symbol_conversion(String.t(), map(), keyword()) ::
          :ok | {:error, :invalid_format | {:pattern_not_found, atom()} | {:unknown_quote_currency, String.t()}}
  def validate_symbol_conversion(unified_symbol, spec, opts \\ [])

  def validate_symbol_conversion(unified_symbol, spec, opts) when is_binary(unified_symbol) and is_map(spec) do
    case parse_extended(unified_symbol) do
      {:ok, parsed} ->
        market_type = opts[:market_type] || detect_market_type(parsed)
        pattern_config = get_pattern_config(spec, market_type)

        cond do
          pattern_config != nil ->
            # Pattern exists - conversion will work
            :ok

          has_legacy_format?(spec) ->
            # Will fall back to legacy denormalize - that's OK
            :ok

          true ->
            {:error, {:pattern_not_found, market_type}}
        end

      {:error, :invalid_format} ->
        {:error, :invalid_format}
    end
  end

  @doc false
  # Checks if spec has legacy symbol_format or symbol_formats for fallback
  defp has_legacy_format?(spec) do
    Map.has_key?(spec, :symbol_format) or Map.has_key?(spec, :symbol_formats)
  end

  # =============================================================================
  # PREFIX HANDLING (R7 - Kraken X/Z and KrakenFutures PI_/PF_/FI_)
  # =============================================================================

  @doc """
  Strips known exchange prefixes from a symbol or currency code.

  Handles:
  - Kraken currency prefixes: X (crypto), Z (fiat) - e.g., "XXBT" → "XBT", "ZUSD" → "USD"
  - KrakenFutures contract prefixes: PI_, PF_, FI_, FF_, PV_ - e.g., "PI_XBTUSD" → "XBTUSD"

  ## Examples

      CCXT.Symbol.strip_prefix("PI_XBTUSD")
      # => {"PI_", "XBTUSD"}

      CCXT.Symbol.strip_prefix("XXBT")
      # => {"X", "XBT"}

      CCXT.Symbol.strip_prefix("BTCUSDT")
      # => {nil, "BTCUSDT"}

  """
  @spec strip_prefix(String.t()) :: {String.t() | nil, String.t()}
  def strip_prefix(symbol) when is_binary(symbol) do
    # Try contract prefixes first (more specific, longer)
    case find_matching_prefix(symbol, @known_contract_prefixes) do
      {prefix, rest} -> {prefix, rest}
      nil -> strip_currency_prefix(symbol)
    end
  end

  @doc false
  # Strips Kraken-style X/Z currency prefixes (only at start, for specific patterns)
  defp strip_currency_prefix(symbol) do
    cond do
      # XXBT → X + XBT (doubled X prefix)
      String.starts_with?(symbol, "XX") ->
        {"X", String.slice(symbol, 1..-1//1)}

      # ZUSD → Z + USD (fiat prefix)
      String.starts_with?(symbol, "Z") and String.length(symbol) == 4 ->
        {"Z", String.slice(symbol, 1..-1//1)}

      # No prefix
      true ->
        {nil, symbol}
    end
  end

  @doc false
  # Finds first matching prefix from a list
  defp find_matching_prefix(symbol, prefixes) do
    Enum.find_value(prefixes, fn prefix ->
      if String.starts_with?(symbol, prefix) do
        {prefix, String.replace_prefix(symbol, prefix, "")}
      end
    end)
  end

  @doc """
  Parses a unified symbol into extended components including derivative fields.

  ## Examples

      CCXT.Symbol.parse_extended("BTC/USDT")
      # => {:ok, %{base: "BTC", quote: "USDT", settle: nil, expiry: nil, strike: nil, option_type: nil}}

      CCXT.Symbol.parse_extended("BTC/USDT:USDT-260327")
      # => {:ok, %{base: "BTC", quote: "USDT", settle: "USDT", expiry: "260327", strike: nil, option_type: nil}}

      CCXT.Symbol.parse_extended("BTC/USD:BTC-260112-84000-C")
      # => {:ok, %{base: "BTC", quote: "USD", settle: "BTC", expiry: "260112", strike: "84000", option_type: "C"}}

  """
  @spec parse_extended(String.t()) :: {:ok, parsed_extended()} | {:error, :invalid_format}
  def parse_extended(symbol) when is_binary(symbol) do
    # Split on colon first: "BTC/USDT:USDT-260327" -> ["BTC/USDT", "USDT-260327"]
    case String.split(symbol, ":") do
      [pair] ->
        # Simple spot symbol
        parse_extended_pair(pair, nil)

      [pair, settle_and_rest] ->
        # Has settle currency and possibly more
        parse_extended_pair(pair, settle_and_rest)

      _ ->
        {:error, :invalid_format}
    end
  end

  @doc """
  Converts date between YYMMDD and DDMMMYY formats.

  ## Examples

      CCXT.Symbol.convert_date("260327", :yymmdd, :ddmmmyy)
      # => "27MAR26"

      CCXT.Symbol.convert_date("27MAR26", :ddmmmyy, :yymmdd)
      # => "260327"

      CCXT.Symbol.convert_date("260109", :yymmdd, :ddmmmyy)
      # => "9JAN26"

  """
  @spec convert_date(String.t(), atom(), atom()) :: String.t()
  def convert_date(date_str, from_format, to_format)

  # Same format - no conversion needed
  def convert_date(date_str, format, format), do: date_str

  # YYMMDD -> DDMMMYY
  def convert_date(date_str, :yymmdd, :ddmmmyy) do
    <<yy::binary-2, mm::binary-2, dd::binary-2>> = date_str
    month = String.to_integer(mm)
    day = String.to_integer(dd)

    month_abbrev = Map.fetch!(@month_abbrevs, month)
    "#{day}#{month_abbrev}#{yy}"
  end

  # DDMMMYY -> YYMMDD
  def convert_date(date_str, :ddmmmyy, :yymmdd) do
    # Parse "27MAR26" or "9JAN26" (day can be 1 or 2 digits)
    date_upper = String.upcase(date_str)

    case Regex.run(~r/^(\d{1,2})([A-Z]{3})(\d{2})$/, date_upper) do
      [_, day_str, month_str, year_str] ->
        month = Map.fetch!(@month_numbers, month_str)
        day = String.to_integer(day_str)
        "#{year_str}#{pad_two(month)}#{pad_two(day)}"

      _ ->
        date_str
    end
  end

  # YYYYMMDD -> YYMMDD (just drop century)
  def convert_date(date_str, :yyyymmdd, :yymmdd) do
    <<_century::binary-2, rest::binary>> = date_str
    rest
  end

  # YYMMDD -> YYYYMMDD (add 20 as century)
  def convert_date(date_str, :yymmdd, :yyyymmdd), do: "20#{date_str}"

  # YYYYMMDD -> DDMMMYY
  def convert_date(date_str, :yyyymmdd, :ddmmmyy) do
    date_str
    |> convert_date(:yyyymmdd, :yymmdd)
    |> convert_date(:yymmdd, :ddmmmyy)
  end

  # DDMMMYY -> YYYYMMDD
  def convert_date(date_str, :ddmmmyy, :yyyymmdd) do
    date_str
    |> convert_date(:ddmmmyy, :yymmdd)
    |> convert_date(:yymmdd, :yyyymmdd)
  end

  # ============================================================================
  # Private: Extended Parsing
  # ============================================================================

  @doc false
  # Parses simple spot pair like "BTC/USDT" into extended components
  defp parse_extended_pair(pair, nil) do
    # Simple pair like "BTC/USDT"
    case String.split(pair, "/") do
      [base, quote_currency] when base != "" and quote_currency != "" ->
        {:ok,
         %{
           base: base,
           quote: quote_currency,
           settle: nil,
           expiry: nil,
           strike: nil,
           option_type: nil
         }}

      _ ->
        {:error, :invalid_format}
    end
  end

  @doc false
  # Parses pair with derivative suffix like "BTC/USDT" + "USDT-260327"
  defp parse_extended_pair(pair, settle_and_rest) do
    # Parse pair first
    case String.split(pair, "/") do
      [base, quote_currency] when base != "" and quote_currency != "" ->
        # Parse settle and derivative components
        parse_derivative_suffix(base, quote_currency, settle_and_rest)

      _ ->
        {:error, :invalid_format}
    end
  end

  @doc false
  # Parses derivative suffix into settle, expiry, strike, and option_type components
  defp parse_derivative_suffix(base, quote_currency, settle_and_rest) do
    # Settle and rest: "USDT" or "USDT-260327" or "BTC-260112-84000-C"
    parts = String.split(settle_and_rest, "-")

    case parts do
      [settle] ->
        # Just settle, no expiry (swap/perpetual)
        {:ok,
         %{
           base: base,
           quote: quote_currency,
           settle: settle,
           expiry: nil,
           strike: nil,
           option_type: nil
         }}

      [settle, expiry] ->
        # Settle + expiry (future)
        {:ok,
         %{
           base: base,
           quote: quote_currency,
           settle: settle,
           expiry: expiry,
           strike: nil,
           option_type: nil
         }}

      [settle, expiry, strike, option_type] ->
        # Settle + expiry + strike + type (option)
        {:ok,
         %{
           base: base,
           quote: quote_currency,
           settle: settle,
           expiry: expiry,
           strike: strike,
           option_type: option_type
         }}

      _ ->
        {:error, :invalid_format}
    end
  end

  # ============================================================================
  # Private: Market Type Detection
  # ============================================================================

  @doc false
  # Detects market type from parsed symbol components (option > future > swap > spot)
  defp detect_market_type(parsed) do
    cond do
      parsed.option_type != nil -> :option
      parsed.expiry != nil -> :future
      parsed.settle != nil -> :swap
      true -> :spot
    end
  end

  # ============================================================================
  # Private: Pattern Config Retrieval
  # ============================================================================

  @doc false
  # Retrieves pattern configuration for a market type from spec's symbol_patterns
  defp get_pattern_config(spec, market_type) do
    case Map.get(spec, :symbol_patterns) do
      nil -> nil
      patterns when is_map(patterns) -> Map.get(patterns, market_type)
    end
  end

  # ============================================================================
  # Private: Apply Pattern (unified -> exchange)
  # ============================================================================

  # Pattern categories for dispatch
  # Naming convention: {separator}_{case} for spot, {type}_{suffix/format} for derivatives
  # Example: no_separator_upper = no separator + uppercase
  # Example: future_ddmmmyy = future with DDMMMYY date format
  @spot_patterns ~w(no_separator_upper no_separator_lower no_separator_mixed
                    underscore_upper underscore_lower underscore_mixed
                    dash_upper dash_lower dash_mixed)a

  @swap_patterns ~w(implicit suffix_perpetual suffix_swap suffix_perp)a
  @future_patterns ~w(future_yymmdd future_ddmmmyy future_yyyymmdd future_unknown)a
  @option_patterns ~w(option_ddmmmyy option_yymmdd option_with_settle option_unknown)a

  @doc false
  # Dispatches to market-type-specific pattern application.
  defp apply_pattern(parsed, config, spec) do
    aliases = Map.get(spec, :currency_aliases, %{})
    base = apply_forward_alias(parsed.base, aliases)
    pattern = config.pattern

    cond do
      pattern in @spot_patterns -> apply_spot_pattern(base, parsed, config)
      pattern in @swap_patterns -> apply_swap_pattern(base, parsed, config)
      pattern in @future_patterns -> apply_future_pattern(base, parsed, config)
      pattern in @option_patterns -> apply_option_pattern(base, parsed, config)
      true -> "#{base}#{config.separator}#{parsed.quote}"
    end
  end

  @doc false
  # Applies spot patterns using separator extraction from pattern name
  defp apply_spot_pattern(base, parsed, config) do
    separator = spot_separator(config.pattern)
    result = "#{base}#{separator}#{parsed.quote}"

    if String.ends_with?(Atom.to_string(config.pattern), "_mixed") do
      result
    else
      apply_case(result, config.case)
    end
  end

  @doc false
  # Extracts separator from spot pattern name
  defp spot_separator(pattern) do
    pattern_str = Atom.to_string(pattern)

    cond do
      String.starts_with?(pattern_str, "no_separator") -> ""
      String.starts_with?(pattern_str, "underscore") -> "_"
      String.starts_with?(pattern_str, "dash") -> "-"
      true -> ""
    end
  end

  @doc false
  # Applies swap/perpetual patterns: implicit, suffix_perpetual, suffix_swap, suffix_perp
  defp apply_swap_pattern(base, parsed, config) do
    case config.pattern do
      :implicit ->
        apply_case("#{base}#{config.separator}#{parsed.quote}", config.case)

      :suffix_perpetual ->
        apply_case("#{base}#{config.separator}#{parsed.quote}#{config.suffix}", config.case)

      :suffix_swap ->
        apply_case("#{base}#{config.separator}#{parsed.quote}#{config.suffix}", config.case)

      :suffix_perp ->
        apply_case("#{base}#{config.separator}#{parsed.quote}#{config.suffix}", config.case)
    end
  end

  @doc false
  # Applies future patterns: future_yymmdd, future_ddmmmyy, future_yyyymmdd, future_unknown
  defp apply_future_pattern(base, parsed, config) do
    case config.pattern do
      :future_yymmdd ->
        apply_case("#{base}#{config.separator}#{parsed.quote}#{config.separator}#{parsed.expiry}", config.case)

      :future_ddmmmyy ->
        apply_future_ddmmmyy(base, parsed, config)

      :future_yyyymmdd ->
        expiry = convert_date(parsed.expiry, :yymmdd, :yyyymmdd)
        apply_case("#{base}#{config.separator}#{parsed.quote}#{config.separator}#{expiry}", config.case)

      :future_unknown ->
        apply_case("#{base}#{config.separator}#{parsed.quote}#{config.separator}#{parsed.expiry}", config.case)
    end
  end

  @doc false
  # Handles DDMMMYY future format with Deribit vs Bybit style detection
  defp apply_future_ddmmmyy(base, parsed, config) do
    expiry_converted = convert_date(parsed.expiry, :yymmdd, :ddmmmyy)
    sep = config.separator

    # Deribit style: BTC-16JAN26 (just base-date, no quote when USD)
    # Bybit style: BTCUSDT-16JAN26 (base+quote-date)
    if sep == "-" and parsed.quote == "USD" do
      apply_case("#{base}-#{expiry_converted}", config.case)
    else
      apply_case("#{base}#{parsed.quote}-#{expiry_converted}", config.case)
    end
  end

  @doc false
  # Applies option patterns: option_ddmmmyy, option_yymmdd, option_with_settle, option_unknown
  defp apply_option_pattern(base, parsed, config) do
    case config.pattern do
      :option_ddmmmyy ->
        expiry = convert_date(parsed.expiry, :yymmdd, :ddmmmyy)
        apply_case("#{base}-#{expiry}-#{parsed.strike}-#{parsed.option_type}", config.case)

      :option_yymmdd ->
        apply_case("#{base}-#{parsed.quote}-#{parsed.expiry}-#{parsed.strike}-#{parsed.option_type}", config.case)

      :option_with_settle ->
        expiry = convert_date(parsed.expiry, :yymmdd, :ddmmmyy)
        apply_case("#{base}-#{expiry}-#{parsed.strike}-#{parsed.option_type}-#{parsed.settle}", config.case)

      :option_unknown ->
        apply_case("#{base}-#{parsed.expiry}-#{parsed.strike}-#{parsed.option_type}", config.case)
    end
  end

  # ============================================================================
  # Private: Reverse Pattern (exchange -> unified)
  # ============================================================================

  @doc false
  # Main dispatcher for exchange ID → unified symbol conversion
  defp reverse_pattern(exchange_id, config, market_type, spec) do
    aliases = Map.get(spec, :currency_aliases, %{})

    case market_type do
      :spot -> reverse_spot(exchange_id, config, aliases)
      :swap -> reverse_swap(exchange_id, config, aliases)
      :future -> reverse_future(exchange_id, config, aliases)
      :option -> reverse_option(exchange_id, config, aliases)
      _ -> normalize(exchange_id, spec)
    end
  end

  @doc false
  # Converts spot exchange ID to unified: "BTCUSDT" → "BTC/USDT"
  defp reverse_spot(exchange_id, config, aliases) do
    # Normalize case for parsing
    id = String.upcase(exchange_id)
    sep = config.separator

    {base, quote_currency} =
      if sep == "" do
        # No separator - need to find where base ends
        split_no_separator(id)
      else
        case String.split(id, sep) do
          [b, q] -> {b, q}
          _ -> {id, ""}
        end
      end

    base = apply_reverse_alias(base, aliases)
    build(base, quote_currency)
  end

  @doc false
  # Converts swap exchange ID to unified: "BTC_USD-PERPETUAL" → "BTC/USD:BTC"
  defp reverse_swap(exchange_id, config, aliases) do
    id = String.upcase(exchange_id)

    # Remove suffix if present
    id_without_suffix =
      case config.suffix do
        nil -> id
        suffix -> String.replace_suffix(id, String.upcase(suffix), "")
      end

    # Split base/quote
    sep = config.separator

    {base, quote_currency} =
      if sep == "" do
        split_no_separator(id_without_suffix)
      else
        case String.split(id_without_suffix, sep) do
          [b, q] -> {b, q}
          [b] -> {b, "USD"}
          _ -> {id_without_suffix, ""}
        end
      end

    base = apply_reverse_alias(base, aliases)

    # For swaps, settle usually equals quote (linear) or base (inverse)
    # Use quote as default settle
    settle = if quote_currency in ["USD", "USDC"], do: base, else: quote_currency
    build(base, quote_currency, settle)
  end

  @doc false
  # Converts future exchange ID to unified, dispatching by date format
  defp reverse_future(exchange_id, config, aliases) do
    id = String.upcase(exchange_id)

    case config.date_format do
      :ddmmmyy -> reverse_future_ddmmmyy(id, exchange_id, config, aliases)
      :yymmdd -> reverse_future_yymmdd(id, exchange_id, config, aliases)
      _ -> normalize(exchange_id, %{separator: config.separator, case: config.case})
    end
  end

  @doc false
  # Handles DDMMMYY future format: "BTC-16JAN26" (Deribit) or "BTCUSDT-16JAN26" (Bybit)
  # Try Bybit first (more specific pattern with quote currency) before Deribit
  defp reverse_future_ddmmmyy(id, exchange_id, config, aliases) do
    bybit_result = parse_bybit_future(id, aliases)
    deribit_result = parse_deribit_future(id, aliases)

    cond do
      bybit_result != nil -> bybit_result
      deribit_result != nil -> deribit_result
      true -> normalize(exchange_id, %{separator: config.separator, case: config.case})
    end
  end

  @doc false
  # Parses Deribit-style future: BTC-16JAN26
  defp parse_deribit_future(id, aliases) do
    case Regex.run(~r/^([A-Z]+)-(\d{1,2}[A-Z]{3}\d{2})$/, id) do
      [_, base, date] ->
        base = apply_reverse_alias(base, aliases)
        expiry = convert_date(date, :ddmmmyy, :yymmdd)
        build(base, "USD", "#{base}-#{expiry}")

      _ ->
        nil
    end
  end

  @doc false
  # Parses Bybit-style future: BTCUSDT-16JAN26
  defp parse_bybit_future(id, aliases) do
    case Regex.run(~r/^([A-Z]+)(USDT|USDC|USD)-(\d{1,2}[A-Z]{3}\d{2})$/, id) do
      [_, base, quote_currency, date] ->
        base = apply_reverse_alias(base, aliases)
        expiry = convert_date(date, :ddmmmyy, :yymmdd)
        build(base, quote_currency, "#{quote_currency}-#{expiry}")

      _ ->
        nil
    end
  end

  @doc false
  # Handles YYMMDD future format: "BTCUSDT_260327" (Binance) or "BTC-USD-260327" (OKX)
  defp reverse_future_yymmdd(id, exchange_id, config, aliases) do
    sep = config.separator
    parts = String.split(id, sep)

    case parts do
      [pair, date] when sep == "_" ->
        {base, quote_currency} = split_no_separator(pair)
        base = apply_reverse_alias(base, aliases)
        build(base, quote_currency, "#{quote_currency}-#{date}")

      [base, quote_currency, date] ->
        base = apply_reverse_alias(base, aliases)
        settle = if quote_currency in ["USD"], do: base, else: quote_currency
        build(base, quote_currency, "#{settle}-#{date}")

      _ ->
        normalize(exchange_id, %{separator: config.separator, case: config.case})
    end
  end

  @doc false
  # Converts option exchange ID to unified, dispatching by pattern type
  defp reverse_option(exchange_id, config, aliases) do
    id = String.upcase(exchange_id)

    case config.pattern do
      :option_ddmmmyy -> reverse_option_ddmmmyy(id, exchange_id, aliases)
      :option_yymmdd -> reverse_option_yymmdd(id, exchange_id, aliases)
      :option_with_settle -> reverse_option_with_settle(id, exchange_id, aliases)
      _ -> exchange_id
    end
  end

  @doc false
  # Parses Deribit-style option: BTC-12JAN26-84000-C
  defp reverse_option_ddmmmyy(id, exchange_id, aliases) do
    case Regex.run(~r/^([A-Z]+)-(\d{1,2}[A-Z]{3}\d{2})-(\d+)-([CP])$/, id) do
      [_, base, date, strike, opt_type] ->
        base = apply_reverse_alias(base, aliases)
        expiry = convert_date(date, :ddmmmyy, :yymmdd)
        build(base, "USD", "#{base}-#{expiry}-#{strike}-#{opt_type}")

      _ ->
        exchange_id
    end
  end

  @doc false
  # Parses OKX-style option: BTC-USD-260112-80000-C
  defp reverse_option_yymmdd(id, exchange_id, aliases) do
    case Regex.run(~r/^([A-Z]+)-([A-Z]+)-(\d{6})-(\d+)-([CP])$/, id) do
      [_, base, quote_currency, date, strike, opt_type] ->
        base = apply_reverse_alias(base, aliases)
        settle = if quote_currency in ["USD"], do: base, else: quote_currency
        build(base, quote_currency, "#{settle}-#{date}-#{strike}-#{opt_type}")

      _ ->
        exchange_id
    end
  end

  @doc false
  # Parses Bybit-style option: BTC-25DEC26-105000-P-USDT
  defp reverse_option_with_settle(id, exchange_id, aliases) do
    case Regex.run(~r/^([A-Z]+)-(\d{1,2}[A-Z]{3}\d{2})-(\d+)-([CP])-([A-Z]+)$/, id) do
      [_, base, date, strike, opt_type, settle] ->
        base = apply_reverse_alias(base, aliases)
        expiry = convert_date(date, :ddmmmyy, :yymmdd)
        build(base, settle, "#{settle}-#{expiry}-#{strike}-#{opt_type}")

      _ ->
        exchange_id
    end
  end

  # ============================================================================
  # Private: Helpers
  # ============================================================================

  @doc false
  # Applies case transformation (:upper, :lower, or pass-through for :mixed)
  defp apply_case(str, :upper), do: String.upcase(str)
  defp apply_case(str, :lower), do: String.downcase(str)
  defp apply_case(str, _), do: str

  @doc false
  # Pads integer to 2 digits with leading zero (e.g., 9 → "09")
  defp pad_two(n) when n < 10, do: "0#{n}"
  defp pad_two(n), do: "#{n}"

  @doc false
  # Splits a no-separator symbol (e.g., "BTCUSDT") into {base, quote} tuple.
  # Searches for known quote currencies at the end of the symbol, trying longest
  # matches first (USDT before USD) to handle overlapping currencies correctly.
  # Returns {symbol, ""} if no known quote currency is found.
  defp split_no_separator(symbol) do
    # Sort by length descending to match longest first (USDT before USD)
    sorted_quotes = Enum.sort_by(@default_quote_currencies, &String.length/1, :desc)

    case Enum.find(sorted_quotes, &String.ends_with?(symbol, &1)) do
      nil -> {symbol, ""}
      quote_currency -> {String.replace_suffix(symbol, quote_currency, ""), quote_currency}
    end
  end

  @doc """
  Gets quote currencies from spec if available, falling back to defaults.

  Specs can provide `known_quote_currencies` to support exchange-specific
  quote currencies that aren't in the default list.
  """
  @spec get_quote_currencies(map()) :: [String.t()]
  def get_quote_currencies(spec) do
    case Map.get(spec, :known_quote_currencies) do
      nil -> @default_quote_currencies
      [] -> @default_quote_currencies
      currencies when is_list(currencies) -> currencies
    end
  end

  @doc false
  # Applies currency alias for forward conversion (unified → exchange, e.g., BTC → XBT)
  defp apply_forward_alias(currency, aliases) when map_size(aliases) == 0, do: currency

  defp apply_forward_alias(currency, aliases) do
    Map.get(aliases, currency, currency)
  end

  @doc false
  # Applies currency alias for reverse conversion (exchange → unified, e.g., XBT → BTC)
  defp apply_reverse_alias(currency, aliases) when map_size(aliases) == 0, do: currency

  defp apply_reverse_alias(currency, aliases) do
    # Reverse the aliases map
    reverse = Map.new(aliases, fn {unified, exchange} -> {exchange, unified} end)
    Map.get(reverse, currency, currency)
  end

  # ============================================================================
  # KRAKEN-SPECIFIC HANDLING (R7)
  # ============================================================================

  @doc """
  Normalizes a Kraken-style symbol with X/Z prefixes.

  Kraken uses X prefix for crypto (XXBT for BTC) and Z for fiat (ZUSD for USD).
  This function handles these prefixes during normalization.

  ## Examples

      CCXT.Symbol.normalize_kraken("XXBTZUSD", kraken_spec)
      # => "BTC/USD"

      CCXT.Symbol.normalize_kraken("XETHZEUR", kraken_spec)
      # => "ETH/EUR"

  """
  @spec normalize_kraken(String.t(), map()) :: String.t()
  def normalize_kraken(symbol, spec) do
    aliases = Map.get(spec, :currency_aliases, %{})

    # Strip X/Z prefixes from currencies
    symbol_clean = strip_kraken_prefixes(symbol)

    # Apply aliases (XBT → BTC)
    reverse_aliases = Map.new(aliases, fn {unified, exchange} -> {exchange, unified} end)
    symbol_aliased = apply_currency_aliases(symbol_clean, reverse_aliases)

    # Now find and split
    find_and_split(symbol_aliased)
  end

  @doc false
  # Strips Kraken X/Z prefixes: XXBTZUSD → XBT/USD, XETHZEUR → ETH/EUR
  # Kraken convention: X prefix for crypto (XETH, XXBT), Z prefix for fiat (ZUSD, ZEUR)
  defp strip_kraken_prefixes(symbol) do
    symbol
    |> String.upcase()
    |> split_on_z_fiat()
  end

  @doc false
  # Splits on Z-prefixed fiat, then strips X prefix from base
  # XETHZEUR → {XETH, EUR} → ETH/EUR
  # XXBTZUSD → {XXBT, USD} → XBT/USD (double X becomes single X)
  defp split_on_z_fiat(symbol) do
    case Regex.run(~r/^(.+)Z(USD|EUR|GBP|JPY|CAD|AUD|CHF)$/, symbol) do
      [_, base, fiat] ->
        base_clean = strip_x_prefix(base)
        "#{base_clean}/#{fiat}"

      _ ->
        symbol
    end
  end

  @doc false
  # Strips X prefix from crypto: XETH → ETH, XXBT → XBT (keep one X for XBT alias)
  defp strip_x_prefix("XX" <> rest), do: "X" <> rest
  defp strip_x_prefix("X" <> rest), do: rest
  defp strip_x_prefix(other), do: other
end
