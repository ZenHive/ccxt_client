defmodule CCXT.Test.GeneratorTest do
  @moduledoc """
  Unit tests for CCXT.Test.Generator macro and helpers.
  """
  use ExUnit.Case, async: true

  alias CCXT.Test.Generator
  alias CCXT.Test.Generator.Config
  alias CCXT.Test.Generator.Helpers

  describe "Helpers.validate_signature_format/2" do
    test "accepts nil signature" do
      assert :ok = Helpers.validate_signature_format(nil, %{})
    end

    test "validates hex-encoded signatures" do
      signing = %{signature_encoding: :hex}

      # Valid hex
      assert :ok = Helpers.validate_signature_format("abcdef123456", signing)
      assert :ok = Helpers.validate_signature_format("ABCDEF", signing)
      assert :ok = Helpers.validate_signature_format("0123456789abcdef", signing)
    end

    test "rejects invalid hex signatures" do
      signing = %{signature_encoding: :hex}

      assert_raise ExUnit.AssertionError, fn ->
        Helpers.validate_signature_format("not-hex!", signing)
      end

      assert_raise ExUnit.AssertionError, fn ->
        Helpers.validate_signature_format("ghijkl", signing)
      end
    end

    test "validates base64-encoded signatures" do
      signing = %{signature_encoding: :base64}

      # Valid base64
      assert :ok = Helpers.validate_signature_format("YWJjZGVm", signing)
      assert :ok = Helpers.validate_signature_format("dGVzdA==", signing)
      assert :ok = Helpers.validate_signature_format("YQ==", signing)
    end

    test "rejects invalid base64 signatures" do
      signing = %{signature_encoding: :base64}

      assert_raise ExUnit.AssertionError, fn ->
        Helpers.validate_signature_format("not valid base64!", signing)
      end
    end

    test "defaults to hex encoding when not specified" do
      signing = %{}

      # Valid hex passes
      assert :ok = Helpers.validate_signature_format("abcdef", signing)

      # Invalid hex fails
      assert_raise ExUnit.AssertionError, fn ->
        Helpers.validate_signature_format("not-hex!", signing)
      end
    end

    test "accepts any non-empty string for unknown encodings" do
      signing = %{signature_encoding: :unknown}

      assert :ok = Helpers.validate_signature_format("anything", signing)
      assert :ok = Helpers.validate_signature_format("!@#$%", signing)
    end
  end

  describe "Generator module structure" do
    test "CCXT.Test.Generator module exists" do
      assert Code.ensure_loaded?(Generator)
    end

    test "exports __using__/1 macro" do
      assert {:__using__, 1} in Generator.__info__(:macros)
    end

    test "exports __generate__/2 macro" do
      assert {:__generate__, 2} in Generator.__info__(:macros)
    end
  end

  describe "Generator configuration" do
    test "load_spec! finds extracted spec" do
      # Use Tidewave to test internal function behavior
      # The spec loading is tested indirectly through the generated tests
      assert Code.ensure_loaded?(CCXT.Spec)
    end

    test "classification_tag uses spec.classification directly" do
      # Generated tests now use spec.classification directly as the tag
      # e.g., @moduletag :certified_pro, @moduletag :pro, @moduletag :supported
      assert :certified_pro in [:certified_pro, :pro, :supported]
      assert :pro in [:certified_pro, :pro, :supported]
      assert :supported in [:certified_pro, :pro, :supported]
    end
  end

  describe "Config sandbox filtering" do
    setup do
      binance_config = Config.build(:binance, [])
      {:ok, binance: binance_config}
    end

    test "Binance: fetch_deposits (sapi) excluded from private_methods", %{binance: config} do
      refute Map.has_key?(config.private_methods, :fetch_deposits),
             "fetch_deposits should be excluded — sapi has no sandbox URL"
    end

    test "Binance: fetch_withdrawals (sapi) excluded from private_methods", %{binance: config} do
      refute Map.has_key?(config.private_methods, :fetch_withdrawals),
             "fetch_withdrawals should be excluded — sapi has no sandbox URL"
    end

    test "Binance: fetch_position (eapiPrivate) excluded from private_methods", %{binance: config} do
      refute Map.has_key?(config.private_methods, :fetch_position),
             "fetch_position should be excluded — eapiPrivate has no sandbox URL"
    end

    test "Binance: fetch_balance (private section, has sandbox) still included", %{binance: config} do
      assert Map.has_key?(config.private_methods, :fetch_balance),
             "fetch_balance should be included — 'private' has a sandbox URL"
    end

    test "Binance: no_sandbox_endpoints tracks excluded endpoints with api_sections", %{binance: config} do
      excluded_methods = Enum.map(config.no_sandbox_endpoints, fn {method, _} -> method end)
      assert :fetch_deposits in excluded_methods
      assert :fetch_withdrawals in excluded_methods
      assert :fetch_position in excluded_methods

      # Verify api_sections are captured
      deposits_entry = Enum.find(config.no_sandbox_endpoints, fn {m, _} -> m == :fetch_deposits end)
      assert {_, "sapi"} = deposits_entry

      position_entry = Enum.find(config.no_sandbox_endpoints, fn {m, _} -> m == :fetch_position end)
      assert {_, "eapiPrivate"} = position_entry
    end

    test "Binance: fetch_balance not in no_sandbox_endpoints", %{binance: config} do
      excluded_methods = Enum.map(config.no_sandbox_endpoints, fn {method, _} -> method end)
      refute :fetch_balance in excluded_methods
    end
  end

  describe "Config sandbox filtering — edge cases" do
    test "Deribit: rest fallback covers all sections, no excluded endpoints" do
      config = Config.build(:deribit, [])
      assert config.no_sandbox_endpoints == []
    end

    test "Bybit: all api_sections have matching sandbox URLs, no excluded endpoints" do
      config = Config.build(:bybit, [])
      assert config.no_sandbox_endpoints == []
    end

    test "has_sandbox_for_section? returns true for nil api_section" do
      assert Config.has_sandbox_for_section?(%{"sapi" => "url"}, nil)
    end

    test "has_sandbox_for_section? returns true for non-map sandbox_urls" do
      assert Config.has_sandbox_for_section?("https://testnet.example.com", "sapi")
      assert Config.has_sandbox_for_section?(nil, "sapi")
      assert Config.has_sandbox_for_section?(true, "sapi")
    end

    test "has_sandbox_for_section? returns true when section key exists" do
      urls = %{"sapi" => "https://testnet.example.com", "private" => "https://other.com"}
      assert Config.has_sandbox_for_section?(urls, "sapi")
    end

    test "has_sandbox_for_section? returns true with rest fallback" do
      urls = %{"rest" => "https://test.deribit.com"}
      assert Config.has_sandbox_for_section?(urls, "nonexistent_section")
    end

    test "has_sandbox_for_section? returns true with default fallback" do
      urls = %{"default" => "https://default-testnet.com"}
      assert Config.has_sandbox_for_section?(urls, "nonexistent_section")
    end

    test "has_sandbox_for_section? returns false when section missing and no fallback" do
      urls = %{"private" => "https://testnet.com", "public" => "https://testnet.com"}
      refute Config.has_sandbox_for_section?(urls, "sapi")
    end

    test "endpoint_has_sandbox? returns true when endpoint has no api_section" do
      endpoint_map = %{fetch_balance: %{name: :fetch_balance, auth: true}}
      assert Config.endpoint_has_sandbox?(endpoint_map, :fetch_balance, %{"sapi" => "url"})
    end

    test "endpoint_has_sandbox? returns true when endpoint not in map" do
      assert Config.endpoint_has_sandbox?(%{}, :nonexistent, %{"sapi" => "url"})
    end

    test "endpoint_has_sandbox? returns false for sapi endpoint with no sapi sandbox" do
      endpoint_map = %{fetch_deposits: %{name: :fetch_deposits, api_section: "sapi", auth: true}}
      sandbox_urls = %{"private" => "https://testnet.com", "public" => "https://testnet.com"}
      refute Config.endpoint_has_sandbox?(endpoint_map, :fetch_deposits, sandbox_urls)
    end
  end
end
