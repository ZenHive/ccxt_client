defmodule CCXT.Signing.HmacSha384PayloadTest do
  use ExUnit.Case, async: true

  alias CCXT.Credentials
  alias CCXT.Signing
  alias CCXT.Signing.HmacSha384Payload

  # Test credentials (not real)
  @api_key "test_bitfinex_api_key"
  @secret "test_bitfinex_secret"

  @bitfinex_config %{
    variant: :bitfinex,
    api_key_header: "bfx-apikey",
    signature_header: "bfx-signature",
    nonce_header: "bfx-nonce"
  }

  @gemini_config %{
    variant: :gemini,
    api_key_header: "X-GEMINI-APIKEY",
    payload_header: "X-GEMINI-PAYLOAD",
    signature_header: "X-GEMINI-SIGNATURE"
  }

  setup do
    credentials = %Credentials{
      api_key: @api_key,
      secret: @secret,
      sandbox: false
    }

    {:ok, credentials: credentials}
  end

  describe "sign/3 Bitfinex variant" do
    test "signs request with nonce in header", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/v2/auth/r/wallets",
        body: nil,
        params: %{}
      }

      result = HmacSha384Payload.sign(request, credentials, @bitfinex_config)

      headers_map = Map.new(result.headers)

      # Check required headers
      assert headers_map["bfx-apikey"] == @api_key
      assert is_binary(headers_map["bfx-nonce"])
      assert is_binary(headers_map["bfx-signature"])

      # Signature should be hex (96 chars for SHA384)
      signature = headers_map["bfx-signature"]
      assert String.length(signature) == 96
      assert Regex.match?(~r/^[0-9a-f]+$/, signature)

      # Body should be JSON
      assert result.body == "{}"
    end

    test "signs request with params", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/v2/auth/w/order/submit",
        body: nil,
        params: %{
          type: "EXCHANGE LIMIT",
          symbol: "tBTCUSD",
          amount: "0.001",
          price: "50000"
        }
      }

      result = HmacSha384Payload.sign(request, credentials, @bitfinex_config)

      # Body should contain params
      body_decoded = Jason.decode!(result.body)
      assert body_decoded["type"] == "EXCHANGE LIMIT"
      assert body_decoded["symbol"] == "tBTCUSD"
    end
  end

  describe "sign/3 Gemini variant" do
    test "signs request with payload in header", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/v1/balances",
        body: nil,
        params: %{}
      }

      result = HmacSha384Payload.sign(request, credentials, @gemini_config)

      headers_map = Map.new(result.headers)

      # Check required headers
      assert headers_map["X-GEMINI-APIKEY"] == @api_key
      assert is_binary(headers_map["X-GEMINI-PAYLOAD"])
      assert is_binary(headers_map["X-GEMINI-SIGNATURE"])

      # Payload should be base64 encoded JSON
      payload_b64 = headers_map["X-GEMINI-PAYLOAD"]
      {:ok, payload_json} = Base.decode64(payload_b64)
      payload = Jason.decode!(payload_json)

      assert payload["request"] == "/v1/balances"
      assert is_binary(payload["nonce"])

      # Signature should be hex (96 chars for SHA384)
      signature = headers_map["X-GEMINI-SIGNATURE"]
      assert String.length(signature) == 96

      # Body should be nil for Gemini (payload in headers)
      assert result.body == nil
    end

    test "includes params in payload", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/v1/order/new",
        body: nil,
        params: %{
          symbol: "btcusd",
          amount: "0.001",
          price: "50000",
          side: "buy",
          type: "exchange limit"
        }
      }

      result = HmacSha384Payload.sign(request, credentials, @gemini_config)

      headers_map = Map.new(result.headers)
      payload_b64 = headers_map["X-GEMINI-PAYLOAD"]
      {:ok, payload_json} = Base.decode64(payload_b64)
      payload = Jason.decode!(payload_json)

      assert payload["symbol"] == "btcusd"
      assert payload["side"] == "buy"
      assert payload["request"] == "/v1/order/new"
    end
  end

  describe "nonce generation" do
    test "nonces are unique", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/v2/auth/r/wallets",
        body: nil,
        params: %{}
      }

      result1 = HmacSha384Payload.sign(request, credentials, @bitfinex_config)
      result2 = HmacSha384Payload.sign(request, credentials, @bitfinex_config)

      headers1 = Map.new(result1.headers)
      headers2 = Map.new(result2.headers)

      assert headers1["bfx-nonce"] != headers2["bfx-nonce"]
    end
  end

  describe "dispatch via Signing.sign/4" do
    test "dispatches to HmacSha384Payload", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/test",
        body: nil,
        params: %{}
      }

      result = Signing.sign(:hmac_sha384_payload, request, credentials, @bitfinex_config)

      assert is_binary(result.url)
      headers_map = Map.new(result.headers)
      assert Map.has_key?(headers_map, "bfx-signature")
    end
  end

  describe "edge cases" do
    test "handles empty string credentials (produces output but API will reject)" do
      credentials = %Credentials{api_key: "", secret: "", sandbox: false}

      request = %{
        method: :post,
        path: "/v2/auth/r/wallets",
        body: nil,
        params: %{}
      }

      result = HmacSha384Payload.sign(request, credentials, @bitfinex_config)

      headers_map = Map.new(result.headers)
      assert headers_map["bfx-apikey"] == ""
      # Signature is still generated
      assert is_binary(headers_map["bfx-signature"])
      assert String.length(headers_map["bfx-signature"]) == 96
    end

    test "Bitfinex uses params for body even when body pre-built" do
      credentials = %Credentials{api_key: @api_key, secret: @secret, sandbox: false}

      request = %{
        method: :post,
        path: "/v2/auth/w/order/submit",
        body: "ignored",
        params: %{type: "EXCHANGE LIMIT", symbol: "tBTCUSD"}
      }

      result = HmacSha384Payload.sign(request, credentials, @bitfinex_config)

      # Bitfinex always builds body from params
      body_decoded = Jason.decode!(result.body)
      assert body_decoded["type"] == "EXCHANGE LIMIT"
      assert body_decoded["symbol"] == "tBTCUSD"
    end

    test "Gemini handles pre-built body (ignores it, uses params)" do
      credentials = %Credentials{api_key: @api_key, secret: @secret, sandbox: false}

      request = %{
        method: :post,
        path: "/v1/order/new",
        body: "ignored",
        params: %{symbol: "btcusd", amount: "0.001"}
      }

      result = HmacSha384Payload.sign(request, credentials, @gemini_config)

      # Gemini puts payload in headers, body should be nil
      assert result.body == nil

      headers_map = Map.new(result.headers)
      payload_b64 = headers_map["X-GEMINI-PAYLOAD"]
      {:ok, payload_json} = Base.decode64(payload_b64)
      payload = Jason.decode!(payload_json)

      # Params should be in payload
      assert payload["symbol"] == "btcusd"
    end

    test "handles special characters in params" do
      credentials = %Credentials{api_key: @api_key, secret: @secret, sandbox: false}

      request = %{
        method: :post,
        path: "/v2/auth/w/order/submit",
        body: nil,
        params: %{filter: "type=limit&status=active", symbol: "tBTC/USD"}
      }

      result = HmacSha384Payload.sign(request, credentials, @bitfinex_config)

      # Body should contain the params as JSON
      body_decoded = Jason.decode!(result.body)
      assert body_decoded["filter"] == "type=limit&status=active"
      assert body_decoded["symbol"] == "tBTC/USD"
    end

    test "nonce is numeric string" do
      credentials = %Credentials{api_key: @api_key, secret: @secret, sandbox: false}

      request = %{
        method: :post,
        path: "/v2/auth/r/wallets",
        body: nil,
        params: %{}
      }

      result = HmacSha384Payload.sign(request, credentials, @bitfinex_config)

      headers_map = Map.new(result.headers)
      nonce = headers_map["bfx-nonce"]

      # Should be a numeric string
      assert is_binary(nonce)
      assert String.match?(nonce, ~r/^\d+$/)
    end
  end
end
