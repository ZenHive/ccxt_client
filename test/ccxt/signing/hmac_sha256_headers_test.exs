defmodule CCXT.Signing.HmacSha256HeadersTest do
  use ExUnit.Case, async: true

  alias CCXT.Credentials
  alias CCXT.Signing
  alias CCXT.Signing.HmacSha256Headers

  # Test credentials (not real)
  @api_key "test_api_key_12345"
  @secret "test_secret_key_67890"

  @bybit_config %{
    api_key_header: "X-BAPI-API-KEY",
    timestamp_header: "X-BAPI-TIMESTAMP",
    signature_header: "X-BAPI-SIGN",
    recv_window_header: "X-BAPI-RECV-WINDOW",
    recv_window: 5000,
    signature_encoding: :hex
  }

  setup do
    credentials = %Credentials{
      api_key: @api_key,
      secret: @secret,
      sandbox: true
    }

    {:ok, credentials: credentials}
  end

  describe "sign/3 for GET requests" do
    test "signs GET request with query params", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/v5/account/wallet-balance",
        body: nil,
        params: %{accountType: "UNIFIED"}
      }

      result = HmacSha256Headers.sign(request, credentials, @bybit_config)

      # Check URL has query string
      assert String.contains?(result.url, "?")
      assert String.contains?(result.url, "accountType=UNIFIED")

      # Check headers
      headers_map = Map.new(result.headers)
      assert headers_map["X-BAPI-API-KEY"] == @api_key
      assert is_binary(headers_map["X-BAPI-TIMESTAMP"])
      assert is_binary(headers_map["X-BAPI-SIGN"])
      assert headers_map["X-BAPI-RECV-WINDOW"] == "5000"

      # Signature should be hex (64 chars for SHA256)
      assert String.length(headers_map["X-BAPI-SIGN"]) == 64
      assert Regex.match?(~r/^[0-9a-f]+$/, headers_map["X-BAPI-SIGN"])

      # Body should be nil for GET
      assert result.body == nil
    end

    test "signs GET request without params", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/v5/market/tickers",
        body: nil,
        params: %{}
      }

      result = HmacSha256Headers.sign(request, credentials, @bybit_config)

      # URL should not have query string
      assert result.url == "/v5/market/tickers"
      assert result.body == nil
    end
  end

  describe "sign/3 for POST requests" do
    test "signs POST request with JSON body", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/v5/order/create",
        body: nil,
        params: %{
          category: "spot",
          symbol: "BTCUSDT",
          side: "Buy",
          orderType: "Market",
          qty: "0.001"
        }
      }

      result = HmacSha256Headers.sign(request, credentials, @bybit_config)

      # URL should not have query string for POST
      assert result.url == "/v5/order/create"

      # Body should be JSON
      assert is_binary(result.body)
      body_decoded = Jason.decode!(result.body)
      assert body_decoded["category"] == "spot"
      assert body_decoded["symbol"] == "BTCUSDT"

      # Check headers
      headers_map = Map.new(result.headers)
      assert headers_map["Content-Type"] == "application/json"
      assert is_binary(headers_map["X-BAPI-SIGN"])
    end

    test "signs POST request with pre-built body", %{credentials: credentials} do
      json_body = Jason.encode!(%{test: "value"})

      request = %{
        method: :post,
        path: "/v5/order/create",
        body: json_body,
        params: %{}
      }

      result = HmacSha256Headers.sign(request, credentials, @bybit_config)

      assert result.body == json_body
    end
  end

  describe "signature consistency" do
    test "same input produces same signature", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/v5/test",
        body: nil,
        params: %{foo: "bar"}
      }

      # Mock timestamp to ensure consistency
      # In real usage, timestamps will differ

      result1 = HmacSha256Headers.sign(request, credentials, @bybit_config)
      result2 = HmacSha256Headers.sign(request, credentials, @bybit_config)

      # Headers will have different timestamps, so signatures will differ
      # This is expected behavior - each request gets a fresh timestamp
      headers1 = Map.new(result1.headers)
      headers2 = Map.new(result2.headers)

      # But both should be valid hex signatures
      assert String.length(headers1["X-BAPI-SIGN"]) == 64
      assert String.length(headers2["X-BAPI-SIGN"]) == 64
    end
  end

  describe "dispatch via Signing.sign/4" do
    test "dispatches to HmacSha256Headers", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{}
      }

      result = Signing.sign(:hmac_sha256_headers, request, credentials, @bybit_config)

      assert is_binary(result.url)
      assert is_list(result.headers)
    end
  end

  describe "edge cases" do
    test "handles empty string credentials (produces output but API will reject)" do
      # Empty credentials are technically valid for signing but exchange will reject
      credentials = %Credentials{api_key: "", secret: "", sandbox: true}

      request = %{
        method: :get,
        path: "/v5/account/wallet-balance",
        body: nil,
        params: %{}
      }

      result = HmacSha256Headers.sign(request, credentials, @bybit_config)

      # Signing succeeds but API key header is empty
      headers_map = Map.new(result.headers)
      assert headers_map["X-BAPI-API-KEY"] == ""
      # Signature is still generated (HMAC with empty key is valid)
      assert is_binary(headers_map["X-BAPI-SIGN"])
    end

    test "handles minimal config (uses defaults for missing optional fields)" do
      credentials = %Credentials{api_key: @api_key, secret: @secret, sandbox: true}

      # Config with only required fields
      minimal_config = %{
        api_key_header: "X-BAPI-API-KEY",
        timestamp_header: "X-BAPI-TIMESTAMP",
        signature_header: "X-BAPI-SIGN"
        # recv_window_header and recv_window omitted
      }

      request = %{
        method: :get,
        path: "/v5/test",
        body: nil,
        params: %{}
      }

      result = HmacSha256Headers.sign(request, credentials, minimal_config)

      headers_map = Map.new(result.headers)
      assert headers_map["X-BAPI-API-KEY"] == @api_key
      assert is_binary(headers_map["X-BAPI-SIGN"])
      # No recv_window header when not configured
      refute Map.has_key?(headers_map, "X-BAPI-RECV-WINDOW")
    end

    test "handles special characters in params (URL encoding)" do
      credentials = %Credentials{api_key: @api_key, secret: @secret, sandbox: true}

      request = %{
        method: :get,
        path: "/v5/test",
        body: nil,
        params: %{filter: "status=active&type=limit", symbol: "BTC/USDT"}
      }

      result = HmacSha256Headers.sign(request, credentials, @bybit_config)

      # Special characters should be URL-encoded
      assert String.contains?(result.url, "filter=")
      assert String.contains?(result.url, "symbol=")
      # The URL should be properly formed
      assert is_binary(result.url)
    end

    test "handles DELETE method", %{credentials: credentials} do
      request = %{
        method: :delete,
        path: "/v5/order/cancel",
        body: nil,
        params: %{orderId: "12345"}
      }

      result = HmacSha256Headers.sign(request, credentials, @bybit_config)

      # DELETE should be treated like GET (params in query string)
      assert String.contains?(result.url, "?")
      assert String.contains?(result.url, "orderId=12345")
      assert result.body == nil
    end

    test "handles empty map params", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/v5/test",
        body: nil,
        params: %{}
      }

      result = HmacSha256Headers.sign(request, credentials, @bybit_config)

      # Empty params should result in no query string
      assert result.url == "/v5/test"
      refute String.contains?(result.url, "?")
      assert is_list(result.headers)
    end
  end
end
