defmodule CCXT.DefaultsTest do
  use ExUnit.Case, async: true

  alias CCXT.Defaults

  describe "default values" do
    test "recv_window_ms/0 returns default value" do
      assert Defaults.recv_window_ms() == 5_000
    end

    test "request_timeout_ms/0 returns default value" do
      assert Defaults.request_timeout_ms() == 30_000
    end

    test "extraction_timeout_ms/0 returns default value" do
      assert Defaults.extraction_timeout_ms() == 30_000
    end

    test "rate_limit_cleanup_interval_ms/0 returns default value" do
      assert Defaults.rate_limit_cleanup_interval_ms() == 60_000
    end

    test "rate_limit_max_age_ms/0 returns default value" do
      assert Defaults.rate_limit_max_age_ms() == 60_000
    end
  end

  describe "application config override" do
    test "recv_window_ms/0 respects application config" do
      original = Application.get_env(:ccxt_client, :recv_window_ms)

      try do
        Application.put_env(:ccxt_client, :recv_window_ms, 10_000)
        assert Defaults.recv_window_ms() == 10_000
      after
        if original do
          Application.put_env(:ccxt_client, :recv_window_ms, original)
        else
          Application.delete_env(:ccxt_client, :recv_window_ms)
        end
      end
    end

    test "request_timeout_ms/0 respects application config" do
      original = Application.get_env(:ccxt_client, :request_timeout_ms)

      try do
        Application.put_env(:ccxt_client, :request_timeout_ms, 60_000)
        assert Defaults.request_timeout_ms() == 60_000
      after
        if original do
          Application.put_env(:ccxt_client, :request_timeout_ms, original)
        else
          Application.delete_env(:ccxt_client, :request_timeout_ms)
        end
      end
    end

    test "extraction_timeout_ms/0 respects application config" do
      original = Application.get_env(:ccxt_client, :extraction_timeout_ms)

      try do
        Application.put_env(:ccxt_client, :extraction_timeout_ms, 60_000)
        assert Defaults.extraction_timeout_ms() == 60_000
      after
        if original do
          Application.put_env(:ccxt_client, :extraction_timeout_ms, original)
        else
          Application.delete_env(:ccxt_client, :extraction_timeout_ms)
        end
      end
    end

    test "rate_limit_cleanup_interval_ms/0 respects application config" do
      original = Application.get_env(:ccxt_client, :rate_limit_cleanup_interval_ms)

      try do
        Application.put_env(:ccxt_client, :rate_limit_cleanup_interval_ms, 120_000)
        assert Defaults.rate_limit_cleanup_interval_ms() == 120_000
      after
        if original do
          Application.put_env(:ccxt_client, :rate_limit_cleanup_interval_ms, original)
        else
          Application.delete_env(:ccxt_client, :rate_limit_cleanup_interval_ms)
        end
      end
    end

    test "rate_limit_max_age_ms/0 respects application config" do
      original = Application.get_env(:ccxt_client, :rate_limit_max_age_ms)

      try do
        Application.put_env(:ccxt_client, :rate_limit_max_age_ms, 120_000)
        assert Defaults.rate_limit_max_age_ms() == 120_000
      after
        if original do
          Application.put_env(:ccxt_client, :rate_limit_max_age_ms, original)
        else
          Application.delete_env(:ccxt_client, :rate_limit_max_age_ms)
        end
      end
    end
  end
end
