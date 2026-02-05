defmodule CCXT.WS.Patterns.OpSubscribeObjectsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Patterns.OpSubscribeObjects

  # Pure unit tests - no I/O, fast execution
  @moduletag :ws_pattern
  @moduletag :fast

  describe "subscribe/2" do
    test "builds subscribe message with object channels" do
      config = %{op_field: "op", args_field: "args"}
      channels = [%{"channel" => "tickers", "instId" => "BTC-USDT"}]
      message = OpSubscribeObjects.subscribe(channels, config)

      assert message["op"] == "subscribe"
      assert message["args"] == channels
    end

    test "builds subscribe message with multiple object channels" do
      config = %{op_field: "op", args_field: "args"}

      channels = [
        %{"channel" => "tickers", "instId" => "BTC-USDT"},
        %{"channel" => "books", "instId" => "ETH-USDT"}
      ]

      message = OpSubscribeObjects.subscribe(channels, config)

      assert message["op"] == "subscribe"
      assert message["args"] == channels
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "channels"}
      channels = [%{"channel" => "tickers", "instId" => "BTC-USDT"}]
      message = OpSubscribeObjects.subscribe(channels, config)

      assert message["action"] == "subscribe"
      assert message["channels"] == channels
    end

    test "uses default field names when config is empty" do
      config = %{}
      channels = [%{"channel" => "tickers"}]
      message = OpSubscribeObjects.subscribe(channels, config)

      assert message["op"] == "subscribe"
      assert message["args"] == channels
    end
  end

  describe "unsubscribe/2" do
    test "builds unsubscribe message with object channels" do
      config = %{op_field: "op", args_field: "args"}
      channels = [%{"channel" => "tickers", "instId" => "BTC-USDT"}]
      message = OpSubscribeObjects.unsubscribe(channels, config)

      assert message["op"] == "unsubscribe"
      assert message["args"] == channels
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "channels"}
      channels = [%{"channel" => "tickers", "instId" => "BTC-USDT"}]
      message = OpSubscribeObjects.unsubscribe(channels, config)

      assert message["action"] == "unsubscribe"
      assert message["channels"] == channels
    end
  end

  describe "format_channel/3" do
    test "returns map with channel and instId for symbol" do
      template = %{channel_name: "tickers"}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = OpSubscribeObjects.format_channel(template, params, config)

      assert is_map(channel)
      assert channel["channel"] == "tickers"
      assert channel["instId"] == "BTCUSDT"
    end

    test "returns map with channel only when no symbol" do
      template = %{channel_name: "account"}
      params = %{}
      config = %{}

      channel = OpSubscribeObjects.format_channel(template, params, config)

      assert is_map(channel)
      assert channel["channel"] == "account"
      refute Map.has_key?(channel, "instId")
    end

    test "formats market ID without slashes" do
      template = %{channel_name: "trades"}
      params = %{symbol: "ETH/BTC"}
      config = %{}

      channel = OpSubscribeObjects.format_channel(template, params, config)

      assert channel["instId"] == "ETHBTC"
    end

    test "handles empty channel name" do
      template = %{}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = OpSubscribeObjects.format_channel(template, params, config)

      assert channel["channel"] == ""
      assert channel["instId"] == "BTCUSDT"
    end
  end
end
