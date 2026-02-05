defmodule CCXT.ErrorTest do
  use ExUnit.Case, async: true

  alias CCXT.Error

  describe "rate_limited/1" do
    test "creates rate limited error with defaults" do
      error = Error.rate_limited()
      assert error.type == :rate_limited
      assert error.message == "Rate limit exceeded"
      assert error.retry_after == nil
    end

    test "creates rate limited error with retry_after" do
      error = Error.rate_limited(retry_after: 1000, exchange: :binance)
      assert error.type == :rate_limited
      assert error.retry_after == 1000
      assert error.exchange == :binance
    end
  end

  describe "insufficient_balance/1" do
    test "creates insufficient balance error" do
      error = Error.insufficient_balance(exchange: :bybit, code: "10001")
      assert error.type == :insufficient_balance
      assert error.message == "Insufficient balance"
      assert error.exchange == :bybit
      assert error.code == "10001"
    end
  end

  describe "invalid_credentials/1" do
    test "creates invalid credentials error" do
      error = Error.invalid_credentials(message: "API key expired")
      assert error.type == :invalid_credentials
      assert error.message == "API key expired"
    end
  end

  describe "order_not_found/1" do
    test "creates order not found error" do
      error = Error.order_not_found(raw: %{"error" => "no order"})
      assert error.type == :order_not_found
      assert error.raw == %{"error" => "no order"}
    end
  end

  describe "invalid_order/1" do
    test "creates invalid order error" do
      error = Error.invalid_order(message: "Price too low")
      assert error.type == :invalid_order
      assert error.message == "Price too low"
    end
  end

  describe "invalid_parameters/1" do
    test "creates invalid parameters error with defaults" do
      error = Error.invalid_parameters()
      assert error.type == :invalid_parameters
      assert error.message == "Invalid request parameters"
    end

    test "creates invalid parameters error with custom message" do
      error = Error.invalid_parameters(message: "Missing required field: symbol", exchange: :binance)
      assert error.type == :invalid_parameters
      assert error.message == "Missing required field: symbol"
      assert error.exchange == :binance
    end
  end

  describe "market_closed/1" do
    test "creates market closed error" do
      error = Error.market_closed()
      assert error.type == :market_closed
      assert error.message == "Market is closed"
    end
  end

  describe "network_error/1" do
    test "creates network error" do
      error = Error.network_error(message: "Connection timeout")
      assert error.type == :network_error
      assert error.message == "Connection timeout"
    end
  end

  describe "access_restricted/1" do
    test "creates access restricted error with defaults" do
      error = Error.access_restricted()
      assert error.type == :access_restricted
      assert error.message == "Access restricted - exchange returned HTML instead of JSON"
    end

    test "creates access restricted error with custom message and hints" do
      error =
        Error.access_restricted(
          message: "Received HTML page 'Access Denied' instead of JSON",
          code: 403,
          exchange: :okx,
          hints: ["Check VPN", "Verify API URL"]
        )

      assert error.type == :access_restricted
      assert error.message == "Received HTML page 'Access Denied' instead of JSON"
      assert error.code == 403
      assert error.exchange == :okx
      # User hints come first, auto hints follow
      assert Enum.at(error.hints, 0) == "Check VPN"
      assert Enum.at(error.hints, 1) == "Verify API URL"
    end

    test "creates access restricted error with raw body preview" do
      error =
        Error.access_restricted(raw: %{status: 200, page_title: "Cloudflare", body_preview: "<!DOCTYPE html>..."})

      assert error.raw == %{status: 200, page_title: "Cloudflare", body_preview: "<!DOCTYPE html>..."}
    end
  end

  describe "exchange_error/2" do
    test "creates generic exchange error" do
      error = Error.exchange_error("Unknown error occurred", code: 500, exchange: :kraken)
      assert error.type == :exchange_error
      assert error.message == "Unknown error occurred"
      assert error.code == 500
      assert error.exchange == :kraken
    end
  end

  # =============================================================================
  # Recoverability (Task 149 - auto-populated)
  # =============================================================================

  describe "recoverable field - auto-populated" do
    test "rate_limited is recoverable" do
      error = Error.rate_limited()
      assert error.recoverable == true
    end

    test "network_error is recoverable" do
      error = Error.network_error()
      assert error.recoverable == true
    end

    test "market_closed is recoverable" do
      error = Error.market_closed()
      assert error.recoverable == true
    end

    test "insufficient_balance is not recoverable" do
      error = Error.insufficient_balance()
      assert error.recoverable == false
    end

    test "invalid_credentials is not recoverable" do
      error = Error.invalid_credentials()
      assert error.recoverable == false
    end

    test "invalid_parameters is not recoverable" do
      error = Error.invalid_parameters()
      assert error.recoverable == false
    end

    test "invalid_order is not recoverable" do
      error = Error.invalid_order()
      assert error.recoverable == false
    end

    test "order_not_found is not recoverable" do
      error = Error.order_not_found()
      assert error.recoverable == false
    end

    test "access_restricted is not recoverable" do
      error = Error.access_restricted()
      assert error.recoverable == false
    end

    test "not_supported is not recoverable" do
      error = Error.not_supported()
      assert error.recoverable == false
    end

    test "exchange_error has nil recoverability" do
      error = Error.exchange_error("Unknown error")
      assert error.recoverable == nil
    end
  end

  # =============================================================================
  # Hints (Task 149 - auto-populated)
  # =============================================================================

  describe "hints field - auto-populated" do
    test "rate_limited auto-populates hints" do
      error = Error.rate_limited()
      assert is_list(error.hints)
      assert error.hints != []
      assert Enum.any?(error.hints, &String.contains?(&1, "backoff"))
    end

    test "rate_limited with retry_after includes specific wait hint" do
      error = Error.rate_limited(retry_after: 2000)
      assert "Wait 2000ms before retrying" in error.hints
    end

    test "insufficient_balance auto-populates hints" do
      error = Error.insufficient_balance()
      assert is_list(error.hints)
      assert Enum.any?(error.hints, &String.contains?(&1, "balance"))
    end

    test "invalid_credentials auto-populates hints" do
      error = Error.invalid_credentials()
      assert is_list(error.hints)
      assert Enum.any?(error.hints, &String.contains?(&1, "API"))
    end

    test "user hints are prepended to auto hints" do
      user_hints = ["Check your network", "Contact support"]
      error = Error.network_error(hints: user_hints)

      assert Enum.at(error.hints, 0) == "Check your network"
      assert Enum.at(error.hints, 1) == "Contact support"
      # Auto hints should follow (at least 3 hints total: 2 user + 1+ auto)
      assert Enum.at(error.hints, 2)
    end

    test "access_restricted with custom hints preserves user hints" do
      error = Error.access_restricted(hints: ["Use VPN", "Check firewall"])
      assert Enum.at(error.hints, 0) == "Use VPN"
      assert Enum.at(error.hints, 1) == "Check firewall"
    end
  end
end
