defmodule CCXT.Test.WsContractHelpers do
  @moduledoc """
  Test assertion helpers for WS contract compliance.

  Used by W12's contract self-tests and W15's integration tests to verify
  that normalized WS payloads conform to family contracts.
  """

  import ExUnit.Assertions

  alias CCXT.Types.Balance
  alias CCXT.Types.OHLCVBar
  alias CCXT.Types.Order
  alias CCXT.Types.OrderBook
  alias CCXT.Types.Position
  alias CCXT.Types.Ticker
  alias CCXT.Types.Trade
  alias CCXT.WS.Contract

  @doc """
  Asserts that `result` conforms to the contract for `family`.

  Validates struct type, required fields, and shape. Fails with
  descriptive message on violation.
  """
  @spec assert_contract_compliance(Contract.family(), term()) :: term()
  def assert_contract_compliance(family, result) do
    case Contract.validate(family, result) do
      {:ok, _} ->
        result

      {:error, violations} ->
        flunk("""
        Contract violation for #{inspect(family)}:
        #{format_violations(violations)}

        Got: #{inspect(result, limit: 3, printable_limit: 100)}
        """)
    end
  end

  @doc """
  Asserts that the `:raw` field on a struct preserves the original data.

  For structs with a `:raw` field, verifies it matches `original`.
  """
  @spec assert_raw_preserved(struct(), map()) :: :ok
  def assert_raw_preserved(%{raw: raw}, original) do
    assert raw == original,
           "Expected :raw field to preserve original data.\nExpected: #{inspect(original, limit: 3)}\nGot: #{inspect(raw, limit: 3)}"

    :ok
  end

  def assert_raw_preserved(result, _original) do
    flunk("Result does not have a :raw field: #{inspect(result, limit: 3)}")
  end

  @doc """
  Asserts all required fields for `family` are non-nil in `result`.

  For list families, checks each element.
  """
  @spec assert_required_fields(Contract.family(), term()) :: :ok
  def assert_required_fields(family, result) do
    required = Contract.required_fields(family)
    spec = Contract.family_spec(family)

    items =
      case spec.result_shape do
        :single -> [result]
        :list when is_list(result) -> result
        :list -> flunk("Expected list for #{inspect(family)}, got: #{inspect(result, limit: 3)}")
      end

    for item <- items, field <- required do
      value = Map.get(item, field)

      assert value != nil,
             "Required field #{inspect(field)} is nil in #{inspect(family)} result"
    end

    :ok
  end

  @doc """
  Asserts that numeric fields have been coerced to numbers (not strings).

  Checks the specified fields on the result struct.
  """
  @spec assert_coercion_applied(struct(), [atom()]) :: :ok
  def assert_coercion_applied(result, fields) do
    for field <- fields do
      value = Map.get(result, field)

      if value != nil do
        assert is_number(value),
               "Expected #{inspect(field)} to be a number after coercion, got: #{inspect(value)}"
      end
    end

    :ok
  end

  @doc """
  Builds a minimal valid payload for testing a family.

  Returns a well-formed struct (or list of structs) that passes
  `Contract.validate/2`. Useful as baseline for test mutations.
  """
  @spec build_sample_payload(Contract.family()) :: term()
  def build_sample_payload(:watch_ticker) do
    %Ticker{symbol: "BTC/USDT", last: 42_000.0, bid: 41_999.0, ask: 42_001.0}
  end

  def build_sample_payload(:watch_trades) do
    [
      %Trade{
        symbol: "BTC/USDT",
        price: 42_000.0,
        amount: 0.5,
        timestamp: 1_700_000_000_000,
        side: :buy
      }
    ]
  end

  def build_sample_payload(:watch_order_book) do
    %OrderBook{
      bids: [[41_999.0, 1.0], [41_998.0, 2.0]],
      asks: [[42_001.0, 0.5], [42_002.0, 1.5]],
      symbol: "BTC/USDT"
    }
  end

  def build_sample_payload(:watch_ohlcv) do
    [
      %OHLCVBar{
        timestamp: 1_700_000_000_000,
        open: 42_000.0,
        high: 42_500.0,
        low: 41_800.0,
        close: 42_100.0,
        volume: 150.5
      }
    ]
  end

  def build_sample_payload(:watch_orders) do
    [
      %Order{
        id: "12345",
        symbol: "BTC/USDT",
        status: :open,
        side: :buy,
        type: :limit,
        price: 42_000.0,
        amount: 0.5
      }
    ]
  end

  def build_sample_payload(:watch_balance) do
    %Balance{
      free: %{"BTC" => 1.0, "USDT" => 50_000.0},
      used: %{"BTC" => 0.0, "USDT" => 0.0},
      total: %{"BTC" => 1.0, "USDT" => 50_000.0}
    }
  end

  def build_sample_payload(:watch_positions) do
    [
      %Position{
        symbol: "BTC/USDT",
        side: :long,
        leverage: 10,
        entry_price: 42_000.0
      }
    ]
  end

  # -- Private ----------------------------------------------------------------

  defp format_violations(violations) do
    Enum.map_join(violations, "\n", fn
      {:wrong_type, expected, got} ->
        "  - Wrong type: expected #{inspect(expected)}, got #{inspect(got, limit: 2)}"

      {:wrong_shape, expected, got} ->
        "  - Wrong shape: expected #{inspect(expected)}, got #{inspect(got, limit: 2)}"

      {:missing_field, field} ->
        "  - Missing required field: #{inspect(field)}"

      {:wrong_element_type, idx, expected, got} ->
        "  - Element [#{idx}]: expected #{inspect(expected)}, got #{inspect(got, limit: 2)}"

      {:invalid_ohlcv, reason} ->
        "  - Invalid OHLCV: #{inspect(reason)}"

      other ->
        "  - #{inspect(other)}"
    end)
  end
end
