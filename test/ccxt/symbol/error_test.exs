defmodule CCXT.Symbol.ErrorTest do
  use ExUnit.Case, async: true

  alias CCXT.Symbol.Error

  describe "new/2" do
    test "creates error with message and defaults" do
      error = Error.new("something broke")

      assert error.message == "something broke"
      assert error.symbol == nil
      assert error.reason == :unknown
      assert error.spec_name == nil
      assert error.market_type == nil
    end

    test "creates error with all options" do
      error =
        Error.new("bad symbol",
          symbol: "BTCUSDT",
          reason: :invalid_format,
          spec_name: :binance,
          market_type: :spot
        )

      assert error.message == "bad symbol"
      assert error.symbol == "BTCUSDT"
      assert error.reason == :invalid_format
      assert error.spec_name == :binance
      assert error.market_type == :spot
    end
  end

  describe "invalid_format/1" do
    test "creates error with :invalid_format reason" do
      error = Error.invalid_format("INVALID!!!")

      assert error.reason == :invalid_format
      assert error.symbol == "INVALID!!!"
      assert error.message =~ "Invalid symbol format"
      assert error.message =~ "INVALID!!!"
    end
  end

  describe "pattern_not_found/3" do
    test "creates error without spec_name" do
      error = Error.pattern_not_found("BTC/USDT", :spot)

      assert error.reason == :pattern_not_found
      assert error.symbol == "BTC/USDT"
      assert error.market_type == :spot
      assert error.spec_name == nil
      assert error.message =~ "No symbol pattern found for market type :spot"
      refute error.message =~ " in "
    end

    test "creates error with spec_name" do
      error = Error.pattern_not_found("BTC/USDT", :swap, :bybit)

      assert error.reason == :pattern_not_found
      assert error.symbol == "BTC/USDT"
      assert error.market_type == :swap
      assert error.spec_name == :bybit
      assert error.message =~ "No symbol pattern found for market type :swap in bybit"
    end
  end

  describe "unknown_quote_currency/2" do
    test "creates error without attempted_split" do
      error = Error.unknown_quote_currency("BTCUSDT")

      assert error.reason == :unknown_quote_currency
      assert error.symbol == "BTCUSDT"
      assert error.message =~ "Could not determine quote currency"
      assert error.message =~ "BTCUSDT"
      refute error.message =~ "tried to split"
    end

    test "creates error with attempted_split" do
      error = Error.unknown_quote_currency("BTCUSDT", "BTC/USDT")

      assert error.reason == :unknown_quote_currency
      assert error.symbol == "BTCUSDT"
      assert error.message =~ "tried to split: BTC/USDT"
    end
  end

  describe "parse_failed/2" do
    test "creates error with reason in message" do
      error = Error.parse_failed("BTC-USDT", :no_separator)

      assert error.reason == :parse_failed
      assert error.symbol == "BTC-USDT"
      assert error.message =~ "Failed to parse symbol"
      assert error.message =~ "BTC-USDT"
      assert error.message =~ ":no_separator"
    end
  end

  describe "unsupported_prefix/2" do
    test "creates error with tuple reason" do
      error = Error.unsupported_prefix("m:BTC/USDT", "m")

      assert error.reason == {:unsupported_prefix, "m"}
      assert error.symbol == "m:BTC/USDT"
      assert error.message =~ "Unsupported prefix"
      assert error.message =~ ~s("m")
      assert error.message =~ "m:BTC/USDT"
    end
  end

  describe "Exception protocol" do
    test "message/1 returns the message string" do
      error = Error.invalid_format("BAD")
      assert Exception.message(error) == error.message
    end

    test "can be raised and rescued" do
      assert_raise Error, ~r/Invalid symbol format/, fn ->
        raise Error.invalid_format("BAD")
      end
    end
  end
end
