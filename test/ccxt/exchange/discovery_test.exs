defmodule CCXT.Exchange.DiscoveryTest do
  use ExUnit.Case, async: true

  alias CCXT.Exchange.Discovery

  describe "which_support/1" do
    test "returns exchanges supporting fetch_ticker" do
      exchanges = Discovery.which_support(:fetch_ticker)

      assert is_list(exchanges)
      assert exchanges != []

      # All returned modules should have the capability
      for module <- exchanges do
        spec = module.__ccxt_spec__()
        assert Map.get(spec.has, :fetch_ticker, false) == true
      end
    end

    test "returns empty list for unknown capability" do
      exchanges = Discovery.which_support(:nonexistent_capability_xyz)
      assert exchanges == []
    end

    test "returns exchanges supporting fetch_balance" do
      exchanges = Discovery.which_support(:fetch_balance)
      assert is_list(exchanges)
      # fetch_balance is a common capability
      assert exchanges != []
    end
  end

  describe "which_support_all/1" do
    test "returns all exchanges for empty list" do
      all = Discovery.which_support_all([])
      assert is_list(all)
      assert all != []
    end

    test "returns exchanges supporting multiple capabilities" do
      exchanges = Discovery.which_support_all([:fetch_ticker, :fetch_balance])

      assert is_list(exchanges)

      # All returned exchanges should support both capabilities
      for module <- exchanges do
        spec = module.__ccxt_spec__()
        assert Map.get(spec.has, :fetch_ticker, false) == true
        assert Map.get(spec.has, :fetch_balance, false) == true
      end
    end

    test "returns subset when filtering by more capabilities" do
      one_cap = Discovery.which_support_all([:fetch_ticker])
      two_caps = Discovery.which_support_all([:fetch_ticker, :fetch_balance])

      # Adding more requirements should not increase the count
      assert length(two_caps) <= length(one_cap)
    end

    test "returns empty list when no exchange supports all capabilities" do
      # Use an impossible combination
      exchanges = Discovery.which_support_all([:fetch_ticker, :nonexistent_xyz])
      assert exchanges == []
    end
  end

  describe "which_support_any/1" do
    test "returns empty list for empty input" do
      exchanges = Discovery.which_support_any([])
      assert exchanges == []
    end

    test "returns exchanges supporting at least one capability" do
      exchanges = Discovery.which_support_any([:fetch_ticker, :nonexistent_xyz])

      # Should return same as which_support(:fetch_ticker) since other is unknown
      ticker_only = Discovery.which_support(:fetch_ticker)
      assert MapSet.new(exchanges) == MapSet.new(ticker_only)
    end

    test "returns superset when adding more options" do
      one_option = Discovery.which_support_any([:fetch_ticker])
      # Any exchange supporting either should be >= exchanges supporting just one
      two_options = Discovery.which_support_any([:fetch_ticker, :fetch_balance])

      assert length(two_options) >= length(one_option)
    end
  end

  describe "compare/2" do
    test "compares capability across exchanges" do
      exchanges = Enum.take(Discovery.all_exchanges(), 2)

      if length(exchanges) < 2 do
        flunk("Need at least 2 exchange modules to test compare/2. Run `mix ccxt.sync --tier1` first.")
      end

      result = Discovery.compare(exchanges, :fetch_ticker)

      assert is_map(result)
      assert map_size(result) == 2

      for {module, details} <- result do
        assert is_atom(module)
        assert Map.has_key?(details, :supported)
        assert Map.has_key?(details, :spec_id)
        assert Map.has_key?(details, :endpoint)
      end
    end

    test "returns empty map for empty module list" do
      result = Discovery.compare([], :fetch_ticker)
      assert result == %{}
    end

    test "filters non-exchange modules" do
      result = Discovery.compare([Enum, String], :fetch_ticker)
      assert result == %{}
    end

    test "includes endpoint details when available" do
      case Discovery.which_support(:fetch_ticker) do
        [module | _] ->
          result = Discovery.compare([module], :fetch_ticker)

          details = result[module]
          assert details.supported == true
          # Should have endpoint info for semantic endpoints
          if details.endpoint do
            assert is_map(details.endpoint)
          end

        [] ->
          flunk("No exchanges support :fetch_ticker. Run `mix ccxt.sync --tier1` first.")
      end
    end
  end

  describe "all_capabilities/1" do
    test "returns list of capability atoms" do
      capabilities = Discovery.all_capabilities()

      assert is_list(capabilities)
      assert capabilities != []
      assert Enum.all?(capabilities, &is_atom/1)
    end

    test "includes common capabilities" do
      capabilities = Discovery.all_capabilities()

      # These should be present in any exchange
      assert :fetch_ticker in capabilities
    end

    test "returns sorted unique list" do
      capabilities = Discovery.all_capabilities()

      # Should be sorted
      assert capabilities == Enum.sort(capabilities)

      # Should be unique
      assert capabilities == Enum.uniq(capabilities)
    end
  end

  describe "all_exchanges/0" do
    test "returns list of exchange modules" do
      modules = Discovery.all_exchanges()

      assert is_list(modules)
      assert modules != []

      for module <- modules do
        assert is_atom(module)
        assert function_exported?(module, :__ccxt_spec__, 0)
      end
    end
  end

  describe "capability_counts/0" do
    test "returns map of capability to count" do
      counts = Discovery.capability_counts()

      assert is_map(counts)
      assert map_size(counts) > 0

      # fetch_ticker should be widely supported
      assert counts[:fetch_ticker] > 0
    end

    test "counts match which_support results" do
      counts = Discovery.capability_counts()
      ticker_exchanges = Discovery.which_support(:fetch_ticker)

      assert counts[:fetch_ticker] == length(ticker_exchanges)
    end
  end

  describe "which_support_ids/1" do
    test "returns exchange IDs instead of modules" do
      ids = Discovery.which_support_ids(:fetch_ticker)

      assert is_list(ids)
      assert ids != []
      assert Enum.all?(ids, &is_binary/1)
    end

    test "returns empty list for unsupported capability" do
      ids = Discovery.which_support_ids(:nonexistent_xyz)
      assert ids == []
    end
  end
end
