defmodule CCXT.WS.Generator.FunctionsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias CCXT.WS.Generator.Functions

  @orderbook_limit 25
  @topic_list ["positions", "positions.reduced"]
  @spot_url "wss://stream.example.com/spot"
  @private_url "wss://stream.example.com/private"
  @unknown_url "wss://stream.example.com/unknown"
  @symbol "BTC/USDT"
  @symbols ["BTC/USDT", "ETH/USDT"]
  @timeframe "1h"

  @ws_config %{
    subscription_pattern: :op_subscribe,
    subscription_config: %{
      op_field: "op",
      args_field: "args",
      separator: "."
    },
    channel_templates: %{
      watch_ticker: %{channel_name: "tickers"},
      watch_tickers: %{channel_name: "tickers"},
      watch_order_book: %{channel_name: "orderbook"},
      watch_ohlcv: %{channel_name: "ohlcv"},
      watch_balance: %{
        url_routed: true,
        url_patterns: [
          %{pattern: "spot", account_type: "spot"},
          %{pattern: "private", account_type: "unified"}
        ],
        topic_dict: %{"spot" => "wallet", "unified" => "wallet.unified"}
      },
      watch_orders: %{
        url_routed: true,
        url_patterns: [
          %{pattern: "private", account_type: "unified"}
        ],
        topic_dict: %{"unified" => "orders"}
      },
      watch_positions: %{
        url_routed: true,
        url_patterns: [
          %{pattern: "private", account_type: "unified"}
        ],
        topic_dict: %{"unified" => @topic_list}
      }
    }
  }

  @spec add_custom_method(map()) :: map()
  defp add_custom_method(ws_config) do
    Map.update!(ws_config, :channel_templates, fn templates ->
      Map.put(templates, :watch_custom, %{channel_name: "custom"})
    end)
  end

  @spec build_module(map()) :: module()
  defp build_module(ws_config) do
    spec = %{name: "TestExchange", ws: ws_config}
    moduledoc = Functions.generate_moduledoc(spec)
    introspection = Functions.generate_introspection(ws_config)
    watch_functions = Functions.generate_watch_functions(ws_config)
    unique = :erlang.unique_integer([:positive])
    module_name = Module.concat(__MODULE__, "Generated#{unique}")

    {:module, module, _bytecode, _exports} =
      Module.create(
        module_name,
        quote do
          @moduledoc unquote(moduledoc)
          @ws_spec unquote(Macro.escape(ws_config))

          unquote(introspection)
          unquote(watch_functions)
        end,
        Macro.Env.location(__ENV__)
      )

    module
  end

  describe "generate_moduledoc/1" do
    test "includes exchange name and subscription pattern" do
      spec = %{name: "TestExchange", ws: @ws_config}
      doc = Functions.generate_moduledoc(spec)

      assert doc =~ "TestExchange"
      assert doc =~ ":op_subscribe"
    end
  end

  describe "generate_introspection/1" do
    test "emits ws spec, pattern, and channels functions" do
      mod = build_module(@ws_config)

      assert mod.__ccxt_ws_spec__() == @ws_config
      assert mod.__ccxt_ws_pattern__() == :op_subscribe
      assert is_map(mod.__ccxt_ws_channels__())
      assert Map.has_key?(mod.__ccxt_ws_channels__(), :watch_ticker)
    end
  end

  describe "generate_watch_functions/1" do
    test "builds standard subscription functions" do
      mod = build_module(@ws_config)

      assert {:ok, ticker} = mod.watch_ticker_subscription(@symbol)
      assert ticker.channel == "tickers.BTCUSDT"
      assert ticker.method == :watch_ticker
      assert ticker.auth_required == false

      assert {:ok, tickers} = mod.watch_tickers_subscription(@symbols)
      assert tickers.channel == ["tickers.BTCUSDT", "tickers.ETHUSDT"]
      assert tickers.method == :watch_tickers

      assert {:ok, orderbook} = mod.watch_order_book_subscription(@symbol, @orderbook_limit)
      assert orderbook.channel == "orderbook.#{@orderbook_limit}.BTCUSDT"
      assert orderbook.method == :watch_order_book

      assert {:ok, ohlcv} = mod.watch_ohlcv_subscription(@symbol, @timeframe)
      assert ohlcv.channel == "ohlcv.#{@timeframe}.BTCUSDT"
      assert ohlcv.method == :watch_ohlcv
    end

    test "defaults unknown watch methods to single-symbol params with warning" do
      log =
        capture_log(fn ->
          mod = build_module(add_custom_method(@ws_config))
          assert {:ok, result} = mod.watch_custom_subscription(@symbol)
          assert result.method == :watch_custom
        end)

      assert log =~ "Unknown watch method"
    end
  end

  describe "url-routed subscriptions" do
    test "builds no-param URL-routed subscription from url" do
      mod = build_module(@ws_config)

      assert {:ok, sub} = mod.watch_balance_subscription(@spot_url)
      assert sub.channel == "wallet"
      assert sub.method == :watch_balance
      assert sub.auth_required == true
    end

    test "returns error for URL without matching pattern" do
      mod = build_module(@ws_config)

      assert {:error, :no_matching_url_pattern} =
               mod.watch_balance_subscription(@unknown_url)
    end

    test "builds URL-routed symbol subscription" do
      mod = build_module(@ws_config)

      assert {:ok, sub} = mod.watch_orders_subscription(@private_url, @symbol)
      assert sub.channel == "orders"
      assert sub.symbol == @symbol
      assert sub.method == :watch_orders
      assert sub.auth_required == true
    end

    test "builds URL-routed symbols subscription with list channel" do
      mod = build_module(@ws_config)

      assert {:ok, sub} = mod.watch_positions_subscription(@private_url, @symbols)
      assert sub.channel == @topic_list
      assert sub.symbols == @symbols
      assert sub.method == :watch_positions
      assert sub.auth_required == true
    end
  end
end
