defmodule CCXT.Signing.DeribitTest do
  use ExUnit.Case, async: true

  alias CCXT.Credentials
  alias CCXT.Signing
  alias CCXT.Signing.Custom
  alias CCXT.Signing.Deribit

  # Test credentials (not real)
  @api_key "test_deribit_api_key"
  @secret "test_deribit_secret_key"

  setup do
    credentials = %Credentials{
      api_key: @api_key,
      secret: @secret,
      sandbox: true
    }

    {:ok, credentials: credentials}
  end

  describe "sign/3 for GET requests" do
    test "signs GET request with params - query string appended", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v2/public/get_instruments",
        body: nil,
        params: %{currency: "BTC", kind: "future"}
      }

      result = Deribit.sign(request, credentials, %{})

      # URL should contain query string
      assert String.contains?(result.url, "?")
      assert String.contains?(result.url, "currency=BTC")
      assert String.contains?(result.url, "kind=future")
      # Body should remain nil for GET
      assert result.body == nil
      assert result.method == :get
    end

    test "signs GET request without params - path unchanged", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v2/public/test",
        body: nil,
        params: %{}
      }

      result = Deribit.sign(request, credentials, %{})

      # No query string when no params
      assert result.url == "/api/v2/public/test"
      refute String.contains?(result.url, "?")
      assert result.body == nil
    end
  end

  describe "sign/3 for POST requests" do
    test "signs POST request with body", %{credentials: credentials} do
      json_body = Jason.encode!(%{instrument_name: "BTC-PERPETUAL", amount: 10})

      request = %{
        method: :post,
        path: "/api/v2/private/buy",
        body: json_body,
        params: %{}
      }

      result = Deribit.sign(request, credentials, %{})

      # Body should be preserved
      assert result.body == json_body
      assert result.method == :post
      assert result.url == "/api/v2/private/buy"
    end

    test "signs POST request without body - empty string used in signature", %{credentials: credentials} do
      request = %{
        method: :post,
        path: "/api/v2/private/get_positions",
        body: nil,
        params: %{}
      }

      result = Deribit.sign(request, credentials, %{})

      # Body should stay nil in the result
      assert result.body == nil
      # Authorization header should still be generated
      headers_map = Map.new(result.headers)
      assert is_binary(headers_map["Authorization"])
    end
  end

  describe "signature format" do
    @basic_request %{method: :get, path: "/api/v2/public/test", body: nil, params: %{}}

    test "Authorization header has correct deri-hmac-sha256 format", %{credentials: credentials} do
      result = Deribit.sign(@basic_request, credentials, %{})

      headers_map = Map.new(result.headers)
      auth = headers_map["Authorization"]

      assert String.starts_with?(auth, "deri-hmac-sha256 ")
    end

    test "Authorization header contains id with api_key", %{credentials: credentials} do
      result = Deribit.sign(@basic_request, credentials, %{})
      headers_map = Map.new(result.headers)
      auth = headers_map["Authorization"]

      assert String.contains?(auth, "id=#{@api_key}")
    end

    test "Authorization header contains ts, sig, nonce fields", %{credentials: credentials} do
      result = Deribit.sign(@basic_request, credentials, %{})
      headers_map = Map.new(result.headers)
      auth = headers_map["Authorization"]

      assert String.contains?(auth, "ts=")
      assert String.contains?(auth, "sig=")
      assert String.contains?(auth, "nonce=")
    end

    test "signature is 64-char hex string (SHA256)", %{credentials: credentials} do
      result = Deribit.sign(@basic_request, credentials, %{})
      headers_map = Map.new(result.headers)
      auth = headers_map["Authorization"]

      # Extract sig value from "deri-hmac-sha256 id=...,ts=...,sig=SIG,nonce=..."
      [_prefix, pairs_str] = String.split(auth, " ", parts: 2)
      pairs = String.split(pairs_str, ",")
      sig_pair = Enum.find(pairs, &String.starts_with?(&1, "sig="))
      sig = String.replace_prefix(sig_pair, "sig=", "")

      assert String.length(sig) == 64
      assert Regex.match?(~r/^[0-9a-f]+$/, sig)
    end

    test "consecutive signs produce valid Authorization headers", %{credentials: credentials} do
      request = %{method: :get, path: "/api/v2/test", body: nil, params: %{foo: "bar"}}

      result1 = Deribit.sign(request, credentials, %{})
      result2 = Deribit.sign(request, credentials, %{})

      headers1 = Map.new(result1.headers)
      headers2 = Map.new(result2.headers)

      assert String.starts_with?(headers1["Authorization"], "deri-hmac-sha256 ")
      assert String.starts_with?(headers2["Authorization"], "deri-hmac-sha256 ")
    end
  end

  describe "dispatch via Signing.sign/4" do
    test "dispatches :deribit pattern correctly", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v2/public/test",
        body: nil,
        params: %{}
      }

      result = Signing.sign(:deribit, request, credentials, %{})

      assert is_binary(result.url)
      assert is_list(result.headers)
      headers_map = Map.new(result.headers)
      assert String.starts_with?(headers_map["Authorization"], "deri-hmac-sha256 ")
    end

    test "dispatches :custom pattern correctly", %{credentials: credentials} do
      config = %{
        custom_module: CCXT.Signing.DeribitTest.SimpleCustomSigner
      }

      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{}
      }

      result = Signing.sign(:custom, request, credentials, config)

      assert result.url == "/test"
      headers_map = Map.new(result.headers)
      assert headers_map["X-Test"] == "custom"
    end
  end

  describe "module_for_pattern/1" do
    test "returns Deribit module for :deribit pattern" do
      assert Signing.module_for_pattern(:deribit) == Deribit
    end

    test "returns Custom module for :custom pattern" do
      assert Signing.module_for_pattern(:custom) == Custom
    end

    test "returns nil for unknown pattern" do
      assert Signing.module_for_pattern(:unknown_pattern) == nil
    end
  end

  describe "edge cases" do
    test "handles DELETE method", %{credentials: credentials} do
      request = %{
        method: :delete,
        path: "/api/v2/private/cancel",
        body: nil,
        params: %{order_id: "12345"}
      }

      result = Deribit.sign(request, credentials, %{})

      assert String.contains?(result.url, "order_id=12345")
      headers_map = Map.new(result.headers)
      assert String.contains?(headers_map["Authorization"], "deri-hmac-sha256")
    end

    test "handles empty string credentials", %{credentials: _credentials} do
      credentials = %Credentials{api_key: "", secret: "", sandbox: true}

      request = %{
        method: :get,
        path: "/api/v2/test",
        body: nil,
        params: %{}
      }

      result = Deribit.sign(request, credentials, %{})

      headers_map = Map.new(result.headers)
      auth = headers_map["Authorization"]
      # id= should be empty
      assert String.contains?(auth, "id=,")
    end

    test "handles nil params by treating as empty map", %{credentials: credentials} do
      request = %{
        method: :get,
        path: "/api/v2/public/test",
        body: nil,
        params: nil
      }

      # Signing.urlencode/1 expects a map — verify nil doesn't crash
      result = Deribit.sign(request, credentials, %{})

      assert result.url == "/api/v2/public/test"
      refute String.contains?(result.url, "?")
      headers_map = Map.new(result.headers)
      assert String.starts_with?(headers_map["Authorization"], "deri-hmac-sha256 ")
    end
  end

  # Simple custom signer for dispatch test
  defmodule SimpleCustomSigner do
    @moduledoc false
    @behaviour Custom

    @impl true
    def sign(request, _credentials, _config) do
      %{
        url: request.path,
        method: request.method,
        headers: [{"X-Test", "custom"}],
        body: nil
      }
    end
  end
end
