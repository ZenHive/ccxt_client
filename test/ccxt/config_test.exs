defmodule CCXT.ConfigTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  # Source of truth for default values - no duplication
  # These are fetched from the actual modules to catch drift
  setup_all do
    defaults = CCXT.Defaults.raw_defaults()
    cb_defaults = CCXT.CircuitBreaker.raw_defaults()

    %{defaults: defaults, cb_defaults: cb_defaults}
  end

  describe "spec/0" do
    test "includes top-level keys with expected defaults", %{defaults: defaults} do
      entries = CCXT.Config.spec()

      assert default_for(entries, [:recv_window_ms]) == defaults.recv_window_ms
      assert default_for(entries, [:request_timeout_ms]) == defaults.request_timeout_ms
      assert default_for(entries, [:extraction_timeout_ms]) == defaults.extraction_timeout_ms
      assert default_for(entries, [:rate_limit_cleanup_interval_ms]) == defaults.rate_limit_cleanup_interval_ms
      assert default_for(entries, [:rate_limit_max_age_ms]) == defaults.rate_limit_max_age_ms
      assert default_for(entries, [:retry_policy]) == defaults.retry_policy
      assert default_test_for(entries, [:retry_policy]) == defaults.retry_policy_test
      assert default_for(entries, [:debug]) == false
      assert default_for(entries, [:broker_id]) == nil
    end

    test "includes circuit breaker keys with expected defaults", %{cb_defaults: cb_defaults} do
      entries = CCXT.Config.spec()

      assert default_for(entries, [:circuit_breaker, :enabled]) == cb_defaults.enabled
      assert default_for(entries, [:circuit_breaker, :max_failures]) == cb_defaults.max_failures
      assert default_for(entries, [:circuit_breaker, :window_ms]) == cb_defaults.window_ms
      assert default_for(entries, [:circuit_breaker, :reset_ms]) == cb_defaults.reset_ms
    end
  end

  describe "spec_json/0" do
    test "returns valid JSON array", %{defaults: defaults} do
      decoded = Jason.decode!(CCXT.Config.spec_json())
      assert is_list(decoded)

      retry_entry =
        Enum.find(decoded, fn entry -> entry["path"] == ["retry_policy"] end)

      assert retry_entry["default"] == Atom.to_string(defaults.retry_policy)
    end
  end

  describe "readme_section/1" do
    test "includes configuration examples and machine-readable spec" do
      section = CCXT.Config.readme_section(:ccxt_client)

      assert section =~ "## Configuration"
      assert section =~ "config :ccxt_client"
      assert section =~ "config :ccxt_client, :circuit_breaker"
      assert section =~ "Machine-readable config spec"
      assert section =~ "```json"
    end
  end

  defp default_for(entries, path) do
    entries
    |> Enum.find(fn entry -> entry.path == path end)
    |> Map.fetch!(:default)
  end

  defp default_test_for(entries, path) do
    entries
    |> Enum.find(fn entry -> entry.path == path end)
    |> Map.fetch!(:default_test)
  end
end
