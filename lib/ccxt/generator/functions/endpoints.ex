defmodule CCXT.Generator.Functions.Endpoints do
  @moduledoc """
  Endpoint function generation for exchange modules.

  Generates the AST for public and private endpoint functions,
  including argument handling, path interpolation, and client calls.
  """

  alias CCXT.Generator.Functions.Docs
  alias CCXT.Generator.Functions.Typespecs
  alias CCXT.Spec

  # Parameters that are optional and get default nil value
  # These are commonly optional across CCXT's unified API methods:
  # - limit: pagination limit (fetchOrders, fetchOHLCV, etc.)
  # - since: start timestamp for historical data (fetchOrders, fetchOHLCV, etc.)
  # - until: end timestamp for historical data
  # - price: for market orders (createOrder)
  # - code: currency code (fetchBalance when fetching specific currency)
  # - trigger_price: for conditional orders
  # - stop_loss_price: for orders with stop loss
  # - take_profit_price: for orders with take profit
  @optional_params [:limit, :since, :until, :price, :code, :trigger_price, :stop_loss_price, :take_profit_price]

  # Inline priv path resolution to avoid compile-time dependency on CCXT.Priv
  # (which would cause cascading recompilation of ~200 exchange modules)
  # Method signatures loaded at compile time for generating extraction failure stubs
  # Use stdlib JSON (Elixir 1.18+) at compile time to avoid Jason dependency ordering issues
  @method_signatures_path (case :code.priv_dir(:ccxt_client) do
                             {:error, :bad_name} ->
                               [__DIR__, "..", "..", "..", "priv", "extractor/ccxt_method_signatures.json"]
                               |> Path.join()
                               |> Path.expand()

                             priv when is_list(priv) ->
                               Path.join(List.to_string(priv), "extractor/ccxt_method_signatures.json")
                           end)
  @external_resource @method_signatures_path
  @method_signatures (case File.read(@method_signatures_path) do
                        {:ok, content} ->
                          case JSON.decode(content) do
                            {:ok, %{"methods" => methods}} ->
                              methods

                            {:error, reason} ->
                              IO.warn(
                                "Failed to parse method signatures from #{@method_signatures_path}: #{inspect(reason)}"
                              )

                              %{}
                          end

                        {:error, reason} ->
                          IO.warn("Failed to load method signatures from #{@method_signatures_path}: #{inspect(reason)}")

                          %{}
                      end)

  # Inline priv path resolution to avoid compile-time dependency on CCXT.Priv
  # Emulated method list loaded at compile time for generating emulation stubs
  # Use stdlib JSON (Elixir 1.18+) at compile time to avoid Jason dependency ordering issues
  @emulated_methods_path (case :code.priv_dir(:ccxt_client) do
                            {:error, :bad_name} ->
                              [__DIR__, "..", "..", "..", "priv", "extractor/ccxt_emulated_methods.json"]
                              |> Path.join()
                              |> Path.expand()

                            priv when is_list(priv) ->
                              Path.join(List.to_string(priv), "extractor/ccxt_emulated_methods.json")
                          end)
  @external_resource @emulated_methods_path
  @emulated_methods (case File.read(@emulated_methods_path) do
                       {:ok, content} ->
                         case JSON.decode(content) do
                           {:ok, %{"emulated_methods" => methods}} ->
                             methods

                           {:ok, _} ->
                             IO.warn("Unexpected format in #{@emulated_methods_path}: missing emulated_methods key")

                             %{}

                           {:error, reason} ->
                             IO.warn(
                               "Failed to parse emulated methods from #{@emulated_methods_path}: #{inspect(reason)}"
                             )

                             %{}
                         end

                       {:error, reason} ->
                         IO.warn("Failed to load emulated methods from #{@emulated_methods_path}: #{inspect(reason)}")

                         %{}
                     end)

  @doc """
  Generates all endpoint functions from the spec.

  Returns AST for all functions defined in `spec.endpoints`, plus stub functions
  for methods that failed during extraction (e.g., inherited methods that don't
  work for this exchange class).
  """
  @spec generate_endpoints(Spec.t()) :: Macro.t()
  def generate_endpoints(spec) do
    endpoint_fns =
      spec.endpoints
      |> Enum.map(&generate_endpoint_function(&1, spec))
      |> List.flatten()

    # Generate stubs for extraction failures
    failure_stubs = generate_extraction_failure_stubs(spec)

    # Generate stubs for emulated methods without HTTP endpoints
    emulated_stubs = generate_emulated_method_stubs(spec)

    endpoint_fns ++ failure_stubs ++ emulated_stubs
  end

  # Generate a function for a single endpoint
  @doc false
  @spec generate_endpoint_function(map(), Spec.t()) :: Macro.t() | []
  defp generate_endpoint_function(endpoint, spec) do
    name = endpoint[:name]
    auth = endpoint[:auth]
    params = Map.get(endpoint, :params, [])

    # Get capability from spec.has to determine if this should be generated
    has_capability = Map.get(spec.has, name, true)

    if has_capability do
      # Build endpoint options map to reduce arity
      # Infer response_type from endpoint name if not explicitly set
      response_type =
        endpoint[:response_type] || CCXT.ResponseCoercer.infer_response_type(name)

      endpoint_opts = %{
        method: endpoint[:method],
        path: endpoint[:path],
        auth: auth,
        params: params,
        param_mappings: Map.get(endpoint, :param_mappings, %{}),
        required_params: Map.get(endpoint, :required_params, []),
        default_params: Map.get(endpoint, :default_params, %{}),
        base_url: endpoint[:base_url],
        market_type: endpoint[:market_type],
        response_transformer: endpoint[:response_transformer],
        response_type: response_type
      }

      generate_endpoint(name, endpoint_opts, spec)
    else
      # Generate a stub that returns {:error, :not_supported}
      generate_unsupported_endpoint(name, auth, params)
    end
  end

  # Shared endpoint generation logic for public and private endpoints.
  # Uses an options map to keep arity low while supporting many configuration options.
  @doc false
  @spec generate_endpoint(atom(), map(), Spec.t()) :: Macro.t()
  defp generate_endpoint(name, opts, spec) do
    %{
      method: method,
      path: path,
      auth: auth,
      params: params,
      param_mappings: param_mappings,
      required_params: required_params,
      default_params: default_params,
      base_url: base_url,
      market_type: market_type,
      response_transformer: response_transformer,
      response_type: response_type
    } = opts

    {args, param_map} = build_args_and_params(params, auth, required_params)
    # Convert param_mappings to compile-time value for injection
    param_mappings_ast = Macro.escape(param_mappings)
    # Convert default_params to compile-time value (e.g., %{"type" => "step0"} for HTX order book)
    default_params_ast = Macro.escape(default_params)
    # Convert response_type for compile-time injection in coercion
    response_type_ast = Macro.escape(response_type)
    doc = Docs.generate_doc(name, params, auth, spec)
    spec_signature = Typespecs.generate_typespec_signature(name, params, auth, required_params)
    return_type_ast = Typespecs.ok_error_return_type_ast(name)
    path_ast = interpolate_path(path, param_mappings)

    # Reference variables from function args (same context: Elixir)
    opts_var = {:opts, [], Elixir}
    creds_var = {:credentials, [], Elixir}

    # Build client_opts AST - add credentials and base_url for endpoints with custom API base
    client_opts_ast = build_client_opts_ast(opts_var, creds_var, auth, base_url)
    # Convert market_type to compile-time value for symbol format lookup
    market_type_ast = Macro.escape(market_type)

    quote do
      @spec unquote(spec_signature) :: unquote(return_type_ast)
      @doc unquote(doc)
      def unquote(name)(unquote_splicing(args)) do
        # Build params: defaults → function args → extra opts params
        params =
          unquote(default_params_ast)
          |> Map.merge(unquote(param_map))
          |> Map.merge(Map.new(Keyword.get(unquote(opts_var), :params, [])))

        # Capture credentials (nil for public endpoints) for emulation dispatch
        credentials = unquote(if auth, do: creds_var)

        # Emulated method dispatch (REST scope)
        case CCXT.Emulation.dispatch(@ccxt_spec, unquote(name), :rest, %{
               exchange_module: __MODULE__,
               params: params,
               opts: unquote(opts_var),
               credentials: credentials
             }) do
          :passthrough ->
            # credo:disable-for-lines:4 Credo.Check.Design.AliasUsage
            params =
              params
              |> CCXT.Generator.Helpers.resolve_generated_placeholders()
              |> CCXT.Generator.Helpers.denormalize_symbol_param(@ccxt_spec, unquote(market_type_ast))

            # Convert OHLCV timestamps if needed (users always pass milliseconds, library converts)
            params = unquote(build_ohlcv_timestamp_conversion_ast(name))

            # Interpolate path, apply mappings, prepend prefix
            base_path = unquote(path_ast)
            # credo:disable-for-next-line Credo.Check.Design.AliasUsage
            params = CCXT.Generator.Helpers.apply_endpoint_mappings(params, unquote(param_mappings_ast))
            path = unquote(build_prefixed_path_ast(spec.path_prefix, path))

            # Execute HTTP request with response transformation
            client_opts = unquote(client_opts_ast)
            # credo:disable-for-next-line Credo.Check.Design.AliasUsage
            CCXT.Generator.Helpers.execute_request(
              @ccxt_spec,
              unquote(method),
              path,
              client_opts,
              unquote(response_transformer),
              unquote(response_type_ast),
              unquote(opts_var)
            )

          {:ok, result} ->
            {:ok, result}

          {:error, _} = error ->
            error
        end
      end
    end
  end

  # Generate a stub for unsupported endpoints
  @doc false
  @spec generate_unsupported_endpoint(atom(), boolean(), [atom()]) :: Macro.t()
  defp generate_unsupported_endpoint(name, auth, params) do
    {args, _param_map} = build_args_and_params(params, auth, [])
    spec_signature = Typespecs.generate_typespec_signature(name, params, auth, [])
    return_type_ast = Typespecs.ok_error_return_type_ast(name)

    quote do
      @spec unquote(spec_signature) :: unquote(return_type_ast)
      @doc false
      def unquote(name)(unquote_splicing(args)) do
        {:error,
         %CCXT.Error{
           type: :exchange_error,
           message: "#{unquote(name)} not supported by this exchange"
         }}
      end
    end
  end

  # Builds client_opts AST for HTTP client calls.
  # Adds credentials for authenticated endpoints and base_url for custom API sections.
  @doc false
  @spec build_client_opts_ast(Macro.t(), Macro.t(), boolean(), String.t() | nil) :: Macro.t()
  defp build_client_opts_ast(opts_var, creds_var, auth, base_url) do
    # Build base client_opts (params + credentials if auth)
    base_opts_ast =
      if auth do
        quote do
          client_opts = Keyword.delete(unquote(opts_var), :params)
          client_opts = Keyword.put(client_opts, :params, params)
          Keyword.put(client_opts, :credentials, unquote(creds_var))
        end
      else
        quote do
          client_opts = Keyword.delete(unquote(opts_var), :params)
          Keyword.put(client_opts, :params, params)
        end
      end

    # Add base_url if endpoint uses a custom API section
    if base_url do
      quote do
        client_opts = unquote(base_opts_ast)
        Keyword.put(client_opts, :base_url, unquote(base_url))
      end
    else
      base_opts_ast
    end
  end

  # Builds function arguments and parameter map AST for endpoint functions.
  #
  # Returns a tuple of {args_ast, param_map_ast} where:
  # - args_ast: List of function argument AST nodes (credentials if auth, params, opts)
  # - param_map_ast: AST that builds a map from param names to their runtime values,
  #   filtering out nil values for optional params
  #
  # Uses consistent Elixir context for all variables so they can be referenced in the function body.
  # `required_params` overrides @optional_params - if a param is in both, it's required.
  @doc false
  @spec build_args_and_params([atom()], boolean(), [atom()]) :: {list(), Macro.t()}
  defp build_args_and_params(params, auth, required_params) do
    # Start with credentials if auth required (using Elixir context)
    base_args = if auth, do: [{:credentials, [], Elixir}], else: []

    # Add params as individual arguments (with defaults for optional ones)
    # A param gets default nil if it's in @optional_params AND NOT in required_params
    param_args =
      Enum.map(params, fn param ->
        is_optional = param in @optional_params and param not in required_params

        if is_optional do
          {:\\, [], [{param, [], Elixir}, nil]}
        else
          {param, [], Elixir}
        end
      end)

    # Always add opts at the end
    opts_arg = {:\\, [], [{:opts, [], Elixir}, []]}

    args = base_args ++ param_args ++ [opts_arg]

    # Build AST that creates the parameter map at runtime
    # Generate: [{:symbol, symbol}, {:limit, limit}, ...] |> Enum.reject(...) |> Map.new()
    param_pairs =
      Enum.map(params, fn param ->
        # Generate a {key, var} tuple AST
        {:{}, [], [param, {param, [], Elixir}]}
      end)

    param_map_ast =
      quote do
        unquote(param_pairs)
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
      end

    {args, param_map_ast}
  end

  # Generates AST for path interpolation at runtime.
  #
  # Handles two placeholder styles:
  # - Phoenix-style: `/ticker/:symbol` - colon prefix
  # - CCXT/OpenAPI-style: `/ticker/{pair}/` - curly braces
  #
  # Path parameters come from trusted spec files loaded at compile time, not user input.
  # The atoms already exist because they're defined in endpoint[:params], making
  # String.to_existing_atom safe - it will only match atoms created during spec loading.
  #
  # Generates AST for path placeholder interpolation using reversed param_mappings.
  # For {param} style, reverses param_mappings to map request names to unified params.
  # Example: param_mappings %{"id" => "order-id"} becomes %{"order-id" => :id}
  #
  # sobelow_skip ["DOS.StringToAtom"]
  @doc false
  @spec interpolate_path(String.t(), map()) :: String.t() | Macro.t()
  defp interpolate_path(path, param_mappings) do
    # For paths with :param or {param} placeholders, generate interpolation code
    # :param style: /ticker/:symbol (Phoenix-style)
    # {param} style: /ticker/{pair}/ (CCXT/OpenAPI-style)
    cond do
      String.contains?(path, ":") ->
        quote do
          Regex.replace(~r/:(\w+)/, unquote(path), fn _match, key ->
            # Safe: path placeholders come from trusted spec files loaded at compile time
            # sobelow_skip ["DOS.StringToAtom"]
            key_atom = String.to_atom(key)
            to_string(Map.get(params, key_atom, ""))
          end)
        end

      String.contains?(path, "{") ->
        interpolate_curly_brace_path(path, param_mappings)

      true ->
        path
    end
  end

  # Generates AST for {param} style path interpolation (CCXT/OpenAPI-style).
  # Reverses param_mappings at compile time: %{"id" => "order-id"} → %{"order-id" => :id}
  # Generates different code when aliases map is empty to avoid Elixir 1.19+ type warnings.
  #
  # sobelow_skip ["DOS.StringToAtom"]
  @doc false
  @spec interpolate_curly_brace_path(String.t(), map()) :: Macro.t()
  defp interpolate_curly_brace_path(path, param_mappings) do
    reversed =
      for {unified, request} <- param_mappings, into: %{} do
        {request, String.to_atom(unified)}
      end

    # Generate different code depending on whether aliases exist
    # This avoids Elixir 1.19+ type warnings about Map.get on empty maps
    if map_size(reversed) == 0 do
      interpolate_curly_brace_path_simple(path)
    else
      interpolate_curly_brace_path_with_aliases(path, reversed)
    end
  end

  @doc false
  defp interpolate_curly_brace_path_simple(path) do
    quote do
      Regex.replace(~r/\{(\w+)\}/, unquote(path), fn _match, key ->
        # Safe: path placeholders come from trusted spec files loaded at compile time
        # sobelow_skip ["DOS.StringToAtom"]
        param_key = String.to_atom(key)
        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        CCXT.Generator.Helpers.get_path_param(params, param_key, key)
      end)
    end
  end

  @doc false
  defp interpolate_curly_brace_path_with_aliases(path, reversed) do
    escaped_reversed = Macro.escape(reversed)

    quote do
      aliases = unquote(escaped_reversed)

      Regex.replace(~r/\{(\w+)\}/, unquote(path), fn _match, key ->
        # First check reversed param_mappings, then try direct atom conversion
        # Safe: path placeholders come from trusted spec files loaded at compile time
        # sobelow_skip ["DOS.StringToAtom"]
        param_key = Map.get(aliases, key, String.to_atom(key))
        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        CCXT.Generator.Helpers.get_path_param(params, param_key, key)
      end)
    end
  end

  # Generates AST for combining path prefix with base path, avoiding double slashes.
  #
  # Handles cases like:
  # - prefix="/api/v3/", base_path="/brokerage" -> "/api/v3/brokerage"
  # - prefix="/api/v3", base_path="/brokerage" -> "/api/v3/brokerage"
  # - prefix="", base_path="/brokerage" -> "/brokerage"
  @doc false
  @spec build_prefixed_path_ast(String.t(), String.t()) :: Macro.t()
  defp build_prefixed_path_ast(prefix, path) do
    cond do
      prefix == "" ->
        quote do
          base_path
        end

      String.starts_with?(path, prefix) ->
        # Path already includes prefix (semantic endpoints)
        quote do
          base_path
        end

      String.ends_with?(prefix, "/") and String.starts_with?(path, "/") ->
        # Avoid double slashes: if prefix ends with "/" and path starts with "/",
        # strip the leading "/" from path
        quote do
          unquote(prefix) <> String.slice(base_path, 1..-1//1)
        end

      true ->
        quote do
          unquote(prefix) <> base_path
        end
    end
  end

  # Generates AST for OHLCV timestamp conversion (ms → seconds for some exchanges).
  # Users always pass milliseconds; the library converts internally based on spec.
  # Only applies to fetch_ohlcv endpoint; other endpoints pass params unchanged.
  # Converts all timestamp params (:since, "to", "from", etc.) - not just :since.
  @doc false
  @spec build_ohlcv_timestamp_conversion_ast(atom()) :: Macro.t()
  defp build_ohlcv_timestamp_conversion_ast(:fetch_ohlcv) do
    quote do
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      CCXT.Generator.Helpers.convert_ohlcv_timestamps(params, @ccxt_spec.ohlcv_timestamp_resolution)
    end
  end

  defp build_ohlcv_timestamp_conversion_ast(_name) do
    # For non-OHLCV endpoints, no conversion needed - just return params unchanged
    quote do
      params
    end
  end

  # =============================================================================
  # Extraction Failure Stub Generation
  #
  # When CCXT reports has.X: true but the method fails during extraction
  # (e.g., "fetchPosition() supports option markets only"), we generate a
  # stub function that returns the helpful error message instead of leaving
  # the user with a confusing "function undefined" compile error.
  # =============================================================================

  @doc false
  @spec generate_extraction_failure_stubs(Spec.t()) :: [Macro.t()]
  defp generate_extraction_failure_stubs(spec) do
    failures = get_in(spec.endpoint_extraction_stats, ["failures"]) || []

    # Get names of endpoints that were successfully extracted
    existing_endpoints = MapSet.new(spec.endpoints, & &1[:name])

    failures
    |> Enum.map(&parse_failure/1)
    |> Enum.reject(fn
      nil -> true
      {name, _msg} -> MapSet.member?(existing_endpoints, name)
    end)
    |> Enum.map(fn {name, message} ->
      generate_failure_stub(name, message, spec)
    end)
  end

  # Parse failure entry into {atom_name, error_message}
  @doc false
  @spec parse_failure(map()) :: {atom(), String.t()} | nil
  defp parse_failure(%{"method" => method, "error" => error}) when is_binary(method) do
    # Convert camelCase to snake_case atom
    name = method |> Macro.underscore() |> String.to_atom()
    {name, error}
  end

  defp parse_failure(_), do: nil

  # Generate a stub function for a failed extraction
  @doc false
  @spec generate_failure_stub(atom(), String.t(), Spec.t()) :: Macro.t()
  defp generate_failure_stub(name, message, spec) do
    {params, auth} = method_metadata(name)

    {args, _param_map} = build_args_and_params(params, auth, [])
    spec_signature = Typespecs.generate_typespec_signature(name, params, auth, [])
    return_type_ast = Typespecs.ok_error_return_type_ast(name)
    exchange_id = spec.exchange_id || String.to_atom(spec.id)

    quote do
      @doc """
      **Not supported on this exchange.**

      #{unquote(message)}

      This method exists in CCXT's capability list but cannot be called on this
      exchange class due to market type restrictions or inheritance limitations.
      """
      @spec unquote(spec_signature) :: unquote(return_type_ast)
      def unquote(name)(unquote_splicing(args)) do
        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        {:error,
         CCXT.Error.not_supported(
           message: unquote(message),
           exchange: unquote(exchange_id)
         )}
      end
    end
  end

  @doc false
  # Generates stub functions for emulated methods that have no HTTP endpoint mapping.
  @spec generate_emulated_method_stubs(Spec.t()) :: [Macro.t()]
  defp generate_emulated_method_stubs(spec) do
    entries = Map.get(@emulated_methods, spec.id, [])
    excluded = build_excluded_names(spec)

    entries
    |> Enum.map(&emulated_entry_to_name_pair/1)
    |> Enum.reject(fn
      nil -> true
      {name, _entry} -> MapSet.member?(excluded, name)
    end)
    |> Map.new()
    |> Enum.map(fn {name, entry} -> generate_emulated_stub(name, entry, spec) end)
  end

  @doc false
  # Builds a set of method names that should not get emulated stubs.
  @spec build_excluded_names(Spec.t()) :: MapSet.t()
  defp build_excluded_names(spec) do
    endpoint_names = MapSet.new(spec.endpoints, & &1[:name])
    failure_names = MapSet.new(failure_stub_names(spec))
    MapSet.union(endpoint_names, failure_names)
  end

  @doc false
  # Converts an emulated entry to {name, entry} tuple or nil.
  @spec emulated_entry_to_name_pair(map()) :: {atom(), map()} | nil
  defp emulated_entry_to_name_pair(entry) do
    case emulated_entry_to_name(entry) do
      nil -> nil
      name -> {name, entry}
    end
  end

  @doc false
  # Extracts emulated method names from failure entries to avoid duplicate stubs.
  @spec failure_stub_names(Spec.t()) :: [atom()]
  defp failure_stub_names(spec) do
    failures = get_in(spec.endpoint_extraction_stats, ["failures"]) || []

    failures
    |> Enum.map(&parse_failure/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn {name, _msg} -> name end)
  end

  @doc false
  # Converts an emulated method entry to its snake_case atom name.
  @spec emulated_entry_to_name(map()) :: atom() | nil
  defp emulated_entry_to_name(%{"name" => name}) when is_binary(name) do
    name
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp emulated_entry_to_name(_), do: nil

  @doc false
  # Generates a stub function for an emulated method.
  @spec generate_emulated_stub(atom(), map(), Spec.t()) :: Macro.t()
  defp generate_emulated_stub(name, entry, spec) do
    {params, auth} = method_metadata(name)
    {args, param_map} = build_args_and_params(params, auth, [])
    spec_signature = Typespecs.generate_typespec_signature(name, params, auth, [])
    return_type_ast = Typespecs.ok_error_return_type_ast(name)
    exchange_id = spec.exchange_id || String.to_atom(spec.id)
    reason_suffix = emulated_reason_suffix(entry)
    opts_var = {:opts, [], Elixir}
    creds_var = {:credentials, [], Elixir}

    quote do
      @doc """
      **Emulated method (no HTTP call).**

      CCXT marks this method as emulated for this exchange#{unquote(reason_suffix)}.
      """
      @spec unquote(spec_signature) :: unquote(return_type_ast)
      def unquote(name)(unquote_splicing(args)) do
        params = unquote(param_map)
        extra_params = Keyword.get(unquote(opts_var), :params, [])
        params = Map.merge(params, Map.new(extra_params))
        credentials = unquote(if auth, do: creds_var)

        case CCXT.Emulation.dispatch(@ccxt_spec, unquote(name), :rest, %{
               exchange_module: __MODULE__,
               params: params,
               opts: unquote(opts_var),
               credentials: credentials
             }) do
          :passthrough ->
            {:error,
             CCXT.Error.not_supported(
               message: "Emulated method not registered: #{unquote(Atom.to_string(name))}",
               exchange: unquote(exchange_id)
             )}

          {:ok, result} ->
            {:ok, result}

          {:error, _} = error ->
            error
        end
      end
    end
  end

  @doc false
  # Builds the reason suffix for emulated method docs.
  @spec emulated_reason_suffix(map()) :: String.t()
  defp emulated_reason_suffix(entry) do
    case Map.get(entry, "reasons", []) do
      [] -> ""
      reasons -> " (#{Enum.join(reasons, ", ")})"
    end
  end

  # Convert snake_case to camelCase for CCXT method lookup
  @doc false
  @spec camelize(String.t()) :: String.t()
  defp camelize(string) do
    string
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map_join(fn
      {word, 0} -> word
      {word, _} -> String.capitalize(word)
    end)
  end

  # Extracts method parameters and auth requirement from cached CCXT signatures.
  @doc false
  @spec method_metadata(atom()) :: {[atom()], boolean()}
  defp method_metadata(name) do
    camel_name = name |> Atom.to_string() |> camelize()
    params = @method_signatures |> Map.get(camel_name, []) |> Enum.map(&String.to_atom/1)
    auth = infer_auth_from_name(name)
    {params, auth}
  end

  # Infer authentication requirement from method name
  @doc false
  @spec infer_auth_from_name(atom()) :: boolean()
  defp infer_auth_from_name(name) do
    name_str = Atom.to_string(name)

    # Public methods typically start with fetch_ and are market data
    public_prefixes = [
      "fetch_ticker",
      "fetch_order_book",
      "fetch_trades",
      "fetch_ohlcv",
      "fetch_markets",
      "fetch_currencies",
      "fetch_time",
      "fetch_status"
    ]

    not Enum.any?(public_prefixes, &String.starts_with?(name_str, &1))
  end
end
