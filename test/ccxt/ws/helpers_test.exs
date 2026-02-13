defmodule CCXT.WS.HelpersTest do
  use ExUnit.Case, async: true

  alias CCXT.WS.Helpers

  describe "resolve_url/3" do
    test "resolves simple string URL" do
      ws_config = %{
        urls: "wss://ws.example.com/v1"
      }

      assert {:ok, "wss://ws.example.com/v1"} = Helpers.resolve_url(ws_config, :any)
    end

    test "resolves nested URL with path" do
      ws_config = %{
        urls: %{
          "public" => %{
            "spot" => "wss://stream.example.com/public/spot",
            "linear" => "wss://stream.example.com/public/linear"
          },
          "private" => "wss://stream.example.com/private"
        }
      }

      # Nested path
      assert {:ok, "wss://stream.example.com/public/spot"} =
               Helpers.resolve_url(ws_config, [:public, :spot])

      assert {:ok, "wss://stream.example.com/public/linear"} =
               Helpers.resolve_url(ws_config, ["public", "linear"])

      # Single level path
      assert {:ok, "wss://stream.example.com/private"} =
               Helpers.resolve_url(ws_config, :private)
    end

    test "interpolates hostname placeholder" do
      ws_config = %{
        urls: %{
          "public" => "wss://stream.{hostname}/v5/public"
        },
        hostname: "bybit.com"
      }

      assert {:ok, "wss://stream.bybit.com/v5/public"} =
               Helpers.resolve_url(ws_config, :public)
    end

    test "uses test_urls in sandbox mode" do
      ws_config = %{
        urls: %{
          "public" => "wss://stream.example.com/public"
        },
        test_urls: %{
          "public" => "wss://stream-testnet.example.com/public"
        }
      }

      # Production
      assert {:ok, "wss://stream.example.com/public"} =
               Helpers.resolve_url(ws_config, :public, sandbox: false)

      # Sandbox
      assert {:ok, "wss://stream-testnet.example.com/public"} =
               Helpers.resolve_url(ws_config, :public, sandbox: true)
    end

    test "falls back to urls if test_urls missing in sandbox mode" do
      ws_config = %{
        urls: %{
          "public" => "wss://stream.example.com/public"
        }
      }

      assert {:ok, "wss://stream.example.com/public"} =
               Helpers.resolve_url(ws_config, :public, sandbox: true)
    end

    test "returns error for missing path" do
      ws_config = %{
        urls: %{
          "public" => "wss://stream.example.com/public"
        }
      }

      assert {:error, {:url_not_found, ["unknown"]}} =
               Helpers.resolve_url(ws_config, :unknown)
    end

    test "returns error for no ws config" do
      spec = %{ws: nil}

      assert {:error, {:no_ws_config, :public}} =
               Helpers.resolve_url(spec, :public)
    end

    test "works with spec struct containing ws key" do
      spec = %{
        ws: %{
          urls: %{
            "public" => "wss://ws.example.com/public"
          }
        }
      }

      assert {:ok, "wss://ws.example.com/public"} =
               Helpers.resolve_url(spec, :public)
    end

    test "finds first URL from deeply nested map when path is partial" do
      ws_config = %{
        urls: %{
          "public" => %{
            "spot" => "wss://stream.example.com/public/spot",
            "linear" => "wss://stream.example.com/public/linear"
          }
        }
      }

      # When path leads to a map, return first URL found
      {:ok, url} = Helpers.resolve_url(ws_config, :public)
      assert url in ["wss://stream.example.com/public/spot", "wss://stream.example.com/public/linear"]
    end
  end

  describe "build_client_config/2" do
    test "builds config with keep_alive from streaming" do
      ws_config = %{
        streaming: %{
          keep_alive: 18_000
        }
      }

      config = Helpers.build_client_config(ws_config)

      assert Keyword.get(config, :timeout) == 5000
      assert Keyword.get(config, :reconnect_on_error) == true
      assert Keyword.get(config, :restore_subscriptions) == true
      assert Keyword.get(config, :heartbeat_config) == %{type: :ping, interval: 18_000}
    end

    test "allows overriding heartbeat type" do
      ws_config = %{
        streaming: %{
          keep_alive: 30_000
        }
      }

      config = Helpers.build_client_config(ws_config, heartbeat_type: :deribit)

      assert Keyword.get(config, :heartbeat_config) == %{type: :deribit, interval: 30_000}
    end

    test "allows overriding timeout" do
      ws_config = %{
        streaming: %{
          keep_alive: 18_000
        }
      }

      config = Helpers.build_client_config(ws_config, timeout: 10_000)

      assert Keyword.get(config, :timeout) == 10_000
    end

    test "allows overriding reconnect and restore flags" do
      ws_config = %{
        streaming: %{
          keep_alive: 18_000
        }
      }

      config =
        Helpers.build_client_config(ws_config, reconnect_on_error: false, restore_subscriptions: false)

      assert Keyword.get(config, :reconnect_on_error) == false
      assert Keyword.get(config, :restore_subscriptions) == false
    end

    test "passes through additional options" do
      ws_config = %{
        streaming: %{
          keep_alive: 18_000
        }
      }

      config = Helpers.build_client_config(ws_config, debug: true, handler: fn msg -> msg end)

      assert Keyword.get(config, :debug) == true
      assert Keyword.has_key?(config, :handler)
    end

    test "returns default config for nil ws" do
      spec = %{ws: nil}

      config = Helpers.build_client_config(spec)

      assert Keyword.get(config, :timeout) == 5000
      assert Keyword.get(config, :reconnect_on_error) == true
      refute Keyword.has_key?(config, :heartbeat_config)
    end

    test "handles missing streaming config" do
      ws_config = %{
        urls: "wss://example.com"
      }

      config = Helpers.build_client_config(ws_config)

      assert Keyword.get(config, :timeout) == 5000
      assert Keyword.get(config, :reconnect_on_error) == true
      assert Keyword.get(config, :restore_subscriptions) == true
      refute Keyword.has_key?(config, :heartbeat_config)
    end
  end

  describe "build_restore_message/2" do
    test "returns nil for empty subscriptions" do
      ws_config = %{
        subscription_pattern: :op_subscribe,
        subscription_config: %{op_field: "op", args_field: "args"}
      }

      assert Helpers.build_restore_message(ws_config, []) == nil
    end

    test "returns nil for nil ws config" do
      assert Helpers.build_restore_message(%{ws: nil}, [%{channel: "test"}]) == nil
    end

    test "builds restore message from subscriptions with string channels" do
      ws_config = %{
        subscription_pattern: :op_subscribe,
        subscription_config: %{op_field: "op", args_field: "args"}
      }

      subs = [
        %{channel: "tickers.BTCUSDT", message: %{}},
        %{channel: "orderbook.50.BTCUSDT", message: %{}}
      ]

      {:ok, message} = Helpers.build_restore_message(ws_config, subs)

      assert is_map(message)
      assert Map.get(message, "op") == "subscribe"
      args = Map.get(message, "args")
      assert "tickers.BTCUSDT" in args
      assert "orderbook.50.BTCUSDT" in args
    end

    test "handles subscriptions with list channels" do
      ws_config = %{
        subscription_pattern: :op_subscribe,
        subscription_config: %{op_field: "op", args_field: "args"}
      }

      subs = [
        %{channel: ["order", "stopOrder"], message: %{}}
      ]

      {:ok, message} = Helpers.build_restore_message(ws_config, subs)

      args = Map.get(message, "args")
      assert "order" in args
      assert "stopOrder" in args
    end

    test "deduplicates channels" do
      ws_config = %{
        subscription_pattern: :op_subscribe,
        subscription_config: %{op_field: "op", args_field: "args"}
      }

      subs = [
        %{channel: "tickers.BTCUSDT", message: %{}},
        %{channel: "tickers.BTCUSDT", message: %{}}
      ]

      {:ok, message} = Helpers.build_restore_message(ws_config, subs)

      args = Map.get(message, "args")
      assert length(args) == 1
    end
  end

  describe "get_subscription_pattern/1" do
    test "extracts pattern from spec with ws key" do
      spec = %{ws: %{subscription_pattern: :event_subscribe}}

      assert Helpers.get_subscription_pattern(spec) == :event_subscribe
    end

    test "extracts pattern from ws config directly" do
      ws_config = %{subscription_pattern: :op_subscribe}

      assert Helpers.get_subscription_pattern(ws_config) == :op_subscribe
    end

    test "returns nil for nil ws" do
      assert Helpers.get_subscription_pattern(%{ws: nil}) == nil
    end

    test "returns nil for missing pattern" do
      assert Helpers.get_subscription_pattern(%{}) == nil
    end
  end

  describe "get_keep_alive_interval/1" do
    test "extracts interval from spec with ws key" do
      spec = %{ws: %{streaming: %{keep_alive: 18_000}}}

      assert Helpers.get_keep_alive_interval(spec) == 18_000
    end

    test "extracts interval from ws config directly" do
      ws_config = %{streaming: %{keep_alive: 30_000}}

      assert Helpers.get_keep_alive_interval(ws_config) == 30_000
    end

    test "returns nil for nil ws" do
      assert Helpers.get_keep_alive_interval(%{ws: nil}) == nil
    end

    test "returns nil for missing streaming" do
      assert Helpers.get_keep_alive_interval(%{}) == nil
    end
  end

  describe "has_ws_support?/1" do
    test "returns true for spec with ws config" do
      spec = %{ws: %{urls: "wss://example.com"}}

      assert Helpers.has_ws_support?(spec) == true
    end

    test "returns false for nil ws" do
      assert Helpers.has_ws_support?(%{ws: nil}) == false
    end

    test "returns false for empty ws" do
      assert Helpers.has_ws_support?(%{ws: %{}}) == false
    end

    test "returns false for missing ws key" do
      assert Helpers.has_ws_support?(%{}) == false
    end
  end

  # ===================================================================
  # Task 25: Edge-case branch coverage
  # ===================================================================

  describe "resolve_url/3 - edge cases" do
    test "atom rescue path when key has never been atomized" do
      ws_config = %{
        urls: %{
          "public" => "wss://example.com/public"
        }
      }

      # Use a key that definitely doesn't exist as an atom.
      # Note: if another test atomizes this string first, this test still passes
      # but takes the Map.get path instead of the rescue path. Acceptable since
      # both paths produce the same {:error, {:url_not_found, _}} result.
      assert {:error, {:url_not_found, ["zzz_nonexistent_atom_xyz_12345"]}} =
               Helpers.resolve_url(ws_config, "zzz_nonexistent_atom_xyz_12345")
    end

    test "binary path normalization works same as atom" do
      ws_config = %{
        urls: %{
          "public" => "wss://stream.example.com/public"
        }
      }

      assert {:ok, "wss://stream.example.com/public"} =
               Helpers.resolve_url(ws_config, "public")

      assert {:ok, "wss://stream.example.com/public"} =
               Helpers.resolve_url(ws_config, :public)
    end

    test "returns error when nested map contains no URLs (empty map)" do
      ws_config = %{
        urls: %{
          "public" => %{}
        }
      }

      assert {:error, :no_url_found} = Helpers.resolve_url(ws_config, :public)
    end

    test "returns error when urls key is missing (nil url_source)" do
      ws_config = %{
        hostname: "example.com"
      }

      assert {:error, {:url_not_found, ["public"]}} = Helpers.resolve_url(ws_config, :public)
    end

    test "handles list path normalization" do
      ws_config = %{
        urls: %{
          "public" => %{
            "spot" => "wss://stream.example.com/public/spot"
          }
        }
      }

      assert {:ok, "wss://stream.example.com/public/spot"} =
               Helpers.resolve_url(ws_config, [:public, :spot])
    end
  end

  describe "find_first_url - edge cases" do
    test "returns first URL when path leads to map" do
      ws_config = %{
        urls: %{
          "public" => %{
            "spot" => "wss://example.com/spot"
          }
        }
      }

      {:ok, url} = Helpers.resolve_url(ws_config, :public)
      assert url == "wss://example.com/spot"
    end

    test "finds URL in deeply nested structure" do
      ws_config = %{
        urls: %{
          "public" => %{
            "nested" => %{
              "deep" => "wss://example.com/deep"
            }
          }
        }
      }

      {:ok, url} = Helpers.resolve_url(ws_config, :public)
      assert url == "wss://example.com/deep"
    end
  end

  describe "build_restore_message/2 - no-channel subscriptions" do
    test "returns nil when subscriptions have no channel key" do
      ws_config = %{
        subscription_pattern: :op_subscribe,
        subscription_config: %{op_field: "op", args_field: "args"}
      }

      subs = [%{other: "data"}, %{method: :watch_ticker}]

      assert Helpers.build_restore_message(ws_config, subs) == nil
    end
  end

  describe "build_client_config/2 - keep_alive absent in streaming" do
    test "no heartbeat_config when streaming has no keep_alive" do
      # streaming has other keys but no :keep_alive — heartbeat should be disabled
      ws_config = %{
        streaming: %{other_setting: true}
      }

      config = Helpers.build_client_config(ws_config)

      # 5000 is the default timeout, not from ws_config
      assert Keyword.get(config, :timeout) == 5000
      refute Keyword.has_key?(config, :heartbeat_config)
    end
  end
end
