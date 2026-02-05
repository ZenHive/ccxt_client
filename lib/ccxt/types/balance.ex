defmodule CCXT.Types.Balance do
  @moduledoc """
  Unified account balance data from an exchange.

  Contains available and locked balances for all currencies in the account.

  ## Fields

  - `free` - Map of currency => available balance
  - `used` - Map of currency => locked/reserved balance
  - `total` - Map of currency => total balance (free + used)
  - `timestamp` - Unix timestamp in milliseconds
  - `datetime` - ISO 8601 datetime string
  - `raw` - Original response from exchange

  ## Example

      balance = %CCXT.Types.Balance{
        free: %{"BTC" => 1.5, "USDT" => 10000.0},
        used: %{"BTC" => 0.5, "USDT" => 5000.0},
        total: %{"BTC" => 2.0, "USDT" => 15000.0}
      }

      CCXT.Types.Balance.get(balance, "BTC")
      # => %{free: 1.5, used: 0.5, total: 2.0}

  """

  import CCXT.Types.Helpers, only: [get_value: 2]

  @type currency_balance :: %{
          free: float(),
          used: float(),
          total: float()
        }

  @type t :: %__MODULE__{
          free: %{String.t() => float()},
          used: %{String.t() => float()},
          total: %{String.t() => float()},
          timestamp: non_neg_integer() | nil,
          datetime: String.t() | nil,
          raw: map() | nil
        }

  defstruct free: %{},
            used: %{},
            total: %{},
            timestamp: nil,
            datetime: nil,
            raw: nil

  @doc """
  Creates a Balance from a map of values.

  Keys can be atoms or strings. Unknown keys are ignored.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      free: get_value(map, :free) || %{},
      used: get_value(map, :used) || %{},
      total: get_value(map, :total) || %{},
      timestamp: get_value(map, :timestamp),
      datetime: get_value(map, :datetime),
      raw: map
    }
  end

  @doc """
  Gets the balance for a specific currency.

  Returns a map with `:free`, `:used`, and `:total` keys,
  or nil if the currency is not in the balance.
  """
  @spec get(t(), String.t()) :: currency_balance() | nil
  def get(%__MODULE__{} = balance, currency) when is_binary(currency) do
    free = Map.get(balance.free, currency)
    used = Map.get(balance.used, currency)
    total = Map.get(balance.total, currency)

    if is_nil(free) and is_nil(used) and is_nil(total) do
      nil
    else
      %{
        free: free || 0.0,
        used: used || 0.0,
        total: total || 0.0
      }
    end
  end

  @doc """
  Returns a list of all currencies in the balance.
  """
  @spec currencies(t()) :: [String.t()]
  def currencies(%__MODULE__{} = balance) do
    balance.total
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Returns non-zero balances only.
  """
  @spec non_zero(t()) :: t()
  def non_zero(%__MODULE__{} = balance) do
    currencies_with_balance =
      balance.total
      |> Enum.filter(fn {_currency, total} -> total > 0 end)
      |> MapSet.new(fn {currency, _} -> currency end)

    %__MODULE__{
      free: Map.filter(balance.free, fn {k, _} -> MapSet.member?(currencies_with_balance, k) end),
      used: Map.filter(balance.used, fn {k, _} -> MapSet.member?(currencies_with_balance, k) end),
      total: Map.filter(balance.total, fn {k, _} -> MapSet.member?(currencies_with_balance, k) end),
      timestamp: balance.timestamp,
      datetime: balance.datetime,
      raw: balance.raw
    }
  end
end
