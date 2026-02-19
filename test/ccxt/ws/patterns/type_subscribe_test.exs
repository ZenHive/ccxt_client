defmodule CCXT.WS.Patterns.TypeSubscribeTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Patterns.TypeSubscribe

  # Pure unit tests - no I/O, fast execution
  @moduletag :ws_pattern
  @moduletag :fast

  describe "subscribe/2" do
    test "builds subscribe message with single topic (default :string format)" do
      config = %{op_field: "type", args_field: "topic"}
      message = TypeSubscribe.subscribe(["/market/ticker:BTC-USDT"], config)

      assert message["type"] == "subscribe"
      assert message["topic"] == "/market/ticker:BTC-USDT"
    end

    test "builds subscribe message with array format" do
      config = %{op_field: "type", args_field: "channels", args_format: :array}
      message = TypeSubscribe.subscribe(["ticker", "orderbook"], config)

      assert message["type"] == "subscribe"
      assert message["channels"] == ["ticker", "orderbook"]
    end

    test "uses custom field names from config" do
      config = %{op_field: "action", args_field: "channel"}
      message = TypeSubscribe.subscribe(["ticker"], config)

      assert message["action"] == "subscribe"
      assert message["channel"] == "ticker"
    end

    test "uses default field names when config is empty" do
      config = %{}
      message = TypeSubscribe.subscribe(["ticker"], config)

      assert message["type"] == "subscribe"
      assert message["topic"] == "ticker"
    end

    test "handles empty channel list with string format" do
      config = %{args_format: :string}
      message = TypeSubscribe.subscribe([], config)

      assert message["type"] == "subscribe"
      assert message["topic"] == ""
    end
  end

  describe "unsubscribe/2" do
    test "builds unsubscribe message with single topic" do
      config = %{op_field: "type", args_field: "topic"}
      message = TypeSubscribe.unsubscribe(["/market/ticker:BTC-USDT"], config)

      assert message["type"] == "unsubscribe"
      assert message["topic"] == "/market/ticker:BTC-USDT"
    end

    test "builds unsubscribe message with array format" do
      config = %{op_field: "type", args_field: "channels", args_format: :array}
      message = TypeSubscribe.unsubscribe(["ticker", "orderbook"], config)

      assert message["type"] == "unsubscribe"
      assert message["channels"] == ["ticker", "orderbook"]
    end
  end

  describe "format_channel/3" do
    test "formats channel with : separator (KuCoin style)" do
      template = %{channel_name: "/market/ticker", separator: ":"}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = TypeSubscribe.format_channel(template, params, config)

      assert channel == "/market/ticker:BTCUSDT"
    end

    test "returns channel name only when no symbol" do
      template = %{channel_name: "/market/snapshot", separator: ":"}
      params = %{}
      config = %{}

      channel = TypeSubscribe.format_channel(template, params, config)

      assert channel == "/market/snapshot"
    end

    test "uses native market ID format by default" do
      template = %{channel_name: "ticker"}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = TypeSubscribe.format_channel(template, params, config)

      assert channel == "ticker:BTCUSDT"
    end

    test "uses config separator as fallback" do
      template = %{channel_name: "ticker"}
      params = %{symbol: "BTC/USDT"}
      config = %{separator: "."}

      channel = TypeSubscribe.format_channel(template, params, config)

      assert channel == "ticker.BTCUSDT"
    end

    test "uses lowercase market ID format when specified" do
      template = %{channel_name: "ticker", separator: ":", market_id_format: :lowercase}
      params = %{symbol: "BTC/USDT"}
      config = %{}

      channel = TypeSubscribe.format_channel(template, params, config)

      assert channel == "ticker:btcusdt"
    end

    test "returns only market ID when channels_field present (Coinbase dual-field)" do
      template = %{channel_name: "matches"}
      params = %{symbol: "BTC/USD"}
      config = %{channels_field: "channels"}

      channel = TypeSubscribe.format_channel(template, params, config)

      # Native format strips "/" → "BTCUSD"; real exchange IDs come via symbol_context
      assert channel == "BTCUSD"
    end

    test "returns channel_name when no symbol with channels_field" do
      template = %{channel_name: "user"}
      params = %{}
      config = %{channels_field: "channels"}

      channel = TypeSubscribe.format_channel(template, params, config)

      assert channel == "user"
    end
  end

  describe "dual-field subscribe (Coinbase style)" do
    @coinbase_config %{
      op_field: "type",
      args_field: "product_ids",
      args_format: :string_list,
      channels_field: "channels",
      channel_name: "matches"
    }

    test "subscribe populates both product_ids and channels" do
      message = TypeSubscribe.subscribe(["BTCUSD"], @coinbase_config)

      assert message["type"] == "subscribe"
      assert message["product_ids"] == ["BTCUSD"]
      assert message["channels"] == ["matches"]
    end

    test "subscribe with multiple product_ids" do
      message = TypeSubscribe.subscribe(["BTCUSD", "ETHUSD"], @coinbase_config)

      assert message["type"] == "subscribe"
      assert message["product_ids"] == ["BTCUSD", "ETHUSD"]
      assert message["channels"] == ["matches"]
    end

    test "unsubscribe populates both product_ids and channels" do
      message = TypeSubscribe.unsubscribe(["BTCUSD"], @coinbase_config)

      assert message["type"] == "unsubscribe"
      assert message["product_ids"] == ["BTCUSD"]
      assert message["channels"] == ["matches"]
    end

    test "subscribe with singular channel field returns string" do
      config = %{@coinbase_config | channels_field: "channel", channel_name: "ticker"}
      message = TypeSubscribe.subscribe(["BTCUSD"], config)

      assert message["type"] == "subscribe"
      assert message["product_ids"] == ["BTCUSD"]
      assert message["channel"] == "ticker"
    end
  end
end
