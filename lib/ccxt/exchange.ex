defmodule CCXT.Exchange do
  @moduledoc """
  Documentation for the unified API convention used by exchange modules.

  Generated exchange modules follow these conventions, providing a consistent
  interface across 100+ exchanges. Note that each exchange may have slightly
  different parameters based on their API - this module documents the general
  patterns.

  ## API Categories

  ### Public Market Data (no credentials required)
  - `fetch_ticker/2` - Get ticker for a symbol
  - `fetch_tickers/2` - Get tickers for multiple symbols
  - `fetch_order_book/3` - Get order book for a symbol
  - `fetch_trades/3` - Get recent trades
  - `fetch_ohlcv/4` - Get OHLCV candles
  - `fetch_markets/1` - Get all available markets

  ### Private Account Data (credentials required)
  - `fetch_balance/2` - Get account balance
  - `fetch_open_orders/3` - Get open orders
  - `fetch_closed_orders/3` - Get closed orders
  - `fetch_order/3` - Get a specific order
  - `fetch_my_trades/3` - Get your trades

  ### Trading (credentials required)
  - `create_order/7` - Create a new order
  - `cancel_order/4` - Cancel an order
  - `cancel_all_orders/3` - Cancel all orders

  ### Derivatives (credentials required)
  - `fetch_positions/3` - Get open positions
  - `set_leverage/4` - Set leverage for a symbol

  ## Usage

  Exchange modules are generated from spec files:

      # Public data - no credentials needed
      {:ok, ticker} = CCXT.Bybit.fetch_ticker("BTC/USDT")

      # Private data - credentials required
      creds = %CCXT.Credentials{api_key: "...", secret: "..."}
      {:ok, balance} = CCXT.Bybit.fetch_balance(creds)

  ## Exchange-Specific Parameters

  Many exchanges require additional parameters (e.g., `category`, `accountType`).
  Pass these via the `params:` option to maintain consistent function signatures:

      # Bybit requires category for most endpoints
      CCXT.Bybit.fetch_ticker("BTCUSDT", params: %{category: "spot"})
      CCXT.Bybit.fetch_balance(creds, params: %{accountType: "UNIFIED"})

      # OKX uses instType
      CCXT.OKX.fetch_ticker("BTC-USDT", params: %{instType: "SPOT"})

  This pattern keeps the unified API consistent while allowing exchange-specific
  customization without changing function arities.

  ## Introspection Functions

  All generated modules include:
  - `__ccxt_spec__/0` - Returns the exchange specification
  - `__ccxt_endpoints__/0` - Returns the list of supported endpoints
  - `__ccxt_signing__/0` - Returns the signing configuration
  - `__ccxt_classification__/0` - Returns the classification (:certified_pro, :pro, or :supported)

  ## Why Not a Behaviour?

  Exchange APIs vary significantly - different parameters, different response
  structures, different capabilities. A strict Elixir behaviour would require
  all exchanges to implement identical function signatures, which doesn't match
  reality. Instead, each generated module has its own `@spec` that Dialyzer
  validates, providing type safety without false conformity guarantees.

  ## Return Types

  Generated modules currently return raw exchange responses as maps. A future
  phase will add response normalization to convert raw maps to typed structs
  like `Ticker.t()`, `Order.t()`, etc.
  """
end
