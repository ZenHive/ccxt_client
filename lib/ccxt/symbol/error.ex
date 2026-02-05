defmodule CCXT.Symbol.Error do
  @moduledoc """
  Error raised when symbol conversion fails.

  This exception is raised by the bang functions (`to_exchange_id!/3`, `from_exchange_id!/3`)
  when pattern matching or parsing fails. It provides detailed context about what went wrong.

  ## Example

      try do
        CCXT.Symbol.to_exchange_id!("INVALID", spec)
      rescue
        e in CCXT.Symbol.Error ->
          Logger.error("Symbol conversion failed: \#{e.message}")
          Logger.debug("Reason: \#{inspect(e.reason)}")
      end

  """

  defexception [:message, :symbol, :reason, :spec_name, :market_type]

  @type t :: %__MODULE__{
          message: String.t(),
          symbol: String.t() | nil,
          reason: reason(),
          spec_name: atom() | nil,
          market_type: atom() | nil
        }

  @type reason ::
          :invalid_format
          | :pattern_not_found
          | :unknown_quote_currency
          | :parse_failed
          | {:unsupported_prefix, String.t()}

  @doc """
  Creates a new SymbolError exception.

  ## Options

  - `:symbol` - The symbol that failed conversion
  - `:reason` - The specific reason for failure
  - `:spec_name` - Name of the exchange spec (if available)
  - `:market_type` - Market type that was being converted
  """
  @spec new(String.t(), keyword()) :: t()
  def new(message, opts \\ []) do
    %__MODULE__{
      message: message,
      symbol: Keyword.get(opts, :symbol),
      reason: Keyword.get(opts, :reason, :unknown),
      spec_name: Keyword.get(opts, :spec_name),
      market_type: Keyword.get(opts, :market_type)
    }
  end

  @doc """
  Creates an error for invalid symbol format.
  """
  @spec invalid_format(String.t()) :: t()
  def invalid_format(symbol) do
    new(
      "Invalid symbol format: #{inspect(symbol)}",
      symbol: symbol,
      reason: :invalid_format
    )
  end

  @doc """
  Creates an error for missing pattern configuration.
  """
  @spec pattern_not_found(String.t(), atom(), atom() | nil) :: t()
  def pattern_not_found(symbol, market_type, spec_name \\ nil) do
    spec_desc = if spec_name, do: " in #{spec_name}", else: ""

    new(
      "No symbol pattern found for market type :#{market_type}#{spec_desc}",
      symbol: symbol,
      reason: :pattern_not_found,
      spec_name: spec_name,
      market_type: market_type
    )
  end

  @doc """
  Creates an error for unknown quote currency.
  """
  @spec unknown_quote_currency(String.t(), String.t() | nil) :: t()
  def unknown_quote_currency(symbol, attempted_split \\ nil) do
    extra = if attempted_split, do: " (tried to split: #{attempted_split})", else: ""

    new(
      "Could not determine quote currency in #{inspect(symbol)}#{extra}",
      symbol: symbol,
      reason: :unknown_quote_currency
    )
  end

  @doc """
  Creates an error for parse failures.
  """
  @spec parse_failed(String.t(), term()) :: t()
  def parse_failed(symbol, reason) do
    new(
      "Failed to parse symbol #{inspect(symbol)}: #{inspect(reason)}",
      symbol: symbol,
      reason: :parse_failed
    )
  end

  @doc """
  Creates an error for unsupported prefix patterns.
  """
  @spec unsupported_prefix(String.t(), String.t()) :: t()
  def unsupported_prefix(symbol, prefix) do
    new(
      "Unsupported prefix #{inspect(prefix)} in symbol #{inspect(symbol)}",
      symbol: symbol,
      reason: {:unsupported_prefix, prefix}
    )
  end

  @impl Exception
  def message(%__MODULE__{message: msg}), do: msg
end
