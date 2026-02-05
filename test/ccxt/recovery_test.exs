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

  describe "find_recent_orders/3" do
    test "requires symbol option" do
      assert_raise KeyError, ~r/key :symbol not found/, fn ->
        Recovery.find_recent_orders(MockExchange, mock_credentials(), [])
      end
    end

    test "returns empty list when no orders match" do
      defmodule EmptyOrdersExchange do
        @moduledoc false
        def fetch_orders(_credentials, _symbol, _opts) do
          {:ok, []}
        end
      end

      {:ok, orders} =
        Recovery.find_recent_orders(EmptyOrdersExchange, mock_credentials(), symbol: "BTC/USDT")

      assert orders == []
    end

    test "filters orders by time window" do
      now = System.os_time(:millisecond)
      old_time = now - 120_000
      recent_time = now - 30_000

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
      defmodule OpenOrdersExchange do
        @moduledoc false
        def fetch_open_orders(_credentials, _symbol, _opts) do
          now = System.os_time(:millisecond)
          {:ok, [%{"id" => "open1", "status" => "open", "timestamp" => now - 1000}]}
        end
      end

      {:ok, orders} =
        Recovery.find_recent_orders(OpenOrdersExchange, mock_credentials(),
          symbol: "BTC/USDT",
          status: :open
        )

      assert length(orders) == 1
      assert hd(orders)["id"] == "open1"
    end

    test "fetches closed orders only when status is :closed" do
      defmodule ClosedOrdersExchange do
        @moduledoc false
        def fetch_closed_orders(_credentials, _symbol, _opts) do
          now = System.os_time(:millisecond)
          {:ok, [%{"id" => "closed1", "status" => "closed", "timestamp" => now - 1000}]}
        end
      end

      {:ok, orders} =
        Recovery.find_recent_orders(ClosedOrdersExchange, mock_credentials(),
          symbol: "BTC/USDT",
          status: :closed
        )

      assert length(orders) == 1
      assert hd(orders)["id"] == "closed1"
    end

    test "combines open and closed when fetch_orders not available" do
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
      defmodule ErrorExchange do
        @moduledoc false
        def fetch_orders(_credentials, _symbol, _opts) do
          {:error, :network_error}
        end
      end

      result =
        Recovery.find_recent_orders(ErrorExchange, mock_credentials(), symbol: "BTC/USDT")

      assert {:error, :network_error} = result
    end

    test "handles function not exported" do
      defmodule NoFunctionsExchange do
        # No fetch functions defined
        @moduledoc false
      end

      result =
        Recovery.find_recent_orders(NoFunctionsExchange, mock_credentials(), symbol: "BTC/USDT")

      assert {:error, {:function_not_exported, _}} = result
    end

    test "accepts DateTime for since/until" do
      defmodule DateTimeExchange do
        @moduledoc false
        def fetch_orders(_credentials, _symbol, _opts) do
          now = System.os_time(:millisecond)
          {:ok, [%{"id" => "1", "timestamp" => now - 1000}]}
        end
      end

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

      {:ok, order} =
        Recovery.find_by_client_id(ClientIdExchange, mock_credentials(), "my-order-123", symbol: "BTC/USDT")

      assert order["id"] == "1"
      assert order["clientOrderId"] == "my-order-123"
    end

    test "returns :not_found when client_order_id doesn't exist" do
      defmodule NoMatchExchange do
        @moduledoc false
        def fetch_orders(_credentials, _symbol, _opts) do
          now = System.os_time(:millisecond)
          {:ok, [%{"id" => "1", "clientOrderId" => "other-order", "timestamp" => now - 1000}]}
        end
      end

      result =
        Recovery.find_by_client_id(NoMatchExchange, mock_credentials(), "nonexistent", symbol: "BTC/USDT")

      assert {:error, :not_found} = result
    end

    test "returns error when symbol not provided and required" do
      defmodule SymbolRequiredExchange do
        # Only has fetch_order which requires symbol
        @moduledoc false
      end

      result =
        Recovery.find_by_client_id(SymbolRequiredExchange, mock_credentials(), "my-order-123")

      assert {:error, {:symbol_required, _}} = result
    end

    test "uses fetch_order_by_client_id when available" do
      defmodule DirectClientIdExchange do
        @moduledoc false
        def fetch_order_by_client_id(_credentials, client_order_id, _symbol) do
          {:ok, %{"id" => "direct", "clientOrderId" => client_order_id}}
        end
      end

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
      defmodule AltFieldExchange do
        @moduledoc false
        def fetch_orders(_credentials, _symbol, _opts) do
          now = System.os_time(:millisecond)
          {:ok, [%{"id" => "1", "client_order_id" => "my-order-123", "timestamp" => now - 1000}]}
        end
      end

      {:ok, order} =
        Recovery.find_by_client_id(AltFieldExchange, mock_credentials(), "my-order-123", symbol: "BTC/USDT")

      assert order["id"] == "1"
    end

    test "handles atom keys in orders" do
      defmodule AtomKeyExchange do
        @moduledoc false
        def fetch_orders(_credentials, _symbol, _opts) do
          now = System.os_time(:millisecond)
          {:ok, [%{id: "1", clientOrderId: "my-order-123", timestamp: now - 1000}]}
        end
      end

      {:ok, order} =
        Recovery.find_by_client_id(AtomKeyExchange, mock_credentials(), "my-order-123", symbol: "BTC/USDT")

      assert order[:id] == "1"
    end
  end

  describe "edge cases" do
    test "handles orders with missing timestamp" do
      defmodule MissingTimestampExchange do
        @moduledoc false
        def fetch_orders(_credentials, _symbol, _opts) do
          {:ok, [%{"id" => "1", "side" => "buy"}]}
        end
      end

      # Orders without timestamp should be filtered out by time filter
      {:ok, orders} =
        Recovery.find_recent_orders(MissingTimestampExchange, mock_credentials(), symbol: "BTC/USDT")

      # Will be filtered out because timestamp = 0 is before since
      assert orders == []
    end

    test "handles orders with missing amount" do
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
      defmodule DateTimeOrderExchange do
        @moduledoc false
        def fetch_orders(_credentials, _symbol, _opts) do
          # Use a timestamp slightly in the past to avoid race conditions
          {:ok, [%{"id" => "1", "timestamp" => DateTime.add(DateTime.utc_now(), -1, :second)}]}
        end
      end

      {:ok, orders} =
        Recovery.find_recent_orders(DateTimeOrderExchange, mock_credentials(), symbol: "BTC/USDT")

      assert length(orders) == 1
    end

    test "handles exceptions in exchange calls" do
      defmodule ExceptionExchange do
        @moduledoc false
        def fetch_orders(_credentials, _symbol, _opts) do
          raise "Boom!"
        end
      end

      result =
        Recovery.find_recent_orders(ExceptionExchange, mock_credentials(), symbol: "BTC/USDT")

      assert {:error, {:exception, "Boom!"}} = result
    end
  end
end
