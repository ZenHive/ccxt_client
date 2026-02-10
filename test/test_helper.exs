require Logger

ExUnit.start()
ExUnit.configure(exclude: [:integration])

# =============================================================================
# Test Tags Reference
# =============================================================================
#
# This project uses ExUnit tags extensively for filtering tests. Use tags to
# run specific subsets of tests based on type, exchange, or feature.
#
# ## Running Tests with Tags
#
#     mix test --only <tag>           # Run only tests with this tag
#     mix test --exclude <tag>        # Run all tests except those with this tag
#     mix test --only tier1 --only tier2  # Combine tags (OR logic)
#
# ## IMPORTANT: --only vs --include Behavior
#
# These are NOT equivalent when `exclude: [:integration]` is configured:
#
#     --only integration     # Runs ONLY integration tests (~180 tests)
#                            # Sets: exclude: [:test], include: [integration: true]
#
#     --include integration  # Runs ALL tests (~2400+ tests)
#                            # Just overrides the exclude for :integration tag
#                            # Non-integration tests still run!
#
# The "excluded" count with --only is expected behavior (non-matching tests).
# The "invalid" count indicates actual problems (setup_all failures, etc).
#
# ## Test Type Tags
#
# | Tag              | Description                                    | Default |
# |------------------|------------------------------------------------|---------|
# | :integration     | Real API calls to testnets/sandboxes           | Excluded|
# | :unit            | Unit tests (no network calls)                  | Included|
# | :smoke           | REST smoke tests (quick validation)            | Included|
# | :ws_smoke        | WebSocket smoke tests                          | Included|
# | :ws_integration  | WebSocket integration tests                    | Excluded|
# | :introspection   | Module/spec verification tests                 | Included|
# | :ws_introspection| WS module verification tests                   | Excluded|
#
# ## Exchange & Priority Tags
#
# | Tag              | Description                                    |
# |------------------|------------------------------------------------|
# | :exchange_{id}   | Exchange-specific (e.g., :exchange_bybit)      |
# | :tier1           | Tier 1 exchanges (production-ready)            |
# | :tier2           | Tier 2 exchanges (integration-tested)          |
# | :tier3           | Tier 3 exchanges (compile-only)                |
# | :dex             | Decentralized exchanges                        |
# | :unclassified    | Not yet classified                             |
# | :certified_pro   | CCXT "Certified Pro" classification            |
# | :pro             | CCXT "Pro" classification                      |
# | :supported       | CCXT "Supported" classification                |
#
# ## Feature Tags (REST)
#
# | Tag              | Description                                    |
# |------------------|------------------------------------------------|
# | :public          | Public endpoint tests (no auth needed)         |
# | :authenticated   | Private endpoint tests (requires credentials)  |
# | :signing         | Signing verification tests (offline)           |
# | :passphrase      | Tests requiring passphrase credential          |
#
# ## WebSocket Feature Tags
#
# | Tag              | Description                                    |
# |------------------|------------------------------------------------|
# | :ws_public       | Public WS channels (ticker, orderbook, trades) |
# | :ws_private      | Private WS channels (balance, orders)          |
# | :ws_pattern      | WS subscription pattern tests                  |
# | :connection      | Connection management tests                    |
# | :ticker          | Ticker channel tests                           |
# | :orderbook       | Orderbook channel tests                        |
# | :trades          | Trades channel tests                           |
# | :balance         | Balance channel tests                          |
# | :orders          | Orders channel tests                           |
#
# ## Behavior Tags
#
# | Tag              | Description                                    |
# |------------------|------------------------------------------------|
# | :slow            | Slow-running tests                             |
# | :fast            | Fast tests                                     |
# | :skip            | Skipped tests                                  |
# | :regression      | Regression tests                               |
# | :generated       | Generated test code                            |
# | :nodejs          | Tests requiring Node.js                        |
# | :sanity          | Sanity check tests                             |
#
# ## Common Usage Patterns
#
#     # Run Tier 1 integration tests
#     mix test --only integration --only tier1
#
#     # Run public endpoint tests only
#     mix test --only public --exclude integration
#
#     # Run WS integration tests for a specific exchange
#     mix test --only ws_integration --only exchange_bybit
#
#     # Run all tests except slow ones
#     mix test --exclude slow
#
#     # Run signing tests (offline, no credentials needed)
#     mix test --only signing
#
#     # Run WS public channel tests (ticker, orderbook, trades)
#     mix test --only ws_integration --only ws_public
#
# =============================================================================

# =============================================================================
# Testnet Credential Registration
# =============================================================================
#
# Register credentials from environment variables ONCE at test startup.
# Generated tests use CCXT.Testnet.creds/2 to retrieve these credentials.
#
# This pattern ensures:
# - Credentials are loaded once, not N times per test
# - Missing credentials fail loudly with clear instructions
# - Tests can use setup_all for one-time credential check per module
#
# Multi-API exchanges (Binance, OKX) have different testnets per API section:
# - Spot: BINANCE_TESTNET_API_KEY
# - Futures: BINANCE_FUTURES_TESTNET_API_KEY
# Tests auto-skip when no credentials available for their sandbox.

# Exchange configurations: {exchange_atom, opts} or {exchange_atom, sandbox_key, opts}
# Options:
#   :testnet - Use EXCHANGE_TESTNET_* env vars (default: true for most)
#   :passphrase - Also load EXCHANGE_PASSPHRASE env var
#   :secret_suffix - Override secret env var suffix (default: "API_SECRET")
testnet_configs = [
  # Bybit (unified account, same credentials for all markets)
  {:bybit, testnet: true},

  # Binance - separate testnets for spot vs futures
  # BINANCE_TESTNET_API_KEY (spot)
  {:binance, :default, testnet: true},
  # BINANCE_FUTURES_TESTNET_API_KEY (USD-M futures)
  {:binance, :futures, testnet: true},
  # BINANCE_COINM_TESTNET_API_KEY (COIN-M futures)
  {:binance, :coinm, testnet: true},

  # OKX - unified demo trading account
  {:okx, testnet: true, passphrase: true},

  # Other exchanges
  {:kraken, testnet: true},
  {:krakenfutures, testnet: true},
  {:coinbaseexchange, testnet: true, passphrase: true},
  {:kucoin, testnet: true, passphrase: true},
  {:gate, testnet: true},
  {:htx, testnet: true},
  {:deribit, testnet: true, secret_suffix: "SECRET_KEY"},
  {:bitstamp, testnet: true}
]

# Register all exchanges and get list of successfully registered ones
registered = CCXT.Testnet.register_all_from_env(testnet_configs)

# Log which exchanges have credentials (helpful for debugging)
if registered != [] do
  count = length(registered)

  # Format as "exchange" or "exchange/sandbox_key" for non-default sandboxes
  exchanges_list =
    registered
    |> Enum.sort()
    |> Enum.map_join(", ", fn
      {exchange, :default} -> Atom.to_string(exchange)
      {exchange, sandbox_key} -> "#{exchange}/#{sandbox_key}"
    end)

  Logger.info("✓ #{count} testnet credential(s) registered: #{exchanges_list}")
end
