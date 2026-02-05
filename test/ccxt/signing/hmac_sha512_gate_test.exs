defmodule CCXT.Signing.HmacSha512GateTest do
  use ExUnit.Case, async: true

  alias CCXT.Credentials
  alias CCXT.Signing
  alias CCXT.Signing.HmacSha512Gate

  # Test credentials (not real)
  # Note: Gate.io secrets are used directly (NOT base64 encoded)
  @api_key "test_gate_api_key"
  @secret "test_gate_secret_key"

  @gate_config %{
    api_key_header: "KEY",
    signature_header: "SIGN",
    timestamp_header: "Timestamp",
    signing_path_prefix: "/api/v4"
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
    test "signs GET request without body", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/spot/accounts",
        body: nil,
        params: %{}
      }

      result = HmacSha512Gate.sign(request, credentials, @gate_config)

      # URL should be the path (no query for empty params)
      assert result.url == "/spot/accounts"

      # Check headers
      headers_map = Map.new(result.headers)
      assert headers_map["KEY"] == @api_key
      assert is_binary(headers_map["SIGN"])
      assert is_binary(headers_map["Timestamp"])

      # Signature should be hex encoded (128 chars for SHA512)
      assert String.length(headers_map["SIGN"]) == 128
      assert Regex.match?(~r/^[0-9a-f]+$/, headers_map["SIGN"])
    end

    test "signs GET request with query params", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/spot/orders",
        body: nil,
        params: %{currency_pair: "BTC_USDT", status: "open"}
      }

      result = HmacSha512Gate.sign(request, credentials, @gate_config)

      # URL should include query string
      assert String.contains?(result.url, "/spot/orders?")
      assert String.contains?(result.url, "currency_pair=BTC_USDT")
      assert String.contains?(result.url, "status=open")

      headers_map = Map.new(result.headers)
      assert headers_map["KEY"] == @api_key
      assert is_binary(headers_map["SIGN"])
    end

    test "signs POST request with body", %{credentials: credentials} do
      body = ~s({"currency_pair":"BTC_USDT","side":"buy","amount":"0.001"})

      request = %{
        method: :post,
        path: "/spot/orders",
        body: body,
        params: %{}
      }

      result = HmacSha512Gate.sign(request, credentials, @gate_config)

      # Body should be preserved
      assert result.body == body

      # Content-Type should be JSON
      headers_map = Map.new(result.headers)
      assert headers_map["Content-Type"] == "application/json"
      assert headers_map["KEY"] == @api_key
      assert is_binary(headers_map["SIGN"])
    end

    test "empty body becomes nil in result", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/spot/accounts",
        body: "",
        params: %{}
      }

      result = HmacSha512Gate.sign(request, credentials, @gate_config)

      # Empty string body should become nil
      assert result.body == nil
    end

    test "timestamp is in seconds (not milliseconds)", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/spot/accounts",
        body: nil,
        params: %{}
      }

      result = HmacSha512Gate.sign(request, credentials, @gate_config)

      headers_map = Map.new(result.headers)
      timestamp = String.to_integer(headers_map["Timestamp"])

      # Timestamp in seconds should be around 10 digits (not 13 for milliseconds)
      assert timestamp > 1_700_000_000
      assert timestamp < 2_000_000_000
    end
  end

  describe "signature format" do
    test "signature is valid hex-encoded SHA512", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/spot/accounts",
        body: nil,
        params: %{}
      }

      result = HmacSha512Gate.sign(request, credentials, @gate_config)

      headers_map = Map.new(result.headers)
      signature = headers_map["SIGN"]

      # Should be 128 hex characters (64 bytes * 2)
      assert String.length(signature) == 128

      # Should be valid hex
      assert {:ok, _decoded} = Base.decode16(signature, case: :lower)
    end
  end

  describe "dispatch via Signing.sign/4" do
    test "dispatches to HmacSha512Gate", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{}
      }

      result = Signing.sign(:hmac_sha512_gate, request, credentials, @gate_config)

      assert is_binary(result.url)
      headers_map = Map.new(result.headers)
      assert Map.has_key?(headers_map, "SIGN")
      assert Map.has_key?(headers_map, "Timestamp")
    end
  end

  describe "payload construction" do
    test "different signing path prefixes produce different signatures", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/spot/accounts",
        body: nil,
        params: %{}
      }

      config_v4 = %{@gate_config | signing_path_prefix: "/api/v4"}
      config_v5 = %{@gate_config | signing_path_prefix: "/api/v5"}

      result_v4 = HmacSha512Gate.sign(request, credentials, config_v4)
      result_v5 = HmacSha512Gate.sign(request, credentials, config_v5)

      headers_v4 = Map.new(result_v4.headers)
      headers_v5 = Map.new(result_v5.headers)

      # Different prefixes MUST produce different signatures
      # (timestamps may also differ, but the prefix is the variable under test)
      refute headers_v4["SIGN"] == headers_v5["SIGN"],
             "Expected different signatures for different path prefixes, but got the same signature"
    end
  end

  describe "edge cases" do
    test "handles empty string credentials (produces output but API will reject)" do
      credentials = %Credentials{api_key: "", secret: "", sandbox: false}

      request = %{
        method: :get,
        path: "/spot/accounts",
        body: nil,
        params: %{}
      }

      result = HmacSha512Gate.sign(request, credentials, @gate_config)

      headers_map = Map.new(result.headers)
      assert headers_map["KEY"] == ""
      # Signature is still generated (128 hex chars for SHA512)
      assert String.length(headers_map["SIGN"]) == 128
    end

    test "handles DELETE method" do
      credentials = %Credentials{api_key: @api_key, secret: @secret, sandbox: false}

      request = %{
        method: :delete,
        path: "/spot/orders/12345",
        body: nil,
        params: %{currency_pair: "BTC_USDT"}
      }

      result = HmacSha512Gate.sign(request, credentials, @gate_config)

      # DELETE should have params in query string
      assert String.contains?(result.url, "?")
      assert String.contains?(result.url, "currency_pair=BTC_USDT")
      assert result.body == nil
    end

    test "handles special characters in params" do
      credentials = %Credentials{api_key: @api_key, secret: @secret, sandbox: false}

      request = %{
        method: :get,
        path: "/spot/orders",
        body: nil,
        params: %{currency_pair: "BTC_USDT", filter: "status=open&type=limit"}
      }

      result = HmacSha512Gate.sign(request, credentials, @gate_config)

      # Should handle special characters
      assert String.contains?(result.url, "currency_pair=BTC_USDT")
      assert String.contains?(result.url, "filter=")
    end

    test "handles PUT method" do
      credentials = %Credentials{api_key: @api_key, secret: @secret, sandbox: false}

      body = ~s({"currency_pair":"BTC_USDT","amount":"0.001"})

      request = %{
        method: :put,
        path: "/spot/orders/12345",
        body: body,
        params: %{}
      }

      result = HmacSha512Gate.sign(request, credentials, @gate_config)

      # PUT should preserve body
      assert result.body == body

      headers_map = Map.new(result.headers)
      assert headers_map["Content-Type"] == "application/json"
    end

    test "handles minimal config (uses defaults)" do
      credentials = %Credentials{api_key: @api_key, secret: @secret, sandbox: false}

      minimal_config = %{
        api_key_header: "KEY",
        signature_header: "SIGN",
        timestamp_header: "Timestamp"
        # signing_path_prefix omitted
      }

      request = %{
        method: :get,
        path: "/spot/accounts",
        body: nil,
        params: %{}
      }

      result = HmacSha512Gate.sign(request, credentials, minimal_config)

      headers_map = Map.new(result.headers)
      assert headers_map["KEY"] == @api_key
      assert is_binary(headers_map["SIGN"])
      assert is_binary(headers_map["Timestamp"])
    end
  end
end
