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
end
