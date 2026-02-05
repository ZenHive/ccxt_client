defmodule CCXT.Types.BalanceTest do
  use ExUnit.Case, async: true

  alias CCXT.Types.Balance

  describe "from_map/1" do
    test "creates balance from map" do
      map = %{
        free: %{"BTC" => 1.5, "USDT" => 10_000.0},
        used: %{"BTC" => 0.5, "USDT" => 5000.0},
        total: %{"BTC" => 2.0, "USDT" => 15_000.0}
      }

      balance = Balance.from_map(map)

      assert balance.free == %{"BTC" => 1.5, "USDT" => 10_000.0}
      assert balance.used == %{"BTC" => 0.5, "USDT" => 5000.0}
      assert balance.total == %{"BTC" => 2.0, "USDT" => 15_000.0}
    end

    test "defaults to empty maps" do
      balance = Balance.from_map(%{})

      assert balance.free == %{}
      assert balance.used == %{}
      assert balance.total == %{}
    end
  end

  describe "get/2" do
    test "returns balance for existing currency" do
      balance = %Balance{
        free: %{"BTC" => 1.5},
        used: %{"BTC" => 0.5},
        total: %{"BTC" => 2.0}
      }

      assert Balance.get(balance, "BTC") == %{free: 1.5, used: 0.5, total: 2.0}
    end

    test "returns nil for non-existent currency" do
      balance = %Balance{free: %{}, used: %{}, total: %{}}
      assert Balance.get(balance, "BTC") == nil
    end

    test "defaults missing values to 0.0" do
      balance = %Balance{free: %{"BTC" => 1.0}, used: %{}, total: %{"BTC" => 1.0}}
      assert Balance.get(balance, "BTC") == %{free: 1.0, used: 0.0, total: 1.0}
    end
  end

  describe "currencies/1" do
    test "returns sorted list of currencies" do
      balance = %Balance{total: %{"ETH" => 1.0, "BTC" => 2.0, "USDT" => 100.0}}
      assert Balance.currencies(balance) == ["BTC", "ETH", "USDT"]
    end
  end

  describe "non_zero/1" do
    test "filters out zero balances" do
      balance = %Balance{
        free: %{"BTC" => 1.0, "ETH" => 0.0},
        used: %{"BTC" => 0.5, "ETH" => 0.0},
        total: %{"BTC" => 1.5, "ETH" => 0.0}
      }

      result = Balance.non_zero(balance)

      assert result.total == %{"BTC" => 1.5}
      assert result.free == %{"BTC" => 1.0}
      assert Map.keys(result.used) == ["BTC"]
    end
  end
end
