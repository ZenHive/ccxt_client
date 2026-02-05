defmodule CCXT.WS.Patterns.EventSubscribeTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Patterns.EventSubscribe

  # Pure unit tests - no I/O, fast execution
  @moduletag :ws_pattern
  @moduletag :fast

  describe "subscribe/2" do
    test "builds subscribe message with default array format" do
      config = %{op_field: "event", args_field: "payload"}
      message = EventSubscribe.subscribe(["BTC_USDT"], config)

      assert message["event"] == "subscribe"
      assert message["payload"] == ["BTC_USDT"]
    end

    test "builds subscribe message with object_list format" do
      config = %{op_field: "event", args_field: "channels", args_format: :object_list}

      channels = [
        %{"channel" => "ticker", "symbol" => "tBTCUSD"},
        %{"channel" => "trades", "symbol" => "tETHUSD"}
      ]

      message = EventSubscribe.subscribe(channels, config)

      assert message["event"] == "subscribe"
      assert message["channels"] == channels
    end

    test "builds subscribe message with string format" do
      config = %{op_field: "event", args_field: "channel", args_format: :string}
      message = EventSubscribe.subscribe(["ticker"], config)

      assert message["event"] == "subscribe"
      assert message["channel"] == "ticker"
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "symbols"}
      message = EventSubscribe.subscribe(["BTC_USDT"], config)

      assert message["action"] == "subscribe"
      assert message["symbols"] == ["BTC_USDT"]
    end

    test "uses default field names when config is empty" do
      config = %{}
      message = EventSubscribe.subscribe(["channel1"], config)

      assert message["event"] == "subscribe"
      assert message["payload"] == ["channel1"]
    end
  end

  describe "unsubscribe/2" do
    test "builds unsubscribe message with default array format" do
      config = %{op_field: "event", args_field: "payload"}
      message = EventSubscribe.unsubscribe(["BTC_USDT"], config)

      assert message["event"] == "unsubscribe"
      assert message["payload"] == ["BTC_USDT"]
    end

    test "builds unsubscribe message with object_list format" do
      config = %{args_format: :object_list, args_field: "channels"}
      channels = [%{"channel" => "ticker", "symbol" => "tBTCUSD"}]
      message = EventSubscribe.unsubscribe(channels, config)

      assert message["event"] == "unsubscribe"
      assert message["channels"] == channels
    end

    test "builds unsubscribe message with string format" do
      config = %{args_format: :string, args_field: "channel"}
      message = EventSubscribe.unsubscribe(["ticker"], config)

      assert message["event"] == "unsubscribe"
      assert message["channel"] == "ticker"
    end
  end

  describe "format_channel/3" do
    test "formats channel with . separator (Gate style)" do
      template = %{channel_name: "spot.tickers", separator: "."}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = EventSubscribe.format_channel(template, params, config)

      assert channel == "spot.tickers.BTCUSDT"
    end

    test "returns channel name only when no symbol" do
      template = %{channel_name: "balance", separator: "."}
      params = %{}
      config = %{}

      channel = EventSubscribe.format_channel(template, params, config)

      assert channel == "balance"
    end

    test "formats channel with timeframe" do
      template = %{channel_name: "kline", separator: "."}
      params = %{symbol: "BTC/USDT", timeframe: "1h"}
      config = %{}

      channel = EventSubscribe.format_channel(template, params, config)

      assert channel == "kline.1h.BTCUSDT"
    end

    test "formats channel with limit" do
      template = %{channel_name: "orderbook", separator: "."}
      params = %{symbol: "BTC/USDT", limit: 20}
      config = %{}

      channel = EventSubscribe.format_channel(template, params, config)

      assert channel == "orderbook.20.BTCUSDT"
    end

    test "skips nil timeframe and limit" do
      template = %{channel_name: "ticker", separator: "."}
      params = %{symbol: "BTC/USDT", timeframe: nil, limit: nil}
      config = %{}

      channel = EventSubscribe.format_channel(template, params, config)

      assert channel == "ticker.BTCUSDT"
    end

    test "uses config separator as fallback" do
      template = %{channel_name: "trades"}
      params = %{symbol: "BTC/USDT"}
      config = %{separator: "_"}

      channel = EventSubscribe.format_channel(template, params, config)

      assert channel == "trades_BTCUSDT"
    end

    test "uses template market_id_format" do
      template = %{channel_name: "ticker", market_id_format: :lowercase}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = EventSubscribe.format_channel(template, params, config)

      assert channel == "ticker.btcusdt"
    end
  end
end
