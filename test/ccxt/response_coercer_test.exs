defmodule CCXT.ResponseCoercerTest do
  @moduledoc """
  Tests for response type coercion.
  """
  use ExUnit.Case, async: true

  alias CCXT.ResponseCoercer
  alias CCXT.Types.Account
  alias CCXT.Types.Balance
  alias CCXT.Types.BorrowInterest
  alias CCXT.Types.Conversion
  alias CCXT.Types.CrossBorrowRate
  alias CCXT.Types.DepositAddress
  alias CCXT.Types.DepositWithdrawFee
  alias CCXT.Types.FundingHistory
  alias CCXT.Types.FundingRate
  alias CCXT.Types.FundingRateHistory
  alias CCXT.Types.Greeks
  alias CCXT.Types.IsolatedBorrowRate
  alias CCXT.Types.LastPrice
  alias CCXT.Types.LedgerEntry
  alias CCXT.Types.Leverage
  alias CCXT.Types.LeverageTier
  alias CCXT.Types.Liquidation
  alias CCXT.Types.LongShortRatio
  alias CCXT.Types.MarginMode
  alias CCXT.Types.MarginModification
  alias CCXT.Types.OpenInterest
  alias CCXT.Types.Option
  alias CCXT.Types.Order
  alias CCXT.Types.OrderBook
  alias CCXT.Types.Position
  alias CCXT.Types.Ticker
  alias CCXT.Types.Trade
  alias CCXT.Types.TradingFeeInterface
  alias CCXT.Types.Transaction
  alias CCXT.Types.TransferEntry

  describe "coerce/3 with nil type" do
    test "returns data unchanged" do
      data = %{"symbol" => "BTC/USDT", "last" => 50_000.0}
      assert ResponseCoercer.coerce(data, nil, []) == data
    end
  end

  describe "coerce/3 with raw: true" do
    test "returns data unchanged for ticker type" do
      data = %{"symbol" => "BTC/USDT", "last" => 50_000.0}
      assert ResponseCoercer.coerce(data, :ticker, raw: true) == data
    end

    test "returns data unchanged for order type" do
      data = %{"id" => "123", "symbol" => "BTC/USDT"}
      assert ResponseCoercer.coerce(data, :order, raw: true) == data
    end

    test "returns list unchanged for tickers type" do
      data = [%{"symbol" => "BTC/USDT"}, %{"symbol" => "ETH/USDT"}]
      assert ResponseCoercer.coerce(data, :tickers, raw: true) == data
    end
  end

  describe "coerce/3 for :ticker" do
    test "coerces map to Ticker struct" do
      data = %{
        "symbol" => "BTC/USDT",
        "last" => 50_000.0,
        "bid" => 49_999.0,
        "ask" => 50_001.0,
        "high" => 51_000.0,
        "low" => 49_000.0,
        "open" => 49_500.0,
        "close" => 50_000.0,
        "baseVolume" => 1000.0,
        "quoteVolume" => 50_000_000.0
      }

      result = ResponseCoercer.coerce(data, :ticker, [])

      assert %Ticker{} = result
      assert result.symbol == "BTC/USDT"
      assert result.last == 50_000.0
    end
  end

  describe "coerce/3 for :tickers (list)" do
    test "coerces list of maps to list of Ticker structs" do
      data = [
        %{"symbol" => "BTC/USDT", "last" => 50_000.0},
        %{"symbol" => "ETH/USDT", "last" => 3000.0}
      ]

      result = ResponseCoercer.coerce(data, :tickers, [])

      assert is_list(result)
      assert length(result) == 2
      assert %Ticker{symbol: "BTC/USDT"} = Enum.at(result, 0)
      assert %Ticker{symbol: "ETH/USDT"} = Enum.at(result, 1)
    end
  end

  describe "coerce/3 for :order" do
    test "coerces map to Order struct" do
      data = %{
        "id" => "order123",
        "symbol" => "BTC/USDT",
        "side" => "buy",
        "type" => "limit",
        "amount" => 1.0,
        "price" => 50_000.0,
        "status" => "open"
      }

      result = ResponseCoercer.coerce(data, :order, [])

      assert %Order{} = result
      assert result.id == "order123"
      assert result.symbol == "BTC/USDT"
    end
  end

  describe "coerce/3 for :orders (list)" do
    test "coerces list of maps to list of Order structs" do
      data = [
        %{"id" => "order1", "symbol" => "BTC/USDT"},
        %{"id" => "order2", "symbol" => "ETH/USDT"}
      ]

      result = ResponseCoercer.coerce(data, :orders, [])

      assert is_list(result)
      assert length(result) == 2
      assert %Order{id: "order1"} = Enum.at(result, 0)
      assert %Order{id: "order2"} = Enum.at(result, 1)
    end
  end

  describe "coerce/3 for :position" do
    test "coerces map to Position struct" do
      data = %{
        "symbol" => "BTC/USDT",
        "side" => "long",
        "contracts" => 10.0,
        "notional" => 500_000.0
      }

      result = ResponseCoercer.coerce(data, :position, [])

      assert %Position{} = result
      assert result.symbol == "BTC/USDT"
    end
  end

  describe "coerce/3 for :positions (list)" do
    test "coerces list of maps to list of Position structs" do
      data = [
        %{"symbol" => "BTC/USDT", "side" => "long"},
        %{"symbol" => "ETH/USDT", "side" => "short"}
      ]

      result = ResponseCoercer.coerce(data, :positions, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%Position{}, &1))
    end
  end

  describe "coerce/3 for :balance" do
    test "coerces map to Balance struct" do
      data = %{
        "info" => %{},
        "timestamp" => 1_640_000_000_000,
        "datetime" => "2021-12-20T00:00:00.000Z",
        "free" => %{"BTC" => 1.0, "USDT" => 10_000.0},
        "used" => %{"BTC" => 0.5, "USDT" => 5000.0},
        "total" => %{"BTC" => 1.5, "USDT" => 15_000.0}
      }

      result = ResponseCoercer.coerce(data, :balance, [])

      assert %Balance{} = result
    end
  end

  describe "coerce/3 for :order_book" do
    test "coerces map to OrderBook struct" do
      data = %{
        "symbol" => "BTC/USDT",
        "bids" => [[50_000.0, 1.0], [49_999.0, 2.0]],
        "asks" => [[50_001.0, 1.5], [50_002.0, 0.5]],
        "timestamp" => 1_640_000_000_000,
        "nonce" => 12_345
      }

      result = ResponseCoercer.coerce(data, :order_book, [])

      assert %OrderBook{} = result
      assert result.symbol == "BTC/USDT"
    end
  end

  describe "coerce/3 for :trade" do
    test "coerces map to Trade struct" do
      data = %{
        "id" => "trade123",
        "symbol" => "BTC/USDT",
        "side" => "buy",
        "price" => 50_000.0,
        "amount" => 0.1
      }

      result = ResponseCoercer.coerce(data, :trade, [])

      assert %Trade{} = result
      assert result.id == "trade123"
    end
  end

  describe "coerce/3 for :trades (list)" do
    test "coerces list of maps to list of Trade structs" do
      data = [
        %{"id" => "trade1", "symbol" => "BTC/USDT"},
        %{"id" => "trade2", "symbol" => "BTC/USDT"}
      ]

      result = ResponseCoercer.coerce(data, :trades, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%Trade{}, &1))
    end
  end

  describe "coerce/3 for :funding_rate" do
    test "coerces map to FundingRate struct" do
      data = %{
        "symbol" => "BTC/USDT:USDT",
        "info" => %{},
        "fundingRate" => 0.0001,
        "markPrice" => 50_000.0,
        "indexPrice" => 49_998.0,
        "timestamp" => 1_700_000_000_000,
        "datetime" => "2023-11-14T22:13:20.000Z"
      }

      result = ResponseCoercer.coerce(data, :funding_rate, [])

      assert %FundingRate{} = result
      assert result.symbol == "BTC/USDT:USDT"
      assert result.funding_rate == 0.0001
      assert result.mark_price == 50_000.0
    end
  end

  describe "coerce/3 for :funding_rates (list)" do
    test "coerces list of maps to list of FundingRate structs" do
      data = [
        %{"symbol" => "BTC/USDT:USDT", "info" => %{}, "fundingRate" => 0.0001},
        %{"symbol" => "ETH/USDT:USDT", "info" => %{}, "fundingRate" => 0.0002}
      ]

      result = ResponseCoercer.coerce(data, :funding_rates, [])

      assert is_list(result)
      assert length(result) == 2
      assert %FundingRate{symbol: "BTC/USDT:USDT"} = Enum.at(result, 0)
      assert %FundingRate{symbol: "ETH/USDT:USDT"} = Enum.at(result, 1)
    end
  end

  describe "coerce/3 for :funding_rates (dict)" do
    test "coerces dict of maps to dict of FundingRate structs" do
      data = %{
        "BTC/USDT:USDT" => %{
          "symbol" => "BTC/USDT:USDT",
          "info" => %{},
          "fundingRate" => 0.0001,
          "markPrice" => 50_000.0
        },
        "ETH/USDT:USDT" => %{
          "symbol" => "ETH/USDT:USDT",
          "info" => %{},
          "fundingRate" => 0.0002,
          "markPrice" => 3000.0
        }
      }

      result = ResponseCoercer.coerce(data, :funding_rates, [])

      assert is_map(result)
      assert map_size(result) == 2
      assert %FundingRate{symbol: "BTC/USDT:USDT", funding_rate: 0.0001} = result["BTC/USDT:USDT"]
      assert %FundingRate{symbol: "ETH/USDT:USDT", funding_rate: 0.0002} = result["ETH/USDT:USDT"]
    end
  end

  describe "coerce/3 for :funding_rate_history (list)" do
    test "coerces list of maps to list of FundingRateHistory structs" do
      data = [
        %{
          "symbol" => "BTC/USDT:USDT",
          "info" => %{},
          "fundingRate" => 0.0001,
          "timestamp" => 1_700_000_000_000,
          "datetime" => "2023-11-14T22:13:20.000Z"
        },
        %{
          "symbol" => "BTC/USDT:USDT",
          "info" => %{},
          "fundingRate" => 0.00015,
          "timestamp" => 1_700_028_800_000,
          "datetime" => "2023-11-15T06:13:20.000Z"
        }
      ]

      result = ResponseCoercer.coerce(data, :funding_rate_history, [])

      assert is_list(result)
      assert length(result) == 2
      assert %FundingRateHistory{funding_rate: 0.0001} = Enum.at(result, 0)
      assert %FundingRateHistory{funding_rate: 0.00015} = Enum.at(result, 1)
    end
  end

  # --- New types (Task 170) ---

  describe "coerce/3 for :transaction" do
    test "coerces map to Transaction struct" do
      data = %{
        "id" => "tx123",
        "txid" => "0xabc",
        "timestamp" => 1_700_000_000_000,
        "datetime" => "2023-11-14T22:13:20.000Z",
        "currency" => "BTC",
        "amount" => 1.5,
        "status" => "ok",
        "type" => "deposit"
      }

      result = ResponseCoercer.coerce(data, :transaction, [])

      assert %Transaction{} = result
      assert result.id == "tx123"
      assert result.currency == "BTC"
      assert result.amount == 1.5
    end
  end

  describe "coerce/3 for :transactions (list)" do
    test "coerces list of maps to list of Transaction structs" do
      data = [
        %{"id" => "tx1", "currency" => "BTC", "amount" => 1.0, "type" => "deposit"},
        %{"id" => "tx2", "currency" => "ETH", "amount" => 10.0, "type" => "withdrawal"}
      ]

      result = ResponseCoercer.coerce(data, :transactions, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%Transaction{}, &1))
    end
  end

  describe "coerce/3 for :transfer" do
    test "coerces map to TransferEntry struct" do
      data = %{
        "id" => "transfer123",
        "timestamp" => 1_700_000_000_000,
        "datetime" => "2023-11-14T22:13:20.000Z",
        "currency" => "USDT",
        "amount" => 1000.0,
        "status" => "ok"
      }

      result = ResponseCoercer.coerce(data, :transfer, [])

      assert %TransferEntry{} = result
      assert result.id == "transfer123"
      assert result.currency == "USDT"
    end
  end

  describe "coerce/3 for :transfers (list)" do
    test "coerces list of maps to list of TransferEntry structs" do
      data = [
        %{"id" => "t1", "currency" => "USDT", "amount" => 500.0},
        %{"id" => "t2", "currency" => "BTC", "amount" => 0.1}
      ]

      result = ResponseCoercer.coerce(data, :transfers, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%TransferEntry{}, &1))
    end
  end

  describe "coerce/3 for :deposit_address" do
    test "coerces map to DepositAddress struct" do
      data = %{
        "currency" => "BTC",
        "network" => "bitcoin",
        "address" => "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
        "tag" => nil
      }

      result = ResponseCoercer.coerce(data, :deposit_address, [])

      assert %DepositAddress{} = result
      assert result.currency == "BTC"
      assert result.address == "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
    end
  end

  describe "coerce/3 for :ledger_entry" do
    test "coerces map to LedgerEntry struct" do
      data = %{
        "id" => "ledger123",
        "timestamp" => 1_700_000_000_000,
        "datetime" => "2023-11-14T22:13:20.000Z",
        "direction" => "in",
        "currency" => "USDT",
        "amount" => 100.0
      }

      result = ResponseCoercer.coerce(data, :ledger_entry, [])

      assert %LedgerEntry{} = result
      assert result.id == "ledger123"
      assert result.currency == "USDT"
    end
  end

  describe "coerce/3 for :ledger_entries (list)" do
    test "coerces list of maps to list of LedgerEntry structs" do
      data = [
        %{"id" => "l1", "currency" => "USDT", "amount" => 100.0},
        %{"id" => "l2", "currency" => "BTC", "amount" => 0.01}
      ]

      result = ResponseCoercer.coerce(data, :ledger_entries, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%LedgerEntry{}, &1))
    end
  end

  describe "coerce/3 for :leverage" do
    test "coerces map to Leverage struct" do
      data = %{
        "symbol" => "BTC/USDT:USDT",
        "marginMode" => "cross",
        "longLeverage" => 10.0,
        "shortLeverage" => 10.0
      }

      result = ResponseCoercer.coerce(data, :leverage, [])

      assert %Leverage{} = result
      assert result.symbol == "BTC/USDT:USDT"
    end
  end

  describe "coerce/3 for :trading_fee" do
    test "coerces map to TradingFeeInterface struct" do
      data = %{
        "symbol" => "BTC/USDT",
        "maker" => 0.001,
        "taker" => 0.002,
        "percentage" => true
      }

      result = ResponseCoercer.coerce(data, :trading_fee, [])

      assert %TradingFeeInterface{} = result
      assert result.symbol == "BTC/USDT"
      assert result.maker == 0.001
      assert result.taker == 0.002
    end
  end

  describe "coerce/3 for :trading_fees (list)" do
    test "coerces list of maps to list of TradingFeeInterface structs" do
      data = [
        %{"symbol" => "BTC/USDT", "maker" => 0.001, "taker" => 0.002},
        %{"symbol" => "ETH/USDT", "maker" => 0.001, "taker" => 0.002}
      ]

      result = ResponseCoercer.coerce(data, :trading_fees, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%TradingFeeInterface{}, &1))
    end
  end

  describe "coerce/3 for :trading_fees (dict)" do
    test "coerces dict of maps to dict of TradingFeeInterface structs" do
      data = %{
        "BTC/USDT" => %{"symbol" => "BTC/USDT", "maker" => 0.001, "taker" => 0.002},
        "ETH/USDT" => %{"symbol" => "ETH/USDT", "maker" => 0.001, "taker" => 0.002}
      }

      result = ResponseCoercer.coerce(data, :trading_fees, [])

      assert is_map(result)
      assert map_size(result) == 2
      assert %TradingFeeInterface{symbol: "BTC/USDT"} = result["BTC/USDT"]
      assert %TradingFeeInterface{symbol: "ETH/USDT"} = result["ETH/USDT"]
    end
  end

  describe "coerce/3 for :deposit_withdraw_fee" do
    test "coerces map to DepositWithdrawFee struct" do
      data = %{
        "withdraw" => %{"fee" => 0.0005, "percentage" => false},
        "deposit" => %{"fee" => 0.0, "percentage" => false},
        "networks" => %{}
      }

      result = ResponseCoercer.coerce(data, :deposit_withdraw_fee, [])

      assert %DepositWithdrawFee{} = result
    end
  end

  describe "coerce/3 for :deposit_withdraw_fees (dict)" do
    test "coerces dict of maps to dict of DepositWithdrawFee structs" do
      data = %{
        "BTC" => %{"withdraw" => %{"fee" => 0.0005}, "deposit" => %{"fee" => 0.0}, "networks" => %{}},
        "ETH" => %{"withdraw" => %{"fee" => 0.005}, "deposit" => %{"fee" => 0.0}, "networks" => %{}}
      }

      result = ResponseCoercer.coerce(data, :deposit_withdraw_fees, [])

      assert is_map(result)
      assert map_size(result) == 2
      assert %DepositWithdrawFee{} = result["BTC"]
      assert %DepositWithdrawFee{} = result["ETH"]
    end
  end

  describe "coerce/3 for :margin_modification" do
    test "coerces map to MarginModification struct" do
      data = %{
        "symbol" => "BTC/USDT:USDT",
        "type" => "add",
        "marginMode" => "isolated",
        "amount" => 100.0,
        "status" => "ok"
      }

      result = ResponseCoercer.coerce(data, :margin_modification, [])

      assert %MarginModification{} = result
      assert result.symbol == "BTC/USDT:USDT"
      assert result.amount == 100.0
    end
  end

  describe "coerce/3 for :open_interest" do
    test "coerces map to OpenInterest struct" do
      data = %{
        "symbol" => "BTC/USDT:USDT",
        "openInterestAmount" => 50_000.0,
        "openInterestValue" => 2_500_000_000.0,
        "timestamp" => 1_700_000_000_000
      }

      result = ResponseCoercer.coerce(data, :open_interest, [])

      assert %OpenInterest{} = result
      assert result.symbol == "BTC/USDT:USDT"
    end
  end

  describe "coerce/3 for :open_interests (list)" do
    test "coerces list of maps to list of OpenInterest structs" do
      data = [
        %{"symbol" => "BTC/USDT:USDT", "openInterestAmount" => 50_000.0, "timestamp" => 1_700_000_000_000},
        %{"symbol" => "BTC/USDT:USDT", "openInterestAmount" => 51_000.0, "timestamp" => 1_700_003_600_000}
      ]

      result = ResponseCoercer.coerce(data, :open_interests, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%OpenInterest{}, &1))
    end
  end

  describe "coerce/3 for :margin_mode" do
    test "coerces map to MarginMode struct" do
      data = %{
        "symbol" => "BTC/USDT:USDT",
        "marginMode" => "cross"
      }

      result = ResponseCoercer.coerce(data, :margin_mode, [])

      assert %MarginMode{} = result
      assert result.symbol == "BTC/USDT:USDT"
    end
  end

  describe "coerce/3 for :liquidation" do
    test "coerces map to Liquidation struct" do
      data = %{
        "symbol" => "BTC/USDT:USDT",
        "timestamp" => 1_700_000_000_000,
        "datetime" => "2023-11-14T22:13:20.000Z",
        "price" => 45_000.0,
        "baseValue" => 1.5
      }

      result = ResponseCoercer.coerce(data, :liquidation, [])

      assert %Liquidation{} = result
      assert result.symbol == "BTC/USDT:USDT"
      assert result.price == 45_000.0
    end
  end

  describe "coerce/3 for :liquidations (list)" do
    test "coerces list of maps to list of Liquidation structs" do
      data = [
        %{"symbol" => "BTC/USDT:USDT", "price" => 45_000.0, "timestamp" => 1_700_000_000_000},
        %{"symbol" => "ETH/USDT:USDT", "price" => 2000.0, "timestamp" => 1_700_000_000_000}
      ]

      result = ResponseCoercer.coerce(data, :liquidations, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%Liquidation{}, &1))
    end
  end

  describe "coerce/3 for :borrow_interest" do
    test "coerces map to BorrowInterest struct" do
      data = %{
        "symbol" => "BTC/USDT",
        "currency" => "USDT",
        "interest" => 0.05,
        "interestRate" => 0.0001,
        "amountBorrowed" => 10_000.0
      }

      result = ResponseCoercer.coerce(data, :borrow_interest, [])

      assert %BorrowInterest{} = result
      assert result.currency == "USDT"
    end
  end

  describe "coerce/3 for :borrow_interests (list)" do
    test "coerces list of maps to list of BorrowInterest structs" do
      data = [
        %{"currency" => "USDT", "interest" => 0.05, "interestRate" => 0.0001},
        %{"currency" => "BTC", "interest" => 0.001, "interestRate" => 0.00005}
      ]

      result = ResponseCoercer.coerce(data, :borrow_interests, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%BorrowInterest{}, &1))
    end
  end

  describe "coerce/3 for :borrow_rate" do
    test "coerces map to CrossBorrowRate struct" do
      data = %{
        "currency" => "USDT",
        "rate" => 0.0001,
        "period" => 86_400_000,
        "timestamp" => 1_700_000_000_000,
        "datetime" => "2023-11-14T22:13:20.000Z"
      }

      result = ResponseCoercer.coerce(data, :borrow_rate, [])

      assert %CrossBorrowRate{} = result
      assert result.currency == "USDT"
      assert result.rate == 0.0001
    end
  end

  describe "coerce/3 for :conversion" do
    test "coerces map to Conversion struct" do
      data = %{
        "id" => "conv123",
        "timestamp" => 1_700_000_000_000,
        "datetime" => "2023-11-14T22:13:20.000Z",
        "fromCurrency" => "BTC",
        "fromAmount" => 1.0,
        "toCurrency" => "USDT",
        "toAmount" => 50_000.0
      }

      result = ResponseCoercer.coerce(data, :conversion, [])

      assert %Conversion{} = result
      assert result.id == "conv123"
    end
  end

  describe "coerce/3 for :conversions (list)" do
    test "coerces list of maps to list of Conversion structs" do
      data = [
        %{"id" => "c1", "fromCurrency" => "BTC", "toCurrency" => "USDT", "timestamp" => 1_700_000_000_000},
        %{"id" => "c2", "fromCurrency" => "ETH", "toCurrency" => "USDT", "timestamp" => 1_700_000_000_000}
      ]

      result = ResponseCoercer.coerce(data, :conversions, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%Conversion{}, &1))
    end
  end

  describe "coerce/3 for :greeks" do
    test "coerces map to Greeks struct" do
      data = %{
        "symbol" => "BTC-27DEC24-100000-C",
        "timestamp" => 1_700_000_000_000,
        "datetime" => "2023-11-14T22:13:20.000Z",
        "delta" => 0.45,
        "gamma" => 0.001,
        "theta" => -15.5
      }

      result = ResponseCoercer.coerce(data, :greeks, [])

      assert %Greeks{} = result
      assert result.symbol == "BTC-27DEC24-100000-C"
      assert result.delta == 0.45
    end
  end

  # --- New types (Task 170b) ---

  describe "coerce/3 for :account" do
    test "coerces map to Account struct" do
      data = %{
        "id" => "main",
        "type" => "spot",
        "code" => "USDT",
        "info" => %{}
      }

      result = ResponseCoercer.coerce(data, :account, [])

      assert %Account{} = result
      assert result.id == "main"
      assert result.type == "spot"
      assert result.code == "USDT"
    end
  end

  describe "coerce/3 for :accounts (list)" do
    test "coerces list of maps to list of Account structs" do
      data = [
        %{"id" => "main", "type" => "spot", "code" => "USDT"},
        %{"id" => "margin", "type" => "margin", "code" => "BTC"}
      ]

      result = ResponseCoercer.coerce(data, :accounts, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%Account{}, &1))
    end
  end

  describe "coerce/3 for :option" do
    test "coerces map to Option struct" do
      data = %{
        "symbol" => "BTC-27DEC24-100000-C",
        "currency" => "BTC",
        "info" => %{},
        "impliedVolatility" => 0.65,
        "openInterest" => 1000.0,
        "bidPrice" => 500.0,
        "askPrice" => 550.0,
        "midPrice" => 525.0,
        "markPrice" => 520.0,
        "lastPrice" => 510.0,
        "underlyingPrice" => 50_000.0,
        "change" => 10.0,
        "percentage" => 2.0,
        "baseVolume" => 100.0,
        "quoteVolume" => 5_000_000.0
      }

      result = ResponseCoercer.coerce(data, :option, [])

      assert %Option{} = result
      assert result.symbol == "BTC-27DEC24-100000-C"
      assert result.implied_volatility == 0.65
    end
  end

  describe "coerce/3 for :options (dict)" do
    test "coerces dict of maps to dict of Option structs" do
      data = %{
        "BTC-27DEC24-100000-C" => %{
          "symbol" => "BTC-27DEC24-100000-C",
          "currency" => "BTC",
          "info" => %{},
          "impliedVolatility" => 0.65,
          "openInterest" => 1000.0,
          "bidPrice" => 500.0,
          "askPrice" => 550.0,
          "midPrice" => 525.0,
          "markPrice" => 520.0,
          "lastPrice" => 510.0,
          "underlyingPrice" => 50_000.0,
          "change" => 10.0,
          "percentage" => 2.0,
          "baseVolume" => 100.0,
          "quoteVolume" => 5_000_000.0
        },
        "BTC-27DEC24-100000-P" => %{
          "symbol" => "BTC-27DEC24-100000-P",
          "currency" => "BTC",
          "info" => %{},
          "impliedVolatility" => 0.70,
          "openInterest" => 800.0,
          "bidPrice" => 2000.0,
          "askPrice" => 2100.0,
          "midPrice" => 2050.0,
          "markPrice" => 2040.0,
          "lastPrice" => 2030.0,
          "underlyingPrice" => 50_000.0,
          "change" => -5.0,
          "percentage" => -0.25,
          "baseVolume" => 50.0,
          "quoteVolume" => 2_500_000.0
        }
      }

      result = ResponseCoercer.coerce(data, :options, [])

      assert is_map(result)
      assert map_size(result) == 2
      assert %Option{symbol: "BTC-27DEC24-100000-C"} = result["BTC-27DEC24-100000-C"]
      assert %Option{symbol: "BTC-27DEC24-100000-P"} = result["BTC-27DEC24-100000-P"]
    end
  end

  describe "coerce/3 for :funding_history" do
    test "coerces map to FundingHistory struct" do
      data = %{
        "id" => "fh123",
        "symbol" => "BTC/USDT:USDT",
        "code" => "USDT",
        "info" => %{},
        "timestamp" => 1_700_000_000_000,
        "datetime" => "2023-11-14T22:13:20.000Z",
        "amount" => 1.25
      }

      result = ResponseCoercer.coerce(data, :funding_history, [])

      assert %FundingHistory{} = result
      assert result.id == "fh123"
      assert result.symbol == "BTC/USDT:USDT"
      assert result.amount == 1.25
    end
  end

  describe "coerce/3 for :funding_histories (list)" do
    test "coerces list of maps to list of FundingHistory structs" do
      data = [
        %{"id" => "fh1", "symbol" => "BTC/USDT:USDT", "code" => "USDT", "amount" => 1.0},
        %{"id" => "fh2", "symbol" => "ETH/USDT:USDT", "code" => "USDT", "amount" => 0.5}
      ]

      result = ResponseCoercer.coerce(data, :funding_histories, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%FundingHistory{}, &1))
    end
  end

  describe "coerce/3 for :isolated_borrow_rate" do
    test "coerces map to IsolatedBorrowRate struct" do
      data = %{
        "symbol" => "BTC/USDT",
        "info" => %{},
        "base" => "BTC",
        "baseRate" => 0.0001,
        "quote" => "USDT",
        "quoteRate" => 0.0002,
        "timestamp" => 1_700_000_000_000,
        "datetime" => "2023-11-14T22:13:20.000Z"
      }

      result = ResponseCoercer.coerce(data, :isolated_borrow_rate, [])

      assert %IsolatedBorrowRate{} = result
      assert result.symbol == "BTC/USDT"
      assert result.base == "BTC"
      assert result.base_rate == 0.0001
    end
  end

  describe "coerce/3 for :isolated_borrow_rates (dict)" do
    test "coerces dict of maps to dict of IsolatedBorrowRate structs" do
      data = %{
        "BTC/USDT" => %{
          "symbol" => "BTC/USDT",
          "info" => %{},
          "base" => "BTC",
          "baseRate" => 0.0001,
          "quote" => "USDT",
          "quoteRate" => 0.0002
        },
        "ETH/USDT" => %{
          "symbol" => "ETH/USDT",
          "info" => %{},
          "base" => "ETH",
          "baseRate" => 0.0003,
          "quote" => "USDT",
          "quoteRate" => 0.0004
        }
      }

      result = ResponseCoercer.coerce(data, :isolated_borrow_rates, [])

      assert is_map(result)
      assert map_size(result) == 2
      assert %IsolatedBorrowRate{symbol: "BTC/USDT"} = result["BTC/USDT"]
      assert %IsolatedBorrowRate{symbol: "ETH/USDT"} = result["ETH/USDT"]
    end
  end

  describe "coerce/3 for :last_price" do
    test "coerces map to LastPrice struct" do
      data = %{
        "symbol" => "BTC/USDT",
        "info" => %{},
        "price" => 50_000.0,
        "side" => "buy",
        "timestamp" => 1_700_000_000_000
      }

      result = ResponseCoercer.coerce(data, :last_price, [])

      assert %LastPrice{} = result
      assert result.symbol == "BTC/USDT"
      assert result.price == 50_000.0
    end
  end

  describe "coerce/3 for :last_prices (dict)" do
    test "coerces dict of maps to dict of LastPrice structs" do
      data = %{
        "BTC/USDT" => %{"symbol" => "BTC/USDT", "info" => %{}, "price" => 50_000.0},
        "ETH/USDT" => %{"symbol" => "ETH/USDT", "info" => %{}, "price" => 3000.0}
      }

      result = ResponseCoercer.coerce(data, :last_prices, [])

      assert is_map(result)
      assert map_size(result) == 2
      assert %LastPrice{symbol: "BTC/USDT", price: 50_000.0} = result["BTC/USDT"]
      assert %LastPrice{symbol: "ETH/USDT", price: 3000.0} = result["ETH/USDT"]
    end
  end

  describe "coerce/3 for :long_short_ratio" do
    test "coerces map to LongShortRatio struct" do
      data = %{
        "symbol" => "BTC/USDT:USDT",
        "info" => %{},
        "longShortRatio" => 1.25,
        "timestamp" => 1_700_000_000_000,
        "datetime" => "2023-11-14T22:13:20.000Z"
      }

      result = ResponseCoercer.coerce(data, :long_short_ratio, [])

      assert %LongShortRatio{} = result
      assert result.symbol == "BTC/USDT:USDT"
      assert result.long_short_ratio == 1.25
    end
  end

  describe "coerce/3 for :long_short_ratios (list)" do
    test "coerces list of maps to list of LongShortRatio structs" do
      data = [
        %{"symbol" => "BTC/USDT:USDT", "info" => %{}, "longShortRatio" => 1.25, "timestamp" => 1_700_000_000_000},
        %{"symbol" => "BTC/USDT:USDT", "info" => %{}, "longShortRatio" => 1.30, "timestamp" => 1_700_003_600_000}
      ]

      result = ResponseCoercer.coerce(data, :long_short_ratios, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%LongShortRatio{}, &1))
    end
  end

  describe "coerce/3 for :leverage_tier" do
    test "coerces map to LeverageTier struct" do
      data = %{
        "tier" => 1,
        "symbol" => "BTC/USDT:USDT",
        "currency" => "USDT",
        "info" => %{},
        "minNotional" => 0,
        "maxNotional" => 10_000,
        "maintenanceMarginRate" => 0.005,
        "maxLeverage" => 125
      }

      result = ResponseCoercer.coerce(data, :leverage_tier, [])

      assert %LeverageTier{} = result
      assert result.tier == 1
      assert result.max_leverage == 125
    end
  end

  describe "coerce/3 for :leverage_tiers (dict-of-lists)" do
    test "coerces dict of lists to dict of lists of LeverageTier structs" do
      data = %{
        "BTC/USDT:USDT" => [
          %{
            "tier" => 1,
            "symbol" => "BTC/USDT:USDT",
            "info" => %{},
            "minNotional" => 0,
            "maxNotional" => 10_000,
            "maintenanceMarginRate" => 0.005,
            "maxLeverage" => 125
          },
          %{
            "tier" => 2,
            "symbol" => "BTC/USDT:USDT",
            "info" => %{},
            "minNotional" => 10_000,
            "maxNotional" => 50_000,
            "maintenanceMarginRate" => 0.01,
            "maxLeverage" => 100
          }
        ],
        "ETH/USDT:USDT" => [
          %{
            "tier" => 1,
            "symbol" => "ETH/USDT:USDT",
            "info" => %{},
            "minNotional" => 0,
            "maxNotional" => 5000,
            "maintenanceMarginRate" => 0.005,
            "maxLeverage" => 100
          }
        ]
      }

      result = ResponseCoercer.coerce(data, :leverage_tiers, [])

      assert is_map(result)
      assert map_size(result) == 2

      btc_tiers = result["BTC/USDT:USDT"]
      assert is_list(btc_tiers)
      assert length(btc_tiers) == 2
      assert %LeverageTier{tier: 1, max_leverage: 125} = Enum.at(btc_tiers, 0)
      assert %LeverageTier{tier: 2, max_leverage: 100} = Enum.at(btc_tiers, 1)

      eth_tiers = result["ETH/USDT:USDT"]
      assert is_list(eth_tiers)
      assert length(eth_tiers) == 1
      assert %LeverageTier{tier: 1, max_leverage: 100} = Enum.at(eth_tiers, 0)
    end

    test "handles empty list values" do
      data = %{
        "BTC/USDT:USDT" => [],
        "ETH/USDT:USDT" => [
          %{"tier" => 1, "symbol" => "ETH/USDT:USDT", "info" => %{}, "maxLeverage" => 50}
        ]
      }

      result = ResponseCoercer.coerce(data, :leverage_tiers, [])

      assert result["BTC/USDT:USDT"] == []
      assert [%LeverageTier{max_leverage: 50}] = result["ETH/USDT:USDT"]
    end

    test "logs warning for unexpected non-list non-map values" do
      import ExUnit.CaptureLog

      data = %{
        "BTC/USDT:USDT" => "unexpected_string"
      }

      log =
        capture_log(fn ->
          result = ResponseCoercer.coerce(data, :leverage_tiers, [])
          assert result["BTC/USDT:USDT"] == "unexpected_string"
        end)

      assert log =~ "unexpected value"
      assert log =~ "leverage_tiers"
    end
  end

  describe "coerce/3 for :market_leverage_tiers (list)" do
    test "coerces list of maps to list of LeverageTier structs" do
      data = [
        %{
          "tier" => 1,
          "symbol" => "BTC/USDT:USDT",
          "info" => %{},
          "minNotional" => 0,
          "maxNotional" => 10_000,
          "maintenanceMarginRate" => 0.005,
          "maxLeverage" => 125
        },
        %{
          "tier" => 2,
          "symbol" => "BTC/USDT:USDT",
          "info" => %{},
          "minNotional" => 10_000,
          "maxNotional" => 50_000,
          "maintenanceMarginRate" => 0.01,
          "maxLeverage" => 100
        }
      ]

      result = ResponseCoercer.coerce(data, :market_leverage_tiers, [])

      assert is_list(result)
      assert length(result) == 2
      assert Enum.all?(result, &match?(%LeverageTier{}, &1))
    end
  end

  describe "coerce/3 with unexpected data types" do
    test "returns nil unchanged" do
      assert ResponseCoercer.coerce(nil, :ticker, []) == nil
    end

    test "returns string unchanged" do
      assert ResponseCoercer.coerce("unexpected", :ticker, []) == "unexpected"
    end
  end

  describe "infer_response_type/1" do
    test "infers :ticker from :fetch_ticker" do
      assert ResponseCoercer.infer_response_type(:fetch_ticker) == :ticker
    end

    test "infers :tickers from :fetch_tickers" do
      assert ResponseCoercer.infer_response_type(:fetch_tickers) == :tickers
    end

    test "infers :order from :fetch_order" do
      assert ResponseCoercer.infer_response_type(:fetch_order) == :order
    end

    test "infers :orders from :fetch_orders" do
      assert ResponseCoercer.infer_response_type(:fetch_orders) == :orders
    end

    test "infers :orders from :fetch_open_orders" do
      assert ResponseCoercer.infer_response_type(:fetch_open_orders) == :orders
    end

    test "infers :orders from :fetch_closed_orders" do
      assert ResponseCoercer.infer_response_type(:fetch_closed_orders) == :orders
    end

    test "infers :trades from :fetch_trades" do
      assert ResponseCoercer.infer_response_type(:fetch_trades) == :trades
    end

    test "infers :trades from :fetch_my_trades" do
      assert ResponseCoercer.infer_response_type(:fetch_my_trades) == :trades
    end

    test "infers :position from :fetch_position" do
      assert ResponseCoercer.infer_response_type(:fetch_position) == :position
    end

    test "infers :positions from :fetch_positions" do
      assert ResponseCoercer.infer_response_type(:fetch_positions) == :positions
    end

    test "infers :balance from :fetch_balance" do
      assert ResponseCoercer.infer_response_type(:fetch_balance) == :balance
    end

    test "infers :order_book from :fetch_order_book" do
      assert ResponseCoercer.infer_response_type(:fetch_order_book) == :order_book
    end

    test "infers :order from :create_order" do
      assert ResponseCoercer.infer_response_type(:create_order) == :order
    end

    test "infers :order from :cancel_order" do
      assert ResponseCoercer.infer_response_type(:cancel_order) == :order
    end

    test "infers :order from :edit_order" do
      assert ResponseCoercer.infer_response_type(:edit_order) == :order
    end

    test "infers :funding_rate from :fetch_funding_rate" do
      assert ResponseCoercer.infer_response_type(:fetch_funding_rate) == :funding_rate
    end

    test "infers :funding_rates from :fetch_funding_rates" do
      assert ResponseCoercer.infer_response_type(:fetch_funding_rates) == :funding_rates
    end

    test "infers :funding_rate_history from :fetch_funding_rate_history" do
      assert ResponseCoercer.infer_response_type(:fetch_funding_rate_history) == :funding_rate_history
    end

    # New infer_response_type assertions (Task 170)

    test "infers :transactions from :fetch_deposits" do
      assert ResponseCoercer.infer_response_type(:fetch_deposits) == :transactions
    end

    test "infers :transactions from :fetch_withdrawals" do
      assert ResponseCoercer.infer_response_type(:fetch_withdrawals) == :transactions
    end

    test "infers :transaction from :fetch_deposit" do
      assert ResponseCoercer.infer_response_type(:fetch_deposit) == :transaction
    end

    test "infers :transaction from :fetch_withdrawal" do
      assert ResponseCoercer.infer_response_type(:fetch_withdrawal) == :transaction
    end

    test "infers :deposit_address from :fetch_deposit_address" do
      assert ResponseCoercer.infer_response_type(:fetch_deposit_address) == :deposit_address
    end

    test "infers :transfer from :transfer" do
      assert ResponseCoercer.infer_response_type(:transfer) == :transfer
    end

    test "infers :transfers from :fetch_transfers" do
      assert ResponseCoercer.infer_response_type(:fetch_transfers) == :transfers
    end

    test "infers :ledger_entries from :fetch_ledger" do
      assert ResponseCoercer.infer_response_type(:fetch_ledger) == :ledger_entries
    end

    test "infers :leverage from :fetch_leverage" do
      assert ResponseCoercer.infer_response_type(:fetch_leverage) == :leverage
    end

    test "infers :leverage from :set_leverage" do
      assert ResponseCoercer.infer_response_type(:set_leverage) == :leverage
    end

    test "infers :trading_fee from :fetch_trading_fee" do
      assert ResponseCoercer.infer_response_type(:fetch_trading_fee) == :trading_fee
    end

    test "infers :trading_fees from :fetch_trading_fees" do
      assert ResponseCoercer.infer_response_type(:fetch_trading_fees) == :trading_fees
    end

    test "infers :deposit_withdraw_fees from :fetch_deposit_withdraw_fees" do
      assert ResponseCoercer.infer_response_type(:fetch_deposit_withdraw_fees) == :deposit_withdraw_fees
    end

    test "infers :margin_modification from :add_margin" do
      assert ResponseCoercer.infer_response_type(:add_margin) == :margin_modification
    end

    test "infers :margin_modification from :reduce_margin" do
      assert ResponseCoercer.infer_response_type(:reduce_margin) == :margin_modification
    end

    test "infers :open_interest from :fetch_open_interest" do
      assert ResponseCoercer.infer_response_type(:fetch_open_interest) == :open_interest
    end

    test "infers :open_interests from :fetch_open_interest_history" do
      assert ResponseCoercer.infer_response_type(:fetch_open_interest_history) == :open_interests
    end

    test "infers :margin_mode from :set_margin_mode" do
      assert ResponseCoercer.infer_response_type(:set_margin_mode) == :margin_mode
    end

    test "infers :margin_mode from :fetch_margin_mode" do
      assert ResponseCoercer.infer_response_type(:fetch_margin_mode) == :margin_mode
    end

    test "infers :liquidations from :fetch_liquidations" do
      assert ResponseCoercer.infer_response_type(:fetch_liquidations) == :liquidations
    end

    test "infers :liquidations from :fetch_my_liquidations" do
      assert ResponseCoercer.infer_response_type(:fetch_my_liquidations) == :liquidations
    end

    test "infers :borrow_interests from :fetch_borrow_interest" do
      assert ResponseCoercer.infer_response_type(:fetch_borrow_interest) == :borrow_interests
    end

    test "infers :borrow_rate from :fetch_cross_borrow_rate" do
      assert ResponseCoercer.infer_response_type(:fetch_cross_borrow_rate) == :borrow_rate
    end

    test "infers :conversion from :fetch_convert_trade" do
      assert ResponseCoercer.infer_response_type(:fetch_convert_trade) == :conversion
    end

    test "infers :conversions from :fetch_convert_trade_history" do
      assert ResponseCoercer.infer_response_type(:fetch_convert_trade_history) == :conversions
    end

    test "infers :greeks from :fetch_greeks" do
      assert ResponseCoercer.infer_response_type(:fetch_greeks) == :greeks
    end

    # New infer_response_type assertions (Task 170b)

    test "infers :accounts from :fetch_accounts" do
      assert ResponseCoercer.infer_response_type(:fetch_accounts) == :accounts
    end

    test "infers :option from :fetch_option" do
      assert ResponseCoercer.infer_response_type(:fetch_option) == :option
    end

    test "infers :options from :fetch_option_chain" do
      assert ResponseCoercer.infer_response_type(:fetch_option_chain) == :options
    end

    test "infers :funding_histories from :fetch_funding_history" do
      assert ResponseCoercer.infer_response_type(:fetch_funding_history) == :funding_histories
    end

    test "infers :isolated_borrow_rate from :fetch_isolated_borrow_rate" do
      assert ResponseCoercer.infer_response_type(:fetch_isolated_borrow_rate) == :isolated_borrow_rate
    end

    test "infers :isolated_borrow_rates from :fetch_isolated_borrow_rates" do
      assert ResponseCoercer.infer_response_type(:fetch_isolated_borrow_rates) == :isolated_borrow_rates
    end

    test "infers :last_prices from :fetch_last_prices" do
      assert ResponseCoercer.infer_response_type(:fetch_last_prices) == :last_prices
    end

    test "infers :long_short_ratios from :fetch_long_short_ratio_history" do
      assert ResponseCoercer.infer_response_type(:fetch_long_short_ratio_history) == :long_short_ratios
    end

    test "infers :leverage_tiers from :fetch_leverage_tiers" do
      assert ResponseCoercer.infer_response_type(:fetch_leverage_tiers) == :leverage_tiers
    end

    test "infers :market_leverage_tiers from :fetch_market_leverage_tiers" do
      assert ResponseCoercer.infer_response_type(:fetch_market_leverage_tiers) == :market_leverage_tiers
    end

    test "returns nil for unknown endpoints" do
      assert ResponseCoercer.infer_response_type(:some_custom_endpoint) == nil
      assert ResponseCoercer.infer_response_type(:fetch_unknown) == nil
    end
  end

  describe "type_modules/0" do
    test "returns map of type atoms to modules" do
      modules = ResponseCoercer.type_modules()
      assert is_map(modules)
      # Original types
      assert modules[:ticker] == Ticker
      assert modules[:order] == Order
      assert modules[:funding_rate] == FundingRate
      assert modules[:funding_rate_history] == FundingRateHistory
      # New types (Task 170)
      assert modules[:transaction] == Transaction
      assert modules[:transfer] == TransferEntry
      assert modules[:deposit_address] == DepositAddress
      assert modules[:ledger_entry] == LedgerEntry
      assert modules[:leverage] == Leverage
      assert modules[:trading_fee] == TradingFeeInterface
      assert modules[:deposit_withdraw_fee] == DepositWithdrawFee
      assert modules[:margin_modification] == MarginModification
      assert modules[:open_interest] == OpenInterest
      assert modules[:margin_mode] == MarginMode
      assert modules[:liquidation] == Liquidation
      assert modules[:borrow_interest] == BorrowInterest
      assert modules[:borrow_rate] == CrossBorrowRate
      assert modules[:conversion] == Conversion
      assert modules[:greeks] == Greeks
      # New types (Task 170b)
      assert modules[:account] == Account
      assert modules[:option] == Option
      assert modules[:funding_history] == FundingHistory
      assert modules[:isolated_borrow_rate] == IsolatedBorrowRate
      assert modules[:last_price] == LastPrice
      assert modules[:long_short_ratio] == LongShortRatio
      assert modules[:leverage_tier] == LeverageTier
    end
  end

  describe "list_types/0" do
    test "returns list of plural type atoms" do
      types = ResponseCoercer.list_types()
      assert is_list(types)
      # Original
      assert :tickers in types
      assert :orders in types
      assert :positions in types
      assert :trades in types
      assert :funding_rates in types
      assert :funding_rate_history in types
      # New (Task 170)
      assert :transactions in types
      assert :transfers in types
      assert :ledger_entries in types
      assert :open_interests in types
      assert :liquidations in types
      assert :borrow_interests in types
      assert :conversions in types
      assert :trading_fees in types
      # New (Task 170b)
      assert :accounts in types
      assert :funding_histories in types
      assert :long_short_ratios in types
      assert :market_leverage_tiers in types
    end
  end

  describe "dict_types/0" do
    test "returns list of dict type atoms" do
      types = ResponseCoercer.dict_types()
      assert is_list(types)
      assert :funding_rates in types
      # New (Task 170)
      assert :trading_fees in types
      assert :deposit_withdraw_fees in types
      # New (Task 170b)
      assert :options in types
      assert :isolated_borrow_rates in types
      assert :last_prices in types
    end
  end

  describe "dict_of_list_types/0" do
    test "returns list of dict-of-list type atoms" do
      types = ResponseCoercer.dict_of_list_types()
      assert is_list(types)
      assert :leverage_tiers in types
    end
  end
end
