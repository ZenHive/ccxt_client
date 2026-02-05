defmodule CCXT.WS.SmokeTest do
  @moduledoc """
  Smoke tests for all WS exchange modules.

  These tests verify that WS modules compile correctly and export expected
  introspection functions. Tests are generated dynamically based on which
  exchanges are installed.

  ## Running Tests

      # Run all WS smoke tests
      mix test --only ws_smoke

      # Run WS smoke tests for Tier 1 exchanges only
      mix test --only ws_smoke --only tier1

      # Run WS smoke tests excluding distribution report
      mix test --only ws_smoke --exclude ws_distribution_report

      # Run tests for a specific exchange
      mix test --only ws_smoke --only exchange_binance

  """
  use CCXT.Test.WSSmokeTestGenerator
end
