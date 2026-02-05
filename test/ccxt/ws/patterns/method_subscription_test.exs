defmodule CCXT.WS.Patterns.MethodSubscriptionTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Patterns.MethodSubscription

  # Pure unit tests - no I/O, fast execution
  @moduletag :ws_pattern
  @moduletag :fast

  describe "subscribe/2" do
    test "builds subscribe message with subscription.type structure" do
      config = %{op_field: "method", args_field: "subscription"}
      message = MethodSubscription.subscribe(["allMids"], config)

      assert message["method"] == "subscribe"
      assert message["subscription"] == %{"type" => "allMids"}
    end

    test "uses first channel as the type" do
      config = %{op_field: "method", args_field: "subscription"}
      message = MethodSubscription.subscribe(["trades", "orderbook"], config)

      assert message["subscription"]["type"] == "trades"
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "sub"}
      message = MethodSubscription.subscribe(["ticker"], config)

      assert message["action"] == "subscribe"
      assert message["sub"] == %{"type" => "ticker"}
    end

    test "uses default field names when config is empty" do
      config = %{}
      message = MethodSubscription.subscribe(["allMids"], config)

      assert message["method"] == "subscribe"
      assert message["subscription"] == %{"type" => "allMids"}
    end

    test "handles empty channel list" do
      config = %{}
      message = MethodSubscription.subscribe([], config)

      assert message["method"] == "subscribe"
      assert message["subscription"]["type"] == ""
    end
  end

  describe "unsubscribe/2" do
    test "builds unsubscribe message with subscription.type structure" do
      config = %{op_field: "method", args_field: "subscription"}
      message = MethodSubscription.unsubscribe(["allMids"], config)

      assert message["method"] == "unsubscribe"
      assert message["subscription"] == %{"type" => "allMids"}
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "sub"}
      message = MethodSubscription.unsubscribe(["ticker"], config)

      assert message["action"] == "unsubscribe"
      assert message["sub"] == %{"type" => "ticker"}
    end
  end

  describe "format_channel/3" do
    test "formats channel with separator" do
      template = %{channel_name: "trades", separator: "."}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = MethodSubscription.format_channel(template, params, config)

      assert channel == "trades.BTCUSDT"
    end

    test "returns channel name only when no symbol" do
      template = %{channel_name: "allMids", separator: "."}
      params = %{}
      config = %{}

      channel = MethodSubscription.format_channel(template, params, config)

      assert channel == "allMids"
    end

    test "uses native market ID format by default" do
      template = %{channel_name: "orderUpdates"}
      params = %{symbol: "ETH/BTC"}
      config = %{}

      channel = MethodSubscription.format_channel(template, params, config)

      assert channel == "orderUpdates.ETHBTC"
    end

    test "uses config separator as fallback" do
      template = %{channel_name: "ticker"}
      params = %{symbol: "BTC/USDT"}
      config = %{separator: "_"}

      channel = MethodSubscription.format_channel(template, params, config)

      assert channel == "ticker_BTCUSDT"
    end

    test "uses template market_id_format" do
      template = %{channel_name: "trades", market_id_format: :lowercase}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = MethodSubscription.format_channel(template, params, config)

      assert channel == "trades.btcusdt"
    end
  end
end
