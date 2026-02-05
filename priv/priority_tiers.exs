# Priority Tiers for Production Trading
#
# This file defines exchange priorities based on trading importance.
# This is ORTHOGONAL to CCXT classification (certified, pro, supported).
#
# CCXT classification = API capabilities (WebSocket, certification status)
# Priority tiers = Trading importance (volume, liquidity, opportunity)
#
# Source of truth: docs/exchange-priorities.md
#
# Usage:
#   mix ccxt.sync --tier1              # Priority Tier 1 only
#   mix ccxt.sync --tier2              # Priority Tier 2 only
#   mix ccxt.sync --tier1 --tier2      # Tiers 1 + 2 combined
#   mix ccxt.sync --dex                # DEX track only
#   mix test --only tier1              # Run tier1 tests
#   mix test --only dex                # Run DEX tests

%{
  # Tier 1: Must Have (80%+ of volume/opportunity)
  # Includes candidates under consideration
  tier1: ~w(binance bybit okx deribit coinbaseexchange),

  # Tier 2: Valuable (specific use cases)
  tier2: ~w(kraken kucoin gate htx bitmex),

  # Tier 3: Low Priority (explicitly deprioritized)
  tier3: ~w(bitget bingx bitmart coinex cryptocom mexc hashkey woo),

  # DEX Track (separate from CEX tiers - different infrastructure)
  dex: ~w(hyperliquid aster dydx paradex apex woofipro derive modetrade)
}

# Note: Exchanges not listed remain :unclassified
