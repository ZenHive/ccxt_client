defmodule CCXT.WS.ClientTest do
  use ExUnit.Case, async: true

  alias CCXT.WS.Client

  @test_url "wss://example.com"

  # Mock spec for testing
  @mock_spec %{
    ws: %{
      urls: %{
        "public" => %{
          "spot" => "wss://stream.example.com/public/spot"
        },
        "private" => "wss://stream.example.com/private"
      },
      streaming: %{
        keep_alive: 18_000
      },
      subscription_pattern: :op_subscribe,
      subscription_config: %{
        op_field: "op",
        args_field: "args"
      }
    }
  }

  defp disconnected_client(spec \\ @mock_spec) do
    zen_client = %ZenWebsocket.Client{state: :disconnected}

    %Client{
      zen_client: zen_client,
      spec: spec,
      url: @test_url,
      url_path: [:public],
      subscriptions: []
    }
  end

  describe "struct" do
    test "has expected fields" do
      client = %Client{
        zen_client: nil,
        spec: @mock_spec,
        url: @test_url,
        url_path: [:public, :spot],
        subscriptions: []
      }

      assert client.spec == @mock_spec
      assert client.url == "wss://example.com"
      assert client.url_path == [:public, :spot]
      assert client.subscriptions == []
    end
  end

  describe "get_url/1" do
    test "returns the URL" do
      client = %Client{
        zen_client: nil,
        spec: @mock_spec,
        url: "wss://stream.example.com/public/spot",
        url_path: [:public, :spot]
      }

      assert Client.get_url(client) == "wss://stream.example.com/public/spot"
    end
  end

  describe "get_subscriptions/1" do
    test "returns empty list for new client" do
      client = %Client{
        zen_client: nil,
        spec: @mock_spec,
        url: @test_url,
        url_path: [:public],
        subscriptions: []
      }

      assert Client.get_subscriptions(client) == []
    end

    test "returns subscriptions list" do
      subs = [
        %{channel: "tickers.BTCUSDT", message: %{}, method: :watch_ticker, auth_required: false}
      ]

      client = %Client{
        zen_client: nil,
        spec: @mock_spec,
        url: @test_url,
        url_path: [:public],
        subscriptions: subs
      }

      assert Client.get_subscriptions(client) == subs
    end
  end

  describe "get_zen_client/1" do
    test "returns the underlying zen client" do
      # Create a mock zen client struct
      zen_client = %ZenWebsocket.Client{
        gun_pid: nil,
        stream_ref: nil,
        state: :disconnected,
        url: "wss://example.com",
        monitor_ref: nil,
        server_pid: nil
      }

      client = %Client{
        zen_client: zen_client,
        spec: @mock_spec,
        url: @test_url,
        url_path: [:public]
      }

      assert Client.get_zen_client(client) == zen_client
    end
  end

  describe "connect/3 error paths" do
    test "returns error when spec has no ws config" do
      spec = %{ws: nil}

      assert {:error, {:no_ws_config, :public}} = Client.connect(spec, :public)
    end

    test "returns error when url path not found" do
      spec = %{ws: %{urls: %{"public" => %{"spot" => "wss://stream.example.com/public/spot"}}}}

      assert {:error, {:url_not_found, ["private"]}} = Client.connect(spec, :private)
    end
  end

  describe "send_message/2" do
    test "encodes map and returns not_connected when disconnected" do
      client = disconnected_client()

      assert {:error, {:not_connected, :disconnected}} =
               Client.send_message(client, %{"op" => "ping"})
    end

    test "sends binary and returns not_connected when disconnected" do
      client = disconnected_client()

      assert {:error, {:not_connected, :disconnected}} =
               Client.send_message(client, "ping")
    end
  end

  describe "subscribe/2" do
    test "returns not_connected when disconnected" do
      client = disconnected_client()
      subscription = %{channel: "tickers.BTCUSDT", message: %{"op" => "subscribe"}}

      assert {:error, {:not_connected, :disconnected}} = Client.subscribe(client, subscription)
    end
  end

  describe "unsubscribe/2" do
    test "returns not_connected when disconnected" do
      client = disconnected_client()
      subscription = %{channel: "tickers.BTCUSDT"}

      assert {:error, {:not_connected, :disconnected}} = Client.unsubscribe(client, subscription)
    end
  end

  describe "close/1" do
    test "returns :ok for disconnected client" do
      client = disconnected_client()

      assert :ok = Client.close(client)
    end
  end

  describe "get_state/1" do
    test "returns state from zen client" do
      zen_client = %ZenWebsocket.Client{state: :connecting}

      client = %Client{
        zen_client: zen_client,
        spec: @mock_spec,
        url: @test_url,
        url_path: [:public]
      }

      assert Client.get_state(client) == :connecting
    end
  end

  describe "restore_subscriptions/2" do
    test "returns :ok when no subscriptions" do
      client = disconnected_client()

      assert :ok = Client.restore_subscriptions(client, [])
    end

    test "propagates error when disconnected" do
      client = disconnected_client()
      subscriptions = [%{channel: "tickers.BTCUSDT"}]

      assert {:error, {:not_connected, :disconnected}} =
               Client.restore_subscriptions(client, subscriptions)
    end

    test "propagates error for mixed string/list channels when disconnected" do
      client = disconnected_client()

      subscriptions = [
        %{channel: "tickers.BTCUSDT"},
        %{channel: ["order", "stopOrder"]},
        %{method: :watch_ticker}
      ]

      assert {:error, {:not_connected, :disconnected}} =
               Client.restore_subscriptions(client, subscriptions)
    end
  end

  # ===================================================================
  # Task 25: Edge-case branch coverage
  # ===================================================================

  describe "unsubscribe/2 - list channel" do
    test "handles list channel format when disconnected" do
      client = disconnected_client()
      subscription = %{channel: ["ch1", "ch2"]}

      assert {:error, {:not_connected, :disconnected}} = Client.unsubscribe(client, subscription)
    end
  end

  describe "restore_subscriptions/2 - no-channel subscriptions" do
    test "returns :ok when subscriptions have no channel key" do
      client = disconnected_client()
      subs = [%{other: "data"}, %{method: :watch_ticker}]

      assert :ok = Client.restore_subscriptions(client, subs)
    end
  end

  describe "get_state/1 - disconnected" do
    test "returns :disconnected for disconnected client" do
      client = disconnected_client()

      assert Client.get_state(client) == :disconnected
    end
  end

  # Integration tests would require a real WebSocket server
  # These are tagged as :integration and skipped by default

  describe "connect/3 integration" do
    @describetag :integration
    @tag :skip
    test "connects to a real WebSocket server" do
      # This test would connect to a real exchange testnet
      # Skipped by default - run with: mix test --include integration
    end
  end
end
