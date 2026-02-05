defmodule CCXT.WS.Patterns.MethodTopicsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Patterns.MethodTopics

  # Pure unit tests - no I/O, fast execution
  @moduletag :ws_pattern
  @moduletag :fast

  describe "subscribe/2" do
    test "builds subscribe message with topics field" do
      config = %{op_field: "method", args_field: "topics"}
      message = MethodTopics.subscribe(["spot/ticker:BTC_USDT"], config)

      assert message["method"] == "subscribe"
      assert message["topics"] == ["spot/ticker:BTC_USDT"]
    end

    test "builds subscribe message with multiple topics" do
      config = %{op_field: "method", args_field: "topics"}

      message =
        MethodTopics.subscribe(["spot/ticker:BTC_USDT", "spot/depth:ETH_USDT"], config)

      assert message["method"] == "subscribe"
      assert message["topics"] == ["spot/ticker:BTC_USDT", "spot/depth:ETH_USDT"]
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "channels"}
      message = MethodTopics.subscribe(["channel1"], config)

      assert message["action"] == "subscribe"
      assert message["channels"] == ["channel1"]
    end

    test "uses default field names when config is empty" do
      config = %{}
      message = MethodTopics.subscribe(["topic1"], config)

      assert message["method"] == "subscribe"
      assert message["topics"] == ["topic1"]
    end
  end

  describe "unsubscribe/2" do
    test "builds unsubscribe message with topics field" do
      config = %{op_field: "method", args_field: "topics"}
      message = MethodTopics.unsubscribe(["spot/ticker:BTC_USDT"], config)

      assert message["method"] == "unsubscribe"
      assert message["topics"] == ["spot/ticker:BTC_USDT"]
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "channels"}
      message = MethodTopics.unsubscribe(["channel1"], config)

      assert message["action"] == "unsubscribe"
      assert message["channels"] == ["channel1"]
    end
  end

  describe "format_channel/3" do
    test "formats channel with : separator (Exmo style)" do
      template = %{channel_name: "spot/ticker", separator: ":"}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = MethodTopics.format_channel(template, params, config)

      assert channel == "spot/ticker:BTCUSDT"
    end

    test "returns channel name only when no symbol" do
      template = %{channel_name: "spot/balance", separator: ":"}
      params = %{}
      config = %{}

      channel = MethodTopics.format_channel(template, params, config)

      assert channel == "spot/balance"
    end

    test "uses native market ID format by default" do
      template = %{channel_name: "spot/depth"}
      params = %{symbol: "ETH/BTC"}
      config = %{}

      channel = MethodTopics.format_channel(template, params, config)

      assert channel == "spot/depth:ETHBTC"
    end

    test "uses config separator as fallback" do
      template = %{channel_name: "trades"}
      params = %{symbol: "BTC/USDT"}
      config = %{separator: "_"}

      channel = MethodTopics.format_channel(template, params, config)

      assert channel == "trades_BTCUSDT"
    end

    test "uses template market_id_format" do
      template = %{channel_name: "spot/ticker", market_id_format: :lowercase}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = MethodTopics.format_channel(template, params, config)

      assert channel == "spot/ticker:btcusdt"
    end
  end
end
