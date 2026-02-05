defmodule CCXT.WS.Patterns.ReqtypeSubTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Patterns.ReqtypeSub

  # Pure unit tests - no I/O, fast execution
  @moduletag :ws_pattern
  @moduletag :fast

  describe "subscribe/2" do
    test "builds subscribe message with reqType and dataType" do
      config = %{op_field: "reqType", args_field: "dataType"}
      message = ReqtypeSub.subscribe(["BTC-USDT@ticker"], config)

      assert message["reqType"] == "sub"
      assert message["dataType"] == "BTC-USDT@ticker"
    end

    test "uses first channel when multiple provided" do
      config = %{op_field: "reqType", args_field: "dataType"}
      message = ReqtypeSub.subscribe(["BTC-USDT@ticker", "ETH-USDT@depth"], config)

      assert message["dataType"] == "BTC-USDT@ticker"
    end

    test "uses custom field names from config" do
      config = %{op_field: "type", args_field: "channel"}
      message = ReqtypeSub.subscribe(["BTC-USDT@ticker"], config)

      assert message["type"] == "sub"
      assert message["channel"] == "BTC-USDT@ticker"
    end

    test "uses default field names when config is empty" do
      config = %{}
      message = ReqtypeSub.subscribe(["BTC-USDT@ticker"], config)

      assert message["reqType"] == "sub"
      assert message["dataType"] == "BTC-USDT@ticker"
    end

    test "handles empty channel list" do
      config = %{}
      message = ReqtypeSub.subscribe([], config)

      assert message["reqType"] == "sub"
      assert message["dataType"] == ""
    end
  end

  describe "unsubscribe/2" do
    test "builds unsubscribe message with unsub reqType" do
      config = %{op_field: "reqType", args_field: "dataType"}
      message = ReqtypeSub.unsubscribe(["BTC-USDT@ticker"], config)

      assert message["reqType"] == "unsub"
      assert message["dataType"] == "BTC-USDT@ticker"
    end

    test "uses custom field names from config" do
      config = %{op_field: "type", args_field: "channel"}
      message = ReqtypeSub.unsubscribe(["BTC-USDT@ticker"], config)

      assert message["type"] == "unsub"
      assert message["channel"] == "BTC-USDT@ticker"
    end
  end

  describe "format_channel/3" do
    test "formats channel with symbol first then @ separator (BingX style)" do
      template = %{channel_name: "ticker", separator: "@"}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = ReqtypeSub.format_channel(template, params, config)

      # BingX format: {symbol}@{channel}
      assert channel == "BTCUSDT@ticker"
    end

    test "returns channel name only when no symbol" do
      template = %{channel_name: "balance", separator: "@"}
      params = %{}
      config = %{}

      channel = ReqtypeSub.format_channel(template, params, config)

      assert channel == "balance"
    end

    test "uses native market ID format by default" do
      template = %{channel_name: "depth"}
      params = %{symbol: "ETH/BTC"}
      config = %{}

      channel = ReqtypeSub.format_channel(template, params, config)

      assert channel == "ETHBTC@depth"
    end

    test "uses config separator as fallback" do
      template = %{channel_name: "trades"}
      params = %{symbol: "BTC/USDT"}
      config = %{separator: "_"}

      channel = ReqtypeSub.format_channel(template, params, config)

      assert channel == "BTCUSDT_trades"
    end

    test "uses template market_id_format" do
      template = %{channel_name: "ticker", market_id_format: :lowercase}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = ReqtypeSub.format_channel(template, params, config)

      assert channel == "btcusdt@ticker"
    end
  end
end
