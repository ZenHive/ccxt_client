defmodule CCXT.Trading.Helpers.Risk do
  @moduledoc """
  Risk calculation helpers for position analysis.

  Pure functions for calculating margin headroom and liquidation distance
  from position data. These helpers work with `CCXT.Types.Position` structs.

  ## Example

      position = %CCXT.Types.Position{
        mark_price: 50_000.0,
        liquidation_price: 40_000.0
      }

      CCXT.Trading.Helpers.Risk.margin_headroom(position)
      # => 0.2 (20% headroom)

      CCXT.Trading.Helpers.Risk.liquidation_distance(position)
      # => 10_000.0 (absolute price distance)

  """

  alias CCXT.Types.Position

  @doc """
  Calculates margin headroom as a percentage.

  Returns the distance between mark price and liquidation price as a
  percentage of the mark price: `abs(mark - liq) / mark`.

  Returns `nil` if either `mark_price` or `liquidation_price` is nil.

  ## Examples

      iex> position = %CCXT.Types.Position{mark_price: 50_000.0, liquidation_price: 40_000.0}
      iex> CCXT.Trading.Helpers.Risk.margin_headroom(position)
      0.2

      iex> position = %CCXT.Types.Position{mark_price: nil, liquidation_price: 40_000.0}
      iex> CCXT.Trading.Helpers.Risk.margin_headroom(position)
      nil

  """
  @spec margin_headroom(Position.t()) :: float() | nil
  def margin_headroom(%Position{mark_price: mark, liquidation_price: liq})
      when is_number(mark) and is_number(liq) and mark > 0 do
    abs(mark - liq) / mark
  end

  def margin_headroom(%Position{}), do: nil

  @doc """
  Calculates the absolute price distance to liquidation.

  Returns `abs(mark_price - liquidation_price)`.

  Returns `nil` if either `mark_price` or `liquidation_price` is nil.

  ## Examples

      iex> position = %CCXT.Types.Position{mark_price: 50_000.0, liquidation_price: 40_000.0}
      iex> CCXT.Trading.Helpers.Risk.liquidation_distance(position)
      10_000.0

      iex> position = %CCXT.Types.Position{mark_price: 50_000.0, liquidation_price: nil}
      iex> CCXT.Trading.Helpers.Risk.liquidation_distance(position)
      nil

  """
  @spec liquidation_distance(Position.t()) :: float() | nil
  def liquidation_distance(%Position{mark_price: mark, liquidation_price: liq}) when is_number(mark) and is_number(liq) do
    abs(mark - liq)
  end

  def liquidation_distance(%Position{}), do: nil
end
