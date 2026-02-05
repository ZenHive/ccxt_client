defmodule CCXT.Test.Generator.SigningTests do
  @moduledoc """
  Generates comprehensive signing verification tests from exchange specs.

  These tests validate that signing implementations produce correctly formatted
  signatures without hitting exchange APIs. All tests are tagged with `@tag :signing`.

  ## Generated Tests

  For each exchange with a signing configuration:

  1. **signing config exists and is valid** - Validates signing config structure
  2. **signing module produces headers** - Basic signing produces output
  3. **signature has expected format** - Pattern-specific signature validation
  4. **required headers are present** - API key, timestamp, signature headers
  5. **timestamp format is correct** - Validates timestamp matches pattern expectations
  6. **passphrase header present** (if required) - For OKX, KuCoin, etc.

  ## Pattern-Specific Validation

  | Pattern | Signature Format | Timestamp | Extra Headers |
  |---------|-----------------|-----------|---------------|
  | `:hmac_sha256_query` | 64-char hex in query | milliseconds | API key header |
  | `:hmac_sha256_headers` | 64-char hex in header | milliseconds | API key, timestamp |
  | `:hmac_sha256_iso_passphrase` | base64 in header | ISO8601 | passphrase |
  | `:hmac_sha256_passphrase_signed` | base64 in header | milliseconds | signed passphrase |
  | `:hmac_sha512_nonce` | base64 in header | nonce | API key |
  | `:hmac_sha512_gate` | 128-char hex | seconds | timestamp |
  | `:hmac_sha384_payload` | base64 | nonce | API key |

  """

  @doc """
  Generates signing verification tests.

  Returns a quoted block containing all signing tests, or nil if no signing config.
  """
  @spec generate(atom() | nil, boolean()) :: Macro.t() | nil
  def generate(nil, _has_passphrase), do: nil

  # Note: signing_pattern parameter is used only for nil check above.
  # Actual pattern is retrieved at runtime via @module.__ccxt_signing__()
  # to ensure tests use the live spec value, not a compile-time snapshot.
  def generate(_signing_pattern, has_passphrase) do
    quote do
      alias CCXT.Test.Generator.Helpers.Signature, as: SignatureHelper

      describe "signing verification" do
        @tag :signing
        test "signing config exists and is valid", %{credentials: credentials, api_url: api_url} do
          require_credentials!(credentials, @exchange_id, Keyword.put(@credential_opts, :api_url, api_url))

          signing = @module.__ccxt_signing__()

          assert is_map(signing), "signing config should be a map"
          assert is_atom(signing.pattern), "signing.pattern should be an atom"

          assert signing.pattern in CCXT.Signing.patterns(),
                 "Unknown signing pattern: #{signing.pattern}"

          Logger.info("Signing pattern: #{signing.pattern}")
        end

        @tag :signing
        test "signing module produces headers", %{credentials: credentials, api_url: api_url} do
          require_credentials!(credentials, @exchange_id, Keyword.put(@credential_opts, :api_url, api_url))

          signing = @module.__ccxt_signing__()
          pattern = signing.pattern

          request = %{
            method: :get,
            path: "/api/v1/account",
            params: %{},
            body: nil
          }

          signed = CCXT.Signing.sign(pattern, request, credentials, signing)

          assert is_list(signed.headers), "signed request should have headers"
          assert [_ | _] = signed.headers, "signed request should have at least one header"
          assert is_binary(signed.url), "signed request should have URL"

          Logger.info(
            "Signing produces #{length(signed.headers)} headers, " <>
              "pattern=#{pattern}"
          )
        end

        @tag :signing
        test "signature has expected format", %{credentials: credentials, api_url: api_url} do
          require_credentials!(credentials, @exchange_id, Keyword.put(@credential_opts, :api_url, api_url))

          signing = @module.__ccxt_signing__()
          pattern = signing.pattern

          request = %{
            method: :post,
            path: "/api/v1/order",
            params: %{symbol: "BTCUSDT", side: "buy", type: "limit", quantity: 0.001, price: 50_000},
            body: nil
          }

          signed = CCXT.Signing.sign(pattern, request, credentials, signing)

          SignatureHelper.validate_signature_for_pattern(signed, signing, pattern)

          Logger.info("Signature format valid for pattern=#{pattern}")
        end

        @tag :signing
        test "required headers are present", %{credentials: credentials, api_url: api_url} do
          require_credentials!(credentials, @exchange_id, Keyword.put(@credential_opts, :api_url, api_url))

          signing = @module.__ccxt_signing__()
          pattern = signing.pattern

          request = %{
            method: :get,
            path: "/api/v1/account",
            params: %{},
            body: nil
          }

          signed = CCXT.Signing.sign(pattern, request, credentials, signing)
          headers_map = Map.new(signed.headers)

          SignatureHelper.validate_required_headers(headers_map, signing, pattern)

          Logger.info("All required headers present for pattern=#{pattern}")
        end

        @tag :signing
        test "timestamp format is correct", %{credentials: credentials, api_url: api_url} do
          require_credentials!(credentials, @exchange_id, Keyword.put(@credential_opts, :api_url, api_url))

          signing = @module.__ccxt_signing__()
          pattern = signing.pattern

          request = %{
            method: :get,
            path: "/api/v1/time",
            params: %{},
            body: nil
          }

          signed = CCXT.Signing.sign(pattern, request, credentials, signing)
          headers_map = Map.new(signed.headers)

          SignatureHelper.validate_timestamp_format(headers_map, signed, signing, pattern)

          Logger.info("Timestamp format valid for pattern=#{pattern}")
        end

        unquote(generate_passphrase_test(has_passphrase))
      end
    end
  end

  # Generate passphrase test only if exchange requires passphrase
  defp generate_passphrase_test(false), do: nil

  defp generate_passphrase_test(true) do
    quote do
      @tag :signing
      @tag :passphrase
      test "passphrase header is present", %{credentials: credentials, api_url: api_url} do
        require_credentials!(credentials, @exchange_id, Keyword.put(@credential_opts, :api_url, api_url))

        signing = @module.__ccxt_signing__()
        pattern = signing.pattern

        request = %{
          method: :get,
          path: "/api/v1/account",
          params: %{},
          body: nil
        }

        signed = CCXT.Signing.sign(pattern, request, credentials, signing)
        headers_map = Map.new(signed.headers)

        passphrase_header = signing[:passphrase_header]

        if passphrase_header do
          assert Map.has_key?(headers_map, passphrase_header),
                 "Expected passphrase header '#{passphrase_header}' to be present. " <>
                   "Headers: #{inspect(Map.keys(headers_map))}"

          passphrase_value = headers_map[passphrase_header]
          assert is_binary(passphrase_value), "Passphrase should be a string"
          # Passphrase can be empty string if not provided, but header must exist

          Logger.info("Passphrase header '#{passphrase_header}' present")
        else
          Logger.info("No passphrase header configured for this exchange")
        end
      end
    end
  end
end
