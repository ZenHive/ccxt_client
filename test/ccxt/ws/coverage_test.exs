defmodule CCXT.WS.CoverageTest do
  use ExUnit.Case, async: true

  alias CCXT.WS.Coverage

  @moduletag :unit

  describe "families/0" do
    test "returns 7 known families" do
      families = Coverage.families()

      assert length(families) == 7

      assert :watch_ticker in families
      assert :watch_trades in families
      assert :watch_order_book in families
      assert :watch_ohlcv in families
      assert :watch_orders in families
      assert :watch_balance in families
      assert :watch_positions in families
    end
  end

  describe "compute_exchange_status/2" do
    test "returns :supported when family is declared and has handler" do
      families_supported = [:watch_ticker, :watch_trades]
      ws_has = %{watch_ticker: true, watch_trades: true}

      statuses = Coverage.compute_exchange_status(families_supported, ws_has)

      assert statuses[:watch_ticker] == :supported
      assert statuses[:watch_trades] == :supported
    end

    test "returns :no_handler when family is declared but handler missing" do
      families_supported = [:watch_ticker]
      ws_has = %{watch_ticker: true, watch_trades: true}

      statuses = Coverage.compute_exchange_status(families_supported, ws_has)

      assert statuses[:watch_ticker] == :supported
      assert statuses[:watch_trades] == :no_handler
    end

    test "returns :unsupported when family is not declared" do
      families_supported = [:watch_ticker]
      ws_has = %{watch_ticker: true}

      statuses = Coverage.compute_exchange_status(families_supported, ws_has)

      assert statuses[:watch_ticker] == :supported
      assert statuses[:watch_positions] == :unsupported
    end

    test "handles nil ws_has — all families unsupported" do
      statuses = Coverage.compute_exchange_status([], nil)

      assert Enum.all?(statuses, fn {_f, s} -> s == :unsupported end)
    end

    test "emulated values are not treated as declared" do
      families_supported = [:watch_ticker]
      ws_has = %{watch_ticker: true, watch_ohlcv: "emulated"}

      statuses = Coverage.compute_exchange_status(families_supported, ws_has)

      assert statuses[:watch_ticker] == :supported
      # "emulated" is not true, so :unsupported
      assert statuses[:watch_ohlcv] == :unsupported
    end

    test "false values are not treated as declared" do
      families_supported = []
      ws_has = %{watch_ticker: false, watch_trades: nil}

      statuses = Coverage.compute_exchange_status(families_supported, ws_has)

      assert statuses[:watch_ticker] == :unsupported
      assert statuses[:watch_trades] == :unsupported
    end

    test "always returns all 7 families" do
      statuses = Coverage.compute_exchange_status([], %{})

      assert map_size(statuses) == 7

      for family <- Coverage.families() do
        assert Map.has_key?(statuses, family), "missing family: #{family}"
      end
    end

    test "mixed scenario — supported, no_handler, and unsupported" do
      families_supported = [:watch_ticker, :watch_order_book]

      ws_has = %{
        watch_ticker: true,
        watch_order_book: true,
        watch_trades: true,
        watch_ohlcv: false,
        watch_positions: nil
      }

      statuses = Coverage.compute_exchange_status(families_supported, ws_has)

      assert statuses[:watch_ticker] == :supported
      assert statuses[:watch_order_book] == :supported
      assert statuses[:watch_trades] == :no_handler
      assert statuses[:watch_ohlcv] == :unsupported
      assert statuses[:watch_positions] == :unsupported
    end
  end

  describe "build_result (via compute_exchange_status + summarize)" do
    test "coverage_pct math is correct" do
      # 2 declared, 1 supported = 50%
      families_supported = [:watch_ticker]
      ws_has = %{watch_ticker: true, watch_trades: true}

      statuses = Coverage.compute_exchange_status(families_supported, ws_has)
      matrix = %{"test" => build_result_from_statuses(statuses)}
      result = matrix["test"]

      assert result.declared_count == 2
      assert result.supported_count == 1
      assert_in_delta result.coverage_pct, 50.0, 0.01
      assert result.missing_families == [:watch_trades]
      assert result.missing_spec == false
    end

    test "zero declared families gives 100% coverage" do
      statuses = Coverage.compute_exchange_status([], %{})
      result = build_result_from_statuses(statuses)

      assert result.declared_count == 0
      assert result.coverage_pct == 100.0
      assert result.missing_families == []
    end

    test "all 7 declared and supported gives 100%" do
      all_families = Coverage.families()
      ws_has = Map.new(all_families, fn f -> {f, true} end)

      statuses = Coverage.compute_exchange_status(all_families, ws_has)
      result = build_result_from_statuses(statuses)

      assert result.declared_count == 7
      assert result.supported_count == 7
      assert result.coverage_pct == 100.0
      assert result.missing_families == []
    end

    test "missing_families list is sorted" do
      families_supported = []
      ws_has = %{watch_trades: true, watch_balance: true, watch_ohlcv: true}

      statuses = Coverage.compute_exchange_status(families_supported, ws_has)
      result = build_result_from_statuses(statuses)

      assert result.missing_families == Enum.sort(result.missing_families)
    end
  end

  describe "summarize/1" do
    test "correct aggregate counts" do
      matrix = %{
        "exchange_a" => %{
          statuses: %{},
          supported_count: 5,
          declared_count: 6,
          coverage_pct: 83.3,
          missing_families: [:watch_ohlcv],
          missing_spec: false
        },
        "exchange_b" => %{
          statuses: %{},
          supported_count: 7,
          declared_count: 7,
          coverage_pct: 100.0,
          missing_families: [],
          missing_spec: false
        }
      }

      summary = Coverage.summarize(matrix)

      assert summary.total_exchanges == 2
      assert summary.exchanges_with_gaps == 1
      assert summary.exchanges_fully_covered == 1
      assert summary.missing_specs == 0
      assert summary.total_supported == 12
      assert summary.total_no_handler == 1
      assert summary.total_declared == 13
    end

    test "empty matrix" do
      summary = Coverage.summarize(%{})

      assert summary.total_exchanges == 0
      assert summary.exchanges_with_gaps == 0
      assert summary.exchanges_fully_covered == 0
      assert summary.missing_specs == 0
      assert summary.total_supported == 0
      assert summary.total_no_handler == 0
      assert summary.total_declared == 0
    end

    test "counts missing_specs correctly" do
      matrix = %{
        "no_spec" => %{
          statuses: %{},
          supported_count: 0,
          declared_count: 0,
          coverage_pct: 0.0,
          missing_families: [],
          missing_spec: true
        },
        "has_spec" => %{
          statuses: %{},
          supported_count: 3,
          declared_count: 3,
          coverage_pct: 100.0,
          missing_families: [],
          missing_spec: false
        }
      }

      summary = Coverage.summarize(matrix)

      assert summary.missing_specs == 1
      assert summary.exchanges_with_gaps == 1
      assert summary.exchanges_fully_covered == 1
    end
  end

  describe "missing spec result" do
    test "compute_result for nonexistent exchange returns missing_spec result" do
      result = Coverage.compute_result("nonexistent_exchange_xyz")

      assert result.missing_spec == true
      assert result.declared_count == 0
      assert result.supported_count == 0
      assert result.coverage_pct == 0.0
      assert result.missing_families == []
      assert Enum.all?(result.statuses, fn {_f, s} -> s == :unsupported end)
    end
  end

  describe "integration smoke test" do
    test "compute_matrix with bybit returns valid structure" do
      # bybit should be available as an extracted spec
      matrix = Coverage.compute_matrix(["bybit"])

      assert Map.has_key?(matrix, "bybit")
      result = matrix["bybit"]

      assert is_map(result.statuses)
      assert map_size(result.statuses) == 7
      assert is_integer(result.supported_count)
      assert is_integer(result.declared_count)
      assert is_float(result.coverage_pct)
      assert is_list(result.missing_families)
      assert result.missing_spec == false

      # All status values must be valid atoms
      for {_family, status} <- result.statuses do
        assert status in [:supported, :no_handler, :unsupported],
               "Invalid status: #{inspect(status)}"
      end
    end
  end

  # Helper to build a result from statuses without going through spec loading
  defp build_result_from_statuses(statuses) do
    declared_count = Enum.count(statuses, fn {_f, s} -> s != :unsupported end)
    supported_count = Enum.count(statuses, fn {_f, s} -> s == :supported end)

    missing_families =
      statuses
      |> Enum.filter(fn {_f, s} -> s == :no_handler end)
      |> Enum.map(fn {f, _s} -> f end)
      |> Enum.sort()

    coverage_pct =
      if declared_count == 0 do
        100.0
      else
        supported_count / declared_count * 100.0
      end

    %{
      statuses: statuses,
      supported_count: supported_count,
      declared_count: declared_count,
      coverage_pct: coverage_pct,
      missing_families: missing_families,
      missing_spec: false
    }
  end
end
