defmodule CCXT.Generator.Introspection do
  @moduledoc """
  Runtime introspection helpers for generated exchange modules.

  These functions provide detailed endpoint information and parameter hints
  to help users discover required parameters and exchange-specific settings.
  """

  alias CCXT.MethodCategories
  alias CCXT.Spec

  @doc """
  Returns detailed endpoint information with contextual hints.

  Looks up the endpoint by name and enriches it with hints about
  required parameters, account types, and other exchange-specific settings.
  """
  @spec endpoint_info(Spec.t(), atom()) :: map() | nil
  def endpoint_info(spec, name) do
    case find_endpoint(spec, name) do
      nil -> nil
      endpoint -> enrich_endpoint(endpoint, spec, name)
    end
  end

  @doc """
  Returns a list of required parameters beyond the function signature.

  For methods like fetch_balance on Bybit, this returns [:accountType]
  because Bybit's unified account system requires specifying the account type.
  """
  @spec required_params(Spec.t(), atom()) :: [atom()]
  def required_params(spec, name) do
    spec
    |> endpoint_info(name)
    |> get_in([:hints, :required_extra_params])
    |> case do
      nil -> []
      list -> list
    end
  end

  @doc """
  Returns the default account type for an exchange.

  For exchanges with unified account system (like Bybit), returns the value
  from accounts_by_type["unified"]. For other exchanges, uses the default_type
  option to look up the account type mapping. Returns nil if no account type
  is needed.

  ## Examples

      Introspection.default_account_type(bybit_spec)
      #=> "UNIFIED"

      Introspection.default_account_type(binance_spec)
      #=> nil
  """
  @spec default_account_type(Spec.t()) :: String.t() | nil
  def default_account_type(spec) do
    options = get_options(spec)
    accounts_by_type = Map.get(options, :accounts_by_type, %{})
    derive_default_account_type(options, accounts_by_type)
  end

  @doc """
  Returns the default derivatives category for an exchange.

  For derivatives endpoints (positions, funding rates, open interest),
  returns the default category (linear, inverse, or option).

  ## Examples

      Introspection.default_derivatives_category(bybit_spec)
      #=> "linear"
  """
  @spec default_derivatives_category(Spec.t()) :: String.t() | nil
  def default_derivatives_category(spec) do
    options = get_options(spec)
    options[:default_sub_type]
  end

  @doc """
  Returns the default settle coin for an exchange.

  For derivatives endpoints (positions), returns the default settlement
  currency (e.g., "USDT" for linear perpetuals).

  ## Examples

      Introspection.default_settle_coin(bybit_spec)
      #=> "USDT"
  """
  @spec default_settle_coin(Spec.t()) :: String.t() | nil
  def default_settle_coin(spec) do
    options = get_options(spec)
    options[:default_settle]
  end

  @doc """
  Returns whether the exchange uses category param in API requests.

  Some exchanges (Bybit, Bitget) require explicit category params (e.g., "linear",
  "spot") while others (Binance) route internally based on the endpoint.

  ## Examples

      Introspection.uses_category_param?(bybit_spec)
      #=> true

      Introspection.uses_category_param?(binance_spec)
      #=> false
  """
  @spec uses_category_param?(Spec.t()) :: boolean()
  def uses_category_param?(spec) do
    options = get_options(spec)
    options[:uses_category_param] == true
  end

  @doc """
  Returns whether the exchange uses accountType param in API requests.

  Some exchanges (Bybit, Bitget) require explicit accountType params while
  others (Binance) route internally based on the endpoint.

  ## Examples

      Introspection.uses_account_type_param?(bybit_spec)
      #=> true

      Introspection.uses_account_type_param?(binance_spec)
      #=> false
  """
  @spec uses_account_type_param?(Spec.t()) :: boolean()
  def uses_account_type_param?(spec) do
    options = get_options(spec)
    options[:uses_account_type_param] == true
  end

  @doc false
  # Extracts options from spec, defaulting to empty map if nil.
  # Uses pattern matching instead of || fallback.
  @spec get_options(Spec.t()) :: map()
  defp get_options(%Spec{options: nil}), do: %{}
  defp get_options(%Spec{options: options}), do: options

  @doc false
  # Finds endpoint by name in spec's endpoint list.
  defp find_endpoint(spec, name) do
    Enum.find(spec.endpoints, fn ep -> ep[:name] == name end)
  end

  @doc false
  # Enriches endpoint with contextual hints based on method type.
  defp enrich_endpoint(endpoint, spec, name) do
    hints = build_hints(spec, name)

    Map.put(endpoint, :hints, hints)
  end

  @doc false
  # Builds contextual hints for an endpoint based on method type and spec options.
  defp build_hints(spec, name) do
    hints = %{}
    options = get_options(spec)

    # Add account type hints for relevant methods
    hints =
      if name in MethodCategories.account_type_methods() do
        accounts_by_type = Map.get(options, :accounts_by_type, %{})
        default_account_type = derive_default_account_type(options, accounts_by_type)

        hints
        |> maybe_put(:account_types, accounts_by_type, map_size(accounts_by_type) > 0)
        |> maybe_put(:default_account_type, default_account_type, default_account_type != nil)
        |> maybe_put_required_extra_params(:accountType, default_account_type != nil)
      else
        hints
      end

    # Add derivatives category hints for relevant methods
    hints =
      if name in MethodCategories.derivatives_methods() do
        default_sub_type = options[:default_sub_type]

        hints
        |> maybe_put(:derivatives_category, default_sub_type, default_sub_type != nil)
        |> maybe_put_required_extra_params(:category, default_sub_type != nil)
      else
        hints
      end

    # Add param mappings if present
    hints =
      case spec.param_mappings do
        nil -> hints
        mappings when map_size(mappings) > 0 -> Map.put(hints, :param_mappings, mappings)
        _ -> hints
      end

    # Add timestamp resolution hints for OHLCV methods
    hints =
      if name in MethodCategories.ohlcv_methods() do
        resolution = spec.ohlcv_timestamp_resolution

        hints
        |> Map.put(:timestamp_resolution, resolution)
        |> Map.put(:timestamp_note, timestamp_resolution_note(resolution))
      else
        hints
      end

    # Task 108: Add feature limits and fee info
    hints
    |> add_feature_limits(spec, name)
    |> add_fee_info(spec, name)
  end

  @doc false
  # Returns a human-readable note about timestamp handling for OHLCV methods.
  defp timestamp_resolution_note(:milliseconds), do: "Pass timestamps in milliseconds (standard)"

  defp timestamp_resolution_note(:seconds),
    do: "Pass timestamps in milliseconds - library converts to seconds automatically"

  defp timestamp_resolution_note(:unknown), do: "Pass timestamps in milliseconds (resolution not detected)"

  @doc false
  # Adds feature limits to hints for methods that have them (e.g., fetchMyTrades.limit: 1000)
  # Task 108: Uses features data to enrich endpoint info
  defp add_feature_limits(hints, spec, name) do
    # Methods that commonly have feature limits
    feature_limit_methods = [
      :fetch_my_trades,
      :fetch_orders,
      :fetch_open_orders,
      :fetch_closed_orders,
      :create_orders,
      :cancel_orders,
      :fetch_ohlcv,
      :fetch_trades
    ]

    if name in feature_limit_methods and spec.features do
      limits = extract_feature_limits(spec.features, name)

      if map_size(limits) > 0 do
        Map.put(hints, :feature_limits, limits)
      else
        hints
      end
    else
      hints
    end
  end

  @doc false
  # Extracts feature limits for a method across all market types
  defp extract_feature_limits(features, method_name) do
    features
    |> Enum.filter(fn {_market_type, type_features} -> is_map(type_features) end)
    |> Enum.reduce(%{}, fn {market_type, type_features}, acc ->
      case Map.get(type_features, method_name) do
        %{} = method_features when map_size(method_features) > 0 ->
          # Found limits for this method (e.g., %{limit: 1000})
          Map.put(acc, market_type, method_features)

        limit when is_integer(limit) ->
          # Direct limit value
          Map.put(acc, market_type, %{limit: limit})

        _ ->
          acc
      end
    end)
  end

  @doc false
  # Adds fee info to hints for order-related endpoints
  # Task 108: Shows maker/taker fees for create_order and related methods
  defp add_fee_info(hints, spec, name) do
    order_methods = [
      :create_order,
      :create_orders,
      :edit_order,
      :create_market_order,
      :create_limit_order
    ]

    if name in order_methods and spec.fees do
      fee_info = build_fee_info(spec.fees)

      if map_size(fee_info) > 0 do
        Map.put(hints, :fee_info, fee_info)
      else
        hints
      end
    else
      hints
    end
  end

  @doc false
  # Builds fee info map from spec.fees
  defp build_fee_info(fees) do
    base_info = build_base_fee_info(fees[:trading])

    # Add market-type specific fees if different from base
    market_types = [:spot, :swap, :future, :option, :linear, :inverse]

    Enum.reduce(market_types, base_info, fn market_type, acc ->
      add_market_type_fee(acc, market_type, Map.get(fees, market_type))
    end)
  end

  @doc false
  # Builds base fee info from trading fees
  defp build_base_fee_info(nil), do: %{}

  defp build_base_fee_info(trading) do
    %{}
    |> maybe_put(:maker, trading[:maker], trading[:maker] != nil)
    |> maybe_put(:taker, trading[:taker], trading[:taker] != nil)
    |> maybe_put(:tier_based, trading[:tier_based], trading[:tier_based] != nil)
    |> maybe_put(:fee_side, trading[:fee_side], trading[:fee_side] != nil)
  end

  @doc false
  # Adds market-type specific fee to the accumulator
  defp add_market_type_fee(acc, _market_type, nil), do: acc

  defp add_market_type_fee(acc, market_type, %{trading: trading}) when is_map(trading) do
    type_fees = %{maker: trading[:maker], taker: trading[:taker]}
    Map.put(acc, market_type, type_fees)
  end

  defp add_market_type_fee(acc, market_type, type_fees) when is_map(type_fees) do
    if type_fees[:maker] || type_fees[:taker] do
      Map.put(acc, market_type, %{maker: type_fees[:maker], taker: type_fees[:taker]})
    else
      acc
    end
  end

  defp add_market_type_fee(acc, _market_type, _), do: acc

  @doc false
  # Derives the account type value from spec options.
  # Uses the pre-computed default_account_type key to look up in accounts_by_type.
  defp derive_default_account_type(options, accounts_by_type) do
    case options[:default_account_type] do
      nil -> nil
      key -> Map.get(accounts_by_type, key)
    end
  end

  @doc false
  # Conditionally adds key/value to map when condition is true.
  @spec maybe_put(map(), atom(), term(), boolean()) :: map()
  defp maybe_put(map, _key, _value, false), do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)

  @doc false
  # Appends param to :required_extra_params list if not already present.
  defp maybe_put_required_extra_params(hints, _param, false), do: hints

  defp maybe_put_required_extra_params(hints, param, true) do
    existing = Map.get(hints, :required_extra_params, [])

    if param in existing do
      hints
    else
      Map.put(hints, :required_extra_params, existing ++ [param])
    end
  end
end
