defmodule CCXT.MethodCategories do
  @moduledoc """
  Shared method categorization for hints and introspection.

  This module defines which unified API methods require specific parameters
  like account type or derivatives category. Used by both `CCXT.Error.Hints`
  and `CCXT.Generator.Introspection` to avoid duplication.
  """

  # Methods that commonly require account type parameter (e.g., unified, spot, contract)
  @account_type_methods [
    :fetch_balance,
    :fetch_positions,
    :fetch_position,
    :fetch_account_positions,
    :fetch_ledger
  ]

  # Methods that commonly require derivatives category (linear/inverse/option)
  @derivatives_methods [
    :fetch_positions,
    :fetch_position,
    :fetch_funding_rate,
    :fetch_funding_rate_history,
    :fetch_funding_rates,
    :fetch_open_interest
  ]

  # Methods that use OHLCV timestamps (may expect seconds or milliseconds)
  @ohlcv_methods [:fetch_ohlcv]

  @doc """
  Returns methods that commonly require an account type parameter.

  For exchanges with unified account systems (like Bybit), these methods
  often need an `accountType` parameter (e.g., "unified", "spot", "contract").
  """
  @spec account_type_methods() :: [atom()]
  def account_type_methods, do: @account_type_methods

  @doc """
  Returns methods that commonly require a derivatives category parameter.

  For derivatives endpoints, these methods often need a `category` parameter
  (e.g., "linear", "inverse", "option").
  """
  @spec derivatives_methods() :: [atom()]
  def derivatives_methods, do: @derivatives_methods

  @doc """
  Returns methods that use OHLCV timestamps.

  For these methods, the library auto-converts millisecond timestamps to the
  exchange's expected format (milliseconds or seconds) based on the spec's
  `ohlcv_timestamp_resolution` field.
  """
  @spec ohlcv_methods() :: [atom()]
  def ohlcv_methods, do: @ohlcv_methods
end
