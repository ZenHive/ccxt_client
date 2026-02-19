defmodule CCXT.Test.WSIntegrationHelperTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import CCXT.Test.WSIntegrationHelper, only: [receive_data_message: 1]

  @timeout_ms 500

  describe "receive_data_message/1" do
    test "skips :system-tagged messages, returns next data" do
      send(self(), {:ws_message, {:system, %{"id" => nil, "result" => nil}}})
      send(self(), {:ws_message, {:watch_trades, %{"e" => "trade", "s" => "BTCUSDT"}}})

      result = receive_data_message(@timeout_ms)
      assert result == %{"e" => "trade", "s" => "BTCUSDT"}
    end

    test "returns data from :routed family" do
      send(self(), {:ws_message, {:watch_ticker, %{"s" => "BTCUSDT", "c" => "42000"}}})

      result = receive_data_message(@timeout_ms)
      assert result == %{"s" => "BTCUSDT", "c" => "42000"}
    end

    test "returns data from untagged messages" do
      send(self(), {:ws_message, %{"some" => "data"}})

      result = receive_data_message(@timeout_ms)
      assert result == %{"some" => "data"}
    end

    test "flunks on error messages" do
      send(self(), {:ws_message, {:raw, %{"type" => "error", "msg" => "bad request"}}})

      assert_raise ExUnit.AssertionError, ~r/Received error from exchange/, fn ->
        receive_data_message(@timeout_ms)
      end
    end

    test "decodes tagged binary JSON payload" do
      json = Jason.encode!(%{"e" => "trade", "s" => "ETHUSDT"})
      send(self(), {:ws_message, {:watch_trades, json}})

      result = receive_data_message(@timeout_ms)
      assert result == %{"e" => "trade", "s" => "ETHUSDT"}
    end

    test "legacy system_message? fallback works for untagged pong" do
      send(self(), {:ws_message, %{"op" => "pong"}})
      send(self(), {:ws_message, {:watch_trades, %{"data" => 1}}})

      result = receive_data_message(@timeout_ms)
      assert result == %{"data" => 1}
    end
  end
end
