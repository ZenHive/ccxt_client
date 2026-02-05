defmodule CCXT.WS.Patterns.ActionSubscribeTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Patterns.ActionSubscribe

  # Pure unit tests - no I/O, fast execution
  @moduletag :ws_pattern
  @moduletag :fast

  describe "subscribe/2" do
    test "builds subscribe message with nested params.channels" do
      config = %{op_field: "action", args_field: "params"}
      message = ActionSubscribe.subscribe(["ticker"], config)

      assert message["action"] == "subscribe"
      assert message["params"] == %{"channels" => ["ticker"]}
    end

    test "builds subscribe message with multiple channels" do
      config = %{op_field: "action", args_field: "params"}
      message = ActionSubscribe.subscribe(["ticker", "trades", "orderbook"], config)

      assert message["action"] == "subscribe"
      assert message["params"]["channels"] == ["ticker", "trades", "orderbook"]
    end

    test "uses custom field names from config" do
      config = %{op_field: "method", args_field: "data"}
      message = ActionSubscribe.subscribe(["channel1"], config)

      assert message["method"] == "subscribe"
      assert message["data"] == %{"channels" => ["channel1"]}
    end

    test "uses default field names when config is empty" do
      config = %{}
      message = ActionSubscribe.subscribe(["ticker"], config)

      assert message["action"] == "subscribe"
      assert message["params"] == %{"channels" => ["ticker"]}
    end
  end

  describe "unsubscribe/2" do
    test "builds unsubscribe message with nested params.channels" do
      config = %{op_field: "action", args_field: "params"}
      message = ActionSubscribe.unsubscribe(["ticker"], config)

      assert message["action"] == "unsubscribe"
      assert message["params"] == %{"channels" => ["ticker"]}
    end

    test "uses custom field names from config" do
      config = %{op_field: "method", args_field: "data"}
      message = ActionSubscribe.unsubscribe(["channel1"], config)

      assert message["method"] == "unsubscribe"
      assert message["data"] == %{"channels" => ["channel1"]}
    end
  end

  describe "format_channel/3" do
    test "formats channel with separator" do
      template = %{channel_name: "ticker", separator: "."}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = ActionSubscribe.format_channel(template, params, config)

      assert channel == "ticker.BTCUSDT"
    end

    test "returns channel name only when no symbol" do
      template = %{channel_name: "account", separator: "."}
      params = %{}
      config = %{}

      channel = ActionSubscribe.format_channel(template, params, config)

      assert channel == "account"
    end

    test "uses native market ID format by default" do
      template = %{channel_name: "trades"}
      params = %{symbol: "ETH/BTC"}
      config = %{}

      channel = ActionSubscribe.format_channel(template, params, config)

      assert channel == "trades.ETHBTC"
    end

    test "uses config separator as fallback" do
      template = %{channel_name: "ticker"}
      params = %{symbol: "BTC/USDT"}
      config = %{separator: "_"}

      channel = ActionSubscribe.format_channel(template, params, config)

      assert channel == "ticker_BTCUSDT"
    end

    test "uses template market_id_format" do
      template = %{channel_name: "ticker", market_id_format: :lowercase}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = ActionSubscribe.format_channel(template, params, config)

      assert channel == "ticker.btcusdt"
    end
  end
end
