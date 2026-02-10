defmodule CCXT.Types.SchemaFromMapTest do
  @moduledoc """
  Meta-test covering from_map/1 for all auto-generated struct types.

  Verifies that every schema-backed wrapper module can:
  1. Accept an empty map without crashing
  2. Return the correct struct type
  3. Accept string-keyed maps (as returned by JSON decoders)
  """

  use ExUnit.Case, async: true

  @moduletag :unit

  # All 40 wrapper modules that use schema structs with from_map/1.
  # Type-alias modules (Bool, Dict, Int, etc.) are excluded — they don't define structs.
  @struct_types [
    CCXT.Types.Account,
    CCXT.Types.BalanceAccount,
    CCXT.Types.BalanceEntry,
    CCXT.Types.BorrowInterest,
    CCXT.Types.CancellationRequest,
    CCXT.Types.Conversion,
    CCXT.Types.CrossBorrowRate,
    CCXT.Types.CurrencyInterface,
    CCXT.Types.DepositAddress,
    CCXT.Types.DepositWithdrawFee,
    CCXT.Types.DepositWithdrawFeeNetwork,
    CCXT.Types.FeeInterface,
    CCXT.Types.FundingHistory,
    CCXT.Types.FundingRate,
    CCXT.Types.FundingRateHistory,
    CCXT.Types.Greeks,
    CCXT.Types.IsolatedBorrowRate,
    CCXT.Types.LastPrice,
    CCXT.Types.LedgerEntry,
    CCXT.Types.Leverage,
    CCXT.Types.LeverageTier,
    CCXT.Types.Liquidation,
    CCXT.Types.LongShortRatio,
    CCXT.Types.MarginMode,
    CCXT.Types.MarginModification,
    CCXT.Types.MarketInterface,
    CCXT.Types.MarketMarginModes,
    CCXT.Types.MinMax,
    CCXT.Types.OpenInterest,
    CCXT.Types.Option,
    CCXT.Types.Order,
    CCXT.Types.OrderBook,
    CCXT.Types.OrderRequest,
    CCXT.Types.Position,
    CCXT.Types.Ticker,
    CCXT.Types.Trade,
    CCXT.Types.TradingFeeInterface,
    CCXT.Types.Transaction,
    CCXT.Types.TransferEntry,
    CCXT.Types.WithdrawalResponse
  ]

  for type <- @struct_types do
    describe "#{inspect(type)}.from_map/1" do
      test "accepts empty map and returns correct struct" do
        result = unquote(type).from_map(%{})
        assert is_struct(result, unquote(type))
      end

      test "accepts string-keyed map" do
        result = unquote(type).from_map(%{"id" => "test", "symbol" => "BTC/USDT", "info" => %{}})
        assert is_struct(result, unquote(type))
      end
    end
  end

  test "all struct types are accounted for (sanity check)" do
    assert length(@struct_types) == 40
  end
end
