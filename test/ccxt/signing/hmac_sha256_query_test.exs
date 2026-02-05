defmodule CCXT.Signing.HmacSha256QueryTest do
  use ExUnit.Case, async: true

  alias CCXT.Credentials
  alias CCXT.Signing
  alias CCXT.Signing.HmacSha256Query

  # Test credentials (not real)
  @api_key "vmPUZE6mv9SD5VNHk4HlWFsOr6aKE2zvsw0MuIgwCIPy6utIco14y7Ju91duEh8A"
  @secret "NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j"

  @binance_config %{
    api_key_header: "X-MBX-APIKEY",
    timestamp_key: "timestamp",
    signature_key: "signature",
    recv_window_key: "recvWindow",
    recv_window: 5000,
    auto_recv_window: true,
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
    test "appends signature to query string", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v3/account",
        body: nil,
        params: %{}
      }

      result = HmacSha256Query.sign(request, credentials, @binance_config)

      # URL should have timestamp and signature
      assert String.contains?(result.url, "timestamp=")
      assert String.contains?(result.url, "recvWindow=5000")
      assert String.contains?(result.url, "&signature=")

      # Signature should be last parameter
      assert String.match?(result.url, ~r/signature=[0-9a-f]{64}$/)

      # Body should be nil for GET
      assert result.body == nil
    end

    test "includes params in query string", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v3/ticker/price",
        body: nil,
        params: %{symbol: "BTCUSDT"}
      }

      result = HmacSha256Query.sign(request, credentials, @binance_config)

      assert String.contains?(result.url, "symbol=BTCUSDT")
      assert String.contains?(result.url, "timestamp=")
      assert String.contains?(result.url, "signature=")
    end
  end

  describe "sign/3 for POST requests" do
    test "signs POST with params in URL", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/api/v3/order",
        body: nil,
        params: %{
          symbol: "BTCUSDT",
          side: "BUY",
          type: "MARKET",
          quantity: "0.001"
        }
      }

      result = HmacSha256Query.sign(request, credentials, @binance_config)

      # For Binance-style, even POST has params in URL
      assert String.contains?(result.url, "symbol=BTCUSDT")
      assert String.contains?(result.url, "signature=")

      # Check headers
      headers_map = Map.new(result.headers)
      assert headers_map["X-MBX-APIKEY"] == @api_key
    end
  end

  describe "signature verification" do
    test "signature is valid HMAC-SHA256 hex", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{a: "1", b: "2"}
      }

      result = HmacSha256Query.sign(request, credentials, @binance_config)

      # Extract signature from URL
      [_path, query] = String.split(result.url, "?")
      params = URI.decode_query(query)

      signature = params["signature"]

      # Should be 64 hex chars (256 bits)
      assert String.length(signature) == 64
      assert Regex.match?(~r/^[0-9a-f]+$/, signature)
    end
  end

  describe "parameter ordering" do
    test "params are sorted alphabetically before signing", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{z: "last", a: "first", m: "middle"}
      }

      result = HmacSha256Query.sign(request, credentials, @binance_config)

      # Params should be sorted
      assert String.contains?(result.url, "a=first")

      # Check ordering in URL
      [_path, query] = String.split(result.url, "?")

      # a should come before m, m before z
      a_pos = query |> :binary.match("a=first") |> elem(0)
      m_pos = query |> :binary.match("m=middle") |> elem(0)
      z_pos = query |> :binary.match("z=last") |> elem(0)

      assert a_pos < m_pos
      assert m_pos < z_pos
    end
  end

  describe "dispatch via Signing.sign/4" do
    test "dispatches to HmacSha256Query", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{}
      }

      result = Signing.sign(:hmac_sha256_query, request, credentials, @binance_config)

      assert is_binary(result.url)
      assert String.contains?(result.url, "signature=")
    end
  end

  describe "edge cases" do
    test "handles empty string credentials (produces output but API will reject)" do
      credentials = %Credentials{api_key: "", secret: "", sandbox: true}

      request = %{
        method: :get,
        path: "/api/v3/account",
        body: nil,
        params: %{}
      }

      result = HmacSha256Query.sign(request, credentials, @binance_config)

      # Signing succeeds but API key header is empty
      headers_map = Map.new(result.headers)
      assert headers_map["X-MBX-APIKEY"] == ""
      # Signature is still generated in URL
      assert String.contains?(result.url, "signature=")
    end

    test "handles minimal config (uses defaults for missing optional fields)" do
      credentials = %Credentials{api_key: @api_key, secret: @secret, sandbox: true}

      # Config with only required fields
      minimal_config = %{
        api_key_header: "X-MBX-APIKEY",
        timestamp_key: "timestamp",
        signature_key: "signature"
        # recv_window_key and auto_recv_window omitted
      }

      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{}
      }

      result = HmacSha256Query.sign(request, credentials, minimal_config)

      # Should work without recv_window
      assert String.contains?(result.url, "timestamp=")
      assert String.contains?(result.url, "signature=")
      refute String.contains?(result.url, "recvWindow=")
    end

    test "handles special characters in params (URL encoding)", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v3/test",
        body: nil,
        params: %{filter: "status=active&type=limit", symbol: "BTC/USDT"}
      }

      result = HmacSha256Query.sign(request, credentials, @binance_config)

      # Special characters should be URL-encoded
      assert String.contains?(result.url, "filter=")
      assert String.contains?(result.url, "symbol=")
      assert String.contains?(result.url, "signature=")
    end

    test "handles DELETE method", %{credentials: credentials} do
      request = %{
        method: :delete,
        path: "/api/v3/order",
        body: nil,
        params: %{symbol: "BTCUSDT", orderId: "12345"}
      }

      result = HmacSha256Query.sign(request, credentials, @binance_config)

      # DELETE should work like GET
      assert String.contains?(result.url, "symbol=BTCUSDT")
      assert String.contains?(result.url, "orderId=12345")
      assert String.contains?(result.url, "signature=")
    end

    test "handles base64 signature encoding", %{credentials: credentials} do
      config_base64 = Map.put(@binance_config, :signature_encoding, :base64)

      request = %{
        method: :get,
        path: "/api/v3/test",
        body: nil,
        params: %{}
      }

      result = HmacSha256Query.sign(request, credentials, config_base64)

      # Extract signature from URL - it gets URL-encoded
      [_path, query] = String.split(result.url, "?")
      params = URI.decode_query(query)
      signature = params["signature"]

      # URI.decode_query decodes + as space (standard URL decoding)
      # Convert spaces back to + for base64 decoding
      signature_fixed = String.replace(signature, " ", "+")

      # Base64 signature should be decodable
      decoded =
        case Base.decode64(signature_fixed) do
          {:ok, bytes} -> bytes
          :error -> Base.url_decode64!(signature_fixed, padding: false)
        end

      # SHA256 produces 32 bytes
      assert byte_size(decoded) == 32
    end
  end
end
