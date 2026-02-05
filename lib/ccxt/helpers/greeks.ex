defmodule CCXT.Helpers.Greeks do
  @moduledoc """
  Options-related calculation helpers.

  Pure functions for calculating days to expiry and moneyness for options
  contracts. Useful for options trading strategies and filtering.

  ## Example

      # Days until option expires
      expiry_ms = 1_735_689_600_000  # 2025-01-01 00:00:00 UTC
      CCXT.Helpers.Greeks.days_to_expiry(expiry_ms)
      # => 5.5 (days from now)

      # Determine moneyness
      CCXT.Helpers.Greeks.moneyness(50_000.0, 48_000.0, :call)
      # => :itm (in the money)

  """

  @milliseconds_per_day 86_400_000

  # ATM threshold: within 0.1% of strike is considered at-the-money
  @atm_threshold 0.001

  @type moneyness :: :itm | :atm | :otm

  @doc """
  Calculates days until expiry from a timestamp in milliseconds.

  Returns a float representing the number of days (can be fractional).
  Negative values indicate the option has already expired.

  ## Examples

      # 1 day in the future
      future_ms = System.system_time(:millisecond) + 86_400_000
      CCXT.Helpers.Greeks.days_to_expiry(future_ms)
      # => ~1.0

      # Already expired (returns negative)
      past_ms = System.system_time(:millisecond) - 86_400_000
      CCXT.Helpers.Greeks.days_to_expiry(past_ms)
      # => ~-1.0

  """
  @spec days_to_expiry(integer()) :: float()
  def days_to_expiry(expiry_ms) when is_integer(expiry_ms) do
    now_ms = System.system_time(:millisecond)
    (expiry_ms - now_ms) / @milliseconds_per_day
  end

  @doc """
  Calculates days until expiry from now to a given DateTime.

  ## Example

      expiry = ~U[2025-01-01 00:00:00Z]
      CCXT.Helpers.Greeks.days_to_expiry_from_datetime(expiry)

  """
  @spec days_to_expiry_from_datetime(DateTime.t()) :: float()
  def days_to_expiry_from_datetime(%DateTime{} = expiry) do
    expiry_ms = DateTime.to_unix(expiry, :millisecond)
    days_to_expiry(expiry_ms)
  end

  @doc """
  Determines the moneyness of an option.

  Returns `:itm` (in the money), `:atm` (at the money), or `:otm` (out of the money).

  ATM threshold: spot price within 0.1% of strike is considered at-the-money.

  ## Call Options
  - ITM: spot > strike
  - OTM: spot < strike

  ## Put Options
  - ITM: spot < strike
  - OTM: spot > strike

  ## Examples

      iex> CCXT.Helpers.Greeks.moneyness(50_000.0, 48_000.0, :call)
      :itm

      iex> CCXT.Helpers.Greeks.moneyness(50_000.0, 52_000.0, :call)
      :otm

      iex> CCXT.Helpers.Greeks.moneyness(50_000.0, 48_000.0, :put)
      :otm

      iex> CCXT.Helpers.Greeks.moneyness(50_000.0, 52_000.0, :put)
      :itm

      iex> CCXT.Helpers.Greeks.moneyness(50_000.0, 50_000.0, :call)
      :atm

  """
  @spec moneyness(number(), number(), :call | :put) :: moneyness()
  def moneyness(spot, strike, option_type) when is_number(spot) and is_number(strike) and spot > 0 and strike > 0 do
    # Calculate how far spot is from strike as a ratio
    ratio = abs(spot - strike) / strike

    cond do
      ratio <= @atm_threshold ->
        :atm

      option_type == :call ->
        if spot > strike, do: :itm, else: :otm

      option_type == :put ->
        if spot < strike, do: :itm, else: :otm
    end
  end
end
