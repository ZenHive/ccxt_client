defmodule CCXT.Types.LedgerEntryTest do
  use ExUnit.Case, async: true

  alias CCXT.Types.LedgerEntry

  describe "from_map/1" do
    test "normalizes status string to atom" do
      assert LedgerEntry.from_map(%{status: "pending"}).status == :pending
      assert LedgerEntry.from_map(%{status: "ok"}).status == :ok
      assert LedgerEntry.from_map(%{status: "failed"}).status == :failed
      assert LedgerEntry.from_map(%{status: "canceled"}).status == :canceled
    end

    test "normalizes cancelled to canceled" do
      assert LedgerEntry.from_map(%{status: "cancelled"}).status == :canceled
    end

    test "normalizes direction string to atom" do
      assert LedgerEntry.from_map(%{direction: "in"}).direction == :in
      assert LedgerEntry.from_map(%{direction: "out"}).direction == :out
    end

    test "normalizes type via to_atom_safe" do
      # These are existing atoms so to_atom_safe will convert them
      assert LedgerEntry.from_map(%{type: "trade"}).type == :trade
      assert LedgerEntry.from_map(%{type: "fee"}).type == :fee
      assert LedgerEntry.from_map(%{type: "deposit"}).type == :deposit
      assert LedgerEntry.from_map(%{type: "withdrawal"}).type == :withdrawal
    end

    test "handles nil fields" do
      entry = LedgerEntry.from_map(%{status: nil, type: nil, direction: nil})
      assert entry.status == nil
      assert entry.type == nil
      assert entry.direction == nil
    end

    test "preserves other fields" do
      map = %{
        id: "ledger-456",
        currency: "ETH",
        amount: 2.0,
        status: "ok",
        type: "trade",
        direction: "in"
      }

      entry = LedgerEntry.from_map(map)
      assert entry.id == "ledger-456"
      assert entry.currency == "ETH"
      assert entry.amount == 2.0
    end
  end
end
