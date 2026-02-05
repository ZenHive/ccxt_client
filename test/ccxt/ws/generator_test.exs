defmodule CCXT.WS.GeneratorTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Subscription

  # Dynamically find an available WS module instead of hardcoding
  setup_all do
    ws_module = find_available_ws_module()

    if ws_module do
      {:ok, ws_module: ws_module}
    else
      # No WS modules available - skip all tests
      IO.puts("\n⚠️  No WS modules available, skipping WS generator tests")
      :ok
    end
  end

  @doc false
  # Finds any available exchange with WS module from tier1/tier2 candidates
  defp find_available_ws_module do
    # Build candidate list dynamically from what's available
    candidates =
      [
        # tier1
        CCXT.Bybit.WS,
        CCXT.OKX.WS,
        CCXT.Binance.WS,
        # tier2
        CCXT.Kraken.WS,
        CCXT.Gate.WS,
        CCXT.Bitmex.WS,
        CCXT.HTX.WS,
        CCXT.Kucoin.WS
      ]

    Enum.find(candidates, fn mod ->
      Code.ensure_loaded?(mod) and function_exported?(mod, :__ccxt_ws_spec__, 0)
    end)
  end

  describe "generated module introspection" do
    @describetag :requires_spec

    @tag :requires_ws_module
    test "generates __ccxt_ws_spec__/0", context do
      ws_module = context[:ws_module]
      if is_nil(ws_module), do: skip_no_ws_module()

      spec = ws_module.__ccxt_ws_spec__()
      assert is_map(spec)
      assert Map.has_key?(spec, :subscription_pattern)
    end

    @tag :requires_ws_module
    test "generates __ccxt_ws_pattern__/0", context do
      ws_module = context[:ws_module]
      if is_nil(ws_module), do: skip_no_ws_module()

      pattern = ws_module.__ccxt_ws_pattern__()
      assert is_atom(pattern)
      assert pattern in Subscription.patterns()
    end

    @tag :requires_ws_module
    test "generates __ccxt_ws_channels__/0", context do
      ws_module = context[:ws_module]
      if is_nil(ws_module), do: skip_no_ws_module()

      channels = ws_module.__ccxt_ws_channels__()
      assert is_map(channels)
      assert Map.has_key?(channels, :watch_ticker)
    end
  end

  describe "generated subscription functions" do
    @describetag :requires_spec

    @tag :requires_ws_module
    test "watch_ticker_subscription/2 builds ticker subscription", context do
      ws_module = context[:ws_module]
      if is_nil(ws_module), do: skip_no_ws_module()

      {:ok, result} = ws_module.watch_ticker_subscription("BTC/USDT")

      assert is_binary(result.channel)
      assert is_map(result.message)
      assert result.method == :watch_ticker
      assert result.auth_required == false
    end

    @tag :requires_ws_module
    test "watch_order_book_subscription/3 builds orderbook subscription", context do
      ws_module = context[:ws_module]
      if is_nil(ws_module), do: skip_no_ws_module()

      {:ok, result} = ws_module.watch_order_book_subscription("ETH/USDT", 25)

      assert is_binary(result.channel)
      assert is_map(result.message)
      assert result.method == :watch_order_book
    end

    @tag :requires_ws_module
    test "watch_trades_subscription/2 builds trades subscription", context do
      ws_module = context[:ws_module]
      if is_nil(ws_module), do: skip_no_ws_module()

      {:ok, result} = ws_module.watch_trades_subscription("BTC/USDT")

      assert is_binary(result.channel)
      assert result.method == :watch_trades
    end

    @tag :requires_ws_module
    test "watch_ohlcv_subscription/3 builds ohlcv subscription with timeframe", context do
      ws_module = context[:ws_module]
      if is_nil(ws_module), do: skip_no_ws_module()

      {:ok, result} = ws_module.watch_ohlcv_subscription("BTC/USDT", "1h")

      assert is_binary(result.channel)
      assert result.method == :watch_ohlcv
    end

    @tag :requires_ws_module
    test "watch_balance_subscription requires auth", context do
      ws_module = context[:ws_module]
      if is_nil(ws_module), do: skip_no_ws_module()

      # Different exchanges have different private subscription patterns
      # Some are URL-routed (Bybit), some are message-routed
      result =
        cond do
          function_exported?(ws_module, :watch_balance_subscription, 1) ->
            # URL-routed pattern (needs URL to determine endpoint)
            ws_module.watch_balance_subscription("wss://example.com/private")

          function_exported?(ws_module, :watch_balance_subscription, 0) ->
            ws_module.watch_balance_subscription()

          true ->
            {:error, :not_supported}
        end

      case result do
        {:ok, sub} ->
          assert sub.method == :watch_balance
          assert sub.auth_required == true

        {:error, :not_supported} ->
          # Exchange doesn't implement this subscription method
          :ok

        {:error, {:no_topic_for_account_type, _account_type}} ->
          # URL routing doesn't have a topic for this account type (exchange limitation)
          :ok

        {:error, other} ->
          flunk("Unexpected error from watch_balance_subscription: #{inspect(other)}")
      end
    end

    @tag :requires_ws_module
    test "watch_orders_subscription requires auth", context do
      ws_module = context[:ws_module]
      if is_nil(ws_module), do: skip_no_ws_module()

      # Different exchanges have different private subscription patterns
      result =
        cond do
          function_exported?(ws_module, :watch_orders_subscription, 2) ->
            # URL-routed pattern (needs URL to determine endpoint)
            ws_module.watch_orders_subscription("wss://example.com/private", "BTC/USDT")

          function_exported?(ws_module, :watch_orders_subscription, 1) ->
            ws_module.watch_orders_subscription("BTC/USDT")

          true ->
            {:error, :not_supported}
        end

      case result do
        {:ok, sub} ->
          assert sub.method == :watch_orders
          assert sub.auth_required == true

        {:error, :not_supported} ->
          # Exchange doesn't implement this subscription method
          :ok

        {:error, {:no_topic_for_account_type, _account_type}} ->
          # URL routing doesn't have a topic for this account type (exchange limitation)
          :ok

        {:error, other} ->
          flunk("Unexpected error from watch_orders_subscription: #{inspect(other)}")
      end
    end

    @tag :requires_ws_module
    test "watch_tickers_subscription/2 handles multiple symbols", context do
      ws_module = context[:ws_module]
      if is_nil(ws_module), do: skip_no_ws_module()

      {:ok, result} = ws_module.watch_tickers_subscription(["BTC/USDT", "ETH/USDT"])

      assert is_list(result.channel)
      assert length(result.channel) == 2
      assert result.method == :watch_tickers
    end
  end

  describe "channel formatting" do
    @describetag :requires_spec

    @tag :requires_ws_module
    test "converts unified symbol to exchange format", context do
      ws_module = context[:ws_module]
      if is_nil(ws_module), do: skip_no_ws_module()

      {:ok, result} = ws_module.watch_ticker_subscription("BTC/USDT")

      # All exchanges should convert unified symbol to their format
      # Most use "BTCUSDT" but some may vary (BTC-USDT, BTC_USDT, etc.)
      # Just verify the channel contains some form of the symbol
      channel_str = if is_binary(result.channel), do: result.channel, else: inspect(result.channel)
      assert channel_str =~ "BTC" or channel_str =~ "btc"
    end

    @tag :requires_ws_module
    test "handles spot and futures symbols", context do
      ws_module = context[:ws_module]
      if is_nil(ws_module), do: skip_no_ws_module()

      {:ok, spot} = ws_module.watch_ticker_subscription("BTC/USDT")
      {:ok, perp} = ws_module.watch_ticker_subscription("BTC/USDT:USDT")

      # Both should generate valid channels
      assert is_binary(spot.channel)
      assert is_binary(perp.channel)
    end
  end

  # Helper to skip tests when no WS module is available
  defp skip_no_ws_module do
    flunk("No WS module available - sync exchanges with `mix ccxt.sync --tier1`")
  end
end
