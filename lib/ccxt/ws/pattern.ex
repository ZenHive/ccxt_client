defmodule CCXT.WS.Pattern do
  @moduledoc """
  Behaviour for WebSocket subscription patterns.

  Each pattern module implements the specific message format used by exchanges
  for subscribing/unsubscribing to channels. Patterns are detected by
  `CCXT.Extract.WsSubscriptionDetector` and dispatched through
  `CCXT.WS.Subscription`.

  ## Pattern Types

  | Pattern | Exchanges | Op Field | Args Field | Args Format |
  |---------|-----------|----------|------------|-------------|
  | `:op_subscribe` | Bybit, Bitmex | "op" | "args" | string_list |
  | `:op_subscribe_objects` | OKX | "op" | "args" | object_list |
  | `:method_subscribe` | Binance, XT | "method" | "params" | string_list |
  | `:type_subscribe` | KuCoin, Coinbase | "type" | "topic" | string |
  | `:jsonrpc_subscribe` | Deribit | "method" | "params.channels" | string_list |
  | `:event_subscribe` | Gate, Bitfinex, Woo | "event" | varies | object_list |
  | `:action_subscribe` | Alpaca, LBank | "action" | "params" | params_object |
  | `:method_params_subscribe` | Kraken, Crypto.com | "method" | "params" | params_object |
  | `:method_subscription` | Hyperliquid | "method" | "subscription" | params_object |
  | `:method_as_topic` | Coinex, Phemex | "method" | "params" | string_list |
  | `:method_topics` | Exmo | "method" | "topics" | string_list |
  | `:sub_subscribe` | HTX | "sub" | "sub" | string |
  | `:reqtype_sub` | BingX | "reqType" | "dataType" | string |
  | `:custom` | 7 unique | varies | varies | varies |

  ## Implementation

  Each pattern module must implement:

  - `subscribe/2` - Build subscribe message for channels
  - `unsubscribe/2` - Build unsubscribe message for channels
  - `format_channel/3` - Format channel name from template and params

  ## Example

      defmodule CCXT.WS.Patterns.OpSubscribe do
        @behaviour CCXT.WS.Pattern

        @impl true
        def subscribe(channels, config) do
          %{
            "op" => "subscribe",
            "args" => channels
          }
        end

        @impl true
        def unsubscribe(channels, config) do
          %{
            "op" => "unsubscribe",
            "args" => channels
          }
        end

        @impl true
        def format_channel(template, params, config) do
          separator = config[:separator] || "."
          channel = template.channel_name
          symbol = format_market_id(params[:symbol], config[:market_id_format])
          channel <> separator <> symbol
        end
      end

  """

  @typedoc "Subscription config from spec"
  @type config :: %{
          optional(:op_field) => String.t(),
          optional(:args_field) => String.t(),
          optional(:args_format) => :string_list | :object_list | :string | :params_object,
          optional(:separator) => String.t(),
          optional(:market_id_format) => :native | :lowercase | :uppercase
        }

  @typedoc "Channel template from spec"
  @type template :: %{
          optional(:channel_name) => String.t() | nil,
          optional(:separator) => String.t(),
          optional(:pattern) => atom(),
          optional(:market_id_format) => atom(),
          optional(:params) => [String.t()]
        }

  @typedoc "Parameters for channel formatting"
  @type params :: %{
          optional(:symbol) => String.t(),
          optional(:symbols) => [String.t()],
          optional(:timeframe) => String.t(),
          optional(:limit) => non_neg_integer()
        }

  @doc """
  Builds a subscribe message for the given channels.

  Returns a map that can be JSON-encoded and sent over the WebSocket.
  """
  @callback subscribe(channels :: [String.t()], config :: config()) :: map()

  @doc """
  Builds an unsubscribe message for the given channels.

  Returns a map that can be JSON-encoded and sent over the WebSocket.
  """
  @callback unsubscribe(channels :: [String.t()], config :: config()) :: map()

  @doc """
  Formats a channel name from a template and parameters.

  Takes a channel template (e.g., `%{channel_name: "tickers", separator: "."}`),
  parameters (e.g., `%{symbol: "BTC/USDT"}`), and config, then produces
  the formatted channel string (e.g., `"tickers.BTCUSDT"`).
  """
  @callback format_channel(template :: template(), params :: params(), config :: config()) ::
              String.t() | map()

  # ===========================================================================
  # Shared Helper Functions
  # ===========================================================================

  @doc """
  Formats a market ID according to the specified format.

  - `:native` - Use as-is (remove slashes for exchange format)
  - `:lowercase` - Convert to lowercase
  - `:uppercase` - Convert to uppercase

  ## Examples

      iex> CCXT.WS.Pattern.format_market_id("BTC/USDT", :native)
      "BTCUSDT"

      iex> CCXT.WS.Pattern.format_market_id("BTC/USDT", :lowercase)
      "btcusdt"

      iex> CCXT.WS.Pattern.format_market_id(nil, :native)
      ""

  """
  @spec format_market_id(String.t() | nil, atom() | nil) :: String.t()
  def format_market_id(nil, _format), do: ""

  def format_market_id(symbol, format) do
    # Remove slash for exchange format (BTC/USDT → BTCUSDT)
    base = String.replace(symbol, "/", "")

    case format do
      :lowercase -> String.downcase(base)
      :uppercase -> String.upcase(base)
      _ -> base
    end
  end

  @doc """
  Builds a channel string from parts, filtering empty values.

  Takes a list of parts, rejects empty strings, and joins with separator.
  This is a shared helper used by pattern modules to construct channel names.

  ## Examples

      iex> CCXT.WS.Pattern.build_channel(["ticker", "1h", "BTCUSDT"], ".")
      "ticker.1h.BTCUSDT"

      iex> CCXT.WS.Pattern.build_channel(["ticker", "", "BTCUSDT"], ".")
      "ticker.BTCUSDT"

  """
  @spec build_channel([String.t()], String.t()) :: String.t()
  def build_channel(parts, separator) when is_list(parts) do
    parts
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.join(separator)
  end

  @doc """
  Adds a part to a list if the value is not nil.

  Used by pattern modules to conditionally build channel parts.

  ## Examples

      iex> CCXT.WS.Pattern.maybe_add_part(["ticker"], "1h")
      ["ticker", "1h"]

      iex> CCXT.WS.Pattern.maybe_add_part(["ticker"], nil)
      ["ticker"]

  """
  @spec maybe_add_part([String.t()], term()) :: [String.t()]
  def maybe_add_part(parts, nil), do: parts
  def maybe_add_part(parts, value), do: parts ++ [value]

  @doc """
  Adds a transformed part to a list if the value is not nil.

  ## Examples

      iex> CCXT.WS.Pattern.maybe_add_part(["orderbook"], 25, &to_string/1)
      ["orderbook", "25"]

      iex> CCXT.WS.Pattern.maybe_add_part(["orderbook"], nil, &to_string/1)
      ["orderbook"]

  """
  @spec maybe_add_part([String.t()], term(), (term() -> String.t())) :: [String.t()]
  def maybe_add_part(parts, nil, _transform), do: parts
  def maybe_add_part(parts, value, transform), do: parts ++ [transform.(value)]

  @doc """
  Appends template default params (with non-nil defaults) to channel parts.

  Template params are extracted from CCXT watch methods (e.g., `interval` with
  default `"100ms"` for Deribit's `watchTicker`). Positional params like symbol,
  timeframe, and limit are already handled by the pattern module and are skipped.

  Runtime params can override defaults. Both atom and string keys are accepted.

  ## Examples

      iex> CCXT.WS.Pattern.apply_template_params(["ticker", "BTC-PERPETUAL"], [%{"default" => "100ms", "name" => "interval"}], %{})
      ["ticker", "BTC-PERPETUAL", "100ms"]

      iex> CCXT.WS.Pattern.apply_template_params(["ticker", "BTC-PERPETUAL"], [%{"default" => "100ms", "name" => "interval"}], %{"interval" => "raw"})
      ["ticker", "BTC-PERPETUAL", "raw"]

      iex> CCXT.WS.Pattern.apply_template_params(["ticker"], [], %{})
      ["ticker"]

  """
  @spec apply_template_params([String.t()], [map()], map()) :: [String.t()]
  def apply_template_params(parts, [], _runtime_params), do: parts

  def apply_template_params(parts, template_params, runtime_params) do
    string_params = stringify_keys(runtime_params)

    Enum.reduce(template_params, parts, fn param, acc ->
      resolve_template_param(acc, param, string_params)
    end)
  end

  @positional_params ~w(symbol timeframe limit)

  @doc false
  # Resolves a single template param — appends its value if it has a non-nil default
  # and is not a positional param (those are handled by format_channel directly)
  defp resolve_template_param(parts, %{"name" => name, "default" => default}, string_params)
       when default != nil and name not in @positional_params do
    value =
      case Map.fetch(string_params, name) do
        {:ok, v} -> v
        :error -> default
      end

    parts ++ [to_string(value)]
  end

  defp resolve_template_param(parts, _param, _string_params), do: parts

  @doc false
  # Normalizes map keys to strings — avoids atom conversion from untrusted input.
  # Non-atom/non-string keys (e.g. integers) are silently dropped.
  defp stringify_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {k, v}, acc when is_atom(k) -> Map.put(acc, Atom.to_string(k), v)
      {k, v}, acc when is_binary(k) -> Map.put(acc, k, v)
      _, acc -> acc
    end)
  end

  defp stringify_keys(_), do: %{}
end
