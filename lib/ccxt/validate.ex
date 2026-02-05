defmodule CCXT.Validate do
  @moduledoc """
  Validation utilities with helpful error hints.

  This module provides validation functions for symbols, parameters, and WebSocket
  symbol formats. Each function returns helpful error messages that guide users
  toward correct usage.

  ## Functions

  - `symbol/3` - Validates that a symbol is in unified format (BASE/QUOTE)
  - `params/3` - Validates that required parameters are present for an endpoint
  - `ws_symbol/3` - Validates and transforms a symbol for WebSocket subscriptions

  ## Exchange Resolution

  All functions accept exchange identifiers in multiple formats:
  - Exchange module (e.g., `CCXT.Bybit`)
  - Exchange atom (e.g., `:bybit`)
  - Exchange string (e.g., `"bybit"`)
  - Spec struct directly (e.g., `%CCXT.Spec{}`)
  """

  alias CCXT.Spec
  alias CCXT.Symbol

  # WebSocket symbol transformations by exchange
  # These exchanges require lowercase symbols for WebSocket subscriptions
  @ws_lowercase_exchanges ~w(binance binanceusdm binancecoinm)

  # =============================================================================
  # Task 126: Symbol Format Validation
  # =============================================================================

  @doc """
  Validates that a symbol is in unified format.

  Returns `{:ok, symbol}` if valid, or `{:error, message}` with a helpful hint
  showing the expected format for the exchange.

  ## Parameters

  - `exchange` - Exchange module, atom, string, or spec struct
  - `symbol` - The symbol to validate
  - `opts` - Optional keyword list:
    - `:market_type` - Market type for derivatives (`:swap`, `:future`, `:option`)

  ## Examples

      CCXT.Validate.symbol(:bybit, "BTC/USDT")
      # => {:ok, "BTC/USDT"}

      CCXT.Validate.symbol(:bybit, "BTC-USDT")
      # => {:error, "Invalid symbol format 'BTC-USDT'. Bybit uses 'BASE/QUOTE' format (separator: /, case: upper). Example: BTC/USDT"}

      CCXT.Validate.symbol(:bybit, "BTC/USDT:USDT", market_type: :swap)
      # => {:ok, "BTC/USDT:USDT"}

  """
  @spec symbol(module() | atom() | String.t() | Spec.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def symbol(exchange, symbol, opts \\ [])

  def symbol(exchange, symbol, opts) when is_binary(symbol) do
    case resolve_spec(exchange) do
      {:ok, spec} ->
        validate_symbol_format(symbol, spec, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  # Validates a symbol against the unified format using Symbol.parse/1
  @spec validate_symbol_format(String.t(), Spec.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp validate_symbol_format(symbol, spec, _opts) do
    case Symbol.parse(symbol) do
      {:ok, _parsed} ->
        {:ok, symbol}

      {:error, :invalid_format} ->
        {:error, build_symbol_error_hint(symbol, spec)}
    end
  end

  @doc false
  # Builds a helpful error message for invalid symbol format
  @spec build_symbol_error_hint(String.t(), Spec.t()) :: String.t()
  defp build_symbol_error_hint(symbol, spec) do
    exchange_name = spec.name
    format = get_symbol_format(spec)

    separator_desc =
      case format[:separator] do
        "" -> "no separator"
        "/" -> "/"
        sep -> sep
      end

    case_desc =
      case format[:case] do
        :upper -> "upper"
        :lower -> "lower"
        :mixed -> "mixed"
        _ -> "upper"
      end

    # Build example using a common pair
    example = build_example_symbol(format)

    "Invalid symbol format '#{symbol}'. #{exchange_name} uses 'BASE/QUOTE' format " <>
      "(separator: #{separator_desc}, case: #{case_desc}). Example: #{example}"
  end

  @doc false
  # Gets the symbol format from a spec, with defaults
  @spec get_symbol_format(Spec.t()) :: map()
  defp get_symbol_format(%Spec{symbol_format: nil}), do: %{separator: "", case: :upper}
  defp get_symbol_format(%Spec{symbol_format: format}), do: format

  @doc false
  # Builds an example unified symbol
  @spec build_example_symbol(map()) :: String.t()
  defp build_example_symbol(_format), do: "BTC/USDT"

  # =============================================================================
  # Task 127: Required Param Validation
  # =============================================================================

  @doc """
  Validates that required parameters are present for an endpoint.

  Returns `{:ok, params_map}` if all required parameters are present,
  or `{:error, message}` listing the missing parameters.

  ## Parameters

  - `exchange` - Exchange module, atom, string, or spec struct
  - `method` - The endpoint method name (e.g., `:create_order`, `:fetch_balance`)
  - `params` - The parameters provided (map or keyword list)

  ## Examples

      CCXT.Validate.params(:bybit, :create_order, %{symbol: "BTC/USDT"})
      # => {:error, "Missing required parameters: [:type, :side, :amount]. Endpoint 'create_order' requires: symbol, type, side, amount, price"}

      CCXT.Validate.params(:bybit, :create_order, %{symbol: "BTC/USDT", type: "limit", side: "buy", amount: 0.1, price: 50000})
      # => {:ok, %{symbol: "BTC/USDT", type: "limit", side: "buy", amount: 0.1, price: 50000}}

  """
  @spec params(module() | atom() | String.t() | Spec.t(), atom(), map() | keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def params(exchange, method, params) when is_atom(method) do
    params_map = normalize_params(params)

    case resolve_spec(exchange) do
      {:ok, spec} ->
        validate_endpoint_params(spec, method, params_map)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  # Normalizes params to a map with atom keys.
  # String keys are converted to atoms only if the atom already exists (security).
  # Unknown string keys are kept as strings to avoid atom table exhaustion.
  @spec normalize_params(map() | keyword()) :: map()
  defp normalize_params(params) when is_map(params) do
    Map.new(params, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {safe_to_atom(k), v}
    end)
  end

  defp normalize_params(params) when is_list(params) do
    Map.new(params)
  end

  @doc false
  # Safely converts a string to an existing atom, keeping as string if not found.
  # This prevents atom table exhaustion from user-provided keys.
  @spec safe_to_atom(String.t()) :: atom() | String.t()
  defp safe_to_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  @doc false
  # Validates endpoint parameters against required params list.
  # Handles both atom and string keys (string keys kept when atom doesn't exist).
  @spec validate_endpoint_params(Spec.t(), atom(), map()) ::
          {:ok, map()} | {:error, String.t()}
  defp validate_endpoint_params(spec, method, params_map) do
    case find_endpoint(spec, method) do
      nil ->
        {:error, "Unknown endpoint '#{method}' for #{spec.name}"}

      endpoint ->
        required = get_required_params(endpoint)
        # Normalize keys to strings for comparison (handles mixed atom/string keys)
        provided_keys = params_map |> Map.keys() |> MapSet.new(&to_string/1)
        missing = Enum.filter(required, fn p -> to_string(p) not in provided_keys end)

        if Enum.empty?(missing) do
          {:ok, params_map}
        else
          {:error, build_params_error_hint(method, missing, required)}
        end
    end
  end

  @doc false
  # Finds an endpoint by name in the spec's endpoint list
  @spec find_endpoint(Spec.t(), atom()) :: map() | nil
  defp find_endpoint(%Spec{endpoints: endpoints}, name) do
    Enum.find(endpoints, fn ep -> ep[:name] == name end)
  end

  @doc false
  # Gets required params from an endpoint
  # Uses :required_params if available, falls back to :params
  @spec get_required_params(map()) :: [atom()]
  defp get_required_params(endpoint) do
    case Map.get(endpoint, :required_params) do
      nil -> Map.get(endpoint, :params, [])
      required -> required
    end
  end

  @doc false
  # Builds a helpful error message for missing parameters
  @spec build_params_error_hint(atom(), [atom()], [atom()]) :: String.t()
  defp build_params_error_hint(method, missing, required) do
    required_str = Enum.map_join(required, ", ", &to_string/1)

    "Missing required parameters: #{inspect(missing)}. " <>
      "Endpoint '#{method}' requires: #{required_str}"
  end

  # =============================================================================
  # Task 144: WS Symbol Validation
  # =============================================================================

  @doc """
  Validates and transforms a symbol for WebSocket subscriptions.

  First validates the symbol format, then denormalizes it to exchange format,
  and applies any WebSocket-specific transformations (e.g., Binance uses lowercase).

  ## Parameters

  - `exchange` - Exchange module, atom, string, or spec struct
  - `symbol` - The unified symbol to validate and transform
  - `opts` - Optional keyword list:
    - `:market_type` - Market type for derivatives (`:swap`, `:future`, `:option`)

  ## Examples

      CCXT.Validate.ws_symbol(:binance, "BTC/USDT")
      # => {:ok, "btcusdt"}

      CCXT.Validate.ws_symbol(:bybit, "BTC/USDT")
      # => {:ok, "BTCUSDT"}

      CCXT.Validate.ws_symbol(:binance, "BTC-USDT")
      # => {:error, "Invalid symbol format 'BTC-USDT'. ..."}

  """
  @spec ws_symbol(module() | atom() | String.t() | Spec.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def ws_symbol(exchange, symbol, opts \\ [])

  def ws_symbol(exchange, symbol, opts) when is_binary(symbol) do
    case resolve_spec(exchange) do
      {:ok, spec} ->
        # First validate the symbol format
        case validate_symbol_format(symbol, spec, opts) do
          {:ok, valid_symbol} ->
            transform_for_websocket(valid_symbol, spec, opts)

          {:error, _} = error ->
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  # Transforms a validated symbol for WebSocket subscriptions
  @spec transform_for_websocket(String.t(), Spec.t(), keyword()) :: {:ok, String.t()}
  defp transform_for_websocket(symbol, spec, opts) do
    market_type = Keyword.get(opts, :market_type)

    # Denormalize to exchange format
    exchange_symbol = Symbol.denormalize(symbol, spec, market_type)

    # Apply WS-specific transforms
    transformed = apply_ws_transform(exchange_symbol, spec.id)

    {:ok, transformed}
  end

  @doc false
  # Applies WebSocket-specific transformations
  @spec apply_ws_transform(String.t(), String.t()) :: String.t()
  defp apply_ws_transform(symbol, exchange_id) do
    if exchange_id in @ws_lowercase_exchanges do
      String.downcase(symbol)
    else
      symbol
    end
  end

  # =============================================================================
  # Exchange Resolution
  # =============================================================================

  @doc false
  # Resolves an exchange identifier to a spec struct.
  # Accepts: module, atom, string, or spec struct.
  @spec resolve_spec(module() | atom() | String.t() | Spec.t()) ::
          {:ok, Spec.t()} | {:error, String.t()}
  defp resolve_spec(%Spec{} = spec), do: {:ok, spec}

  defp resolve_spec(exchange) when is_atom(exchange) do
    # Check if it's a module with __ccxt_spec__/0
    if function_exported?(exchange, :__ccxt_spec__, 0) do
      {:ok, exchange.__ccxt_spec__()}
    else
      # Try to construct the module name
      resolve_spec_from_id(Atom.to_string(exchange))
    end
  end

  defp resolve_spec(exchange) when is_binary(exchange) do
    resolve_spec_from_id(exchange)
  end

  @doc false
  # Resolves a spec from an exchange ID string
  @spec resolve_spec_from_id(String.t()) :: {:ok, Spec.t()} | {:error, String.t()}
  defp resolve_spec_from_id(exchange_id) do
    module_name = Module.concat(CCXT, Macro.camelize(exchange_id))

    if Code.ensure_loaded?(module_name) and function_exported?(module_name, :__ccxt_spec__, 0) do
      {:ok, module_name.__ccxt_spec__()}
    else
      # Try loading spec from file as fallback
      load_spec_from_file(exchange_id)
    end
  end

  @doc false
  # Loads a spec from priv/specs/ directory
  @spec load_spec_from_file(String.t()) :: {:ok, Spec.t()} | {:error, String.t()}
  defp load_spec_from_file(exchange_id) do
    # Check extracted specs first, then curated
    paths = [
      Path.join([:code.priv_dir(:ccxt_client), "specs", "extracted", "#{exchange_id}.exs"]),
      Path.join([:code.priv_dir(:ccxt_client), "specs", "curated", "#{exchange_id}.exs"])
    ]

    case Enum.find(paths, &File.exists?/1) do
      nil ->
        {:error, "Exchange '#{exchange_id}' not found. Check that the exchange ID is correct."}

      path ->
        spec = Spec.load!(path)
        {:ok, spec}
    end
  rescue
    e ->
      {:error, "Failed to load spec for '#{exchange_id}': #{Exception.message(e)}"}
  end
end
