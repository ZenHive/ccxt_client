defmodule CCXT.WS.Patterns.MethodAsTopicTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Patterns.MethodAsTopic
  # Pure unit tests - no I/O, fast execution
  @moduletag :ws_pattern
  @moduletag :fast

  describe "subscribe/2" do
    test "uses channel as the method name" do
      config = %{op_field: "method", args_field: "params"}
      message = MethodAsTopic.subscribe(["ticker.subscribe"], config)

      assert message["method"] == "ticker.subscribe"
      assert message["params"] == []
      assert is_integer(message["id"])
    end

    test "uses first channel as method when multiple provided" do
      config = %{op_field: "method", args_field: "params"}
      message = MethodAsTopic.subscribe(["depth.subscribe", "ticker.subscribe"], config)

      assert message["method"] == "depth.subscribe"
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "args"}
      message = MethodAsTopic.subscribe(["ticker.subscribe"], config)

      assert message["action"] == "ticker.subscribe"
      assert message["args"] == []
    end

    test "uses default field names when config is empty" do
      config = %{}
      message = MethodAsTopic.subscribe(["ticker.subscribe"], config)

      assert message["method"] == "ticker.subscribe"
      assert message["params"] == []
    end

    test "generates unique IDs for each call" do
      config = %{}
      message1 = MethodAsTopic.subscribe(["ticker.subscribe"], config)
      message2 = MethodAsTopic.subscribe(["depth.subscribe"], config)

      assert message1["id"] != message2["id"]
    end

    test "handles empty channel list" do
      config = %{}
      message = MethodAsTopic.subscribe([], config)

      assert message["method"] == "subscribe"
    end
  end

  describe "unsubscribe/2" do
    test "converts subscribe to unsubscribe in method name" do
      config = %{op_field: "method", args_field: "params"}
      message = MethodAsTopic.unsubscribe(["ticker.subscribe"], config)

      assert message["method"] == "ticker.unsubscribe"
      assert message["params"] == []
      assert is_integer(message["id"])
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "args"}
      message = MethodAsTopic.unsubscribe(["depth.subscribe"], config)

      assert message["action"] == "depth.unsubscribe"
      assert message["args"] == []
    end

    test "handles method without .subscribe suffix" do
      config = %{}
      message = MethodAsTopic.unsubscribe(["ticker"], config)

      # When no .subscribe suffix, replacement doesn't match but still works
      assert message["method"] == "ticker"
    end
  end

  describe "format_channel/3" do
    test "formats channel with .subscribe suffix" do
      template = %{channel_name: "ticker", separator: "."}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = MethodAsTopic.format_channel(template, params, config)

      assert channel == "ticker.subscribe.BTCUSDT"
    end

    test "returns channel with .subscribe when no symbol" do
      template = %{channel_name: "state", separator: "."}
      params = %{}
      config = %{}

      channel = MethodAsTopic.format_channel(template, params, config)

      assert channel == "state.subscribe"
    end

    test "uses native market ID format by default" do
      template = %{channel_name: "depth"}
      params = %{symbol: "ETH/BTC"}
      config = %{}

      channel = MethodAsTopic.format_channel(template, params, config)

      assert channel == "depth.subscribe.ETHBTC"
    end

    test "uses config separator as fallback" do
      template = %{channel_name: "ticker"}
      params = %{symbol: "BTC/USDT"}
      config = %{separator: "_"}

      channel = MethodAsTopic.format_channel(template, params, config)

      assert channel == "ticker.subscribe_BTCUSDT"
    end

    test "uses template market_id_format" do
      template = %{channel_name: "trades", market_id_format: :uppercase}
      params = %{symbol: "btc/usdt"}
      config = %{}

      channel = MethodAsTopic.format_channel(template, params, config)

      assert channel == "trades.subscribe.BTCUSDT"
    end
  end
end
