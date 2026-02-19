defmodule CCXT.Test.WSChannelConfig do
  @moduledoc """
  Channel-specific overrides for WS integration tests.

  Some exchange testnets lack activity on certain channels (e.g., Binance
  spot testnet has no trades). This module routes those channel tests to
  alternative endpoints.

  Lives outside `test/ccxt/ws/integration/generated/` so it survives
  `mix ccxt.sync` regeneration.

  ## Override Keys

  - `:url_path` - URL path atoms (e.g., `[:future]`). Must exist in spec's `test_urls`.
  - `:symbol` - Override test symbol (e.g., `"BTC/USDT:USDT"` for futures).
  - `:timeout_ms` - Override message timeout in milliseconds.

  ## Discovering Available Paths

      spec = CCXT.Spec.load!("path/to/binance.exs")
      Map.keys(spec.ws.test_urls)
      #=> ["delivery", "future", "margin", "spot", "ws-api"]
  """

  @type override :: %{
          optional(:url_path) => [atom()],
          optional(:symbol) => String.t(),
          optional(:timeout_ms) => pos_integer()
        }

  # Binance spot testnet has no trade/orderbook activity — route to futures testnet.
  # Verified: [:future] → "wss://fstream.binancefuture.com/ws" (active)
  # Symbol "BTC/USDT" → "btcusdt@trade" works on both spot and futures.
  @overrides %{
    {"binance", :trades} => %{url_path: [:future]},
    {"binance", :orderbook} => %{url_path: [:future]}
  }

  @doc "Returns override for a specific exchange and channel, or nil."
  @spec get(String.t() | atom(), atom()) :: override() | nil
  def get(exchange_id, channel) when is_atom(exchange_id), do: get(Atom.to_string(exchange_id), channel)

  def get(exchange_id, channel) when is_binary(exchange_id), do: Map.get(@overrides, {exchange_id, channel})

  @doc "Returns all configured overrides."
  @spec all() :: map()
  def all, do: @overrides

  @doc "Returns url_path override or the given default."
  @spec resolve_url_path(String.t() | atom(), atom(), term()) :: term()
  def resolve_url_path(exchange_id, channel, default) do
    case get(exchange_id, channel) do
      %{url_path: path} when is_list(path) -> path
      _ -> default
    end
  end

  @doc "Returns symbol override or the given default."
  @spec resolve_symbol(String.t() | atom(), atom(), String.t()) :: String.t()
  def resolve_symbol(exchange_id, channel, default) do
    case get(exchange_id, channel) do
      %{symbol: s} when is_binary(s) -> s
      _ -> default
    end
  end

  @doc "Returns timeout_ms override or the given default."
  @spec resolve_timeout(String.t() | atom(), atom(), pos_integer()) :: pos_integer()
  def resolve_timeout(exchange_id, channel, default) do
    case get(exchange_id, channel) do
      %{timeout_ms: t} when is_integer(t) and t > 0 -> t
      _ -> default
    end
  end
end
