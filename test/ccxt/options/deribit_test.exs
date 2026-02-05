defmodule CCXT.Options.DeribitTest do
  use ExUnit.Case, async: true

  alias CCXT.Options.Deribit

  describe "parse_option/1" do
    test "parses BTC call option" do
      assert {:ok, parsed} = Deribit.parse_option("BTC-31JAN26-84000-C")

      assert parsed.underlying == "BTC"
      assert parsed.expiry == ~D[2026-01-31]
      assert parsed.strike == 84_000.0
      assert parsed.type == :call
    end

    test "parses ETH put option" do
      assert {:ok, parsed} = Deribit.parse_option("ETH-28MAR25-2500-P")

      assert parsed.underlying == "ETH"
      assert parsed.expiry == ~D[2025-03-28]
      assert parsed.strike == 2500.0
      assert parsed.type == :put
    end

    test "parses single-digit day" do
      assert {:ok, parsed} = Deribit.parse_option("BTC-7FEB26-90000-C")

      assert parsed.expiry == ~D[2026-02-07]
    end

    test "parses all months" do
      months = [
        {"JAN", 1},
        {"FEB", 2},
        {"MAR", 3},
        {"APR", 4},
        {"MAY", 5},
        {"JUN", 6},
        {"JUL", 7},
        {"AUG", 8},
        {"SEP", 9},
        {"OCT", 10},
        {"NOV", 11},
        {"DEC", 12}
      ]

      for {month_str, month_num} <- months do
        symbol = "BTC-15#{month_str}25-50000-C"
        assert {:ok, parsed} = Deribit.parse_option(symbol)
        assert parsed.expiry.month == month_num
      end
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = Deribit.parse_option("invalid")
      assert {:error, :invalid_format} = Deribit.parse_option("BTC/USDT")
      assert {:error, :invalid_format} = Deribit.parse_option("BTC-PERP")
      assert {:error, :invalid_format} = Deribit.parse_option("")
    end

    test "returns error for invalid month" do
      assert {:error, :invalid_format} = Deribit.parse_option("BTC-31XXX26-84000-C")
    end

    test "returns error for invalid date" do
      # February 31st doesn't exist
      assert {:error, :invalid_format} = Deribit.parse_option("BTC-31FEB26-84000-C")
    end
  end

  describe "parse_option!/1" do
    test "returns parsed data on success" do
      parsed = Deribit.parse_option!("BTC-31JAN26-84000-C")

      assert parsed.underlying == "BTC"
      assert parsed.strike == 84_000.0
    end

    test "raises on invalid format" do
      assert_raise ArgumentError, ~r/Invalid option symbol/, fn ->
        Deribit.parse_option!("invalid")
      end
    end
  end

  describe "strike/1" do
    test "extracts strike price" do
      assert {:ok, 84_000.0} = Deribit.strike("BTC-31JAN26-84000-C")
      assert {:ok, 2500.0} = Deribit.strike("ETH-28MAR25-2500-P")
    end

    test "returns error for invalid symbol" do
      assert {:error, :invalid_format} = Deribit.strike("invalid")
    end
  end

  describe "expiry/1" do
    test "extracts expiry date" do
      assert {:ok, ~D[2026-01-31]} = Deribit.expiry("BTC-31JAN26-84000-C")
    end

    test "returns error for invalid symbol" do
      assert {:error, :invalid_format} = Deribit.expiry("invalid")
    end
  end

  describe "option_type/1" do
    test "extracts call type" do
      assert {:ok, :call} = Deribit.option_type("BTC-31JAN26-84000-C")
    end

    test "extracts put type" do
      assert {:ok, :put} = Deribit.option_type("BTC-31JAN26-84000-P")
    end

    test "returns error for invalid symbol" do
      assert {:error, :invalid_format} = Deribit.option_type("invalid")
    end
  end

  describe "underlying/1" do
    test "extracts underlying asset" do
      assert {:ok, "BTC"} = Deribit.underlying("BTC-31JAN26-84000-C")
      assert {:ok, "ETH"} = Deribit.underlying("ETH-28MAR25-2500-P")
      assert {:ok, "SOL"} = Deribit.underlying("SOL-15DEC25-100-C")
    end

    test "returns error for invalid symbol" do
      assert {:error, :invalid_format} = Deribit.underlying("invalid")
    end
  end

  describe "valid_option?/1" do
    test "returns true for valid symbols" do
      assert Deribit.valid_option?("BTC-31JAN26-84000-C")
      assert Deribit.valid_option?("ETH-28MAR25-2500-P")
    end

    test "returns false for invalid symbols" do
      refute Deribit.valid_option?("invalid")
      refute Deribit.valid_option?("BTC/USDT")
      refute Deribit.valid_option?("BTC-PERP")
    end
  end
end
