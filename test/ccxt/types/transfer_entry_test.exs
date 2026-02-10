defmodule CCXT.Types.TransferEntryTest do
  use ExUnit.Case, async: true

  alias CCXT.Types.TransferEntry

  describe "from_map/1" do
    test "normalizes status string to atom" do
      assert TransferEntry.from_map(%{status: "pending"}).status == :pending
      assert TransferEntry.from_map(%{status: "ok"}).status == :ok
      assert TransferEntry.from_map(%{status: "failed"}).status == :failed
      assert TransferEntry.from_map(%{status: "canceled"}).status == :canceled
    end

    test "normalizes cancelled to canceled" do
      assert TransferEntry.from_map(%{status: "cancelled"}).status == :canceled
    end

    test "handles nil status" do
      assert TransferEntry.from_map(%{status: nil}).status == nil
    end

    test "preserves other fields" do
      map = %{
        id: "transfer-789",
        currency: "USDT",
        amount: 1000.0,
        status: "ok"
      }

      entry = TransferEntry.from_map(map)
      assert entry.id == "transfer-789"
      assert entry.currency == "USDT"
      assert entry.amount == 1000.0
    end
  end
end
