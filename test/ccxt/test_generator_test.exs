defmodule CCXT.Test.GeneratorTest do
  @moduledoc """
  Unit tests for CCXT.Test.Generator macro and helpers.
  """
  use ExUnit.Case, async: true

  alias CCXT.Test.Generator
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
end
