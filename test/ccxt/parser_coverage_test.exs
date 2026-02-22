defmodule CCXT.ParserCoverageTest do
  @moduledoc """
  Parser coverage assertions and inventory for the normalization pipeline.

  Ensures Tier 1 exchanges have required parsers, validates cross-module
  consistency between MappingCompiler and ResponseCoercer, and provides
  informational coverage reporting.
  """

  use ExUnit.Case, async: true

  alias CCXT.ResponseCoercer
  alias CCXT.ResponseParser.MappingCompiler
  alias CCXT.Test.ExchangeHelper

  require Logger

  @moduletag :parser_coverage

  @analysis MappingCompiler.load_analysis()

  # Guard: P1 analysis must be loaded for tests to be meaningful
  if @analysis == %{} do
    raise "P1 analysis file not found at #{MappingCompiler.analysis_path()} — cannot run parser coverage tests"
  end

  @tier1_exchanges ~w(binance bybit okx deribit coinbaseexchange)
  @tier1_required_types [:ticker, :trade, :order]

  # Known exceptions: types where parser instructions are intentionally absent
  @known_exceptions %{
    order_book: "Most exchanges return unified bids/asks/timestamp keys — no field remapping needed",
    balance: "Balance has nested currency maps (%{free: %{}, used: %{}, total: %{}}), not simple field remapping"
  }

  # type_modules entries that intentionally have no corresponding parse method
  @known_extra_types MapSet.new([:market_interface])

  # ── Tier 1 hard assertions ───────────────────────────────────────────

  describe "tier 1: required parser coverage" do
    for exchange_id <- @tier1_exchanges,
        type <- @tier1_required_types do
      @exchange_id exchange_id
      @parser_type type

      test "#{exchange_id} has parser instructions for #{type}" do
        exchange_module =
          @exchange_id
          |> Macro.camelize()
          |> then(&Module.concat([CCXT, &1]))

        assert Code.ensure_loaded?(exchange_module),
               "Exchange module #{inspect(exchange_module)} not available"

        parsers = exchange_module.__ccxt_parsers__()

        assert Map.has_key?(parsers, @parser_type),
               """
               #{@exchange_id} is missing parser instructions for #{inspect(@parser_type)}.

               Available parsers: #{parsers |> Map.keys() |> Enum.sort() |> inspect()}

               This is a Tier 1 exchange — #{inspect(@parser_type)} parser is required.
               Check the P1 analysis data and MappingCompiler for this exchange.
               """

        instructions = Map.get(parsers, @parser_type)

        assert is_list(instructions) and instructions != [],
               "#{@exchange_id} #{inspect(@parser_type)} parser has empty instruction list"
      end
    end
  end

  # ── Coverage inventory (informational) ────────────────────────────────

  describe "coverage inventory" do
    test "reports parser coverage across all available exchanges" do
      modules = ExchangeHelper.available_exchange_modules()
      assert modules != [], "No exchange modules available — cannot report coverage"

      schema_types =
        MappingCompiler.method_schemas()
        |> Map.values()
        |> Enum.map(&elem(&1, 1))
        |> Enum.sort()

      type_count = length(schema_types)

      coverage_report =
        for mod <- Enum.sort_by(modules, &Module.split(&1)) do
          parsers = mod.__ccxt_parsers__()
          parser_keys = parsers |> Map.keys() |> MapSet.new()

          covered = Enum.filter(schema_types, &MapSet.member?(parser_keys, &1))

          exchange_name = mod |> Module.split() |> List.last()
          percentage = Float.round(length(covered) / type_count * 100, 1)

          gaps =
            Enum.reject(schema_types, fn type ->
              MapSet.member?(parser_keys, type) or Map.has_key?(@known_exceptions, type)
            end)

          %{
            exchange: exchange_name,
            covered: length(covered),
            total: type_count,
            percentage: percentage,
            gaps: gaps
          }
        end

      # Coverage report via Logger (suppressed by --quiet, visible in normal runs)
      report_lines =
        for entry <- coverage_report do
          gap_str = if entry.gaps == [], do: "", else: " gaps: #{inspect(entry.gaps)}"
          "  #{entry.exchange}: #{entry.covered}/#{entry.total} (#{entry.percentage}%)#{gap_str}"
        end

      Logger.info("""
      \n=== Parser Coverage Report ===
      Schema types: #{type_count}
      Known exceptions: #{inspect(Map.keys(@known_exceptions))}

      #{Enum.join(report_lines, "\n")}

      === End Coverage Report ===
      """)

      # Verify every exchange has at least one parser (not just "modules exist")
      for entry <- coverage_report do
        assert entry.covered > 0,
               "#{entry.exchange} has 0 parser coverage — expected at least 1 parser"
      end
    end
  end

  # ── Cross-validation: method_schemas ⊆ type_modules ──────────────────

  describe "cross-validation" do
    test "every method_schemas type atom exists in ResponseCoercer.type_modules/0" do
      schema_type_atoms =
        MappingCompiler.method_schemas()
        |> Map.values()
        |> MapSet.new(&elem(&1, 1))

      type_module_keys =
        ResponseCoercer.type_modules()
        |> Map.keys()
        |> MapSet.new()

      missing = MapSet.difference(schema_type_atoms, type_module_keys)

      assert MapSet.size(missing) == 0,
             """
             These type atoms from MappingCompiler.method_schemas/0 are missing
             from ResponseCoercer.type_modules/0:

             #{inspect(MapSet.to_list(missing))}

             Every schema type must have a corresponding entry in the coercer
             so that parsed data can be converted to typed structs.
             """
    end

    test "extra type_modules entries are from a known set" do
      # type_modules may have entries without a corresponding parse method
      # (e.g., :market_interface is coerced but not parsed from exchange data).
      # This test verifies any extras are expected — fails loudly if new unknowns appear.
      schema_type_atoms =
        MappingCompiler.method_schemas()
        |> Map.values()
        |> MapSet.new(&elem(&1, 1))

      type_module_keys =
        ResponseCoercer.type_modules()
        |> Map.keys()
        |> MapSet.new()

      extra = MapSet.difference(type_module_keys, schema_type_atoms)
      unexpected = MapSet.difference(extra, @known_extra_types)

      assert MapSet.size(unexpected) == 0,
             """
             Unexpected type_modules entries not in method_schemas:
             #{inspect(MapSet.to_list(unexpected))}

             If these are intentional, add them to @known_extra_types in this test.
             """
    end
  end

  # ── Known exceptions ──────────────────────────────────────────────────

  describe "known exceptions" do
    for {type, _rationale} <- @known_exceptions do
      @exception_type type

      test "#{type} has a documented rationale" do
        rationale = Map.fetch!(@known_exceptions, @exception_type)

        assert byte_size(rationale) > 0,
               "Known exception #{inspect(@exception_type)} must have a non-empty rationale string"
      end
    end
  end
end
