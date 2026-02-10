defmodule CCXT.HTTP.ClientTest do
  # async: false required because Req.Test.stub uses global process dictionary state
  # that would conflict between concurrent tests
  use ExUnit.Case, async: false

  alias CCXT.Credentials
  alias CCXT.Error
  alias CCXT.HTTP.Client
  alias CCXT.Spec

  @moduletag :unit
  # Suppress telemetry info logs about local function handlers
  @moduletag capture_log: true

  # Note: exchange_id (atom) is normally pre-computed at compile time by Generator,
  # but for tests we must set it explicitly since we're creating specs manually
  @test_spec %Spec{
    id: "testexchange",
    exchange_id: :testexchange,
    name: "Test Exchange",
    urls: %{
      api: "https://api.testexchange.com",
      sandbox: "https://sandbox.testexchange.com"
    },
    signing: %{
      pattern: :hmac_sha256_headers,
      api_key_header: "X-API-KEY",
      timestamp_header: "X-TIMESTAMP",
      signature_header: "X-SIGNATURE"
    },
    error_codes: %{
      10_001 => :insufficient_balance,
      10_002 => :order_not_found,
      10_003 => :invalid_order,
      "RATE_LIMIT" => :rate_limited
    },
    error_code_details: %{
      10_001 => %{type: :insufficient_balance, description: "Balance too low"},
      10_002 => %{type: :order_not_found, description: "Order does not exist"},
      10_003 => %{type: :invalid_order, description: "Order is invalid"},
      "RATE_LIMIT" => %{type: :rate_limited, description: "Rate limit exceeded"}
    }
  }

  @test_credentials %Credentials{
    api_key: "test_api_key",
    secret: "test_secret",
    sandbox: true
  }

  describe "request/4 telemetry" do
    setup do
      # Attach telemetry handler for testing
      ref = make_ref()
      parent = self()

      handler_id = "test-handler-#{inspect(ref)}"

      :telemetry.attach_many(
        handler_id,
        [
          [:ccxt, :request, :start],
          [:ccxt, :request, :stop],
          [:ccxt, :request, :exception]
        ],
        fn event, measurements, metadata, _config ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)

      :ok
    end

    test "emits start and stop events on success" do
      Req.Test.stub(:success_stub, fn conn ->
        Req.Test.json(conn, %{result: "ok"})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      {:ok, _} = Client.request(spec, :get, "/test", plug: {Req.Test, :success_stub})

      assert_receive {:telemetry, [:ccxt, :request, :start], %{system_time: _},
                      %{exchange: :testexchange, method: :get, path: "/test"}}

      assert_receive {:telemetry, [:ccxt, :request, :stop], %{duration: _},
                      %{exchange: :testexchange, method: :get, path: "/test", status: 200}}
    end

    test "emits stop event on error response" do
      Req.Test.stub(:error_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{error: "Server error"})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      Client.request(spec, :get, "/error", plug: {Req.Test, :error_stub})

      assert_receive {:telemetry, [:ccxt, :request, :start], _, _}
      assert_receive {:telemetry, [:ccxt, :request, :stop], _, %{status: 500}}
    end

    test "emits exception telemetry event on raised error" do
      Req.Test.stub(:exception_telemetry_stub, fn _conn ->
        raise "Telemetry test exception"
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      Client.request(spec, :get, "/test", plug: {Req.Test, :exception_telemetry_stub})

      assert_receive {:telemetry, [:ccxt, :request, :start], _, _}

      assert_receive {:telemetry, [:ccxt, :request, :exception], %{duration: _},
                      %{exchange: :testexchange, method: :get, path: "/test", kind: :exception}}
    end
  end

  describe "error normalization" do
    test "normalizes 429 to rate_limited" do
      Req.Test.stub(:rate_limit_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "5")
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{message: "Too many requests"})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :rate_limited, retry_after: 5000}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :rate_limit_stub})
    end

    test "normalizes 401 to invalid_credentials" do
      Req.Test.stub(:auth_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{message: "Invalid API key"})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :invalid_credentials}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :auth_stub})
    end

    test "normalizes 403 to invalid_credentials" do
      Req.Test.stub(:forbidden_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(403)
        |> Req.Test.json(%{message: "Forbidden"})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :invalid_credentials}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :forbidden_stub})
    end

    test "uses error_codes from spec to normalize errors" do
      Req.Test.stub(:balance_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{code: 10_001, message: "Insufficient balance"})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :insufficient_balance, code: 10_001}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :balance_stub})
    end

    test "uses error_code_details description when message is missing" do
      Req.Test.stub(:missing_message_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{code: 10_001})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      case Client.request(spec, :get, "/test", plug: {Req.Test, :missing_message_stub}) do
        {:error, %Error{type: :insufficient_balance, message: message}} ->
          assert String.contains?(message, "Balance too low")

        {:error, other} ->
          flunk("Expected insufficient_balance error, got: #{inspect(other)}")

        {:ok, response} ->
          flunk("Expected error response, got success: #{inspect(response)}")
      end
    end

    test "falls back to exchange_error for unknown codes" do
      Req.Test.stub(:unknown_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{code: 99_999, message: "Unknown error"})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :exchange_error, code: 99_999}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :unknown_stub})
    end
  end

  describe "successful responses" do
    test "returns parsed JSON body" do
      Req.Test.stub(:ticker_stub, fn conn ->
        Req.Test.json(conn, %{ticker: %{symbol: "BTC/USDT", last: 50_000}})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:ok, %{status: 200, body: body}} =
               Client.request(spec, :get, "/ticker", plug: {Req.Test, :ticker_stub})

      assert body["ticker"]["symbol"] == "BTC/USDT"
    end
  end

  describe "raw_request/5" do
    test "makes request without signing" do
      Req.Test.stub(:raw_stub, fn conn ->
        Req.Test.json(conn, %{raw: true})
      end)

      headers = [{"content-type", "application/json"}]

      assert {:ok, %{status: 200, body: body}} =
               Client.raw_request(:get, "http://localhost/raw", headers, nil, plug: {Req.Test, :raw_stub})

      assert body["raw"] == true
    end
  end

  describe "signing integration" do
    test "applies signing when credentials provided" do
      Req.Test.stub(:signed_stub, fn conn ->
        # Verify that signing headers were added
        api_key_header = Plug.Conn.get_req_header(conn, "x-api-key")
        assert api_key_header != []
        Req.Test.json(conn, %{authenticated: true})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:ok, %{status: 200, body: %{"authenticated" => true}}} =
               Client.request(spec, :get, "/private",
                 credentials: @test_credentials,
                 plug: {Req.Test, :signed_stub}
               )
    end
  end

  describe "exception handling" do
    test "returns network_error when exception is raised" do
      Req.Test.stub(:exception_stub, fn _conn ->
        raise "Simulated connection failure"
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :network_error, message: message}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :exception_stub})

      assert message =~ "Exception:"
      assert message =~ "Simulated connection failure"
    end
  end

  describe "http_config header injection" do
    test "applies static headers from http_config" do
      Req.Test.stub(:header_check_stub, fn conn ->
        # Verify that custom headers were added
        partner_id = Plug.Conn.get_req_header(conn, "apca-partner-id")
        assert partner_id == ["ccxt"]
        Req.Test.json(conn, %{headers_applied: true})
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          http_config: %{
            headers: %{"APCA-PARTNER-ID" => "ccxt"}
          }
      }

      assert {:ok, %{status: 200, body: %{"headers_applied" => true}}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :header_check_stub})
    end

    test "applies user_agent from http_config" do
      Req.Test.stub(:ua_check_stub, fn conn ->
        user_agent = Plug.Conn.get_req_header(conn, "user-agent")
        assert user_agent == ["CustomBot/1.0"]
        Req.Test.json(conn, %{ua_applied: true})
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          http_config: %{
            user_agent: "CustomBot/1.0"
          }
      }

      assert {:ok, %{status: 200, body: %{"ua_applied" => true}}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :ua_check_stub})
    end

    test "applies both headers and user_agent from http_config" do
      Req.Test.stub(:both_check_stub, fn conn ->
        cb_version = Plug.Conn.get_req_header(conn, "cb-version")
        user_agent = Plug.Conn.get_req_header(conn, "user-agent")
        assert cb_version == ["2018-05-30"]
        assert user_agent == ["Mozilla/5.0"]
        Req.Test.json(conn, %{both_applied: true})
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          http_config: %{
            headers: %{"CB-VERSION" => "2018-05-30"},
            user_agent: "Mozilla/5.0"
          }
      }

      assert {:ok, %{status: 200, body: %{"both_applied" => true}}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :both_check_stub})
    end

    test "works without http_config (nil)" do
      Req.Test.stub(:no_config_stub, fn conn ->
        Req.Test.json(conn, %{no_config: true})
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          http_config: nil
      }

      assert {:ok, %{status: 200, body: %{"no_config" => true}}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :no_config_stub})
    end

    test "applies headers to signed requests" do
      Req.Test.stub(:signed_header_stub, fn conn ->
        # Verify both signing headers and custom headers are present
        api_key = Plug.Conn.get_req_header(conn, "x-api-key")
        partner_id = Plug.Conn.get_req_header(conn, "x-gate-channel-id")
        assert api_key != []
        assert partner_id == ["ccxt"]
        Req.Test.json(conn, %{signed_with_headers: true})
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          http_config: %{
            headers: %{"X-Gate-Channel-Id" => "ccxt"}
          }
      }

      assert {:ok, %{status: 200, body: %{"signed_with_headers" => true}}} =
               Client.request(spec, :get, "/private",
                 credentials: @test_credentials,
                 plug: {Req.Test, :signed_header_stub}
               )
    end
  end

  describe "error code extraction" do
    test "handles ret_code error format" do
      Req.Test.stub(:ret_code_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{ret_code: 10_001, msg: "Insufficient balance"})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :insufficient_balance, code: 10_001}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :ret_code_stub})
    end

    test "handles retCode error format" do
      Req.Test.stub(:ret_code_camel_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{retCode: 10_002, retMsg: "Order not found"})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :order_not_found, code: 10_002}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :ret_code_camel_stub})
    end

    test "handles error_code format" do
      Req.Test.stub(:error_code_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{error_code: 10_003, error: "Invalid order"})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :invalid_order, code: 10_003}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :error_code_stub})
    end

    test "handles string error codes" do
      Req.Test.stub(:string_code_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{code: "RATE_LIMIT", message: "Rate limited"})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :rate_limited}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :string_code_stub})
    end

    test "handles non-map error body" do
      Req.Test.stub(:string_error_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(500, "Internal Server Error")
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :exchange_error, message: "Internal Server Error"}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :string_error_stub})
    end
  end

  # Task 37: Body-level error detection tests
  describe "body-level error detection (HTTP 200 with error in body)" do
    test "detects error with :success_code pattern (Bybit style)" do
      # Bybit returns HTTP 200 but retCode != 0 indicates error
      # Use error code 99999 which is not in error_codes to get generic :exchange_error
      Req.Test.stub(:bybit_error_stub, fn conn ->
        Req.Test.json(conn, %{
          "retCode" => 99_999,
          "retMsg" => "Invalid period!",
          "result" => %{}
        })
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          response_error: %{
            type: :success_code,
            field: "retCode",
            success_values: ["0"],
            code_field: "retCode",
            message_field: "retMsg"
          }
      }

      assert {:error, %Error{type: :exchange_error, code: 99_999, message: "Invalid period!"}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :bybit_error_stub})
    end

    test "passes through success with :success_code pattern" do
      Req.Test.stub(:bybit_success_stub, fn conn ->
        Req.Test.json(conn, %{
          "retCode" => 0,
          "retMsg" => "OK",
          "result" => %{"symbol" => "BTCUSDT"}
        })
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          response_error: %{
            type: :success_code,
            field: "retCode",
            success_values: ["0"],
            code_field: "retCode",
            message_field: "retMsg"
          }
      }

      assert {:ok, %{status: 200, body: body}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :bybit_success_stub})

      assert body["retCode"] == 0
    end

    test "detects error with :error_present pattern (Gate.io style)" do
      # Gate.io returns error if "label" field exists
      Req.Test.stub(:gate_error_stub, fn conn ->
        Req.Test.json(conn, %{
          "label" => "ORDER_NOT_FOUND",
          "message" => "Order not found"
        })
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          response_error: %{
            type: :error_present,
            field: "label",
            code_field: "label",
            message_field: "message"
          }
      }

      assert {:error, %Error{type: :exchange_error, code: "ORDER_NOT_FOUND", message: "Order not found"}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :gate_error_stub})
    end

    test "passes through success with :error_present pattern" do
      Req.Test.stub(:gate_success_stub, fn conn ->
        Req.Test.json(conn, %{
          "id" => "123456",
          "status" => "filled"
        })
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          response_error: %{
            type: :error_present,
            field: "label",
            code_field: "label",
            message_field: "message"
          }
      }

      assert {:ok, %{status: 200, body: body}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :gate_success_stub})

      assert body["id"] == "123456"
    end

    test "detects error with :error_array pattern (Kraken style)" do
      # Kraken returns error if "error" array is non-empty
      Req.Test.stub(:kraken_error_stub, fn conn ->
        Req.Test.json(conn, %{
          "error" => ["EOrder:Invalid order"]
        })
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          response_error: %{
            type: :error_array,
            field: "error",
            message_field: "error"
          }
      }

      assert {:error, %Error{type: :exchange_error, message: "EOrder:Invalid order"}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :kraken_error_stub})
    end

    test "passes through success with :error_array pattern" do
      Req.Test.stub(:kraken_success_stub, fn conn ->
        Req.Test.json(conn, %{
          "error" => [],
          "result" => %{"XXBTZUSD" => %{"a" => ["50000.00"]}}
        })
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          response_error: %{
            type: :error_array,
            field: "error",
            message_field: "error"
          }
      }

      assert {:ok, %{status: 200, body: body}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :kraken_success_stub})

      assert body["error"] == []
    end

    test "detects error with :error_field_present pattern (Binance style)" do
      # Binance returns error if "code" field exists
      Req.Test.stub(:binance_error_stub, fn conn ->
        Req.Test.json(conn, %{
          "code" => -1121,
          "msg" => "Invalid symbol."
        })
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          response_error: %{
            type: :error_field_present,
            field: "code",
            code_field: "code",
            message_field: "msg"
          }
      }

      assert {:error, %Error{type: :exchange_error, code: -1121, message: "Invalid symbol."}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :binance_error_stub})
    end

    test "passes through success with :error_field_present pattern" do
      # Binance success responses don't have "code" field
      Req.Test.stub(:binance_success_stub, fn conn ->
        Req.Test.json(conn, %{
          "symbol" => "BTCUSDT",
          "price" => "50000.00"
        })
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          response_error: %{
            type: :error_field_present,
            field: "code",
            code_field: "code",
            message_field: "msg"
          }
      }

      assert {:ok, %{status: 200, body: body}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :binance_success_stub})

      assert body["symbol"] == "BTCUSDT"
    end

    test "detects error with :success_bool pattern" do
      Req.Test.stub(:success_bool_error_stub, fn conn ->
        Req.Test.json(conn, %{
          "success" => false,
          "error" => "Something went wrong"
        })
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          response_error: %{
            type: :success_bool,
            field: "success",
            message_field: "error"
          }
      }

      assert {:error, %Error{type: :exchange_error, message: "Something went wrong"}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :success_bool_error_stub})
    end

    test "maps error codes to typed errors via error_codes" do
      Req.Test.stub(:typed_error_stub, fn conn ->
        Req.Test.json(conn, %{
          "retCode" => 10_001,
          "retMsg" => "Insufficient balance"
        })
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          response_error: %{
            type: :success_code,
            field: "retCode",
            success_values: ["0"],
            code_field: "retCode",
            message_field: "retMsg"
          }
      }

      # error_codes in @test_spec maps 10_001 => :insufficient_balance
      assert {:error, %Error{type: :insufficient_balance, code: 10_001}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :typed_error_stub})
    end

    test "handles multiple field names (first match wins)" do
      # Some exchanges use different field names in different API versions
      Req.Test.stub(:multi_field_stub, fn conn ->
        Req.Test.json(conn, %{
          "ret_code" => 10_001,
          "ret_msg" => "Error from ret_code"
        })
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          error_code_details: %{},
          response_error: %{
            type: :success_code,
            field: ["retCode", "ret_code"],
            success_values: ["0"],
            code_field: ["retCode", "ret_code"],
            message_field: ["retMsg", "ret_msg"]
          }
      }

      assert {:error, %Error{code: 10_001, message: "Error from ret_code"}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :multi_field_stub})
    end

    test "skips body error check when response_error is nil" do
      # Without response_error config, HTTP 200 with error body should pass through
      Req.Test.stub(:no_config_error_stub, fn conn ->
        Req.Test.json(conn, %{
          "retCode" => 10_001,
          "retMsg" => "This would be an error if configured"
        })
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          response_error: nil
      }

      # Should return success since no response_error config
      assert {:ok, %{status: 200, body: body}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :no_config_error_stub})

      assert body["retCode"] == 10_001
    end

    test "handles non-map body gracefully" do
      Req.Test.stub(:string_body_stub, fn conn ->
        Plug.Conn.send_resp(conn, 200, "plain text response")
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          response_error: %{
            type: :success_code,
            field: "retCode",
            success_values: ["0"]
          }
      }

      # Should return success since body is not a map
      assert {:ok, %{status: 200, body: "plain text response"}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :string_body_stub})
    end
  end

  # Note: param_mappings are applied at the endpoint level in generated functions
  # (via CCXT.Generator.Helpers.apply_endpoint_mappings), NOT in Client.request.
  # This is intentional - spec-level mappings caused conflicts (e.g., KuCoin symbol→symbols).
  # See CCXT.Generator.Helpers tests for param_mappings coverage.

  describe "HTML response detection (geographic/access restrictions)" do
    test "detects HTML via Content-Type header and returns access_restricted error" do
      Req.Test.stub(:html_content_type_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, """
        <!DOCTYPE html>
        <html><head><title>Access Denied</title></head>
        <body>Your region is restricted</body></html>
        """)
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :access_restricted} = error} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :html_content_type_stub})

      assert error.message =~ "Access Denied"
      assert error.exchange == :testexchange
      assert is_list(error.hints)
      assert error.hints != []
    end

    test "detects HTML via body markers (<!DOCTYPE) even without Content-Type header" do
      Req.Test.stub(:html_body_doctype_stub, fn conn ->
        # Some servers might not set proper Content-Type
        conn
        |> Plug.Conn.put_resp_content_type("application/octet-stream")
        |> Plug.Conn.send_resp(200, "<!DOCTYPE html><html><head><title>Blocked</title></head></html>")
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :access_restricted} = error} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :html_body_doctype_stub})

      assert error.message =~ "Blocked"
    end

    test "detects HTML via body markers (<html)" do
      Req.Test.stub(:html_body_tag_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "<html><head><title>Cloudflare Challenge</title></head></html>")
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :access_restricted} = error} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :html_body_tag_stub})

      assert error.message =~ "Cloudflare Challenge"
    end

    test "detects HTML on error status codes (403 Forbidden with HTML page)" do
      Req.Test.stub(:html_403_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(403, """
        <!DOCTYPE html>
        <html><head><title>403 Forbidden</title></head>
        <body>Access to this resource is denied</body></html>
        """)
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :access_restricted, code: 403} = error} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :html_403_stub})

      assert error.message =~ "403 Forbidden"
    end

    test "does not flag valid JSON responses as HTML" do
      Req.Test.stub(:valid_json_stub, fn conn ->
        Req.Test.json(conn, %{
          "result" => "success",
          "data" => %{"html" => "<div>some html content</div>"}
        })
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:ok, %{status: 200, body: body}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :valid_json_stub})

      assert body["result"] == "success"
    end

    test "does not flag plain text responses as HTML" do
      Req.Test.stub(:plain_text_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "OK")
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:ok, %{status: 200, body: "OK"}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :plain_text_stub})
    end

    test "extracts page title for error message" do
      Req.Test.stub(:html_with_title_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, """
        <!DOCTYPE html>
        <html>
        <head><title>OKX - Trading Platform</title></head>
        <body>Page content</body>
        </html>
        """)
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :access_restricted} = error} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :html_with_title_stub})

      assert error.message =~ "OKX - Trading Platform"
      assert error.raw[:page_title] == "OKX - Trading Platform"
    end

    test "handles HTML without title gracefully" do
      Req.Test.stub(:html_no_title_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<!DOCTYPE html><html><body>No title here</body></html>")
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :access_restricted} = error} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :html_no_title_stub})

      assert error.message == "Received HTML instead of JSON API response"
      assert error.raw[:page_title] == nil
    end

    test "includes body preview in raw error data" do
      long_html =
        "<!DOCTYPE html><html><head><title>Test</title></head><body>" <> String.duplicate("x", 500) <> "</body></html>"

      Req.Test.stub(:html_long_body_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, long_html)
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :access_restricted} = error} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :html_long_body_stub})

      # Body preview should be truncated to 200 chars
      assert String.length(error.raw[:body_preview]) == 200
    end

    test "provides actionable hints in error" do
      Req.Test.stub(:html_hints_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<!DOCTYPE html><html><body>Blocked</body></html>")
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      assert {:error, %Error{type: :access_restricted} = error} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :html_hints_stub})

      assert "Verify the API URL is correct (check path_prefix in spec)" in error.hints
      assert Enum.any?(error.hints, &String.contains?(&1, "curl"))
    end
  end

  # Task 100: Broker ID support for volume attribution
  describe "broker header injection" do
    test "injects broker header from signing config when options has broker ID" do
      Req.Test.stub(:broker_header_stub, fn conn ->
        # Verify that broker header was added
        referer = Plug.Conn.get_req_header(conn, "referer")
        assert referer == ["MY_BROKER_ID"]
        Req.Test.json(conn, %{broker_applied: true})
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          signing: %{
            pattern: :hmac_sha256_headers,
            broker_config: %{header: "Referer", option_key: "brokerId"}
          },
          options: %{"brokerId" => "MY_BROKER_ID"}
      }

      assert {:ok, %{status: 200, body: %{"broker_applied" => true}}} =
               Client.request(spec, :get, "/private",
                 credentials: @test_credentials,
                 plug: {Req.Test, :broker_header_stub}
               )
    end

    test "respects application config override for broker ID" do
      # Set application config
      Application.put_env(:ccxt_client, :broker_id, "APP_CONFIG_BROKER")

      on_exit(fn ->
        Application.delete_env(:ccxt_client, :broker_id)
      end)

      Req.Test.stub(:app_broker_stub, fn conn ->
        # Should use app config, not spec options
        referer = Plug.Conn.get_req_header(conn, "referer")
        assert referer == ["APP_CONFIG_BROKER"]
        Req.Test.json(conn, %{app_broker: true})
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          signing: %{
            pattern: :hmac_sha256_headers,
            broker_config: %{header: "Referer", option_key: "brokerId"}
          },
          options: %{"brokerId" => "SPEC_BROKER_ID"}
      }

      assert {:ok, %{status: 200, body: %{"app_broker" => true}}} =
               Client.request(spec, :get, "/private",
                 credentials: @test_credentials,
                 plug: {Req.Test, :app_broker_stub}
               )
    end

    test "skips broker header when no broker_config in signing" do
      Req.Test.stub(:no_broker_stub, fn conn ->
        # Verify no unexpected broker header
        referer = Plug.Conn.get_req_header(conn, "referer")
        assert referer == []
        Req.Test.json(conn, %{no_broker: true})
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          signing: %{
            pattern: :hmac_sha256_headers
            # No broker_config
          },
          options: %{"brokerId" => "IGNORED_BROKER"}
      }

      assert {:ok, %{status: 200, body: %{"no_broker" => true}}} =
               Client.request(spec, :get, "/private",
                 credentials: @test_credentials,
                 plug: {Req.Test, :no_broker_stub}
               )
    end

    test "skips broker header when broker ID not found in options" do
      Req.Test.stub(:missing_broker_stub, fn conn ->
        # Verify no broker header
        source_key = Plug.Conn.get_req_header(conn, "x-source-key")
        assert source_key == []
        Req.Test.json(conn, %{missing_broker: true})
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          signing: %{
            pattern: :hmac_sha256_headers,
            broker_config: %{header: "X-SOURCE-KEY", option_key: "broker"}
          },
          options: %{}
      }

      assert {:ok, %{status: 200, body: %{"missing_broker" => true}}} =
               Client.request(spec, :get, "/private",
                 credentials: @test_credentials,
                 plug: {Req.Test, :missing_broker_stub}
               )
    end

    test "does not inject broker header for public requests" do
      Req.Test.stub(:public_no_broker_stub, fn conn ->
        # Public requests should not have broker header
        referer = Plug.Conn.get_req_header(conn, "referer")
        assert referer == []
        Req.Test.json(conn, %{public: true})
      end)

      spec = %{
        @test_spec
        | urls: %{api: "http://localhost", sandbox: "http://localhost"},
          signing: %{
            pattern: :hmac_sha256_headers,
            broker_config: %{header: "Referer", option_key: "brokerId"}
          },
          options: %{"brokerId" => "MY_BROKER_ID"}
      }

      # No credentials = public request
      assert {:ok, %{status: 200, body: %{"public" => true}}} =
               Client.request(spec, :get, "/public", plug: {Req.Test, :public_no_broker_stub})
    end
  end

  # Task 159: Debug request logging
  describe "debug_request option" do
    import ExUnit.CaptureLog

    @tag capture_log: false
    test "logs request details when enabled" do
      Req.Test.stub(:debug_stub, fn conn ->
        Req.Test.json(conn, %{result: "ok"})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      log =
        capture_log(fn ->
          Client.request(spec, :get, "/test",
            debug_request: true,
            plug: {Req.Test, :debug_stub}
          )
        end)

      assert log =~ "[CCXT] Request Debug"
      assert log =~ "Exchange: testexchange"
      assert log =~ "Method: get"
      assert log =~ "URL: http://localhost/test"
    end

    @tag capture_log: false
    test "does not log when debug_request is false (default)" do
      Req.Test.stub(:no_debug_stub, fn conn ->
        Req.Test.json(conn, %{result: "ok"})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      log =
        capture_log(fn ->
          Client.request(spec, :get, "/test", plug: {Req.Test, :no_debug_stub})
        end)

      refute log =~ "[CCXT] Request Debug"
    end
  end

  # Helper to create a spec with a unique exchange_id to avoid circuit breaker cross-test pollution
  defp unique_spec do
    exchange_id = :"client_test_#{System.unique_integer([:positive])}"

    %{
      @test_spec
      | exchange_id: exchange_id,
        id: Atom.to_string(exchange_id),
        urls: %{api: "http://localhost", sandbox: "http://localhost"}
    }
  end

  describe "debug mode exception logging" do
    import ExUnit.CaptureLog

    test "logs exception details when debug config is true" do
      Application.put_env(:ccxt_client, :debug, true)

      on_exit(fn ->
        Application.delete_env(:ccxt_client, :debug)
      end)

      Req.Test.stub(:debug_exception_stub, fn _conn ->
        raise "Debug test explosion"
      end)

      spec = unique_spec()

      log =
        capture_log(fn ->
          Client.request(spec, :get, "/test", plug: {Req.Test, :debug_exception_stub})
        end)

      assert log =~ "CCXT request exception"
      assert log =~ "/test"
      assert log =~ "Debug test explosion"
    end

    test "does not log exception details when debug config is false" do
      Application.put_env(:ccxt_client, :debug, false)

      on_exit(fn ->
        Application.delete_env(:ccxt_client, :debug)
      end)

      Req.Test.stub(:no_debug_exception_stub, fn _conn ->
        raise "Silent explosion"
      end)

      spec = unique_spec()

      log =
        capture_log(fn ->
          Client.request(spec, :get, "/test", plug: {Req.Test, :no_debug_exception_stub})
        end)

      refute log =~ "CCXT request exception"
    end
  end

  describe "transport error handling" do
    test "handles Req.TransportError with timeout reason" do
      Req.Test.stub(:transport_timeout_stub, fn _conn ->
        raise Req.TransportError, reason: :timeout
      end)

      spec = unique_spec()

      assert {:error, %Error{type: :network_error, message: message}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :transport_timeout_stub})

      assert message =~ "timeout"
    end
  end

  describe "JSON decode fallback" do
    test "passes through list body unchanged" do
      Req.Test.stub(:list_body_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!([%{"key" => "value"}]))
      end)

      spec = unique_spec()

      assert {:ok, %{status: 200, body: body}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :list_body_stub})

      assert is_list(body)
      assert hd(body)["key"] == "value"
    end

    test "binary body that is not JSON passes through as-is" do
      Req.Test.stub(:non_json_binary_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "PLAIN TEXT RESPONSE")
      end)

      spec = unique_spec()

      assert {:ok, %{status: 200, body: "PLAIN TEXT RESPONSE"}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :non_json_binary_stub})
    end
  end

  describe "error message edge cases" do
    test "array-valued message field gets joined" do
      Req.Test.stub(:array_msg_stub, fn conn ->
        Req.Test.json(conn, %{
          "retCode" => 99_999,
          "retMsg" => ["Error 1", "Error 2"]
        })
      end)

      spec = %{
        unique_spec()
        | response_error: %{
            type: :success_code,
            field: "retCode",
            success_values: ["0"],
            code_field: "retCode",
            message_field: "retMsg"
          }
      }

      assert {:error, %Error{message: message}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :array_msg_stub})

      assert message == "Error 1, Error 2"
    end

    test "augment_message does not duplicate when message equals description" do
      Req.Test.stub(:same_msg_desc_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{code: 10_001, message: "Balance too low"})
      end)

      spec = %{unique_spec() | error_codes: @test_spec.error_codes, error_code_details: @test_spec.error_code_details}

      assert {:error, %Error{message: message}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :same_msg_desc_stub})

      # Should NOT be "Balance too low (Balance too low)" - no duplication
      assert message == "Balance too low"
    end

    test "augment_message uses description when message is Unknown error" do
      Req.Test.stub(:unknown_msg_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{code: 10_001})
      end)

      spec = %{unique_spec() | error_codes: @test_spec.error_codes, error_code_details: @test_spec.error_code_details}

      assert {:error, %Error{message: message}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :unknown_msg_stub})

      # When message is "Unknown error", description should replace it entirely
      assert message == "Balance too low"
    end
  end

  describe "retry-after parsing edge cases" do
    test "non-integer retry-after header results in nil retry_after" do
      Req.Test.stub(:date_retry_after_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "Thu, 01 Dec 2024 00:00:00 GMT")
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{message: "Rate limited"})
      end)

      spec = unique_spec()

      assert {:error, %Error{type: :rate_limited, retry_after: nil}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :date_retry_after_stub})
    end
  end

  describe "rate key building" do
    test "public request without credentials returns proper error on 500" do
      Req.Test.stub(:public_500_stub, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{error: "Internal error"})
      end)

      spec = unique_spec()

      # No credentials passed = public request
      assert {:error, %Error{type: :exchange_error}} =
               Client.request(spec, :get, "/test", plug: {Req.Test, :public_500_stub})
    end
  end

  # Task 159: Base client caching
  describe "base client caching" do
    test "reuses base client across requests" do
      # Clear any existing cached client
      try do
        :persistent_term.erase({Client, :base_client})
      rescue
        ArgumentError -> :ok
      end

      Req.Test.stub(:cache_test_1, fn conn ->
        Req.Test.json(conn, %{result: "ok"})
      end)

      Req.Test.stub(:cache_test_2, fn conn ->
        Req.Test.json(conn, %{result: "ok"})
      end)

      spec = %{@test_spec | urls: %{api: "http://localhost", sandbox: "http://localhost"}}

      # First request creates client
      {:ok, _} = Client.request(spec, :get, "/test1", plug: {Req.Test, :cache_test_1})

      # Verify client is cached
      cached = :persistent_term.get({Client, :base_client}, nil)
      assert %Req.Request{} = cached

      # Second request should reuse the same client (no error means it worked)
      {:ok, _} = Client.request(spec, :get, "/test2", plug: {Req.Test, :cache_test_2})

      # Client should still be the same instance
      cached_after = :persistent_term.get({Client, :base_client}, nil)
      assert cached == cached_after
    end
  end

  describe "circuit breaker integration" do
    setup do
      # Use unique exchange ID per test to avoid cross-test pollution
      exchange_id = :"cb_test_#{System.unique_integer([:positive])}"
      spec = %{@test_spec | id: Atom.to_string(exchange_id), exchange_id: exchange_id}
      {:ok, spec: spec, exchange_id: exchange_id}
    end

    test "returns circuit_open error when circuit is blown", %{spec: spec, exchange_id: exchange_id} do
      alias CCXT.CircuitBreaker

      # First, ensure the fuse is installed
      CircuitBreaker.check(exchange_id)

      # Blow the circuit by recording failures
      for _ <- 1..5 do
        CircuitBreaker.record_failure(exchange_id)
      end

      # Verify circuit is blown
      assert CircuitBreaker.status(exchange_id) == :blown

      # Now request should fail immediately with circuit_open error
      result = Client.request(spec, :get, "/test")

      assert {:error, %Error{type: :circuit_open, exchange: ^exchange_id}} = result
    end

    test "records failure on 500+ responses", %{spec: spec, exchange_id: exchange_id} do
      alias CCXT.CircuitBreaker

      Req.Test.stub(:circuit_500_test, fn conn ->
        Plug.Conn.send_resp(conn, 500, Jason.encode!(%{error: "server error"}))
      end)

      # Make request that returns 500
      {:error, _} = Client.request(spec, :get, "/test", plug: {Req.Test, :circuit_500_test})

      # Circuit should still be ok after 1 failure (threshold is 5)
      assert CircuitBreaker.status(exchange_id) == :ok
    end

    test "does not record failure on 4xx responses", %{spec: spec, exchange_id: exchange_id} do
      alias CCXT.CircuitBreaker

      Req.Test.stub(:circuit_400_test, fn conn ->
        Plug.Conn.send_resp(conn, 400, Jason.encode!(%{error: "bad request"}))
      end)

      # Make multiple 400 requests
      for _ <- 1..10 do
        Client.request(spec, :get, "/test", plug: {Req.Test, :circuit_400_test})
      end

      # Circuit should still be ok (4xx don't trip circuit)
      assert CircuitBreaker.status(exchange_id) == :ok
    end

    test "allows requests when circuit is ok", %{spec: spec, exchange_id: exchange_id} do
      alias CCXT.CircuitBreaker

      Req.Test.stub(:circuit_ok_test, fn conn ->
        Req.Test.json(conn, %{result: "success"})
      end)

      # Verify circuit is ok
      assert CircuitBreaker.check(exchange_id) == :ok

      # Request should succeed
      {:ok, response} = Client.request(spec, :get, "/test", plug: {Req.Test, :circuit_ok_test})

      assert response.body["result"] == "success"
    end
  end

  # Task 161: Rate limit header parsing integration
  describe "rate limit header parsing" do
    alias CCXT.HTTP.RateLimitInfo
    alias CCXT.HTTP.RateLimitState

    setup do
      # Attach telemetry handler for rate limit verification
      ref = make_ref()
      parent = self()
      handler_id = "rate-limit-handler-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:ccxt, :request, :stop],
        fn _event, _measurements, metadata, _config ->
          send(parent, {:stop_metadata, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :ok
    end

    test "parses Binance weight headers and enriches telemetry" do
      Req.Test.stub(:binance_rl_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-mbx-used-weight-1m", "750")
        |> Req.Test.json(%{result: "ok"})
      end)

      spec = %{
        unique_spec()
        | rate_limits: %{requests: 1200, period: 60_000}
      }

      assert {:ok, _} = Client.request(spec, :get, "/test", plug: {Req.Test, :binance_rl_stub})

      assert_receive {:stop_metadata, metadata}
      assert %RateLimitInfo{} = metadata.rate_limit
      assert metadata.rate_limit.source == :binance_weight
      assert metadata.rate_limit.used == 750
      assert metadata.rate_limit.limit == 1200
      assert metadata.rate_limit.remaining == 450
    end

    test "parses Bybit rate limit headers and enriches telemetry" do
      Req.Test.stub(:bybit_rl_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-bapi-limit", "120")
        |> Plug.Conn.put_resp_header("x-bapi-limit-status", "95")
        |> Plug.Conn.put_resp_header("x-bapi-limit-reset-timestamp", "1704067200000")
        |> Req.Test.json(%{result: "ok"})
      end)

      spec = unique_spec()

      assert {:ok, _} = Client.request(spec, :get, "/test", plug: {Req.Test, :bybit_rl_stub})

      assert_receive {:stop_metadata, metadata}
      assert %RateLimitInfo{} = metadata.rate_limit
      assert metadata.rate_limit.source == :bybit_bapi
      assert metadata.rate_limit.limit == 120
      assert metadata.rate_limit.remaining == 95
      assert metadata.rate_limit.used == 25
    end

    test "parses standard rate limit headers and enriches telemetry" do
      Req.Test.stub(:standard_rl_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-ratelimit-limit", "100")
        |> Plug.Conn.put_resp_header("x-ratelimit-remaining", "75")
        |> Plug.Conn.put_resp_header("x-ratelimit-reset", "1704067200")
        |> Req.Test.json(%{result: "ok"})
      end)

      spec = unique_spec()

      assert {:ok, _} = Client.request(spec, :get, "/test", plug: {Req.Test, :standard_rl_stub})

      assert_receive {:stop_metadata, metadata}
      assert %RateLimitInfo{} = metadata.rate_limit
      assert metadata.rate_limit.source == :standard
      assert metadata.rate_limit.limit == 100
      assert metadata.rate_limit.remaining == 75
    end

    test "stores rate limit info in ETS for public requests" do
      exchange = :"rl_ets_test_#{System.unique_integer([:positive])}"

      Req.Test.stub(:rl_ets_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-mbx-used-weight-1m", "500")
        |> Req.Test.json(%{result: "ok"})
      end)

      spec = %{
        @test_spec
        | exchange_id: exchange,
          id: Atom.to_string(exchange),
          urls: %{api: "http://localhost", sandbox: "http://localhost"},
          rate_limits: %{requests: 1200}
      }

      assert {:ok, _} = Client.request(spec, :get, "/test", plug: {Req.Test, :rl_ets_stub})

      # Verify stored in ETS
      assert %RateLimitInfo{used: 500, limit: 1200} = RateLimitState.status(exchange)
    end

    test "stores rate limit info in ETS for authenticated requests" do
      exchange = :"rl_auth_ets_test_#{System.unique_integer([:positive])}"

      Req.Test.stub(:rl_auth_ets_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-bapi-limit", "120")
        |> Plug.Conn.put_resp_header("x-bapi-limit-status", "80")
        |> Req.Test.json(%{result: "ok"})
      end)

      spec = %{
        @test_spec
        | exchange_id: exchange,
          id: Atom.to_string(exchange),
          urls: %{api: "http://localhost", sandbox: "http://localhost"}
      }

      assert {:ok, _} =
               Client.request(spec, :get, "/test",
                 credentials: @test_credentials,
                 plug: {Req.Test, :rl_auth_ets_stub}
               )

      # Should be stored under the API key, not :public
      assert %RateLimitInfo{limit: 120} = RateLimitState.status(exchange, @test_credentials.api_key)
      # Public should be nil
      assert nil == RateLimitState.status(exchange)
    end

    test "does not include rate_limit in telemetry when no rate limit headers present" do
      Req.Test.stub(:no_rl_headers_stub, fn conn ->
        Req.Test.json(conn, %{result: "ok"})
      end)

      spec = unique_spec()

      assert {:ok, _} = Client.request(spec, :get, "/test", plug: {Req.Test, :no_rl_headers_stub})

      assert_receive {:stop_metadata, metadata}
      refute Map.has_key?(metadata, :rate_limit)
    end

    test "rate limit parsing works alongside error responses" do
      Req.Test.stub(:rl_error_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-mbx-used-weight-1m", "1199")
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{code: -1121, msg: "Invalid symbol"})
      end)

      exchange = :"rl_error_test_#{System.unique_integer([:positive])}"

      spec = %{
        @test_spec
        | exchange_id: exchange,
          id: Atom.to_string(exchange),
          urls: %{api: "http://localhost", sandbox: "http://localhost"},
          rate_limits: %{requests: 1200}
      }

      # Should still return error
      assert {:error, %Error{}} = Client.request(spec, :get, "/test", plug: {Req.Test, :rl_error_stub})

      # But rate limit info should be stored and in telemetry
      assert_receive {:stop_metadata, metadata}
      assert %RateLimitInfo{used: 1199} = metadata.rate_limit
      assert %RateLimitInfo{used: 1199} = RateLimitState.status(exchange)
    end
  end
end
