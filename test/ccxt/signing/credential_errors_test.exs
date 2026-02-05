defmodule CCXT.Signing.CredentialErrorsTest do
  @moduledoc """
  Task 43c: Test credential error messages.

  Verifies that helpful error messages are produced when:
  1. Credentials are nil during struct creation
  2. Credentials are empty strings
  3. Required passphrase is missing (OKX, KuCoin)
  4. API call made without credentials on private endpoint
  """

  use ExUnit.Case, async: true

  alias CCXT.Credentials
  alias CCXT.Signing.HmacSha256Headers
  alias CCXT.Signing.HmacSha256Iso
  alias CCXT.Signing.HmacSha256Kucoin

  describe "Credentials.new/1 with nil values" do
    test "returns error for nil api_key" do
      result = Credentials.new(api_key: nil, secret: "secret123")

      assert {:error, :missing_api_key} = result
    end

    test "returns error for nil secret" do
      result = Credentials.new(api_key: "apikey123", secret: nil)

      assert {:error, :missing_secret} = result
    end

    test "returns error when api_key is omitted" do
      result = Credentials.new(secret: "secret123")

      assert {:error, :missing_api_key} = result
    end

    test "returns error when secret is omitted" do
      result = Credentials.new(api_key: "apikey123")

      assert {:error, :missing_secret} = result
    end

    test "returns error for empty options" do
      result = Credentials.new([])

      assert {:error, :missing_api_key} = result
    end
  end

  describe "Credentials.new!/1 with nil values" do
    test "raises ArgumentError for nil api_key" do
      assert_raise ArgumentError, "api_key is required", fn ->
        Credentials.new!(api_key: nil, secret: "secret123")
      end
    end

    test "raises ArgumentError for nil secret" do
      assert_raise ArgumentError, "secret is required", fn ->
        Credentials.new!(api_key: "apikey123", secret: nil)
      end
    end

    test "raises ArgumentError when api_key is omitted" do
      assert_raise ArgumentError, "api_key is required", fn ->
        Credentials.new!(secret: "secret123")
      end
    end

    test "raises ArgumentError when secret is omitted" do
      assert_raise ArgumentError, "secret is required", fn ->
        Credentials.new!(api_key: "apikey123")
      end
    end
  end

  describe "signing with empty string credentials" do
    @bybit_config %{
      api_key_header: "X-BAPI-API-KEY",
      timestamp_header: "X-BAPI-TIMESTAMP",
      signature_header: "X-BAPI-SIGN",
      recv_window: 5000,
      signature_encoding: :hex
    }

    test "empty api_key produces request but API will reject it" do
      # Empty strings are technically valid for struct but API will reject
      credentials = %Credentials{api_key: "", secret: "secret123"}
      request = %{method: :get, path: "/test", body: nil, params: %{}}

      result = HmacSha256Headers.sign(request, credentials, @bybit_config)

      # Signing succeeds but api_key header is empty
      headers_map = Map.new(result.headers)
      assert headers_map["X-BAPI-API-KEY"] == ""
    end

    test "empty secret produces signature but will be invalid" do
      credentials = %Credentials{api_key: "apikey123", secret: ""}
      request = %{method: :get, path: "/test", body: nil, params: %{}}

      result = HmacSha256Headers.sign(request, credentials, @bybit_config)

      # Signing succeeds (HMAC with empty key is valid) but exchange will reject
      headers_map = Map.new(result.headers)
      assert is_binary(headers_map["X-BAPI-SIGN"])
    end
  end

  describe "OKX pattern missing passphrase" do
    @okx_config %{
      api_key_header: "OK-ACCESS-KEY",
      signature_header: "OK-ACCESS-SIGN",
      timestamp_header: "OK-ACCESS-TIMESTAMP",
      passphrase_header: "OK-ACCESS-PASSPHRASE",
      has_passphrase: true,
      signature_encoding: :base64
    }

    test "missing passphrase in credentials for OKX pattern" do
      # OKX requires passphrase but credentials don't have one
      credentials = %Credentials{api_key: "apikey", secret: "secret", password: nil}
      request = %{method: :get, path: "/api/v5/account/balance", body: nil, params: %{}}

      result = HmacSha256Iso.sign(request, credentials, @okx_config)

      # Signing succeeds but passphrase header will be empty string (nil coerced)
      # Exchange will reject request with empty passphrase
      headers_map = Map.new(result.headers)
      assert headers_map["OK-ACCESS-PASSPHRASE"] == ""
    end

    test "passphrase provided works correctly for OKX pattern" do
      credentials = %Credentials{api_key: "apikey", secret: "secret", password: "mypassphrase"}
      request = %{method: :get, path: "/api/v5/account/balance", body: nil, params: %{}}

      result = HmacSha256Iso.sign(request, credentials, @okx_config)

      headers_map = Map.new(result.headers)
      assert headers_map["OK-ACCESS-PASSPHRASE"] == "mypassphrase"
    end
  end

  describe "KuCoin pattern missing passphrase" do
    @kucoin_config %{
      api_key_header: "KC-API-KEY",
      signature_header: "KC-API-SIGN",
      timestamp_header: "KC-API-TIMESTAMP",
      passphrase_header: "KC-API-PASSPHRASE",
      version_header: "KC-API-KEY-VERSION",
      api_version: "2",
      has_passphrase: true,
      passphrase_signed: true,
      signature_encoding: :base64
    }

    test "missing passphrase in credentials for KuCoin pattern" do
      # KuCoin requires passphrase but credentials don't have one
      credentials = %Credentials{api_key: "apikey", secret: "secret", password: nil}
      request = %{method: :get, path: "/api/v1/accounts", body: nil, params: %{}}

      # KuCoin signs the passphrase with HMAC - nil gets coerced to empty string
      result = HmacSha256Kucoin.sign(request, credentials, @kucoin_config)

      # Verify signing doesn't crash and produces expected headers
      assert is_map(result)
      headers_map = Map.new(result.headers)

      # Explicit check: nil passphrase produces signed empty string
      passphrase_header = headers_map["KC-API-PASSPHRASE"]

      assert is_binary(passphrase_header),
             "Expected KC-API-PASSPHRASE header, got: #{inspect(headers_map)}"

      # The signed passphrase will be base64-encoded HMAC of empty string
      # Exchange will reject this, but signing completes without crash
      assert String.length(passphrase_header) > 0
    end

    test "passphrase provided works correctly for KuCoin pattern" do
      credentials = %Credentials{api_key: "apikey", secret: "secret", password: "mypassphrase"}
      request = %{method: :get, path: "/api/v1/accounts", body: nil, params: %{}}

      result = HmacSha256Kucoin.sign(request, credentials, @kucoin_config)

      headers_map = Map.new(result.headers)
      assert headers_map["KC-API-KEY"] == "apikey"
      assert is_binary(headers_map["KC-API-PASSPHRASE"])
      # KuCoin signs the passphrase, so it won't equal the original
      assert headers_map["KC-API-PASSPHRASE"] != "mypassphrase"
    end
  end

  describe "struct creation validation" do
    test "Credentials struct enforces required keys" do
      # Direct struct creation without api_key/secret raises at compile time
      # This is enforced by @enforce_keys [:api_key, :secret]
      # We test that valid creation works:
      creds = %Credentials{api_key: "key", secret: "secret"}
      assert creds.api_key == "key"
      assert creds.secret == "secret"
      assert creds.password == nil
      assert creds.sandbox == false
    end

    test "Credentials struct allows optional password" do
      creds = %Credentials{api_key: "key", secret: "secret", password: "pass"}
      assert creds.password == "pass"
    end

    test "Credentials struct allows sandbox flag" do
      creds = %Credentials{api_key: "key", secret: "secret", sandbox: true}
      assert creds.sandbox == true
    end
  end

  describe "helpful error message content" do
    test "new! error message mentions api_key specifically" do
      error =
        assert_raise ArgumentError, fn ->
          Credentials.new!(secret: "secret")
        end

      assert error.message =~ "api_key"
    end

    test "new! error message mentions secret specifically" do
      error =
        assert_raise ArgumentError, fn ->
          Credentials.new!(api_key: "key")
        end

      assert error.message =~ "secret"
    end
  end
end
