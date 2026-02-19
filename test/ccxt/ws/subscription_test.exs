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

  describe "format_channel/3 with symbol_context" do
    # OKX-style: dash separator (BTC/USDT → BTC-USDT)
    @okx_symbol_context %{
      symbol_patterns: %{
        spot: %{
          case: :upper,
          pattern: :dash_upper,
          suffix: nil,
          separator: "-",
          date_format: nil,
          component_order: nil
        }
      },
      symbol_format: nil,
      symbol_formats: nil,
      currency_aliases: %{}
    }

    test "OKX op_subscribe_objects: produces BTC-USDT in instId" do
      template = %{channel_name: "tickers"}
      params = %{symbol: "BTC/USDT"}

      config = %{
        subscription_pattern: :op_subscribe_objects,
        subscription_config: %{},
        symbol_context: @okx_symbol_context
      }

      channel = Subscription.format_channel(template, params, config)
      assert channel == %{"channel" => "tickers", "instId" => "BTC-USDT"}
    end

    test "symbol_context threads through to op_subscribe pattern" do
      template = %{channel_name: "tickers", separator: "."}
      params = %{symbol: "BTC/USDT"}

      config = %{
        subscription_pattern: :op_subscribe,
        subscription_config: %{},
        symbol_context: @okx_symbol_context
      }

      channel = Subscription.format_channel(template, params, config)
      assert channel == "tickers.BTC-USDT"
    end

    test "without symbol_context, falls back to naive formatting" do
      template = %{channel_name: "tickers", separator: "."}
      params = %{symbol: "BTC/USDT"}
      config = %{subscription_pattern: :op_subscribe, subscription_config: %{}}

      channel = Subscription.format_channel(template, params, config)
      assert channel == "tickers.BTCUSDT"
    end

    test "Binance method_subscribe: lowercase with symbol_context" do
      binance_ctx = %{
        symbol_patterns: %{
          spot: %{
            case: :upper,
            pattern: :no_separator_upper,
            suffix: nil,
            separator: "",
            date_format: nil,
            component_order: nil
          }
        },
        symbol_format: nil,
        symbol_formats: nil,
        currency_aliases: %{}
      }

      template = %{channel_name: "ticker", separator: "@", market_id_format: :lowercase}
      params = %{symbol: "BTC/USDT"}

      config = %{
        subscription_pattern: :method_subscribe,
        subscription_config: %{},
        symbol_context: binance_ctx
      }

      channel = Subscription.format_channel(template, params, config)
      assert channel == "btcusdt@ticker"
    end

    test "Coinbase type_subscribe: dash separator with symbol_context" do
      coinbase_ctx = %{
        symbol_patterns: %{
          spot: %{
            case: :upper,
            pattern: :dash_upper,
            suffix: nil,
            separator: "-",
            date_format: nil,
            component_order: nil
          }
        },
        symbol_format: nil,
        symbol_formats: nil,
        currency_aliases: %{}
      }

      template = %{channel_name: "ticker", separator: "-"}
      params = %{symbol: "BTC/USD"}

      config = %{
        subscription_pattern: :type_subscribe,
        subscription_config: %{},
        symbol_context: coinbase_ctx
      }

      channel = Subscription.format_channel(template, params, config)
      assert channel == "ticker-BTC-USD"
    end
  end

  describe "Coinbase dual-field (end-to-end through Subscription)" do
    @coinbase_ws_config %{
      subscription_pattern: :type_subscribe,
      subscription_config: %{
        op_field: "type",
        args_field: "product_ids",
        args_format: :string_list,
        channels_field: "channels",
        channel_name: "matches"
      }
    }

    test "build_subscribe produces dual-field message" do
      message = Subscription.build_subscribe(["BTC-USD"], @coinbase_ws_config)

      assert message["type"] == "subscribe"
      assert message["product_ids"] == ["BTC-USD"]
      assert message["channels"] == ["matches"]
    end

    test "build_unsubscribe produces dual-field message" do
      message = Subscription.build_unsubscribe(["BTC-USD"], @coinbase_ws_config)

      assert message["type"] == "unsubscribe"
      assert message["product_ids"] == ["BTC-USD"]
      assert message["channels"] == ["matches"]
    end

    test "format_channel with channels_field returns only market ID" do
      template = %{channel_name: "matches"}
      params = %{symbol: "BTC/USD"}

      channel = Subscription.format_channel(template, params, @coinbase_ws_config)

      # With channels_field, format_channel returns only the market ID
      assert channel == "BTCUSD"
    end
  end
end
