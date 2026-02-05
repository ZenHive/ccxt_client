defmodule CCXT.Signing.HmacSha256IsoTest do
  use ExUnit.Case, async: true

  alias CCXT.Credentials
  alias CCXT.Signing
  alias CCXT.Signing.HmacSha256Iso

  # Test credentials (not real)
  @api_key "test_okx_api_key"
  @secret "test_okx_secret_key"
  @passphrase "test_passphrase"

  @okx_config %{
    api_key_header: "OK-ACCESS-KEY",
    timestamp_header: "OK-ACCESS-TIMESTAMP",
    signature_header: "OK-ACCESS-SIGN",
    passphrase_header: "OK-ACCESS-PASSPHRASE",
    signature_encoding: :base64
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
    test "signs GET request with ISO timestamp", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v5/account/balance",
        body: nil,
        params: %{}
      }

      result = HmacSha256Iso.sign(request, credentials, @okx_config)

      # Check headers
      headers_map = Map.new(result.headers)
      assert headers_map["OK-ACCESS-KEY"] == @api_key
      assert headers_map["OK-ACCESS-PASSPHRASE"] == @passphrase

      # Timestamp should be ISO8601 format
      timestamp = headers_map["OK-ACCESS-TIMESTAMP"]
      assert is_binary(timestamp)
      assert String.contains?(timestamp, "T")
      assert String.ends_with?(timestamp, "Z")

      # Signature should be base64 encoded
      signature = headers_map["OK-ACCESS-SIGN"]
      assert is_binary(signature)
      # Base64 can be decoded
      assert {:ok, _} = Base.decode64(signature)

      # URL should be the path (no query for empty params)
      assert result.url == "/api/v5/account/balance"
    end

    test "signs GET request with query params", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v5/market/ticker",
        body: nil,
        params: %{instId: "BTC-USDT"}
      }

      result = HmacSha256Iso.sign(request, credentials, @okx_config)

      # URL should include query params
      assert String.contains?(result.url, "?")
      assert String.contains?(result.url, "instId=BTC-USDT")
    end
  end

  describe "sign/3 for POST requests" do
    test "signs POST request with JSON body", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/api/v5/trade/order",
        body: nil,
        params: %{
          instId: "BTC-USDT",
          tdMode: "cash",
          side: "buy",
          ordType: "market",
          sz: "0.001"
        }
      }

      result = HmacSha256Iso.sign(request, credentials, @okx_config)

      # Body should be JSON
      assert is_binary(result.body)
      body_decoded = Jason.decode!(result.body)
      assert body_decoded["instId"] == "BTC-USDT"
      assert body_decoded["side"] == "buy"

      # Headers should include Content-Type
      headers_map = Map.new(result.headers)
      assert headers_map["Content-Type"] == "application/json"
    end
  end

  describe "passphrase handling" do
    test "includes passphrase in headers", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v5/account/balance",
        body: nil,
        params: %{}
      }

      result = HmacSha256Iso.sign(request, credentials, @okx_config)

      headers_map = Map.new(result.headers)
      assert headers_map["OK-ACCESS-PASSPHRASE"] == @passphrase
    end

    test "handles missing passphrase", %{credentials: _credentials} do
      credentials_no_pass = %Credentials{
        api_key: @api_key,
        secret: @secret,
        password: nil,
        sandbox: true
      }

      request = %{
        method: :get,
        path: "/api/v5/account/balance",
        body: nil,
        params: %{}
      }

      result = HmacSha256Iso.sign(request, credentials_no_pass, @okx_config)

      headers_map = Map.new(result.headers)
      # Passphrase should be empty string, not nil
      assert headers_map["OK-ACCESS-PASSPHRASE"] == ""
    end
  end

  describe "dispatch via Signing.sign/4" do
    test "dispatches to HmacSha256Iso", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{}
      }

      result = Signing.sign(:hmac_sha256_iso_passphrase, request, credentials, @okx_config)

      assert is_binary(result.url)
      headers_map = Map.new(result.headers)
      assert Map.has_key?(headers_map, "OK-ACCESS-SIGN")
    end
  end

  describe "edge cases" do
    test "handles empty string credentials (produces output but API will reject)" do
      credentials = %Credentials{api_key: "", secret: "", password: "", sandbox: true}

      request = %{
        method: :get,
        path: "/api/v5/account/balance",
        body: nil,
        params: %{}
      }

      result = HmacSha256Iso.sign(request, credentials, @okx_config)

      headers_map = Map.new(result.headers)
      assert headers_map["OK-ACCESS-KEY"] == ""
      assert headers_map["OK-ACCESS-PASSPHRASE"] == ""
      # Signature is still generated
      assert is_binary(headers_map["OK-ACCESS-SIGN"])
    end

    test "handles minimal config (uses defaults for missing optional fields)" do
      credentials = %Credentials{
        api_key: @api_key,
        secret: @secret,
        password: @passphrase,
        sandbox: true
      }

      minimal_config = %{
        api_key_header: "OK-ACCESS-KEY",
        timestamp_header: "OK-ACCESS-TIMESTAMP",
        signature_header: "OK-ACCESS-SIGN",
        passphrase_header: "OK-ACCESS-PASSPHRASE"
        # signature_encoding omitted - should default to :base64
      }

      request = %{
        method: :get,
        path: "/api/v5/test",
        body: nil,
        params: %{}
      }

      result = HmacSha256Iso.sign(request, credentials, minimal_config)

      headers_map = Map.new(result.headers)
      assert headers_map["OK-ACCESS-KEY"] == @api_key
      # Should use base64 encoding by default
      signature = headers_map["OK-ACCESS-SIGN"]
      assert {:ok, _} = Base.decode64(signature)
    end

    test "handles DELETE method", %{credentials: credentials} do
      request = %{
        method: :delete,
        path: "/api/v5/trade/cancel-order",
        body: nil,
        params: %{instId: "BTC-USDT", ordId: "12345"}
      }

      result = HmacSha256Iso.sign(request, credentials, @okx_config)

      # DELETE should have params in query string
      assert String.contains?(result.url, "?")
      assert String.contains?(result.url, "instId=BTC-USDT")
      assert result.body == nil
    end

    test "handles special characters in params", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v5/test",
        body: nil,
        params: %{filter: "type=spot&status=live", instId: "BTC/USDT"}
      }

      result = HmacSha256Iso.sign(request, credentials, @okx_config)

      # Should handle special characters
      assert String.contains?(result.url, "filter=")
      assert String.contains?(result.url, "instId=")
    end

    test "ISO timestamp format is correct", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v5/test",
        body: nil,
        params: %{}
      }

      result = HmacSha256Iso.sign(request, credentials, @okx_config)

      headers_map = Map.new(result.headers)
      timestamp = headers_map["OK-ACCESS-TIMESTAMP"]

      # ISO 8601 format: YYYY-MM-DDTHH:MM:SS.sssZ
      assert Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/, timestamp)
    end
  end
end
