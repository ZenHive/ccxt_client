defmodule CCXT.SigningPatternCoverageTest do
  @moduledoc """
  Cross-cutting tests ensuring the test helper's signature validation
  covers all signing patterns defined in CCXT.Signing.

  Prevents drift between:
  - CCXT.Signing.patterns/0 (source of truth)
  - SignatureHelper.validate_signature_for_pattern/3 (test validation)
  - Exchange specs (what exchanges actually use)
  """

  use ExUnit.Case, async: true

  alias CCXT.Test.ExchangeHelper

  # Patterns handled by explicit function clauses in SignatureHelper
  @explicit_clause_patterns [:hmac_sha256_query, :deribit, :custom]

  # Patterns handled by the @pattern_algorithms map in the catch-all clause
  @pattern_algorithms_patterns [
    :hmac_sha256_headers,
    :hmac_sha256_iso_passphrase,
    :hmac_sha256_passphrase_signed,
    :hmac_sha512_nonce,
    :hmac_sha512_gate,
    :hmac_sha384_payload
  ]

  @all_handled_patterns @explicit_clause_patterns ++ @pattern_algorithms_patterns

  describe "signing pattern test coverage" do
    test "every CCXT.Signing.patterns/0 pattern is handled by the test helper" do
      signing_patterns = CCXT.Signing.patterns()
      handled = MapSet.new(@all_handled_patterns)

      unhandled = Enum.reject(signing_patterns, &MapSet.member?(handled, &1))

      assert unhandled == [],
             "These signing patterns from CCXT.Signing.patterns/0 are NOT handled by " <>
               "SignatureHelper.validate_signature_for_pattern/3: #{inspect(unhandled)}. " <>
               "Add explicit clauses or @pattern_algorithms entries in " <>
               "test/support/test_generator/helpers/signature.ex"
    end

    test "no stale patterns in test helper that aren't in CCXT.Signing.patterns/0" do
      signing_patterns = MapSet.new(CCXT.Signing.patterns())

      stale = Enum.reject(@all_handled_patterns, &MapSet.member?(signing_patterns, &1))

      assert stale == [],
             "These patterns are handled by SignatureHelper but no longer exist " <>
               "in CCXT.Signing.patterns/0: #{inspect(stale)}. " <>
               "Remove the stale clauses from test/support/test_generator/helpers/signature.ex"
    end

    test "all loaded specs have signing patterns the test helper can validate" do
      spec_paths = ExchangeHelper.all_available_spec_paths()
      assert spec_paths != [], "No exchange specs found — cannot verify signing coverage"

      handled = MapSet.new(@all_handled_patterns)

      problems =
        for path <- spec_paths, reduce: [] do
          acc ->
            spec = CCXT.Spec.load!(path)

            case spec.signing do
              nil ->
                acc

              %{pattern: pattern} ->
                if MapSet.member?(handled, pattern) do
                  acc
                else
                  [{spec.id, pattern} | acc]
                end

              _other ->
                acc
            end
        end

      assert problems == [],
             "These exchanges use signing patterns not handled by SignatureHelper: " <>
               "#{inspect(Enum.reverse(problems))}. " <>
               "Add validation for these patterns in test/support/test_generator/helpers/signature.ex"
    end
  end
end
