defmodule CCXT.Trading.Options.Deribit do
  @moduledoc """
  Deribit option symbol parsing utilities.

  Parses Deribit-format option symbols like "BTC-31JAN26-84000-C" into
  structured data for analysis.

  ## Example

      CCXT.Trading.Options.Deribit.parse_option("BTC-31JAN26-84000-C")
      # => {:ok, %{underlying: "BTC", expiry: ~D[2026-01-31], strike: 84000.0, type: :call}}

      CCXT.Trading.Options.Deribit.parse_option("ETH-28MAR25-2500-P")
      # => {:ok, %{underlying: "ETH", expiry: ~D[2025-03-28], strike: 2500.0, type: :put}}

  """

  @months_map %{
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

  # Pattern: UNDERLYING-DDMMMYY-STRIKE-TYPE
  # Examples: BTC-31JAN26-84000-C, ETH-28MAR25-2500-P
  @symbol_pattern ~r/^([A-Z]+)-(\d{1,2})([A-Z]{3})(\d{2})-(\d+)-([CP])$/

  @typedoc "Parsed option symbol data"
  @type parsed_option :: %{
          underlying: String.t(),
          expiry: Date.t(),
          strike: float(),
          type: :call | :put
        }

  @doc """
  Parse a Deribit option symbol into structured data.

  ## Parameters

    * `symbol` - Deribit option symbol (e.g., "BTC-31JAN26-84000-C")

  ## Returns

    * `{:ok, parsed}` - Successfully parsed option data
    * `{:error, :invalid_format}` - Symbol doesn't match expected format

  ## Example

      iex> CCXT.Trading.Options.Deribit.parse_option("BTC-31JAN26-84000-C")
      {:ok, %{underlying: "BTC", expiry: ~D[2026-01-31], strike: 84000.0, type: :call}}

      iex> CCXT.Trading.Options.Deribit.parse_option("invalid")
      {:error, :invalid_format}

  """
  @spec parse_option(String.t()) :: {:ok, parsed_option()} | {:error, :invalid_format}
  def parse_option(symbol) when is_binary(symbol) do
    case Regex.run(@symbol_pattern, symbol) do
      [_full, underlying, day, month_str, year, strike, type] ->
        with {:ok, expiry} <- parse_expiry(day, month_str, year),
             {:ok, option_type} <- parse_type(type) do
          {:ok,
           %{
             underlying: underlying,
             expiry: expiry,
             strike: String.to_integer(strike) * 1.0,
             type: option_type
           }}
        end

      nil ->
        {:error, :invalid_format}
    end
  end

  @doc """
  Parse a Deribit option symbol, raising on failure.

  Same as `parse_option/1` but raises `ArgumentError` on invalid format.

  ## Example

      iex> CCXT.Trading.Options.Deribit.parse_option!("BTC-31JAN26-84000-C")
      %{underlying: "BTC", expiry: ~D[2026-01-31], strike: 84000.0, type: :call}

  """
  @spec parse_option!(String.t()) :: parsed_option()
  def parse_option!(symbol) when is_binary(symbol) do
    case parse_option(symbol) do
      {:ok, parsed} -> parsed
      {:error, :invalid_format} -> raise ArgumentError, "Invalid option symbol: #{symbol}"
    end
  end

  @doc """
  Extract strike price from a Deribit option symbol.

  ## Example

      iex> CCXT.Trading.Options.Deribit.strike("BTC-31JAN26-84000-C")
      {:ok, 84000.0}

  """
  @spec strike(String.t()) :: {:ok, float()} | {:error, :invalid_format}
  def strike(symbol) when is_binary(symbol) do
    case parse_option(symbol) do
      {:ok, %{strike: strike}} -> {:ok, strike}
      error -> error
    end
  end

  @doc """
  Extract expiry date from a Deribit option symbol.

  ## Example

      iex> CCXT.Trading.Options.Deribit.expiry("BTC-31JAN26-84000-C")
      {:ok, ~D[2026-01-31]}

  """
  @spec expiry(String.t()) :: {:ok, Date.t()} | {:error, :invalid_format}
  def expiry(symbol) when is_binary(symbol) do
    case parse_option(symbol) do
      {:ok, %{expiry: expiry}} -> {:ok, expiry}
      error -> error
    end
  end

  @doc """
  Extract option type (:call or :put) from a Deribit option symbol.

  ## Example

      iex> CCXT.Trading.Options.Deribit.option_type("BTC-31JAN26-84000-C")
      {:ok, :call}

  """
  @spec option_type(String.t()) :: {:ok, :call | :put} | {:error, :invalid_format}
  def option_type(symbol) when is_binary(symbol) do
    case parse_option(symbol) do
      {:ok, %{type: type}} -> {:ok, type}
      error -> error
    end
  end

  @doc """
  Extract underlying asset from a Deribit option symbol.

  ## Example

      iex> CCXT.Trading.Options.Deribit.underlying("BTC-31JAN26-84000-C")
      {:ok, "BTC"}

  """
  @spec underlying(String.t()) :: {:ok, String.t()} | {:error, :invalid_format}
  def underlying(symbol) when is_binary(symbol) do
    case parse_option(symbol) do
      {:ok, %{underlying: underlying}} -> {:ok, underlying}
      error -> error
    end
  end

  @doc """
  Check if a symbol is a valid Deribit option format.

  ## Example

      iex> CCXT.Trading.Options.Deribit.valid_option?("BTC-31JAN26-84000-C")
      true

      iex> CCXT.Trading.Options.Deribit.valid_option?("BTC/USDT")
      false

  """
  @spec valid_option?(String.t()) :: boolean()
  def valid_option?(symbol) when is_binary(symbol) do
    match?({:ok, _}, parse_option(symbol))
  end

  # Parse expiry date from day, month string, and 2-digit year
  @doc false
  defp parse_expiry(day, month_str, year) do
    month = Map.get(@months_map, month_str)

    if month do
      day_int = String.to_integer(day)
      # Assume 20xx century for 2-digit years
      year_int = 2000 + String.to_integer(year)

      case Date.new(year_int, month, day_int) do
        {:ok, date} -> {:ok, date}
        {:error, _} -> {:error, :invalid_format}
      end
    else
      {:error, :invalid_format}
    end
  end

  # Parse option type from C/P suffix
  @doc false
  defp parse_type("C"), do: {:ok, :call}
  defp parse_type("P"), do: {:ok, :put}
end
