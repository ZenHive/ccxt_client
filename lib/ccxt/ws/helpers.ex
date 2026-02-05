defmodule CCXT.WS.Helpers do
  @moduledoc """
  Pure helper functions for WebSocket client integration.

  This module provides exchange-agnostic helpers for:
  - URL resolution from nested spec structures
  - ZenWebsocket configuration building
  - Subscription restore message building

  ## URL Resolution

  Exchange WS URLs can be simple strings or deeply nested maps:

      # Simple (OKX, Deribit)
      urls: "wss://ws.okx.com:8443/ws/v5/public"

      # Nested (Bybit)
      urls: %{
        "public" => %{
          "spot" => "wss://stream.bybit.com/v5/public/spot",
          "linear" => "wss://stream.bybit.com/v5/public/linear"
        },
        "private" => %{
          "contract" => "wss://stream.bybit.com/v5/private"
        }
      }

  The `resolve_url/3` function navigates this structure using a path:

      resolve_url(spec, [:public, :spot])
      #=> {:ok, "wss://stream.bybit.com/v5/public/spot"}

  ## Hostname Interpolation

  URLs may contain `{hostname}` placeholders that get replaced with
  the exchange's hostname from the spec:

      "wss://stream.{hostname}/v5/public/spot"
      #=> "wss://stream.bybit.com/v5/public/spot"

  """

  alias CCXT.WS.Subscription

  @type url_path :: atom() | String.t() | [atom() | String.t()]

  @doc """
  Resolves a WebSocket URL from the spec.

  Handles nested URL maps and hostname interpolation.

  ## Parameters

  - `spec` - Exchange specification (CCXT.Spec struct or map with :ws key)
  - `path` - URL path, can be:
    - `:test` - Returns first test URL found
    - `[:public, :spot]` - Nested path
    - `"public"` or `:public` - Single level
  - `opts` - Options:
    - `:sandbox` - If true, prefer test_urls over urls (default: false)

  ## Examples

      # Simple path
      iex> resolve_url(spec, :public)
      {:ok, "wss://ws.okx.com:8443/ws/v5/public"}

      # Nested path
      iex> resolve_url(spec, [:public, :spot])
      {:ok, "wss://stream.bybit.com/v5/public/spot"}

      # Sandbox mode
      iex> resolve_url(spec, [:public, :spot], sandbox: true)
      {:ok, "wss://stream-testnet.bybit.com/v5/public/spot"}

      # Not found
      iex> resolve_url(spec, [:public, :unknown])
      {:error, {:url_not_found, [:public, :unknown]}}

  """
  @spec resolve_url(map(), url_path(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def resolve_url(spec, path, opts \\ [])

  def resolve_url(%{ws: nil}, path, _opts) do
    {:error, {:no_ws_config, path}}
  end

  def resolve_url(%{ws: ws_config}, path, opts) do
    resolve_url_from_ws(ws_config, path, opts)
  end

  def resolve_url(ws_config, path, opts) when is_map(ws_config) do
    resolve_url_from_ws(ws_config, path, opts)
  end

  @doc false
  # Resolves URL from WS config map, handling sandbox mode and hostname interpolation
  @spec resolve_url_from_ws(map(), url_path(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defp resolve_url_from_ws(ws_config, path, opts) do
    sandbox = Keyword.get(opts, :sandbox, false)
    hostname = Map.get(ws_config, :hostname)

    # Choose URL source based on sandbox mode
    url_source =
      if sandbox do
        Map.get(ws_config, :test_urls) || Map.get(ws_config, :urls)
      else
        Map.get(ws_config, :urls)
      end

    case navigate_url_map(url_source, normalize_path(path)) do
      {:ok, url} when is_binary(url) ->
        {:ok, interpolate_hostname(url, hostname)}

      {:ok, nested} when is_map(nested) ->
        # Return first available URL from nested map
        case find_first_url(nested) do
          {:ok, url} -> {:ok, interpolate_hostname(url, hostname)}
          error -> error
        end

      {:error, _} = error ->
        error
    end
  end

  @doc false
  # Normalizes URL path to a list of strings for consistent map navigation
  @spec normalize_path(url_path()) :: [String.t()]
  defp normalize_path(path) when is_atom(path), do: [Atom.to_string(path)]
  defp normalize_path(path) when is_binary(path), do: [path]

  defp normalize_path(path) when is_list(path) do
    Enum.map(path, fn
      p when is_atom(p) -> Atom.to_string(p)
      p when is_binary(p) -> p
    end)
  end

  @doc false
  # Navigates nested URL map structure using path segments, supports both string and atom keys
  @spec navigate_url_map(term(), [String.t()]) :: {:ok, term()} | {:error, term()}
  defp navigate_url_map(url, []) when is_binary(url), do: {:ok, url}
  defp navigate_url_map(map, []) when is_map(map), do: {:ok, map}
  defp navigate_url_map(nil, path), do: {:error, {:url_not_found, path}}

  defp navigate_url_map(map, [key | rest]) when is_map(map) do
    # Try both string and atom keys
    value = Map.get(map, key) || Map.get(map, String.to_existing_atom(key))

    case value do
      nil -> {:error, {:url_not_found, [key | rest]}}
      found -> navigate_url_map(found, rest)
    end
  rescue
    ArgumentError ->
      # String.to_existing_atom failed - key doesn't exist as atom
      {:error, {:url_not_found, [key | rest]}}
  end

  defp navigate_url_map(url, _path) when is_binary(url) do
    # Already at a URL, ignore remaining path
    {:ok, url}
  end

  @doc false
  # Finds the first URL string in a potentially nested map structure
  @spec find_first_url(map()) :: {:ok, String.t()} | {:error, :no_url_found}
  defp find_first_url(map) when is_map(map) do
    result =
      Enum.find_value(map, fn
        {_key, url} when is_binary(url) -> url
        {_key, nested} when is_map(nested) -> find_first_url_value(nested)
        _ -> nil
      end)

    case result do
      nil -> {:error, :no_url_found}
      url -> {:ok, url}
    end
  end

  @doc false
  # Recursively searches for the first URL value in a nested map, returns nil if not found
  @spec find_first_url_value(map()) :: String.t() | nil
  defp find_first_url_value(map) do
    Enum.find_value(map, fn
      {_key, url} when is_binary(url) -> url
      {_key, nested} when is_map(nested) -> find_first_url_value(nested)
      _ -> nil
    end)
  end

  @doc false
  # Replaces {hostname} placeholder in URL with actual hostname value
  @spec interpolate_hostname(String.t(), String.t() | nil) :: String.t()
  defp interpolate_hostname(url, nil), do: url
  defp interpolate_hostname(url, hostname), do: String.replace(url, "{hostname}", hostname)

  @doc """
  Builds ZenWebsocket client configuration from spec.

  Extracts relevant settings from the exchange's WS config and converts
  them to ZenWebsocket options.

  ## Parameters

  - `spec` - Exchange specification
  - `opts` - Additional options to merge (override extracted settings)

  ## Options

  - `:heartbeat_type` - Override heartbeat type (`:ping`, `:deribit`, `:custom`)
  - `:timeout` - Connection timeout in ms (default: 5000)
  - `:handler` - Message handler function
  - `:debug` - Enable debug logging

  ## Examples

      iex> build_client_config(spec)
      [
        timeout: 5000,
        heartbeat_config: %{type: :ping, interval: 18000},
        reconnect_on_error: true
      ]

      iex> build_client_config(spec, timeout: 10_000, debug: true)
      [
        timeout: 10000,
        heartbeat_config: %{type: :ping, interval: 18000},
        reconnect_on_error: true,
        debug: true
      ]

  """
  @spec build_client_config(map(), keyword()) :: keyword()
  def build_client_config(spec, opts \\ [])

  def build_client_config(%{ws: nil}, opts) do
    default_config(opts)
  end

  def build_client_config(%{ws: ws_config}, opts) do
    build_config_from_ws(ws_config, opts)
  end

  def build_client_config(ws_config, opts) when is_map(ws_config) do
    build_config_from_ws(ws_config, opts)
  end

  @doc false
  # Builds ZenWebsocket config from WS config map, extracting heartbeat settings and merging user opts
  @spec build_config_from_ws(map(), keyword()) :: keyword()
  defp build_config_from_ws(ws_config, opts) do
    streaming = Map.get(ws_config, :streaming) || %{}
    keep_alive = Map.get(streaming, :keep_alive)

    # Build heartbeat config if keep_alive is specified
    heartbeat_config =
      if keep_alive do
        heartbeat_type = Keyword.get(opts, :heartbeat_type, :ping)
        %{type: heartbeat_type, interval: keep_alive}
      else
        :disabled
      end

    base_config = [
      timeout: Keyword.get(opts, :timeout, 5000),
      reconnect_on_error: Keyword.get(opts, :reconnect_on_error, true),
      restore_subscriptions: Keyword.get(opts, :restore_subscriptions, true)
    ]

    # Add heartbeat config if not disabled
    base_config =
      if heartbeat_config == :disabled do
        base_config
      else
        Keyword.put(base_config, :heartbeat_config, heartbeat_config)
      end

    # Merge with user-provided opts (user opts take precedence)
    # But filter out :heartbeat_type which is only used for building heartbeat_config
    user_opts = Keyword.delete(opts, :heartbeat_type)
    Keyword.merge(base_config, user_opts)
  end

  @doc false
  # Returns default ZenWebsocket config when no WS config is available in spec
  @spec default_config(keyword()) :: keyword()
  defp default_config(opts) do
    Keyword.merge(
      [timeout: Keyword.get(opts, :timeout, 5000), reconnect_on_error: Keyword.get(opts, :reconnect_on_error, true)],
      Keyword.delete(opts, :heartbeat_type)
    )
  end

  @doc """
  Builds a subscription restore message from active subscriptions.

  After reconnection, subscriptions need to be restored. This function
  builds the appropriate message based on the exchange's subscription pattern.

  ## Parameters

  - `spec` - Exchange specification
  - `subscriptions` - List of subscription maps from previous session

  ## Examples

      iex> subs = [
      ...>   %{channel: "tickers.BTCUSDT", message: %{...}},
      ...>   %{channel: "orderbook.50.BTCUSDT", message: %{...}}
      ...> ]
      iex> build_restore_message(spec, subs)
      {:ok, %{"op" => "subscribe", "args" => ["tickers.BTCUSDT", "orderbook.50.BTCUSDT"]}}

  """
  @spec build_restore_message(map(), [map()]) :: {:ok, map()} | {:error, term()} | nil
  def build_restore_message(_spec, []), do: nil
  def build_restore_message(%{ws: nil}, _subscriptions), do: nil

  def build_restore_message(%{ws: ws_config}, subscriptions) do
    build_restore_from_ws(ws_config, subscriptions)
  end

  def build_restore_message(ws_config, subscriptions) when is_map(ws_config) do
    build_restore_from_ws(ws_config, subscriptions)
  end

  @doc false
  # Extracts unique channels from subscriptions and builds a bulk subscribe message for restoration
  @spec build_restore_from_ws(map(), [map()]) :: {:ok, map()} | {:error, term()}
  defp build_restore_from_ws(ws_config, subscriptions) do
    # Extract channels from subscriptions
    channels =
      subscriptions
      |> Enum.flat_map(fn
        %{channel: channel} when is_binary(channel) -> [channel]
        %{channel: channels} when is_list(channels) -> channels
        _ -> []
      end)
      |> Enum.uniq()

    if Enum.empty?(channels) do
      nil
    else
      # Use the subscription module to build the message
      message = Subscription.build_subscribe(channels, ws_config)
      {:ok, message}
    end
  end

  @doc """
  Gets the subscription pattern from the spec.

  ## Examples

      iex> get_subscription_pattern(spec)
      :event_subscribe

  """
  @spec get_subscription_pattern(map()) :: atom() | nil
  def get_subscription_pattern(%{ws: nil}), do: nil
  def get_subscription_pattern(%{ws: %{subscription_pattern: pattern}}), do: pattern
  def get_subscription_pattern(%{subscription_pattern: pattern}), do: pattern
  def get_subscription_pattern(_), do: nil

  @doc """
  Gets the keep-alive interval from the spec in milliseconds.

  ## Examples

      iex> get_keep_alive_interval(spec)
      18000

  """
  @spec get_keep_alive_interval(map()) :: non_neg_integer() | nil
  def get_keep_alive_interval(%{ws: nil}), do: nil

  def get_keep_alive_interval(%{ws: %{streaming: %{keep_alive: interval}}}) when is_integer(interval), do: interval

  def get_keep_alive_interval(%{streaming: %{keep_alive: interval}}) when is_integer(interval), do: interval

  def get_keep_alive_interval(_), do: nil

  @doc """
  Checks if the spec has WebSocket support.

  ## Examples

      iex> has_ws_support?(spec)
      true

  """
  @spec has_ws_support?(map()) :: boolean()
  def has_ws_support?(%{ws: nil}), do: false
  def has_ws_support?(%{ws: ws}) when is_map(ws) and map_size(ws) > 0, do: true
  def has_ws_support?(_), do: false
end
