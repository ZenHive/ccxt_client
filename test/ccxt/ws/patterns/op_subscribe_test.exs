defmodule CCXT.WS.Patterns.OpSubscribeTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Patterns.OpSubscribe

  describe "subscribe/2" do
    test "builds basic subscribe message" do
      config = %{op_field: "op", args_field: "args"}
      message = OpSubscribe.subscribe(["ticker.BTCUSDT"], config)

      assert message["op"] == "subscribe"
      assert message["args"] == ["ticker.BTCUSDT"]
    end

    test "builds subscribe message with multiple channels" do
      config = %{op_field: "op", args_field: "args"}
      message = OpSubscribe.subscribe(["ticker.BTCUSDT", "ticker.ETHUSDT"], config)

      assert message["op"] == "subscribe"
      assert message["args"] == ["ticker.BTCUSDT", "ticker.ETHUSDT"]
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "channels"}
      message = OpSubscribe.subscribe(["channel1"], config)

      assert message["action"] == "subscribe"
      assert message["channels"] == ["channel1"]
    end
  end

  describe "unsubscribe/2" do
    test "builds unsubscribe message" do
      config = %{op_field: "op", args_field: "args"}
      message = OpSubscribe.unsubscribe(["ticker.BTCUSDT"], config)

      assert message["op"] == "unsubscribe"
      assert message["args"] == ["ticker.BTCUSDT"]
    end
  end

  describe "format_channel/3" do
    test "formats channel with separator" do
      template = %{channel_name: "ticker", separator: "."}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = OpSubscribe.format_channel(template, params, config)
      assert channel == "ticker.BTCUSDT"
    end

    test "formats channel without symbol" do
      template = %{channel_name: "balance", separator: "."}
      params = %{}
      config = %{}

      channel = OpSubscribe.format_channel(template, params, config)
      assert channel == "balance"
    end

    test "formats channel with timeframe" do
      template = %{channel_name: "kline", separator: "."}
      params = %{symbol: "BTC/USDT", timeframe: "1h"}
      config = %{}

      channel = OpSubscribe.format_channel(template, params, config)
      assert channel == "kline.1h.BTCUSDT"
    end

    test "formats channel with limit" do
      template = %{channel_name: "orderbook", separator: "."}
      params = %{symbol: "BTC/USDT", limit: 25}
      config = %{}

      channel = OpSubscribe.format_channel(template, params, config)
      assert channel == "orderbook.25.BTCUSDT"
    end

    test "skips nil limit" do
      template = %{channel_name: "orderbook", separator: "."}
      params = %{symbol: "BTC/USDT", limit: nil}
      config = %{}

      channel = OpSubscribe.format_channel(template, params, config)
      assert channel == "orderbook.BTCUSDT"
    end
  end
end
