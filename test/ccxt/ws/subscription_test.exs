defmodule CCXT.WS.SubscriptionTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Subscription

  describe "patterns/0" do
    test "returns list of supported patterns" do
      patterns = Subscription.patterns()
      assert is_list(patterns)
      assert :op_subscribe in patterns
      assert :method_subscribe in patterns
      assert :jsonrpc_subscribe in patterns
      assert :type_subscribe in patterns
      assert :event_subscribe in patterns
      assert :custom in patterns
    end
  end

  describe "pattern_module/1" do
    test "returns module for known patterns" do
      assert Subscription.pattern_module(:op_subscribe) == CCXT.WS.Patterns.OpSubscribe
      assert Subscription.pattern_module(:method_subscribe) == CCXT.WS.Patterns.MethodSubscribe
      assert Subscription.pattern_module(:jsonrpc_subscribe) == CCXT.WS.Patterns.JsonRpc
      assert Subscription.pattern_module(:custom) == CCXT.WS.Patterns.Custom
    end

    test "returns nil for unknown patterns" do
      assert Subscription.pattern_module(:unknown_pattern) == nil
    end
  end

  describe "build_subscribe/2" do
    test "builds op_subscribe message" do
      config = %{
        subscription_pattern: :op_subscribe,
        subscription_config: %{op_field: "op", args_field: "args"}
      }

      message = Subscription.build_subscribe(["tickers.BTCUSDT"], config)
      assert message["op"] == "subscribe"
      assert message["args"] == ["tickers.BTCUSDT"]
    end

    test "builds method_subscribe message" do
      config = %{
        subscription_pattern: :method_subscribe,
        subscription_config: %{method_field: "method", params_field: "params"}
      }

      message = Subscription.build_subscribe(["btcusdt@ticker"], config)
      assert message["method"] == "SUBSCRIBE"
      assert message["params"] == ["btcusdt@ticker"]
    end

    test "builds event_subscribe message" do
      config = %{
        subscription_pattern: :event_subscribe,
        subscription_config: %{op_field: "event", args_field: "payload"}
      }

      message = Subscription.build_subscribe(["tickers.BTCUSDT"], config)
      assert message["event"] == "subscribe"
      assert message["payload"] == ["tickers.BTCUSDT"]
    end

    test "builds jsonrpc_subscribe message" do
      config = %{
        subscription_pattern: :jsonrpc_subscribe,
        subscription_config: %{method: "public/subscribe", channel_field: "channels"}
      }

      message = Subscription.build_subscribe(["ticker.BTC-PERPETUAL"], config)
      assert message["jsonrpc"] == "2.0"
      assert message["method"] == "public/subscribe"
      assert message["params"]["channels"] == ["ticker.BTC-PERPETUAL"]
    end

    test "falls back to custom pattern when pattern unknown" do
      config = %{
        subscription_pattern: :nonexistent,
        subscription_config: %{}
      }

      message = Subscription.build_subscribe(["channel"], config)
      assert message["channels"] == ["channel"]
    end
  end

  describe "build_unsubscribe/2" do
    test "builds op_subscribe unsubscribe message" do
      config = %{
        subscription_pattern: :op_subscribe,
        subscription_config: %{op_field: "op", args_field: "args"}
      }

      message = Subscription.build_unsubscribe(["tickers.BTCUSDT"], config)
      assert message["op"] == "unsubscribe"
      assert message["args"] == ["tickers.BTCUSDT"]
    end
  end

  describe "format_channel/3" do
    test "formats channel with op_subscribe pattern" do
      template = %{channel_name: "tickers", separator: "."}
      params = %{symbol: "BTC/USDT"}
      config = %{subscription_pattern: :op_subscribe, subscription_config: %{}}

      channel = Subscription.format_channel(template, params, config)
      assert channel == "tickers.BTCUSDT"
    end

    test "formats channel with event_subscribe pattern" do
      template = %{channel_name: "ticker", separator: "."}
      params = %{symbol: "ETH/USDT"}
      config = %{subscription_pattern: :event_subscribe, subscription_config: %{}}

      channel = Subscription.format_channel(template, params, config)
      assert channel == "ticker.ETHUSDT"
    end
  end
end
