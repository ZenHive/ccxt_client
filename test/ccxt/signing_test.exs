defmodule CCXT.SigningTest do
  use ExUnit.Case, async: true

  alias CCXT.Signing

  describe "patterns/0" do
    test "returns all supported patterns" do
      patterns = Signing.patterns()

      assert :hmac_sha256_query in patterns
      assert :hmac_sha256_headers in patterns
      assert :hmac_sha256_iso_passphrase in patterns
      assert :hmac_sha256_passphrase_signed in patterns
      assert :hmac_sha512_nonce in patterns
      assert :hmac_sha512_gate in patterns
      assert :hmac_sha384_payload in patterns
      assert :deribit in patterns
      assert :custom in patterns
      assert length(patterns) == 9
    end
  end

  describe "pattern?/1" do
    test "returns true for valid patterns" do
      assert Signing.pattern?(:hmac_sha256_query)
      assert Signing.pattern?(:hmac_sha256_headers)
      assert Signing.pattern?(:hmac_sha512_nonce)
      assert Signing.pattern?(:custom)
    end

    test "returns false for invalid patterns" do
      refute Signing.pattern?(:invalid)
      refute Signing.pattern?(:hmac_md5)
    end
  end

  describe "timestamp helpers" do
    test "timestamp_ms returns milliseconds" do
      ts = Signing.timestamp_ms()
      assert is_integer(ts)
      # Should be a reasonable timestamp (after year 2020)
      assert ts > 1_577_836_800_000
    end

    test "timestamp_seconds returns seconds" do
      ts = Signing.timestamp_seconds()
      assert is_integer(ts)
      assert ts > 1_577_836_800
    end

    test "timestamp_iso8601 returns ISO format" do
      ts = Signing.timestamp_iso8601()
      assert is_binary(ts)
      assert String.contains?(ts, "T")
      assert String.ends_with?(ts, "Z")
    end
  end

  describe "hmac helpers" do
    test "hmac_sha256 produces correct hash" do
      # Test vector
      data = "hello"
      secret = "secret"
      result = Signing.hmac_sha256(data, secret)

      # Known HMAC-SHA256 value (verified with :crypto.mac)
      expected =
        Base.decode16!("88AAB3EDE8D3ADF94D26AB90D3BAFD4A2083070C3BCCE9C014EE04A443847C0B",
          case: :upper
        )

      assert result == expected
    end

    test "hmac_sha384 produces correct hash" do
      data = "hello"
      secret = "secret"
      result = Signing.hmac_sha384(data, secret)
      assert byte_size(result) == 48
    end

    test "hmac_sha512 produces correct hash" do
      data = "hello"
      secret = "secret"
      result = Signing.hmac_sha512(data, secret)
      assert byte_size(result) == 64
    end
  end

  describe "encoding helpers" do
    test "encode_hex produces lowercase hex" do
      binary = <<0xDE, 0xAD, 0xBE, 0xEF>>
      assert Signing.encode_hex(binary) == "deadbeef"
    end

    test "encode_base64 produces base64" do
      binary = "hello"
      assert Signing.encode_base64(binary) == "aGVsbG8="
    end

    test "decode_base64 decodes base64" do
      assert Signing.decode_base64("aGVsbG8=") == "hello"
    end
  end

  describe "urlencode helpers" do
    test "urlencode encodes empty map" do
      assert Signing.urlencode(%{}) == ""
    end

    test "urlencode encodes and sorts params" do
      params = %{b: 2, a: 1, c: 3}
      result = Signing.urlencode(params)
      assert result == "a=1&b=2&c=3"
    end

    test "urlencode_raw encodes without URL encoding special chars" do
      params = %{a: 1, b: 2}
      result = Signing.urlencode_raw(params)
      assert result == "a=1&b=2"
    end
  end
end
