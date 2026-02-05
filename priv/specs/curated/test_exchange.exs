# Test exchange specification for validating the generator macro.
# This is a minimal spec that exercises all generator features.

%{
  id: "test_exchange",
  name: "Test Exchange",
  countries: ["US"],
  version: "v1",
  classification: :certified_pro,
  options: %{},
  urls: %{
    api: "https://api.test-exchange.com",
    sandbox: "https://sandbox.test-exchange.com",
    www: "https://www.test-exchange.com",
    doc: "https://docs.test-exchange.com"
  },
  rate_limits: %{
    requests: 100,
    period: 60_000
  },
  signing: %{
    pattern: :hmac_sha256_headers,
    api_key_header: "X-API-KEY",
    timestamp_header: "X-TIMESTAMP",
    signature_header: "X-SIGNATURE",
    recv_window_header: "X-RECV-WINDOW",
    recv_window: 5000
  },
  has: %{
    fetch_ticker: true,
    fetch_tickers: true,
    fetch_order_book: true,
    fetch_trades: true,
    fetch_ohlcv: true,
    fetch_markets: true,
    fetch_balance: true,
    fetch_open_orders: true,
    fetch_closed_orders: true,
    fetch_order: true,
    fetch_my_trades: true,
    create_order: true,
    cancel_order: true,
    cancel_all_orders: false,
    fetch_positions: false,
    set_leverage: false
  },
  timeframes: %{
    "1m" => "1",
    "5m" => "5",
    "15m" => "15",
    "1h" => "60",
    "4h" => "240",
    "1d" => "D"
  },
  endpoints: [
    # Public endpoints (no auth)
    %{
      name: :fetch_ticker,
      method: :get,
      path: "/v1/ticker",
      auth: false,
      params: [:symbol]
    },
    %{
      name: :fetch_tickers,
      method: :get,
      path: "/v1/tickers",
      auth: false,
      params: [:symbols]
    },
    %{
      name: :fetch_order_book,
      method: :get,
      path: "/v1/orderbook",
      auth: false,
      params: [:symbol, :limit]
    },
    %{
      name: :fetch_trades,
      method: :get,
      path: "/v1/trades",
      auth: false,
      params: [:symbol, :limit]
    },
    %{
      name: :fetch_ohlcv,
      method: :get,
      path: "/v1/klines",
      auth: false,
      params: [:symbol, :interval, :since, :limit]
    },
    %{
      name: :fetch_markets,
      method: :get,
      path: "/v1/markets",
      auth: false,
      params: []
    },
    # Private endpoints (auth required)
    %{
      name: :fetch_balance,
      method: :get,
      path: "/v1/account/balance",
      auth: true,
      params: []
    },
    %{
      name: :fetch_open_orders,
      method: :get,
      path: "/v1/orders/open",
      auth: true,
      params: [:symbol]
    },
    %{
      name: :fetch_closed_orders,
      method: :get,
      path: "/v1/orders/closed",
      auth: true,
      params: [:symbol]
    },
    %{
      name: :fetch_order,
      method: :get,
      path: "/v1/orders/:order_id",
      auth: true,
      params: [:order_id, :symbol]
    },
    %{
      name: :fetch_my_trades,
      method: :get,
      path: "/v1/trades/mine",
      auth: true,
      params: [:symbol]
    },
    %{
      name: :create_order,
      method: :post,
      path: "/v1/orders",
      auth: true,
      params: [:symbol, :type, :side, :amount, :price]
    },
    %{
      name: :cancel_order,
      method: :delete,
      path: "/v1/orders/:order_id",
      auth: true,
      params: [:order_id, :symbol]
    },
    # Unsupported endpoint (has: cancel_all_orders: false) - generates stub
    %{
      name: :cancel_all_orders,
      method: :delete,
      path: "/v1/orders",
      auth: true,
      params: [:symbol]
    }
  ],
  error_codes: %{
    10_001 => :rate_limited,
    10_002 => :invalid_credentials,
    10_003 => :insufficient_balance,
    10_004 => :order_not_found,
    10_005 => :invalid_order,
    10_006 => :market_closed
  }
}
