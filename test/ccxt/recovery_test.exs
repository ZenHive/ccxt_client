defmodule CCXT.RecoveryTest do
  use ExUnit.Case, async: true

  alias CCXT.Recovery

  # Mock credentials for testing
  defp mock_credentials do
    %CCXT.Credentials{
      api_key: "test_key",
      secret: "test_secret"
    }
  end

  # Mock exchange modules namespaced under test module to prevent cross-file collisions
  defmodule EmptyOrdersExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts), do: {:ok, []}
  end

  defmodule TimeFilterExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)

      {:ok,
       [
         %{"id" => "1", "timestamp" => now - 120_000, "symbol" => "BTC/USDT"},
         %{"id" => "2", "timestamp" => now - 30_000, "symbol" => "BTC/USDT"},
         %{"id" => "3", "timestamp" => now - 10_000, "symbol" => "BTC/USDT"}
       ]}
    end
  end

  defmodule SideFilterExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)

      {:ok,
       [
         %{"id" => "1", "side" => "buy", "timestamp" => now - 1000},
         %{"id" => "2", "side" => "sell", "timestamp" => now - 1000},
         %{"id" => "3", "side" => "buy", "timestamp" => now - 1000}
       ]}
    end
  end

  defmodule AmountFilterExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)

      {:ok,
       [
         %{"id" => "1", "amount" => 1.0, "timestamp" => now - 1000},
         %{"id" => "2", "amount" => 1.005, "timestamp" => now - 1000},
         %{"id" => "3", "amount" => 1.02, "timestamp" => now - 1000},
         %{"id" => "4", "amount" => 0.5, "timestamp" => now - 1000}
       ]}
    end
  end

  defmodule OpenOrdersExchange do
    @moduledoc false
    def fetch_open_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)
      {:ok, [%{"id" => "open1", "status" => "open", "timestamp" => now - 1000}]}
    end
  end

  defmodule ClosedOrdersExchange do
    @moduledoc false
    def fetch_closed_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)
      {:ok, [%{"id" => "closed1", "status" => "closed", "timestamp" => now - 1000}]}
    end
  end

  defmodule CombinedOrdersExchange do
    @moduledoc false
    def fetch_open_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)
      {:ok, [%{"id" => "open1", "timestamp" => now - 1000}]}
    end

    def fetch_closed_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)
      {:ok, [%{"id" => "closed1", "timestamp" => now - 1000}]}
    end
  end

  defmodule ErrorExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts), do: {:error, :network_error}
  end

  defmodule NoFunctionsExchange do
    @moduledoc false
  end

  defmodule DateTimeExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)
      {:ok, [%{"id" => "1", "timestamp" => now - 1000}]}
    end
  end

  defmodule ClientIdExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)

      {:ok,
       [
         %{"id" => "1", "clientOrderId" => "my-order-123", "timestamp" => now - 1000},
         %{"id" => "2", "clientOrderId" => "other-order", "timestamp" => now - 1000}
       ]}
    end
  end

  defmodule NoMatchExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)
      {:ok, [%{"id" => "1", "clientOrderId" => "other-order", "timestamp" => now - 1000}]}
    end
  end

  defmodule SymbolRequiredExchange do
    @moduledoc false
  end

  defmodule DirectClientIdExchange do
    @moduledoc false
    def fetch_order_by_client_id(_credentials, client_order_id, _symbol) do
      {:ok, %{"id" => "direct", "clientOrderId" => client_order_id}}
    end
  end

  defmodule AltFieldExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)
      {:ok, [%{"id" => "1", "client_order_id" => "my-order-123", "timestamp" => now - 1000}]}
    end
  end

  defmodule AtomKeyExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)
      {:ok, [%{id: "1", clientOrderId: "my-order-123", timestamp: now - 1000}]}
    end
  end

  defmodule MissingTimestampExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts) do
      {:ok, [%{"id" => "1", "side" => "buy"}]}
    end
  end

  defmodule MissingAmountExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)

      {:ok,
       [
         %{"id" => "1", "timestamp" => now - 1000},
         %{"id" => "2", "amount" => 1.0, "timestamp" => now - 1000}
       ]}
    end
  end

  defmodule DateTimeOrderExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts) do
      {:ok, [%{"id" => "1", "timestamp" => DateTime.add(DateTime.utc_now(), -1, :second)}]}
    end
  end

  defmodule ExceptionExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts), do: raise("Boom!")
  end

  defmodule ThrowExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts), do: throw(:oops)
  end

  defmodule FetchOrderErrorExchange do
    @moduledoc false
    def fetch_order(_credentials, _client_id, _symbol), do: {:error, :not_found}

    def fetch_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)
      {:ok, [%{"id" => "1", "clientOrderId" => "target-123", "timestamp" => now - 1000}]}
    end
  end

  defmodule RaisingClientIdExchange do
    @moduledoc false
    def fetch_order_by_client_id(_credentials, _client_id, _symbol), do: raise("Unexpected error")

    def fetch_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)
      {:ok, [%{"id" => "1", "clientOrderId" => "rescue-123", "timestamp" => now - 1000}]}
    end
  end

  defmodule AtomSideExchange do
    @moduledoc false
    def fetch_orders(_credentials, _symbol, _opts) do
      now = System.os_time(:millisecond)

      {:ok,
       [
         %{id: "1", side: :buy, timestamp: now - 1000},
         %{id: "2", side: :sell, timestamp: now - 1000}
       ]}
    end
  end

  describe "find_recent_orders/3" do
    test "requires symbol option" do
      assert_raise KeyError, ~r/key :symbol not found/, fn ->
        Recovery.find_recent_orders(MockExchange, mock_credentials(), [])
      end
    end

    test "returns empty list when no orders match" do
      {:ok, orders} =
        Recovery.find_recent_orders(EmptyOrdersExchange, mock_credentials(), symbol: "BTC/USDT")

      assert orders == []
    end

    test "filters orders by time window" do
      now = System.os_time(:millisecond)
      # Only orders in the last 60 seconds
      {:ok, orders} =
        Recovery.find_recent_orders(TimeFilterExchange, mock_credentials(),
          symbol: "BTC/USDT",
          since: now - 60_000
        )

      assert length(orders) == 2
      assert Enum.all?(orders, fn o -> o["id"] in ["2", "3"] end)
    end

    test "filters orders by side" do
      {:ok, buy_orders} =
        Recovery.find_recent_orders(SideFilterExchange, mock_credentials(),
          symbol: "BTC/USDT",
          side: :buy
        )

      assert length(buy_orders) == 2
      assert Enum.all?(buy_orders, fn o -> o["side"] == "buy" end)

      {:ok, sell_orders} =
        Recovery.find_recent_orders(SideFilterExchange, mock_credentials(),
          symbol: "BTC/USDT",
          side: :sell
        )

      assert length(sell_orders) == 1
      assert hd(sell_orders)["side"] == "sell"
    end

    test "filters orders by amount tolerance" do
      # 1% tolerance around 1.0 = 0.99 to 1.01
      {:ok, orders} =
        Recovery.find_recent_orders(AmountFilterExchange, mock_credentials(),
          symbol: "BTC/USDT",
          amount: 1.0,
          amount_tolerance: 0.01
        )

      assert length(orders) == 2
      assert Enum.all?(orders, fn o -> o["id"] in ["1", "2"] end)
    end

    test "fetches open orders only when status is :open" do
      {:ok, orders} =
        Recovery.find_recent_orders(OpenOrdersExchange, mock_credentials(),
          symbol: "BTC/USDT",
          status: :open
        )

      assert length(orders) == 1
      assert hd(orders)["id"] == "open1"
    end

    test "fetches closed orders only when status is :closed" do
      {:ok, orders} =
        Recovery.find_recent_orders(ClosedOrdersExchange, mock_credentials(),
          symbol: "BTC/USDT",
          status: :closed
        )

      assert length(orders) == 1
      assert hd(orders)["id"] == "closed1"
    end

    test "combines open and closed when fetch_orders not available" do
      {:ok, orders} =
        Recovery.find_recent_orders(CombinedOrdersExchange, mock_credentials(),
          symbol: "BTC/USDT",
          status: :all
        )

      assert length(orders) == 2
      ids = Enum.map(orders, & &1["id"])
      assert "open1" in ids
      assert "closed1" in ids
    end

    test "handles exchange errors gracefully" do
      result =
        Recovery.find_recent_orders(ErrorExchange, mock_credentials(), symbol: "BTC/USDT")

      assert {:error, :network_error} = result
    end

    test "handles function not exported" do
      result =
        Recovery.find_recent_orders(NoFunctionsExchange, mock_credentials(), symbol: "BTC/USDT")

      assert {:error, {:function_not_exported, _}} = result
    end

    test "accepts DateTime for since/until" do
      since = DateTime.add(DateTime.utc_now(), -60, :second)
      until_time = DateTime.utc_now()

      {:ok, orders} =
        Recovery.find_recent_orders(DateTimeExchange, mock_credentials(),
          symbol: "BTC/USDT",
          since: since,
          until: until_time
        )

      assert length(orders) == 1
    end
  end

  describe "find_by_client_id/4" do
    test "finds order by client_order_id in recent orders" do
      {:ok, order} =
        Recovery.find_by_client_id(ClientIdExchange, mock_credentials(), "my-order-123", symbol: "BTC/USDT")

      assert order["id"] == "1"
      assert order["clientOrderId"] == "my-order-123"
    end

    test "returns :not_found when client_order_id doesn't exist" do
      result =
        Recovery.find_by_client_id(NoMatchExchange, mock_credentials(), "nonexistent", symbol: "BTC/USDT")

      assert {:error, :not_found} = result
    end

    test "returns error when symbol not provided and required" do
      result =
        Recovery.find_by_client_id(SymbolRequiredExchange, mock_credentials(), "my-order-123")

      assert {:error, {:symbol_required, _}} = result
    end

    test "uses fetch_order_by_client_id when available" do
      {:ok, order} =
        Recovery.find_by_client_id(
          DirectClientIdExchange,
          mock_credentials(),
          "my-order-123",
          symbol: "BTC/USDT"
        )

      assert order["id"] == "direct"
    end

    test "handles alternative client_order_id field names" do
      {:ok, order} =
        Recovery.find_by_client_id(AltFieldExchange, mock_credentials(), "my-order-123", symbol: "BTC/USDT")

      assert order["id"] == "1"
    end

    test "handles atom keys in orders" do
      {:ok, order} =
        Recovery.find_by_client_id(AtomKeyExchange, mock_credentials(), "my-order-123", symbol: "BTC/USDT")

      assert order[:id] == "1"
    end
  end

  describe "edge cases" do
    test "handles orders with missing timestamp" do
      # Orders without timestamp should be filtered out by time filter
      {:ok, orders} =
        Recovery.find_recent_orders(MissingTimestampExchange, mock_credentials(), symbol: "BTC/USDT")

      # Will be filtered out because timestamp = 0 is before since
      assert orders == []
    end

    test "handles orders with missing amount" do
      {:ok, orders} =
        Recovery.find_recent_orders(MissingAmountExchange, mock_credentials(),
          symbol: "BTC/USDT",
          amount: 1.0,
          amount_tolerance: 0.01
        )

      # Only the order with amount should match
      assert length(orders) == 1
      assert hd(orders)["id"] == "2"
    end

    test "handles DateTime timestamps in orders" do
      {:ok, orders} =
        Recovery.find_recent_orders(DateTimeOrderExchange, mock_credentials(), symbol: "BTC/USDT")

      assert length(orders) == 1
    end

    test "handles exceptions in exchange calls" do
      result =
        Recovery.find_recent_orders(ExceptionExchange, mock_credentials(), symbol: "BTC/USDT")

      assert {:error, {:exception, "Boom!"}} = result
    end

    test "call_if_exported handles throw" do
      result =
        Recovery.find_recent_orders(ThrowExchange, mock_credentials(), symbol: "BTC/USDT")

      assert {:error, {:throw, :oops}} = result
    end

    test "try_fetch_by_client_id falls back when fetch_order returns error" do
      {:ok, order} =
        Recovery.find_by_client_id(
          FetchOrderErrorExchange,
          mock_credentials(),
          "target-123",
          symbol: "BTC/USDT"
        )

      assert order["clientOrderId"] == "target-123"
    end

    test "try_fetch_by_client_id rescues exceptions from fetch_order_by_client_id" do
      {:ok, order} =
        Recovery.find_by_client_id(
          RaisingClientIdExchange,
          mock_credentials(),
          "rescue-123",
          symbol: "BTC/USDT"
        )

      assert order["clientOrderId"] == "rescue-123"
    end

    test "filter_by_side works with atom side keys" do
      {:ok, orders} =
        Recovery.find_recent_orders(AtomSideExchange, mock_credentials(),
          symbol: "BTC/USDT",
          side: :buy
        )

      assert length(orders) == 1
      assert hd(orders)[:side] == :buy
    end
  end
end
