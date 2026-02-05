defmodule CCXT.Test.ExchangeHelperTest do
  @moduledoc """
  Tests for CCXT.Test.ExchangeHelper sync state helpers.
  """
  use ExUnit.Case, async: true

  alias CCXT.Test.ExchangeHelper

  @state_all "all"
  @state_partial "partial"

  defp temp_state_path do
    unique = System.unique_integer([:positive, :monotonic])
    Path.join([System.tmp_dir!(), "ccxt_sync_state_test_#{unique}.txt"])
  end

  @doc false
  # Cleanup temp file after test
  defp with_cleanup(path, fun) do
    fun.()
  after
    File.rm(path)
  end

  test "strict_exchange_tests?/1 returns true when marker is all" do
    path = temp_state_path()

    with_cleanup(path, fn ->
      File.write!(path, @state_all)
      assert ExchangeHelper.strict_exchange_tests?(path)
    end)
  end

  test "strict_exchange_tests?/1 returns false when marker is partial" do
    path = temp_state_path()

    with_cleanup(path, fn ->
      File.write!(path, @state_partial)
      refute ExchangeHelper.strict_exchange_tests?(path)
    end)
  end

  test "strict_exchange_tests?/1 returns false when marker is missing" do
    path = temp_state_path()
    # Ensure file doesn't exist (cleanup from previous runs)
    File.rm(path)
    refute ExchangeHelper.strict_exchange_tests?(path)
  end
end
