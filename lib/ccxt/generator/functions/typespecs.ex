defmodule CCXT.Generator.Functions.Typespecs do
  @moduledoc """
  Type specification generation for endpoint functions.

  Generates @spec AST for function signatures based on parameter types.
  Validates at compile time that all params in CCXT method signatures have types.
  """

  # Parameter name to type mapping for typespec generation
  # Types are represented as AST that will be injected into @spec
  @param_types %{
    # Symbol/market identifiers
    symbol: quote(do: String.t()),
    symbols: quote(do: [String.t()] | nil),
    # Pagination
    limit: quote(do: non_neg_integer() | nil),
    since: quote(do: non_neg_integer() | nil),
    # Order identifiers
    id: quote(do: String.t()),
    ids: quote(do: [String.t()]),
    order_id: quote(do: String.t()),
    clientOrderId: quote(do: String.t()),
    clientOrderIds: quote(do: [String.t()]),
    # Order parameters
    type: quote(do: atom()),
    side: quote(do: atom()),
    amount: quote(do: number()),
    price: quote(do: number() | nil),
    cost: quote(do: number()),
    orders: quote(do: [map()]),
    order: quote(do: map()),
    # Trigger/stop prices
    triggerPrice: quote(do: number()),
    stopLossPrice: quote(do: number()),
    takeProfitPrice: quote(do: number()),
    takeProfit: quote(do: number() | nil),
    stopLoss: quote(do: number() | nil),
    trailingPercent: quote(do: number()),
    trailingAmount: quote(do: number()),
    trailingTriggerPrice: quote(do: number() | nil),
    # Timeframes
    timeframe: quote(do: String.t()),
    interval: quote(do: String.t()),
    timeout: quote(do: non_neg_integer()),
    # Leverage/margin
    leverage: quote(do: number()),
    marginMode: quote(do: atom()),
    hedged: quote(do: boolean()),
    # Currency/account
    code: quote(do: String.t()),
    codes: quote(do: [String.t()]),
    currency: quote(do: String.t()),
    fromCode: quote(do: String.t()),
    toCode: quote(do: String.t()),
    fromAccount: quote(do: String.t()),
    toAccount: quote(do: String.t()),
    name: quote(do: String.t()),
    # Address/network
    network: quote(do: String.t() | nil),
    address: quote(do: String.t()),
    tag: quote(do: String.t() | nil),
    # Generic
    params: quote(do: map()),
    data: quote(do: term())
  }

  @type_union_delimiter "|"
  @generic_open "<"
  @generic_close ">"
  @array_open "["
  @array_close "]"
  @array_suffix "[]"
  @array_suffix_length String.length(@array_suffix)
  @param_separator ","
  @empty_string ""
  @depth_base 0
  @depth_step 1
  @one_char_length 1

  # TypeScript primitive types mapped to Elixir spec AST
  # Used by primitive_or_module_type/1 to reduce cyclomatic complexity
  @primitive_type_map %{
    "any" => quote(do: term()),
    "unknown" => quote(do: term()),
    "void" => quote(do: term()),
    "object" => quote(do: map()),
    "{}" => quote(do: map()),
    "string" => quote(do: String.t()),
    "Str" => quote(do: String.t()),
    "boolean" => quote(do: boolean()),
    "Bool" => quote(do: boolean()),
    "number" => quote(do: number()),
    "Num" => quote(do: number()),
    "Int" => quote(do: integer()),
    "Strings" => quote(do: [String.t()] | nil)
  }

  # Parameters that are optional and get default nil value.
  # Keep in sync with CCXT.Generator.Functions.Endpoints.
  @optional_params [:limit, :since, :until, :price, :code, :trigger_price, :stop_loss_price, :take_profit_price]

  # ===========================================================================
  # Compile-time validation against ccxt_method_signatures.json
  # ===========================================================================

  # Inline priv path resolution to avoid compile-time dependency on CCXT.Priv
  # (which would cause cascading recompilation of ~200 exchange modules)
  @signatures_path (case :code.priv_dir(:ccxt_client) do
                      {:error, :bad_name} ->
                        [__DIR__, "..", "..", "..", "priv", "extractor/ccxt_method_signatures.json"]
                        |> Path.join()
                        |> Path.expand()

                      priv when is_list(priv) ->
                        Path.join(List.to_string(priv), "extractor/ccxt_method_signatures.json")
                    end)

  # Internal CCXT methods whose params we don't need types for
  @internal_methods ~w(
    fetch fetch2 fetchWebEndpoint fetchPartialBalance fetchFreeBalance
    fetchTotalBalance fetchUsedBalance createSafeDictionary setHeaders
    setProxyAgents setMarketsFromExchange fetchPaginatedCallCursor
    fetchPaginatedCallDeterministic fetchPaginatedCallDynamic
    fetchPaginatedCallIncremental fetchRestOrderBookSafe createNetworksByIdObject
    createCcxtTradeId createOHLCVObject createExpiredOptionMarket
    setTakeProfitAndStopLossParams
  )

  if File.exists?(@signatures_path) do
    @external_resource @signatures_path

    # Single file read for both params validation and return types
    # Use stdlib JSON (Elixir 1.18+) at compile time to avoid Jason dependency ordering issues
    @signatures_data @signatures_path |> File.read!() |> JSON.decode!()

    # sobelow_skip ["DOS.StringToAtom"]
    @json_params @signatures_data
                 |> Map.get("methods", %{})
                 |> Enum.reject(fn {method, _} -> method in @internal_methods end)
                 |> Enum.flat_map(fn {_method, params} -> params end)
                 |> Enum.uniq()
                 |> Enum.map(&String.to_atom/1)

    @missing_params @json_params
                    |> Enum.reject(&Map.has_key?(@param_types, &1))
                    |> Enum.sort()

    if @missing_params != [] do
      require Logger

      Logger.info("""
      CCXT.Generator.Functions.Typespecs: Missing types for #{length(@missing_params)} params:
      #{inspect(@missing_params)}

      These params will use term() in typespecs. Consider adding them to @param_types.
      """)
    end

    @return_types Map.get(@signatures_data, "returns", %{})
  else
    @return_types %{}
  end

  @doc """
  Generate @spec typespec AST for an endpoint function.

  Returns just the function call signature AST (without @spec wrapper).
  The caller wraps this in `@spec ... :: return_type`.
  """
  @spec generate_typespec_signature(atom(), [atom()], boolean(), [atom()]) :: Macro.t()
  def generate_typespec_signature(name, params, auth, required_params) do
    # Build parameter types list
    param_types =
      if auth do
        # Private endpoint: credentials first
        [quote(do: CCXT.Credentials.t()) | Enum.map(params, &param_to_type(&1, required_params))]
      else
        Enum.map(params, &param_to_type(&1, required_params))
      end

    # Add opts :: keyword() at the end
    all_types = param_types ++ [quote(do: keyword())]

    # Build the spec call AST: name(type1, type2, ...)
    {name, [], all_types}
  end

  @doc """
  Returns the known parameter types map.

  Useful for introspection and debugging.
  """
  @spec param_types() :: map()
  def param_types, do: @param_types

  @doc """
  Returns the return type AST for a unified method.

  Defaults to `map()` when no return type is available.
  """
  @spec return_type_ast(atom()) :: Macro.t()
  def return_type_ast(name) do
    method_name = name |> Atom.to_string() |> camelize()

    case Map.get(@return_types, method_name) do
      nil -> quote(do: map())
      return_type -> ts_type_to_spec_ast(return_type)
    end
  end

  @doc """
  Returns the full ok/error return type for a unified method.
  """
  @spec ok_error_return_type_ast(atom()) :: Macro.t()
  def ok_error_return_type_ast(name) do
    ok_type = return_type_ast(name)
    quote(do: {:ok, unquote(ok_type)} | {:error, CCXT.Error.t()})
  end

  @doc false
  # Map parameter name to its type AST
  # Falls back to term() for unknown params (logged at compile time for debugging)
  @spec param_to_type(atom(), [atom()]) :: Macro.t()
  defp param_to_type(param, required_params) do
    case Map.fetch(@param_types, param) do
      {:ok, type_ast} ->
        maybe_nilable_type(type_ast, param, required_params)

      :error ->
        # Log at compile time for visibility, but don't warn (these are expected for new params)
        require Logger

        Logger.debug(
          "Unknown param type for #{inspect(param)}, using term(). " <>
            "Consider adding to @param_types in CCXT.Generator.Functions.Typespecs"
        )

        type_ast = quote(do: term())
        maybe_nilable_type(type_ast, param, required_params)
    end
  end

  defp maybe_nilable_type(type_ast, param, required_params) do
    if param in @optional_params and param not in required_params do
      if type_includes_nil?(type_ast) do
        type_ast
      else
        quote(do: unquote(type_ast) | nil)
      end
    else
      type_ast
    end
  end

  defp type_includes_nil?({:|, _, [left, right]}) do
    type_includes_nil?(left) or type_includes_nil?(right)
  end

  defp type_includes_nil?(nil), do: true
  defp type_includes_nil?(_other), do: false

  defp camelize(string) do
    string
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map_join(fn
      {word, @depth_base} -> word
      {word, _} -> String.capitalize(word)
    end)
  end

  defp ts_type_to_spec_ast(type) when is_list(type) do
    type
    |> Enum.map(&ts_type_to_spec_ast/1)
    |> unionize()
  end

  defp ts_type_to_spec_ast(type) when is_binary(type) do
    type
    |> normalize_ts_type()
    |> parse_ts_type()
  end

  defp ts_type_to_spec_ast(_type), do: quote(do: map())

  defp normalize_ts_type(type) do
    type
    |> String.trim()
    |> strip_wrapping_parentheses()
  end

  defp strip_wrapping_parentheses(<<"(", rest::binary>>) do
    if String.ends_with?(rest, ")") do
      rest |> String.slice(@depth_base, String.length(rest) - @one_char_length) |> String.trim()
    else
      "(" <> rest
    end
  end

  defp strip_wrapping_parentheses(type), do: type

  defp parse_ts_type(type) do
    case split_top_level(type, @type_union_delimiter) do
      [single] -> parse_ts_type_single(single)
      parts -> parts |> Enum.map(&parse_ts_type/1) |> unionize()
    end
  end

  defp parse_ts_type_single(type) do
    if String.ends_with?(type, @array_suffix) do
      parse_array_suffix_type(type)
    else
      parse_generic_or_primitive(type)
    end
  end

  defp parse_array_suffix_type(type) do
    inner_length = String.length(type) - @array_suffix_length
    inner = String.slice(type, @depth_base, inner_length)
    quote(do: [unquote(parse_ts_type(inner))])
  end

  defp parse_generic_or_primitive(type) do
    with :error <- try_parse_dictionary(type),
         :error <- try_parse_record(type),
         :error <- try_parse_array(type) do
      primitive_or_module_type(type)
    end
  end

  defp try_parse_dictionary(type) do
    case strip_generic(type, "Dictionary") do
      {:ok, inner} -> map_type_from_generic({:ok, inner})
      :error -> :error
    end
  end

  defp try_parse_record(type) do
    case strip_generic(type, "Record") do
      {:ok, inner} -> map_type_from_generic({:ok, inner})
      :error -> :error
    end
  end

  defp try_parse_array(type) do
    case strip_generic(type, "Array") do
      {:ok, inner} -> array_type_from_generic({:ok, inner})
      :error -> :error
    end
  end

  defp strip_generic(type, prefix) do
    prefix_with = prefix <> @generic_open

    if String.starts_with?(type, prefix_with) and String.ends_with?(type, @generic_close) do
      start_index = String.length(prefix_with)
      end_index = String.length(type) - @one_char_length
      length = end_index - start_index
      {:ok, String.slice(type, start_index, length)}
    else
      :error
    end
  end

  defp map_type_from_generic({:ok, inner}) do
    params = split_top_level(inner, @param_separator)

    case params do
      [value_type] ->
        key_type = quote(do: String.t())
        value_ast = parse_ts_type(value_type)
        quote(do: %{unquote(key_type) => unquote(value_ast)})

      [key_type, value_type] ->
        key_ast = key_type_to_spec_ast(key_type)
        value_ast = parse_ts_type(value_type)
        quote(do: %{unquote(key_ast) => unquote(value_ast)})

      _ ->
        quote(do: map())
    end
  end

  defp array_type_from_generic({:ok, inner}) do
    quote(do: [unquote(parse_ts_type(inner))])
  end

  defp primitive_or_module_type(type) do
    Map.get(@primitive_type_map, type) || module_type_ast(type)
  end

  defp module_type_ast(type_name) do
    module = Module.concat([CCXT.Types, type_name])
    quote(do: unquote(module).t())
  end

  defp key_type_to_spec_ast(type) do
    case normalize_ts_type(type) do
      "string" -> quote(do: String.t())
      "Str" -> quote(do: String.t())
      "number" -> quote(do: number())
      "Num" -> quote(do: number())
      "Int" -> quote(do: integer())
      _ -> quote(do: term())
    end
  end

  defp split_top_level(type, delimiter) do
    {parts, current, _depth} =
      type
      |> String.graphemes()
      |> Enum.reduce({[], @empty_string, @depth_base}, fn char, {parts, current, depth} ->
        cond do
          char in [@generic_open, @array_open] ->
            {parts, current <> char, depth + @depth_step}

          char in [@generic_close, @array_close] ->
            {parts, current <> char, depth - @depth_step}

          char == delimiter and depth == @depth_base ->
            {[String.trim(current) | parts], @empty_string, depth}

          true ->
            {parts, current <> char, depth}
        end
      end)

    parts
    |> Enum.reverse([String.trim(current)])
    |> Enum.reject(&(&1 == @empty_string))
  end

  defp unionize([]), do: quote(do: term())

  defp unionize([single]), do: single

  defp unionize([first | rest]) do
    Enum.reduce(rest, first, fn type_ast, acc ->
      quote(do: unquote(acc) | unquote(type_ast))
    end)
  end
end
