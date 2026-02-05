defmodule CCXT.Generator.Functions.DocsTest do
  @moduledoc """
  Tests for documentation generation, including fee information.
  """
  use ExUnit.Case, async: true

  alias CCXT.Generator.Functions.Docs
  alias CCXT.Spec

  # ===========================================================================
  # Task 110: Fee info in generated docs
  # ===========================================================================

  describe "generate_doc/4 with fees" do
    test "includes fee section for create_order with trading fees" do
      spec_with_fees = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [],
        has: %{},
        options: %{},
        fees: %{
          trading: %{maker: 0.001, taker: 0.002, tier_based: false}
        }
      }

      doc = Docs.generate_doc(:create_order, [:symbol, :type, :side, :amount, :price], true, spec_with_fees)

      assert doc =~ "## Fees"
      # Trailing zeros are trimmed for cleaner display
      assert doc =~ "Maker: 0.1%"
      assert doc =~ "Taker: 0.2%"
      assert doc =~ "Tier-based: false"
    end

    test "includes market-type specific fees when different from base" do
      spec_with_market_fees = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [],
        has: %{},
        options: %{},
        fees: %{
          trading: %{maker: 0.001, taker: 0.002},
          swap: %{maker: 0.0002, taker: 0.0005}
        }
      }

      doc = Docs.generate_doc(:create_order, [:symbol, :type, :side, :amount], true, spec_with_market_fees)

      assert doc =~ "## Fees"
      # Trailing zeros are trimmed for cleaner display
      assert doc =~ "Swap: maker 0.02%, taker 0.05%"
    end

    test "does not include fee section for non-order endpoints" do
      spec_with_fees = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [],
        has: %{},
        options: %{},
        fees: %{
          trading: %{maker: 0.001, taker: 0.002}
        }
      }

      doc = Docs.generate_doc(:fetch_ticker, [:symbol], false, spec_with_fees)

      refute doc =~ "## Fees"
    end

    test "does not include fee section when no fees in spec" do
      spec_no_fees = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [],
        has: %{},
        options: %{},
        fees: nil
      }

      doc = Docs.generate_doc(:create_order, [:symbol, :type, :side, :amount], true, spec_no_fees)

      refute doc =~ "## Fees"
    end

    test "includes fees for all order-related methods" do
      spec_with_fees = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [],
        has: %{},
        options: %{},
        fees: %{
          trading: %{maker: 0.001, taker: 0.002}
        }
      }

      order_methods = [:create_order, :create_orders, :edit_order, :create_market_order, :create_limit_order]

      for method <- order_methods do
        doc = Docs.generate_doc(method, [:symbol], true, spec_with_fees)
        assert doc =~ "## Fees", "Expected fee section for #{method}"
      end
    end
  end

  describe "generate_doc/4 parameters" do
    test "includes credentials parameter for authenticated endpoints" do
      spec = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [],
        has: %{},
        options: %{},
        fees: nil
      }

      doc = Docs.generate_doc(:fetch_balance, [], true, spec)

      assert doc =~ "credentials"
      assert doc =~ "CCXT.Credentials struct"
    end

    test "includes parameter descriptions" do
      spec = %Spec{
        id: :test_exchange,
        name: "Test",
        classification: :supported,
        urls: %{api: "https://api.test.com"},
        signing: %{pattern: :none},
        endpoints: [],
        has: %{},
        options: %{},
        fees: nil
      }

      doc = Docs.generate_doc(:fetch_ticker, [:symbol], false, spec)

      assert doc =~ "`symbol`"
      assert doc =~ "Trading symbol"
    end
  end
end
