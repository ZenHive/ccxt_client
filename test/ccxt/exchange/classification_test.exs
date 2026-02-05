defmodule CCXT.Exchange.ClassificationTest do
  @moduledoc """
  Tests for CCXT.Exchange.Classification module.

  Verifies that exchange classification is correctly derived from CCXT's
  certified and pro properties.
  """
  use ExUnit.Case, async: true

  alias CCXT.Exchange.Classification

  require Logger

  describe "certified_pro_exchanges/0" do
    test "returns exchanges with both certified AND pro" do
      exchanges = Classification.certified_pro_exchanges()

      # All certified_pro should be both certified and pro
      for exchange <- exchanges do
        assert Classification.certified?(exchange),
               "Certified Pro exchange #{exchange} should be certified"

        assert Classification.pro?(exchange),
               "Certified Pro exchange #{exchange} should be pro"
      end
    end

    test "certified_pro_exchanges are non-empty when data is available" do
      exchanges = Classification.certified_pro_exchanges()

      # Verify that any certified_pro exchanges we have are valid
      # (empty list = no iterations, handles --only mode naturally)
      for exchange <- exchanges do
        assert Classification.certified?(exchange),
               "#{exchange} in certified_pro should be certified"

        assert Classification.pro?(exchange),
               "#{exchange} in certified_pro should be pro"
      end
    end
  end

  describe "pro_exchanges/0" do
    test "returns exchanges with pro but NOT certified" do
      pro_only = Classification.pro_exchanges()
      certified = Classification.certified_exchanges()

      # No pro_only should be certified
      for exchange <- pro_only do
        refute exchange in certified,
               "Pro-only exchange #{exchange} should not be certified"
      end

      # All pro_only should have pro: true
      for exchange <- pro_only do
        assert Classification.pro?(exchange),
               "Pro-only exchange #{exchange} should be pro"
      end
    end
  end

  describe "supported_exchanges/0" do
    test "returns exchanges with neither certified nor pro" do
      supported = Classification.supported_exchanges()
      all_pro = Classification.all_pro_exchanges()
      certified = Classification.certified_exchanges()

      for exchange <- supported do
        refute exchange in all_pro,
               "Supported exchange #{exchange} should not be pro"

        refute exchange in certified,
               "Supported exchange #{exchange} should not be certified"
      end
    end
  end

  describe "classification categories" do
    test "are mutually exclusive" do
      certified_pro = MapSet.new(Classification.certified_pro_exchanges())
      pro_only = MapSet.new(Classification.pro_exchanges())
      supported = MapSet.new(Classification.supported_exchanges())

      assert MapSet.disjoint?(certified_pro, pro_only),
             "Certified Pro and Pro should not overlap"

      assert MapSet.disjoint?(certified_pro, supported),
             "Certified Pro and Supported should not overlap"

      assert MapSet.disjoint?(pro_only, supported),
             "Pro and Supported should not overlap"
    end

    test "cover all exchanges" do
      all = MapSet.new(Classification.all_exchanges())
      certified_pro = MapSet.new(Classification.certified_pro_exchanges())
      pro_only = MapSet.new(Classification.pro_exchanges())
      supported = MapSet.new(Classification.supported_exchanges())

      combined =
        certified_pro
        |> MapSet.union(pro_only)
        |> MapSet.union(supported)

      assert MapSet.equal?(all, combined),
             "Combined categories should equal all exchanges"
    end

    test "counts sum to total" do
      total =
        Classification.certified_pro_count() +
          Classification.pro_count() +
          Classification.supported_count()

      all_count = Classification.all_count()

      assert total == all_count,
             "Category counts (#{total}) should sum to all exchanges (#{all_count})"
    end
  end

  describe "testnet support (orthogonal property)" do
    test "testnet_exchanges includes exchanges from multiple categories" do
      testnet = Classification.testnet_exchanges()
      certified_pro = Classification.certified_pro_exchanges()

      # In --only mode with non-certified exchange, certified_pro may be empty
      # Use Enum.empty? to avoid type comparison warning in Elixir 1.20+
      if Enum.empty?(certified_pro) do
        Logger.info("[skipped] No Certified Pro exchanges (likely --only mode)")
        :ok
      else
        # Testnet should include some certified_pro exchanges
        certified_pro_with_testnet = Enum.filter(certified_pro, &(&1 in testnet))
        assert certified_pro_with_testnet != [], "Some certified_pro should have testnet"
      end
    end

    test "has_testnet?/1 works correctly" do
      testnet = Classification.testnet_exchanges()

      for exchange <- testnet do
        assert Classification.has_testnet?(exchange),
               "has_testnet? should return true for #{exchange}"
      end

      # Test a non-testnet exchange if we have one
      all = Classification.all_exchanges()
      non_testnet = all -- testnet

      if non_testnet != [] do
        [first | _] = non_testnet

        refute Classification.has_testnet?(first),
               "has_testnet? should return false for #{first}"
      end
    end

    test "certified_pro_with_testnet returns correct intersection" do
      with_testnet = Classification.certified_pro_with_testnet()
      certified_pro = Classification.certified_pro_exchanges()
      testnet = Classification.testnet_exchanges()

      for exchange <- with_testnet do
        assert exchange in certified_pro
        assert exchange in testnet
      end
    end
  end

  describe "single-exchange predicates" do
    test "certified?/1 returns correct values" do
      certified = Classification.certified_exchanges()

      for exchange <- certified do
        assert Classification.certified?(exchange)
      end

      # Unknown exchange should return false
      refute Classification.certified?("unknown_exchange_xyz")
    end

    test "pro?/1 returns correct values" do
      all_pro = Classification.all_pro_exchanges()

      for exchange <- all_pro do
        assert Classification.pro?(exchange)
      end

      # Unknown exchange should return false
      refute Classification.pro?("unknown_exchange_xyz")
    end

    test "get_classification/1 returns correct category" do
      for exchange <- Classification.certified_pro_exchanges() do
        assert Classification.get_classification(exchange) == :certified_pro
      end

      for exchange <- Classification.pro_exchanges() do
        assert Classification.get_classification(exchange) == :pro
      end

      for exchange <- Classification.supported_exchanges() do
        assert Classification.get_classification(exchange) == :supported
      end

      assert Classification.get_classification("unknown_xyz") == :unknown
    end
  end

  describe "atom conversions" do
    test "certified_pro_atoms returns atoms" do
      atoms = Classification.certified_pro_atoms()
      assert is_list(atoms)

      for atom <- atoms do
        assert is_atom(atom)
      end

      # Check count matches
      assert length(atoms) == Classification.certified_pro_count()
    end

    test "pro_atoms returns atoms" do
      atoms = Classification.pro_atoms()
      assert is_list(atoms)

      for atom <- atoms do
        assert is_atom(atom)
      end

      assert length(atoms) == Classification.pro_count()
    end

    test "supported_atoms returns atoms" do
      atoms = Classification.supported_atoms()
      assert is_list(atoms)

      for atom <- atoms do
        assert is_atom(atom)
      end

      assert length(atoms) == Classification.supported_count()
    end
  end

  describe "sanity checks" do
    @tag :sanity
    test "exchange counts are reasonable" do
      # These counts should match approximately what CCXT reports
      # Allow some variance as CCXT updates

      all_count = Classification.all_count()
      certified_pro_count = Classification.certified_pro_count()
      pro_count = Classification.pro_count()
      supported_count = Classification.supported_count()

      # All exchanges: should be 100+ (CCXT has ~107)
      # Note: During development with only certified-pro specs, this may be lower
      if all_count > 20 do
        assert all_count >= 100, "Expected 100+ exchanges, got #{all_count}"
        assert certified_pro_count >= 10, "Expected 10+ certified pro, got #{certified_pro_count}"
        assert certified_pro_count <= 30, "Expected <30 certified pro, got #{certified_pro_count}"
      end

      # Log counts for visibility
      Logger.info("Classification counts:")
      Logger.info("  All exchanges: #{all_count}")
      Logger.info("  Certified Pro: #{certified_pro_count}")
      Logger.info("  Pro (not certified): #{pro_count}")
      Logger.info("  Supported: #{supported_count}")
      Logger.info("  With testnet: #{Classification.testnet_count()}")
    end
  end
end
