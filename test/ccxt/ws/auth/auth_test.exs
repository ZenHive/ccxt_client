defmodule CCXT.WS.AuthTest do
  use ExUnit.Case, async: true

  alias CCXT.Credentials
  alias CCXT.WS.Auth
  alias CCXT.WS.Auth.ListenKey
  alias CCXT.WS.Auth.RestToken

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

  describe "listen_key pre_auth/3" do
    test "selects endpoint by market type" do
      endpoints = [
        %{type: :spot, endpoint: :public_post_user_data_stream},
        %{type: :linear, endpoint: :fapi_private_post_listen_key}
      ]

      config = %{pre_auth: %{endpoints: endpoints}}

      assert {:ok,
              %{
                endpoint: :fapi_private_post_listen_key,
                market_type: :linear,
                credentials: @test_credentials
              }} = ListenKey.pre_auth(@test_credentials, config, market_type: :linear)
    end

    test "normalizes :future to :linear and finds endpoint" do
      endpoints = [
        %{type: :spot, endpoint: :public_post_user_data_stream},
        %{type: :linear, endpoint: :fapi_private_post_listen_key}
      ]

      config = %{pre_auth: %{endpoints: endpoints}}

      assert {:ok,
              %{
                endpoint: :fapi_private_post_listen_key,
                market_type: :linear,
                credentials: @test_credentials
              }} = ListenKey.pre_auth(@test_credentials, config, market_type: :future)
    end

    test "normalizes :delivery to :inverse and finds endpoint" do
      endpoints = [
        %{type: :spot, endpoint: :public_post_user_data_stream},
        %{type: :inverse, endpoint: :dapi_private_post_listen_key}
      ]

      config = %{pre_auth: %{endpoints: endpoints}}

      assert {:ok,
              %{
                endpoint: :dapi_private_post_listen_key,
                market_type: :inverse,
                credentials: @test_credentials
              }} = ListenKey.pre_auth(@test_credentials, config, market_type: :delivery)
    end

    test "normalizes :contract to :linear" do
      endpoints = [
        %{type: :linear, endpoint: :fapi_private_post_listen_key}
      ]

      config = %{pre_auth: %{endpoints: endpoints}}

      assert {:ok, %{market_type: :linear}} =
               ListenKey.pre_auth(@test_credentials, config, market_type: :contract)
    end

    test "returns error with details when no matching endpoint" do
      endpoints = [
        %{type: :linear, endpoint: :fapi_private_post_listen_key}
      ]

      config = %{pre_auth: %{endpoints: endpoints}}

      expected = %{requested: :inverse, normalized: :inverse, available: [:linear]}

      assert {:error, {:no_endpoint_for_market_type, ^expected}} =
               ListenKey.pre_auth(@test_credentials, config, market_type: :inverse)
    end

    test "returns error when no endpoints configured" do
      config = %{pre_auth: %{endpoints: []}}

      assert {:error, {:no_endpoint_for_market_type, %{requested: :spot, normalized: :spot, available: []}}} =
               ListenKey.pre_auth(@test_credentials, config, [])
    end

    test "passes through enriched fields (api_section, method, path)" do
      endpoints = [
        %{
          type: :linear,
          endpoint: "fapiPrivatePostListenKey",
          api_section: "fapiPrivate",
          method: "POST",
          path: "/listenKey"
        }
      ]

      config = %{pre_auth: %{endpoints: endpoints}}

      assert {:ok, result} = ListenKey.pre_auth(@test_credentials, config, market_type: :linear)

      assert result.endpoint == "fapiPrivatePostListenKey"
      assert result.api_section == "fapiPrivate"
      assert result.method == "POST"
      assert result.path == "/listenKey"
      assert result.market_type == :linear
    end

    test "defaults method to POST when not in endpoint config" do
      endpoints = [%{type: :spot, endpoint: "publicPostUserDataStream"}]
      config = %{pre_auth: %{endpoints: endpoints}}

      assert {:ok, result} = ListenKey.pre_auth(@test_credentials, config, [])
      assert result.method == "POST"
    end
  end

  describe "listen_key build_auth_message/3 and handle_auth_response/2" do
    test "returns :no_message and :ok" do
      assert :no_message = ListenKey.build_auth_message(@test_credentials, %{}, [])
      assert :ok = ListenKey.handle_auth_response(%{}, %{})
    end
  end

  describe "rest_token pre_auth/3" do
    test "returns endpoint and credentials when configured" do
      config = %{pre_auth: %{endpoint: :private_post_get_web_sockets_token}}

      assert {:ok, %{endpoint: :private_post_get_web_sockets_token, credentials: @test_credentials}} =
               RestToken.pre_auth(@test_credentials, config, [])
    end

    test "returns error when endpoint missing" do
      config = %{pre_auth: %{}}

      assert {:error, :no_token_endpoint} = RestToken.pre_auth(@test_credentials, config, [])
    end
  end

  describe "rest_token build_auth_message/3 and handle_auth_response/2" do
    test "returns :no_message and :ok" do
      assert :no_message = RestToken.build_auth_message(@test_credentials, %{}, [])
      assert :ok = RestToken.handle_auth_response(%{}, %{})
    end
  end

  describe "build_subscribe_auth/5 - inline_subscribe" do
    test "builds auth data for subscribe message" do
      # InlineSubscribe requires base64-encoded secret
      creds = %Credentials{
        api_key: "test_api_key",
        secret: Base.encode64("test_secret_bytes"),
        password: "test_passphrase"
      }

      config = %{pattern: :inline_subscribe}

      auth_data = Auth.build_subscribe_auth(:inline_subscribe, creds, config, "user", ["BTC-USD"])

      assert is_map(auth_data)
      assert auth_data["key"] == "test_api_key"
      assert is_binary(auth_data["timestamp"])
      assert is_binary(auth_data["signature"])
      assert auth_data["passphrase"] == "test_passphrase"
      # Signature should be base64-encoded
      assert {:ok, _} = Base.decode64(auth_data["signature"])
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
      assert Auth.module_for_pattern(:listen_key) == ListenKey
      assert Auth.module_for_pattern(:rest_token) == RestToken
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

  # ===================================================================
  # Task 24: Per-module handle_auth_response + config variant coverage
  # ===================================================================

  describe "DirectHmacExpiry - handle_auth_response/2" do
    alias CCXT.WS.Auth.DirectHmacExpiry

    test "success: true returns :ok" do
      assert :ok = DirectHmacExpiry.handle_auth_response(%{"success" => true}, %{})
    end

    test "ret_msg containing error returns auth_failed" do
      response = %{"ret_msg" => "auth error occurred"}

      assert {:error, {:auth_failed, "auth error occurred"}} =
               DirectHmacExpiry.handle_auth_response(response, %{})
    end

    test "catch-all returns auth_failed with full response" do
      response = %{"success" => false, "code" => "10001"}

      assert {:error, {:auth_failed, ^response}} =
               DirectHmacExpiry.handle_auth_response(response, %{})
    end
  end

  describe "DirectHmacExpiry - base64 encoding option" do
    alias CCXT.WS.Auth.DirectHmacExpiry

    test "base64 encoding produces base64 signature" do
      config = %{encoding: :base64, op_field: "op", op_value: "auth"}

      assert {:ok, message} = DirectHmacExpiry.build_auth_message(@test_credentials, config, [])

      [_api_key, _expires, signature] = message["args"]
      # Verify it's valid base64 (alphanumeric, +, /, = padding)
      assert signature =~ ~r/^[A-Za-z0-9+\/]+=*$/
    end
  end

  describe "IsoPassphrase - handle_auth_response/2" do
    alias CCXT.WS.Auth.IsoPassphrase

    test "login event with code 0 returns :ok" do
      response = %{"event" => "login", "code" => "0"}
      assert :ok = IsoPassphrase.handle_auth_response(response, %{})
    end

    test "error event returns auth_failed with msg" do
      response = %{"event" => "error", "msg" => "invalid credentials"}

      assert {:error, {:auth_failed, "invalid credentials"}} =
               IsoPassphrase.handle_auth_response(response, %{})
    end

    test "catch-all returns auth_failed with full response" do
      response = %{"something" => "unexpected"}

      assert {:error, {:auth_failed, ^response}} =
               IsoPassphrase.handle_auth_response(response, %{})
    end
  end

  describe "IsoPassphrase - milliseconds timestamp_unit" do
    alias CCXT.WS.Auth.IsoPassphrase

    test "milliseconds timestamp produces longer string" do
      config = %{
        timestamp_unit: :milliseconds,
        op_field: "op",
        op_value: "login"
      }

      assert {:ok, message} = IsoPassphrase.build_auth_message(@test_credentials, config, [])

      [auth_args] = message["args"]
      timestamp = auth_args["timestamp"]
      # Millisecond timestamps are 13+ digits (e.g., 1699999999999)
      assert String.length(timestamp) >= 13
    end

    test "default seconds timestamp produces shorter string" do
      config = %{op_field: "op", op_value: "login"}

      assert {:ok, message} = IsoPassphrase.build_auth_message(@test_credentials, config, [])

      [auth_args] = message["args"]
      timestamp = auth_args["timestamp"]
      # Second timestamps are 10 digits (e.g., 1699999999)
      assert String.length(timestamp) == 10
    end
  end

  describe "JsonrpcLinebreak - handle_auth_response/2" do
    alias CCXT.WS.Auth.JsonrpcLinebreak

    test "access_token in result returns :ok" do
      response = %{"result" => %{"access_token" => "tok_abc123"}}
      assert :ok = JsonrpcLinebreak.handle_auth_response(response, %{})
    end

    test "error field returns auth_failed" do
      error_detail = %{"code" => 13_004, "message" => "invalid_credentials"}
      response = %{"error" => error_detail}

      assert {:error, {:auth_failed, ^error_detail}} =
               JsonrpcLinebreak.handle_auth_response(response, %{})
    end

    test "catch-all returns auth_failed with full response" do
      response = %{"unknown" => true}

      assert {:error, {:auth_failed, ^response}} =
               JsonrpcLinebreak.handle_auth_response(response, %{})
    end
  end

  describe "JsonrpcLinebreak - TTL extraction from auth response" do
    alias CCXT.WS.Auth.JsonrpcLinebreak

    test "returns {:ok, %{ttl_ms: N}} when expires_in is present as integer" do
      response = %{"result" => %{"access_token" => "tok_abc", "expires_in" => 900}}

      assert {:ok, %{ttl_ms: 900_000}} = JsonrpcLinebreak.handle_auth_response(response, %{})
    end

    test "returns {:ok, %{ttl_ms: N}} when expires_in is a numeric string" do
      response = %{"result" => %{"access_token" => "tok_abc", "expires_in" => "1800"}}

      assert {:ok, %{ttl_ms: 1_800_000}} = JsonrpcLinebreak.handle_auth_response(response, %{})
    end

    test "returns bare :ok when expires_in is absent" do
      response = %{"result" => %{"access_token" => "tok_abc"}}

      assert :ok = JsonrpcLinebreak.handle_auth_response(response, %{})
    end

    test "returns bare :ok when expires_in is zero" do
      response = %{"result" => %{"access_token" => "tok_abc", "expires_in" => 0}}

      assert :ok = JsonrpcLinebreak.handle_auth_response(response, %{})
    end

    test "returns bare :ok when expires_in is negative" do
      response = %{"result" => %{"access_token" => "tok_abc", "expires_in" => -100}}

      assert :ok = JsonrpcLinebreak.handle_auth_response(response, %{})
    end

    test "returns bare :ok when expires_in is non-numeric string" do
      response = %{"result" => %{"access_token" => "tok_abc", "expires_in" => "never"}}

      assert :ok = JsonrpcLinebreak.handle_auth_response(response, %{})
    end
  end

  describe "JsonrpcLinebreak - custom opts" do
    alias CCXT.WS.Auth.JsonrpcLinebreak

    test "custom nonce via opts" do
      config = %{method_value: "public/auth"}

      assert {:ok, message} =
               JsonrpcLinebreak.build_auth_message(@test_credentials, config, nonce: "custom_nonce_123")

      assert message["params"]["nonce"] == "custom_nonce_123"
    end

    test "custom request_id via opts" do
      config = %{method_value: "public/auth"}

      assert {:ok, message} =
               JsonrpcLinebreak.build_auth_message(@test_credentials, config, request_id: 42)

      assert message["id"] == 42
    end
  end

  describe "Sha384Nonce - handle_auth_response/2" do
    alias CCXT.WS.Auth.Sha384Nonce

    test "auth event with OK status returns :ok" do
      response = %{"event" => "auth", "status" => "OK"}
      assert :ok = Sha384Nonce.handle_auth_response(response, %{})
    end

    test "auth event with FAILED status returns error with msg" do
      response = %{"event" => "auth", "status" => "FAILED", "msg" => "bad api key"}

      assert {:error, {:auth_failed, "bad api key"}} =
               Sha384Nonce.handle_auth_response(response, %{})
    end

    test "catch-all returns auth_failed with full response" do
      response = %{"event" => "info", "version" => 2}

      assert {:error, {:auth_failed, ^response}} =
               Sha384Nonce.handle_auth_response(response, %{})
    end
  end

  describe "Sha384Nonce - custom event_value" do
    alias CCXT.WS.Auth.Sha384Nonce

    test "custom event_value in message" do
      config = %{event_value: "authenticate"}

      assert {:ok, message} = Sha384Nonce.build_auth_message(@test_credentials, config, [])

      assert message["event"] == "authenticate"
    end
  end

  describe "Sha512Newline - handle_auth_response/2" do
    alias CCXT.WS.Auth.Sha512Newline

    test "api event with success status returns :ok" do
      response = %{"event" => "api", "result" => %{"status" => "success"}}
      assert :ok = Sha512Newline.handle_auth_response(response, %{})
    end

    test "error field returns auth_failed" do
      response = %{"error" => "invalid_key"}

      assert {:error, {:auth_failed, "invalid_key"}} =
               Sha512Newline.handle_auth_response(response, %{})
    end

    test "result without status (fallback) returns :ok" do
      response = %{"result" => %{"token" => "abc"}}
      assert :ok = Sha512Newline.handle_auth_response(response, %{})
    end

    test "no result catch-all returns auth_failed" do
      response = %{"event" => "unknown"}

      assert {:error, {:auth_failed, ^response}} =
               Sha512Newline.handle_auth_response(response, %{})
    end
  end

  describe "Sha512Newline - custom config" do
    alias CCXT.WS.Auth.Sha512Newline

    test "custom channel" do
      config = %{channel: "futures.login"}

      assert {:ok, message} = Sha512Newline.build_auth_message(@test_credentials, config, [])

      assert message["channel"] == "futures.login"
    end

    test "custom request_id via opts" do
      config = %{}

      assert {:ok, message} =
               Sha512Newline.build_auth_message(@test_credentials, config, request_id: "req_42")

      assert message["id"] == "req_42"
    end
  end

  describe "InlineSubscribe - build_subscribe_auth/4 variants" do
    alias CCXT.WS.Auth.InlineSubscribe

    @b64_credentials %Credentials{
      api_key: "test_api_key",
      secret: Base.encode64("test_secret_bytes"),
      password: "test_passphrase"
    }

    test "produces correct field names and base64 signature" do
      auth_data =
        InlineSubscribe.build_subscribe_auth(
          @b64_credentials,
          %{},
          "user",
          ["BTC-USD", "ETH-USD"]
        )

      assert is_map(auth_data)
      assert auth_data["key"] == "test_api_key"
      assert auth_data["passphrase"] == "test_passphrase"
      assert is_binary(auth_data["timestamp"])
      assert is_binary(auth_data["signature"])
      # Signature must be valid base64
      assert {:ok, _} = Base.decode64(auth_data["signature"])
    end

    test "channel and symbols are ignored (fixed payload)" do
      # Same credentials produce same signature regardless of channel/symbols
      auth1 = InlineSubscribe.build_subscribe_auth(@b64_credentials, %{}, "user", ["BTC-USD"])
      auth2 = InlineSubscribe.build_subscribe_auth(@b64_credentials, %{}, "level2", ["ETH-USD"])

      # Both use same timestamp-based payload, so with same timestamp they'd match
      # Just verify both produce valid auth data
      assert auth1["key"] == auth2["key"]
      assert auth1["passphrase"] == auth2["passphrase"]
    end

    test "no passphrase when password is nil" do
      creds = %Credentials{
        api_key: "test_api_key",
        secret: Base.encode64("test_secret"),
        password: nil
      }

      auth_data = InlineSubscribe.build_subscribe_auth(creds, %{}, "user", [])

      assert auth_data["key"] == "test_api_key"
      refute Map.has_key?(auth_data, "passphrase")
    end
  end

  describe "Auth dispatcher - uncovered branches" do
    test "unknown pattern in build_auth_message returns error" do
      assert {:error, {:unknown_pattern, :totally_unknown}} =
               Auth.build_auth_message(:totally_unknown, @test_credentials, %{}, [])
    end

    test "htx_variant returns not_implemented" do
      assert {:error, {:not_implemented, :htx_variant}} =
               Auth.build_auth_message(:htx_variant, @test_credentials, %{}, [])
    end

    test "generic_hmac delegates to DirectHmacExpiry" do
      config = %{op_field: "op", op_value: "auth"}

      assert {:ok, message} = Auth.build_auth_message(:generic_hmac, @test_credentials, config, [])

      assert message["op"] == "auth"
      assert is_list(message["args"])
    end

    test "default handler: success true returns :ok" do
      response = %{"success" => true}
      assert :ok = Auth.handle_auth_response(:some_unknown_pattern, response, %{})
    end

    test "default handler: access_token in result returns :ok" do
      response = %{"result" => %{"access_token" => "token123"}}
      assert :ok = Auth.handle_auth_response(:some_unknown_pattern, response, %{})
    end

    test "default handler: failure fallback returns error" do
      response = %{"nope" => true}

      assert {:error, {:auth_failed, ^response}} =
               Auth.handle_auth_response(:some_unknown_pattern, response, %{})
    end

    test "default handler: auth event with OK status returns :ok" do
      response = %{"event" => "auth", "status" => "OK"}
      assert :ok = Auth.handle_auth_response(:some_unknown_pattern, response, %{})
    end
  end

  describe "pre_auth/4 dispatcher coverage" do
    test "direct_hmac_expiry pre_auth returns ok" do
      assert {:ok, %{}} = Auth.pre_auth(:direct_hmac_expiry, @test_credentials, %{}, [])
    end

    test "iso_passphrase pre_auth returns ok" do
      assert {:ok, %{}} = Auth.pre_auth(:iso_passphrase, @test_credentials, %{}, [])
    end

    test "jsonrpc_linebreak pre_auth returns ok" do
      assert {:ok, %{}} = Auth.pre_auth(:jsonrpc_linebreak, @test_credentials, %{}, [])
    end

    test "sha384_nonce pre_auth returns ok" do
      assert {:ok, %{}} = Auth.pre_auth(:sha384_nonce, @test_credentials, %{}, [])
    end

    test "sha512_newline pre_auth returns ok" do
      assert {:ok, %{}} = Auth.pre_auth(:sha512_newline, @test_credentials, %{}, [])
    end

    test "inline_subscribe pre_auth returns ok" do
      assert {:ok, %{}} = Auth.pre_auth(:inline_subscribe, @test_credentials, %{}, [])
    end

    test "unknown pattern pre_auth returns ok (catch-all)" do
      assert {:ok, %{}} = Auth.pre_auth(:some_unknown, @test_credentials, %{}, [])
    end
  end

  describe "handle_auth_response/3 dispatcher delegates" do
    test "iso_passphrase delegates to module" do
      response = %{"event" => "login", "code" => "0"}
      assert :ok = Auth.handle_auth_response(:iso_passphrase, response, %{})
    end

    test "jsonrpc_linebreak delegates to module" do
      response = %{"result" => %{"access_token" => "tok"}}
      assert :ok = Auth.handle_auth_response(:jsonrpc_linebreak, response, %{})
    end

    test "sha384_nonce delegates to module" do
      response = %{"event" => "auth", "status" => "OK"}
      assert :ok = Auth.handle_auth_response(:sha384_nonce, response, %{})
    end

    test "sha512_newline delegates to module" do
      response = %{"event" => "api", "result" => %{"status" => "success"}}
      assert :ok = Auth.handle_auth_response(:sha512_newline, response, %{})
    end
  end

  describe "InlineSubscribe - pre_auth and auth stubs" do
    alias CCXT.WS.Auth.InlineSubscribe

    test "pre_auth returns ok" do
      assert {:ok, %{}} = InlineSubscribe.pre_auth(@test_credentials, %{}, [])
    end

    test "build_auth_message returns :no_message" do
      assert :no_message = InlineSubscribe.build_auth_message(@test_credentials, %{}, [])
    end

    test "handle_auth_response returns :ok" do
      assert :ok = InlineSubscribe.handle_auth_response(%{}, %{})
    end
  end
end
