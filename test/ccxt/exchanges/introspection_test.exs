defmodule CCXT.Exchanges.IntrospectionTest do
  @moduledoc """
  Introspection tests for ALL generated exchange modules.

  These tests verify that generated modules have:
  1. Valid introspection functions (__ccxt_spec__, __ccxt_endpoints__, etc.)
  2. Expected endpoint functions based on their spec
  3. Valid spec data structure
  4. Escape hatch functions (request/3, raw_request/5)

  These tests require no network calls and no credentials - they verify
  compile-time generated code only.

  Run with:
    mix test test/ccxt/exchanges/introspection_test.exs

  Or run all introspection tests:
    mix test --only introspection
  """
  use ExUnit.Case, async: true

  require Logger

  @moduletag :introspection

  # Test exchange is excluded (not a real exchange)
  @excluded_exchanges [:test_exchange]

  # Use canonical list from CCXT.Signing
  @valid_patterns CCXT.Signing.patterns()

  # Get all exchange modules dynamically (all tiers)
  defp all_exchange_modules do
    exchanges_dir = Path.join([File.cwd!(), "lib", "ccxt", "exchanges"])

    if File.dir?(exchanges_dir) do
      exchanges_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".ex"))
      |> Enum.map(fn file ->
        exchange_name =
          file
          |> String.replace_suffix(".ex", "")
          |> Macro.camelize()

        module = Module.concat([CCXT, exchange_name])

        exchange_atom =
          file
          |> String.replace_suffix(".ex", "")
          |> String.to_atom()

        {exchange_atom, module}
      end)
      |> Enum.filter(fn {atom, module} ->
        atom not in @excluded_exchanges and
          Code.ensure_loaded?(module)
      end)
    else
      []
    end
  end

  # Group exchanges by classification
  defp exchanges_by_classification do
    Enum.group_by(all_exchange_modules(), fn {_name, module} ->
      spec = module.__ccxt_spec__()
      spec.classification
    end)
  end

  describe "module existence" do
    test "all exchange modules compile and load" do
      exchanges_dir = Path.join([File.cwd!(), "lib", "ccxt", "exchanges"])

      # Count non-stub .ex files (excluding test_exchange)
      # Stub files are 1-byte placeholders created by --only mode
      expected_files =
        exchanges_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".ex"))
        |> Enum.reject(&(&1 == "test_exchange.ex"))
        |> Enum.filter(fn file ->
          path = Path.join(exchanges_dir, file)
          # Non-stub files have more than 1 byte
          File.stat!(path).size > 1
        end)

      modules = all_exchange_modules()

      # Verify ALL non-stub modules loaded
      assert length(modules) == length(expected_files),
             "Expected #{length(expected_files)} exchanges, got #{length(modules)}. " <>
               "Some modules may have failed to load."

      # All modules should be loaded
      for {name, module} <- modules do
        assert Code.ensure_loaded?(module),
               "Module #{module} (#{name}) should be loaded"
      end
    end

    test "reports classification distribution" do
      by_classification = exchanges_by_classification()
      total = length(all_exchange_modules())

      certified_pro_count = length(Map.get(by_classification, :certified_pro, []))
      pro_count = length(Map.get(by_classification, :pro, []))
      supported_count = length(Map.get(by_classification, :supported, []))

      Logger.info("Exchange classification distribution (#{total} total):")
      Logger.info("  Certified Pro: #{certified_pro_count}")
      Logger.info("  Pro: #{pro_count}")
      Logger.info("  Supported: #{supported_count}")

      # Sanity check: all classifications should add up
      assert total == certified_pro_count + pro_count + supported_count
    end
  end

  describe "__ccxt_spec__/0" do
    test "all modules export __ccxt_spec__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_spec__, 0),
               "#{name}: missing __ccxt_spec__/0"
      end
    end

    test "spec returns valid CCXT.Spec struct" do
      for {name, module} <- all_exchange_modules() do
        spec = module.__ccxt_spec__()

        assert %CCXT.Spec{} = spec,
               "#{name}: __ccxt_spec__/0 should return a CCXT.Spec struct"

        # Required fields
        assert is_binary(spec.id), "#{name}: spec.id should be a string"
        assert is_binary(spec.name), "#{name}: spec.name should be a string"
        assert is_map(spec.urls), "#{name}: spec.urls should be a map"
        assert Map.has_key?(spec.urls, :api), "#{name}: spec.urls should have :api"
      end
    end

    test "spec.id matches module name convention" do
      for {name, module} <- all_exchange_modules() do
        spec = module.__ccxt_spec__()

        # The module name should match the spec id (with camelcase conversion)
        expected_module_suffix = Macro.camelize(spec.id)
        module_name = module |> Module.split() |> List.last()

        assert module_name == expected_module_suffix,
               "#{name}: module name '#{module_name}' should match spec.id '#{spec.id}' (expected #{expected_module_suffix})"
      end
    end
  end

  describe "__ccxt_endpoints__/0" do
    test "all modules export __ccxt_endpoints__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_endpoints__, 0),
               "#{name}: missing __ccxt_endpoints__/0"
      end
    end

    test "endpoints is a list of valid endpoint maps" do
      for {name, module} <- all_exchange_modules() do
        endpoints = module.__ccxt_endpoints__()

        assert is_list(endpoints),
               "#{name}: __ccxt_endpoints__/0 should return a list"

        for endpoint <- endpoints do
          assert is_map(endpoint), "#{name}: each endpoint should be a map"
          assert Map.has_key?(endpoint, :name), "#{name}: endpoint should have :name"
          assert Map.has_key?(endpoint, :method), "#{name}: endpoint should have :method"
          assert Map.has_key?(endpoint, :path), "#{name}: endpoint should have :path"
          assert Map.has_key?(endpoint, :auth), "#{name}: endpoint should have :auth"
          assert Map.has_key?(endpoint, :params), "#{name}: endpoint should have :params"

          assert is_atom(endpoint[:name]), "#{name}: endpoint.name should be atom"

          assert endpoint[:method] in [:get, :post, :put, :delete, :patch],
                 "#{name}: endpoint.method should be valid HTTP method"

          assert is_binary(endpoint[:path]), "#{name}: endpoint.path should be string"
          assert is_boolean(endpoint[:auth]), "#{name}: endpoint.auth should be boolean"
          assert is_list(endpoint[:params]), "#{name}: endpoint.params should be list"
        end
      end
    end
  end

  describe "__ccxt_signing__/0" do
    test "all modules export __ccxt_signing__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_signing__, 0),
               "#{name}: missing __ccxt_signing__/0"
      end
    end

    test "all signing configs have valid patterns" do
      # 100% of exchanges should use valid patterns
      invalid =
        all_exchange_modules()
        |> Enum.filter(fn {_name, module} ->
          signing = module.__ccxt_signing__()
          signing != nil and signing[:pattern] not in @valid_patterns
        end)
        |> Enum.map(fn {name, module} ->
          {name, module.__ccxt_signing__()[:pattern]}
        end)

      if invalid != [] do
        invalid_list =
          Enum.map_join(invalid, "\n", fn {name, pattern} ->
            "  #{name}: #{inspect(pattern)}"
          end)

        flunk("Exchanges with invalid signing patterns:\n#{invalid_list}")
      end
    end

    test "signing config has required fields when pattern is set" do
      for {name, module} <- all_exchange_modules() do
        signing = module.__ccxt_signing__()

        if signing != nil do
          assert is_map(signing), "#{name}: signing should be a map"
          assert Map.has_key?(signing, :pattern), "#{name}: signing should have :pattern"
          assert is_atom(signing[:pattern]), "#{name}: signing.pattern should be atom"
        end
      end
    end
  end

  describe "__ccxt_classification__/0" do
    test "all modules export __ccxt_classification__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_classification__, 0),
               "#{name}: missing __ccxt_classification__/0"
      end
    end

    test "classification is :certified_pro, :pro, or :supported" do
      for {name, module} <- all_exchange_modules() do
        classification = module.__ccxt_classification__()

        assert classification in [:certified_pro, :pro, :supported],
               "#{name}: classification should be :certified_pro, :pro, or :supported, got #{classification}"
      end
    end
  end

  describe "endpoint functions" do
    test "all endpoint functions exist based on spec" do
      for {name, module} <- all_exchange_modules() do
        endpoints = module.__ccxt_endpoints__()

        for endpoint <- endpoints do
          func_name = endpoint[:name]
          # Calculate expected arity: params + opts (+ credentials for auth)
          base_arity = length(endpoint[:params]) + 1
          expected_arity = if endpoint[:auth], do: base_arity + 1, else: base_arity

          assert function_exported?(module, func_name, expected_arity),
                 "#{name}: missing #{func_name}/#{expected_arity} (auth=#{endpoint[:auth]}, params=#{inspect(endpoint[:params])})"
        end
      end
    end

    # NOTE: We don't test has.X => function exists because `has` comes from CCXT's
    # capability declaration, but functions are only generated from `endpoints`.
    # The extractor may not have extracted all endpoints for all capabilities.
    # The test above "all endpoint functions exist based on spec" verifies the
    # correct relationship: every endpoint in spec has a corresponding function.
  end

  describe "escape hatches" do
    test "all modules export request/3" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :request, 3),
               "#{name}: missing request/3 escape hatch"
      end
    end

    test "all modules export raw_request/5" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :raw_request, 5),
               "#{name}: missing raw_request/5 escape hatch"
      end
    end
  end

  # ===========================================================================
  # Extended Introspection Functions (Complete CCXT Data Passthrough)
  # ===========================================================================

  describe "extended introspection - metadata functions" do
    test "all modules export __ccxt_extended_metadata__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_extended_metadata__, 0),
               "#{name}: missing __ccxt_extended_metadata__/0"
      end
    end

    test "__ccxt_extended_metadata__/0 returns map or nil" do
      for {name, module} <- all_exchange_modules() do
        result = module.__ccxt_extended_metadata__()

        assert is_nil(result) or is_map(result),
               "#{name}: __ccxt_extended_metadata__/0 should return map or nil, got #{inspect(result)}"
      end
    end

    test "all modules export __ccxt_extraction_info__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_extraction_info__, 0),
               "#{name}: missing __ccxt_extraction_info__/0"
      end
    end

    test "__ccxt_extraction_info__/0 returns extraction metadata" do
      for {name, module} <- all_exchange_modules() do
        result = module.__ccxt_extraction_info__()

        if result do
          assert is_map(result), "#{name}: __ccxt_extraction_info__/0 should return map"
          assert Map.has_key?(result, :ccxt_version), "#{name}: should have :ccxt_version"
        end
      end
    end
  end

  describe "extended introspection - market data functions" do
    test "all modules export __ccxt_currencies__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_currencies__, 0),
               "#{name}: missing __ccxt_currencies__/0"
      end
    end

    test "__ccxt_currencies__/0 returns map or nil" do
      for {name, module} <- all_exchange_modules() do
        result = module.__ccxt_currencies__()

        assert is_nil(result) or is_map(result),
               "#{name}: __ccxt_currencies__/0 should return map or nil"
      end
    end

    test "all modules export __ccxt_markets__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_markets__, 0),
               "#{name}: missing __ccxt_markets__/0"
      end
    end

    test "__ccxt_markets__/0 returns map or nil" do
      for {name, module} <- all_exchange_modules() do
        result = module.__ccxt_markets__()

        assert is_nil(result) or is_map(result),
               "#{name}: __ccxt_markets__/0 should return map or nil"
      end
    end
  end

  describe "extended introspection - API configuration functions" do
    test "all modules export __ccxt_required_credentials__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_required_credentials__, 0),
               "#{name}: missing __ccxt_required_credentials__/0"
      end
    end

    test "__ccxt_required_credentials__/0 returns map or nil" do
      for {name, module} <- all_exchange_modules() do
        result = module.__ccxt_required_credentials__()

        assert is_nil(result) or is_map(result),
               "#{name}: __ccxt_required_credentials__/0 should return map or nil"
      end
    end

    test "all modules export __ccxt_api_param_requirements__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_api_param_requirements__, 0),
               "#{name}: missing __ccxt_api_param_requirements__/0"
      end
    end

    test "all modules export __ccxt_url_strategy__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_url_strategy__, 0),
               "#{name}: missing __ccxt_url_strategy__/0"
      end
    end

    test "all modules export __ccxt_exchange_options__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_exchange_options__, 0),
               "#{name}: missing __ccxt_exchange_options__/0"
      end
    end
  end

  describe "extended introspection - status functions" do
    test "all modules export __ccxt_status__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_status__, 0),
               "#{name}: missing __ccxt_status__/0"
      end
    end

    test "all modules export __ccxt_endpoint_stats__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_endpoint_stats__, 0),
               "#{name}: missing __ccxt_endpoint_stats__/0"
      end
    end

    test "__ccxt_endpoint_stats__/0 returns extraction quality metrics" do
      for {name, module} <- all_exchange_modules() do
        result = module.__ccxt_endpoint_stats__()

        if result do
          assert is_map(result), "#{name}: __ccxt_endpoint_stats__/0 should return map"
          # May have coverage info
          if Map.has_key?(result, "coveragePercent") do
            assert is_number(result["coveragePercent"]),
                   "#{name}: coveragePercent should be a number"
          end
        end
      end
    end
  end

  describe "extended introspection - classification flags" do
    test "all modules export __ccxt_certified__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_certified__, 0),
               "#{name}: missing __ccxt_certified__/0"
      end
    end

    test "__ccxt_certified__/0 returns boolean or nil" do
      for {name, module} <- all_exchange_modules() do
        result = module.__ccxt_certified__()

        assert is_nil(result) or is_boolean(result),
               "#{name}: __ccxt_certified__/0 should return boolean or nil"
      end
    end

    test "all modules export __ccxt_pro__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_pro__, 0),
               "#{name}: missing __ccxt_pro__/0"
      end
    end

    test "__ccxt_pro__/0 returns boolean or nil" do
      for {name, module} <- all_exchange_modules() do
        result = module.__ccxt_pro__()

        assert is_nil(result) or is_boolean(result),
               "#{name}: __ccxt_pro__/0 should return boolean or nil"
      end
    end

    test "all modules export __ccxt_dex__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_dex__, 0),
               "#{name}: missing __ccxt_dex__/0"
      end
    end

    test "__ccxt_dex__/0 returns boolean or nil" do
      for {name, module} <- all_exchange_modules() do
        result = module.__ccxt_dex__()

        assert is_nil(result) or is_boolean(result),
               "#{name}: __ccxt_dex__/0 should return boolean or nil"
      end
    end

    test "all modules export __ccxt_precision_mode__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_precision_mode__, 0),
               "#{name}: missing __ccxt_precision_mode__/0"
      end
    end

    test "__ccxt_precision_mode__/0 returns integer or nil" do
      for {name, module} <- all_exchange_modules() do
        result = module.__ccxt_precision_mode__()

        assert is_nil(result) or is_integer(result),
               "#{name}: __ccxt_precision_mode__/0 should return integer or nil, got #{inspect(result)}"
      end
    end
  end

  describe "extended introspection - documentation functions" do
    test "all modules export __ccxt_comment__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_comment__, 0),
               "#{name}: missing __ccxt_comment__/0"
      end
    end

    test "__ccxt_comment__/0 returns string or nil" do
      for {name, module} <- all_exchange_modules() do
        result = module.__ccxt_comment__()

        assert is_nil(result) or is_binary(result),
               "#{name}: __ccxt_comment__/0 should return string or nil"
      end
    end

    test "all modules export __ccxt_raw_endpoints__/0" do
      for {name, module} <- all_exchange_modules() do
        assert function_exported?(module, :__ccxt_raw_endpoints__, 0),
               "#{name}: missing __ccxt_raw_endpoints__/0"
      end
    end
  end

  describe "signing pattern distribution" do
    test "reports signing pattern coverage (100% expected)" do
      modules = all_exchange_modules()

      pattern_counts =
        modules
        |> Enum.map(fn {_name, module} ->
          signing = module.__ccxt_signing__()
          if signing, do: signing[:pattern], else: :none
        end)
        |> Enum.frequencies()
        |> Enum.sort_by(fn {_pattern, count} -> -count end)

      Logger.info("Signing pattern distribution (#{length(modules)} exchanges):")

      for {pattern, count} <- pattern_counts do
        pct = Float.round(count / length(modules) * 100, 1)
        Logger.info("  #{pattern}: #{count} (#{pct}%)")
      end

      # 100% should use valid patterns
      total_valid =
        pattern_counts
        |> Enum.filter(fn {pattern, _} -> pattern in @valid_patterns end)
        |> Enum.map(fn {_, count} -> count end)
        |> Enum.sum()

      assert total_valid == length(modules),
             "All #{length(modules)} exchanges should use valid patterns, but only #{total_valid} do"
    end
  end
end
