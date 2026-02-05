defmodule CCXT.WS.AuthTest do
  use ExUnit.Case, async: true

  alias CCXT.Credentials
  alias CCXT.WS.Auth

  @test_credentials %Credentials{
    api_key: "test_api_key",
    secret: "test_api_secret",
    password: "test_passphrase"
  }

  describe "patterns/0" do
    test "returns list of known patterns" do
      patterns = Auth.patterns()

      assert :direct_hmac_expiry in patterns
      assert :iso_passphrase in patterns
      assert :jsonrpc_linebreak in patterns
      assert :sha384_nonce in patterns
      assert :sha512_newline in patterns
      assert :listen_key in patterns
      assert :rest_token in patterns
      assert :inline_subscribe in patterns
    end
  end

  describe "requires_pre_auth?/1" do
    test "listen_key requires pre-auth" do
      assert Auth.requires_pre_auth?(:listen_key)
    end

    test "rest_token requires pre-auth" do
      assert Auth.requires_pre_auth?(:rest_token)
    end

    test "direct_hmac_expiry does not require pre-auth" do
      refute Auth.requires_pre_auth?(:direct_hmac_expiry)
    end

    test "iso_passphrase does not require pre-auth" do
      refute Auth.requires_pre_auth?(:iso_passphrase)
    end
  end

  describe "inline_auth?/1" do
    test "inline_subscribe uses inline auth" do
      assert Auth.inline_auth?(:inline_subscribe)
    end

    test "direct_hmac_expiry does not use inline auth" do
      refute Auth.inline_auth?(:direct_hmac_expiry)
    end
  end

  describe "build_auth_message/4 - direct_hmac_expiry" do
    test "builds op/args format message" do
      config = %{
        pattern: :direct_hmac_expiry,
        op_field: "op",
        op_value: "auth"
      }

      assert {:ok, message} = Auth.build_auth_message(:direct_hmac_expiry, @test_credentials, config, [])

      assert message["op"] == "auth"
      assert is_list(message["args"])
      assert length(message["args"]) == 3

      [api_key, expires, signature] = message["args"]
      assert api_key == "test_api_key"
      assert is_integer(expires)
      assert is_binary(signature)
    end
  end

  describe "build_auth_message/4 - iso_passphrase" do
    test "builds login message with passphrase" do
      config = %{
        pattern: :iso_passphrase,
        op_field: "op",
        op_value: "login"
      }

      assert {:ok, message} = Auth.build_auth_message(:iso_passphrase, @test_credentials, config, [])

      assert message["op"] == "login"
      assert is_list(message["args"])
      assert length(message["args"]) == 1

      [auth_args] = message["args"]
      assert auth_args["apiKey"] == "test_api_key"
      assert auth_args["passphrase"] == "test_passphrase"
      assert is_binary(auth_args["timestamp"])
      assert is_binary(auth_args["sign"])
    end
  end

  describe "build_auth_message/4 - jsonrpc_linebreak" do
    test "builds JSON-RPC format message" do
      config = %{
        pattern: :jsonrpc_linebreak,
        method_value: "public/auth"
      }

      assert {:ok, message} = Auth.build_auth_message(:jsonrpc_linebreak, @test_credentials, config, [])

      assert message["jsonrpc"] == "2.0"
      assert message["method"] == "public/auth"
      assert is_integer(message["id"])
      assert is_map(message["params"])

      params = message["params"]
      assert params["grant_type"] == "client_signature"
      assert params["client_id"] == "test_api_key"
      assert is_integer(params["timestamp"])
      assert is_binary(params["signature"])
      assert is_binary(params["nonce"])
    end
  end

  describe "build_auth_message/4 - sha384_nonce" do
    test "builds event/auth format message" do
      config = %{
        pattern: :sha384_nonce,
        event_value: "auth"
      }

      assert {:ok, message} = Auth.build_auth_message(:sha384_nonce, @test_credentials, config, [])

      assert message["event"] == "auth"
      assert message["apiKey"] == "test_api_key"
      assert is_binary(message["authSig"])
      assert is_integer(message["authNonce"])
      assert is_binary(message["authPayload"])
    end
  end

  describe "build_auth_message/4 - sha512_newline" do
    test "builds channel/event format message" do
      config = %{
        pattern: :sha512_newline,
        event_field: "event",
        event_value: "login"
      }

      assert {:ok, message} = Auth.build_auth_message(:sha512_newline, @test_credentials, config, [])

      assert message["event"] == "api"
      assert message["channel"] == "spot.login"
      assert is_integer(message["time"])

      payload = message["payload"]
      assert payload["api_key"] == "test_api_key"
      assert is_binary(payload["signature"])
      assert is_binary(payload["timestamp"])
    end
  end

  describe "build_auth_message/4 - patterns without WS messages" do
    test "listen_key returns :no_message" do
      config = %{pattern: :listen_key}

      assert :no_message = Auth.build_auth_message(:listen_key, @test_credentials, config, [])
    end

    test "rest_token returns :no_message" do
      config = %{pattern: :rest_token}

      assert :no_message = Auth.build_auth_message(:rest_token, @test_credentials, config, [])
    end

    test "inline_subscribe returns :no_message" do
      config = %{pattern: :inline_subscribe}

      assert :no_message = Auth.build_auth_message(:inline_subscribe, @test_credentials, config, [])
    end
  end

  describe "build_subscribe_auth/5 - inline_subscribe" do
    test "builds auth data for subscribe message" do
      config = %{pattern: :inline_subscribe}

      auth_data = Auth.build_subscribe_auth(:inline_subscribe, @test_credentials, config, "user", ["BTC-USD"])

      assert is_map(auth_data)
      assert auth_data["api_key"] == "test_api_key"
      assert is_binary(auth_data["timestamp"])
      assert is_binary(auth_data["signature"])
    end
  end

  describe "build_subscribe_auth/5 - rest_token" do
    test "includes token from config" do
      config = %{pattern: :rest_token, token: "ws_token_123"}

      auth_data = Auth.build_subscribe_auth(:rest_token, @test_credentials, config, "channel", [])

      assert auth_data == %{"token" => "ws_token_123"}
    end

    test "returns nil when no token" do
      config = %{pattern: :rest_token}

      auth_data = Auth.build_subscribe_auth(:rest_token, @test_credentials, config, "channel", [])

      assert auth_data == nil
    end
  end

  describe "build_subscribe_auth/5 - other patterns" do
    test "returns nil for patterns without subscribe auth" do
      config = %{pattern: :direct_hmac_expiry}

      assert Auth.build_subscribe_auth(:direct_hmac_expiry, @test_credentials, config, "ch", []) == nil
    end
  end

  describe "module_for_pattern/1" do
    test "returns correct module for each pattern" do
      assert Auth.module_for_pattern(:direct_hmac_expiry) == CCXT.WS.Auth.DirectHmacExpiry
      assert Auth.module_for_pattern(:iso_passphrase) == CCXT.WS.Auth.IsoPassphrase
      assert Auth.module_for_pattern(:jsonrpc_linebreak) == CCXT.WS.Auth.JsonrpcLinebreak
      assert Auth.module_for_pattern(:sha384_nonce) == CCXT.WS.Auth.Sha384Nonce
      assert Auth.module_for_pattern(:sha512_newline) == CCXT.WS.Auth.Sha512Newline
      assert Auth.module_for_pattern(:listen_key) == CCXT.WS.Auth.ListenKey
      assert Auth.module_for_pattern(:rest_token) == CCXT.WS.Auth.RestToken
      assert Auth.module_for_pattern(:inline_subscribe) == CCXT.WS.Auth.InlineSubscribe
    end

    test "returns nil for unknown pattern" do
      assert Auth.module_for_pattern(:unknown) == nil
    end
  end

  describe "handle_auth_response/3" do
    test "returns :ok for success response with success: true" do
      response = %{"success" => true}
      assert :ok = Auth.handle_auth_response(:direct_hmac_expiry, response, %{})
    end

    test "returns :ok for event auth with OK status" do
      response = %{"event" => "auth", "status" => "OK"}
      assert :ok = Auth.handle_auth_response(:generic_hmac, response, %{})
    end

    test "returns error for failed auth" do
      response = %{"success" => false, "ret_msg" => "auth error"}

      assert {:error, {:auth_failed, _}} =
               Auth.handle_auth_response(:direct_hmac_expiry, response, %{})
    end
  end
end
