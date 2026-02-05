defmodule CCXT.SymbolTest do
  use ExUnit.Case, async: true

  alias CCXT.Symbol
  alias CCXT.Symbol.Error

  # Format maps matching exchange patterns (extracted from CCXT)
  @binance_format %{separator: "", case: :upper}
  @coinbase_format %{separator: "-", case: :upper}
  @bitstamp_format %{separator: "", case: :lower}
  @gateio_format %{separator: "_", case: :upper}

  # Spec-like map with currency aliases (e.g., Kraken uses XBT for BTC)
  @kraken_spec %{
    symbol_format: %{separator: "", case: :upper},
    currency_aliases: %{"BTC" => "XBT", "DOGE" => "XDG"}
  }

  describe "normalize/2" do
    test "passes through already unified symbols" do
      assert Symbol.normalize("BTC/USDT", @binance_format) == "BTC/USDT"
      assert Symbol.normalize("ETH/BTC", @binance_format) == "ETH/BTC"
    end

    test "normalizes concatenated symbols (Binance style)" do
      assert Symbol.normalize("BTCUSDT", @binance_format) == "BTC/USDT"
      assert Symbol.normalize("ETHBTC", @binance_format) == "ETH/BTC"
      assert Symbol.normalize("SOLUSDC", @binance_format) == "SOL/USDC"
    end

    test "normalizes dash-separated symbols (Coinbase style)" do
      assert Symbol.normalize("BTC-USD", @coinbase_format) == "BTC/USD"
      assert Symbol.normalize("ETH-EUR", @coinbase_format) == "ETH/EUR"
    end

    test "normalizes underscore-separated symbols (Gate.io style)" do
      assert Symbol.normalize("BTC_USDT", @gateio_format) == "BTC/USDT"
      assert Symbol.normalize("ETH_BTC", @gateio_format) == "ETH/BTC"
    end

    test "normalizes lowercase symbols (Bitstamp style)" do
      assert Symbol.normalize("btcusd", @bitstamp_format) == "BTC/USD"
      assert Symbol.normalize("etheur", @bitstamp_format) == "ETH/EUR"
    end

    test "applies currency aliases (Kraken style XBT -> BTC)" do
      # Kraken uses XBT internally, normalize converts to unified BTC
      assert Symbol.normalize("XBTUSDT", @kraken_spec) == "BTC/USDT"
      assert Symbol.normalize("XDGBTC", @kraken_spec) == "DOGE/BTC"
    end

    test "handles unknown format with default normalization" do
      # Empty format map uses defaults (no separator, uppercase)
      assert Symbol.normalize("BTCUSDT", %{}) == "BTC/USDT"
    end

    test "works with spec struct containing symbol_format" do
      # Simulates using a real CCXT.Spec struct
      spec = %{symbol_format: @coinbase_format, currency_aliases: %{}}
      assert Symbol.normalize("BTC-USD", spec) == "BTC/USD"
    end
  end

  describe "denormalize/2" do
    test "removes slash for most exchanges" do
      assert Symbol.denormalize("BTC/USDT", @binance_format) == "BTCUSDT"
      assert Symbol.denormalize("ETH/BTC", @binance_format) == "ETHBTC"
    end

    test "uses dash separator for Coinbase" do
      assert Symbol.denormalize("BTC/USD", @coinbase_format) == "BTC-USD"
      assert Symbol.denormalize("ETH/EUR", @coinbase_format) == "ETH-EUR"
    end

    test "uses underscore separator for Gate.io" do
      assert Symbol.denormalize("BTC/USDT", @gateio_format) == "BTC_USDT"
      assert Symbol.denormalize("ETH/BTC", @gateio_format) == "ETH_BTC"
    end

    test "uses lowercase for Bitstamp" do
      assert Symbol.denormalize("BTC/USD", @bitstamp_format) == "btcusd"
      assert Symbol.denormalize("ETH/EUR", @bitstamp_format) == "etheur"
    end

    test "strips settle currency for derivatives" do
      assert Symbol.denormalize("BTC/USDT:USDT", @binance_format) == "BTCUSDT"
      assert Symbol.denormalize("ETH/USD:USD", @coinbase_format) == "ETH-USD"
    end

    test "works with spec struct containing symbol_format" do
      spec = %{symbol_format: @gateio_format}
      assert Symbol.denormalize("BTC/USDT", spec) == "BTC_USDT"
    end
  end

  describe "parse/1" do
    test "parses spot symbol" do
      assert {:ok, result} = Symbol.parse("BTC/USDT")
      assert result.base == "BTC"
      assert result.quote == "USDT"
      assert result.settle == nil
    end

    test "parses derivative symbol with settle currency" do
      assert {:ok, result} = Symbol.parse("BTC/USDT:USDT")
      assert result.base == "BTC"
      assert result.quote == "USDT"
      assert result.settle == "USDT"
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = Symbol.parse("invalid")
      assert {:error, :invalid_format} = Symbol.parse("BTC")
      assert {:error, :invalid_format} = Symbol.parse("/USDT")
      assert {:error, :invalid_format} = Symbol.parse("BTC/")
    end
  end

  describe "parse!/1" do
    test "parses valid symbol" do
      result = Symbol.parse!("BTC/USDT")
      assert result.base == "BTC"
      assert result.quote == "USDT"
    end

    test "raises on invalid format" do
      assert_raise ArgumentError, ~r/invalid symbol format/, fn ->
        Symbol.parse!("invalid")
      end
    end
  end

  describe "build/3" do
    test "builds spot symbol" do
      assert Symbol.build("BTC", "USDT") == "BTC/USDT"
    end

    test "builds derivative symbol with settle" do
      assert Symbol.build("BTC", "USDT", "USDT") == "BTC/USDT:USDT"
    end

    test "ignores nil settle" do
      assert Symbol.build("ETH", "BTC", nil) == "ETH/BTC"
    end
  end

  describe "roundtrip" do
    test "normalize then denormalize returns exchange format" do
      original = "BTCUSDT"
      normalized = Symbol.normalize(original, @binance_format)
      denormalized = Symbol.denormalize(normalized, @binance_format)
      assert denormalized == original
    end

    test "denormalize then normalize returns unified format" do
      original = "BTC/USDT"
      denormalized = Symbol.denormalize(original, @binance_format)
      normalized = Symbol.normalize(denormalized, @binance_format)
      assert normalized == original
    end

    test "roundtrip works with Coinbase format" do
      original = "BTC-USD"
      normalized = Symbol.normalize(original, @coinbase_format)
      assert normalized == "BTC/USD"
      denormalized = Symbol.denormalize(normalized, @coinbase_format)
      assert denormalized == original
    end

    test "roundtrip works with Gate.io format" do
      original = "BTC_USDT"
      normalized = Symbol.normalize(original, @gateio_format)
      assert normalized == "BTC/USDT"
      denormalized = Symbol.denormalize(normalized, @gateio_format)
      assert denormalized == original
    end
  end

  # ============================================================================
  # to_exchange_id/3 and from_exchange_id/3 tests
  # ============================================================================

  describe "convert_date/3" do
    test "yymmdd to ddmmmyy" do
      assert Symbol.convert_date("260327", :yymmdd, :ddmmmyy) == "27MAR26"
      assert Symbol.convert_date("260109", :yymmdd, :ddmmmyy) == "9JAN26"
      assert Symbol.convert_date("251225", :yymmdd, :ddmmmyy) == "25DEC25"
    end

    test "ddmmmyy to yymmdd" do
      assert Symbol.convert_date("27MAR26", :ddmmmyy, :yymmdd) == "260327"
      assert Symbol.convert_date("9JAN26", :ddmmmyy, :yymmdd) == "260109"
      assert Symbol.convert_date("25DEC25", :ddmmmyy, :yymmdd) == "251225"
    end

    test "yymmdd to yyyymmdd" do
      assert Symbol.convert_date("260327", :yymmdd, :yyyymmdd) == "20260327"
      assert Symbol.convert_date("251225", :yymmdd, :yyyymmdd) == "20251225"
    end

    test "same format returns unchanged" do
      assert Symbol.convert_date("260327", :yymmdd, :yymmdd) == "260327"
      assert Symbol.convert_date("27MAR26", :ddmmmyy, :ddmmmyy) == "27MAR26"
    end
  end

  describe "to_exchange_id/3 spot patterns" do
    @binance_spec %{
      symbol_patterns: %{spot: %{pattern: :no_separator_upper, separator: "", case: :upper}}
    }
    @deribit_spec %{
      symbol_patterns: %{spot: %{pattern: :underscore_upper, separator: "_", case: :upper}}
    }
    @coinbase_spec %{
      symbol_patterns: %{spot: %{pattern: :dash_upper, separator: "-", case: :upper}}
    }
    @bitstamp_spec %{
      symbol_patterns: %{spot: %{pattern: :no_separator_lower, separator: "", case: :lower}}
    }

    test "no_separator_upper - Binance style" do
      assert Symbol.to_exchange_id("BTC/USDT", @binance_spec) == "BTCUSDT"
      assert Symbol.to_exchange_id("ETH/BTC", @binance_spec) == "ETHBTC"
    end

    test "underscore_upper - Deribit style" do
      assert Symbol.to_exchange_id("BNB/USDC", @deribit_spec) == "BNB_USDC"
      assert Symbol.to_exchange_id("ETH/BTC", @deribit_spec) == "ETH_BTC"
    end

    test "dash_upper - Coinbase style" do
      assert Symbol.to_exchange_id("BTC/USD", @coinbase_spec) == "BTC-USD"
      assert Symbol.to_exchange_id("ETH/EUR", @coinbase_spec) == "ETH-EUR"
    end

    test "no_separator_lower - Bitstamp style" do
      assert Symbol.to_exchange_id("BTC/USD", @bitstamp_spec) == "btcusd"
      assert Symbol.to_exchange_id("ETH/EUR", @bitstamp_spec) == "etheur"
    end
  end

  describe "to_exchange_id/3 swap patterns" do
    @binance_swap_spec %{
      symbol_patterns: %{swap: %{pattern: :implicit, separator: "", case: :upper, suffix: nil}}
    }
    @deribit_swap_spec %{
      symbol_patterns: %{
        swap: %{pattern: :suffix_perpetual, separator: "_", case: :upper, suffix: "-PERPETUAL"}
      }
    }
    @okx_swap_spec %{
      symbol_patterns: %{swap: %{pattern: :suffix_swap, separator: "-", case: :upper, suffix: "-SWAP"}}
    }

    test "implicit - Binance style" do
      assert Symbol.to_exchange_id("BTC/USDT:USDT", @binance_swap_spec) == "BTCUSDT"
    end

    test "suffix_perpetual - Deribit style" do
      assert Symbol.to_exchange_id("BTC/USD:BTC", @deribit_swap_spec) == "BTC_USD-PERPETUAL"
    end

    test "suffix_swap - OKX style" do
      assert Symbol.to_exchange_id("BTC/USDT:USDT", @okx_swap_spec) == "BTC-USDT-SWAP"
    end
  end

  describe "to_exchange_id/3 future patterns" do
    @binance_future_spec %{
      symbol_patterns: %{
        future: %{
          pattern: :future_yymmdd,
          separator: "_",
          case: :upper,
          date_format: :yymmdd
        }
      }
    }
    @deribit_future_spec %{
      symbol_patterns: %{
        future: %{
          pattern: :future_ddmmmyy,
          separator: "-",
          case: :upper,
          date_format: :ddmmmyy
        }
      }
    }
    @bybit_future_spec %{
      symbol_patterns: %{
        future: %{
          pattern: :future_ddmmmyy,
          separator: "-",
          case: :upper,
          date_format: :ddmmmyy
        }
      }
    }

    test "future_yymmdd - Binance style" do
      assert Symbol.to_exchange_id("BTC/USDT:USDT-260327", @binance_future_spec) == "BTC_USDT_260327"
    end

    test "future_ddmmmyy - Deribit style (base-date only for USD)" do
      assert Symbol.to_exchange_id("BTC/USD:BTC-260116", @deribit_future_spec) == "BTC-16JAN26"
    end

    test "future_ddmmmyy - Bybit style (base+quote-date)" do
      assert Symbol.to_exchange_id("BTC/USDT:USDT-260116", @bybit_future_spec) == "BTCUSDT-16JAN26"
    end
  end

  describe "to_exchange_id/3 option patterns" do
    @deribit_option_spec %{
      symbol_patterns: %{
        option: %{
          pattern: :option_ddmmmyy,
          separator: "-",
          case: :upper,
          date_format: :ddmmmyy
        }
      }
    }
    @okx_option_spec %{
      symbol_patterns: %{
        option: %{
          pattern: :option_yymmdd,
          separator: "-",
          case: :upper,
          date_format: :yymmdd
        }
      }
    }
    @bybit_option_spec %{
      symbol_patterns: %{
        option: %{
          pattern: :option_with_settle,
          separator: "-",
          case: :upper,
          date_format: :ddmmmyy
        }
      }
    }

    test "option_ddmmmyy - Deribit style" do
      assert Symbol.to_exchange_id("BTC/USD:BTC-260112-84000-C", @deribit_option_spec) ==
               "BTC-12JAN26-84000-C"
    end

    test "option_yymmdd - OKX style" do
      assert Symbol.to_exchange_id("BTC/USD:BTC-260112-80000-C", @okx_option_spec) ==
               "BTC-USD-260112-80000-C"
    end

    test "option_with_settle - Bybit style" do
      assert Symbol.to_exchange_id("BTC/USDT:USDT-261225-105000-P", @bybit_option_spec) ==
               "BTC-25DEC26-105000-P-USDT"
    end
  end

  describe "from_exchange_id/3 spot patterns" do
    @binance_spec %{
      symbol_patterns: %{spot: %{pattern: :no_separator_upper, separator: "", case: :upper}}
    }
    @deribit_spec %{
      symbol_patterns: %{spot: %{pattern: :underscore_upper, separator: "_", case: :upper}}
    }
    @coinbase_spec %{
      symbol_patterns: %{spot: %{pattern: :dash_upper, separator: "-", case: :upper}}
    }

    test "no_separator_upper - Binance style" do
      assert Symbol.from_exchange_id("BTCUSDT", @binance_spec, :spot) == "BTC/USDT"
    end

    test "underscore_upper - Deribit style" do
      assert Symbol.from_exchange_id("BNB_USDC", @deribit_spec, :spot) == "BNB/USDC"
    end

    test "dash_upper - Coinbase style" do
      assert Symbol.from_exchange_id("BTC-USD", @coinbase_spec, :spot) == "BTC/USD"
    end
  end

  describe "from_exchange_id/3 swap patterns" do
    @deribit_swap_spec %{
      symbol_patterns: %{
        swap: %{pattern: :suffix_perpetual, separator: "_", case: :upper, suffix: "-PERPETUAL"}
      }
    }
    @okx_swap_spec %{
      symbol_patterns: %{swap: %{pattern: :suffix_swap, separator: "-", case: :upper, suffix: "-SWAP"}}
    }

    test "suffix_perpetual - Deribit style" do
      assert Symbol.from_exchange_id("BTC_USD-PERPETUAL", @deribit_swap_spec, :swap) == "BTC/USD:BTC"
    end

    test "suffix_swap - OKX style" do
      assert Symbol.from_exchange_id("BTC-USDT-SWAP", @okx_swap_spec, :swap) == "BTC/USDT:USDT"
    end
  end

  describe "from_exchange_id/3 future patterns" do
    @binance_future_spec %{
      symbol_patterns: %{
        future: %{
          pattern: :future_yymmdd,
          separator: "_",
          case: :upper,
          date_format: :yymmdd
        }
      }
    }
    @deribit_future_spec %{
      symbol_patterns: %{
        future: %{
          pattern: :future_ddmmmyy,
          separator: "-",
          case: :upper,
          date_format: :ddmmmyy
        }
      }
    }

    test "future_yymmdd - Binance style" do
      assert Symbol.from_exchange_id("BTCUSDT_260327", @binance_future_spec, :future) ==
               "BTC/USDT:USDT-260327"
    end

    test "future_ddmmmyy - Deribit style" do
      assert Symbol.from_exchange_id("BTC-16JAN26", @deribit_future_spec, :future) ==
               "BTC/USD:BTC-260116"
    end

    test "future_ddmmmyy - Bybit style" do
      assert Symbol.from_exchange_id("BTCUSDT-16JAN26", @deribit_future_spec, :future) ==
               "BTC/USDT:USDT-260116"
    end
  end

  describe "from_exchange_id/3 option patterns" do
    @deribit_option_spec %{
      symbol_patterns: %{
        option: %{
          pattern: :option_ddmmmyy,
          separator: "-",
          case: :upper,
          date_format: :ddmmmyy
        }
      }
    }
    @okx_option_spec %{
      symbol_patterns: %{
        option: %{
          pattern: :option_yymmdd,
          separator: "-",
          case: :upper,
          date_format: :yymmdd
        }
      }
    }
    @bybit_option_spec %{
      symbol_patterns: %{
        option: %{
          pattern: :option_with_settle,
          separator: "-",
          case: :upper,
          date_format: :ddmmmyy
        }
      }
    }

    test "option_ddmmmyy - Deribit style" do
      assert Symbol.from_exchange_id("BTC-12JAN26-84000-C", @deribit_option_spec, :option) ==
               "BTC/USD:BTC-260112-84000-C"
    end

    test "option_yymmdd - OKX style" do
      assert Symbol.from_exchange_id("BTC-USD-260112-80000-C", @okx_option_spec, :option) ==
               "BTC/USD:BTC-260112-80000-C"
    end

    test "option_with_settle - Bybit style" do
      assert Symbol.from_exchange_id("BTC-25DEC26-105000-P-USDT", @bybit_option_spec, :option) ==
               "BTC/USDT:USDT-261225-105000-P"
    end
  end

  describe "to_exchange_id/3 with currency aliases" do
    @kraken_spec %{
      currency_aliases: %{"BTC" => "XBT"},
      symbol_patterns: %{spot: %{pattern: :no_separator_upper, separator: "", case: :upper}}
    }

    test "applies forward alias (unified -> exchange)" do
      assert Symbol.to_exchange_id("BTC/USDT", @kraken_spec) == "XBTUSDT"
    end
  end

  describe "to_exchange_id/3 fallback" do
    test "falls back to denormalize when no pattern found" do
      spec = %{symbol_format: %{separator: "-", case: :upper}}
      assert Symbol.to_exchange_id("BTC/USDT", spec) == "BTC-USDT"
    end

    test "falls back when symbol_patterns is empty" do
      spec = %{symbol_patterns: %{}, symbol_format: %{separator: "_", case: :upper}}
      assert Symbol.to_exchange_id("BTC/USDT", spec) == "BTC_USDT"
    end
  end

  describe "bidirectional roundtrip" do
    @binance_full_spec %{
      symbol_patterns: %{
        spot: %{pattern: :no_separator_upper, separator: "", case: :upper},
        swap: %{pattern: :implicit, separator: "", case: :upper, suffix: nil},
        future: %{pattern: :future_yymmdd, separator: "_", case: :upper, date_format: :yymmdd}
      }
    }

    test "spot roundtrip" do
      unified = "BTC/USDT"
      exchange_id = Symbol.to_exchange_id(unified, @binance_full_spec)
      assert exchange_id == "BTCUSDT"
      result = Symbol.from_exchange_id(exchange_id, @binance_full_spec, :spot)
      assert result == unified
    end

    test "future roundtrip" do
      unified = "BTC/USDT:USDT-260327"
      exchange_id = Symbol.to_exchange_id(unified, @binance_full_spec)
      assert exchange_id == "BTC_USDT_260327"
      result = Symbol.from_exchange_id(exchange_id, @binance_full_spec, :future)
      assert result == unified
    end
  end

  # ============================================================================
  # R7: Edge Case Tests
  # ============================================================================

  describe "to_exchange_id!/3 bang function" do
    @binance_spec %{
      symbol_patterns: %{spot: %{pattern: :no_separator_upper, separator: "", case: :upper}}
    }

    test "returns exchange ID on success" do
      assert Symbol.to_exchange_id!("BTC/USDT", @binance_spec) == "BTCUSDT"
    end

    test "raises on invalid symbol format" do
      assert_raise Error, ~r/Invalid symbol format/, fn ->
        Symbol.to_exchange_id!("INVALID", @binance_spec)
      end
    end

    test "raises when pattern not found" do
      empty_spec = %{symbol_patterns: %{}}

      assert_raise Error, ~r/No symbol pattern found/, fn ->
        Symbol.to_exchange_id!("BTC/USDT", empty_spec)
      end
    end

    test "error includes market type" do
      empty_spec = %{symbol_patterns: %{}}

      error =
        assert_raise Error, fn ->
          Symbol.to_exchange_id!("BTC/USDT", empty_spec)
        end

      assert error.market_type == :spot
      assert error.reason == :pattern_not_found
    end
  end

  describe "from_exchange_id!/3 bang function" do
    @binance_spec %{
      symbol_patterns: %{spot: %{pattern: :no_separator_upper, separator: "", case: :upper}}
    }

    test "returns unified symbol on success" do
      assert Symbol.from_exchange_id!("BTCUSDT", @binance_spec, :spot) == "BTC/USDT"
    end

    test "raises when pattern not found" do
      empty_spec = %{symbol_patterns: %{}}

      assert_raise Error, ~r/No symbol pattern found/, fn ->
        Symbol.from_exchange_id!("BTCUSDT", empty_spec, :spot)
      end
    end
  end

  describe "validate_symbol_conversion/3" do
    @binance_spec %{
      symbol_patterns: %{spot: %{pattern: :no_separator_upper, separator: "", case: :upper}}
    }

    test "returns :ok when pattern will match" do
      assert :ok = Symbol.validate_symbol_conversion("BTC/USDT", @binance_spec)
    end

    test "returns :ok with legacy fallback" do
      legacy_spec = %{symbol_format: %{separator: "-", case: :upper}}
      assert :ok = Symbol.validate_symbol_conversion("BTC/USDT", legacy_spec)
    end

    test "returns error on invalid format" do
      assert {:error, :invalid_format} = Symbol.validate_symbol_conversion("INVALID", @binance_spec)
    end

    test "returns error when no pattern and no fallback" do
      empty_spec = %{}
      assert {:error, {:pattern_not_found, :spot}} = Symbol.validate_symbol_conversion("BTC/USDT", empty_spec)
    end
  end

  describe "strip_prefix/1" do
    test "strips KrakenFutures PI_ prefix" do
      assert {"PI_", "XBTUSD"} = Symbol.strip_prefix("PI_XBTUSD")
    end

    test "strips KrakenFutures PF_ prefix" do
      assert {"PF_", "ETHUSD"} = Symbol.strip_prefix("PF_ETHUSD")
    end

    test "strips KrakenFutures FI_ prefix" do
      assert {"FI_", "XBTUSD"} = Symbol.strip_prefix("FI_XBTUSD")
    end

    test "strips Kraken XX prefix" do
      assert {"X", "XBT"} = Symbol.strip_prefix("XXBT")
    end

    test "strips Kraken Z prefix for 4-char fiat" do
      assert {"Z", "USD"} = Symbol.strip_prefix("ZUSD")
    end

    test "returns nil prefix for regular symbols" do
      assert {nil, "BTCUSDT"} = Symbol.strip_prefix("BTCUSDT")
    end

    test "returns nil prefix for dash-separated symbols" do
      assert {nil, "BTC-USD"} = Symbol.strip_prefix("BTC-USD")
    end
  end

  describe "normalize_kraken/2" do
    @kraken_spec %{
      currency_aliases: %{"BTC" => "XBT", "DOGE" => "XDG"}
    }

    test "normalizes XXBTZUSD to BTC/USD" do
      assert Symbol.normalize_kraken("XXBTZUSD", @kraken_spec) == "BTC/USD"
    end

    test "normalizes XETHZEUR to ETH/EUR" do
      assert Symbol.normalize_kraken("XETHZEUR", @kraken_spec) == "ETH/EUR"
    end

    test "normalizes without aliases" do
      assert Symbol.normalize_kraken("XETHZUSD", %{}) == "ETH/USD"
    end

    test "handles lowercase input" do
      assert Symbol.normalize_kraken("xxbtzusd", @kraken_spec) == "BTC/USD"
    end
  end

  describe "get_quote_currencies/1" do
    test "returns spec's known_quote_currencies when available" do
      spec = %{known_quote_currencies: ["CUSTOM", "TEST"]}
      assert Symbol.get_quote_currencies(spec) == ["CUSTOM", "TEST"]
    end

    test "returns defaults when spec has nil" do
      spec = %{known_quote_currencies: nil}
      result = Symbol.get_quote_currencies(spec)
      assert "USDT" in result
      assert "USD" in result
    end

    test "returns defaults when spec has empty list" do
      spec = %{known_quote_currencies: []}
      result = Symbol.get_quote_currencies(spec)
      assert "USDT" in result
    end

    test "returns defaults when spec has no known_quote_currencies" do
      result = Symbol.get_quote_currencies(%{})
      assert "USDT" in result
      assert "BTC" in result
    end
  end

  describe "edge cases - silent fallback scenarios" do
    test "to_exchange_id returns input when parse fails (non-bang)" do
      # Non-bang version should return input unchanged, not crash
      result = Symbol.to_exchange_id("INVALID_NO_SLASH", %{})
      assert result == "INVALID_NO_SLASH"
    end

    test "from_exchange_id falls back to normalize when no pattern" do
      # Should use normalize as fallback, not crash
      spec = %{symbol_format: %{separator: "-", case: :upper}}
      result = Symbol.from_exchange_id("BTC-USD", spec, :spot)
      assert result == "BTC/USD"
    end
  end
end
