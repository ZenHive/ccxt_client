defmodule CCXT.HealthTest do
  use ExUnit.Case, async: true

  alias CCXT.Error
  alias CCXT.Health

  # =============================================================================
  # Unit Tests (no network, async: true)
  # =============================================================================

  describe "ping/1" do
    test "returns error for invalid exchange" do
      assert {:error, %Error{type: :not_supported}} = Health.ping(:nonexistent_exchange_xyz)
    end

    test "returns error for non-exchange CCXT module" do
      # CCXT.Error exists but is not an exchange module (no __ccxt_spec__/0)
      assert {:error, %Error{type: :not_supported}} = Health.ping(:error)
    end
  end

  describe "latency/1" do
    test "returns error for invalid exchange" do
      assert {:error, %Error{type: :not_supported}} = Health.latency(:nonexistent_exchange_xyz)
    end
  end

  describe "all/1" do
    test "returns empty map for empty list" do
      assert Health.all([]) == %{}
    end

    test "includes error for invalid exchange" do
      result = Health.all([:nonexistent_exchange_xyz])
      assert Map.has_key?(result, :nonexistent_exchange_xyz)
      assert {:error, %Error{type: :not_supported}} = result[:nonexistent_exchange_xyz]
    end

    test "returns timeout error for timed-out exchanges" do
      # Use an impossibly short timeout to force a timeout on a real exchange
      result = Health.all([:bybit], timeout: 1)
      assert Map.has_key?(result, :bybit)
      assert {:error, :timeout} = result[:bybit]
    end

    test "never produces :unknown key" do
      result = Health.all([:nonexistent_exchange_xyz, :also_nonexistent])
      refute Map.has_key?(result, :unknown)
      assert Map.has_key?(result, :nonexistent_exchange_xyz)
      assert Map.has_key?(result, :also_nonexistent)
    end
  end

  describe "status/2" do
    test "returns error for invalid exchange" do
      assert {:error, %Error{type: :not_supported}} = Health.status(:nonexistent_exchange_xyz)
    end
  end

  # =============================================================================
  # Integration Tests (real network calls)
  # =============================================================================

  describe "ping/1 integration" do
    @describetag :integration
    @describetag :tier1
    @describetag :exchange_bybit

    test "bybit is reachable" do
      assert :ok = Health.ping(:bybit)
    end
  end

  describe "latency/1 integration" do
    @describetag :integration
    @describetag :tier1
    @describetag :exchange_bybit

    test "bybit returns positive latency" do
      assert {:ok, ms} = Health.latency(:bybit)
      assert is_float(ms)
      assert ms > 0
    end
  end

  describe "all/1 integration" do
    @describetag :integration
    @describetag :tier1

    test "checks multiple exchanges concurrently" do
      exchanges = [:bybit, :binance]
      result = Health.all(exchanges)

      # All requested exchanges should be in the result
      for exchange <- exchanges do
        assert Map.has_key?(result, exchange),
               "Expected #{exchange} in result, got: #{inspect(Map.keys(result))}"

        case result[exchange] do
          :ok ->
            :ok

          {:error, %Error{type: :network_error}} ->
            :ok

          {:error, %Error{type: :rate_limited}} ->
            :ok

          {:error, other} ->
            flunk("Unexpected error for #{exchange}: #{inspect(other)}")
        end
      end
    end

    test "handles mix of valid and invalid exchanges" do
      result = Health.all([:bybit, :nonexistent_exchange_xyz])

      assert Map.has_key?(result, :bybit)
      assert Map.has_key?(result, :nonexistent_exchange_xyz)
      assert {:error, %Error{type: :not_supported}} = result[:nonexistent_exchange_xyz]
    end
  end

  describe "status/2 integration" do
    @describetag :integration
    @describetag :tier1
    @describetag :exchange_bybit

    test "bybit returns complete health snapshot" do
      assert {:ok, snapshot} = Health.status(:bybit)

      assert snapshot.exchange == :bybit
      assert is_boolean(snapshot.reachable)
      assert snapshot.circuit in [:ok, :blown, :not_installed]

      if snapshot.reachable do
        assert is_float(snapshot.latency_ms)
        assert snapshot.latency_ms > 0
        refute Map.has_key?(snapshot, :error)
      else
        assert is_nil(snapshot.latency_ms)
        assert Map.has_key?(snapshot, :error)
      end
    end
  end
end
