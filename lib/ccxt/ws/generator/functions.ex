defmodule CCXT.WS.Generator.Functions do
  @moduledoc """
  Generates WebSocket subscription functions at compile time.

  This module creates `watch_*_subscription/2` functions for each
  watch method defined in the exchange's WS spec.

  ## Generated Functions

  For each watch method in the spec, generates a subscription builder:

  - `watch_ticker_subscription/2` - Single symbol ticker
  - `watch_tickers_subscription/2` - Multiple symbols
  - `watch_order_book_subscription/3` - Order book with optional limit
  - `watch_ohlcv_subscription/3` - OHLCV with timeframe
  - `watch_balance_subscription/1` - Account balance (auth required)
  - etc.

  ## Return Format

  All generated functions return:

      {:ok, %{
        channel: String.t() | [String.t()],
        message: map(),
        method: atom(),
        auth_required: boolean()
      }}

  ## The `opts` Parameter

  All generated functions accept an `opts` keyword list as the last parameter.
  This is reserved for future extensibility (e.g., custom separators, market
  type hints, or authentication options). Currently unused but included for
  API stability.

  """

  # Credo: nested module references inside quote blocks are intentional -
  # they become part of the generated module code, not this module.
  # credo:disable-for-this-file Credo.Check.Design.AliasUsage

  require Logger

  # Watch methods that require authentication
  # Primary auth mechanism is per-channel extraction (Task 191).
  # This list is a defensive fallback for exchanges where extraction misses auth.
  @private_watch_methods ~w(
    watch_balance watch_orders watch_my_trades watch_positions
    watch_orders_for_symbols watch_my_trades_for_symbols
    watch_my_liquidations watch_my_liquidations_for_symbols
    watch_position_for_symbols watch_private_multiple
  )a

  # Parameter specifications for each watch method
  # Format: {[params], "doc_string"}
  @method_param_specs %{
    watch_balance: {[], ""},
    watch_heartbeat: {[], ""},
    watch_private: {[], ""},
    watch_public: {[], ""},
    watch_ticker: {[:symbol], "symbol"},
    watch_tickers: {[:symbols], "symbols"},
    watch_order_book: {[:symbol, :limit], "symbol, limit"},
    watch_order_book_snapshot: {[:symbol, :limit], "symbol, limit"},
    watch_order_book_for_symbols: {[:symbols], "symbols"},
    watch_trades: {[:symbol], "symbol"},
    watch_trades_for_symbols: {[:symbols], "symbols"},
    watch_ohlcv: {[:symbol, :timeframe], "symbol, timeframe"},
    watch_ohlcv_for_symbols: {[:symbols], "symbols"},
    watch_orders: {[:symbol], "symbol"},
    watch_orders_for_symbols: {[:symbols], "symbols"},
    watch_my_trades: {[:symbol], "symbol"},
    watch_my_trades_for_symbols: {[:symbols], "symbols"},
    watch_position_for_symbols: {[:symbols], "symbols"},
    watch_positions: {[:symbols], "symbols"},
    watch_bids_asks: {[:symbols], "symbols"},
    watch_liquidations: {[:symbol], "symbol"},
    watch_liquidations_for_symbols: {[:symbols], "symbols"},
    watch_my_liquidations: {[:symbol], "symbol"},
    watch_my_liquidations_for_symbols: {[:symbols], "symbols"},
    watch_funding_rate: {[:symbol], "symbol"},
    watch_funding_rates: {[:symbols], "symbols"},
    watch_mark_price: {[:symbol], "symbol"},
    watch_mark_prices: {[:symbols], "symbols"},
    watch_topics: {[:symbol], "symbol"},
    watch_multiple: {[], ""},
    watch_private_multiple: {[], ""},
    watch_public_multiple: {[], ""}
  }

  @doc """
  Generates module documentation for the WS module.

  Creates a comprehensive moduledoc including:
  - Exchange name and subscription pattern
  - Usage examples
  - Links to available methods
  """
  @spec generate_moduledoc(map()) :: String.t()
  def generate_moduledoc(spec) do
    # Use Map.get for struct access compatibility
    exchange_name = Map.get(spec, :name) || Map.get(spec, :id) || "Exchange"
    ws_config = Map.get(spec, :ws) || %{}
    pattern = Map.get(ws_config, :subscription_pattern) || :unknown

    """
    WebSocket subscription builders for #{exchange_name}.

    This module provides pure functions that build subscription messages
    for WebSocket channels. Use these with a WebSocket client (like ZenWebsocket)
    to subscribe to real-time data feeds.

    ## Subscription Pattern

    This exchange uses the `#{inspect(pattern)}` subscription pattern.

    ## Usage

        # Build a ticker subscription
        {:ok, sub} = #{exchange_name}.WS.watch_ticker_subscription("BTC/USDT")

        # sub contains:
        # %{
        #   channel: "...",           # Channel name for message routing
        #   message: %{...},          # JSON message to send
        #   method: :watch_ticker,    # Original method
        #   auth_required: false      # Whether credentials needed
        # }

        # Send via WebSocket client
        ZenWebsocket.Client.send_message(client, Jason.encode!(sub.message))

    ## Available Methods

    See `__ccxt_ws_channels__/0` for the list of available watch methods.
    """
  end

  @doc """
  Generates introspection functions for the WS module.
  """
  @spec generate_introspection(map()) :: Macro.t()
  def generate_introspection(ws_config) do
    pattern = ws_config[:subscription_pattern]
    channels = ws_config[:channel_templates] || %{}

    quote do
      @doc "Returns the WS spec configuration."
      @spec __ccxt_ws_spec__() :: map()
      def __ccxt_ws_spec__, do: @ws_spec

      @doc "Returns the subscription pattern atom."
      @spec __ccxt_ws_pattern__() :: atom()
      def __ccxt_ws_pattern__, do: unquote(pattern)

      @doc "Returns the channel templates map."
      @spec __ccxt_ws_channels__() :: map()
      def __ccxt_ws_channels__, do: unquote(Macro.escape(channels))
    end
  end

  @doc """
  Generates watch_*_subscription functions for all available watch methods.
  """
  @spec generate_watch_functions(map()) :: Macro.t()
  def generate_watch_functions(ws_config) do
    channel_templates = ws_config[:channel_templates] || %{}

    # Generate a function for each channel template
    functions =
      Enum.map(channel_templates, fn {method, template} ->
        generate_watch_function(method, template, ws_config)
      end)

    quote do
      (unquote_splicing(functions))
    end
  end

  @doc false
  # For dual-field patterns (Coinbase), injects the template's channel_name into
  # subscription_config so that subscribe/2 can populate the channels field.
  # No-op when channels_field is absent (most exchanges).
  @spec inject_channel_name(map(), map()) :: map()
  defp inject_channel_name(ws_config, template) do
    sub_config = ws_config[:subscription_config] || %{}
    channel_name = template[:channel_name]

    if sub_config[:channels_field] && channel_name do
      put_in(ws_config, [:subscription_config, :channel_name], channel_name)
    else
      ws_config
    end
  end

  @doc false
  # Generates a single watch_*_subscription function based on method type.
  # Dispatches to specialized generators (no-param, symbol, symbols, ohlcv, orderbook).
  # For URL-routed channels, generates functions that require URL parameter.
  # sobelow_skip ["DOS.BinToAtom"]
  @spec generate_watch_function(atom(), map(), map()) :: Macro.t()
  defp generate_watch_function(method, template, ws_config) do
    # Convert :watch_ticker to :watch_ticker_subscription
    # Safe: method comes from CCXT spec channel_templates, not user input
    func_name = :"#{method}_subscription"

    # Determine if auth is required (hardcoded private methods OR per-channel extraction)
    auth_required = method in @private_watch_methods or template[:auth_required] == true

    # Determine parameters based on method name
    {params, param_doc} = method_params(method)

    # For dual-field patterns (Coinbase): inject template's channel_name
    # into subscription_config so subscribe/2 can populate the channels field
    ws_config = inject_channel_name(ws_config, template)

    # Check if this is a URL-routed channel (Bybit-style)
    url_routed = template[:url_routed] == true

    # Generate function documentation
    doc =
      if url_routed do
        generate_url_routed_doc(method, param_doc, auth_required, template[:topic_dict])
      else
        generate_function_doc(method, param_doc, auth_required)
      end

    # Generate the function body
    if url_routed do
      # URL-routed channels need URL parameter to resolve topic
      generate_url_routed_function(func_name, method, template, ws_config, auth_required, doc, params)
    else
      case params do
        [] ->
          # No symbol parameter (e.g., watch_balance)
          generate_no_param_function(func_name, method, template, ws_config, auth_required, doc)

        [:symbol] ->
          # Single symbol parameter
          generate_symbol_function(func_name, method, template, ws_config, auth_required, doc)

        [:symbols] ->
          # Multiple symbols parameter
          generate_symbols_function(func_name, method, template, ws_config, auth_required, doc)

        [:symbol, :timeframe] ->
          # Symbol + timeframe (OHLCV)
          generate_ohlcv_function(func_name, method, template, ws_config, auth_required, doc)

        [:symbol, :limit] ->
          # Symbol + limit (orderbook)
          generate_orderbook_function(func_name, method, template, ws_config, auth_required, doc)
      end
    end
  end

  @doc false
  # Determines what parameters a watch method requires.
  # Uses @method_param_specs map lookup for reduced complexity.
  # Falls back to single symbol param for unknown methods with warning.
  @spec method_params(atom()) :: {[atom()], String.t()}
  defp method_params(method) do
    case Map.fetch(@method_param_specs, method) do
      {:ok, spec} ->
        spec

      :error ->
        Logger.warning("Unknown watch method #{inspect(method)}, defaulting to single symbol param")
        {[:symbol], "symbol"}
    end
  end

  @doc false
  # Builds the @doc string for a generated watch_*_subscription function.
  @spec generate_function_doc(atom(), String.t(), boolean()) :: String.t()
  defp generate_function_doc(method, param_doc, auth_required) do
    auth_note = if auth_required, do: "\n\n  Requires authentication.", else: ""
    params_note = if param_doc == "", do: "", else: "\n  - `#{param_doc}` - Trading pair or list"

    """
    Builds subscription for #{method |> Atom.to_string() |> String.replace("_", " ")}.
    #{params_note}
    - `opts` - Optional parameters#{auth_note}

    Returns `{:ok, %{channel: ..., message: ..., method: ..., auth_required: ...}}`
    """
  end

  @doc false
  # Builds the @doc string for URL-routed watch_*_subscription functions.
  # These require a URL parameter because the channel varies by connection type.
  @spec generate_url_routed_doc(atom(), String.t(), boolean(), map() | nil) :: String.t()
  defp generate_url_routed_doc(method, param_doc, auth_required, topic_dict) do
    auth_note = if auth_required, do: "\n\n  Requires authentication.", else: ""
    params_note = if param_doc == "", do: "", else: "\n  - `#{param_doc}` - Trading pair or list"

    topic_examples =
      if is_map(topic_dict) and map_size(topic_dict) > 0 do
        examples =
          Enum.map_join(topic_dict, "\n", fn {type, topic} -> "  - #{type} → #{inspect(topic)}" end)

        "\n\n  Channel varies by URL type:\n#{examples}"
      else
        ""
      end

    """
    Builds subscription for #{method |> Atom.to_string() |> String.replace("_", " ")}.

    **URL-routed channel** - requires WebSocket URL to determine the correct topic.
    #{params_note}
    - `url` - WebSocket URL (determines account type)
    - `opts` - Optional parameters#{topic_examples}#{auth_note}

    Returns `{:ok, %{channel: ..., message: ..., method: ..., auth_required: ...}}`
    or `{:error, reason}` if URL doesn't match any known pattern.
    """
  end

  @doc false
  # Generates a subscription function that takes no parameters (e.g., watch_balance).
  @spec generate_no_param_function(atom(), atom(), map(), map(), boolean(), String.t()) :: Macro.t()
  defp generate_no_param_function(func_name, method, template, ws_config, auth_required, doc) do
    quote do
      @doc unquote(doc)
      @spec unquote(func_name)(keyword()) ::
              {:ok, %{channel: String.t() | map(), message: map(), method: atom(), auth_required: boolean()}}
      def unquote(func_name)(opts \\ []) do
        template = unquote(Macro.escape(template))
        config = unquote(Macro.escape(ws_config))

        channel = CCXT.WS.Subscription.format_channel(template, %{}, config)
        message = CCXT.WS.Subscription.build_subscribe([channel], config)

        {:ok,
         %{
           channel: channel,
           message: message,
           method: unquote(method),
           auth_required: unquote(auth_required)
         }}
      end
    end
  end

  @doc false
  # Generates a subscription function that takes a single symbol parameter.
  @spec generate_symbol_function(atom(), atom(), map(), map(), boolean(), String.t()) :: Macro.t()
  defp generate_symbol_function(func_name, method, template, ws_config, auth_required, doc) do
    quote do
      @doc unquote(doc)
      @spec unquote(func_name)(String.t(), keyword()) ::
              {:ok, %{channel: String.t() | map(), message: map(), method: atom(), auth_required: boolean()}}
      def unquote(func_name)(symbol, opts \\ []) do
        template = unquote(Macro.escape(template))
        config = unquote(Macro.escape(ws_config))

        channel = CCXT.WS.Subscription.format_channel(template, %{symbol: symbol}, config)
        message = CCXT.WS.Subscription.build_subscribe([channel], config)

        {:ok,
         %{
           channel: channel,
           message: message,
           method: unquote(method),
           auth_required: unquote(auth_required)
         }}
      end
    end
  end

  @doc false
  # Generates a subscription function that takes multiple symbols parameter.
  @spec generate_symbols_function(atom(), atom(), map(), map(), boolean(), String.t()) :: Macro.t()
  defp generate_symbols_function(func_name, method, template, ws_config, auth_required, doc) do
    quote do
      @doc unquote(doc)
      @spec unquote(func_name)([String.t()], keyword()) ::
              {:ok, %{channel: [String.t() | map()], message: map(), method: atom(), auth_required: boolean()}}
      def unquote(func_name)(symbols, opts \\ []) when is_list(symbols) do
        template = unquote(Macro.escape(template))
        config = unquote(Macro.escape(ws_config))

        channels =
          Enum.map(symbols, fn symbol ->
            CCXT.WS.Subscription.format_channel(template, %{symbol: symbol}, config)
          end)

        message = CCXT.WS.Subscription.build_subscribe(channels, config)

        {:ok,
         %{
           channel: channels,
           message: message,
           method: unquote(method),
           auth_required: unquote(auth_required)
         }}
      end
    end
  end

  @doc false
  # Generates a subscription function that takes symbol and timeframe parameters.
  @spec generate_ohlcv_function(atom(), atom(), map(), map(), boolean(), String.t()) :: Macro.t()
  defp generate_ohlcv_function(func_name, method, template, ws_config, auth_required, doc) do
    quote do
      @doc unquote(doc)
      @spec unquote(func_name)(String.t(), String.t(), keyword()) ::
              {:ok, %{channel: String.t() | map(), message: map(), method: atom(), auth_required: boolean()}}
      def unquote(func_name)(symbol, timeframe \\ "1m", opts \\ []) do
        template = unquote(Macro.escape(template))
        config = unquote(Macro.escape(ws_config))

        channel =
          CCXT.WS.Subscription.format_channel(
            template,
            %{symbol: symbol, timeframe: timeframe},
            config
          )

        message = CCXT.WS.Subscription.build_subscribe([channel], config)

        {:ok,
         %{
           channel: channel,
           message: message,
           method: unquote(method),
           auth_required: unquote(auth_required)
         }}
      end
    end
  end

  @doc false
  # Generates a subscription function that takes symbol and limit parameters.
  @spec generate_orderbook_function(atom(), atom(), map(), map(), boolean(), String.t()) :: Macro.t()
  defp generate_orderbook_function(func_name, method, template, ws_config, auth_required, doc) do
    quote do
      @doc unquote(doc)
      @spec unquote(func_name)(String.t(), non_neg_integer() | nil, keyword()) ::
              {:ok, %{channel: String.t() | map(), message: map(), method: atom(), auth_required: boolean()}}
      def unquote(func_name)(symbol, limit \\ nil, opts \\ []) do
        template = unquote(Macro.escape(template))
        config = unquote(Macro.escape(ws_config))

        channel =
          CCXT.WS.Subscription.format_channel(
            template,
            %{symbol: symbol, limit: limit},
            config
          )

        message = CCXT.WS.Subscription.build_subscribe([channel], config)

        {:ok,
         %{
           channel: channel,
           message: message,
           method: unquote(method),
           auth_required: unquote(auth_required)
         }}
      end
    end
  end

  @doc false
  # Generates a subscription function for URL-routed channels.
  # These channels require the WebSocket URL to determine the correct topic.
  @spec generate_url_routed_function(atom(), atom(), map(), map(), boolean(), String.t(), [atom()]) ::
          Macro.t()
  defp generate_url_routed_function(func_name, method, template, ws_config, auth_required, doc, params) do
    url_patterns = template[:url_patterns] || []
    topic_dict = template[:topic_dict] || %{}

    case params do
      [] ->
        # No additional params (e.g., watch_balance)
        generate_url_routed_no_param(func_name, method, url_patterns, topic_dict, ws_config, auth_required, doc)

      [:symbol] ->
        # Single symbol parameter (e.g., watch_my_trades, watch_orders)
        generate_url_routed_symbol(func_name, method, url_patterns, topic_dict, ws_config, auth_required, doc)

      [:symbols] ->
        # Multiple symbols parameter (e.g., watch_positions)
        generate_url_routed_symbols(func_name, method, url_patterns, topic_dict, ws_config, auth_required, doc)

      _ ->
        # Default to no-param for unsupported combinations
        generate_url_routed_no_param(func_name, method, url_patterns, topic_dict, ws_config, auth_required, doc)
    end
  end

  @doc false
  # Generates URL-routed function with no additional parameters.
  @spec generate_url_routed_no_param(atom(), atom(), list(), map(), map(), boolean(), String.t()) ::
          Macro.t()
  defp generate_url_routed_no_param(func_name, method, url_patterns, topic_dict, ws_config, auth_required, doc) do
    quote do
      @doc unquote(doc)
      @spec unquote(func_name)(String.t(), keyword()) ::
              {:ok, %{channel: String.t() | [String.t()], message: map(), method: atom(), auth_required: boolean()}}
              | {:error, term()}
      def unquote(func_name)(url, opts \\ []) do
        url_patterns = unquote(Macro.escape(url_patterns))
        topic_dict = unquote(Macro.escape(topic_dict))
        config = unquote(Macro.escape(ws_config))

        case CCXT.WS.UrlRouting.resolve_topic(url, url_patterns, topic_dict) do
          {:ok, topic} ->
            channels = if is_list(topic), do: topic, else: [topic]
            message = CCXT.WS.Subscription.build_subscribe(channels, config)

            {:ok,
             %{
               channel: topic,
               message: message,
               method: unquote(method),
               auth_required: unquote(auth_required)
             }}

          {:error, _reason} = error ->
            error
        end
      end
    end
  end

  @doc false
  # Generates URL-routed function with single symbol parameter.
  @spec generate_url_routed_symbol(atom(), atom(), list(), map(), map(), boolean(), String.t()) ::
          Macro.t()
  defp generate_url_routed_symbol(func_name, method, url_patterns, topic_dict, ws_config, auth_required, doc) do
    quote do
      @doc unquote(doc)
      @spec unquote(func_name)(String.t(), String.t(), keyword()) ::
              {:ok, %{channel: String.t() | [String.t()], message: map(), method: atom(), auth_required: boolean()}}
              | {:error, term()}
      def unquote(func_name)(url, symbol, opts \\ []) do
        url_patterns = unquote(Macro.escape(url_patterns))
        topic_dict = unquote(Macro.escape(topic_dict))
        config = unquote(Macro.escape(ws_config))

        case CCXT.WS.UrlRouting.resolve_topic(url, url_patterns, topic_dict) do
          {:ok, topic} ->
            # For symbol-based subscriptions, the topic may need symbol interpolation
            channels = if is_list(topic), do: topic, else: [topic]
            message = CCXT.WS.Subscription.build_subscribe(channels, config)

            {:ok,
             %{
               channel: topic,
               message: message,
               method: unquote(method),
               auth_required: unquote(auth_required),
               symbol: symbol
             }}

          {:error, _reason} = error ->
            error
        end
      end
    end
  end

  @doc false
  # Generates URL-routed function with multiple symbols parameter.
  @spec generate_url_routed_symbols(atom(), atom(), list(), map(), map(), boolean(), String.t()) ::
          Macro.t()
  defp generate_url_routed_symbols(func_name, method, url_patterns, topic_dict, ws_config, auth_required, doc) do
    quote do
      @doc unquote(doc)
      @spec unquote(func_name)(String.t(), [String.t()], keyword()) ::
              {:ok, %{channel: String.t() | [String.t()], message: map(), method: atom(), auth_required: boolean()}}
              | {:error, term()}
      def unquote(func_name)(url, symbols, opts \\ []) when is_list(symbols) do
        url_patterns = unquote(Macro.escape(url_patterns))
        topic_dict = unquote(Macro.escape(topic_dict))
        config = unquote(Macro.escape(ws_config))

        case CCXT.WS.UrlRouting.resolve_topic(url, url_patterns, topic_dict) do
          {:ok, topic} ->
            channels = if is_list(topic), do: topic, else: [topic]
            message = CCXT.WS.Subscription.build_subscribe(channels, config)

            {:ok,
             %{
               channel: topic,
               message: message,
               method: unquote(method),
               auth_required: unquote(auth_required),
               symbols: symbols
             }}

          {:error, _reason} = error ->
            error
        end
      end
    end
  end
end
