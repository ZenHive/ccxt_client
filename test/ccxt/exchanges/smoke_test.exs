defmodule CCXT.Exchanges.SmokeTest do
  @moduledoc """
  Auto-generated smoke tests for all installed exchange modules.

  Tests verify that all exchange modules:
  1. Compile successfully
  2. Have a valid signing pattern configured
  3. Export the expected introspection functions
  4. Have the escape hatch functions

  ## Running

      # All smoke tests
      mix test test/ccxt/exchanges/smoke_test.exs

      # Filter by priority tier
      mix test test/ccxt/exchanges/smoke_test.exs --only tier1
      mix test test/ccxt/exchanges/smoke_test.exs --only tier2
      mix test test/ccxt/exchanges/smoke_test.exs --exclude tier3

      # Filter by CCXT classification
      mix test test/ccxt/exchanges/smoke_test.exs --only certified_pro
      mix test test/ccxt/exchanges/smoke_test.exs --only pro

      # Filter by exchange
      mix test test/ccxt/exchanges/smoke_test.exs --only exchange_bybit

      # Just the distribution report
      mix test test/ccxt/exchanges/smoke_test.exs --only distribution_report
  """

  use CCXT.Test.SmokeTestGenerator
end
