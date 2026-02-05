defmodule CCXT.Test.SmokeTestGenerator do
  @moduledoc """
  Macro that generates smoke tests for all installed exchange modules at compile time.

  This replaces manually written smoke tests by dynamically discovering which
  exchanges have generated modules and creating appropriate tests for each.

  ## Usage

      defmodule CCXT.Exchanges.SmokeTest do
        use CCXT.Test.SmokeTestGenerator
      end

  This generates:
  - Tests for each installed exchange module (introspection, signing, escape hatches)
  - Module tags: `:smoke`, `:exchange_{id}`, classification tag, tier tag
  - Signing pattern distribution report

  ## Generated Tags

  Each generated test receives hierarchical tags:

  | Tag | Description |
  |-----|-------------|
  | `@moduletag :smoke` | All tests are smoke tests |
  | `@tag :exchange_{id}` | Exchange-specific tag |
  | `@tag :certified_pro` / `:pro` / `:supported` | CCXT classification from spec |
  | `@tag :tier1` / `:tier2` / `:tier3` / `:dex` / `:unclassified` | Priority tier |

  ## Filtering Examples

      # Run smoke tests for all exchanges
      mix test --only smoke

      # Run smoke tests for Tier 1 exchanges only
      mix test --only smoke --only tier1

      # Run smoke tests excluding low-priority exchanges
      mix test --only smoke --exclude tier3
  """

  alias CCXT.Exchange.Classification

  # Use canonical list from CCXT.Signing
  @valid_patterns CCXT.Signing.patterns()

  @doc """
  Generates smoke tests for all installed exchange modules.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(_opts) do
    # Get installed exchanges at compile time
    installed_exchanges = get_installed_exchanges()

    tests =
      for {exchange_id, module} <- installed_exchanges do
        generate_exchange_tests(exchange_id, module)
      end

    quote do
      use ExUnit.Case, async: true

      require Logger

      @moduletag :smoke

      # Store valid patterns for tests
      @valid_patterns unquote(@valid_patterns)

      unquote_splicing(tests)

      # Generate signing pattern distribution report
      unquote(generate_distribution_report(installed_exchanges))
    end
  end

  # Get list of installed exchanges and their modules at compile time
  @doc false
  def get_installed_exchanges do
    Classification.all_exchanges()
    |> Enum.reject(&(&1 == "test_exchange"))
    |> Enum.map(fn exchange_id ->
      module_name = Macro.camelize(exchange_id)
      module = Module.concat([CCXT, module_name])
      {exchange_id, module}
    end)
    |> Enum.filter(fn {_exchange_id, module} ->
      Code.ensure_loaded?(module)
    end)
  end

  # Generate tests for a single exchange
  @doc false
  defp generate_exchange_tests(exchange_id, module) do
    classification_tag = Classification.get_classification(exchange_id)
    tier_tag = Classification.get_priority_tier(exchange_id)
    # Safe: exchange_id comes from trusted Classification module (finite set of ~110 exchanges)
    exchange_tag = String.to_atom("exchange_#{exchange_id}")

    quote do
      describe unquote("#{exchange_id}") do
        @tag unquote(exchange_tag)
        @tag unquote(classification_tag)
        @tag unquote(tier_tag)

        test "module compiles and loads" do
          assert Code.ensure_loaded?(unquote(module)),
                 "Module #{inspect(unquote(module))} should be loaded"
        end

        test "exports __ccxt_spec__/0" do
          assert function_exported?(unquote(module), :__ccxt_spec__, 0),
                 "#{unquote(exchange_id)}: missing __ccxt_spec__/0"

          spec = unquote(module).__ccxt_spec__()
          assert is_map(spec), "#{unquote(exchange_id)}: __ccxt_spec__/0 should return a map"
          assert Map.has_key?(spec, :id), "#{unquote(exchange_id)}: spec should have :id"
          assert spec.id == unquote(exchange_id), "#{unquote(exchange_id)}: spec.id mismatch"
        end

        test "exports __ccxt_signing__/0" do
          assert function_exported?(unquote(module), :__ccxt_signing__, 0),
                 "#{unquote(exchange_id)}: missing __ccxt_signing__/0"

          signing = unquote(module).__ccxt_signing__()
          assert is_map(signing), "#{unquote(exchange_id)}: __ccxt_signing__/0 should return a map"
          assert Map.has_key?(signing, :pattern), "#{unquote(exchange_id)}: signing should have :pattern"
        end

        test "exports __ccxt_endpoints__/0" do
          assert function_exported?(unquote(module), :__ccxt_endpoints__, 0),
                 "#{unquote(exchange_id)}: missing __ccxt_endpoints__/0"

          endpoints = unquote(module).__ccxt_endpoints__()
          assert is_list(endpoints), "#{unquote(exchange_id)}: __ccxt_endpoints__/0 should return a list"
        end

        test "has valid signing pattern" do
          signing = unquote(module).__ccxt_signing__()
          pattern = signing[:pattern]

          assert pattern in @valid_patterns,
                 "#{unquote(exchange_id)}: invalid signing pattern #{inspect(pattern)}, expected one of #{inspect(@valid_patterns)}"
        end

        test "exports request/3 escape hatch" do
          assert function_exported?(unquote(module), :request, 3),
                 "#{unquote(exchange_id)}: missing request/3 escape hatch"
        end

        test "exports raw_request/5 escape hatch" do
          assert function_exported?(unquote(module), :raw_request, 5),
                 "#{unquote(exchange_id)}: missing raw_request/5 escape hatch"
        end

        test "classification is correct" do
          exchange_id = unquote(exchange_id)

          # Verify the module's classification matches what Classification reports
          actual = Classification.get_classification(exchange_id)

          assert actual == unquote(classification_tag),
                 "#{exchange_id}: classification mismatch, expected #{unquote(classification_tag)}, got #{actual}"

          # Verify classification predicates are consistent
          assert Classification.certified_pro?(exchange_id) == (actual == :certified_pro)
          assert Classification.pro?(exchange_id) == actual in [:certified_pro, :pro]
        end
      end
    end
  end

  # Generate signing pattern distribution report
  @doc false
  defp generate_distribution_report(installed_exchanges) do
    quote do
      describe "signing pattern distribution" do
        @tag :distribution_report

        test "reports signing pattern coverage" do
          modules = unquote(Macro.escape(installed_exchanges))

          if Enum.empty?(modules) do
            Logger.info("No exchange modules to analyze")
          else
            pattern_counts =
              modules
              |> Enum.map(fn {_exchange_id, module} ->
                module.__ccxt_signing__()[:pattern]
              end)
              |> Enum.frequencies()
              |> Enum.sort_by(fn {_pattern, count} -> -count end)

            Logger.info("Signing pattern distribution (#{length(modules)} exchanges):")

            for {pattern, count} <- pattern_counts do
              pct = Float.round(count / length(modules) * 100, 1)
              Logger.info("  #{pattern}: #{count} (#{pct}%)")
            end

            # Verify all use valid patterns
            total_covered =
              pattern_counts
              |> Enum.filter(fn {pattern, _} -> pattern in @valid_patterns end)
              |> Enum.map(fn {_, count} -> count end)
              |> Enum.sum()

            assert total_covered == length(modules),
                   "All exchanges should use valid patterns"
          end
        end
      end
    end
  end
end
