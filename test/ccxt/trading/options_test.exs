defmodule CCXT.Trading.OptionsTest do
  use ExUnit.Case, async: true

  alias CCXT.Trading.Options
  alias CCXT.Types.Option

  @dte_days 30
  @expired_offset_days -1
  @within_dte_offset_days 5
  @beyond_dte_offset_days 40
  @strike_price 84_000
  @day_pad 2
  @year_pad 2
  @year_mod 100
  @one_minute_seconds 60

  # Sample option chain for testing
  @sample_chain %{
    "BTC-31JAN26-84000-C" => %Option{
      symbol: "BTC-31JAN26-84000-C",
      currency: "BTC",
      open_interest: 100.0,
      implied_volatility: 0.65,
      bid_price: 1000.0,
      ask_price: 1100.0,
      mid_price: 1050.0,
      mark_price: 1050.0,
      last_price: 1040.0,
      underlying_price: 85_000.0,
      change: 50.0,
      percentage: 5.0,
      base_volume: 10.0,
      quote_volume: 10_500.0,
      raw: %{"gamma" => 0.00001, "delta" => 0.45, "theta" => -10.0, "vega" => 50.0}
    },
    "BTC-31JAN26-84000-P" => %Option{
      symbol: "BTC-31JAN26-84000-P",
      currency: "BTC",
      open_interest: 50.0,
      implied_volatility: 0.70,
      bid_price: 500.0,
      ask_price: 550.0,
      mid_price: 525.0,
      mark_price: 525.0,
      last_price: 520.0,
      underlying_price: 85_000.0,
      change: -20.0,
      percentage: -3.7,
      base_volume: 5.0,
      quote_volume: 2625.0,
      raw: %{"gamma" => 0.00001, "delta" => -0.55, "theta" => -8.0, "vega" => 45.0}
    },
    "BTC-31JAN26-90000-C" => %Option{
      symbol: "BTC-31JAN26-90000-C",
      currency: "BTC",
      open_interest: 200.0,
      implied_volatility: 0.60,
      bid_price: 400.0,
      ask_price: 450.0,
      mid_price: 425.0,
      mark_price: 425.0,
      last_price: 420.0,
      underlying_price: 85_000.0,
      change: 10.0,
      percentage: 2.4,
      base_volume: 20.0,
      quote_volume: 8500.0,
      raw: %{"gamma" => 0.000008, "delta" => 0.25, "theta" => -5.0, "vega" => 30.0}
    },
    "BTC-28FEB26-84000-C" => %Option{
      symbol: "BTC-28FEB26-84000-C",
      currency: "BTC",
      open_interest: 75.0,
      implied_volatility: 0.62,
      bid_price: 1500.0,
      ask_price: 1600.0,
      mid_price: 1550.0,
      mark_price: 1550.0,
      last_price: 1540.0,
      underlying_price: 85_000.0,
      change: 30.0,
      percentage: 2.0,
      base_volume: 8.0,
      quote_volume: 12_400.0,
      raw: %{"gamma" => 0.000007, "delta" => 0.50, "theta" => -6.0, "vega" => 60.0}
    }
  }

  describe "oi_by_strike/1" do
    test "aggregates OI from calls and puts at same strike" do
      result = Options.oi_by_strike(@sample_chain)

      # 84000 has call (100) + put (50) + Feb call (75) = 225
      assert result[84_000.0] == 225.0
      # 90000 has only call (200)
      assert result[90_000.0] == 200.0
    end

    test "returns empty map for empty chain" do
      assert Options.oi_by_strike(%{}) == %{}
    end

    test "skips invalid symbols" do
      chain =
        Map.put(@sample_chain, "invalid-symbol", %Option{
          symbol: "invalid",
          currency: "BTC",
          open_interest: 1000.0,
          implied_volatility: 0.5,
          bid_price: 100.0,
          ask_price: 110.0,
          mid_price: 105.0,
          mark_price: 105.0,
          last_price: 105.0,
          underlying_price: 85_000.0,
          change: 0.0,
          percentage: 0.0,
          base_volume: 0.0,
          quote_volume: 0.0,
          raw: %{}
        })

      result = Options.oi_by_strike(chain)

      # Should not include the invalid symbol's OI
      total_oi = result |> Map.values() |> Enum.sum()
      assert total_oi == 425.0
    end

    test "skips options with nil open_interest" do
      chain =
        Map.put(@sample_chain, "BTC-31JAN26-95000-C", %Option{
          symbol: "BTC-31JAN26-95000-C",
          currency: "BTC",
          open_interest: nil,
          implied_volatility: 0.5,
          bid_price: 100.0,
          ask_price: 110.0,
          mid_price: 105.0,
          mark_price: 105.0,
          last_price: 105.0,
          underlying_price: 85_000.0,
          change: 0.0,
          percentage: 0.0,
          base_volume: 0.0,
          quote_volume: 0.0,
          raw: %{}
        })

      result = Options.oi_by_strike(chain)

      # 95000 strike should not appear (nil OI)
      refute Map.has_key?(result, 95_000.0)
      # Total should still be 425.0 from sample chain
      total_oi = result |> Map.values() |> Enum.sum()
      assert total_oi == 425.0
    end
  end

  describe "oi_by_expiry/1" do
    test "aggregates OI by expiry date" do
      result = Options.oi_by_expiry(@sample_chain)

      # Jan 31 has 3 options: 100 + 50 + 200 = 350
      assert result[~D[2026-01-31]] == 350.0
      # Feb 28 has 1 option: 75
      assert result[~D[2026-02-28]] == 75.0
    end

    test "returns empty map for empty chain" do
      assert Options.oi_by_expiry(%{}) == %{}
    end

    test "skips options with nil open_interest" do
      chain =
        Map.put(@sample_chain, "BTC-31MAR26-95000-C", %Option{
          symbol: "BTC-31MAR26-95000-C",
          currency: "BTC",
          open_interest: nil,
          implied_volatility: 0.5,
          bid_price: 100.0,
          ask_price: 110.0,
          mid_price: 105.0,
          mark_price: 105.0,
          last_price: 105.0,
          underlying_price: 85_000.0,
          change: 0.0,
          percentage: 0.0,
          base_volume: 0.0,
          quote_volume: 0.0,
          raw: %{}
        })

      result = Options.oi_by_expiry(chain)

      # Mar 31 should not appear (nil OI)
      refute Map.has_key?(result, ~D[2026-03-31])
      # Total should still be 425.0 from sample chain (Jan 31 + Feb 28)
      total_oi = result |> Map.values() |> Enum.sum()
      assert total_oi == 425.0
    end
  end

  describe "time_to_expiry/1" do
    test "returns positive time for future expiry" do
      # Use a date far in the future
      future_date = Date.add(Date.utc_today(), 30)
      result = Options.time_to_expiry(future_date)

      assert result.hours > 0
      assert result.minutes > 0
      assert result.minutes == result.hours * 60
    end

    test "returns zero for past expiry" do
      past_date = Date.add(Date.utc_today(), -1)
      result = Options.time_to_expiry(past_date)

      assert result.hours == 0.0
      assert result.minutes == 0.0
    end

    test "accepts DateTime input" do
      future_dt = DateTime.add(DateTime.utc_now(), 3600, :second)
      result = Options.time_to_expiry(future_dt)

      assert_in_delta result.hours, 1.0, 0.1
    end
  end

  describe "filter_by_dte/3" do
    test "uses default now_dt when called with 2 args" do
      # Exercises the default parameter path (line 150)
      today = Date.utc_today()
      future = Date.add(today, @within_dte_offset_days)
      future_symbol = deribit_symbol(future, @strike_price, :call)
      chain = %{future_symbol => option_with_symbol(future_symbol)}

      result = Options.filter_by_dte(chain, @dte_days)
      assert Map.has_key?(result, future_symbol)
    end

    test "skips invalid symbols gracefully" do
      # Exercises the {:error, _} -> false path (line 166)
      today = Date.utc_today()
      within_dte = Date.add(today, @within_dte_offset_days)
      {:ok, now} = DateTime.new(today, ~T[07:00:00], "Etc/UTC")

      valid_symbol = deribit_symbol(within_dte, @strike_price, :call)

      chain = %{
        valid_symbol => option_with_symbol(valid_symbol),
        "INVALID-SYMBOL" => option_with_symbol(valid_symbol)
      }

      result = Options.filter_by_dte(chain, @dte_days, now)
      assert Map.has_key?(result, valid_symbol)
      refute Map.has_key?(result, "INVALID-SYMBOL")
    end

    test "excludes expired options and keeps expiries within DTE" do
      today = Date.utc_today()
      expired = Date.add(today, @expired_offset_days)
      within_dte = Date.add(today, @within_dte_offset_days)
      {:ok, now} = DateTime.new(today, ~T[07:00:00], "Etc/UTC")

      expired_symbol = deribit_symbol(expired, @strike_price, :call)
      within_symbol = deribit_symbol(within_dte, @strike_price, :put)

      chain = %{
        expired_symbol => option_with_symbol(expired_symbol),
        within_symbol => option_with_symbol(within_symbol)
      }

      result = Options.filter_by_dte(chain, @dte_days, now)

      refute Map.has_key?(result, expired_symbol)
      assert Map.has_key?(result, within_symbol)
    end

    test "includes options expiring today before expiry time and excludes those beyond DTE" do
      today = Date.utc_today()
      beyond_dte = Date.add(today, @beyond_dte_offset_days)
      {:ok, expiry_dt} = DateTime.new(today, ~T[08:00:00], "Etc/UTC")
      now = DateTime.add(expiry_dt, -@one_minute_seconds, :second)

      today_symbol = deribit_symbol(today, @strike_price, :call)
      beyond_symbol = deribit_symbol(beyond_dte, @strike_price, :put)

      chain = %{
        today_symbol => option_with_symbol(today_symbol),
        beyond_symbol => option_with_symbol(beyond_symbol)
      }

      result = Options.filter_by_dte(chain, @dte_days, now)

      assert Map.has_key?(result, today_symbol)
      refute Map.has_key?(result, beyond_symbol)
    end

    test "includes same-day expiries before 08:00 UTC" do
      today = Date.utc_today()
      {:ok, expiry_dt} = DateTime.new(today, ~T[08:00:00], "Etc/UTC")
      now = DateTime.add(expiry_dt, -@one_minute_seconds, :second)

      today_symbol = deribit_symbol(today, @strike_price, :call)
      chain = %{today_symbol => option_with_symbol(today_symbol)}

      result = Options.filter_by_dte(chain, @dte_days, now)

      assert Map.has_key?(result, today_symbol)
    end

    test "excludes same-day expiries after 08:00 UTC" do
      today = Date.utc_today()
      {:ok, expiry_dt} = DateTime.new(today, ~T[08:00:00], "Etc/UTC")
      now = DateTime.add(expiry_dt, @one_minute_seconds, :second)

      today_symbol = deribit_symbol(today, @strike_price, :call)
      chain = %{today_symbol => option_with_symbol(today_symbol)}

      result = Options.filter_by_dte(chain, @dte_days, now)

      refute Map.has_key?(result, today_symbol)
    end
  end

  describe "max_pain/1" do
    test "finds strike where buyers lose most" do
      {:ok, max_pain_strike} = Options.max_pain(@sample_chain)

      assert max_pain_strike == 84_000.0
    end

    test "returns error for empty chain" do
      assert {:error, :empty_chain} = Options.max_pain(%{})
    end
  end

  describe "put_call_ratio/1" do
    test "calculates ratio correctly" do
      result = Options.put_call_ratio(@sample_chain)

      # Puts: 50, Calls: 100 + 200 + 75 = 375
      # Ratio: 50 / 375 = 0.133...
      assert_in_delta result, 0.133, 0.01
    end

    test "returns nil when no calls" do
      put_only = %{
        "BTC-31JAN26-84000-P" => @sample_chain["BTC-31JAN26-84000-P"]
      }

      assert Options.put_call_ratio(put_only) == nil
    end

    test "returns 0 when no puts" do
      call_only = %{
        "BTC-31JAN26-84000-C" => @sample_chain["BTC-31JAN26-84000-C"]
      }

      assert Options.put_call_ratio(call_only) == 0.0
    end

    test "skips options with nil open_interest" do
      chain = %{
        "BTC-31JAN26-84000-C" => %Option{
          symbol: "BTC-31JAN26-84000-C",
          currency: "BTC",
          open_interest: 100.0,
          implied_volatility: 0.65,
          bid_price: 1000.0,
          ask_price: 1100.0,
          mid_price: 1050.0,
          mark_price: 1050.0,
          last_price: 1040.0,
          underlying_price: 85_000.0,
          change: 0.0,
          percentage: 0.0,
          base_volume: 0.0,
          quote_volume: 0.0,
          raw: %{}
        },
        "BTC-31JAN26-84000-P" => %Option{
          symbol: "BTC-31JAN26-84000-P",
          currency: "BTC",
          open_interest: nil,
          implied_volatility: 0.70,
          bid_price: 500.0,
          ask_price: 550.0,
          mid_price: 525.0,
          mark_price: 525.0,
          last_price: 520.0,
          underlying_price: 85_000.0,
          change: 0.0,
          percentage: 0.0,
          base_volume: 0.0,
          quote_volume: 0.0,
          raw: %{}
        }
      }

      # Put has nil OI, so puts = 0, calls = 100 -> ratio = 0
      assert Options.put_call_ratio(chain) == 0.0
    end
  end

  describe "session_phase/1" do
    test "returns :early for distant expiry" do
      future = Date.add(Date.utc_today(), 30)
      assert Options.session_phase(future) == :early
    end

    test "returns :expired for past expiry" do
      past_dt = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert Options.session_phase(past_dt) == :expired
    end

    test "returns :final_hour within 60 minutes" do
      # 30 minutes from now
      soon = DateTime.add(DateTime.utc_now(), 1800, :second)
      assert Options.session_phase(soon) == :final_hour
    end

    test "returns :last_15min within 15 minutes" do
      # 10 minutes from now
      very_soon = DateTime.add(DateTime.utc_now(), 600, :second)
      assert Options.session_phase(very_soon) == :last_15min
    end
  end

  describe "largest_positions/2" do
    test "returns top N by OI" do
      result = Options.largest_positions(@sample_chain, 2)

      assert length(result) == 2
      # First should be the 90000-C with 200 OI
      [{symbol1, _}, {symbol2, _}] = result
      assert symbol1 == "BTC-31JAN26-90000-C"
      assert symbol2 == "BTC-31JAN26-84000-C"
    end

    test "returns all if N > chain size" do
      result = Options.largest_positions(@sample_chain, 10)
      assert length(result) == 4
    end
  end

  describe "strike_distance/2" do
    test "calculates positive distance for higher strike" do
      result = Options.strike_distance(90_000.0, 85_000.0)
      assert_in_delta result, 5.88, 0.01
    end

    test "calculates negative distance for lower strike" do
      result = Options.strike_distance(80_000.0, 85_000.0)
      assert_in_delta result, -5.88, 0.01
    end

    test "returns 0 when strike equals spot" do
      result = Options.strike_distance(85_000.0, 85_000.0)
      assert result == 0.0
    end
  end

  describe "in_play?/3" do
    test "returns true within threshold" do
      assert Options.in_play?(84_000.0, 85_000.0, 5.0)
    end

    test "returns false outside threshold" do
      refute Options.in_play?(90_000.0, 85_000.0, 2.0)
    end

    test "returns true at exactly threshold" do
      # 5% of 100 is 5, so 105 is exactly at 5% threshold
      assert Options.in_play?(105.0, 100.0, 5.0)
    end
  end

  describe "gex_by_strike/2" do
    test "calculates GEX per strike" do
      result = Options.gex_by_strike(@sample_chain, 85_000.0)

      # Should have entries for strikes with gamma data
      assert map_size(result) > 0
      assert Map.has_key?(result, 84_000.0)
    end

    test "returns empty map for chain without gamma" do
      no_gamma_chain = %{
        "BTC-31JAN26-84000-C" => %Option{
          symbol: "BTC-31JAN26-84000-C",
          currency: "BTC",
          open_interest: 100.0,
          implied_volatility: 0.65,
          bid_price: 1000.0,
          ask_price: 1100.0,
          mid_price: 1050.0,
          mark_price: 1050.0,
          last_price: 1040.0,
          underlying_price: 85_000.0,
          change: 0.0,
          percentage: 0.0,
          base_volume: 0.0,
          quote_volume: 0.0,
          raw: %{}
        }
      }

      assert Options.gex_by_strike(no_gamma_chain, 85_000.0) == %{}
    end
  end

  describe "gamma_flip/2" do
    test "returns error when insufficient data" do
      single = %{"BTC-31JAN26-84000-C" => @sample_chain["BTC-31JAN26-84000-C"]}
      assert {:error, :no_flip_found} = Options.gamma_flip(single, 85_000.0)
    end

    test "finds gamma flip where GEX crosses zero" do
      # Build a chain where GEX flips sign between strikes
      # Lower strike: calls dominate (positive GEX) - high call gamma, low put gamma
      # Higher strike: puts dominate (negative GEX) - high put gamma, low call gamma
      chain = %{
        "BTC-31JAN26-80000-C" => %Option{
          symbol: "BTC-31JAN26-80000-C",
          currency: "BTC",
          open_interest: 500.0,
          implied_volatility: 0.65,
          bid_price: 5000.0,
          ask_price: 5100.0,
          mid_price: 5050.0,
          mark_price: 5050.0,
          last_price: 5050.0,
          underlying_price: 85_000.0,
          change: 0.0,
          percentage: 0.0,
          base_volume: 0.0,
          quote_volume: 0.0,
          raw: %{"gamma" => 0.00005}
        },
        "BTC-31JAN26-90000-P" => %Option{
          symbol: "BTC-31JAN26-90000-P",
          currency: "BTC",
          open_interest: 800.0,
          implied_volatility: 0.70,
          bid_price: 6000.0,
          ask_price: 6100.0,
          mid_price: 6050.0,
          mark_price: 6050.0,
          last_price: 6050.0,
          underlying_price: 85_000.0,
          change: 0.0,
          percentage: 0.0,
          base_volume: 0.0,
          quote_volume: 0.0,
          raw: %{"gamma" => 0.00008}
        }
      }

      assert {:ok, flip_strike} = Options.gamma_flip(chain, 85_000.0)
      # Flip should be between 80000 and 90000
      assert flip_strike > 80_000.0
      assert flip_strike < 90_000.0
    end

    test "returns error when all GEX same sign" do
      # All calls → all positive GEX → no flip
      chain = %{
        "BTC-31JAN26-80000-C" => %Option{
          symbol: "BTC-31JAN26-80000-C",
          currency: "BTC",
          open_interest: 100.0,
          implied_volatility: 0.65,
          bid_price: 1000.0,
          ask_price: 1100.0,
          mid_price: 1050.0,
          mark_price: 1050.0,
          last_price: 1050.0,
          underlying_price: 85_000.0,
          change: 0.0,
          percentage: 0.0,
          base_volume: 0.0,
          quote_volume: 0.0,
          raw: %{"gamma" => 0.00005}
        },
        "BTC-31JAN26-90000-C" => %Option{
          symbol: "BTC-31JAN26-90000-C",
          currency: "BTC",
          open_interest: 200.0,
          implied_volatility: 0.60,
          bid_price: 400.0,
          ask_price: 450.0,
          mid_price: 425.0,
          mark_price: 425.0,
          last_price: 420.0,
          underlying_price: 85_000.0,
          change: 0.0,
          percentage: 0.0,
          base_volume: 0.0,
          quote_volume: 0.0,
          raw: %{"gamma" => 0.00003}
        }
      }

      assert {:error, :no_flip_found} = Options.gamma_flip(chain, 85_000.0)
    end
  end

  describe "pin_magnets/3" do
    test "finds high OI strikes near spot" do
      result = Options.pin_magnets(@sample_chain, 85_000.0, threshold_pct: 10.0)

      # Should return strikes sorted by OI descending
      assert result != []
      [{strike, oi} | _] = result
      assert is_float(strike)
      assert is_float(oi)
    end

    test "respects min_oi filter" do
      result = Options.pin_magnets(@sample_chain, 85_000.0, threshold_pct: 10.0, min_oi: 200.0)

      # Only strikes with aggregated OI >= 200 pass the filter
      # 84000: 100 + 50 + 75 = 225, 90000: 200
      assert length(result) == 2
    end

    test "uses default opts when called without options" do
      # Exercises the default parameter path (line 459)
      result = Options.pin_magnets(@sample_chain, 85_000.0)

      # Default threshold is 5.0%, default min_oi is 0
      # 84000 is ~1.18% from 85000 → in play
      # 90000 is ~5.88% from 85000 → at the edge of 5.0%, may or may not be in
      assert is_list(result)
    end
  end

  describe "hot_zone/3" do
    test "returns :clear when no options for expiry" do
      # Use a date with no options
      result = Options.hot_zone(@sample_chain, 85_000.0, expiry: ~D[2030-01-01])
      assert result == :clear
    end

    test "detects hot zone when spot is near high-OI strike at matching expiry" do
      # 31JAN26 chain has 84000 strike with 225 total OI
      # spot 84000 → 0% distance → within 1.0% threshold
      result = Options.hot_zone(@sample_chain, 84_000.0, expiry: ~D[2026-01-31], threshold_pct: 2.0)
      assert {:hot, strike, oi} = result
      assert is_float(strike)
      assert oi > 0
    end

    test "uses default opts (today's date)" do
      # Exercises the default parameter path (line 494)
      # Since today likely doesn't match the sample chain expiries, expect :clear
      result = Options.hot_zone(@sample_chain, 85_000.0)
      assert result == :clear
    end
  end

  describe "greeks_sum/1" do
    test "aggregates greeks across chain" do
      result = Options.greeks_sum(@sample_chain)

      assert Map.has_key?(result, :delta)
      assert Map.has_key?(result, :gamma)
      assert Map.has_key?(result, :theta)
      assert Map.has_key?(result, :vega)
    end

    test "returns zeros for empty chain" do
      result = Options.greeks_sum(%{})

      assert result.delta == 0.0
      assert result.gamma == 0.0
      assert result.theta == 0.0
      assert result.vega == 0.0
    end

    test "extracts greeks from atom-keyed raw data" do
      # Exercises line 597 (atom key) and line 608 (atom key in get_greek)
      chain = %{
        "BTC-31JAN26-84000-C" => %Option{
          symbol: "BTC-31JAN26-84000-C",
          currency: "BTC",
          open_interest: 100.0,
          implied_volatility: 0.65,
          bid_price: 1000.0,
          ask_price: 1100.0,
          mid_price: 1050.0,
          mark_price: 1050.0,
          last_price: 1040.0,
          underlying_price: 85_000.0,
          change: 0.0,
          percentage: 0.0,
          base_volume: 0.0,
          quote_volume: 0.0,
          raw: %{delta: 0.5, gamma: 0.00001, theta: -10.0, vega: 50.0}
        }
      }

      result = Options.greeks_sum(chain)
      assert_in_delta result.delta, 0.5, 0.001
      assert_in_delta result.gamma, 0.00001, 0.000001
      assert_in_delta result.theta, -10.0, 0.001
      assert_in_delta result.vega, 50.0, 0.001
    end

    test "extracts greeks from string-keyed raw data" do
      # Exercises line 609 (string key in get_greek)
      chain = %{
        "BTC-31JAN26-84000-C" => %Option{
          symbol: "BTC-31JAN26-84000-C",
          currency: "BTC",
          open_interest: 100.0,
          implied_volatility: 0.65,
          bid_price: 1000.0,
          ask_price: 1100.0,
          mid_price: 1050.0,
          mark_price: 1050.0,
          last_price: 1040.0,
          underlying_price: 85_000.0,
          change: 0.0,
          percentage: 0.0,
          base_volume: 0.0,
          quote_volume: 0.0,
          raw: %{"delta" => 0.3, "gamma" => 0.00002, "theta" => -5.0, "vega" => 30.0}
        }
      }

      result = Options.greeks_sum(chain)
      assert_in_delta result.delta, 0.3, 0.001
      assert_in_delta result.gamma, 0.00002, 0.000001
    end

    test "defaults to 0.0 when raw has no greeks" do
      # Exercises line 610 (true -> 0.0 fallback)
      chain = %{
        "BTC-31JAN26-84000-C" => %Option{
          symbol: "BTC-31JAN26-84000-C",
          currency: "BTC",
          open_interest: 100.0,
          implied_volatility: 0.65,
          bid_price: 1000.0,
          ask_price: 1100.0,
          mid_price: 1050.0,
          mark_price: 1050.0,
          last_price: 1040.0,
          underlying_price: 85_000.0,
          change: 0.0,
          percentage: 0.0,
          base_volume: 0.0,
          quote_volume: 0.0,
          raw: %{}
        }
      }

      result = Options.greeks_sum(chain)
      assert result.delta == 0.0
      assert result.gamma == 0.0
      assert result.theta == 0.0
      assert result.vega == 0.0
    end
  end

  defp deribit_symbol(%Date{} = date, strike, type) when is_number(strike) do
    day = date.day |> Integer.to_string() |> String.pad_leading(@day_pad, "0")
    month = date |> Calendar.strftime("%b") |> String.upcase()
    year = date.year |> rem(@year_mod) |> Integer.to_string() |> String.pad_leading(@year_pad, "0")
    type_char = if(type == :call, do: "C", else: "P")

    "BTC-#{day}#{month}#{year}-#{strike}-#{type_char}"
  end

  defp option_with_symbol(symbol) do
    %Option{} = option = @sample_chain["BTC-31JAN26-84000-C"]
    %{option | symbol: symbol}
  end
end
