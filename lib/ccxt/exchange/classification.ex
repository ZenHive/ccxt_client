defmodule CCXT.Exchange.Classification do
  @moduledoc """
  Single source of truth for exchange classification based on CCXT metadata.

  ## Classification System

  CCXT uses two properties to classify exchanges:
  - `certified: true` - Exchange has paid for official CCXT integration (~22 exchanges)
  - `pro: true` - Exchange has WebSocket/Pro API support (~68 exchanges)

  We derive three mutually exclusive categories:

  | Category | CCXT Criteria | Description |
  |----------|---------------|-------------|
  | **Certified Pro** | `certified: true` AND `pro: true` | Premium exchanges with full support |
  | **Pro** | `pro: true` AND NOT `certified` | WebSocket support but not certified |
  | **Supported** | Neither `certified` nor `pro` | Basic REST-only support |

  ## Testnet Support (Orthogonal Property)

  Testnet/sandbox support is independent of classification:

      CCXT.Exchange.Classification.has_testnet?("binance")  # true
      CCXT.Exchange.Classification.has_testnet?("kraken")   # false

  An exchange in any category may or may not have testnet support.

  ## Data Source

  All data is auto-derived from `priv/extractor/ccxt_exchange_tiers.json`,
  which is generated during `mix ccxt.sync` from CCXT's `describe()` metadata.

  ## Usage

      # Get exchanges by classification
      CCXT.Exchange.Classification.certified_pro_exchanges()
      CCXT.Exchange.Classification.pro_exchanges()
      CCXT.Exchange.Classification.supported_exchanges()

      # Check individual exchange
      CCXT.Exchange.Classification.certified?("binance")
      CCXT.Exchange.Classification.pro?("binance")
      CCXT.Exchange.Classification.has_testnet?("binance")

      # Get exchanges suitable for integration testing
      CCXT.Exchange.Classification.certified_pro_with_testnet()

  ## Expected Counts (from CCXT)

  | Category | Count | Examples |
  |----------|-------|----------|
  | Certified Pro | ~22 | binance, bybit, okx, gate, kucoin, htx |
  | Pro (not certified) | ~46 | kraken, deribit, bitstamp, coinbaseexchange |
  | Supported | ~39 | bitfinex, bitflyer, etc. |
  | Has Testnet | ~45 | binance, bybit, bitmex, deribit |
  | **Total** | ~107 | |
  """

  # ===========================================================================
  # Compile-time data loading
  # ===========================================================================

  @classification_json_path "priv/extractor/ccxt_exchange_tiers.json"

  # Load exchange classification from JSON at compile time
  @external_resource @classification_json_path

  {all_exchanges, certified_exchanges, pro_exchanges, testnet_exchanges} =
    if File.exists?(@classification_json_path) do
      # Use stdlib JSON (Elixir 1.18+) at compile time to avoid Jason dependency ordering issues
      data = @classification_json_path |> File.read!() |> JSON.decode!()

      {
        Map.get(data, "all_exchanges", []),
        Map.get(data, "certified_exchanges", []),
        Map.get(data, "pro_exchanges", []),
        Map.get(data, "testnet_exchanges", Map.get(data, "sandbox_exchanges", []))
      }
    else
      # Fallback for fresh checkouts before first `mix ccxt.sync`
      {[], [], [], []}
    end

  @all_exchanges all_exchanges
  @certified_exchanges certified_exchanges
  @pro_exchanges pro_exchanges
  @testnet_exchanges testnet_exchanges

  # ===========================================================================
  # Derived classifications (computed at compile time)
  # ===========================================================================

  # Certified Pro: Both certified AND pro
  @certified_pro_exchanges Enum.filter(@certified_exchanges, &Enum.member?(@pro_exchanges, &1))

  # Pro only: Pro but NOT certified
  @pro_only_exchanges @pro_exchanges -- @certified_exchanges

  # Supported: Neither certified nor pro
  @supported_exchanges @all_exchanges -- @pro_exchanges

  # ===========================================================================
  # Certified Pro Functions
  # ===========================================================================

  @doc """
  Returns exchanges that are both CCXT certified AND have Pro support.

  These are premium exchanges with full official CCXT integration.

  ## Examples

      iex> "binance" in CCXT.Exchange.Classification.certified_pro_exchanges()
      true

      iex> "kraken" in CCXT.Exchange.Classification.certified_pro_exchanges()
      false

  """
  @spec certified_pro_exchanges() :: [String.t()]
  def certified_pro_exchanges, do: @certified_pro_exchanges

  @doc """
  Returns the count of Certified Pro exchanges.
  """
  @spec certified_pro_count() :: non_neg_integer()
  def certified_pro_count, do: length(@certified_pro_exchanges)

  @doc """
  Checks if an exchange is Certified Pro (both certified and pro).

  ## Examples

      iex> CCXT.Exchange.Classification.certified_pro?("binance")
      true

      iex> CCXT.Exchange.Classification.certified_pro?("kraken")
      false

  """
  @spec certified_pro?(String.t()) :: boolean()
  def certified_pro?(exchange_id) do
    Enum.member?(@certified_pro_exchanges, exchange_id)
  end

  @doc """
  Returns Certified Pro exchanges as atoms.
  """
  @spec certified_pro_atoms() :: [atom()]
  # sobelow_skip ["DOS.StringToAtom"]
  def certified_pro_atoms, do: Enum.map(@certified_pro_exchanges, &String.to_atom/1)

  # ===========================================================================
  # Pro Functions (pro but not certified)
  # ===========================================================================

  @doc """
  Returns exchanges with Pro support but NOT certified.

  These exchanges have WebSocket/streaming APIs but haven't paid for
  official CCXT certification.

  ## Examples

      iex> "kraken" in CCXT.Exchange.Classification.pro_exchanges()
      true

      iex> "binance" in CCXT.Exchange.Classification.pro_exchanges()
      false

  """
  @spec pro_exchanges() :: [String.t()]
  def pro_exchanges, do: @pro_only_exchanges

  @doc """
  Returns the count of Pro (non-certified) exchanges.
  """
  @spec pro_count() :: non_neg_integer()
  def pro_count, do: length(@pro_only_exchanges)

  @doc """
  Checks if an exchange is Pro but not certified.

  ## Examples

      iex> CCXT.Exchange.Classification.pro_only?("kraken")
      true

      iex> CCXT.Exchange.Classification.pro_only?("binance")
      false

  """
  @spec pro_only?(String.t()) :: boolean()
  def pro_only?(exchange_id) do
    Enum.member?(@pro_only_exchanges, exchange_id)
  end

  @doc """
  Returns Pro exchanges as atoms.
  """
  @spec pro_atoms() :: [atom()]
  # sobelow_skip ["DOS.StringToAtom"]
  def pro_atoms, do: Enum.map(@pro_only_exchanges, &String.to_atom/1)

  # ===========================================================================
  # Supported Functions (neither certified nor pro)
  # ===========================================================================

  @doc """
  Returns exchanges that are neither certified nor pro.

  These exchanges have basic REST-only support without WebSocket APIs.

  ## Examples

      iex> "bitfinex" in CCXT.Exchange.Classification.supported_exchanges()
      true

      iex> "binance" in CCXT.Exchange.Classification.supported_exchanges()
      false

  """
  @spec supported_exchanges() :: [String.t()]
  def supported_exchanges, do: @supported_exchanges

  @doc """
  Returns the count of Supported exchanges.
  """
  @spec supported_count() :: non_neg_integer()
  def supported_count, do: length(@supported_exchanges)

  @doc """
  Checks if an exchange is Supported (neither certified nor pro).

  ## Examples

      iex> CCXT.Exchange.Classification.supported?("bitfinex")
      true

      iex> CCXT.Exchange.Classification.supported?("binance")
      false

  """
  @spec supported?(String.t()) :: boolean()
  def supported?(exchange_id) do
    Enum.member?(@supported_exchanges, exchange_id)
  end

  @doc """
  Returns Supported exchanges as atoms.
  """
  @spec supported_atoms() :: [atom()]
  # sobelow_skip ["DOS.StringToAtom"]
  def supported_atoms, do: Enum.map(@supported_exchanges, &String.to_atom/1)

  # ===========================================================================
  # General Functions
  # ===========================================================================

  @doc """
  Returns the classification category for an exchange.

  ## Examples

      iex> CCXT.Exchange.Classification.get_classification("binance")
      :certified_pro

      iex> CCXT.Exchange.Classification.get_classification("kraken")
      :pro

      iex> CCXT.Exchange.Classification.get_classification("bitfinex")
      :supported

      iex> CCXT.Exchange.Classification.get_classification("unknown")
      :unknown

  """
  @spec get_classification(String.t()) :: :certified_pro | :pro | :supported | :unknown
  def get_classification(exchange_id) do
    cond do
      Enum.member?(@certified_pro_exchanges, exchange_id) -> :certified_pro
      Enum.member?(@pro_only_exchanges, exchange_id) -> :pro
      Enum.member?(@supported_exchanges, exchange_id) -> :supported
      true -> :unknown
    end
  end

  @doc """
  Returns all exchange IDs from CCXT.
  """
  @spec all_exchanges() :: [String.t()]
  def all_exchanges, do: @all_exchanges

  @doc """
  Returns the total count of all exchanges.
  """
  @spec all_count() :: non_neg_integer()
  def all_count, do: length(@all_exchanges)

  # ===========================================================================
  # Raw CCXT Property Functions
  # ===========================================================================

  @doc """
  Returns all exchanges with `certified: true` in CCXT.

  Note: Most certified exchanges are also pro. Use `certified_pro_exchanges/0`
  for the intersection, or this function if you need raw certified status.
  """
  @spec certified_exchanges() :: [String.t()]
  def certified_exchanges, do: @certified_exchanges

  @doc """
  Checks if an exchange has `certified: true` in CCXT.
  """
  @spec certified?(String.t()) :: boolean()
  def certified?(exchange_id) do
    Enum.member?(@certified_exchanges, exchange_id)
  end

  @doc """
  Returns all exchanges with `pro: true` in CCXT.

  Note: This includes both certified pro and pro-only exchanges.
  """
  @spec all_pro_exchanges() :: [String.t()]
  def all_pro_exchanges, do: @pro_exchanges

  @doc """
  Checks if an exchange has `pro: true` in CCXT.
  """
  @spec pro?(String.t()) :: boolean()
  def pro?(exchange_id) do
    Enum.member?(@pro_exchanges, exchange_id)
  end

  # ===========================================================================
  # Testnet Functions (Orthogonal Property)
  # ===========================================================================

  @doc """
  Returns all exchanges with testnet/sandbox support.

  This is orthogonal to the classification - exchanges in any category
  may or may not have testnet support.
  """
  @spec testnet_exchanges() :: [String.t()]
  def testnet_exchanges, do: @testnet_exchanges

  @doc """
  Returns the count of exchanges with testnet support.
  """
  @spec testnet_count() :: non_neg_integer()
  def testnet_count, do: length(@testnet_exchanges)

  @doc """
  Checks if an exchange has testnet/sandbox support.

  ## Examples

      iex> CCXT.Exchange.Classification.has_testnet?("binance")
      true

      iex> CCXT.Exchange.Classification.has_testnet?("kraken")
      false

  """
  @spec has_testnet?(String.t()) :: boolean()
  def has_testnet?(exchange_id) do
    Enum.member?(@testnet_exchanges, exchange_id)
  end

  @doc """
  Returns Certified Pro exchanges that have testnet support.

  These are the best candidates for integration testing.

  ## Examples

      iex> "binance" in CCXT.Exchange.Classification.certified_pro_with_testnet()
      true

  """
  @spec certified_pro_with_testnet() :: [String.t()]
  def certified_pro_with_testnet do
    Enum.filter(@certified_pro_exchanges, &has_testnet?/1)
  end

  @doc """
  Returns Pro exchanges that have testnet support.
  """
  @spec pro_with_testnet() :: [String.t()]
  def pro_with_testnet do
    Enum.filter(@pro_only_exchanges, &has_testnet?/1)
  end

  # ===========================================================================
  # Priority Tier Functions (Orthogonal to CCXT Classification)
  # ===========================================================================
  #
  # Priority tiers reflect trading importance (volume, liquidity, opportunity).
  # This is SEPARATE from CCXT classification which reflects API capabilities.
  #
  # Use cases:
  # - CCXT classification: "Does this exchange have WebSocket support?"
  # - Priority tiers: "Should I focus development effort on this exchange?"

  @priority_tiers_path "priv/priority_tiers.exs"

  @external_resource @priority_tiers_path

  {tier1_exchanges, tier2_exchanges, tier3_exchanges, dex_exchanges} =
    if File.exists?(@priority_tiers_path) do
      {data, _bindings} = Code.eval_file(@priority_tiers_path)

      {
        Map.get(data, :tier1, []),
        Map.get(data, :tier2, []),
        Map.get(data, :tier3, []),
        Map.get(data, :dex, [])
      }
    else
      # Fallback for fresh checkouts
      {[], [], [], []}
    end

  @tier1_exchanges tier1_exchanges
  @tier2_exchanges tier2_exchanges
  @tier3_exchanges tier3_exchanges
  @dex_exchanges dex_exchanges

  @doc """
  Returns Priority Tier 1 exchanges (must have, 80%+ of trading opportunity).

  These are the exchanges that matter most for real trading:
  binance, bybit, okx, deribit, coinbaseexchange

  ## Examples

      iex> "binance" in CCXT.Exchange.Classification.tier1_exchanges()
      true

      iex> "kraken" in CCXT.Exchange.Classification.tier1_exchanges()
      false

  """
  @spec tier1_exchanges() :: [String.t()]
  def tier1_exchanges, do: @tier1_exchanges

  @doc """
  Returns the count of Tier 1 exchanges.
  """
  @spec tier1_count() :: non_neg_integer()
  def tier1_count, do: length(@tier1_exchanges)

  @doc """
  Returns Priority Tier 2 exchanges (valuable, specific use cases).

  These exchanges have good volume for specific pairs/markets:
  kraken, kucoin, gate, htx, bitmex

  ## Examples

      iex> "kraken" in CCXT.Exchange.Classification.tier2_exchanges()
      true

      iex> "binance" in CCXT.Exchange.Classification.tier2_exchanges()
      false

  """
  @spec tier2_exchanges() :: [String.t()]
  def tier2_exchanges, do: @tier2_exchanges

  @doc """
  Returns the count of Tier 2 exchanges.
  """
  @spec tier2_count() :: non_neg_integer()
  def tier2_count, do: length(@tier2_exchanges)

  @doc """
  Returns Priority Tier 3 exchanges (low priority, explicitly deprioritized).

  These exchanges have issues that make them less suitable for serious trading:
  bitget, bingx, bitmart, coinex, cryptocom, mexc, hashkey, woo

  ## Examples

      iex> "bitget" in CCXT.Exchange.Classification.tier3_exchanges()
      true

      iex> "binance" in CCXT.Exchange.Classification.tier3_exchanges()
      false

  """
  @spec tier3_exchanges() :: [String.t()]
  def tier3_exchanges, do: @tier3_exchanges

  @doc """
  Returns the count of Tier 3 exchanges.
  """
  @spec tier3_count() :: non_neg_integer()
  def tier3_count, do: length(@tier3_exchanges)

  @doc """
  Returns DEX track exchanges (separate from CEX tiers).

  DEXes have different infrastructure (WebSocket-first, ECDSA signing)
  and are tracked separately from CEX priority tiers:
  hyperliquid, aster, dydx, paradex, apex, woofipro, derive, modetrade

  ## Examples

      iex> "hyperliquid" in CCXT.Exchange.Classification.dex_exchanges()
      true

      iex> "binance" in CCXT.Exchange.Classification.dex_exchanges()
      false

  """
  @spec dex_exchanges() :: [String.t()]
  def dex_exchanges, do: @dex_exchanges

  @doc """
  Returns the count of DEX exchanges.
  """
  @spec dex_count() :: non_neg_integer()
  def dex_count, do: length(@dex_exchanges)

  @doc """
  Returns the priority tier for an exchange.

  ## Examples

      iex> CCXT.Exchange.Classification.get_priority_tier("binance")
      :tier1

      iex> CCXT.Exchange.Classification.get_priority_tier("kraken")
      :tier2

      iex> CCXT.Exchange.Classification.get_priority_tier("bitget")
      :tier3

      iex> CCXT.Exchange.Classification.get_priority_tier("hyperliquid")
      :dex

      iex> CCXT.Exchange.Classification.get_priority_tier("unknown_exchange")
      :unclassified

  """
  @spec get_priority_tier(String.t()) :: :tier1 | :tier2 | :tier3 | :dex | :unclassified
  def get_priority_tier(exchange_id) do
    cond do
      exchange_id in @tier1_exchanges -> :tier1
      exchange_id in @tier2_exchanges -> :tier2
      exchange_id in @tier3_exchanges -> :tier3
      exchange_id in @dex_exchanges -> :dex
      true -> :unclassified
    end
  end

  @doc """
  Checks if an exchange is in Priority Tier 1.

  ## Examples

      iex> CCXT.Exchange.Classification.tier1?("binance")
      true

      iex> CCXT.Exchange.Classification.tier1?("kraken")
      false

  """
  @spec tier1?(String.t()) :: boolean()
  def tier1?(exchange_id), do: exchange_id in @tier1_exchanges

  @doc """
  Checks if an exchange is in Priority Tier 2.

  ## Examples

      iex> CCXT.Exchange.Classification.tier2?("kraken")
      true

      iex> CCXT.Exchange.Classification.tier2?("binance")
      false

  """
  @spec tier2?(String.t()) :: boolean()
  def tier2?(exchange_id), do: exchange_id in @tier2_exchanges

  @doc """
  Checks if an exchange is in Priority Tier 3.

  ## Examples

      iex> CCXT.Exchange.Classification.tier3?("bitget")
      true

      iex> CCXT.Exchange.Classification.tier3?("binance")
      false

  """
  @spec tier3?(String.t()) :: boolean()
  def tier3?(exchange_id), do: exchange_id in @tier3_exchanges

  @doc """
  Checks if an exchange is a DEX.

  ## Examples

      iex> CCXT.Exchange.Classification.dex?("hyperliquid")
      true

      iex> CCXT.Exchange.Classification.dex?("binance")
      false

  """
  @spec dex?(String.t()) :: boolean()
  def dex?(exchange_id), do: exchange_id in @dex_exchanges

  @doc """
  Returns Tier 1 exchanges that have testnet support.

  These are ideal for integration testing - high priority AND testable.
  """
  @spec tier1_with_testnet() :: [String.t()]
  def tier1_with_testnet do
    Enum.filter(@tier1_exchanges, &has_testnet?/1)
  end

  @doc """
  Returns Tier 1 exchanges that are also Certified Pro in CCXT.

  Intersection of priority (trading importance) and quality (API support).
  """
  @spec tier1_certified_pro() :: [String.t()]
  def tier1_certified_pro do
    Enum.filter(@tier1_exchanges, &certified_pro?/1)
  end

  # ===========================================================================
  # Tier Helper Functions (for Mix tasks)
  # ===========================================================================

  @doc """
  Returns exchanges for a given priority tier.

  ## Examples

      iex> "binance" in CCXT.Exchange.Classification.exchanges_for_tier(:tier1)
      true

      iex> "kraken" in CCXT.Exchange.Classification.exchanges_for_tier(:tier2)
      true

  """
  @spec exchanges_for_tier(:tier1 | :tier2 | :tier3 | :dex) :: [String.t()]
  def exchanges_for_tier(:tier1), do: @tier1_exchanges
  def exchanges_for_tier(:tier2), do: @tier2_exchanges
  def exchanges_for_tier(:tier3), do: @tier3_exchanges
  def exchanges_for_tier(:dex), do: @dex_exchanges

  @doc """
  Returns the display name for a priority tier (uppercase).

  ## Examples

      iex> CCXT.Exchange.Classification.tier_display_name(:tier1)
      "TIER 1"

      iex> CCXT.Exchange.Classification.tier_display_name(:dex)
      "DEX"

  """
  @spec tier_display_name(:tier1 | :tier2 | :tier3 | :dex) :: String.t()
  def tier_display_name(:tier1), do: "TIER 1"
  def tier_display_name(:tier2), do: "TIER 2"
  def tier_display_name(:tier3), do: "TIER 3"
  def tier_display_name(:dex), do: "DEX"

  @doc """
  Collects exchanges from multiple tier flags.

  Takes a keyword list of options and returns exchanges for all enabled tiers.

  ## Examples

      iex> opts = [tier1: true, tier2: true]
      iex> exchanges = CCXT.Exchange.Classification.collect_tier_exchanges(opts)
      iex> "binance" in exchanges
      true
      iex> "kraken" in exchanges
      true

  """
  @spec collect_tier_exchanges(keyword()) :: {[String.t()], String.t()}
  def collect_tier_exchanges(opts) do
    tiers =
      Enum.filter([:tier1, :tier2, :tier3, :dex], fn tier -> opts[tier] end)

    exchanges =
      tiers
      |> Enum.flat_map(&exchanges_for_tier/1)
      |> Enum.uniq()
      |> Enum.sort()

    label = build_tier_label(tiers, length(exchanges))
    {exchanges, label}
  end

  @doc """
  Checks if any tier flag is set in the options.

  ## Examples

      iex> CCXT.Exchange.Classification.has_tier_flags?(tier1: true)
      true

      iex> CCXT.Exchange.Classification.has_tier_flags?(all: true)
      false

  """
  @spec has_tier_flags?(keyword()) :: boolean()
  def has_tier_flags?(opts) do
    opts[:tier1] || opts[:tier2] || opts[:tier3] || opts[:dex] || false
  end

  @doc false
  @spec build_tier_label([atom()], non_neg_integer()) :: String.t()
  def build_tier_label(tiers, count) do
    tier_names = Enum.map_join(tiers, " + ", &tier_display_name/1)
    "#{tier_names} (#{count})"
  end
end
