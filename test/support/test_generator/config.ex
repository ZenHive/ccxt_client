defmodule CCXT.Test.Generator.Config do
  @moduledoc """
  Compile-time configuration building for test generation.

  This module handles:
  - Loading exchange specs
  - Detecting credential options from spec
  - Determining which methods to test based on spec capabilities
  - Deriving test symbols from spec (avoiding hardcoded exchange-specific values)
  """

  alias CCXT.Exchange.Classification
  alias CCXT.Generator.Introspection
  alias CCXT.Spec

  # Spec directory paths
  @curated_specs_dir Path.join(["priv", "specs", "curated"])
  @extracted_specs_dir Path.join(["priv", "specs", "extracted"])

  # Default test symbol - CCXT unified format that works across exchanges
  # Individual exchanges normalize this to their format (BTCUSDT, BTC-USDT, etc.)
  @default_test_symbol %{symbol: "BTC/USDT", quote: "USDT"}

  # Public methods to test (method_name -> {arity, needs_symbol?})
  @public_methods %{
    fetch_ticker: {2, true},
    fetch_tickers: {2, false},
    fetch_order_book: {3, true},
    fetch_trades: {4, true},
    fetch_ohlcv: {5, true},
    fetch_markets: {1, false},
    fetch_currencies: {1, false}
  }

  # Private methods to test (method_name -> {arity, needs_symbol?, read_only?})
  @private_methods %{
    fetch_balance: {2, false, true},
    fetch_open_orders: {3, true, true},
    fetch_closed_orders: {5, true, true},
    fetch_my_trades: {4, true, true},
    fetch_order: {3, true, true},
    fetch_orders: {5, true, true},
    fetch_deposits: {5, false, true},
    fetch_withdrawals: {5, false, true},
    fetch_positions: {3, false, true},
    fetch_position: {3, true, true}
  }

  # Note: testnet_blacklist removed - per-endpoint sandbox URL routing now handles
  # multi-API exchanges (Binance, OKX, etc.) that have different testnets per API section.
  # Each endpoint routes to its correct sandbox URL based on api_section.

  @typedoc """
  Configuration map for test generation.

  Contains all information needed to generate exchange tests at compile time.
  """
  @type config :: %{
          exchange_id: String.t(),
          module_name: module(),
          credential_opts: keyword(),
          classification_tag: :certified_pro | :pro | :supported,
          priority_tier_tag: :tier1 | :tier2 | :tier3 | :dex | :unclassified,
          exchange_tag: atom(),
          signing_pattern: atom() | nil,
          endpoint_names: [atom()],
          test_symbol: String.t(),
          test_params: map(),
          symbol_formats: map() | nil,
          endpoints: [map()],
          endpoint_map: %{optional(atom()) => map()},
          endpoint_defaults: %{optional(atom()) => map()},
          public_methods: map(),
          private_methods: map(),
          has_passphrase: boolean(),
          default_timeframe: String.t() | nil,
          default_derivatives_category: String.t() | nil,
          default_account_type: String.t() | nil,
          default_settle_coin: String.t() | nil,
          uses_account_type_param: boolean(),
          test_currency: String.t()
        }

  @doc """
  Builds configuration at compile time from exchange ID and options.

  Returns a map with all config needed for test generation.
  """
  @spec build(atom(), keyword()) :: config()
  def build(exchange, opts) do
    exchange_id = to_string(exchange)
    spec = load_spec!(exchange_id)

    module_name = Keyword.get(opts, :module) || derive_module_name(exchange)
    credential_opts = detect_credential_opts(spec)
    signing_config = spec.signing
    signing_pattern = signing_config && Map.get(signing_config, :pattern)
    endpoint_names = spec.endpoints |> Enum.map(& &1.name) |> Enum.uniq()

    # Derive test symbol from spec instead of hardcoded map
    test_symbol_config = derive_test_symbol(spec)

    # Build sets of public and private endpoint names
    public_endpoint_names = build_endpoint_set(spec.endpoints, false)
    private_endpoint_names = build_endpoint_set(spec.endpoints, true)

    # Determine which methods to test based on spec capabilities
    # Task 109: Also consider market_type support via spec.features
    public_methods_to_test =
      filter_methods(@public_methods, spec.has, public_endpoint_names, spec.endpoints, spec.features)

    private_methods_to_test =
      filter_private_methods(
        @private_methods,
        spec.has,
        private_endpoint_names,
        spec.endpoints,
        spec.features,
        credential_opts
      )

    # Check if exchange requires passphrase
    has_passphrase = spec.signing && Map.get(spec.signing, :has_passphrase, false)

    # Get a valid timeframe from spec (extracted from CCXT)
    default_timeframe = derive_default_timeframe(spec.timeframes)

    # Derive test currency from spec options (for deposit/withdrawal tests)
    test_currency = derive_test_currency(spec)

    # Extract derivatives category, account type, and settle coin using introspection
    default_derivatives_category = Introspection.default_derivatives_category(spec)
    default_account_type = Introspection.default_account_type(spec)
    default_settle_coin = Introspection.default_settle_coin(spec)

    # API param requirements (auto-extracted from CCXT request_params)
    uses_account_type_param = Introspection.uses_account_type_param?(spec)

    # Build endpoint map for efficient lookup by name
    endpoint_map = Map.new(spec.endpoints, fn ep -> {ep.name, ep} end)

    # Extract default_params from each endpoint for explicit test param passing
    # Philosophy: Tests should be explicit about required params
    endpoint_defaults =
      for {name, endpoint} <- endpoint_map,
          defaults = endpoint[:default_params],
          defaults != nil and defaults != %{},
          into: %{} do
        {name, defaults}
      end

    %{
      exchange_id: exchange_id,
      module_name: module_name,
      credential_opts: credential_opts,
      classification_tag: spec.classification,
      priority_tier_tag: Classification.get_priority_tier(exchange_id),
      # Safe: exchange_id comes from trusted spec files (finite set of ~110 exchanges),
      # not user input. Atoms are created at compile time during test generation.
      exchange_tag: String.to_atom("exchange_#{exchange_id}"),
      signing_pattern: signing_pattern,
      endpoint_names: endpoint_names,
      test_symbol: test_symbol_config[:symbol],
      test_params: Map.get(test_symbol_config, :params, %{}),
      symbol_formats: spec.symbol_formats,
      endpoints: spec.endpoints,
      endpoint_map: endpoint_map,
      endpoint_defaults: endpoint_defaults,
      public_methods: public_methods_to_test,
      private_methods: private_methods_to_test,
      has_passphrase: has_passphrase,
      default_timeframe: default_timeframe,
      default_derivatives_category: default_derivatives_category,
      default_account_type: default_account_type,
      default_settle_coin: default_settle_coin,
      uses_account_type_param: uses_account_type_param,
      test_currency: test_currency
    }
  end

  @doc """
  Returns the map of all public methods that can be tested.
  """
  @spec public_methods() :: map()
  def public_methods, do: @public_methods

  @doc """
  Returns the map of all private methods that can be tested.
  """
  @spec private_methods() :: map()
  def private_methods, do: @private_methods

  @doc """
  Returns the appropriate test symbol for a specific endpoint based on its market_type.

  Uses the endpoint's market_type to look up the correct symbol format from symbol_formats.
  Falls back to the default test_symbol if no specific format is found.

  ## Examples

      iex> test_symbol_for_endpoint(config, :fetch_ticker)
      "BTC/USDT"

      iex> test_symbol_for_endpoint(config, :fetch_position)  # options endpoint
      "BTC-250103-100000-C"
  """
  @spec test_symbol_for_endpoint(config(), atom()) :: String.t()
  def test_symbol_for_endpoint(config, endpoint_name) do
    endpoint = Map.get(config.endpoint_map, endpoint_name)
    market_type = endpoint[:market_type] || :spot

    case config.symbol_formats do
      %{^market_type => %{sample: sample}} when is_binary(sample) -> sample
      _ -> config.test_symbol
    end
  end

  # Derive test symbol from spec
  # Prefers: spec.options.defaultSymbol > spec markets analysis > unified default
  # Normalizes symbol format based on market type (swap/future use concatenated format)
  @spec derive_test_symbol(Spec.t()) :: map()
  defp derive_test_symbol(spec) do
    cond do
      # Check if spec has a default symbol defined in options
      spec.options[:defaultSymbol] ->
        symbol = spec.options[:defaultSymbol]
        params = derive_params_from_options(spec)
        %{symbol: symbol, quote: derive_quote(symbol), params: params}

      # Check if spec has test configuration with symbol
      spec.options[:test] && spec.options[:test][:symbol] ->
        symbol = spec.options[:test][:symbol]
        params = derive_params_from_options(spec)
        %{symbol: symbol, quote: derive_quote(symbol), params: params}

      # Use unified default - normalize based on market type
      true ->
        params = derive_params_from_options(spec)
        symbol = derive_default_symbol(spec.options)
        %{symbol: symbol, quote: derive_quote(symbol), params: params}
    end
  end

  # Derive default symbol format based on market type
  # Perpetuals/futures use concatenated format (BTCUSDT), spot uses unified (BTC/USDT)
  @doc false
  @spec derive_default_symbol(map() | nil) :: String.t()
  defp derive_default_symbol(nil), do: @default_test_symbol[:symbol]

  defp derive_default_symbol(options) do
    case options[:default_type] do
      # Perpetuals/futures use concatenated symbol format
      type when type in ["swap", "future", "linear", "inverse"] -> "BTCUSDT"
      # Spot and others use unified format
      _ -> @default_test_symbol[:symbol]
    end
  end

  # Derive additional params from spec options.
  # Returns empty map - per-endpoint default_params[category] from spec handles category.
  # Previously this added a global category, but that overrode the correct per-endpoint defaults.
  @doc false
  @spec derive_params_from_options(Spec.t()) :: map()
  defp derive_params_from_options(_spec) do
    %{}
  end

  # Derives quote currency from symbol string.
  #
  # Handles various symbol formats:
  # - Unified: "BTC/USDT" -> "USDT"
  # - Dash-separated: "BTC-USDT" -> "USDT", "BTC-PERPETUAL" -> "USD"
  # - Underscore-separated: "BTC_USDT" -> "USDT"
  # - Concatenated: "BTCUSDT" -> "USDT"
  #
  # Falls back to "USDT" for malformed or unrecognized formats.
  @doc false
  @spec derive_quote(String.t()) :: String.t()
  defp derive_quote(symbol) do
    cond do
      String.contains?(symbol, "/") -> derive_quote_from_slash(symbol)
      String.contains?(symbol, "-") -> derive_quote_from_dash(symbol)
      String.contains?(symbol, "_") -> derive_quote_from_underscore(symbol)
      String.ends_with?(symbol, "USDT") -> "USDT"
      String.ends_with?(symbol, "USD") -> "USD"
      true -> "USDT"
    end
  end

  # Extract quote from slash-separated symbol (e.g., "BTC/USDT" -> "USDT")
  @spec derive_quote_from_slash(String.t()) :: String.t()
  defp derive_quote_from_slash(symbol) do
    case String.split(symbol, "/", parts: 2) do
      [_base, quote] when quote != "" -> quote
      _ -> "USDT"
    end
  end

  # Extract quote from dash-separated symbol (e.g., "BTC-USDT" -> "USDT", "BTC-PERPETUAL" -> "USD")
  @spec derive_quote_from_dash(String.t()) :: String.t()
  defp derive_quote_from_dash(symbol) do
    quote = symbol |> String.split("-") |> List.last()

    if quote in ["PERPETUAL", "PERP", "", nil], do: "USD", else: quote
  end

  # Extract quote from underscore-separated symbol (e.g., "BTC_USDT" -> "USDT")
  @spec derive_quote_from_underscore(String.t()) :: String.t()
  defp derive_quote_from_underscore(symbol) do
    case String.split(symbol, "_", parts: 2) do
      [_base, quote] when quote != "" -> quote
      _ -> "USDT"
    end
  end

  # Build set of endpoint names with specific auth requirement
  @spec build_endpoint_set(list(), boolean()) :: MapSet.t()
  defp build_endpoint_set(endpoints, auth_required) do
    endpoints
    |> Enum.filter(fn ep -> ep[:auth] == auth_required end)
    |> MapSet.new(fn ep -> ep[:name] end)
  end

  # Filter methods based on spec capabilities, endpoint availability, and market type support
  # Returns map of {method => {arity, needs_symbol, required_params}}
  # Task 109: Also filters out endpoints whose market_type isn't supported in features
  @spec filter_methods(map(), map(), MapSet.t(), list(), map() | nil) :: map()
  defp filter_methods(methods, has, endpoint_names, endpoints, features) do
    methods
    |> Enum.filter(fn {method, _} ->
      Map.get(has, method, false) &&
        MapSet.member?(endpoint_names, method) &&
        supports_market_type?(endpoints, method, features)
    end)
    |> Map.new(fn {method, {arity, needs_symbol}} ->
      required_params = get_required_params(endpoints, method)
      {method, {arity, needs_symbol, required_params}}
    end)
  end

  # Look up required_params from spec endpoints list
  @spec get_required_params(list(), atom()) :: [atom()]
  defp get_required_params(endpoints, method) do
    case Enum.find(endpoints, fn ep -> ep[:name] == method end) do
      %{required_params: params} when is_list(params) -> params
      _ -> []
    end
  end

  # Filter private methods and enrich with endpoint params from spec
  # Returns map of {method => {arity, needs_symbol, read_only, endpoint_params}}
  # Task 109: Also filters out endpoints whose market_type isn't supported in features
  # Note: testnet_blacklist removed - per-endpoint sandbox URL routing handles multi-API exchanges
  @spec filter_private_methods(map(), map(), MapSet.t(), list(), map() | nil, keyword()) :: map()
  defp filter_private_methods(methods, has, endpoint_names, endpoints, features, _credential_opts) do
    methods
    |> Enum.filter(fn {method, _} ->
      Map.get(has, method, false) &&
        MapSet.member?(endpoint_names, method) &&
        supports_market_type?(endpoints, method, features)
    end)
    |> Map.new(fn {method, {arity, needs_symbol, read_only}} ->
      endpoint_params = get_endpoint_params(endpoints, method)
      {method, {arity, needs_symbol, read_only, endpoint_params}}
    end)
  end

  # Task 109: Check if the endpoint's market_type is supported by the exchange's features
  # Returns true if:
  # - endpoint has no market_type (general endpoint)
  # - features is nil (no feature data, assume all supported)
  # - endpoint's market_type is present in features
  @spec supports_market_type?(list(), atom(), map() | nil) :: boolean()
  defp supports_market_type?(_endpoints, _method, nil), do: true

  defp supports_market_type?(endpoints, method, features) do
    case Enum.find(endpoints, fn ep -> ep[:name] == method end) do
      nil ->
        # Endpoint not found, let other filters handle it
        true

      endpoint ->
        market_type = endpoint[:market_type]

        # If endpoint has no market_type, it's a general endpoint (always supported)
        # If it has a market_type, check if that type is in features
        is_nil(market_type) or Map.has_key?(features, market_type)
    end
  end

  # Look up endpoint params from spec endpoints list
  @spec get_endpoint_params(list(), atom()) :: [atom()]
  defp get_endpoint_params(endpoints, method) do
    case Enum.find(endpoints, fn ep -> ep[:name] == method end) do
      %{params: params} when is_list(params) -> params
      _ -> []
    end
  end

  # Derive default timeframe from spec
  @spec derive_default_timeframe(map() | nil) :: String.t() | nil
  defp derive_default_timeframe(%{"1m" => value}), do: value

  defp derive_default_timeframe(timeframes) when is_map(timeframes) and map_size(timeframes) > 0 do
    timeframes |> Map.values() |> List.first()
  end

  defp derive_default_timeframe(_), do: nil

  # Derive test currency from spec options
  # Used for deposit/withdrawal tests that require a currency code
  @spec derive_test_currency(Spec.t()) :: String.t()
  defp derive_test_currency(spec) do
    cond do
      # Check spec.options.code (e.g., Deribit has code: "BTC")
      is_map(spec.options) && is_binary(spec.options[:code]) ->
        spec.options[:code]

      # Check spec.options["code"] (string key variant)
      is_map(spec.options) && is_binary(spec.options["code"]) ->
        spec.options["code"]

      # Default to BTC - most universally supported
      true ->
        "BTC"
    end
  end

  @spec load_spec!(String.t()) :: Spec.t()
  defp load_spec!(exchange_id) do
    curated_path = Path.join(@curated_specs_dir, "#{exchange_id}.exs")
    extracted_path = Path.join(@extracted_specs_dir, "#{exchange_id}.exs")

    cond do
      File.exists?(curated_path) ->
        Spec.load!(curated_path)

      File.exists?(extracted_path) ->
        Spec.load!(extracted_path)

      true ->
        raise ArgumentError,
              "No spec found for exchange #{exchange_id}. " <>
                "Run `mix ccxt.extract #{exchange_id}` first."
    end
  end

  @spec derive_module_name(atom()) :: module()
  defp derive_module_name(exchange) do
    exchange_name =
      exchange
      |> to_string()
      |> Macro.camelize()

    Module.concat([CCXT, exchange_name])
  end

  @spec detect_credential_opts(Spec.t()) :: keyword()
  defp detect_credential_opts(spec) do
    opts = []

    opts =
      if has_testnet?(spec) do
        Keyword.put(opts, :testnet, true)
      else
        opts
      end

    opts =
      if spec.signing && Map.get(spec.signing, :has_passphrase, false) do
        Keyword.put(opts, :passphrase, true)
      else
        opts
      end

    case credential_url(spec) do
      nil -> opts
      url -> Keyword.put(opts, :url, url)
    end
  end

  @spec has_testnet?(Spec.t()) :: boolean()
  defp has_testnet?(spec) do
    spec.urls[:sandbox] != nil
  end

  @spec credential_url(Spec.t()) :: String.t() | nil
  defp credential_url(spec) do
    cond do
      # Handle map-based sandbox URLs (multi-API exchanges)
      is_map(spec.urls[:sandbox]) ->
        # Pick first URL from the map for credential docs link
        spec.urls[:sandbox] |> Map.values() |> List.first()

      is_binary(spec.urls[:sandbox]) ->
        spec.urls[:sandbox]

      is_binary(spec.urls[:doc]) ->
        spec.urls[:doc]

      is_list(spec.urls[:doc]) ->
        List.first(spec.urls[:doc])

      true ->
        nil
    end
  end
end
