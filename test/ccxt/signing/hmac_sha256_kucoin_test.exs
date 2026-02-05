defmodule CCXT.Signing.HmacSha256KucoinTest do
  use ExUnit.Case, async: true

  alias CCXT.Credentials
  alias CCXT.Signing
  alias CCXT.Signing.HmacSha256Kucoin

  # Test credentials (not real)
  @api_key "test_kucoin_api_key"
  @secret "test_kucoin_secret"
  @passphrase "test_kucoin_passphrase"

  @kucoin_config %{
    api_key_header: "KC-API-KEY",
    timestamp_header: "KC-API-TIMESTAMP",
    signature_header: "KC-API-SIGN",
    passphrase_header: "KC-API-PASSPHRASE",
    api_key_version_header: "KC-API-KEY-VERSION",
    api_key_version: "2"
  }

  setup do
    credentials = %Credentials{
      api_key: @api_key,
      secret: @secret,
      password: @passphrase,
      sandbox: true
    }

    {:ok, credentials: credentials}
  end

  describe "sign/3 for GET requests" do
    test "signs GET request with all required headers", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v1/accounts",
        body: nil,
        params: %{}
      }

      result = HmacSha256Kucoin.sign(request, credentials, @kucoin_config)

      headers_map = Map.new(result.headers)

      # Check all required headers present
      assert headers_map["KC-API-KEY"] == @api_key
      assert is_binary(headers_map["KC-API-TIMESTAMP"])
      assert is_binary(headers_map["KC-API-SIGN"])
      assert is_binary(headers_map["KC-API-PASSPHRASE"])
      assert headers_map["KC-API-KEY-VERSION"] == "2"

      # Signature should be base64 encoded
      signature = headers_map["KC-API-SIGN"]
      assert {:ok, _} = Base.decode64(signature)

      # Passphrase should be HMAC-signed (base64) for v2
      passphrase = headers_map["KC-API-PASSPHRASE"]
      assert {:ok, _} = Base.decode64(passphrase)
    end

    test "signs GET request with query params", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v1/orders",
        body: nil,
        params: %{status: "active", symbol: "BTC-USDT"}
      }

      result = HmacSha256Kucoin.sign(request, credentials, @kucoin_config)

      # URL should include query params
      assert String.contains?(result.url, "?")
      assert String.contains?(result.url, "status=active")
      assert String.contains?(result.url, "symbol=BTC-USDT")
    end
  end

  describe "sign/3 for POST requests" do
    test "signs POST request with JSON body", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/api/v1/orders",
        body: nil,
        params: %{
          clientOid: "test123",
          side: "buy",
          symbol: "BTC-USDT",
          type: "market",
          size: "0.001"
        }
      }

      result = HmacSha256Kucoin.sign(request, credentials, @kucoin_config)

      # Body should be JSON
      assert is_binary(result.body)
      body_decoded = Jason.decode!(result.body)
      assert body_decoded["side"] == "buy"
      assert body_decoded["symbol"] == "BTC-USDT"

      # URL should not have query string for POST
      refute String.contains?(result.url, "?")

      # Headers should include Content-Type
      headers_map = Map.new(result.headers)
      assert headers_map["Content-Type"] == "application/json"
    end
  end

  describe "passphrase signing (v2 API key)" do
    test "passphrase is HMAC-signed for v2", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v1/accounts",
        body: nil,
        params: %{}
      }

      result = HmacSha256Kucoin.sign(request, credentials, @kucoin_config)

      headers_map = Map.new(result.headers)
      signed_passphrase = headers_map["KC-API-PASSPHRASE"]

      # Should NOT be the raw passphrase
      refute signed_passphrase == @passphrase

      # Should be base64 (HMAC result)
      assert {:ok, decoded} = Base.decode64(signed_passphrase)
      # HMAC-SHA256 produces 32 bytes
      assert byte_size(decoded) == 32
    end

    test "passphrase is raw for v1 API key", %{credentials: credentials} do
      v1_config = Map.put(@kucoin_config, :api_key_version, "1")

      request = %{
        method: :get,
        path: "/api/v1/accounts",
        body: nil,
        params: %{}
      }

      result = HmacSha256Kucoin.sign(request, credentials, v1_config)

      headers_map = Map.new(result.headers)
      passphrase_header = headers_map["KC-API-PASSPHRASE"]

      # For v1, passphrase should be raw
      assert passphrase_header == @passphrase
    end
  end

  describe "dispatch via Signing.sign/4" do
    test "dispatches to HmacSha256Kucoin", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{}
      }

      result = Signing.sign(:hmac_sha256_passphrase_signed, request, credentials, @kucoin_config)

      assert is_binary(result.url)
      headers_map = Map.new(result.headers)
      assert Map.has_key?(headers_map, "KC-API-SIGN")
    end
  end

  describe "edge cases" do
    test "handles empty string credentials (produces output but API will reject)" do
      credentials = %Credentials{api_key: "", secret: "", password: "", sandbox: true}

      request = %{
        method: :get,
        path: "/api/v1/accounts",
        body: nil,
        params: %{}
      }

      result = HmacSha256Kucoin.sign(request, credentials, @kucoin_config)

      headers_map = Map.new(result.headers)
      assert headers_map["KC-API-KEY"] == ""
      # Signature and passphrase are still generated
      assert is_binary(headers_map["KC-API-SIGN"])
      assert is_binary(headers_map["KC-API-PASSPHRASE"])
    end

    test "handles nil passphrase (v2 signs empty string)" do
      credentials = %Credentials{
        api_key: @api_key,
        secret: @secret,
        password: nil,
        sandbox: true
      }

      request = %{
        method: :get,
        path: "/api/v1/accounts",
        body: nil,
        params: %{}
      }

      result = HmacSha256Kucoin.sign(request, credentials, @kucoin_config)

      headers_map = Map.new(result.headers)
      # Even nil passphrase gets HMAC-signed for v2
      assert is_binary(headers_map["KC-API-PASSPHRASE"])
      # Should be base64 (signed empty string)
      assert {:ok, _} = Base.decode64(headers_map["KC-API-PASSPHRASE"])
    end

    test "handles DELETE method", %{credentials: credentials} do
      request = %{
        method: :delete,
        path: "/api/v1/orders/12345",
        body: nil,
        params: %{symbol: "BTC-USDT"}
      }

      result = HmacSha256Kucoin.sign(request, credentials, @kucoin_config)

      # DELETE should have params in query string
      assert String.contains?(result.url, "?")
      assert String.contains?(result.url, "symbol=BTC-USDT")
      assert result.body == nil
    end

    test "handles special characters in params", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v1/orders",
        body: nil,
        params: %{filter: "type=limit&status=active", symbol: "BTC/USDT"}
      }

      result = HmacSha256Kucoin.sign(request, credentials, @kucoin_config)

      # Should handle special characters
      assert String.contains?(result.url, "filter=")
      assert String.contains?(result.url, "symbol=")
    end

    test "handles empty params for POST", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/api/v1/test",
        body: nil,
        params: %{}
      }

      result = HmacSha256Kucoin.sign(request, credentials, @kucoin_config)

      # Empty params POST should have nil or empty body
      assert result.body == nil or result.body == "{}"
      assert result.url == "/api/v1/test"
    end
  end
end
