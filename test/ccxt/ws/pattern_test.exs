defmodule CCXT.WS.PatternTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Pattern

  describe "apply_template_params/3" do
    test "empty params list returns parts unchanged" do
      assert Pattern.apply_template_params(["ticker", "BTC"], [], %{}) == ["ticker", "BTC"]
    end

    test "appends param with non-nil default" do
      params = [%{"name" => "interval", "default" => "100ms"}]
      assert Pattern.apply_template_params(["ticker", "BTC"], params, %{}) == ["ticker", "BTC", "100ms"]
    end

    test "skips param with nil default" do
      params = [%{"name" => "limit", "default" => nil}]
      assert Pattern.apply_template_params(["ticker", "BTC"], params, %{}) == ["ticker", "BTC"]
    end

    test "runtime string-key override replaces default" do
      params = [%{"name" => "interval", "default" => "100ms"}]
      result = Pattern.apply_template_params(["ticker"], params, %{"interval" => "raw"})
      assert result == ["ticker", "raw"]
    end

    test "runtime atom-key override works via stringify_keys" do
      params = [%{"name" => "interval", "default" => "100ms"}]
      result = Pattern.apply_template_params(["ticker"], params, %{interval: "raw"})
      assert result == ["ticker", "raw"]
    end

    test "falsey override 0 is preserved (not replaced by default)" do
      params = [%{"name" => "depth", "default" => "10"}]
      result = Pattern.apply_template_params(["book"], params, %{"depth" => 0})
      assert result == ["book", "0"]
    end

    test "falsey override false is preserved" do
      params = [%{"name" => "snapshot", "default" => "true"}]
      result = Pattern.apply_template_params(["book"], params, %{"snapshot" => false})
      assert result == ["book", "false"]
    end

    test "skips positional params (symbol, timeframe, limit)" do
      params = [
        %{"name" => "symbol", "default" => "BTC"},
        %{"name" => "timeframe", "default" => "1m"},
        %{"name" => "limit", "default" => "100"},
        %{"name" => "interval", "default" => "100ms"}
      ]

      result = Pattern.apply_template_params(["ticker"], params, %{})
      # Only interval should be appended, positional params skipped
      assert result == ["ticker", "100ms"]
    end

    test "handles non-map runtime_params gracefully" do
      params = [%{"name" => "interval", "default" => "100ms"}]
      result = Pattern.apply_template_params(["ticker"], params, nil)
      assert result == ["ticker", "100ms"]
    end

    test "ignores non-atom/non-string keys in runtime_params" do
      params = [%{"name" => "interval", "default" => "100ms"}]
      result = Pattern.apply_template_params(["ticker"], params, %{1 => "x"})
      assert result == ["ticker", "100ms"]
    end

    test "multiple template params appended in order" do
      params = [
        %{"name" => "interval", "default" => "100ms"},
        %{"name" => "depth", "default" => "10"}
      ]

      result = Pattern.apply_template_params(["book", "BTC"], params, %{})
      assert result == ["book", "BTC", "100ms", "10"]
    end
  end

  describe "format_market_id/2" do
    test "converts unified symbol to exchange format (removes slash)" do
      assert Pattern.format_market_id("BTC/USDT", :native) == "BTCUSDT"
    end

    test "handles symbol without slash" do
      assert Pattern.format_market_id("BTCUSDT", :native) == "BTCUSDT"
    end

    test "applies lowercase when format is :lowercase" do
      assert Pattern.format_market_id("BTC/USDT", :lowercase) == "btcusdt"
    end

    test "applies uppercase when format is :uppercase" do
      assert Pattern.format_market_id("btc/usdt", :uppercase) == "BTCUSDT"
    end

    test "defaults to native format when format is nil" do
      assert Pattern.format_market_id("BTC/USDT", nil) == "BTCUSDT"
    end

    test "returns empty string for nil symbol" do
      assert Pattern.format_market_id(nil, :native) == ""
    end
  end

  describe "format_market_id/3 with symbol_context" do
    # OKX-style: dash separator (BTC/USDT → BTC-USDT)
    @okx_ctx %{
      symbol_patterns: %{
        spot: %{case: :upper, pattern: :dash_upper, suffix: nil, separator: "-", date_format: nil, component_order: nil}
      },
      symbol_format: nil,
      symbol_formats: nil,
      currency_aliases: %{}
    }

    # Binance-style: no separator (BTC/USDT → BTCUSDT)
    @binance_ctx %{
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

    # Coinbase-style: dash separator (BTC/USD → BTC-USD)
    @coinbase_ctx %{
      symbol_patterns: %{
        spot: %{case: :upper, pattern: :dash_upper, suffix: nil, separator: "-", date_format: nil, component_order: nil}
      },
      symbol_format: nil,
      symbol_formats: nil,
      currency_aliases: %{}
    }

    test "OKX: produces dash-separated symbol" do
      assert Pattern.format_market_id("BTC/USDT", :native, @okx_ctx) == "BTC-USDT"
    end

    test "OKX: casing preserved with :native format" do
      assert Pattern.format_market_id("ETH/USDT", :native, @okx_ctx) == "ETH-USDT"
    end

    test "Binance: no separator with :lowercase applies casing after conversion" do
      assert Pattern.format_market_id("BTC/USDT", :lowercase, @binance_ctx) == "btcusdt"
    end

    test "Binance: no separator with :native preserves case" do
      assert Pattern.format_market_id("BTC/USDT", :native, @binance_ctx) == "BTCUSDT"
    end

    test "Coinbase: dash separator for BTC/USD" do
      assert Pattern.format_market_id("BTC/USD", :native, @coinbase_ctx) == "BTC-USD"
    end

    test "returns empty string for nil symbol with symbol_context" do
      assert Pattern.format_market_id(nil, :native, @okx_ctx) == ""
    end

    test "falls back to /2 behavior when symbol_context is nil" do
      assert Pattern.format_market_id("BTC/USDT", :native, nil) == "BTCUSDT"
    end

    test "falls back to /2 behavior when symbol_context is empty map" do
      assert Pattern.format_market_id("BTC/USDT", :lowercase, %{}) == "btcusdt"
    end

    test "falls back to /2 behavior when symbol_context has only nil fields" do
      ctx = %{symbol_patterns: nil, symbol_format: nil, symbol_formats: nil, currency_aliases: %{}}
      assert Pattern.format_market_id("BTC/USDT", :native, ctx) == "BTCUSDT"
    end

    test "symbol already in exchange format is not corrupted (regression: unchanged != failure)" do
      # When to_exchange_id returns the same string as input, that's a valid result —
      # not a signal to fall back to naive slash removal
      assert Pattern.format_market_id("BTCUSDT", :native, @binance_ctx) == "BTCUSDT"
      assert Pattern.format_market_id("BTCUSDT", :lowercase, @binance_ctx) == "btcusdt"
    end

    test "slash-containing symbol preserved correctly when context matches identity" do
      # BTC/USDT with Binance context → BTCUSDT (not double-processed)
      assert Pattern.format_market_id("BTC/USDT", :native, @binance_ctx) == "BTCUSDT"
    end
  end
end
