defmodule CCXT.Trading.Options do
  @moduledoc """
  Options analytics and aggregation functions.

  Pure functions for analyzing option chains, calculating open interest
  distributions, and identifying key market levels. Works with
  `CCXT.Types.Option` and `CCXT.Types.OptionChain` types.

  All functions that need strike/expiry data parse it from symbols using
  `CCXT.Trading.Options.Deribit.parse_option/1`.

  ## Example

      chain = %{
        "BTC-31JAN26-84000-C" => %CCXT.Types.Option{open_interest: 100.0, ...},
        "BTC-31JAN26-84000-P" => %CCXT.Types.Option{open_interest: 50.0, ...}
      }

      CCXT.Trading.Options.oi_by_strike(chain)
      # => %{84000.0 => 150.0}

      CCXT.Trading.Options.put_call_ratio(chain)
      # => 0.5

  """

  alias CCXT.Trading.Options.Deribit
  alias CCXT.Types.Option

  @type option_chain :: %{optional(String.t()) => Option.t()}
  @type strike :: float()
  @type expiry :: Date.t()

  # Session phases based on Deribit 08:00 UTC expiry
  @final_hour_minutes 60
  @last_15min_minutes 15

  @doc """
  Aggregate open interest by strike price.

  Sums OI from both calls and puts at each strike.

  ## Example

      CCXT.Trading.Options.oi_by_strike(chain)
      # => %{84000.0 => 150.0, 90000.0 => 200.0}

  """
  @spec oi_by_strike(option_chain()) :: %{strike() => float()}
  def oi_by_strike(chain) when is_map(chain) do
    Enum.reduce(chain, %{}, fn {symbol, option}, acc ->
      accumulate_oi_by_strike(acc, symbol, option)
    end)
  end

  @doc false
  # Accumulates OI by strike, skipping invalid symbols or nil OI
  defp accumulate_oi_by_strike(acc, symbol, option) do
    with {:ok, %{strike: strike}} <- Deribit.parse_option(symbol),
         oi when is_number(oi) <- option.open_interest do
      Map.update(acc, strike, oi, &(&1 + oi))
    else
      _ -> acc
    end
  end

  @doc """
  Aggregate open interest by expiry date.

  Sums OI from all options at each expiry.

  ## Example

      CCXT.Trading.Options.oi_by_expiry(chain)
      # => %{~D[2026-01-31] => 350.0, ~D[2026-02-28] => 200.0}

  """
  @spec oi_by_expiry(option_chain()) :: %{expiry() => float()}
  def oi_by_expiry(chain) when is_map(chain) do
    Enum.reduce(chain, %{}, fn {symbol, option}, acc ->
      accumulate_oi_by_expiry(acc, symbol, option)
    end)
  end

  @doc false
  # Accumulates OI by expiry, skipping invalid symbols or nil OI
  defp accumulate_oi_by_expiry(acc, symbol, option) do
    with {:ok, %{expiry: expiry}} <- Deribit.parse_option(symbol),
         oi when is_number(oi) <- option.open_interest do
      Map.update(acc, expiry, oi, &(&1 + oi))
    else
      _ -> acc
    end
  end

  @doc """
  Calculate time remaining until expiry.

  Returns a map with hours and minutes remaining.

  ## Parameters

    * `expiry` - Expiry date or DateTime (assumes 08:00 UTC for Date)

  ## Example

      CCXT.Trading.Options.time_to_expiry(~D[2026-01-31])
      # => %{hours: 48.5, minutes: 2910.0}

  """
  @spec time_to_expiry(Date.t() | DateTime.t()) :: %{hours: float(), minutes: float()}
  def time_to_expiry(%Date{} = expiry) do
    # Deribit options expire at 08:00 UTC
    {:ok, expiry_dt} = DateTime.new(expiry, ~T[08:00:00], "Etc/UTC")
    time_to_expiry(expiry_dt)
  end

  def time_to_expiry(%DateTime{} = expiry_dt) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(expiry_dt, now, :second)
    diff_minutes = diff_seconds / 60.0
    diff_hours = diff_minutes / 60.0

    %{
      hours: max(0.0, diff_hours),
      minutes: max(0.0, diff_minutes)
    }
  end

  @doc """
  Filter option chain by maximum days to expiry (DTE).

  Returns only options expiring within the specified number of days.
  Excludes options that have already expired.

  ## Parameters

    * `chain` - Option chain map
    * `max_dte` - Maximum days to expiry
    * `now_dt` - Optional current time (for testing)

  ## Example

      CCXT.Trading.Options.filter_by_dte(chain, 7)
      # => filtered chain with only options expiring within 7 days

  """
  @spec filter_by_dte(option_chain(), pos_integer()) :: option_chain()
  @spec filter_by_dte(option_chain(), pos_integer(), DateTime.t()) :: option_chain()
  def filter_by_dte(chain, max_dte, now_dt \\ DateTime.utc_now())

  def filter_by_dte(chain, max_dte, %DateTime{} = now_dt) when is_map(chain) and is_integer(max_dte) and max_dte > 0 do
    today = DateTime.to_date(now_dt)
    max_expiry = Date.add(today, max_dte)
    {:ok, max_expiry_dt} = DateTime.new(max_expiry, ~T[08:00:00], "Etc/UTC")

    chain
    |> Enum.filter(fn {symbol, _option} ->
      case Deribit.parse_option(symbol) do
        {:ok, %{expiry: expiry}} ->
          {:ok, expiry_dt} = DateTime.new(expiry, ~T[08:00:00], "Etc/UTC")

          DateTime.compare(expiry_dt, now_dt) in [:gt, :eq] and
            DateTime.compare(expiry_dt, max_expiry_dt) in [:lt, :eq]

        {:error, _} ->
          false
      end
    end)
    |> Map.new()
  end

  @doc """
  Calculate max pain strike - where most options expire worthless.

  Max pain is the strike price at which option buyers would lose
  the most money (and sellers gain the most). The algorithm tests
  each strike as a potential settlement price and finds the one
  that minimizes total intrinsic value (maximum pain for buyers).

  ## Parameters

    * `chain` - Option chain map

  ## Example

      CCXT.Trading.Options.max_pain(chain)
      # => {:ok, 84000.0}

  """
  @spec max_pain(option_chain()) :: {:ok, strike()} | {:error, :empty_chain}
  def max_pain(chain) when map_size(chain) == 0, do: {:error, :empty_chain}

  def max_pain(chain) when is_map(chain) do
    by_strike = group_by_strike(chain)
    strikes = by_strike |> Map.keys() |> Enum.sort()

    if Enum.empty?(strikes) do
      {:error, :empty_chain}
    else
      min_pain_strike = find_min_pain_strike(strikes, by_strike)
      {:ok, min_pain_strike}
    end
  end

  @doc false
  defp find_min_pain_strike(strikes, by_strike) do
    {min_pain_strike, _min_pain} =
      strikes
      |> Enum.map(fn settlement_price ->
        pain = calculate_total_pain(by_strike, settlement_price)
        {settlement_price, pain}
      end)
      |> Enum.min_by(fn {_strike, pain} -> pain end)

    min_pain_strike
  end

  @doc """
  Calculate put/call ratio from open interest.

  ## Example

      CCXT.Trading.Options.put_call_ratio(chain)
      # => 0.8  (more calls than puts)

  """
  @spec put_call_ratio(option_chain()) :: float() | nil
  def put_call_ratio(chain) when is_map(chain) do
    {puts, calls} =
      Enum.reduce(chain, {0.0, 0.0}, fn {symbol, option}, acc ->
        accumulate_put_call_oi(acc, symbol, option)
      end)

    if calls > 0 do
      puts / calls
    end
  end

  @doc false
  # Accumulates OI into put/call totals, skipping invalid symbols or nil OI
  defp accumulate_put_call_oi({put_oi, call_oi}, symbol, option) do
    with {:ok, %{type: type}} <- Deribit.parse_option(symbol),
         oi when is_number(oi) <- option.open_interest do
      case type do
        :put -> {put_oi + oi, call_oi}
        :call -> {put_oi, call_oi + oi}
      end
    else
      _ -> {put_oi, call_oi}
    end
  end

  @doc """
  Determine trading session phase based on time to expiry.

  Phases for expiry day:
    * `:early` - More than 1 hour to expiry
    * `:final_hour` - 15-60 minutes to expiry
    * `:last_15min` - Less than 15 minutes to expiry
    * `:expired` - Past expiry time

  For non-expiry days, returns `:early`.

  ## Example

      CCXT.Trading.Options.session_phase(~D[2026-01-31])
      # => :early

  """
  @spec session_phase(Date.t() | DateTime.t()) :: :early | :final_hour | :last_15min | :expired
  def session_phase(%Date{} = expiry) do
    {:ok, expiry_dt} = DateTime.new(expiry, ~T[08:00:00], "Etc/UTC")
    session_phase(expiry_dt)
  end

  def session_phase(%DateTime{} = expiry_dt) do
    now = DateTime.utc_now()
    diff_minutes = DateTime.diff(expiry_dt, now, :second) / 60.0

    cond do
      diff_minutes < 0 -> :expired
      diff_minutes < @last_15min_minutes -> :last_15min
      diff_minutes < @final_hour_minutes -> :final_hour
      true -> :early
    end
  end

  @doc """
  Get the N largest positions by open interest.

  ## Example

      CCXT.Trading.Options.largest_positions(chain, 5)
      # => [{"BTC-31JAN26-84000-C", %Option{...}}, ...]

  """
  @spec largest_positions(option_chain(), pos_integer()) :: [{String.t(), Option.t()}]
  def largest_positions(chain, n) when is_map(chain) and is_integer(n) and n > 0 do
    chain
    |> Enum.sort_by(fn {_symbol, option} -> option.open_interest end, :desc)
    |> Enum.take(n)
  end

  @doc """
  Calculate distance from spot to strike as percentage.

  Positive = OTM for calls, ITM for puts
  Negative = ITM for calls, OTM for puts

  ## Example

      CCXT.Trading.Options.strike_distance(90000.0, 85000.0)
      # => 5.88  (strike is 5.88% above spot)

  """
  @spec strike_distance(strike(), number()) :: float()
  def strike_distance(strike, spot) when is_number(strike) and is_number(spot) and spot > 0 do
    (strike - spot) / spot * 100.0
  end

  @doc """
  Check if a strike is "in play" (within threshold of spot).

  ## Example

      CCXT.Trading.Options.in_play?(84000.0, 85000.0, 5.0)
      # => true  (within 5% of spot)

  """
  @spec in_play?(strike(), number(), number()) :: boolean()
  def in_play?(strike, spot, threshold_pct) when is_number(strike) and is_number(spot) and is_number(threshold_pct) do
    abs(strike_distance(strike, spot)) <= threshold_pct
  end

  @doc """
  Calculate gamma exposure (GEX) by strike.

  GEX indicates dealer hedging pressure. Positive GEX means dealers
  are long gamma (will buy dips, sell rips). Negative GEX means
  dealers are short gamma (will amplify moves).

  ## Parameters

    * `chain` - Option chain with greeks (needs gamma field in raw data)
    * `spot` - Current spot price

  ## Example

      CCXT.Trading.Options.gex_by_strike(chain, 85000.0)
      # => %{84000.0 => 1500000.0, 90000.0 => -500000.0}

  """
  @spec gex_by_strike(option_chain(), number()) :: %{strike() => float()}
  def gex_by_strike(chain, spot) when is_map(chain) and is_number(spot) do
    # GEX = Gamma * OI * Spot^2 * Contract_Multiplier * 0.01
    # For calls: dealers are short, so positive gamma = positive GEX
    # For puts: dealers are long, so positive gamma = negative GEX
    Enum.reduce(chain, %{}, fn {symbol, option}, acc ->
      accumulate_gex(acc, symbol, option, spot)
    end)
  end

  @doc false
  defp accumulate_gex(acc, symbol, option, spot) do
    contract_multiplier = 1.0

    with {:ok, parsed} <- Deribit.parse_option(symbol),
         gamma when is_number(gamma) <- get_gamma(option) do
      # Assumes dealer is short calls, long puts (standard market making)
      sign = type_sign(parsed.type)
      gex = sign * gamma * option.open_interest * spot * spot * contract_multiplier * 0.01
      Map.update(acc, parsed.strike, gex, &(&1 + gex))
    else
      _ -> acc
    end
  end

  @doc false
  defp type_sign(:call), do: 1.0
  defp type_sign(:put), do: -1.0

  @doc """
  Find gamma flip level - where GEX crosses zero.

  Above the gamma flip, dealers are long gamma (stabilizing).
  Below the gamma flip, dealers are short gamma (destabilizing).

  ## Example

      CCXT.Trading.Options.gamma_flip(chain, 85000.0)
      # => {:ok, 84500.0}

  """
  @spec gamma_flip(option_chain(), number()) :: {:ok, strike()} | {:error, :no_flip_found}
  def gamma_flip(chain, spot) when is_map(chain) and is_number(spot) do
    gex = gex_by_strike(chain, spot)

    if map_size(gex) < 2 do
      {:error, :no_flip_found}
    else
      strikes = gex |> Map.keys() |> Enum.sort()

      # Find where GEX changes sign
      flip =
        strikes
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.find(fn [s1, s2] ->
          g1 = Map.get(gex, s1, 0)
          g2 = Map.get(gex, s2, 0)
          g1 * g2 < 0
        end)

      case flip do
        [s1, s2] ->
          # Linear interpolation to find zero crossing
          g1 = Map.get(gex, s1)
          g2 = Map.get(gex, s2)
          flip_strike = s1 + (s2 - s1) * abs(g1) / (abs(g1) + abs(g2))
          {:ok, flip_strike}

        nil ->
          {:error, :no_flip_found}
      end
    end
  end

  @doc """
  Find high-gamma strikes near spot (pin magnets).

  These are strikes where dealers have significant gamma exposure,
  creating "magnetic" effects that can pin price.

  ## Parameters

    * `chain` - Option chain
    * `spot` - Current spot price
    * `opts` - Options:
      * `:threshold_pct` - Max distance from spot (default: 5.0)
      * `:min_oi` - Minimum OI to consider (default: 0)

  ## Example

      CCXT.Trading.Options.pin_magnets(chain, 85000.0)
      # => [{84000.0, 150.0}, {86000.0, 120.0}]

  """
  @spec pin_magnets(option_chain(), number(), keyword()) :: [{strike(), float()}]
  def pin_magnets(chain, spot, opts \\ []) when is_map(chain) and is_number(spot) do
    threshold_pct = Keyword.get(opts, :threshold_pct, 5.0)
    min_oi = Keyword.get(opts, :min_oi, 0)

    oi = oi_by_strike(chain)

    oi
    |> Enum.filter(fn {strike, strike_oi} ->
      in_play?(strike, spot, threshold_pct) and strike_oi >= min_oi
    end)
    |> Enum.sort_by(fn {_strike, strike_oi} -> strike_oi end, :desc)
  end

  @doc """
  Detect hot zone / pin risk at expiry.

  When price is near a high-OI strike on expiry day, there's
  significant pin risk as dealers hedge.

  ## Parameters

    * `chain` - Option chain
    * `spot` - Current spot price
    * `opts` - Options:
      * `:expiry` - Expiry date to check (default: today)
      * `:threshold_pct` - Max distance for "hot" (default: 1.0)

  ## Example

      CCXT.Trading.Options.hot_zone(chain, 85000.0)
      # => {:hot, 84000.0, 150.0}  or  :clear

  """
  @spec hot_zone(option_chain(), number(), keyword()) ::
          {:hot, strike(), float()} | :clear
  def hot_zone(chain, spot, opts \\ []) when is_map(chain) and is_number(spot) do
    expiry = Keyword.get(opts, :expiry, Date.utc_today())
    threshold_pct = Keyword.get(opts, :threshold_pct, 1.0)

    # Filter to expiry date
    expiry_chain = filter_by_expiry(chain, expiry)

    if map_size(expiry_chain) == 0 do
      :clear
    else
      oi = oi_by_strike(expiry_chain)

      # Find highest OI strike in play
      hot_strike =
        oi
        |> Enum.filter(fn {strike, _} -> in_play?(strike, spot, threshold_pct) end)
        |> Enum.max_by(fn {_, strike_oi} -> strike_oi end, fn -> nil end)

      case hot_strike do
        {strike, strike_oi} when strike_oi > 0 -> {:hot, strike, strike_oi}
        _ -> :clear
      end
    end
  end

  @doc """
  Sum Greeks across all positions (alias for portfolio aggregation).

  Returns aggregate delta, gamma, theta, vega from the chain.

  ## Example

      CCXT.Trading.Options.greeks_sum(chain)
      # => %{delta: 0.5, gamma: 0.01, theta: -100.0, vega: 500.0}

  """
  @spec greeks_sum(option_chain()) :: %{delta: float(), gamma: float(), theta: float(), vega: float()}
  def greeks_sum(chain) when is_map(chain) do
    chain
    |> Map.values()
    |> Enum.reduce(%{delta: 0.0, gamma: 0.0, theta: 0.0, vega: 0.0}, fn option, acc ->
      %{
        delta: acc.delta + get_greek(option, :delta),
        gamma: acc.gamma + get_greek(option, :gamma),
        theta: acc.theta + get_greek(option, :theta),
        vega: acc.vega + get_greek(option, :vega)
      }
    end)
  end

  # Helper: Group options by strike with their parsed data
  @doc false
  defp group_by_strike(chain) do
    Enum.reduce(chain, %{}, fn {symbol, option}, acc ->
      case Deribit.parse_option(symbol) do
        {:ok, parsed} ->
          entry = %{option: option, type: parsed.type, strike: parsed.strike}
          Map.update(acc, parsed.strike, [entry], &[entry | &1])

        {:error, _} ->
          acc
      end
    end)
  end

  # Helper: Calculate total pain for a given settlement price
  @doc false
  defp calculate_total_pain(by_strike, settlement_price) do
    Enum.reduce(by_strike, 0.0, fn {strike, options}, total ->
      total + calculate_strike_pain(options, strike, settlement_price)
    end)
  end

  @doc false
  defp calculate_strike_pain(options, strike, settlement_price) do
    Enum.reduce(options, 0.0, fn %{option: opt, type: type}, acc ->
      intrinsic = option_intrinsic(type, strike, settlement_price)
      acc + intrinsic * opt.open_interest
    end)
  end

  @doc false
  defp option_intrinsic(:call, strike, settlement), do: max(0, settlement - strike)
  defp option_intrinsic(:put, strike, settlement), do: max(0, strike - settlement)

  # Helper: Filter chain to specific expiry
  @doc false
  defp filter_by_expiry(chain, expiry) do
    chain
    |> Enum.filter(fn {symbol, _option} ->
      case Deribit.parse_option(symbol) do
        {:ok, %{expiry: ^expiry}} -> true
        _ -> false
      end
    end)
    |> Map.new()
  end

  # Helper: Extract gamma from option (may be in raw data)
  @doc false
  defp get_gamma(%Option{} = option) do
    case option.raw do
      %{"gamma" => gamma} when is_number(gamma) -> gamma
      %{gamma: gamma} when is_number(gamma) -> gamma
      _ -> nil
    end
  end

  # Helper: Extract a greek value from option
  @doc false
  defp get_greek(%Option{} = option, greek) do
    raw = option.raw

    cond do
      is_map(raw) and is_number(raw[greek]) -> raw[greek]
      is_map(raw) and is_number(raw[Atom.to_string(greek)]) -> raw[Atom.to_string(greek)]
      true -> 0.0
    end
  end
end
