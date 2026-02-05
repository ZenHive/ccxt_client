defmodule CCXT.WS.PatternTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Pattern

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
