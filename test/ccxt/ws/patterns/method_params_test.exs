defmodule CCXT.WS.Patterns.MethodParamsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Patterns.MethodParams

  # Pure unit tests - no I/O, fast execution
  @moduletag :ws_pattern
  @moduletag :fast

  describe "subscribe/2" do
    test "builds subscribe message with nested params.channel" do
      config = %{op_field: "method", args_field: "params"}
      message = MethodParams.subscribe(["ticker"], config)

      assert message["method"] == "subscribe"
      assert message["params"] == %{"channel" => ["ticker"]}
    end

    test "builds subscribe message with multiple channels" do
      config = %{op_field: "method", args_field: "params"}
      message = MethodParams.subscribe(["ticker", "book", "trade"], config)

      assert message["method"] == "subscribe"
      assert message["params"]["channel"] == ["ticker", "book", "trade"]
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "data"}
      message = MethodParams.subscribe(["channel1"], config)

      assert message["action"] == "subscribe"
      assert message["data"] == %{"channel" => ["channel1"]}
    end

    test "uses default field names when config is empty" do
      config = %{}
      message = MethodParams.subscribe(["ticker"], config)

      assert message["method"] == "subscribe"
      assert message["params"] == %{"channel" => ["ticker"]}
    end
  end

  describe "unsubscribe/2" do
    test "builds unsubscribe message with nested params.channel" do
      config = %{op_field: "method", args_field: "params"}
      message = MethodParams.unsubscribe(["ticker"], config)

      assert message["method"] == "unsubscribe"
      assert message["params"] == %{"channel" => ["ticker"]}
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "data"}
      message = MethodParams.unsubscribe(["channel1"], config)

      assert message["action"] == "unsubscribe"
      assert message["data"] == %{"channel" => ["channel1"]}
    end
  end

  describe "format_channel/3" do
    test "formats channel with separator" do
      template = %{channel_name: "ticker", separator: "."}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = MethodParams.format_channel(template, params, config)

      assert channel == "ticker.BTCUSDT"
    end

    test "returns channel name only when no symbol" do
      template = %{channel_name: "heartbeat", separator: "."}
      params = %{}
      config = %{}

      channel = MethodParams.format_channel(template, params, config)

      assert channel == "heartbeat"
    end

    test "uses native market ID format by default" do
      template = %{channel_name: "book"}
      params = %{symbol: "ETH/BTC"}
      config = %{}

      channel = MethodParams.format_channel(template, params, config)

      assert channel == "book.ETHBTC"
    end

    test "uses config separator as fallback" do
      template = %{channel_name: "trades"}
      params = %{symbol: "BTC/USDT"}
      config = %{separator: "/"}

      channel = MethodParams.format_channel(template, params, config)

      assert channel == "trades/BTCUSDT"
    end

    test "uses template market_id_format" do
      template = %{channel_name: "ticker", market_id_format: :uppercase}
      params = %{symbol: "btc/usdt"}
      config = %{}

      channel = MethodParams.format_channel(template, params, config)

      assert channel == "ticker.BTCUSDT"
    end
  end
end
