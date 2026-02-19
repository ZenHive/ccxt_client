defmodule CCXT.WS.Auth.ExpiryTest do
  use ExUnit.Case, async: true

  alias CCXT.WS.Auth.Expiry

  describe "compute_ttl_ms/2" do
    test "response meta TTL takes priority over config TTL" do
      auth_meta = %{ttl_ms: 900_000}
      auth_config = %{auth_ttl_ms: 3_600_000}

      assert 900_000 = Expiry.compute_ttl_ms(auth_meta, auth_config)
    end

    test "falls back to config auth_ttl_ms when no response meta" do
      auth_config = %{auth_ttl_ms: 1_800_000}

      assert 1_800_000 = Expiry.compute_ttl_ms(nil, auth_config)
    end

    test "falls back to config auth_ttl_ms when response meta has no ttl_ms" do
      auth_meta = %{pattern: :jsonrpc_linebreak}
      auth_config = %{auth_ttl_ms: 1_800_000}

      assert 1_800_000 = Expiry.compute_ttl_ms(auth_meta, auth_config)
    end

    test "returns nil when neither source has TTL" do
      assert nil == Expiry.compute_ttl_ms(nil, %{pattern: :direct_hmac_expiry})
    end

    test "returns nil when both are nil" do
      assert nil == Expiry.compute_ttl_ms(nil, nil)
    end

    test "ignores non-positive response TTL, falls back to config" do
      auth_meta = %{ttl_ms: 0}
      auth_config = %{auth_ttl_ms: 600_000}

      assert 600_000 = Expiry.compute_ttl_ms(auth_meta, auth_config)
    end

    test "ignores negative response TTL, falls back to config" do
      auth_meta = %{ttl_ms: -1000}
      auth_config = %{auth_ttl_ms: 600_000}

      assert 600_000 = Expiry.compute_ttl_ms(auth_meta, auth_config)
    end

    test "ignores non-positive config TTL when no response TTL" do
      assert nil == Expiry.compute_ttl_ms(nil, %{auth_ttl_ms: 0})
      assert nil == Expiry.compute_ttl_ms(nil, %{auth_ttl_ms: -500})
    end
  end

  describe "schedule_delay_ms/1" do
    test "applies 80% safety margin" do
      # 1_000_000 * 0.80 = 800_000
      assert 800_000 = Expiry.schedule_delay_ms(1_000_000)
    end

    test "caps at 24 hours" do
      # 48 hours * 0.80 = 38.4 hours, but capped at 24 hours (86_400_000)
      forty_eight_hours = 48 * 3_600_000

      assert 86_400_000 = Expiry.schedule_delay_ms(forty_eight_hours)
    end

    test "returns nil for nil input" do
      assert nil == Expiry.schedule_delay_ms(nil)
    end

    test "returns nil for zero TTL" do
      assert nil == Expiry.schedule_delay_ms(0)
    end

    test "returns nil for negative TTL" do
      assert nil == Expiry.schedule_delay_ms(-1000)
    end

    test "small TTL applies margin correctly" do
      # 10_000 * 0.80 = 8_000
      assert 8_000 = Expiry.schedule_delay_ms(10_000)
    end

    test "exact 24h TTL stays under cap after margin" do
      twenty_four_hours = 86_400_000
      # 86_400_000 * 0.80 = 69_120_000 (under cap)
      assert 69_120_000 = Expiry.schedule_delay_ms(twenty_four_hours)
    end
  end
end
