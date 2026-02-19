defmodule CCXT.CircuitBreakerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias CCXT.CircuitBreaker

  # Use unique exchange names per test to avoid cross-test pollution
  # Since fuses are global state, we need isolation

  @doc false
  defp blow_circuit(exchange, failure_count \\ 5) do
    CircuitBreaker.check(exchange)
    for _ <- 1..failure_count, do: CircuitBreaker.record_failure(exchange)
  end

  setup do
    # Generate a unique exchange name for this test
    exchange = :"test_exchange_#{System.unique_integer([:positive])}"
    {:ok, exchange: exchange}
  end

  describe "status/1" do
    test "returns :not_installed for unknown exchange", %{exchange: exchange} do
      assert CircuitBreaker.status(exchange) == :not_installed
    end

    test "returns :ok after fuse is installed via check", %{exchange: exchange} do
      # check/1 installs the fuse lazily
      assert CircuitBreaker.check(exchange) == :ok
      assert CircuitBreaker.status(exchange) == :ok
    end
  end

  describe "check/1" do
    test "installs fuse and returns :ok on first call", %{exchange: exchange} do
      assert CircuitBreaker.check(exchange) == :ok
      assert CircuitBreaker.status(exchange) == :ok
    end

    test "returns :ok when circuit is closed", %{exchange: exchange} do
      CircuitBreaker.check(exchange)
      assert CircuitBreaker.check(exchange) == :ok
    end

    test "returns :blown after circuit opens from failures", %{exchange: exchange} do
      log =
        capture_log(fn ->
          blow_circuit(exchange)

          assert CircuitBreaker.check(exchange) == :blown
          assert CircuitBreaker.status(exchange) == :blown
        end)

      assert log =~ "Circuit OPEN"
    end
  end

  describe "reset/1" do
    test "returns {:error, :not_found} for unknown exchange", %{exchange: exchange} do
      assert CircuitBreaker.reset(exchange) == {:error, :not_found}
    end

    test "resets a blown circuit", %{exchange: exchange} do
      log =
        capture_log(fn ->
          blow_circuit(exchange)
          assert CircuitBreaker.status(exchange) == :blown

          # Reset should restore it
          assert CircuitBreaker.reset(exchange) == :ok
          assert CircuitBreaker.status(exchange) == :ok
        end)

      assert log =~ "Circuit OPEN"
    end
  end

  describe "record_failure/1" do
    test "records failure without opening circuit under threshold", %{exchange: exchange} do
      CircuitBreaker.check(exchange)

      # Record 4 failures (under default threshold of 5)
      for _ <- 1..4 do
        CircuitBreaker.record_failure(exchange)
      end

      assert CircuitBreaker.status(exchange) == :ok
    end

    test "opens circuit after threshold failures", %{exchange: exchange} do
      log =
        capture_log(fn ->
          blow_circuit(exchange)
          assert CircuitBreaker.status(exchange) == :blown
        end)

      assert log =~ "Circuit OPEN"
    end

    test "installs fuse and records failure when called before check/1", %{exchange: exchange} do
      log =
        capture_log(fn ->
          # Verify fuse doesn't exist yet
          assert CircuitBreaker.status(exchange) == :not_installed

          # Record failures WITHOUT calling check/1 first
          for _ <- 1..5 do
            CircuitBreaker.record_failure(exchange)
          end

          # Fuse should be installed AND blown
          assert CircuitBreaker.status(exchange) == :blown
        end)

      assert log =~ "Circuit OPEN"
    end
  end

  describe "record_success/1" do
    test "does not affect fuse state (fuse auto-resets)", %{exchange: exchange} do
      CircuitBreaker.check(exchange)

      # Record a success
      assert CircuitBreaker.record_success(exchange) == :ok

      # Status should still be ok
      assert CircuitBreaker.status(exchange) == :ok
    end
  end

  describe "all_statuses/0" do
    test "returns a map of exchange statuses" do
      # Note: Cannot reliably test "empty map" since persistent_term state
      # persists across tests. We verify the return type and structure instead.
      statuses = CircuitBreaker.all_statuses()
      assert is_map(statuses)

      # All values should be :ok or :blown (no :not_installed in output)
      Enum.each(statuses, fn {_exchange, status} ->
        assert status in [:ok, :blown]
      end)
    end

    test "includes installed fuses", %{exchange: exchange} do
      CircuitBreaker.check(exchange)

      statuses = CircuitBreaker.all_statuses()
      assert Map.has_key?(statuses, exchange)
      assert statuses[exchange] == :ok
    end
  end

  describe "should_melt?/1" do
    test "returns true for 5xx responses" do
      assert CircuitBreaker.should_melt?({:ok, %Req.Response{status: 500}}) == true
      assert CircuitBreaker.should_melt?({:ok, %Req.Response{status: 502}}) == true
      assert CircuitBreaker.should_melt?({:ok, %Req.Response{status: 503}}) == true
      assert CircuitBreaker.should_melt?({:ok, %Req.Response{status: 504}}) == true
    end

    test "returns false for 2xx responses" do
      assert CircuitBreaker.should_melt?({:ok, %Req.Response{status: 200}}) == false
      assert CircuitBreaker.should_melt?({:ok, %Req.Response{status: 201}}) == false
      assert CircuitBreaker.should_melt?({:ok, %Req.Response{status: 204}}) == false
    end

    test "returns false for 4xx responses (client errors)" do
      assert CircuitBreaker.should_melt?({:ok, %Req.Response{status: 400}}) == false
      assert CircuitBreaker.should_melt?({:ok, %Req.Response{status: 401}}) == false
      assert CircuitBreaker.should_melt?({:ok, %Req.Response{status: 403}}) == false
      assert CircuitBreaker.should_melt?({:ok, %Req.Response{status: 404}}) == false
      # 429 rate limit - should NOT melt (handled by RateLimiter)
      assert CircuitBreaker.should_melt?({:ok, %Req.Response{status: 429}}) == false
    end

    test "returns true for transport errors" do
      assert CircuitBreaker.should_melt?({:error, %Req.TransportError{reason: :timeout}}) == true
      assert CircuitBreaker.should_melt?({:error, %Req.TransportError{reason: :econnrefused}}) == true
      assert CircuitBreaker.should_melt?({:error, %Req.TransportError{reason: :closed}}) == true
      assert CircuitBreaker.should_melt?({:error, %Req.TransportError{reason: :nxdomain}}) == true
    end

    test "returns true for generic errors" do
      assert CircuitBreaker.should_melt?({:error, :some_error}) == true
      assert CircuitBreaker.should_melt?({:error, "connection failed"}) == true
    end

    test "returns false for non-error values" do
      assert CircuitBreaker.should_melt?(:ok) == false
      assert CircuitBreaker.should_melt?(nil) == false
    end
  end

  describe "fuse_name/1" do
    test "returns prefixed atom" do
      assert CircuitBreaker.fuse_name(:binance) == :ccxt_fuse_binance
      assert CircuitBreaker.fuse_name(:bybit) == :ccxt_fuse_bybit
    end
  end

  describe "config/0" do
    test "returns default config when not set" do
      config = CircuitBreaker.config()

      assert config.enabled == true
      assert config.max_failures == 5
      assert config.window_ms == 10_000
      assert config.reset_ms == 15_000
    end

    test "handles keyword list config" do
      original = Application.get_env(:ccxt_client, :circuit_breaker)

      Application.put_env(:ccxt_client, :circuit_breaker,
        enabled: true,
        max_failures: 3,
        window_ms: 5_000,
        reset_ms: 8_000
      )

      on_exit(fn ->
        if original do
          Application.put_env(:ccxt_client, :circuit_breaker, original)
        else
          Application.delete_env(:ccxt_client, :circuit_breaker)
        end
      end)

      config = CircuitBreaker.config()

      assert config.enabled == true
      assert config.max_failures == 3
      assert config.window_ms == 5_000
      assert config.reset_ms == 8_000
    end
  end

  describe "reset!/1" do
    test "raises ArgumentError for nonexistent fuse", %{exchange: exchange} do
      assert_raise ArgumentError, ~r/No circuit breaker found for/, fn ->
        CircuitBreaker.reset!(exchange)
      end
    end

    test "resets a blown circuit without error", %{exchange: exchange} do
      log =
        capture_log(fn ->
          blow_circuit(exchange)
          assert CircuitBreaker.status(exchange) == :blown
          assert CircuitBreaker.reset!(exchange) == :ok
          assert CircuitBreaker.status(exchange) == :ok
        end)

      assert log =~ "Circuit OPEN"
    end
  end

  describe "should_melt?/1 catch-all transport errors" do
    test "returns true for non-standard transport error reasons" do
      assert CircuitBreaker.should_melt?({:error, %Req.TransportError{reason: :ehostunreach}}) == true
      assert CircuitBreaker.should_melt?({:error, %Req.TransportError{reason: :enetunreach}}) == true
    end
  end

  describe "idempotent check/1" do
    test "calling check on already-installed fuse is idempotent", %{exchange: exchange} do
      log =
        capture_log(fn ->
          # First install
          CircuitBreaker.check(exchange)
          assert CircuitBreaker.status(exchange) == :ok

          # Record some failures (under threshold)
          for _ <- 1..3, do: CircuitBreaker.record_failure(exchange)
          assert CircuitBreaker.status(exchange) == :ok

          # Re-calling check is idempotent
          assert CircuitBreaker.check(exchange) == :ok

          # Can still blow after re-check
          blow_circuit(exchange)
          assert CircuitBreaker.status(exchange) == :blown
        end)

      assert log =~ "Circuit OPEN"
    end
  end

  describe "exchange isolation" do
    test "circuit state is isolated per exchange" do
      exchange1 = :"isolated_test_1_#{System.unique_integer([:positive])}"
      exchange2 = :"isolated_test_2_#{System.unique_integer([:positive])}"

      # Install exchange2 separately (blow_circuit installs exchange1)
      CircuitBreaker.check(exchange2)

      log =
        capture_log(fn ->
          blow_circuit(exchange1)
        end)

      assert log =~ "Circuit OPEN"
      assert CircuitBreaker.status(exchange1) == :blown
      assert CircuitBreaker.status(exchange2) == :ok
    end
  end

  describe "disabled circuit breaker" do
    setup do
      # Store original config
      original = Application.get_env(:ccxt_client, :circuit_breaker)

      # Disable circuit breaker
      Application.put_env(:ccxt_client, :circuit_breaker, %{enabled: false})

      on_exit(fn ->
        if original do
          Application.put_env(:ccxt_client, :circuit_breaker, original)
        else
          Application.delete_env(:ccxt_client, :circuit_breaker)
        end
      end)

      exchange = :"disabled_test_#{System.unique_integer([:positive])}"
      {:ok, exchange: exchange}
    end

    test "check/1 always returns :ok when disabled", %{exchange: exchange} do
      assert CircuitBreaker.check(exchange) == :ok

      # Even after failures
      for _ <- 1..10 do
        CircuitBreaker.record_failure(exchange)
      end

      # Still returns :ok because disabled
      assert CircuitBreaker.check(exchange) == :ok
    end
  end

  describe "max_failures: 0 disables circuit breaker" do
    setup do
      # Store original config
      original = Application.get_env(:ccxt_client, :circuit_breaker)

      # Set max_failures to 0 (should disable)
      Application.put_env(:ccxt_client, :circuit_breaker, %{enabled: true, max_failures: 0})

      on_exit(fn ->
        if original do
          Application.put_env(:ccxt_client, :circuit_breaker, original)
        else
          Application.delete_env(:ccxt_client, :circuit_breaker)
        end
      end)

      exchange = :"zero_failures_test_#{System.unique_integer([:positive])}"
      {:ok, exchange: exchange}
    end

    test "check/1 always returns :ok when max_failures is 0", %{exchange: exchange} do
      assert CircuitBreaker.check(exchange) == :ok

      # Even after many failures
      for _ <- 1..10 do
        CircuitBreaker.record_failure(exchange)
      end

      # Still returns :ok because max_failures: 0 disables the circuit breaker
      assert CircuitBreaker.check(exchange) == :ok
    end
  end

  describe "record_result/2" do
    test "records failure for 500+ responses", %{exchange: exchange} do
      log =
        capture_log(fn ->
          CircuitBreaker.check(exchange)
          for _ <- 1..5, do: CircuitBreaker.record_result(exchange, {:ok, %Req.Response{status: 500}})
          assert CircuitBreaker.status(exchange) == :blown
        end)

      assert log =~ "Circuit OPEN"
    end

    test "records success for 2xx responses", %{exchange: exchange} do
      CircuitBreaker.check(exchange)

      # Many successful responses shouldn't blow the circuit
      for _ <- 1..10 do
        CircuitBreaker.record_result(exchange, {:ok, %Req.Response{status: 200}})
      end

      assert CircuitBreaker.status(exchange) == :ok
    end

    test "records success for 4xx responses (client errors)", %{exchange: exchange} do
      CircuitBreaker.check(exchange)

      # Client errors shouldn't blow the circuit
      for _ <- 1..10 do
        CircuitBreaker.record_result(exchange, {:ok, %Req.Response{status: 400}})
      end

      assert CircuitBreaker.status(exchange) == :ok
    end

    test "records success for 429 rate limit responses", %{exchange: exchange} do
      CircuitBreaker.check(exchange)

      # Rate limits shouldn't blow the circuit (handled by RateLimiter)
      for _ <- 1..10 do
        CircuitBreaker.record_result(exchange, {:ok, %Req.Response{status: 429}})
      end

      assert CircuitBreaker.status(exchange) == :ok
    end

    test "records failure for transport errors", %{exchange: exchange} do
      log =
        capture_log(fn ->
          CircuitBreaker.check(exchange)
          for _ <- 1..5, do: CircuitBreaker.record_result(exchange, {:error, %Req.TransportError{reason: :timeout}})
          assert CircuitBreaker.status(exchange) == :blown
        end)

      assert log =~ "Circuit OPEN"
    end

    test "records failure for generic errors", %{exchange: exchange} do
      log =
        capture_log(fn ->
          CircuitBreaker.check(exchange)
          for _ <- 1..5, do: CircuitBreaker.record_result(exchange, {:error, :some_error})
          assert CircuitBreaker.status(exchange) == :blown
        end)

      assert log =~ "Circuit OPEN"
    end
  end

  describe "auto-reset behavior" do
    setup do
      # Store original config
      original = Application.get_env(:ccxt_client, :circuit_breaker)

      # Use very short reset time for testing (100ms)
      Application.put_env(:ccxt_client, :circuit_breaker, %{
        enabled: true,
        max_failures: 2,
        window_ms: 10_000,
        reset_ms: 100
      })

      on_exit(fn ->
        if original do
          Application.put_env(:ccxt_client, :circuit_breaker, original)
        else
          Application.delete_env(:ccxt_client, :circuit_breaker)
        end
      end)

      exchange = :"auto_reset_test_#{System.unique_integer([:positive])}"
      {:ok, exchange: exchange}
    end

    @tag :slow
    test "circuit auto-resets after reset_ms timeout", %{exchange: exchange} do
      log =
        capture_log(fn ->
          blow_circuit(exchange, 2)
          assert CircuitBreaker.status(exchange) == :blown

          # Wait for auto-reset (100ms + buffer)
          Process.sleep(150)
          assert CircuitBreaker.status(exchange) == :ok
        end)

      assert log =~ "Circuit OPEN"
    end
  end

  describe "telemetry events" do
    test "emits :open event when circuit opens", %{exchange: exchange} do
      test_pid = self()
      handler_id = "test_open_#{exchange}"

      :telemetry.attach(
        handler_id,
        [:ccxt, :circuit_breaker, :open],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      log = capture_log(fn -> blow_circuit(exchange) end)

      assert log =~ "Circuit OPEN"
      assert_receive {:telemetry_event, [:ccxt, :circuit_breaker, :open], _measurements, %{exchange: ^exchange}}
    end

    test "emits :closed event when circuit resets", %{exchange: exchange} do
      test_pid = self()
      handler_id = "test_closed_#{exchange}"

      :telemetry.attach(
        handler_id,
        [:ccxt, :circuit_breaker, :closed],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      log =
        capture_log(fn ->
          blow_circuit(exchange)
          CircuitBreaker.reset(exchange)
        end)

      assert log =~ "Circuit OPEN"
      assert_receive {:telemetry_event, [:ccxt, :circuit_breaker, :closed], _measurements, %{exchange: ^exchange}}
    end

    test "emits :rejected event when request is blocked", %{exchange: exchange} do
      test_pid = self()
      handler_id = "test_rejected_#{exchange}"

      :telemetry.attach(
        handler_id,
        [:ccxt, :circuit_breaker, :rejected],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      log =
        capture_log(fn ->
          blow_circuit(exchange)
          # This check should be rejected
          CircuitBreaker.check(exchange)
        end)

      assert log =~ "Circuit OPEN"
      assert_receive {:telemetry_event, [:ccxt, :circuit_breaker, :rejected], _measurements, %{exchange: ^exchange}}
    end
  end
end
