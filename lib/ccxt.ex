defmodule CCXT do
  @moduledoc """
  Pure Elixir library for cryptocurrency exchange trading.

  Provides unified access to 100+ cryptocurrency exchanges through
  macro-generated modules. Each exchange module implements the
  `CCXT.Exchange` behaviour for consistent API access.

  ## Quick Start

      # Public data - no credentials needed
      {:ok, ticker} = CCXT.Bybit.fetch_ticker("BTC/USDT")

      # Private data - credentials required
      creds = %CCXT.Credentials{
        api_key: "your_api_key",
        secret: "your_secret",
        sandbox: true
      }
      {:ok, balance} = CCXT.Bybit.fetch_balance(creds)

      # Place an order
      {:ok, order} = CCXT.Bybit.create_order(
        creds,
        "BTC/USDT",
        :limit,
        :buy,
        0.001,
        50000.0
      )

  ## Architecture

  - `CCXT.Exchange` - Behaviour defining the unified API
  - `CCXT.Spec` - Exchange specification struct (extracted from CCXT)
  - `CCXT.Credentials` - API credentials struct
  - `CCXT.Error` - Unified error types
  - `CCXT.Symbol` - Symbol normalization
  - `CCXT.Types.*` - Response structs (Ticker, Order, Balance, etc.)

  ## Exchange Tiers

  | Tier | Count | Testing Level |
  |------|-------|---------------|
  | 1    | 10    | Full integration tests against testnets |
  | 2    | 40+   | Fixture-based parsing tests |
  | 3    | 50+   | Compile-only verification |

  """
end
