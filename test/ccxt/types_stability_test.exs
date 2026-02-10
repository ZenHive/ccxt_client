defmodule CCXT.TypesStabilityTest do
  @moduledoc """
  Contract tests for the 6 core CCXT types.

  These tests enforce the additive-only stability policy: removing a contracted
  field from any core type struct will fail this test. New fields may be added
  freely — the test only checks that existing contracted fields remain present.

  See lib/ccxt/types/README.md "Stability Policy" for the full contract.
  """
  use ExUnit.Case, async: true

  # ===========================================================================
  # Contracted Fields
  #
  # These lists represent the public API contract. Fields listed here MUST
  # remain present in the struct. Adding new fields is always safe.
  # Removing or renaming a field here requires a major version bump.
  # ===========================================================================

  alias CCXT.Types.Balance
  alias CCXT.Types.Order
  alias CCXT.Types.OrderBook
  alias CCXT.Types.Position

  @ticker_fields [
    :symbol,
    :raw,
    :timestamp,
    :datetime,
    :high,
    :low,
    :bid,
    :bid_volume,
    :ask,
    :ask_volume,
    :vwap,
    :open,
    :close,
    :last,
    :previous_close,
    :change,
    :percentage,
    :average,
    :quote_volume,
    :base_volume,
    :index_price,
    :mark_price
  ]

  @order_fields [
    :id,
    :client_order_id,
    :datetime,
    :timestamp,
    :last_trade_timestamp,
    :last_update_timestamp,
    :status,
    :symbol,
    :type,
    :time_in_force,
    :side,
    :price,
    :average,
    :amount,
    :filled,
    :remaining,
    :stop_price,
    :trigger_price,
    :take_profit_price,
    :stop_loss_price,
    :cost,
    :trades,
    :fee,
    :reduce_only,
    :post_only,
    :raw
  ]

  @position_fields [
    :symbol,
    :id,
    :raw,
    :timestamp,
    :datetime,
    :contracts,
    :contract_size,
    :side,
    :notional,
    :leverage,
    :unrealized_pnl,
    :realized_pnl,
    :collateral,
    :entry_price,
    :mark_price,
    :liquidation_price,
    :margin_mode,
    :hedged,
    :maintenance_margin,
    :maintenance_margin_percentage,
    :initial_margin,
    :initial_margin_percentage,
    :margin_ratio,
    :last_update_timestamp,
    :last_price,
    :stop_loss_price,
    :take_profit_price,
    :percentage,
    :margin
  ]

  @order_book_fields [
    :asks,
    :bids,
    :datetime,
    :timestamp,
    :nonce,
    :symbol,
    :raw
  ]

  @trade_fields [
    :raw,
    :amount,
    :datetime,
    :id,
    :order_id,
    :price,
    :timestamp,
    :type,
    :side,
    :symbol,
    :taker_or_maker,
    :cost,
    :fee
  ]

  @balance_fields [
    :free,
    :used,
    :total,
    :timestamp,
    :datetime,
    :raw
  ]

  # ===========================================================================
  # Field Presence Tests
  # ===========================================================================

  describe "Ticker struct stability" do
    test "all contracted fields are present" do
      actual_fields = struct_fields(CCXT.Types.Ticker)
      assert_contracted_fields("Ticker", @ticker_fields, actual_fields)
    end
  end

  describe "Order struct stability" do
    test "all contracted fields are present" do
      actual_fields = struct_fields(Order)
      assert_contracted_fields("Order", @order_fields, actual_fields)
    end

    test "helper functions are present" do
      Code.ensure_loaded!(Order)
      assert function_exported?(Order, :open?, 1)
      assert function_exported?(Order, :filled?, 1)
      assert function_exported?(Order, :fill_percentage, 1)
    end
  end

  describe "Position struct stability" do
    test "all contracted fields are present" do
      actual_fields = struct_fields(Position)
      assert_contracted_fields("Position", @position_fields, actual_fields)
    end

    test "helper functions are present" do
      Code.ensure_loaded!(Position)
      assert function_exported?(Position, :long?, 1)
      assert function_exported?(Position, :short?, 1)
      assert function_exported?(Position, :profitable?, 1)
    end
  end

  describe "OrderBook struct stability" do
    test "all contracted fields are present" do
      actual_fields = struct_fields(OrderBook)
      assert_contracted_fields("OrderBook", @order_book_fields, actual_fields)
    end

    test "helper functions are present" do
      Code.ensure_loaded!(OrderBook)
      assert function_exported?(OrderBook, :best_bid, 1)
      assert function_exported?(OrderBook, :best_ask, 1)
      assert function_exported?(OrderBook, :spread, 1)
    end
  end

  describe "Trade struct stability" do
    test "all contracted fields are present" do
      actual_fields = struct_fields(CCXT.Types.Trade)
      assert_contracted_fields("Trade", @trade_fields, actual_fields)
    end
  end

  describe "Balance struct stability" do
    test "all contracted fields are present" do
      actual_fields = struct_fields(Balance)
      assert_contracted_fields("Balance", @balance_fields, actual_fields)
    end

    test "helper functions are present" do
      Code.ensure_loaded!(Balance)
      assert function_exported?(Balance, :get, 2)
      assert function_exported?(Balance, :currencies, 1)
      assert function_exported?(Balance, :non_zero, 1)
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  @doc false
  defp struct_fields(module) do
    module.__struct__()
    |> Map.keys()
    |> List.delete(:__struct__)
  end

  @doc false
  defp assert_contracted_fields(type_name, contracted, actual) do
    missing = contracted -- actual

    if missing != [] do
      flunk("""
      #{type_name} struct is missing contracted fields: #{inspect(missing)}

      Contracted fields are part of the public API stability contract.
      Removing them requires a major version bump.
      See lib/ccxt/types/README.md "Stability Policy" for details.
      """)
    end
  end
end
