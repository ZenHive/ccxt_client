defmodule CCXT.WS.Patterns.CustomTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Patterns.Custom

  # Pure unit tests - no I/O, fast execution
  @moduletag :ws_pattern
  @moduletag :fast

  describe "subscribe/2" do
    test "builds array_format subscribe message (Upbit style)" do
      config = %{custom_type: "array_format"}
      message = Custom.subscribe(["KRW-BTC", "KRW-ETH"], config)

      assert is_list(message)
      assert length(message) == 2

      assert Enum.at(message, 0) == %{"type" => "ticker", "codes" => ["KRW-BTC"]}
      assert Enum.at(message, 1) == %{"type" => "ticker", "codes" => ["KRW-ETH"]}
    end

    test "builds sendTopicAction subscribe message (Deepcoin style)" do
      config = %{custom_type: "sendTopicAction"}
      message = Custom.subscribe(["topic1", "topic2"], config)

      assert message["sendTopicAction"]["action"] == "subscribe"
      assert message["sendTopicAction"]["topics"] == ["topic1", "topic2"]
    end

    test "builds default fallback subscribe message" do
      config = %{}
      message = Custom.subscribe(["channel1", "channel2"], config)

      assert message["subscribe"] == true
      assert message["channels"] == ["channel1", "channel2"]
    end

    test "handles unknown custom_type with fallback" do
      config = %{custom_type: "unknown_type"}
      message = Custom.subscribe(["channel1"], config)

      assert message["subscribe"] == true
      assert message["channels"] == ["channel1"]
    end
  end

  describe "unsubscribe/2" do
    test "builds array_format unsubscribe message (Upbit style)" do
      config = %{custom_type: "array_format"}
      message = Custom.unsubscribe(["KRW-BTC"], config)

      assert is_list(message)
      assert length(message) == 1

      first = Enum.at(message, 0)
      assert first["type"] == "ticker"
      assert first["codes"] == ["KRW-BTC"]
      assert first["isOnlyRealtime"] == true
    end

    test "builds sendTopicAction unsubscribe message (Deepcoin style)" do
      config = %{custom_type: "sendTopicAction"}
      message = Custom.unsubscribe(["topic1", "topic2"], config)

      assert message["sendTopicAction"]["action"] == "unsubscribe"
      assert message["sendTopicAction"]["topics"] == ["topic1", "topic2"]
    end

    test "builds default fallback unsubscribe message" do
      config = %{}
      message = Custom.unsubscribe(["channel1"], config)

      assert message["unsubscribe"] == true
      assert message["channels"] == ["channel1"]
    end
  end

  describe "format_channel/3" do
    test "formats channel with separator" do
      template = %{channel_name: "ticker", separator: "."}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = Custom.format_channel(template, params, config)

      assert channel == "ticker.BTCUSDT"
    end

    test "returns channel name only when no symbol" do
      template = %{channel_name: "status", separator: "."}
      params = %{}
      config = %{}

      channel = Custom.format_channel(template, params, config)

      assert channel == "status"
    end

    test "uses native market ID format by default" do
      template = %{channel_name: "trades"}
      params = %{symbol: "ETH/BTC"}
      config = %{}

      channel = Custom.format_channel(template, params, config)

      assert channel == "trades.ETHBTC"
    end

    test "uses config separator as fallback" do
      template = %{channel_name: "ticker"}
      params = %{symbol: "BTC/USDT"}
      config = %{separator: "-"}

      channel = Custom.format_channel(template, params, config)

      assert channel == "ticker-BTCUSDT"
    end

    test "uses template market_id_format" do
      template = %{channel_name: "orderbook", market_id_format: :lowercase}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = Custom.format_channel(template, params, config)

      assert channel == "orderbook.btcusdt"
    end
  end
end
