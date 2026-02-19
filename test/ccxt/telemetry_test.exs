defmodule CCXT.TelemetryTest do
  use ExUnit.Case, async: true

  alias CCXT.Telemetry

  describe "contract_version/0" do
    test "returns a positive integer" do
      version = Telemetry.contract_version()
      assert is_integer(version)
      assert version > 0
    end
  end

  describe "event name functions" do
    test "request_start/0 returns correct event name" do
      assert Telemetry.request_start() == [:ccxt, :request, :start]
    end

    test "request_stop/0 returns correct event name" do
      assert Telemetry.request_stop() == [:ccxt, :request, :stop]
    end

    test "request_exception/0 returns correct event name" do
      assert Telemetry.request_exception() == [:ccxt, :request, :exception]
    end

    test "circuit_breaker_open/0 returns correct event name" do
      assert Telemetry.circuit_breaker_open() == [:ccxt, :circuit_breaker, :open]
    end

    test "circuit_breaker_closed/0 returns correct event name" do
      assert Telemetry.circuit_breaker_closed() == [:ccxt, :circuit_breaker, :closed]
    end

    test "circuit_breaker_rejected/0 returns correct event name" do
      assert Telemetry.circuit_breaker_rejected() == [:ccxt, :circuit_breaker, :rejected]
    end
  end

  describe "event lists" do
    test "events/0 returns all 6 events" do
      events = Telemetry.events()
      assert length(events) == 6
      assert [:ccxt, :request, :start] in events
      assert [:ccxt, :request, :stop] in events
      assert [:ccxt, :request, :exception] in events
      assert [:ccxt, :circuit_breaker, :open] in events
      assert [:ccxt, :circuit_breaker, :closed] in events
      assert [:ccxt, :circuit_breaker, :rejected] in events
    end

    test "request_events/0 returns 3 request events" do
      events = Telemetry.request_events()
      assert length(events) == 3
      assert [:ccxt, :request, :start] in events
      assert [:ccxt, :request, :stop] in events
      assert [:ccxt, :request, :exception] in events
    end

    test "circuit_breaker_events/0 returns 3 circuit breaker events" do
      events = Telemetry.circuit_breaker_events()
      assert length(events) == 3
      assert [:ccxt, :circuit_breaker, :open] in events
      assert [:ccxt, :circuit_breaker, :closed] in events
      assert [:ccxt, :circuit_breaker, :rejected] in events
    end
  end

  describe "attach/2 and detach/1" do
    test "attaches handler that receives events, then detaches" do
      test_pid = self()
      handler_id = "telemetry_test_#{System.unique_integer([:positive])}"

      :ok =
        Telemetry.attach(handler_id, fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_received, event, measurements, metadata})
        end)

      # Emit one of the registered events
      :telemetry.execute(
        Telemetry.request_start(),
        %{system_time: System.system_time()},
        %{exchange: :test_attach, method: :get, path: "/test"}
      )

      assert_receive {:telemetry_received, [:ccxt, :request, :start], %{system_time: _},
                      %{exchange: :test_attach, method: :get, path: "/test"}}

      # Detach and verify no more events received
      :ok = Telemetry.detach(handler_id)

      :telemetry.execute(
        Telemetry.request_start(),
        %{system_time: System.system_time()},
        %{exchange: :test_detached, method: :get, path: "/test"}
      )

      refute_receive {:telemetry_received, _, _, %{exchange: :test_detached}}
    end

    test "detach returns error for unknown handler" do
      assert {:error, :not_found} = Telemetry.detach("nonexistent_handler_#{System.unique_integer()}")
    end

    test "attach/3 passes config to handler" do
      test_pid = self()
      handler_id = "telemetry_config_test_#{System.unique_integer([:positive])}"
      config = %{log_level: :debug, prefix: "ccxt"}

      :ok =
        Telemetry.attach(
          handler_id,
          fn _event, _measurements, _metadata, handler_config ->
            send(test_pid, {:config_received, handler_config})
          end,
          config
        )

      :telemetry.execute(
        Telemetry.request_start(),
        %{system_time: System.system_time()},
        %{exchange: :test_config, method: :get, path: "/test"}
      )

      assert_receive {:config_received, %{log_level: :debug, prefix: "ccxt"}}

      Telemetry.detach(handler_id)
    end

    test "attach returns error for duplicate handler_id" do
      handler_id = "telemetry_dup_test_#{System.unique_integer([:positive])}"
      handler_fn = fn _event, _measurements, _metadata, _config -> :ok end

      :ok = Telemetry.attach(handler_id, handler_fn)
      assert {:error, :already_exists} = Telemetry.attach(handler_id, handler_fn)

      # Cleanup
      Telemetry.detach(handler_id)
    end
  end
end
