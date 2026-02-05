defmodule CCXT.WS.Patterns.JsonRpcTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Patterns.JsonRpc

  # Pure unit tests - no I/O, fast execution
  @moduletag :ws_pattern
  @moduletag :fast

  describe "subscribe/2" do
    test "builds JSON-RPC 2.0 subscribe message" do
      config = %{}
      message = JsonRpc.subscribe(["ticker.BTC-PERPETUAL"], config)

      assert message["jsonrpc"] == "2.0"
      assert message["method"] == "public/subscribe"
      assert message["params"] == %{"channels" => ["ticker.BTC-PERPETUAL"]}
      assert is_integer(message["id"])
    end

    test "builds subscribe message with multiple channels" do
      config = %{}

      message =
        JsonRpc.subscribe(["ticker.BTC-PERPETUAL", "book.BTC-PERPETUAL.100ms"], config)

      assert message["jsonrpc"] == "2.0"
      assert message["method"] == "public/subscribe"
      assert message["params"]["channels"] == ["ticker.BTC-PERPETUAL", "book.BTC-PERPETUAL.100ms"]
    end

    test "generates unique IDs for each call" do
      config = %{}
      message1 = JsonRpc.subscribe(["ticker.BTC-PERPETUAL"], config)
      message2 = JsonRpc.subscribe(["ticker.ETH-PERPETUAL"], config)

      assert message1["id"] != message2["id"]
    end

    test "ignores config fields (uses fixed structure)" do
      # JsonRpc has a fixed structure, config is ignored
      config = %{op_field: "custom_op", args_field: "custom_args"}
      message = JsonRpc.subscribe(["ticker.BTC-PERPETUAL"], config)

      assert message["jsonrpc"] == "2.0"
      assert message["method"] == "public/subscribe"
      refute Map.has_key?(message, "custom_op")
      refute Map.has_key?(message, "custom_args")
    end

    test "id is positive monotonic integer" do
      config = %{}
      message = JsonRpc.subscribe(["channel"], config)

      assert is_integer(message["id"])
      assert message["id"] > 0
    end
  end

  describe "unsubscribe/2" do
    test "builds JSON-RPC 2.0 unsubscribe message" do
      config = %{}
      message = JsonRpc.unsubscribe(["ticker.BTC-PERPETUAL"], config)

      assert message["jsonrpc"] == "2.0"
      assert message["method"] == "public/unsubscribe"
      assert message["params"] == %{"channels" => ["ticker.BTC-PERPETUAL"]}
      assert is_integer(message["id"])
    end

    test "builds unsubscribe message with multiple channels" do
      config = %{}
      message = JsonRpc.unsubscribe(["ticker.BTC-PERPETUAL", "book.ETH-PERPETUAL"], config)

      assert message["method"] == "public/unsubscribe"
      assert message["params"]["channels"] == ["ticker.BTC-PERPETUAL", "book.ETH-PERPETUAL"]
    end
  end

  describe "format_channel/3" do
    test "formats channel with . separator (Deribit style)" do
      template = %{channel_name: "ticker", separator: "."}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = JsonRpc.format_channel(template, params, config)

      assert channel == "ticker.BTCUSDT"
    end

    test "returns channel name only when no symbol" do
      template = %{channel_name: "heartbeat", separator: "."}
      params = %{}
      config = %{}

      channel = JsonRpc.format_channel(template, params, config)

      assert channel == "heartbeat"
    end

    test "uses native market ID format by default" do
      template = %{channel_name: "book"}
      params = %{symbol: "ETH/BTC"}
      config = %{}

      channel = JsonRpc.format_channel(template, params, config)

      assert channel == "book.ETHBTC"
    end

    test "uses config separator as fallback" do
      template = %{channel_name: "trades"}
      params = %{symbol: "BTC/USDT"}
      config = %{separator: "_"}

      channel = JsonRpc.format_channel(template, params, config)

      assert channel == "trades_BTCUSDT"
    end

    test "uses template market_id_format" do
      template = %{channel_name: "ticker", market_id_format: :lowercase}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = JsonRpc.format_channel(template, params, config)

      assert channel == "ticker.btcusdt"
    end
  end
end
