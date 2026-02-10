defmodule CCXT.Types.TransactionTest do
  use ExUnit.Case, async: true

  alias CCXT.Types.Transaction

  describe "from_map/1" do
    test "normalizes status string to atom" do
      assert Transaction.from_map(%{status: "pending"}).status == :pending
      assert Transaction.from_map(%{status: "ok"}).status == :ok
      assert Transaction.from_map(%{status: "failed"}).status == :failed
      assert Transaction.from_map(%{status: "canceled"}).status == :canceled
    end

    test "normalizes cancelled to canceled" do
      assert Transaction.from_map(%{status: "cancelled"}).status == :canceled
    end

    test "normalizes type string to atom" do
      assert Transaction.from_map(%{type: "deposit"}).type == :deposit
      assert Transaction.from_map(%{type: "withdrawal"}).type == :withdrawal
    end

    test "handles nil status and type" do
      tx = Transaction.from_map(%{status: nil, type: nil})
      assert tx.status == nil
      assert tx.type == nil
    end

    test "preserves other fields" do
      map = %{
        id: "tx-123",
        txid: "0xabc",
        currency: "BTC",
        amount: 1.5,
        status: "ok",
        type: "deposit"
      }

      tx = Transaction.from_map(map)
      assert tx.id == "tx-123"
      assert tx.txid == "0xabc"
      assert tx.currency == "BTC"
      assert tx.amount == 1.5
    end
  end

  describe "deposit?/1" do
    test "returns true for deposits" do
      assert Transaction.deposit?(%Transaction{type: :deposit})
    end

    test "returns false for withdrawals" do
      refute Transaction.deposit?(%Transaction{type: :withdrawal})
    end

    test "returns false for nil type" do
      refute Transaction.deposit?(%Transaction{type: nil})
    end
  end

  describe "withdrawal?/1" do
    test "returns true for withdrawals" do
      assert Transaction.withdrawal?(%Transaction{type: :withdrawal})
    end

    test "returns false for deposits" do
      refute Transaction.withdrawal?(%Transaction{type: :deposit})
    end
  end

  describe "pending?/1" do
    test "returns true for pending status" do
      assert Transaction.pending?(%Transaction{status: :pending})
    end

    test "returns false for ok status" do
      refute Transaction.pending?(%Transaction{status: :ok})
    end

    test "returns false for nil status" do
      refute Transaction.pending?(%Transaction{status: nil})
    end
  end
end
