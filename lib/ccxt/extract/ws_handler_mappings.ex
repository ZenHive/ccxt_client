defmodule CCXT.Extract.WsHandlerMappings do
  @moduledoc """
  Loads WS handler dispatch mappings extracted from CCXT Pro TypeScript files.

  Each exchange's `handleMessage()` method contains a Dict mapping channel names
  to handler functions. This module loads those mappings and provides query APIs
  that map handler names to W12 payload families.

  Data source: `priv/extractor/ccxt_ws_handler_mappings.json`.

  ## Data Flow

      extract-ws-handlers.cjs (static TS analysis)
        → ccxt_ws_handler_mappings.json
        → WsHandlerMappings.load/0
        → query APIs (channel_to_family, families_supported, etc.)
  """

  # Inline priv path resolution to avoid compile-time dependency on CCXT.Priv
  # (which would cause cascading recompilation of ~200 exchange modules)
  @json_path (case :code.priv_dir(:ccxt_client) do
                {:error, :bad_name} ->
                  [__DIR__, "..", "..", "priv", "extractor/ccxt_ws_handler_mappings.json"]
                  |> Path.join()
                  |> Path.expand()

                priv when is_list(priv) ->
                  Path.join(List.to_string(priv), "extractor/ccxt_ws_handler_mappings.json")
              end)

  # Handler method name → W12 family atom.
  # Non-family handlers (auth, pong, subscription management) map to nil.
  @handler_to_family %{
    # Ticker family
    "handleTicker" => :watch_ticker,
    "handleTickers" => :watch_ticker,
    "handleBidAsk" => :watch_ticker,
    "handleBidsAsks" => :watch_ticker,
    "handleMarkPrices" => :watch_ticker,
    "handleWsTickers" => :watch_ticker,
    "handleMarketData" => :watch_ticker,
    "handlePricePointUpdates" => :watch_ticker,
    # Trades family
    "handleTrades" => :watch_trades,
    "handleTrade" => :watch_trades,
    "handleTradesSnapshot" => :watch_trades,
    "handleMyTrade" => :watch_trades,
    "handleMyTrades" => :watch_trades,
    # Order book family
    "handleOrderBook" => :watch_order_book,
    "handleOrderBookUpdate" => :watch_order_book,
    "handleOrderBookSnapshot" => :watch_order_book,
    "handleOrderBookPartialSnapshot" => :watch_order_book,
    "handleL2Updates" => :watch_order_book,
    "handleChecksum" => :watch_order_book,
    # OHLCV family
    "handleOHLCV" => :watch_ohlcv,
    "handleOHLCV1m" => :watch_ohlcv,
    "handleOHLCV24" => :watch_ohlcv,
    "handleInitOHLCV" => :watch_ohlcv,
    "handleFetchOHLCV" => :watch_ohlcv,
    # Orders family (private)
    "handleOrders" => :watch_orders,
    "handleOrder" => :watch_orders,
    "handleOrderUpdate" => :watch_orders,
    "handleMyOrder" => :watch_orders,
    "handleSingleOrder" => :watch_orders,
    "handleMultipleOrders" => :watch_orders,
    "handleOrderRequest" => :watch_orders,
    # Balance family (private)
    "handleBalance" => :watch_balance,
    "handleAcountUpdate" => :watch_balance,
    "handleBalanceAndPosition" => :watch_balance,
    "handleBalanceSnapshot" => :watch_balance,
    "handleAccount" => :watch_balance,
    "handleAccountUpdate" => :watch_balance,
    "handleFetchBalance" => :watch_balance,
    # Positions family (private)
    "handlePositions" => :watch_positions,
    # Non-family handlers → nil (auth, subscription, system, etc.)
    "handleAuthenticate" => nil,
    "handleAuthenticationMessage" => nil,
    "handleAuth" => nil,
    "handlePong" => nil,
    "handlePing" => nil,
    "handleHeartbeat" => nil,
    "handleConnected" => nil,
    "handleSubscriptionStatus" => nil,
    "handleSubscribe" => nil,
    "handleSubscribed" => nil,
    "handleSubscription" => nil,
    "handleSubscriptions" => nil,
    "handleSubscriptionResponse" => nil,
    "handleUnSubscribe" => nil,
    "handleUnsubscribe" => nil,
    "handleUnsubscription" => nil,
    "handleUnSubscription" => nil,
    "handleUnsubscriptionStatus" => nil,
    "handleSystemStatus" => nil,
    "handleInfo" => nil,
    "handleSubject" => nil,
    "handleLiquidation" => nil,
    "handleFundingRate" => nil,
    "handleOrderWs" => nil,
    "handlePlaceOrders" => nil,
    "handleCancelOrder" => nil,
    "handleCancelAllOrders" => nil,
    "handleCreateEditOrder" => nil,
    "handleEventStreamTerminated" => nil,
    "handleTrading" => nil,
    "handleTradingFees" => nil,
    "handleTransaction" => nil,
    "handleDeposits" => nil,
    "handleWithdraw" => nil,
    "handleWithdraws" => nil,
    "handleWsPost" => nil,
    "handleMarkets" => nil,
    "handleFetchCurrencies" => nil,
    "handleErrorMessage" => nil,
    "safeValue" => nil,
    "apiKey" => nil,
    "nonce" => nil,
    "resolveData" => nil
  }

  @known_families [
    :watch_ticker,
    :watch_trades,
    :watch_order_book,
    :watch_ohlcv,
    :watch_orders,
    :watch_balance,
    :watch_positions
  ]

  @doc "Returns the JSON file path for WS handler mappings."
  @spec path() :: String.t()
  def path, do: @json_path

  @doc """
  Loads the WS handler mappings JSON with caching.

  Call `reload!/0` to force re-read.
  """
  @spec load() :: map()
  def load do
    case :persistent_term.get({__MODULE__, :data}, :missing) do
      :missing ->
        data = read_json!()
        :persistent_term.put({__MODULE__, :data}, data)
        data

      data ->
        data
    end
  end

  @doc "Reloads the WS handler mappings JSON (bypassing cache)."
  @spec reload!() :: map()
  def reload! do
    data = read_json!()
    :persistent_term.put({__MODULE__, :data}, data)
    data
  end

  @doc "Returns all exchange IDs with handler mappings."
  @spec exchanges() :: [String.t()]
  def exchanges do
    load()
    |> Map.get("exchanges", [])
    |> Enum.map(&Map.get(&1, "exchange"))
    |> Enum.sort()
  end

  @doc "Returns the full mapping data for a single exchange."
  @spec get(String.t()) :: map() | nil
  def get(exchange_id) do
    load()
    |> Map.get("exchanges", [])
    |> Enum.find(fn e -> Map.get(e, "exchange") == exchange_id end)
  end

  @doc "Returns the envelope pattern config for an exchange."
  @spec envelope_pattern(String.t()) :: map() | nil
  def envelope_pattern(exchange_id) do
    case get(exchange_id) do
      nil -> nil
      data -> Map.get(data, "envelope")
    end
  end

  @doc ~s{Returns the match_type for an exchange ("exact", "exact_then_substring", "split"), or nil if unknown.}
  @spec match_type(String.t()) :: String.t() | nil
  def match_type(exchange_id) do
    case get(exchange_id) do
      nil -> nil
      data -> Map.get(data, "match_type")
    end
  end

  @doc "Returns the raw handler entries list for an exchange, or [] if unknown."
  @spec handlers(String.t()) :: [map()]
  def handlers(exchange_id) do
    case get(exchange_id) do
      nil -> []
      data -> Map.get(data, "handlers", [])
    end
  end

  @doc """
  Resolves a channel name to a W12 family for a given exchange.

  Returns the family atom (e.g., `:watch_ticker`) or `nil` for non-family
  handlers (auth, pong, subscription management, etc.).
  """
  @spec channel_to_family(String.t(), String.t()) :: atom() | nil
  def channel_to_family(exchange_id, channel_name) do
    case get(exchange_id) do
      nil ->
        nil

      data ->
        handler = find_handler_for_channel(data, channel_name)
        if handler, do: handler_to_family(handler)
    end
  end

  @doc """
  Resolves a channel name with tri-state semantics.

  Unlike `channel_to_family/2`, this distinguishes between:
  - `{:family, atom()}` — Handler found, maps to a known family
  - `:system` — Handler found, but non-family (auth, pong, subscription)
  - `:not_found` — No handler matches this channel at all

  ## Examples

      iex> CCXT.Extract.WsHandlerMappings.resolve_channel("bybit", "orderbook")
      {:family, :watch_order_book}

      iex> CCXT.Extract.WsHandlerMappings.resolve_channel("bybit", "pong")
      :system

      iex> CCXT.Extract.WsHandlerMappings.resolve_channel("bybit", "totally_unknown")
      :not_found

  """
  @spec resolve_channel(String.t(), String.t()) :: {:family, atom()} | :system | :not_found
  def resolve_channel(exchange_id, channel_name) do
    case get(exchange_id) do
      nil ->
        :not_found

      data ->
        case find_handler_for_channel(data, channel_name) do
          nil -> :not_found
          handler -> resolve_handler(handler)
        end
    end
  end

  @doc false
  # Maps a handler name to {:family, atom} or :system
  defp resolve_handler(handler_name) do
    case handler_to_family(handler_name) do
      nil -> :system
      family -> {:family, family}
    end
  end

  @doc """
  Returns which W12 families an exchange has handlers for.

  Only includes families with actual handlers (excludes nil/non-family handlers).
  """
  @spec families_supported(String.t()) :: [atom()]
  def families_supported(exchange_id) do
    case get(exchange_id) do
      nil ->
        []

      data ->
        data
        |> Map.get("handlers", [])
        |> Enum.map(fn h -> handler_to_family(Map.get(h, "handler")) end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.sort()
    end
  end

  @doc """
  Returns all channel names that map to a specific family for an exchange.
  """
  @spec channels_for_family(String.t(), atom()) :: [String.t()]
  def channels_for_family(exchange_id, family) when family in @known_families do
    case get(exchange_id) do
      nil ->
        []

      data ->
        data
        |> Map.get("handlers", [])
        |> Enum.filter(fn h -> handler_to_family(Map.get(h, "handler")) == family end)
        |> Enum.map(&Map.get(&1, "channel"))
    end
  end

  @doc "Returns the known handler→family mapping table."
  @spec handler_family_map() :: %{String.t() => atom() | nil}
  def handler_family_map, do: @handler_to_family

  @doc "Returns the list of known W12 families."
  @spec known_families() :: [atom()]
  def known_families, do: @known_families

  @doc """
  Maps a handler method name to a W12 family atom.

  Returns nil for non-family handlers or unknown handlers.
  """
  @spec handler_to_family(String.t()) :: atom() | nil
  def handler_to_family(handler_name) do
    Map.get(@handler_to_family, handler_name)
  end

  # -- Private Helpers -------------------------------------------------------

  @doc false
  # Finds the handler method name for a channel in an exchange's data.
  # Respects the exchange's match_type to avoid false-positive substring matches.
  # Also handles per-handler prefix matching (e.g., OKX "candle" matches "candle1m").
  defp find_handler_for_channel(data, channel_name) do
    handlers = Map.get(data, "handlers", [])
    match_type = Map.get(data, "match_type", "exact")

    # Try exact match first (all match types start with exact)
    exact = Enum.find(handlers, fn h -> Map.get(h, "channel") == channel_name end)

    if exact do
      Map.get(exact, "handler")
    else
      # Try exchange-level fallback strategy
      result =
        case match_type do
          "exact_then_substring" ->
            find_by_substring(handlers, channel_name)

          "split" ->
            find_by_split(handlers, channel_name)

          _ ->
            nil
        end

      # If exchange-level fallback didn't match, try per-handler prefix entries
      result || find_by_prefix(handlers, channel_name)
    end
  end

  @doc false
  # Substring fallback: channel_name contains the handler's channel key
  defp find_by_substring(handlers, channel_name) do
    match =
      Enum.find(handlers, fn h ->
        channel = Map.get(h, "channel", "")
        channel != "" and String.contains?(channel_name, channel)
      end)

    if match, do: Map.get(match, "handler")
  end

  @doc false
  # Prefix fallback: matches handler entries tagged with match_type "prefix"
  # (e.g., OKX "candle" matches "candle1m", "candle5m", etc.)
  defp find_by_prefix(handlers, channel_name) do
    match =
      Enum.find(handlers, fn h ->
        Map.get(h, "match_type") == "prefix" and
          String.starts_with?(channel_name, Map.get(h, "channel", ""))
      end)

    if match, do: Map.get(match, "handler")
  end

  @doc false
  # Split fallback: split channel_name on "." and try each part
  defp find_by_split(handlers, channel_name) do
    parts = String.split(channel_name, ".")

    match =
      Enum.find_value(parts, fn part ->
        Enum.find(handlers, fn h -> Map.get(h, "channel") == part end)
      end)

    if match, do: Map.get(match, "handler")
  end

  @doc false
  # Reads and parses the handler mappings JSON file from disk
  defp read_json! do
    @json_path
    |> File.read!()
    |> Jason.decode!()
  end
end
