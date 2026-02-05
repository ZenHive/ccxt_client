defmodule CCXT.WS.UrlRouting do
  @moduledoc """
  URL-based account type detection for WebSocket channel selection.

  Some exchanges (notably Bybit) use different channel names depending on the
  WebSocket connection type. The connection URL indicates what type of account
  is being used (spot, unified, usdc, etc.), and each watch method may need
  a different topic/channel for each account type.

  ## URL Routing Types

  | Type | Exchange | Pattern |
  |------|----------|---------|
  | `:dictionary` | Bybit | URL → account type via getPrivateType() |
  | `:dictionary` | Gate | URL → market type via getMarketTypeByUrl() |
  | `:binary` | Binance | URL → spot/swap via isSpotUrl() |

  ## Usage

  For URL-routed channels, the subscription builder needs the WebSocket URL
  to determine which topic to subscribe to:

      # Get account type from URL
      account_type = UrlRouting.get_account_type(url, url_patterns)
      #=> "unified"

      # Look up topic for this method and account type
      topic = UrlRouting.get_topic(account_type, topic_dict)
      #=> "wallet"

  ## Example: Bybit watchBalance

  Bybit's watchBalance uses different topics based on connection type:
  - spot URL → "outboundAccountInfo"
  - unified URL → "wallet"
  - usdc URL → no topic (unsupported)

  The URL patterns and topic dictionaries are extracted from CCXT Pro and
  stored in the exchange spec.
  """

  @typedoc """
  URL pattern with account type mapping.

  - `pattern` - String to search for in URL (nil = default)
  - `account_type` - Account type string when pattern matches
  """
  @type url_pattern :: %{
          pattern: String.t() | nil,
          account_type: String.t()
        }

  @typedoc """
  Topic dictionary mapping account types to channel names.

  Keys are account type strings (e.g., "spot", "unified", "usdc").
  Values are topic strings or lists of topics.
  """
  @type topic_dict :: %{String.t() => String.t() | [String.t()]}

  @doc """
  Determines account type from URL using exchange's URL patterns.

  Checks each pattern against the URL in order. The first match wins.
  A pattern with `nil` acts as the default case.

  ## Examples

      iex> patterns = [
      ...>   %{pattern: "spot", account_type: "spot"},
      ...>   %{pattern: "v5/private", account_type: "unified"},
      ...>   %{pattern: nil, account_type: "usdc"}
      ...> ]
      iex> CCXT.WS.UrlRouting.get_account_type("wss://stream.bybit.com/v5/private", patterns)
      "unified"

      iex> patterns = [
      ...>   %{pattern: "spot", account_type: "spot"},
      ...>   %{pattern: nil, account_type: "usdc"}
      ...> ]
      iex> CCXT.WS.UrlRouting.get_account_type("wss://stream.bybit.com/contract", patterns)
      "usdc"

  """
  @spec get_account_type(String.t(), [url_pattern()]) :: String.t() | nil
  def get_account_type(url, patterns) when is_binary(url) and is_list(patterns) do
    find_matching_pattern(url, patterns)
  end

  @doc false
  # Recursively searches URL patterns for first match. Returns the account_type
  # of the first pattern whose string is found in the URL. A pattern with nil
  # acts as default (matches everything). Handles both atom-keyed and string-keyed
  # maps since JSON extraction produces string keys.
  @spec find_matching_pattern(String.t(), [url_pattern()]) :: String.t() | nil
  defp find_matching_pattern(_url, []), do: nil

  defp find_matching_pattern(_url, [%{pattern: nil, account_type: default} | _rest]) do
    # Default pattern (nil) matches everything
    default
  end

  defp find_matching_pattern(url, [%{pattern: pattern, account_type: type} | rest]) do
    if String.contains?(url, pattern) do
      type
    else
      find_matching_pattern(url, rest)
    end
  end

  # Handle string-keyed maps from JSON extraction
  defp find_matching_pattern(_url, [%{"pattern" => nil, "account_type" => default} | _rest]) do
    default
  end

  defp find_matching_pattern(url, [%{"pattern" => pattern, "account_type" => type} | rest]) do
    if String.contains?(url, pattern) do
      type
    else
      find_matching_pattern(url, rest)
    end
  end

  @doc """
  Gets topic from dictionary based on account type.

  Returns the topic(s) for a given account type, or nil if not found.

  ## Examples

      iex> topic_dict = %{"spot" => "outboundAccountInfo", "unified" => "wallet"}
      iex> CCXT.WS.UrlRouting.get_topic("spot", topic_dict)
      "outboundAccountInfo"

      iex> topic_dict = %{"spot" => ["order", "stopOrder"], "unified" => ["order"]}
      iex> CCXT.WS.UrlRouting.get_topic("spot", topic_dict)
      ["order", "stopOrder"]

      iex> topic_dict = %{"spot" => "ticker"}
      iex> CCXT.WS.UrlRouting.get_topic("usdc", topic_dict)
      nil

  """
  @spec get_topic(String.t(), topic_dict()) :: String.t() | [String.t()] | nil
  def get_topic(account_type, topic_dict) when is_binary(account_type) and is_map(topic_dict) do
    Map.get(topic_dict, account_type)
  end

  @doc """
  Resolves the channel/topic for a URL-routed method.

  Combines `get_account_type/2` and `get_topic/2` into a single function.
  Returns `{:ok, topic}` if found, or `{:error, reason}` if not.

  ## Examples

      iex> url_patterns = [
      ...>   %{pattern: "spot", account_type: "spot"},
      ...>   %{pattern: "v5/private", account_type: "unified"},
      ...>   %{pattern: nil, account_type: "usdc"}
      ...> ]
      iex> topic_dict = %{"spot" => "outboundAccountInfo", "unified" => "wallet"}
      iex> CCXT.WS.UrlRouting.resolve_topic("wss://stream.bybit.com/spot/v3/ws", url_patterns, topic_dict)
      {:ok, "outboundAccountInfo"}

      iex> url_patterns = [%{pattern: nil, account_type: "usdc"}]
      iex> topic_dict = %{"spot" => "ticker"}
      iex> CCXT.WS.UrlRouting.resolve_topic("wss://stream.bybit.com/usdc", url_patterns, topic_dict)
      {:error, {:no_topic_for_account_type, "usdc"}}

  """
  @spec resolve_topic(String.t(), [url_pattern()], topic_dict()) ::
          {:ok, String.t() | [String.t()]} | {:error, term()}
  def resolve_topic(url, url_patterns, topic_dict) do
    case get_account_type(url, url_patterns) do
      nil ->
        {:error, :no_matching_url_pattern}

      account_type ->
        case get_topic(account_type, topic_dict) do
          nil -> {:error, {:no_topic_for_account_type, account_type}}
          topic -> {:ok, topic}
        end
    end
  end
end
