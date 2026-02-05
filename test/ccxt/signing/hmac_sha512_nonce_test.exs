defmodule CCXT.Signing.HmacSha512NonceTest do
  use ExUnit.Case, async: true

  alias CCXT.Credentials
  alias CCXT.Signing
  alias CCXT.Signing.HmacSha512Nonce

  # Test credentials (not real)
  # Note: Kraken secrets are base64 encoded
  @api_key "test_kraken_api_key"
  @secret Base.encode64("test_kraken_secret_key_32bytes!!")

  @kraken_config %{
    api_key_header: "API-Key",
    signature_header: "API-Sign",
    nonce_key: "nonce",
    body_encoding: :urlencoded
  }

  setup do
    credentials = %Credentials{
      api_key: @api_key,
      secret: @secret,
      sandbox: false
    }

    {:ok, credentials: credentials}
  end

  describe "sign/3" do
    test "signs request with nonce in body", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/0/private/Balance",
        body: nil,
        params: %{}
      }

      result = HmacSha512Nonce.sign(request, credentials, @kraken_config)

      # Body should contain nonce
      assert is_binary(result.body)
      assert String.contains?(result.body, "nonce=")

      # Check headers
      headers_map = Map.new(result.headers)
      assert headers_map["API-Key"] == @api_key
      assert is_binary(headers_map["API-Sign"])

      # Signature should be base64 encoded
      signature = headers_map["API-Sign"]
      assert {:ok, decoded} = Base.decode64(signature)
      # HMAC-SHA512 produces 64 bytes
      assert byte_size(decoded) == 64
    end

    test "includes params in body with nonce", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/0/private/AddOrder",
        body: nil,
        params: %{
          pair: "XBTUSD",
          type: "buy",
          ordertype: "market",
          volume: "0.001"
        }
      }

      result = HmacSha512Nonce.sign(request, credentials, @kraken_config)

      # Body should contain nonce and params
      assert String.contains?(result.body, "nonce=")
      assert String.contains?(result.body, "pair=XBTUSD")
      assert String.contains?(result.body, "type=buy")

      # Content-Type should be form-urlencoded
      headers_map = Map.new(result.headers)
      assert headers_map["Content-Type"] == "application/x-www-form-urlencoded"
    end

    test "nonce is incrementing", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/0/private/Balance",
        body: nil,
        params: %{}
      }

      result1 = HmacSha512Nonce.sign(request, credentials, @kraken_config)
      result2 = HmacSha512Nonce.sign(request, credentials, @kraken_config)

      # Extract nonces from bodies
      nonce1 = extract_nonce(result1.body)
      nonce2 = extract_nonce(result2.body)

      # Nonce should be different and strictly increasing
      assert nonce2 > nonce1
    end

    test "nonce is timestamp-based (microseconds)", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/0/private/Balance",
        body: nil,
        params: %{}
      }

      result = HmacSha512Nonce.sign(request, credentials, @kraken_config)
      nonce = extract_nonce(result.body)

      # Microsecond timestamps are 16 digits (e.g., 1736500000000000)
      # Kraken requires at least 13 digits (millisecond range)
      nonce_string = Integer.to_string(nonce)
      assert String.length(nonce_string) >= 13, "Nonce should be timestamp-based (13+ digits), got: #{nonce_string}"

      # Nonce should be close to current time (within 1 second)
      current_microseconds = System.system_time(:microsecond)
      time_diff_ms = abs(current_microseconds - nonce) / 1000
      assert time_diff_ms < 1000, "Nonce should be close to current time, diff: #{time_diff_ms}ms"
    end
  end

  describe "signature format" do
    test "signature is valid base64", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/0/private/Balance",
        body: nil,
        params: %{}
      }

      result = HmacSha512Nonce.sign(request, credentials, @kraken_config)

      headers_map = Map.new(result.headers)
      signature = headers_map["API-Sign"]

      # Should be valid base64
      assert {:ok, decoded} = Base.decode64(signature)
      # Should be 64 bytes (SHA512)
      assert byte_size(decoded) == 64
    end
  end

  describe "dispatch via Signing.sign/4" do
    test "dispatches to HmacSha512Nonce", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/test",
        body: nil,
        params: %{}
      }

      result = Signing.sign(:hmac_sha512_nonce, request, credentials, @kraken_config)

      assert is_binary(result.url)
      headers_map = Map.new(result.headers)
      assert Map.has_key?(headers_map, "API-Sign")
    end
  end

  describe "edge cases" do
    test "handles empty string credentials (produces output but API will reject)" do
      # Kraken secret is base64 encoded, empty string is valid base64
      credentials = %Credentials{api_key: "", secret: "", sandbox: false}

      request = %{
        method: :post,
        path: "/0/private/Balance",
        body: nil,
        params: %{}
      }

      result = HmacSha512Nonce.sign(request, credentials, @kraken_config)

      headers_map = Map.new(result.headers)
      assert headers_map["API-Key"] == ""
      # Signature is still generated (will fail at exchange)
      assert is_binary(headers_map["API-Sign"])
    end

    test "handles special characters in params", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/0/private/AddOrder",
        body: nil,
        params: %{
          pair: "XBT/USD",
          type: "buy",
          ordertype: "limit",
          filter: "status=open&type=limit"
        }
      }

      result = HmacSha512Nonce.sign(request, credentials, @kraken_config)

      # Body should contain URL-encoded params
      # Both encoded (%2F) and unencoded (/) forms are valid - depends on implementation
      assert String.contains?(result.body, "pair=XBT%2FUSD") or
               String.contains?(result.body, "pair=XBT/USD")

      assert String.contains?(result.body, "filter=")
    end

    test "handles empty params", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/0/private/Balance",
        body: nil,
        params: %{}
      }

      result = HmacSha512Nonce.sign(request, credentials, @kraken_config)

      # Body should only contain nonce
      assert String.contains?(result.body, "nonce=")
      # Should not have extra & at the end or start
      refute String.starts_with?(result.body, "&")
    end

    test "nonce is always added to body", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/0/private/AddOrder",
        body: nil,
        params: %{pair: "XBTUSD", type: "buy", ordertype: "market", volume: "0.001"}
      }

      result = HmacSha512Nonce.sign(request, credentials, @kraken_config)

      # Nonce should be in body along with params
      assert String.contains?(result.body, "nonce=")
      assert String.contains?(result.body, "pair=XBTUSD")
      assert String.contains?(result.body, "type=buy")
    end

    test "path is used in signature calculation", %{credentials: credentials} do
      request1 = %{
        method: :post,
        path: "/0/private/Balance",
        body: nil,
        params: %{}
      }

      request2 = %{
        method: :post,
        path: "/0/private/TradeBalance",
        body: nil,
        params: %{}
      }

      result1 = HmacSha512Nonce.sign(request1, credentials, @kraken_config)
      result2 = HmacSha512Nonce.sign(request2, credentials, @kraken_config)

      headers1 = Map.new(result1.headers)
      headers2 = Map.new(result2.headers)

      # Different paths should produce different signatures
      refute headers1["API-Sign"] == headers2["API-Sign"]
    end
  end

  # Helper to extract nonce value from body
  defp extract_nonce(body) do
    body
    |> String.split("&")
    |> Enum.find(&String.starts_with?(&1, "nonce="))
    |> String.replace("nonce=", "")
    |> String.to_integer()
  end
end
