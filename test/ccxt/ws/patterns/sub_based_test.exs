defmodule CCXT.WS.Patterns.SubBasedTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Patterns.SubBased

  # Pure unit tests - no I/O, fast execution
  @moduletag :ws_pattern
  @moduletag :fast

  describe "subscribe/2" do
    test "builds subscribe message with sub field" do
      config = %{}
      message = SubBased.subscribe(["market.btcusdt.ticker"], config)

      assert message["sub"] == "market.btcusdt.ticker"
      assert is_binary(message["id"])
      assert String.starts_with?(message["id"], "id")
    end

    test "uses first channel when multiple provided" do
      config = %{}
      message = SubBased.subscribe(["market.btcusdt.ticker", "market.ethusdt.depth"], config)

      assert message["sub"] == "market.btcusdt.ticker"
    end

    test "generates unique IDs for each call" do
      config = %{}
      message1 = SubBased.subscribe(["channel1"], config)
      message2 = SubBased.subscribe(["channel2"], config)

      assert message1["id"] != message2["id"]
    end

    test "handles empty channel list" do
      config = %{}
      message = SubBased.subscribe([], config)

      assert message["sub"] == ""
      assert is_binary(message["id"])
    end

    test "ignores config (fixed structure)" do
      # SubBased has a fixed structure, config is ignored
      config = %{op_field: "custom_op", args_field: "custom_args"}
      message = SubBased.subscribe(["market.btcusdt.ticker"], config)

      assert message["sub"] == "market.btcusdt.ticker"
      refute Map.has_key?(message, "custom_op")
      refute Map.has_key?(message, "custom_args")
    end
  end

  describe "unsubscribe/2" do
    test "builds unsubscribe message with unsub field" do
      config = %{}
      message = SubBased.unsubscribe(["market.btcusdt.ticker"], config)

      assert message["unsub"] == "market.btcusdt.ticker"
      assert is_binary(message["id"])
    end

    test "uses first channel when multiple provided" do
      config = %{}
      message = SubBased.unsubscribe(["market.btcusdt.ticker", "market.ethusdt.depth"], config)

      assert message["unsub"] == "market.btcusdt.ticker"
    end
  end

  describe "format_channel/3" do
    test "formats channel with market. prefix (HTX style)" do
      template = %{channel_name: "ticker", separator: "."}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = SubBased.format_channel(template, params, config)

      # HTX format: market.{symbol}.{channel}
      assert channel == "market.btcusdt.ticker"
    end

    test "returns channel name only when no symbol" do
      template = %{channel_name: "accounts", separator: "."}
      params = %{}
      config = %{}

      channel = SubBased.format_channel(template, params, config)

      assert channel == "accounts"
    end

    test "uses lowercase market ID format by default" do
      template = %{channel_name: "depth"}
      params = %{symbol: "ETH/BTC"}
      config = %{}

      channel = SubBased.format_channel(template, params, config)

      assert channel == "market.ethbtc.depth"
    end

    test "uses config separator as fallback" do
      template = %{channel_name: "kline"}
      params = %{symbol: "BTC/USDT"}
      config = %{separator: "_"}

      channel = SubBased.format_channel(template, params, config)

      assert channel == "market_btcusdt_kline"
    end

    test "uses template market_id_format" do
      template = %{channel_name: "ticker", market_id_format: :uppercase}
      params = %{symbol: "btc/usdt"}
      config = %{}

      channel = SubBased.format_channel(template, params, config)

      assert channel == "market.BTCUSDT.ticker"
    end
  end
end
