# CCXT Client

Elixir client for 100+ cryptocurrency exchanges. This is a standalone package
generated from [ccxt_ex](https://github.com/ZenHive/ccxt_ex).

## Installation

```elixir
def deps do
  [
    {:ccxt_client, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
# Get ticker from any exchange
{:ok, ticker} = CCXT.Binance.fetch_ticker("BTC/USDT")
{:ok, ticker} = CCXT.Bybit.fetch_ticker("BTC/USDT")
{:ok, ticker} = CCXT.OKX.fetch_ticker("BTC/USDT")

# Authenticated requests
credentials = CCXT.Credentials.new(api_key: "...", secret: "...")
{:ok, balance} = CCXT.Binance.fetch_balance(credentials)
```

## Configuration

Configure the client via application config (:ccxt_client).

```elixir
config :ccxt_client,
  recv_window_ms: 10_000,
  request_timeout_ms: 60_000,
  rate_limit_cleanup_interval_ms: 120_000,
  rate_limit_max_age_ms: 120_000,
  retry_policy: :safe_transient,
  debug: false,
  broker_id: "MY_APP_BROKER"

config :ccxt_client, :circuit_breaker,
  enabled: true,
  max_failures: 5,
  window_ms: 10_000,
  reset_ms: 15_000
```

### Top-level keys
| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `recv_window_ms` | `pos_integer` | `5000` | Request timestamp validity window (rejects stale requests). |
| `request_timeout_ms` | `pos_integer` | `30000` | HTTP request timeout in milliseconds. |
| `extraction_timeout_ms` | `pos_integer` | `30000` | Per-exchange extraction timeout used by mix tasks. Notes: Only used by mix tasks, not runtime requests. |
| `rate_limit_cleanup_interval_ms` | `pos_integer` | `60000` | Interval for cleaning up old rate limit timestamps. |
| `rate_limit_max_age_ms` | `pos_integer` | `60000` | Maximum age for rate limit request timestamps. |
| `retry_policy` | `retry_policy` | `:safe_transient (test: false)` | Req retry policy for HTTP requests. Notes: In :test, default is false (no retries). |
| `debug` | `boolean` | `false` | Log exceptions with full stack traces. Notes: May log sensitive data; use only in development. |
| `broker_id` | `string` | `nil` | Optional broker identifier appended to requests. |

### Circuit breaker keys
| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | `boolean` | `true` | Enable or disable the circuit breaker. |
| `max_failures` | `pos_integer` | `5` | Failures before circuit opens (0 disables). |
| `window_ms` | `pos_integer` | `10000` | Time window for counting failures. |
| `reset_ms` | `pos_integer` | `15000` | Time before circuit resets (closes). |

### Machine-readable config spec
```json
[
  {
    "default": 5000,
    "type": "pos_integer",
    "path": [
      "recv_window_ms"
    ],
    "description": "Request timestamp validity window (rejects stale requests).",
    "key": "recv_window_ms",
    "examples": [
      "config :ccxt_client, recv_window_ms: 10_000"
    ]
  },
  {
    "default": 30000,
    "type": "pos_integer",
    "path": [
      "request_timeout_ms"
    ],
    "description": "HTTP request timeout in milliseconds.",
    "key": "request_timeout_ms",
    "examples": [
      "config :ccxt_client, request_timeout_ms: 60_000"
    ]
  },
  {
    "default": 30000,
    "type": "pos_integer",
    "path": [
      "extraction_timeout_ms"
    ],
    "description": "Per-exchange extraction timeout used by mix tasks.",
    "key": "extraction_timeout_ms",
    "examples": [
      "config :ccxt_client, extraction_timeout_ms: 60_000"
    ],
    "notes": [
      "Only used by mix tasks, not runtime requests."
    ]
  },
  {
    "default": 60000,
    "type": "pos_integer",
    "path": [
      "rate_limit_cleanup_interval_ms"
    ],
    "description": "Interval for cleaning up old rate limit timestamps.",
    "key": "rate_limit_cleanup_interval_ms",
    "examples": [
      "config :ccxt_client, rate_limit_cleanup_interval_ms: 120_000"
    ]
  },
  {
    "default": 60000,
    "type": "pos_integer",
    "path": [
      "rate_limit_max_age_ms"
    ],
    "description": "Maximum age for rate limit request timestamps.",
    "key": "rate_limit_max_age_ms",
    "examples": [
      "config :ccxt_client, rate_limit_max_age_ms: 120_000"
    ]
  },
  {
    "default": "safe_transient",
    "type": "retry_policy",
    "path": [
      "retry_policy"
    ],
    "description": "Req retry policy for HTTP requests.",
    "key": "retry_policy",
    "examples": [
      "config :ccxt_client, retry_policy: :safe_transient"
    ],
    "notes": [
      "In :test, default is false (no retries)."
    ],
    "default_test": false
  },
  {
    "default": false,
    "type": "boolean",
    "path": [
      "debug"
    ],
    "description": "Log exceptions with full stack traces.",
    "key": "debug",
    "examples": [
      "config :ccxt_client, debug: true"
    ],
    "notes": [
      "May log sensitive data; use only in development."
    ]
  },
  {
    "default": null,
    "type": "string",
    "path": [
      "broker_id"
    ],
    "description": "Optional broker identifier appended to requests.",
    "key": "broker_id",
    "examples": [
      "config :ccxt_client, broker_id: \"MY_APP_BROKER\""
    ]
  },
  {
    "default": true,
    "type": "boolean",
    "path": [
      "circuit_breaker",
      "enabled"
    ],
    "description": "Enable or disable the circuit breaker.",
    "key": "circuit_breaker",
    "examples": [
      "config :ccxt_client, :circuit_breaker, enabled: true"
    ]
  },
  {
    "default": 5,
    "type": "pos_integer",
    "path": [
      "circuit_breaker",
      "max_failures"
    ],
    "description": "Failures before circuit opens (0 disables).",
    "key": "circuit_breaker",
    "examples": [
      "config :ccxt_client, :circuit_breaker, max_failures: 5"
    ]
  },
  {
    "default": 10000,
    "type": "pos_integer",
    "path": [
      "circuit_breaker",
      "window_ms"
    ],
    "description": "Time window for counting failures.",
    "key": "circuit_breaker",
    "examples": [
      "config :ccxt_client, :circuit_breaker, window_ms: 10_000"
    ]
  },
  {
    "default": 15000,
    "type": "pos_integer",
    "path": [
      "circuit_breaker",
      "reset_ms"
    ],
    "description": "Time before circuit resets (closes).",
    "key": "circuit_breaker",
    "examples": [
      "config :ccxt_client, :circuit_breaker, reset_ms: 15_000"
    ]
  }
]
```


## Supported Exchanges

This package supports 100+ exchanges. See the `lib/ccxt/exchanges/` directory
for the full list.

## Generated Package

This package was generated using:

```bash
mix ccxt.sync --all --output ../ccxt_client
```

To regenerate with updated exchange specs, run the above command from the
ccxt_ex project directory.
