defmodule CCXT.Test.Generator.Helpers.Signature do
  @moduledoc """
  Signature format validation for generated tests.

  Validates cryptographic signatures match expected encoding formats
  (hex, base64) based on exchange signing configuration and pattern.

  ## Pattern-Specific Validation

  | Pattern | Signature Location | Encoding | Length |
  |---------|-------------------|----------|--------|
  | `:hmac_sha256_query` | Query string | hex | 64 chars |
  | `:hmac_sha256_headers` | Header | hex/base64 | 64 chars (hex) or 44 chars (base64) |
  | `:hmac_sha256_iso_passphrase` | Header | base64 | 44 chars |
  | `:hmac_sha256_passphrase_signed` | Header | base64 | 44 chars |
  | `:hmac_sha512_nonce` | Header | base64 | 88 chars |
  | `:hmac_sha512_gate` | Header | hex | 128 chars |
  | `:hmac_sha384_payload` | Header | base64 | 64 chars |

  """

  import ExUnit.Assertions

  require Logger

  # =============================================================================
  # Signature Length Constants
  # =============================================================================
  # SHA256 = 32 bytes -> 64 hex chars or 44 base64 chars
  # SHA384 = 48 bytes -> 96 hex chars or 64 base64 chars
  # SHA512 = 64 bytes -> 128 hex chars or 88 base64 chars

  @signature_lengths %{
    sha256: %{hex: 64, base64: 44},
    sha384: %{hex: 96, base64: 64},
    sha512: %{hex: 128, base64: 88}
  }

  # =============================================================================
  # Timestamp Constants
  # =============================================================================

  @timestamp_digits %{
    milliseconds: 13,
    seconds: 10
  }

  # =============================================================================
  # Pattern Configuration Maps
  # =============================================================================

  # Map pattern to hash algorithm
  @pattern_algorithms %{
    hmac_sha256_headers: :sha256,
    hmac_sha256_iso_passphrase: :sha256,
    hmac_sha256_passphrase_signed: :sha256,
    hmac_sha512_nonce: :sha512,
    hmac_sha512_gate: :sha512,
    hmac_sha384_payload: :sha384
  }

  # Map pattern to timestamp format
  @pattern_timestamp_formats %{
    hmac_sha256_headers: :milliseconds,
    hmac_sha256_iso_passphrase: :iso8601,
    hmac_sha256_passphrase_signed: :milliseconds,
    hmac_sha512_gate: :seconds
  }

  # Patterns that use nonce instead of timestamp
  @nonce_based_patterns [:hmac_sha512_nonce, :hmac_sha384_payload]

  # Map pattern to required header keys (resolved from signing config at runtime)
  @pattern_required_headers %{
    hmac_sha256_query: [:api_key_header],
    hmac_sha256_headers: [:api_key_header, :timestamp_header, :signature_header],
    hmac_sha256_iso_passphrase: [:api_key_header, :timestamp_header, :signature_header, :passphrase_header],
    hmac_sha256_passphrase_signed: [:api_key_header, :timestamp_header, :signature_header, :passphrase_header],
    hmac_sha512_nonce: [:api_key_header, :signature_header],
    hmac_sha512_gate: [:api_key_header, :timestamp_header, :signature_header],
    hmac_sha384_payload: [:api_key_header, :signature_header]
  }

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @typedoc """
  Signing pattern atom identifying the authentication method.

  Supported patterns:
  - `:hmac_sha256_query` - Binance-style (signature in query string)
  - `:hmac_sha256_headers` - Bybit-style (signature in headers)
  - `:hmac_sha256_iso_passphrase` - OKX-style (ISO timestamp + passphrase)
  - `:hmac_sha256_passphrase_signed` - KuCoin-style (signed passphrase)
  - `:hmac_sha512_nonce` - Kraken-style (nonce-based)
  - `:hmac_sha512_gate` - Gate.io-style (seconds timestamp)
  - `:hmac_sha384_payload` - Bitfinex-style (payload signing)
  - `:custom` - Exchange-specific custom implementation
  """
  @type signing_pattern ::
          :hmac_sha256_query
          | :hmac_sha256_headers
          | :hmac_sha256_iso_passphrase
          | :hmac_sha256_passphrase_signed
          | :hmac_sha512_nonce
          | :hmac_sha512_gate
          | :hmac_sha384_payload
          | :custom

  @typedoc """
  Signing configuration map from exchange spec.

  Common keys:
  - `:pattern` - The signing pattern atom
  - `:api_key_header` - Header name for API key
  - `:signature_header` - Header name for signature
  - `:timestamp_header` - Header name for timestamp
  - `:passphrase_header` - Header name for passphrase (if required)
  - `:signature_encoding` - `:hex` or `:base64`
  """
  @type signing_config :: %{
          :pattern => signing_pattern(),
          optional(:api_key_header) => String.t(),
          optional(:signature_header) => String.t(),
          optional(:sign_header) => String.t(),
          optional(:timestamp_header) => String.t(),
          optional(:passphrase_header) => String.t(),
          optional(:signature_encoding) => :hex | :base64,
          optional(:signature_key) => String.t(),
          optional(:timestamp_key) => String.t(),
          optional(atom()) => term()
        }

  @typedoc """
  Signed request returned by `CCXT.Signing.sign/4`.

  Contains the URL (possibly with signature in query string) and headers list.
  """
  @type signed_request :: %{
          :url => String.t(),
          :headers => [{String.t(), String.t()}],
          optional(atom()) => term()
        }

  @doc """
  Validates signature format based on encoding type.

  Basic validation that checks hex vs base64 encoding.
  """
  @spec validate_signature_format(String.t() | nil, signing_config()) :: :ok
  def validate_signature_format(nil, _signing) do
    # No signature header - may be in query string for some patterns
    :ok
  end

  def validate_signature_format(signature, signing) do
    encoding = signing[:signature_encoding] || :hex

    case encoding do
      :hex ->
        assert String.match?(signature, ~r/^[a-fA-F0-9]+$/),
               "Hex signature should contain only hex characters"

      :base64 ->
        assert String.match?(signature, ~r/^[A-Za-z0-9+\/]+=*$/),
               "Base64 signature should be valid base64"

      _ ->
        assert String.length(signature) > 0
    end

    :ok
  end

  @doc """
  Validates signature for a specific signing pattern.

  Performs comprehensive validation including:
  - Signature encoding format (hex vs base64)
  - Signature length matches algorithm expectations
  - Signature location (header vs query string)
  """
  @spec validate_signature_for_pattern(signed_request(), signing_config(), signing_pattern()) :: :ok
  def validate_signature_for_pattern(signed, signing, :hmac_sha256_query) do
    validate_query_signature(signed, signing)
  end

  def validate_signature_for_pattern(_signed, _signing, :custom) do
    # Custom signing pattern - skip standard validation
    :ok
  end

  def validate_signature_for_pattern(signed, signing, pattern) do
    case Map.get(@pattern_algorithms, pattern) do
      nil ->
        Logger.warning("Unknown signing pattern: #{pattern}")
        :ok

      algorithm ->
        validate_header_signature(signed, signing, algorithm)
    end
  end

  @doc """
  Validates that all required headers are present for the signing pattern.
  """
  @spec validate_required_headers(map(), signing_config(), signing_pattern()) :: :ok
  def validate_required_headers(headers_map, signing, pattern) do
    required = required_headers_for_pattern(signing, pattern)
    found_headers = headers_map |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()

    for header <- required do
      assert Map.has_key?(headers_map, header),
             "Expected header '#{header}' to be present. " <>
               "Found: #{Enum.join(found_headers, ", ")}"
    end

    :ok
  end

  @doc """
  Validates timestamp format matches pattern expectations.
  """
  @spec validate_timestamp_format(map(), signed_request(), signing_config(), signing_pattern()) :: :ok
  def validate_timestamp_format(_headers_map, signed, signing, :hmac_sha256_query) do
    validate_query_timestamp(signed.url, signing)
  end

  def validate_timestamp_format(_headers_map, _signed, _signing, pattern) when pattern in @nonce_based_patterns do
    # Nonce-based pattern - no timestamp header expected
    :ok
  end

  def validate_timestamp_format(_headers_map, _signed, _signing, :custom) do
    # Custom pattern - skip timestamp validation
    :ok
  end

  def validate_timestamp_format(headers_map, _signed, signing, pattern) do
    case Map.get(@pattern_timestamp_formats, pattern) do
      nil ->
        :ok

      format ->
        validate_header_timestamp(headers_map, signing, format)
    end
  end

  @doc false
  # Validates signature in query string (Binance-style hmac_sha256_query pattern).
  defp validate_query_signature(signed, signing) do
    signature_key = signing[:signature_key] || "signature"
    encoding = signing[:signature_encoding] || :hex

    # Parse the URL to get the signature from query string
    uri = URI.parse(signed.url)
    query_params = URI.decode_query(uri.query || "")

    signature = query_params[signature_key]

    assert signature != nil,
           "Expected signature in query string with key '#{signature_key}'. " <>
             "URL: #{signed.url}"

    validate_signature_encoding(signature, encoding, :sha256)
  end

  @doc false
  # Validates signature in HTTP headers (most signing patterns except query-based).
  defp validate_header_signature(signed, signing, algorithm) do
    sig_header = signing[:signature_header] || signing[:sign_header]
    encoding = signing[:signature_encoding] || :hex

    headers_map = Map.new(signed.headers)
    signature = headers_map[sig_header]

    if sig_header do
      assert signature != nil,
             "Expected signature in header '#{sig_header}'. " <>
               "Headers: #{inspect(Map.keys(headers_map))}"

      validate_signature_encoding(signature, encoding, algorithm)
    else
      # No signature header configured - signature may be in query string
      :ok
    end
  end

  @doc false
  # Validates signature encoding (hex/base64) and length matches algorithm expectations.
  defp validate_signature_encoding(signature, encoding, algorithm) do
    case encoding do
      :hex ->
        assert String.match?(signature, ~r/^[a-fA-F0-9]+$/),
               "Hex signature should contain only hex characters. Got: #{signature}"

        expected_length = expected_hex_length(algorithm)

        assert String.length(signature) == expected_length,
               "Expected #{algorithm} hex signature to be #{expected_length} chars, " <>
                 "got #{String.length(signature)}"

      :base64 ->
        assert String.match?(signature, ~r/^[A-Za-z0-9+\/]+=*$/),
               "Base64 signature should be valid base64. Got: #{signature}"

        expected_length = expected_base64_length(algorithm)
        actual_length = String.length(signature)

        # Base64 padding causes ±2 char variation:
        # - No padding: exact length (e.g., 44 chars for SHA256)
        # - 1-2 padding chars (=, ==): length varies by 1-2 chars
        # - Some implementations omit padding entirely: may be 1-2 shorter
        assert actual_length >= expected_length - 2 and actual_length <= expected_length + 2,
               "Expected #{algorithm} base64 signature to be ~#{expected_length} chars, " <>
                 "got #{actual_length}"

      _ ->
        assert String.length(signature) > 0, "Signature should not be empty"
    end

    :ok
  end

  @doc false
  # Returns expected hex signature length for the given hash algorithm.
  # Defaults to SHA256 length for unrecognized algorithms.
  @spec expected_hex_length(atom()) :: pos_integer()
  defp expected_hex_length(:sha256), do: @signature_lengths.sha256.hex
  defp expected_hex_length(:sha384), do: @signature_lengths.sha384.hex
  defp expected_hex_length(:sha512), do: @signature_lengths.sha512.hex

  @doc false
  # Returns expected base64 signature length for the given hash algorithm.
  # Defaults to SHA256 length for unrecognized algorithms.
  @spec expected_base64_length(atom()) :: pos_integer()
  defp expected_base64_length(:sha256), do: @signature_lengths.sha256.base64
  defp expected_base64_length(:sha384), do: @signature_lengths.sha384.base64
  defp expected_base64_length(:sha512), do: @signature_lengths.sha512.base64

  @doc false
  # Returns expected timestamp digit count for the given precision.
  @spec expected_timestamp_digits(:milliseconds | :seconds) :: pos_integer()
  defp expected_timestamp_digits(:milliseconds), do: @timestamp_digits.milliseconds
  defp expected_timestamp_digits(:seconds), do: @timestamp_digits.seconds

  @doc false
  # Resolves required header names from signing config based on pattern.
  defp required_headers_for_pattern(signing, pattern) do
    header_keys = Map.get(@pattern_required_headers, pattern, [])

    header_keys
    |> Enum.map(&signing[&1])
    |> Enum.filter(& &1)
  end

  @doc false
  # Validates timestamp in query string (Binance-style patterns).
  defp validate_query_timestamp(url, signing) do
    timestamp_key = signing[:timestamp_key] || "timestamp"

    uri = URI.parse(url)
    query_params = URI.decode_query(uri.query || "")

    timestamp = query_params[timestamp_key]

    assert timestamp != nil,
           "Expected timestamp in query string with key '#{timestamp_key}'. URL: #{url}"

    # Milliseconds timestamp should be 13 digits
    digits = expected_timestamp_digits(:milliseconds)

    assert String.match?(timestamp, ~r/^\d{#{digits}}$/),
           "Expected milliseconds timestamp (#{digits} digits), got: #{timestamp}"

    :ok
  end

  @doc false
  # Validates timestamp in HTTP headers based on expected format.
  defp validate_header_timestamp(headers_map, signing, format) do
    timestamp_header = signing[:timestamp_header]

    if timestamp_header do
      timestamp = headers_map[timestamp_header]

      assert timestamp != nil,
             "Expected timestamp in header '#{timestamp_header}'. " <>
               "Headers: #{inspect(Map.keys(headers_map))}"

      validate_timestamp_value(timestamp, format)
    else
      :ok
    end
  end

  @doc false
  defp validate_timestamp_value(timestamp, :milliseconds) do
    digits = expected_timestamp_digits(:milliseconds)

    assert String.match?(timestamp, ~r/^\d{#{digits}}$/),
           "Expected milliseconds timestamp (#{digits} digits), got: #{timestamp}"

    :ok
  end

  defp validate_timestamp_value(timestamp, :seconds) do
    digits = expected_timestamp_digits(:seconds)

    assert String.match?(timestamp, ~r/^\d{#{digits}}$/),
           "Expected seconds timestamp (#{digits} digits), got: #{timestamp}"

    :ok
  end

  defp validate_timestamp_value(timestamp, :iso8601) do
    # ISO8601 format: 2024-01-15T10:30:00.000Z
    assert String.match?(timestamp, ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/),
           "Expected ISO8601 timestamp, got: #{timestamp}"

    :ok
  end
end
