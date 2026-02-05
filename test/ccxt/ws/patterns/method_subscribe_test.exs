defmodule CCXT.WS.Patterns.MethodSubscribeTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Patterns.MethodSubscribe

  # Pure unit tests - no I/O, fast execution
  @moduletag :ws_pattern
  @moduletag :fast

  describe "subscribe/2" do
    test "builds subscribe message with SUBSCRIBE method" do
      config = %{op_field: "method", args_field: "params"}
      message = MethodSubscribe.subscribe(["btcusdt@ticker"], config)

      assert message["method"] == "SUBSCRIBE"
      assert message["params"] == ["btcusdt@ticker"]
    end

    test "builds subscribe message with multiple channels" do
      config = %{op_field: "method", args_field: "params"}
      message = MethodSubscribe.subscribe(["btcusdt@ticker", "ethusdt@depth"], config)

      assert message["method"] == "SUBSCRIBE"
      assert message["params"] == ["btcusdt@ticker", "ethusdt@depth"]
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "channels"}
      message = MethodSubscribe.subscribe(["channel1"], config)

      assert message["action"] == "SUBSCRIBE"
      assert message["channels"] == ["channel1"]
    end

    test "uses default field names when config is empty" do
      config = %{}
      message = MethodSubscribe.subscribe(["btcusdt@ticker"], config)

      assert message["method"] == "SUBSCRIBE"
      assert message["params"] == ["btcusdt@ticker"]
    end
  end

  describe "unsubscribe/2" do
    test "builds unsubscribe message with UNSUBSCRIBE method" do
      config = %{op_field: "method", args_field: "params"}
      message = MethodSubscribe.unsubscribe(["btcusdt@ticker"], config)

      assert message["method"] == "UNSUBSCRIBE"
      assert message["params"] == ["btcusdt@ticker"]
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "channels"}
      message = MethodSubscribe.unsubscribe(["channel1"], config)

      assert message["action"] == "UNSUBSCRIBE"
      assert message["channels"] == ["channel1"]
    end
  end

  describe "format_channel/3" do
    test "formats channel with symbol first and @ separator (Binance style)" do
      template = %{channel_name: "ticker", separator: "@"}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = MethodSubscribe.format_channel(template, params, config)

      # Symbol comes first, then @, then channel name (default format is :lowercase)
      assert channel == "btcusdt@ticker"
    end

    test "formats channel with lowercase market ID format" do
      template = %{channel_name: "ticker", separator: "@", market_id_format: :lowercase}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = MethodSubscribe.format_channel(template, params, config)

      assert channel == "btcusdt@ticker"
    end

    test "returns channel name only when no symbol" do
      template = %{channel_name: "ticker", separator: "@"}
      params = %{}
      config = %{}

      channel = MethodSubscribe.format_channel(template, params, config)

      assert channel == "ticker"
    end

    test "uses config separator as fallback" do
      template = %{channel_name: "depth"}
      params = %{symbol: "BTC/USDT"}
      config = %{separator: "_"}

      channel = MethodSubscribe.format_channel(template, params, config)

      # Default format is :lowercase for MethodSubscribe
      assert channel == "btcusdt_depth"
    end

    test "uses config market_id_format as fallback" do
      template = %{channel_name: "ticker"}
      params = %{symbol: "BTC/USDT"}
      config = %{market_id_format: :uppercase, separator: "@"}

      channel = MethodSubscribe.format_channel(template, params, config)

      assert channel == "BTCUSDT@ticker"
    end

    test "defaults to @ separator and :lowercase format" do
      template = %{channel_name: "ticker"}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = MethodSubscribe.format_channel(template, params, config)

      # Default separator is @, default format is :lowercase
      assert channel == "btcusdt@ticker"
    end
  end
end
