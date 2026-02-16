defmodule CCXT.Generator.Functions do
  @moduledoc """
  Compile-time function generation for exchange modules.

  This module generates the AST for endpoint functions, introspection functions,
  and escape hatches. It's used internally by `CCXT.Generator`.

  ## Submodules

  Endpoint generation is delegated to specialized submodules:
  - `CCXT.Generator.Functions.Endpoints` - endpoint function AST generation
  - `CCXT.Generator.Functions.Docs` - documentation string generation
  - `CCXT.Generator.Functions.Typespecs` - @spec typespec generation

  ## Generated Introspection Functions

  ### Core Introspection

  - `__ccxt_spec__/0` - Full exchange specification struct
  - `__ccxt_endpoints__/0` - List of endpoint definitions
  - `__ccxt_signing__/0` - Signing pattern and config
  - `__ccxt_classification__/0` - Exchange tier (`:certified_pro`, `:pro`, etc.)

  ### Extended Introspection (Complete CCXT Data Passthrough)

  These functions expose all data extracted from CCXT for advanced use cases:

  | Function | Returns | Use Case |
  |----------|---------|----------|
  | `__ccxt_currencies__/0` | Currency database | Symbol validation, precision |
  | `__ccxt_markets__/0` | Market definitions | Symbol format validation |
  | `__ccxt_extended_metadata__/0` | Logo URLs, referral info, limits | UI, order validation |
  | `__ccxt_required_credentials__/0` | Credential requirements | Auth setup |
  | `__ccxt_api_param_requirements__/0` | Raw param requirements | Param validation |
  | `__ccxt_url_strategy__/0` | URL pattern detection | Debugging |
  | `__ccxt_status__/0` | Exchange operational status | Health checks |
  | `__ccxt_extraction_info__/0` | CCXT version, extraction timestamp | Version tracking |
  | `__ccxt_comment__/0` | Exchange documentation/quirks | Reference |
  | `__ccxt_exchange_options__/0` | Runtime options | Configuration |
  | `__ccxt_endpoint_stats__/0` | Extraction quality metrics | Coverage analysis |
  | `__ccxt_certified__/0` | CCXT certified status | Exchange classification |
  | `__ccxt_pro__/0` | CCXT Pro (WebSocket) support | Feature detection |
  | `__ccxt_dex__/0` | DEX indicator | Exchange type |

  ## Credo Disables

  The generated code uses `credo:disable-for-next-line Credo.Check.Design.AliasUsage`
  in several places. This is intentional because:

  1. **Macro context**: Generated code runs in the caller's module, not this one.
     Aliases defined here aren't available in the generated module.

  2. **Fully qualified names required**: Calls to `CCXT.HTTP.Client` and `CCXT.Error`
     must use full module paths to work correctly in any generated exchange module.

  3. **No runtime impact**: These are compile-time suppressions that don't affect
     the generated code's performance or behavior.
  """

  alias CCXT.Generator.Functions.Endpoints
  alias CCXT.Generator.Functions.Parsers
  alias CCXT.Generator.IntrospectionMeta
  alias CCXT.Spec

  @doc """
  Generates the @moduledoc for a generated exchange module.

  Includes 5 sections:
  1. Authentication - Signing pattern, header names
  2. Credentials - Required fields (api_key, secret, password)
  3. Timeframes - Available OHLCV intervals
  4. Introspection - All introspection functions in a table
  5. Features - Key capabilities (spot, futures, margin, etc.)
  """
  @spec generate_moduledoc(Spec.t()) :: String.t()
  def generate_moduledoc(spec) do
    """
    #{spec.name} exchange client.

    Auto-generated from spec: `priv/specs/*/#{spec.id}.exs`

    ## Authentication

    #{format_authentication(spec)}

    ## Credentials

    #{format_credentials(spec)}

    ## Timeframes

    #{format_timeframes(spec)}

    ## Introspection

    Use these #{IntrospectionMeta.function_count()} functions to explore the exchange programmatically:

    #{IntrospectionMeta.generate_table()}

    ## Features

    #{format_features(spec)}
    """
  end

  @doc false
  defp format_authentication(spec) do
    case spec.signing do
      nil -> "No authentication configured."
      %{pattern: pattern} = signing -> format_signing_details(pattern, signing)
      _ -> "Signing configuration present but format unknown."
    end
  end

  @doc false
  defp format_signing_details(pattern, signing) do
    [
      "- **Signing pattern:** `#{pattern}`",
      format_header_line("API key header", signing[:api_key_header]),
      format_header_line("Signature header", signing[:signature_header]),
      format_header_line("Timestamp header", signing[:timestamp_header]),
      if(signing[:has_passphrase], do: "- **Passphrase:** Required")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  @doc false
  defp format_header_line(_label, nil), do: nil
  defp format_header_line(label, header), do: "- **#{label}:** `#{header}`"

  @doc false
  defp format_credentials(spec) do
    case spec.required_credentials do
      nil ->
        "Credential requirements not specified."

      creds when is_map(creds) ->
        required =
          creds
          |> Enum.filter(fn {_k, v} -> v == true end)
          |> Enum.map(fn {k, _v} -> "- `#{k}`" end)

        if required == [] do
          "No credentials required (public API only)."
        else
          "Required fields:\n\n" <> Enum.join(required, "\n")
        end

      _ ->
        "Credential requirements not specified."
    end
  end

  @doc false
  defp format_timeframes(spec) do
    case spec.timeframes do
      nil ->
        "Timeframes not available."

      timeframes when map_size(timeframes) == 0 ->
        "No OHLCV timeframes supported."

      timeframes when is_map(timeframes) ->
        keys = timeframes |> Map.keys() |> Enum.sort_by(&timeframe_sort_key/1)

        formatted =
          Enum.map_join(keys, ", ", fn k -> "`#{k}`" end)

        "Available intervals: #{formatted}"
    end
  end

  # Timeframe unit multipliers in seconds
  @timeframe_multipliers %{
    "s" => 1,
    "m" => 60,
    "h" => 3600,
    "d" => 86_400,
    "w" => 604_800,
    "M" => 2_592_000
  }

  # Sorts timeframes by duration: 1m < 5m < 1h < 1d < 1w < 1M
  @doc false
  defp timeframe_sort_key(tf) do
    case Regex.run(~r/^(\d+)([smhdwM])$/, tf) do
      [_, num, unit] ->
        String.to_integer(num) * Map.get(@timeframe_multipliers, unit, 0)

      _ ->
        0
    end
  end

  @doc false
  defp format_features(spec) do
    [
      "- **Classification:** `#{spec.classification}`",
      format_status_line(spec),
      format_endpoints_line(spec.endpoints),
      format_capabilities_line(spec.has)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  @doc false
  defp format_endpoints_line(nil), do: nil
  defp format_endpoints_line(endpoints), do: "- **Endpoints:** #{length(endpoints)} unified API methods"

  @doc false
  defp format_status_line(%{certified: true, pro: true}), do: "- **Status:** CCXT Certified + Pro (WebSocket)"
  defp format_status_line(%{certified: true}), do: "- **Status:** CCXT Certified"
  defp format_status_line(%{pro: true}), do: "- **Status:** CCXT Pro (WebSocket support)"
  defp format_status_line(%{dex: true}), do: "- **Status:** Decentralized Exchange (DEX)"
  defp format_status_line(_), do: nil

  @key_capabilities [:fetch_ticker, :create_order, :fetch_balance, :fetch_ohlcv, :fetch_order_book]

  @doc false
  defp format_capabilities_line(has) when is_map(has) and map_size(has) > 0 do
    caps =
      @key_capabilities
      |> Enum.filter(&(Map.get(has, &1) == true))
      |> Enum.map_join(", ", &"`#{&1}`")

    if caps == "", do: nil, else: "- **Key capabilities:** #{caps}"
  end

  defp format_capabilities_line(_), do: nil

  @doc """
  Generates introspection functions for the exchange module.

  Returns AST for:
  - `__ccxt_spec__/0`
  - `__ccxt_endpoints__/0`
  - `__ccxt_signing__/0`
  - `__ccxt_classification__/0`
  - `endpoint_info/1`
  - `required_params/1`
  - `account_types/0`
  - `options/0`

  Extended introspection (new fields for complete CCXT data passthrough):
  - `__ccxt_raw_endpoints__/0` - Raw CCXT API endpoint structure
  - `__ccxt_extended_metadata__/0` - Logo URLs, referral info, precision, limits
  - `__ccxt_required_credentials__/0` - What credentials are needed
  - `__ccxt_currencies__/0` - Currency database
  - `__ccxt_markets__/0` - Market definitions
  - `__ccxt_api_param_requirements__/0` - Required params per endpoint (raw)
  - `__ccxt_url_strategy__/0` - URL pattern detection
  - `__ccxt_status__/0` - Exchange operational status
  - `__ccxt_extraction_info__/0` - When/how spec was extracted
  - `__ccxt_comment__/0` - Exchange documentation
  - `__ccxt_exchange_options__/0` - Runtime-modified options
  - `__ccxt_endpoint_stats__/0` - Extraction quality metrics
  """
  @spec generate_introspection(Spec.t()) :: Macro.t()
  def generate_introspection(spec) do
    quote do
      unquote(generate_core_introspection(spec.classification))
      unquote(generate_endpoint_introspection())
      unquote(generate_options_introspection(spec.options))
      unquote(generate_extended_introspection(spec))
    end
  end

  # Generate core spec/signing/classification functions
  @doc false
  @spec generate_core_introspection(:certified_pro | :pro | :supported) :: Macro.t()
  defp generate_core_introspection(classification) do
    quote do
      @doc "Returns the exchange specification"
      @spec __ccxt_spec__() :: CCXT.Spec.t()
      def __ccxt_spec__, do: @ccxt_spec

      @doc "Returns the exchange identifier"
      @spec __ccxt_exchange_id__() :: atom()
      def __ccxt_exchange_id__, do: String.to_existing_atom(@ccxt_spec.id)

      @doc "Returns the list of supported endpoints"
      @spec __ccxt_endpoints__() :: [map()]
      def __ccxt_endpoints__, do: @ccxt_spec.endpoints

      @doc "Returns the signing configuration"
      @spec __ccxt_signing__() :: map() | nil
      def __ccxt_signing__, do: @ccxt_spec.signing

      @doc "Returns the exchange classification (:certified_pro, :pro, or :supported)"
      @spec __ccxt_classification__() :: :certified_pro | :pro | :supported
      def __ccxt_classification__, do: unquote(classification)
    end
  end

  # Generate endpoint_info and required_params functions
  @doc false
  @spec generate_endpoint_introspection() :: Macro.t()
  defp generate_endpoint_introspection do
    quote do
      @doc """
      Returns detailed information about an endpoint, including contextual hints.

      ## Examples

          iex> CCXT.Bybit.endpoint_info(:fetch_balance)
          %{
            name: :fetch_balance,
            method: :get,
            path: "/v5/account/wallet-balance",
            auth: true,
            params: [],
            hints: %{
              account_types: %{"unified" => "UNIFIED", "spot" => "SPOT", ...},
              default_account_type: "UNIFIED",
              required_extra_params: [:accountType]
            }
          }

          iex> CCXT.Bybit.endpoint_info(:unknown_method)
          nil

      """
      @spec endpoint_info(atom()) :: map() | nil
      def endpoint_info(name) when is_atom(name) do
        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        CCXT.Generator.Introspection.endpoint_info(@ccxt_spec, name)
      end

      @doc """
      Returns a list of required parameters for an endpoint beyond the function signature.

      This helps users discover exchange-specific parameters that are required
      but not part of the unified API signature.

      ## Examples

          iex> CCXT.Bybit.required_params(:fetch_balance)
          [:accountType]

          iex> CCXT.Binance.required_params(:fetch_balance)
          []

      """
      @spec required_params(atom()) :: [atom()]
      def required_params(name) when is_atom(name) do
        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        CCXT.Generator.Introspection.required_params(@ccxt_spec, name)
      end
    end
  end

  # Generate account_types and options functions
  # Pre-computes accounts_by_type at macro expansion time for direct access
  @doc false
  @spec generate_options_introspection(map()) :: Macro.t()
  defp generate_options_introspection(options) do
    accounts_by_type = Map.get(options, :accounts_by_type, %{})

    quote do
      @doc """
      Returns account type mappings for this exchange.

      Maps unified account type names to exchange-specific values.

      ## Examples

          iex> CCXT.Bybit.account_types()
          %{"unified" => "UNIFIED", "spot" => "SPOT", "contract" => "CONTRACT", ...}

          iex> CCXT.Binance.account_types()
          %{}

      """
      @spec account_types() :: map()
      def account_types, do: unquote(Macro.escape(accounts_by_type))

      @doc """
      Returns exchange-specific options from the spec.

      This includes default settings like default_type, default_sub_type,
      default_settle, recv_window, etc.

      ## Examples

          iex> CCXT.Bybit.options()
          %{
            default_type: "swap",
            default_sub_type: "linear",
            default_settle: "USDT",
            accounts_by_type: %{...},
            ...
          }

      """
      @spec options() :: map()
      def options, do: @ccxt_spec.options
    end
  end

  # Generate extended introspection functions for complete CCXT data passthrough
  # This function generates many simple accessor functions - the "complexity" is just
  # extracting many fields, not actual control flow complexity.
  @doc false
  @spec generate_extended_introspection(Spec.t()) :: Macro.t()
  # credo:disable-for-lines:85 Credo.Check.Refactor.CyclomaticComplexity
  defp generate_extended_introspection(spec) do
    # Pre-compute values at macro expansion time for direct access
    raw_endpoints = spec.raw_endpoints
    extended_metadata = spec.extended_metadata
    required_credentials = spec.required_credentials
    currencies = spec.currencies
    markets = spec.markets
    api_param_requirements = spec.api_param_requirements
    url_strategy = spec.url_strategy
    status = spec.status
    extracted_metadata = spec.extracted_metadata
    comment = spec.comment
    exchange_options = spec.exchange_options
    endpoint_extraction_stats = spec.endpoint_extraction_stats
    certified = spec.certified
    pro = spec.pro
    dex = spec.dex
    precision_mode = get_in(spec.symbol_formats || %{}, [:precision_mode])

    quote do
      @doc "Returns raw CCXT API endpoint structure"
      @spec __ccxt_raw_endpoints__() :: map() | nil
      def __ccxt_raw_endpoints__, do: unquote(Macro.escape(raw_endpoints))

      @doc "Returns extended metadata (logo URLs, referral info, precision, limits)"
      @spec __ccxt_extended_metadata__() :: map() | nil
      def __ccxt_extended_metadata__, do: unquote(Macro.escape(extended_metadata))

      @doc "Returns required credentials configuration"
      @spec __ccxt_required_credentials__() :: map() | nil
      def __ccxt_required_credentials__, do: unquote(Macro.escape(required_credentials))

      @doc "Returns currency database"
      @spec __ccxt_currencies__() :: map() | nil
      def __ccxt_currencies__, do: unquote(Macro.escape(currencies))

      @doc "Returns market definitions"
      @spec __ccxt_markets__() :: map() | nil
      def __ccxt_markets__, do: unquote(Macro.escape(markets))

      @doc "Returns raw API parameter requirements"
      @spec __ccxt_api_param_requirements__() :: map() | nil
      def __ccxt_api_param_requirements__, do: unquote(Macro.escape(api_param_requirements))

      @doc "Returns URL strategy pattern detection result"
      @spec __ccxt_url_strategy__() :: map() | nil
      def __ccxt_url_strategy__, do: unquote(Macro.escape(url_strategy))

      @doc "Returns exchange operational status"
      @spec __ccxt_status__() :: map() | nil
      def __ccxt_status__, do: unquote(Macro.escape(status))

      @doc "Returns extraction metadata (ccxt_version, extracted_at)"
      @spec __ccxt_extraction_info__() :: map() | nil
      def __ccxt_extraction_info__, do: unquote(Macro.escape(extracted_metadata))

      @doc "Returns exchange documentation/comment"
      @spec __ccxt_comment__() :: String.t() | nil
      def __ccxt_comment__, do: unquote(comment)

      @doc "Returns runtime-modified exchange options"
      @spec __ccxt_exchange_options__() :: map() | nil
      def __ccxt_exchange_options__, do: unquote(Macro.escape(exchange_options))

      @doc "Returns endpoint extraction quality metrics"
      @spec __ccxt_endpoint_stats__() :: map() | nil
      def __ccxt_endpoint_stats__, do: unquote(Macro.escape(endpoint_extraction_stats))

      @doc "Returns whether exchange is CCXT certified"
      @spec __ccxt_certified__() :: boolean() | nil
      def __ccxt_certified__, do: unquote(certified)

      @doc "Returns whether exchange supports CCXT Pro (WebSocket)"
      @spec __ccxt_pro__() :: boolean() | nil
      def __ccxt_pro__, do: unquote(pro)

      @doc "Returns whether exchange is a DEX"
      @spec __ccxt_dex__() :: boolean() | nil
      def __ccxt_dex__, do: unquote(dex)

      @doc "Returns the exchange precision mode (0=DECIMALS, 1=SIGNIFICANT_DIGITS, 4=TICK_SIZE)"
      @spec __ccxt_precision_mode__() :: non_neg_integer() | nil
      def __ccxt_precision_mode__, do: unquote(precision_mode)
    end
  end

  @doc """
  Generates escape hatch functions for direct API access.

  Returns AST for:
  - `request/3` - Typed request with signing
  - `raw_request/5` - Direct HTTP without signing
  """
  @spec generate_escape_hatches() :: Macro.t()
  def generate_escape_hatches do
    quote do
      @doc """
      Makes a typed request with signing (escape hatch level 2).

      This allows making requests to endpoints not covered by the unified API
      while still benefiting from automatic signing.

      ## Parameters

      - `method` - HTTP method (:get, :post, :put, :delete)
      - `path` - API path (e.g., "/v5/custom/endpoint")

      ## Options

      - `:params` - Request parameters
      - `:credentials` - Credentials for authenticated endpoints

      ## Example

          # Public endpoint
          {:ok, resp} = MyExchange.request(:get, "/v5/market/custom", params: %{symbol: "BTCUSDT"})

          # Private endpoint
          {:ok, resp} = MyExchange.request(:get, "/v5/account/custom",
            credentials: creds,
            params: %{accountType: "UNIFIED"}
          )

      """
      @spec request(atom(), String.t(), keyword()) ::
              {:ok, CCXT.HTTP.Client.response()} | {:error, CCXT.Error.t()}
      def request(method, path, opts \\ []) do
        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        CCXT.HTTP.Client.request(@ccxt_spec, method, path, opts)
      end

      @doc """
      Makes a raw HTTP request without signing (escape hatch level 3).

      Use this for debugging or when you need full control over the request.
      No signing or error normalization is applied.

      ## Parameters

      - `method` - HTTP method
      - `url` - Full URL to request
      - `headers` - Request headers as list of tuples
      - `body` - Request body (or nil)

      ## Options

      - `:timeout` - Request timeout in milliseconds

      ## Example

          {:ok, resp} = MyExchange.raw_request(
            :get,
            "https://api.exchange.com/v5/market/tickers",
            [{"Content-Type", "application/json"}],
            nil
          )

      """
      @spec raw_request(atom(), String.t(), [{String.t(), String.t()}], String.t() | nil, keyword()) ::
              {:ok, CCXT.HTTP.Client.response()} | {:error, term()}
      def raw_request(method, url, headers, body, opts \\ []) do
        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        CCXT.HTTP.Client.raw_request(method, url, headers, body, opts)
      end
    end
  end

  @doc """
  Generates all endpoint functions from the spec.

  Returns AST for all functions defined in `spec.endpoints`.

  Delegates to `CCXT.Generator.Functions.Endpoints.generate_endpoints/1`.
  """
  @spec generate_endpoints(Spec.t()) :: Macro.t()
  defdelegate generate_endpoints(spec), to: Endpoints

  @doc """
  Generates parser mapping attributes and introspection for the exchange module.

  Returns AST for parser module attributes and `__ccxt_parsers__/0`.

  Delegates to `CCXT.Generator.Functions.Parsers.generate_parsers/1`.
  """
  @spec generate_parsers(Spec.t()) :: Macro.t()
  defdelegate generate_parsers(spec), to: Parsers

  @doc """
  Generates convenience methods that wrap core endpoint functions.

  Returns AST for (if supported by the exchange):
  - `fetch_free_balance/2` - Returns only balance.free
  - `fetch_used_balance/2` - Returns only balance.used
  - `fetch_total_balance/2` - Returns only balance.total
  - `fetch_partial_balance/3` - Returns balance[part]

  These mirror CCXT's convenience methods for partial balance fetching.
  Only generates methods if the exchange supports the underlying endpoint.
  """
  @spec generate_convenience_methods(Spec.t()) :: Macro.t()
  def generate_convenience_methods(spec) do
    # Only generate balance convenience methods if fetch_balance exists AND is authenticated.
    # Some exchanges have public balance endpoints (auth: false) which would have different
    # function signatures. The convenience methods assume the standard authenticated signature.
    fetch_balance_endpoint = Enum.find(spec.endpoints, &(&1[:name] == :fetch_balance))
    has_auth_fetch_balance = fetch_balance_endpoint != nil and fetch_balance_endpoint[:auth] == true

    quote do
      unquote(if has_auth_fetch_balance, do: generate_balance_convenience_methods())
    end
  end

  @doc false
  # Generates AST for fetch_free_balance, fetch_used_balance, fetch_total_balance,
  # and fetch_partial_balance - simple wrappers that call fetch_balance and extract one part
  @spec generate_balance_convenience_methods() :: Macro.t()
  defp generate_balance_convenience_methods do
    quote do
      @doc """
      Fetches only the free (available) balances.

      Calls `fetch_balance/2` and extracts the `free` component.

      ## Example

          {:ok, free} = MyExchange.fetch_free_balance(credentials)
          # => %{"BTC" => 1.5, "USDT" => 10000.0}

      """
      @spec fetch_free_balance(CCXT.Credentials.t(), keyword()) :: {:ok, map()} | {:error, CCXT.Error.t()}
      def fetch_free_balance(credentials, opts \\ []) do
        with {:ok, balance} <- fetch_balance(credentials, opts) do
          {:ok, Map.get(balance, "free", %{})}
        end
      end

      @doc """
      Fetches only the used (locked/reserved) balances.

      Calls `fetch_balance/2` and extracts the `used` component.

      ## Example

          {:ok, used} = MyExchange.fetch_used_balance(credentials)
          # => %{"BTC" => 0.5, "USDT" => 5000.0}

      """
      @spec fetch_used_balance(CCXT.Credentials.t(), keyword()) :: {:ok, map()} | {:error, CCXT.Error.t()}
      def fetch_used_balance(credentials, opts \\ []) do
        with {:ok, balance} <- fetch_balance(credentials, opts) do
          {:ok, Map.get(balance, "used", %{})}
        end
      end

      @doc """
      Fetches only the total balances (free + used).

      Calls `fetch_balance/2` and extracts the `total` component.

      ## Example

          {:ok, total} = MyExchange.fetch_total_balance(credentials)
          # => %{"BTC" => 2.0, "USDT" => 15000.0}

      """
      @spec fetch_total_balance(CCXT.Credentials.t(), keyword()) :: {:ok, map()} | {:error, CCXT.Error.t()}
      def fetch_total_balance(credentials, opts \\ []) do
        with {:ok, balance} <- fetch_balance(credentials, opts) do
          {:ok, Map.get(balance, "total", %{})}
        end
      end

      @doc """
      Fetches a specific part of the balance.

      Calls `fetch_balance/2` and extracts the specified component.

      ## Parameters

      - `credentials` - API credentials
      - `part` - Balance part to fetch: `"free"`, `"used"`, or `"total"`
      - `opts` - Options passed to `fetch_balance/2`

      ## Example

          {:ok, free} = MyExchange.fetch_partial_balance(credentials, "free")
          # => %{"BTC" => 1.5, "USDT" => 10000.0}

      """
      @spec fetch_partial_balance(CCXT.Credentials.t(), String.t(), keyword()) ::
              {:ok, map()} | {:error, CCXT.Error.t()}
      def fetch_partial_balance(credentials, part, opts \\ []) when is_binary(part) do
        with {:ok, balance} <- fetch_balance(credentials, opts) do
          {:ok, Map.get(balance, part, %{})}
        end
      end
    end
  end
end
