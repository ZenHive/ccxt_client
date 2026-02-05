defmodule CCXT.Test.WSSmokeTestGenerator do
  @moduledoc """
  Macro that generates smoke tests for all WS modules at compile time.

  This dynamically discovers which exchanges have WS modules and creates
  appropriate tests for each.

  ## Usage

      defmodule CCXT.WS.SmokeTest do
        use CCXT.Test.WSSmokeTestGenerator
      end

  This generates:
  - Tests for each exchange's WS module (introspection, pattern, channels)
  - Tests for watch_*_subscription functions returning correct structure
  - Module tags: `:ws_smoke`, `:exchange_{id}`, tier tag

  ## Generated Tags

  Each generated test receives hierarchical tags:

  | Tag | Description |
  |-----|-------------|
  | `@moduletag :ws_smoke` | All tests are WS smoke tests |
  | `@tag :exchange_{id}` | Exchange-specific tag |
  | `@tag :tier1` / `:tier2` / `:tier3` / `:dex` / `:unclassified` | Priority tier |

  ## Filtering Examples

      # Run WS smoke tests for all exchanges
      mix test --only ws_smoke

      # Run WS smoke tests for Tier 1 exchanges only
      mix test --only ws_smoke --only tier1

      # Run WS smoke tests excluding low-priority exchanges
      mix test --only ws_smoke --exclude tier3
  """

  alias CCXT.Exchange.Classification
  alias CCXT.WS.Subscription

  # Valid subscription patterns from the Subscription module
  @valid_patterns Subscription.patterns()

  @doc """
  Generates WS smoke tests for all installed exchange modules.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(_opts) do
    installed_ws_modules = get_installed_ws_modules()

    tests =
      for {exchange_id, ws_module, base_module} <- installed_ws_modules do
        generate_exchange_ws_tests(exchange_id, ws_module, base_module)
      end

    quote do
      use ExUnit.Case, async: true

      require Logger

      @moduletag :ws_smoke

      @valid_patterns unquote(@valid_patterns)

      unquote_splicing(tests)

      unquote(generate_distribution_report(installed_ws_modules))
    end
  end

  @doc false
  # Gets list of installed exchanges with WS modules at compile time
  defp get_installed_ws_modules do
    Classification.all_exchanges()
    |> Enum.reject(&(&1 == "test_exchange"))
    |> Enum.map(fn exchange_id ->
      module_name = Macro.camelize(exchange_id)
      base_module = Module.concat([CCXT, module_name])
      ws_module = Module.concat([CCXT, module_name, WS])
      {exchange_id, ws_module, base_module}
    end)
    |> Enum.filter(fn {_exchange_id, ws_module, _base_module} ->
      Code.ensure_loaded?(ws_module)
    end)
  end

  @doc false
  # Generate WS tests for a single exchange
  defp generate_exchange_ws_tests(exchange_id, ws_module, base_module) do
    tier_tag = Classification.get_priority_tier(exchange_id)
    # Safe: exchange_id comes from trusted Classification module
    exchange_tag = String.to_atom("exchange_#{exchange_id}")

    introspection_tests = generate_introspection_tests(exchange_id, ws_module)
    subscription_tests = generate_subscription_tests(exchange_id, ws_module)
    base_module_tests = generate_base_module_tests(exchange_id, base_module)

    quote do
      describe unquote("#{exchange_id} WS") do
        @tag unquote(exchange_tag)
        @tag unquote(tier_tag)

        unquote(introspection_tests)
        unquote(subscription_tests)
        unquote(base_module_tests)
      end
    end
  end

  @doc false
  # Generate introspection tests (spec, pattern, channels)
  defp generate_introspection_tests(exchange_id, ws_module) do
    quote do
      test "WS module compiles and loads" do
        assert Code.ensure_loaded?(unquote(ws_module)),
               "Module #{inspect(unquote(ws_module))} should be loaded"
      end

      test "exports __ccxt_ws_spec__/0" do
        assert function_exported?(unquote(ws_module), :__ccxt_ws_spec__, 0),
               "#{unquote(exchange_id)}: missing __ccxt_ws_spec__/0"

        spec = unquote(ws_module).__ccxt_ws_spec__()

        assert is_map(spec),
               "#{unquote(exchange_id)}: __ccxt_ws_spec__/0 should return a map"
      end

      test "exports __ccxt_ws_pattern__/0" do
        assert function_exported?(unquote(ws_module), :__ccxt_ws_pattern__, 0),
               "#{unquote(exchange_id)}: missing __ccxt_ws_pattern__/0"

        pattern = unquote(ws_module).__ccxt_ws_pattern__()

        assert pattern in @valid_patterns,
               "#{unquote(exchange_id)}: invalid WS pattern #{inspect(pattern)}"
      end

      test "exports __ccxt_ws_channels__/0" do
        assert function_exported?(unquote(ws_module), :__ccxt_ws_channels__, 0),
               "#{unquote(exchange_id)}: missing __ccxt_ws_channels__/0"

        channels = unquote(ws_module).__ccxt_ws_channels__()

        assert is_map(channels),
               "#{unquote(exchange_id)}: __ccxt_ws_channels__/0 should return a map"
      end
    end
  end

  @doc false
  # Generate subscription function tests
  defp generate_subscription_tests(exchange_id, ws_module) do
    quote do
      test "watch_ticker_subscription returns correct structure (if available)" do
        ws_module = unquote(ws_module)

        has_ticker_1 = function_exported?(ws_module, :watch_ticker_subscription, 1)
        has_ticker_2 = function_exported?(ws_module, :watch_ticker_subscription, 2)

        if has_ticker_1 or has_ticker_2 do
          result =
            if has_ticker_1 do
              ws_module.watch_ticker_subscription("BTC/USDT")
            else
              ws_module.watch_ticker_subscription("BTC/USDT", [])
            end

          assert {:ok, sub} = result,
                 "#{unquote(exchange_id)}: watch_ticker_subscription should return {:ok, sub}"

          # Inline assertions for subscription structure
          assert is_map(sub), "Subscription should be a map"
          assert Map.has_key?(sub, :channel), "Subscription should have :channel"
          assert Map.has_key?(sub, :message), "Subscription should have :message"
          assert Map.has_key?(sub, :method), "Subscription should have :method"
          assert Map.has_key?(sub, :auth_required), "Subscription should have :auth_required"
          assert is_map(sub.message), "Message should be a map"
          assert is_atom(sub.method), "Method should be an atom"
          assert is_boolean(sub.auth_required), "auth_required should be a boolean"
        end
      end

      test "watch_order_book_subscription returns correct structure (if available)" do
        ws_module = unquote(ws_module)

        has_book_2 = function_exported?(ws_module, :watch_order_book_subscription, 2)
        has_book_3 = function_exported?(ws_module, :watch_order_book_subscription, 3)

        if has_book_2 or has_book_3 do
          result =
            if has_book_2 do
              ws_module.watch_order_book_subscription("BTC/USDT", nil)
            else
              ws_module.watch_order_book_subscription("BTC/USDT", nil, [])
            end

          assert {:ok, sub} = result,
                 "#{unquote(exchange_id)}: watch_order_book_subscription should return {:ok, sub}"

          assert is_map(sub), "Subscription should be a map"
          assert Map.has_key?(sub, :channel), "Subscription should have :channel"
          assert Map.has_key?(sub, :message), "Subscription should have :message"
          assert sub.method == :watch_order_book, "Method should be :watch_order_book"
        end
      end
    end
  end

  @doc false
  # Generate base module tests
  # Note: WS introspection functions are on the .WS submodule, not the base module
  defp generate_base_module_tests(exchange_id, base_module) do
    quote do
      test "base exchange module exists" do
        base_module = unquote(base_module)

        assert Code.ensure_loaded?(base_module),
               "#{unquote(exchange_id)}: base module should be loaded"
      end
    end
  end

  @doc false
  # Generate WS pattern distribution report with coverage percentage
  defp generate_distribution_report(installed_ws_modules) do
    # Get total exchange count at compile time (excluding test_exchange)
    total_exchanges =
      Classification.all_exchanges()
      |> Enum.reject(&(&1 == "test_exchange"))
      |> length()

    quote do
      describe "WS subscription pattern distribution" do
        @tag :ws_distribution_report

        test "reports WS pattern coverage" do
          modules = unquote(Macro.escape(installed_ws_modules))
          total_exchange_count = unquote(total_exchanges)

          if Enum.empty?(modules) do
            Logger.info("No WS modules to analyze")
          else
            pattern_counts =
              modules
              |> Enum.map(fn {_exchange_id, ws_module, _base_module} ->
                ws_module.__ccxt_ws_pattern__()
              end)
              |> Enum.reject(&is_nil/1)
              |> Enum.frequencies()
              |> Enum.sort_by(fn {_pattern, count} -> -count end)

            ws_enabled_count = Enum.sum(Enum.map(pattern_counts, fn {_, count} -> count end))

            # Calculate overall WS coverage percentage
            coverage_pct = Float.round(ws_enabled_count / total_exchange_count * 100, 1)

            Logger.info("WS Coverage: #{ws_enabled_count}/#{total_exchange_count} exchanges (#{coverage_pct}%)")

            Logger.info("WS pattern distribution:")

            for {pattern, count} <- pattern_counts do
              pct = Float.round(count / ws_enabled_count * 100, 1)
              Logger.info("  #{pattern}: #{count} (#{pct}%)")
            end

            all_valid =
              Enum.all?(pattern_counts, fn {pattern, _} -> pattern in @valid_patterns end)

            assert all_valid, "All WS-enabled exchanges should use valid patterns"
          end
        end
      end
    end
  end
end
