defmodule CCXT.Trading.TradingHelpers.OptionsIntegrationTest do
  @moduledoc """
  Integration tests for CCXT.Options module using real exchange data.

  Uses Deribit to fetch actual option chain data and verify
  the options analytics functions work with real data. Uses `normalize: false`
  to get raw option items (ResponseTransformer extracts the path automatically).
  """

  use ExUnit.Case, async: false

  alias CCXT.Trading.Options
  alias CCXT.Trading.Options.Deribit, as: DeribitParser
  alias CCXT.Types.Option

  @moduletag :integration
  @moduletag :trading_helpers

  setup do
    # Deribit public endpoint - no credentials needed for option chain
    {:ok, exchange: CCXT.Deribit}
  end

  # Helper to build option chain map from response
  # ResponseTransformer extracts the path (e.g. ["result"]) automatically,
  # so with normalize: false the response IS the list of option items.
  defp extract_option_chain(response) when is_list(response) do
    Map.new(response, fn item ->
      symbol = item["instrument_name"]

      option = %Option{
        symbol: symbol,
        open_interest: item["open_interest"],
        bid_price: item["bid_price"],
        ask_price: item["ask_price"],
        last_price: item["last"],
        mark_price: item["mark_price"],
        underlying_price: item["underlying_price"],
        raw: item
      }

      {symbol, option}
    end)
  end

  defp extract_option_chain(_), do: %{}

  describe "with real Deribit option chain" do
    @tag timeout: 60_000
    test "oi_by_strike/1 aggregates open interest by strike", %{exchange: exchange} do
      case exchange.fetch_option_chain("BTC", normalize: false) do
        {:ok, raw_response} ->
          chain = extract_option_chain(raw_response)

          assert map_size(chain) > 0, "Expected option chain but got empty response"

          oi_by_strike = Options.oi_by_strike(chain)

          assert is_map(oi_by_strike)
          assert map_size(oi_by_strike) > 0

          # Each strike should have positive OI (floats)
          Enum.each(oi_by_strike, fn {strike, oi} ->
            assert is_number(strike)
            assert is_number(oi)
            assert oi >= 0
          end)

        {:error, reason} ->
          flunk("Failed to fetch option chain: #{inspect(reason)}")
      end
    end

    @tag timeout: 60_000
    test "put_call_ratio/1 calculates ratio from real data", %{exchange: exchange} do
      case exchange.fetch_option_chain("BTC", normalize: false) do
        {:ok, raw_response} ->
          chain = extract_option_chain(raw_response)

          assert map_size(chain) > 0, "Expected option chain but got empty response"

          ratio = Options.put_call_ratio(chain)

          # For real BTC option chain, ratio should always be calculable
          assert ratio, "put_call_ratio returned nil for non-empty chain"
          assert is_float(ratio)
          # Ratio should be positive
          assert ratio >= 0
          # Extreme ratios are unlikely in active markets
          assert ratio < 100

        {:error, reason} ->
          flunk("Failed to fetch option chain: #{inspect(reason)}")
      end
    end

    @tag timeout: 60_000
    test "max_pain/1 finds the max pain strike", %{exchange: exchange} do
      case exchange.fetch_option_chain("BTC", normalize: false) do
        {:ok, raw_response} ->
          chain = extract_option_chain(raw_response)

          assert map_size(chain) > 0, "Expected option chain but got empty response"

          case Options.max_pain(chain) do
            {:ok, max_pain_strike} ->
              assert is_number(max_pain_strike)
              # Max pain should be a reasonable strike (positive)
              assert max_pain_strike > 0

            {:error, :empty_chain} ->
              flunk("max_pain returned :empty_chain for non-empty option chain")
          end

        {:error, reason} ->
          flunk("Failed to fetch option chain: #{inspect(reason)}")
      end
    end

    @tag timeout: 60_000
    test "DeribitParser.parse_option/1 parses real symbols", %{exchange: exchange} do
      case exchange.fetch_option_chain("BTC", normalize: false) do
        {:ok, raw_response} ->
          chain = extract_option_chain(raw_response)

          assert map_size(chain) > 0, "Expected option chain but got empty response"

          # Get first few symbols and verify parsing
          symbols = chain |> Map.keys() |> Enum.take(5)

          # Track how many parsed successfully - at least some should parse
          parsed_count =
            Enum.count(symbols, fn symbol ->
              case DeribitParser.parse_option(symbol) do
                {:ok, parsed} ->
                  assert is_binary(parsed.underlying)
                  assert %Date{} = parsed.expiry
                  assert is_number(parsed.strike)
                  assert parsed.type in [:call, :put]
                  true

                {:error, :invalid_format} ->
                  # Some symbols might not match option format (perps, futures)
                  false
              end
            end)

          assert parsed_count > 0, "Expected at least one symbol to parse successfully"

        {:error, reason} ->
          flunk("Failed to fetch option chain: #{inspect(reason)}")
      end
    end

    @tag timeout: 60_000
    test "oi_by_expiry/1 aggregates by expiry date", %{exchange: exchange} do
      case exchange.fetch_option_chain("BTC", normalize: false) do
        {:ok, raw_response} ->
          chain = extract_option_chain(raw_response)

          assert map_size(chain) > 0, "Expected option chain but got empty response"

          oi_by_expiry = Options.oi_by_expiry(chain)

          assert is_map(oi_by_expiry)

          # Each expiry should be a Date with positive OI
          Enum.each(oi_by_expiry, fn {expiry, oi} ->
            assert %Date{} = expiry
            assert is_number(oi)
            assert oi >= 0
          end)

        {:error, reason} ->
          flunk("Failed to fetch option chain: #{inspect(reason)}")
      end
    end

    @tag timeout: 60_000
    test "largest_positions/2 returns top N positions", %{exchange: exchange} do
      case exchange.fetch_option_chain("BTC", normalize: false) do
        {:ok, raw_response} ->
          chain = extract_option_chain(raw_response)

          assert map_size(chain) > 0, "Expected option chain but got empty response"

          top_5 = Options.largest_positions(chain, 5)

          assert is_list(top_5)
          assert length(top_5) <= 5

          # Verify sorted by OI descending
          ois = Enum.map(top_5, fn {_symbol, option} -> option.open_interest end)
          assert ois == Enum.sort(ois, :desc)

        {:error, reason} ->
          flunk("Failed to fetch option chain: #{inspect(reason)}")
      end
    end

    @tag timeout: 60_000
    test "Option struct fields are populated from real data", %{exchange: exchange} do
      case exchange.fetch_option_chain("BTC", normalize: false) do
        {:ok, raw_response} ->
          chain = extract_option_chain(raw_response)

          assert map_size(chain) > 0, "Expected option chain but got empty response"

          # Get first option and verify struct
          {symbol, option} = Enum.at(chain, 0)

          # Required fields
          assert is_binary(option.symbol)
          assert option.symbol == symbol

          # Open interest should be present
          assert is_number(option.open_interest)

          # Raw data for greeks access
          assert is_map(option.raw)

        {:error, reason} ->
          flunk("Failed to fetch option chain: #{inspect(reason)}")
      end
    end
  end
end
