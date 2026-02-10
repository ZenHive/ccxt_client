defmodule CCXT.Signing.CustomTest do
  use ExUnit.Case, async: true

  alias CCXT.Credentials
  alias CCXT.Signing
  alias CCXT.Signing.Custom
  alias CCXT.Signing.HmacSha256Headers

  # Test credentials
  @api_key "test_custom_api_key"
  @secret "test_custom_secret"

  setup do
    credentials = %Credentials{
      api_key: @api_key,
      secret: @secret,
      sandbox: false
    }

    {:ok, credentials: credentials}
  end

  describe "sign/3" do
    test "delegates to custom module", %{credentials: credentials} do
      config = %{
        custom_module: CCXT.Signing.CustomTest.TestSigner
      }

      request = %{
        method: :get,
        path: "/test/path",
        body: nil,
        params: %{foo: "bar"}
      }

      result = Custom.sign(request, credentials, config)

      # TestSigner adds a custom header
      headers_map = Map.new(result.headers)
      assert headers_map["X-Custom-Signed"] == "true"
      assert headers_map["X-Custom-API-Key"] == @api_key
      assert result.url == "/test/path"
    end

    test "raises without custom_module", %{credentials: credentials} do
      config = %{}

      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{}
      }

      assert_raise ArgumentError, ~r/custom_module/, fn ->
        Custom.sign(request, credentials, config)
      end
    end
  end

  describe "dispatch via Signing.sign/4" do
    test "dispatches to Custom", %{credentials: credentials} do
      config = %{
        custom_module: CCXT.Signing.CustomTest.TestSigner
      }

      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{}
      }

      result = Signing.sign(:custom, request, credentials, config)

      headers_map = Map.new(result.headers)
      assert headers_map["X-Custom-Signed"] == "true"
    end
  end

  describe "validate_module/1" do
    test "accepts module with sign/3" do
      assert {:ok, HmacSha256Headers} =
               Custom.validate_module(HmacSha256Headers)
    end

    test "rejects module without sign/3" do
      assert {:error, message} = Custom.validate_module(String)
      assert message =~ "must implement sign/3"
      assert message =~ "CCXT.Signing.Behaviour"
    end

    test "rejects non-existent module with load error" do
      assert {:error, message} = Custom.validate_module(NoSuchModule)
      assert message =~ "Could not load"
      assert message =~ "CCXT.Signing.Behaviour"
    end
  end

  describe "sign/3 with invalid module" do
    test "raises ArgumentError for module without sign/3", %{credentials: credentials} do
      config = %{custom_module: String}

      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{}
      }

      assert_raise ArgumentError, ~r/must implement sign\/3/, fn ->
        Custom.sign(request, credentials, config)
      end
    end
  end

  describe "edge cases" do
    test "handles empty string credentials", %{credentials: _credentials} do
      credentials = %Credentials{api_key: "", secret: "", sandbox: false}

      config = %{
        custom_module: CCXT.Signing.CustomTest.TestSigner
      }

      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{}
      }

      result = Custom.sign(request, credentials, config)

      headers_map = Map.new(result.headers)
      # Custom signer uses credentials.api_key directly
      assert headers_map["X-Custom-API-Key"] == ""
    end

    test "passes params to custom module", %{credentials: credentials} do
      config = %{
        custom_module: CCXT.Signing.CustomTest.ParamSigner
      }

      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{foo: "bar", baz: "qux"}
      }

      result = Custom.sign(request, credentials, config)

      # ParamSigner should have access to params
      # Use String.contains? since map iteration order is not guaranteed
      assert String.contains?(result.url, "/test?")
      assert String.contains?(result.url, "foo=bar")
      assert String.contains?(result.url, "baz=qux")
    end

    test "passes config to custom module", %{credentials: credentials} do
      config = %{
        custom_module: CCXT.Signing.CustomTest.ConfigSigner,
        custom_header: "X-Custom-Header",
        custom_value: "custom-value"
      }

      request = %{
        method: :get,
        path: "/test",
        body: nil,
        params: %{}
      }

      result = Custom.sign(request, credentials, config)

      headers_map = Map.new(result.headers)
      # ConfigSigner uses config values
      assert headers_map["X-Custom-Header"] == "custom-value"
    end

    test "custom module can modify body", %{credentials: credentials} do
      config = %{
        custom_module: CCXT.Signing.CustomTest.BodySigner
      }

      request = %{
        method: :post,
        path: "/test",
        body: nil,
        params: %{data: "value"}
      }

      result = Custom.sign(request, credentials, config)

      # BodySigner adds a wrapper
      assert result.body == ~s({"wrapped":{"data":"value"}})
    end
  end

  # Test signer module that implements the Custom behaviour
  defmodule TestSigner do
    @moduledoc false
    @behaviour Custom

    @impl true
    def sign(request, credentials, _config) do
      %{
        url: request.path,
        method: request.method,
        headers: [
          {"X-Custom-Signed", "true"},
          {"X-Custom-API-Key", credentials.api_key}
        ],
        body: nil
      }
    end
  end

  # Test signer that uses params
  defmodule ParamSigner do
    @moduledoc false
    @behaviour Custom

    @impl true
    def sign(request, _credentials, _config) do
      query =
        Enum.map_join(request.params, "&", fn {k, v} -> "#{k}=#{v}" end)

      url = if query == "", do: request.path, else: "#{request.path}?#{query}"

      %{
        url: url,
        method: request.method,
        headers: [],
        body: nil
      }
    end
  end

  # Test signer that uses config
  defmodule ConfigSigner do
    @moduledoc false
    @behaviour Custom

    @impl true
    def sign(request, _credentials, config) do
      %{
        url: request.path,
        method: request.method,
        headers: [
          {config.custom_header, config.custom_value}
        ],
        body: nil
      }
    end
  end

  # Test signer that modifies body
  defmodule BodySigner do
    @moduledoc false
    @behaviour Custom

    @impl true
    def sign(request, _credentials, _config) do
      body =
        if request.params == %{} do
          nil
        else
          Jason.encode!(%{wrapped: request.params})
        end

      %{
        url: request.path,
        method: request.method,
        headers: [{"Content-Type", "application/json"}],
        body: body
      }
    end
  end
end
