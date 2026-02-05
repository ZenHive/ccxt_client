defmodule CCXT.Portfolio do
  @moduledoc """
  Portfolio-level aggregation helpers for positions.

  Pure functions for calculating total exposure and unrealized PnL
  across a list of positions. Works with `CCXT.Types.Position` structs.

  ## Example

      positions = [
        %CCXT.Types.Position{symbol: "BTC/USDT:USDT", notional: 50_000.0, unrealized_pnl: 1000.0},
        %CCXT.Types.Position{symbol: "BTC/USDT:USDT", notional: 25_000.0, unrealized_pnl: -500.0},
        %CCXT.Types.Position{symbol: "ETH/USDT:USDT", notional: 10_000.0, unrealized_pnl: 200.0}
      ]

      CCXT.Portfolio.total_exposure(positions)
      # => %{"BTC" => 75_000.0, "ETH" => 10_000.0}

      CCXT.Portfolio.unrealized_pnl(positions)
      # => 700.0

  """

  alias CCXT.Types.Position

  @doc """
  Calculates total notional exposure grouped by base asset.

  Extracts the base asset from each position's symbol and sums the
  notional values. Positions with nil notional are skipped.

  ## Example

      positions = [
        %CCXT.Types.Position{symbol: "BTC/USDT:USDT", notional: 50_000.0},
        %CCXT.Types.Position{symbol: "BTC/USDT:USDT", notional: 25_000.0},
        %CCXT.Types.Position{symbol: "ETH/USDT:USDT", notional: 10_000.0}
      ]

      CCXT.Portfolio.total_exposure(positions)
      # => %{"BTC" => 75_000.0, "ETH" => 10_000.0}

  """
  @spec total_exposure([Position.t()]) :: %{String.t() => float()}
  def total_exposure(positions) when is_list(positions) do
    positions
    |> Enum.filter(&valid_for_exposure?/1)
    |> Enum.group_by(&extract_base_asset/1)
    |> Map.new(fn {asset, group} ->
      total = group |> Enum.map(& &1.notional) |> Enum.sum()
      {asset, total}
    end)
  end

  @doc """
  Calculates total unrealized PnL across all positions.

  Sums the `unrealized_pnl` field from all positions.
  Positions with nil unrealized_pnl are skipped.

  ## Example

      positions = [
        %CCXT.Types.Position{unrealized_pnl: 1000.0},
        %CCXT.Types.Position{unrealized_pnl: -500.0},
        %CCXT.Types.Position{unrealized_pnl: nil}
      ]

      CCXT.Portfolio.unrealized_pnl(positions)
      # => 500.0

  """
  @spec unrealized_pnl([Position.t()]) :: float()
  def unrealized_pnl(positions) when is_list(positions) do
    positions
    |> Enum.map(& &1.unrealized_pnl)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
    |> to_float()
  end

  @doc """
  Calculates total realized PnL across all positions.

  Sums the `realized_pnl` field from all positions.
  Positions with nil realized_pnl are skipped.

  ## Example

      positions = [
        %CCXT.Types.Position{realized_pnl: 500.0},
        %CCXT.Types.Position{realized_pnl: -100.0}
      ]

      CCXT.Portfolio.realized_pnl(positions)
      # => 400.0

  """
  @spec realized_pnl([Position.t()]) :: float()
  def realized_pnl(positions) when is_list(positions) do
    positions
    |> Enum.map(& &1.realized_pnl)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
    |> to_float()
  end

  # Ensure numeric value is always a float (Enum.sum([]) returns integer 0)
  @doc false
  defp to_float(value) when is_number(value), do: value * 1.0

  # Check if position is valid for exposure calculation (has notional and valid symbol)
  @doc false
  defp valid_for_exposure?(%Position{notional: notional, symbol: symbol})
       when is_number(notional) and is_binary(symbol) and symbol != "" do
    String.contains?(symbol, "/")
  end

  defp valid_for_exposure?(_), do: false

  # Extract base asset from unified symbol
  # Handles: "BTC/USDT", "BTC/USDT:USDT", "ETH/USD"
  @doc false
  defp extract_base_asset(%Position{symbol: symbol}) when is_binary(symbol) do
    symbol
    |> String.split("/")
    |> hd()
  end
end
