defmodule CCXT.Exchanges.SupportedSmokeTest do
  @moduledoc """
  Smoke tests for Supported exchanges.

  Supported exchanges have neither `certified: true` nor `pro: true` in CCXT.
  These exchanges have basic REST-only support without WebSocket APIs.

  Tests verify that all Supported exchange modules:
  1. Compile successfully
  2. Have a valid signing pattern configured
  3. Export the expected introspection functions
  4. Have the escape hatch functions

  Run with: mix test test/ccxt/exchanges/classification/supported_smoke_test.exs
  """
  use ExUnit.Case, async: true

  alias CCXT.Exchange.Classification
  alias CCXT.Test.ExchangeHelper

  require Logger

  @moduletag :supported

  # Test exchange (not a real exchange)
  @excluded_exchanges [:test_exchange]

  # Use canonical list from CCXT.Signing
  @valid_patterns CCXT.Signing.patterns()

  # Get Supported exchange modules
  defp expected_supported_atoms do
    Enum.reject(Classification.supported_atoms(), &(&1 in @excluded_exchanges))
  end

  defp supported_modules do
    expected_supported_atoms()
    |> Enum.map(fn atom ->
      module_name = atom |> Atom.to_string() |> Macro.camelize()
      module = Module.concat([CCXT, module_name])
      {atom, module}
    end)
    |> Enum.filter(fn {_atom, module} -> Code.ensure_loaded?(module) end)
  end

  describe "Supported exchange module compilation" do
    test "all Supported exchange modules compile and load" do
      modules = supported_modules()
      expected = expected_supported_atoms()

      # Supported exchanges may be empty in --only mode or when only certified/pro are installed.
      # This is a valid state during development with limited spec extraction.
      if modules == [] do
        Logger.info("[INFO] No Supported exchange modules installed")
      end

      if ExchangeHelper.strict_exchange_tests?() do
        missing = expected -- Enum.map(modules, &elem(&1, 0))

        if missing != [] do
          flunk("""
          Missing Supported exchange modules after full sync!

          Missing: #{inspect(missing)}

          Run: mix ccxt.sync --all
          """)
        end
      end

      # All loaded modules should work
      for {name, module} <- modules do
        assert Code.ensure_loaded?(module),
               "Module #{module} (#{name}) should be loaded"
      end
    end
  end

  describe "introspection functions" do
    test "all modules export __ccxt_spec__/0" do
      for {name, module} <- supported_modules() do
        assert function_exported?(module, :__ccxt_spec__, 0),
               "#{name}: missing __ccxt_spec__/0"

        spec = module.__ccxt_spec__()
        assert is_map(spec), "#{name}: __ccxt_spec__/0 should return a map"
        assert Map.has_key?(spec, :id), "#{name}: spec should have :id"
      end
    end

    test "all modules export __ccxt_signing__/0" do
      for {name, module} <- supported_modules() do
        assert function_exported?(module, :__ccxt_signing__, 0),
               "#{name}: missing __ccxt_signing__/0"

        signing = module.__ccxt_signing__()
        assert is_map(signing), "#{name}: __ccxt_signing__/0 should return a map"
        assert Map.has_key?(signing, :pattern), "#{name}: signing should have :pattern"
      end
    end

    test "all modules export __ccxt_endpoints__/0" do
      for {name, module} <- supported_modules() do
        assert function_exported?(module, :__ccxt_endpoints__, 0),
               "#{name}: missing __ccxt_endpoints__/0"

        endpoints = module.__ccxt_endpoints__()
        assert is_list(endpoints), "#{name}: __ccxt_endpoints__/0 should return a list"
      end
    end
  end

  describe "signing patterns" do
    test "all modules have valid signing patterns" do
      invalid =
        supported_modules()
        |> Enum.filter(fn {_name, module} ->
          pattern = module.__ccxt_signing__()[:pattern]
          pattern not in @valid_patterns
        end)
        |> Enum.map(fn {name, module} ->
          {name, module.__ccxt_signing__()[:pattern]}
        end)

      if invalid != [] do
        invalid_list =
          Enum.map_join(invalid, "\n", fn {name, pattern} -> "  #{name}: #{inspect(pattern)}" end)

        flunk("Supported exchanges with invalid signing patterns:\n#{invalid_list}")
      end
    end
  end

  describe "escape hatches" do
    test "all modules export request/3" do
      for {name, module} <- supported_modules() do
        assert function_exported?(module, :request, 3),
               "#{name}: missing request/3 escape hatch"
      end
    end

    test "all modules export raw_request/5" do
      for {name, module} <- supported_modules() do
        assert function_exported?(module, :raw_request, 5),
               "#{name}: missing raw_request/5 escape hatch"
      end
    end
  end

  describe "classification verification" do
    test "all modules are correctly classified as Supported" do
      for {name, _module} <- supported_modules() do
        exchange_id = Atom.to_string(name)

        assert Classification.supported?(exchange_id),
               "#{name}: should be classified as Supported"

        refute Classification.certified?(exchange_id),
               "#{name}: should NOT have certified: true"

        refute Classification.pro?(exchange_id),
               "#{name}: should NOT have pro: true"
      end
    end
  end

  describe "signing pattern distribution" do
    test "reports signing pattern coverage" do
      modules = supported_modules()

      if modules == [] do
        Logger.info("[INFO] No Supported modules to analyze")
      else
        pattern_counts =
          modules
          |> Enum.map(fn {_name, module} ->
            module.__ccxt_signing__()[:pattern]
          end)
          |> Enum.frequencies()
          |> Enum.sort_by(fn {_pattern, count} -> -count end)

        Logger.info("Signing pattern distribution (#{length(modules)} Supported exchanges):")

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
               "All Supported exchanges should use valid patterns"
      end
    end
  end
end
