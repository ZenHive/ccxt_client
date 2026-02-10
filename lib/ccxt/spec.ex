# This struct is a comprehensive mapping of CCXT's exchange data - the field count
# is dictated by the external API, not our design choice.
# credo:disable-for-this-file Credo.Check.Warning.StructFieldAmount

defmodule CCXT.Spec do
  @moduledoc """
  Exchange specification struct.

  This is the contract between the CCXT extractor and the generator macro.
  Spec files are stored in `priv/specs/*.exs` and loaded at compile time
  to generate exchange modules.

  ## Fields

  - `id` - Exchange identifier (e.g., "binance", "bybit")
  - `name` - Human-readable name (e.g., "Binance", "Bybit")
  - `countries` - List of country codes where exchange operates
  - `version` - API version string
  - `classification` - Classification (:certified_pro, :pro, or :supported)
  - `urls` - Map of URL types to URLs
  - `rate_limits` - Rate limiting configuration
  - `signing` - Signing pattern configuration
  - `has` - Capabilities map (which methods are supported)
  - `timeframes` - OHLCV timeframe mappings
  - `endpoints` - List of endpoint definitions
  - `error_codes` - Map of error codes to error types
  - `error_code_details` - Map of error codes to type + description

  ## Spec Authoring

  For writing custom exchange specs (e.g., for ccxt_client), see
  `docs/spec-authoring-guide.md`. Key points:

  - Current spec format version: 1
  - Required fields: `:id`, `:name`, `:urls`
  - Use `CCXT.Spec.current_spec_format_version/0` to query the version

  ## Example

      %CCXT.Spec{
        id: "bybit",
        name: "Bybit",
        classification: :certified_pro,
        urls: %{
          api: "https://api.bybit.com",
          sandbox: "https://api-testnet.bybit.com",
          www: "https://www.bybit.com",
          doc: "https://bybit-exchange.github.io/docs/"
        },
        signing: %{
          pattern: :hmac_sha256_headers,
          timestamp_key: "X-BAPI-TIMESTAMP",
          signature_key: "X-BAPI-SIGN",
          api_key_header: "X-BAPI-API-KEY"
        },
        has: %{
          fetch_ticker: true,
          fetch_balance: true,
          create_order: true,
          cancel_order: true
        }
      }

  """

  @current_spec_format_version 1

  @type url_value :: String.t() | map()

  @type url_map :: %{
          required(:api) => url_value(),
          optional(:sandbox) => url_value() | nil,
          optional(:www) => url_value() | nil,
          optional(:doc) => url_value() | [url_value()] | nil,
          optional(:other) => map() | nil
        }

  @type rate_limit :: %{
          optional(:requests) => non_neg_integer(),
          optional(:period) => non_neg_integer(),
          optional(:rolling_window_size) => non_neg_integer(),
          optional(:interval_ms) => non_neg_integer(),
          optional(atom()) => term()
        }

  # Signing config is flexible to accommodate exchange-specific fields.
  # Only :pattern is required. Other common fields include:
  # - api_key_header, signature_header, timestamp_header (header names)
  # - signature_encoding (:hex, :base64)
  # - recv_window, recv_window_header (Binance/Bybit style)
  # - has_passphrase (OKX/KuCoin style)
  @type signing_config :: %{
          required(:pattern) => atom(),
          optional(atom()) => term()
        }

  # Semantic endpoints have required fields plus optional extras (e.g., :approximate)
  @type endpoint :: %{
          required(:name) => atom(),
          required(:method) => atom(),
          required(:path) => String.t(),
          required(:auth) => boolean(),
          required(:params) => [term()],
          optional(atom()) => term()
        }

  # Raw endpoints extracted from CCXT (different structure than semantic endpoints)
  @type raw_endpoint :: %{
          path: String.t(),
          method: atom(),
          auth: boolean(),
          cost: number()
        }

  @type raw_endpoints :: %{
          public: [raw_endpoint()],
          private: [raw_endpoint()]
        }

  @typedoc "Capability values from CCXT describe().has"
  @type capability_value :: boolean() | String.t() | atom() | nil

  @typedoc "Capabilities map (unified method support flags)"
  @type capabilities :: %{atom() => capability_value()}

  # Per-market-type format (spot, swap, option may have different separators/symbols)
  # e.g., Binance spot: "" separator = "BTCUSDT"
  #       Binance options: "-" separator = "BTC-250103-100000-C"
  @type market_type_format :: %{
          required(:separator) => String.t(),
          required(:case) => :upper | :lower | :mixed,
          required(:sample) => String.t()
        }

  # Symbol formats per market type (Task 76: market-type-aware extraction)
  # Includes precision data from Task 68
  # Note: 'swap' = perpetual futures, 'future' = expiring futures
  @type symbol_formats :: %{
          optional(:spot) => map(),
          optional(:swap) => map(),
          optional(:future) => map(),
          optional(:option) => map(),
          # Task 68: Precision handling (from primary market)
          optional(:precision_mode) => non_neg_integer(),
          optional(:sample_precision) => map(),
          optional(:sample_limits) => map(),
          optional(atom()) => term()
        }

  # Symbol pattern detection result (R5: detected from symbol_formats samples)
  # Used for static to_exchange_id/2 conversion without loadMarkets()
  @type pattern_config :: %{
          pattern: atom() | nil,
          separator: String.t(),
          case: :upper | :lower | :mixed,
          date_format: atom() | nil,
          suffix: String.t() | nil,
          component_order: [atom() | String.t()] | nil
        }

  @type symbol_patterns :: %{
          optional(:spot) => pattern_config(),
          optional(:swap) => pattern_config(),
          optional(:future) => pattern_config(),
          optional(:option) => pattern_config()
        }

  # Legacy symbol format (deprecated, use symbol_formats instead)
  # Kept for backward compatibility with existing specs
  @type symbol_format :: %{
          required(:separator) => String.t(),
          required(:case) => :upper | :lower | :mixed,
          optional(:precision_mode) => non_neg_integer(),
          optional(:sample_market) => String.t(),
          optional(:sample_precision) => map(),
          optional(:sample_limits) => map()
        }

  # Order mappings describe how exchange formats order types and sides (Task 66)
  # e.g., Binance: :uppercase = "limit" → "LIMIT", "buy" → "BUY"
  #       Bybit: :capitalize = "limit" → "Limit", "buy" → "Buy"
  #       OKX: :lowercase = "limit" → "limit", "buy" → "buy"
  @type order_mappings :: %{
          optional(:side_format) => :uppercase | :lowercase | :capitalize | nil,
          optional(:side_key) => String.t() | nil,
          optional(:type_format) => :uppercase | :lowercase | :capitalize | nil,
          optional(:type_key) => String.t() | nil
        }

  # WebSocket configuration types (Phase 4)
  # See docs/ws-generator-architecture.md for full documentation

  @typedoc "Flexible WS URL - string or nested map of any depth (Bybit: 3+ levels)"
  @type ws_url_value :: String.t() | map()

  @typedoc "WebSocket URL configuration (legacy, for derived specs after W4)"
  @type ws_urls :: %{
          public: %{atom() => String.t()} | String.t(),
          private: String.t()
        }

  @typedoc """
  WebSocket authentication configuration.

  ## Patterns (W11)

  | Pattern | Exchanges | Description |
  |---------|-----------|-------------|
  | `:direct_hmac_expiry` | Bybit, Bitmex | GET/realtime + expires, op: "auth" |
  | `:iso_passphrase` | OKX, Bitget | ISO timestamp + passphrase |
  | `:jsonrpc_linebreak` | Deribit | JSON-RPC with linebreak payload |
  | `:sha384_nonce` | Bitfinex | AUTH + nonce with SHA384 |
  | `:sha512_newline` | Gate | Newline-separated with SHA512 |
  | `:listen_key` | Binance | REST pre-auth for listen key |
  | `:rest_token` | Kraken | REST pre-auth for token |
  | `:inline_subscribe` | Coinbase | Auth in subscribe messages |

  """
  @type ws_auth_config :: %{
          optional(:pattern) => atom(),
          optional(:algorithm) => atom() | String.t() | nil,
          optional(:encoding) => atom() | String.t() | nil,
          optional(:payload_format) => String.t(),
          optional(:message_format) => atom() | String.t(),
          optional(:op_field) => String.t(),
          optional(:op_value) => String.t(),
          optional(:timestamp_unit) => atom() | String.t() | nil,
          optional(:expires_offset_ms) => non_neg_integer(),
          optional(:requires_passphrase) => boolean(),
          optional(:pre_auth) => map(),
          optional(atom()) => term()
        }

  @typedoc "WebSocket heartbeat configuration"
  @type ws_heartbeat_config :: %{
          optional(:type) => atom(),
          optional(:interval) => non_neg_integer() | nil,
          optional(:message) => map() | nil
        }

  @typedoc "WebSocket message pattern detected from ws_raw"
  @type ws_message_pattern :: %{
          required(:format) => atom(),
          optional(:kind_field) => String.t(),
          optional(:kind_value) => String.t(),
          optional(:id_field) => String.t(),
          optional(:args_field) => String.t(),
          optional(:keys) => [String.t()],
          optional(:element_keys) => [String.t()],
          optional(:sources) => [atom()]
        }

  @typedoc "WebSocket message pattern list"
  @type ws_message_patterns :: [ws_message_pattern()]

  @typedoc "WebSocket subscription pattern"
  @type ws_subscription_pattern :: atom()

  @typedoc "WebSocket configuration (derived after W4 - requires subscription_pattern)"
  @type ws_config :: %{
          required(:urls) => ws_url_value(),
          required(:subscription_pattern) => ws_subscription_pattern(),
          required(:subscription_config) => map(),
          optional(:sandbox_urls) => ws_url_value(),
          optional(:auth) => ws_auth_config(),
          optional(:heartbeat) => ws_heartbeat_config(),
          optional(:message_patterns) => ws_message_patterns(),
          optional(:channels) => %{atom() => String.t()},
          optional(:has) => %{atom() => capability_value()},
          optional(:channel_templates) => map(),
          optional(:watch_methods) => [String.t() | atom()],
          optional(:hostname) => String.t(),
          optional(:test_urls) => ws_url_value(),
          optional(:demo_urls) => ws_url_value()
        }

  @typedoc """
  Raw WebSocket configuration from CCXT Pro describe().

  Phase 1 (W1): Captures raw data only. No filtering, no pattern detection.
  Subscription patterns and auth are derived in later phases (W4, W11).

  ## URL Structure Patterns (varies by exchange)

  - **Flat string**: OKX, Deribit → `"wss://ws.okx.com:8443/ws/v5"`
  - **Nested map**: Bybit → `%{public: %{spot: "wss://...", linear: "wss://..."}, private: %{...}}`

  ## Fields

  - `urls` - Production WS URLs (string or nested map)
  - `test_urls` - Testnet WS URLs
  - `demo_urls` - Demo trading WS URLs
  - `streaming` - Keep-alive interval and ping config
  - `options` - WS-specific options from describe().options.ws
  - `has` - watch* capabilities (including false/nil to document unsupported)
  - `hostname` - Default hostname for URL interpolation
  """
  @type ws_raw_config :: %{
          optional(:urls) => ws_url_value(),
          optional(:test_urls) => ws_url_value(),
          optional(:demo_urls) => ws_url_value(),
          optional(:streaming) => %{optional(:keep_alive) => non_neg_integer()},
          optional(:options) => map(),
          optional(:has) => %{atom() => capability_value()},
          optional(:hostname) => String.t(),
          # Derived fields present in some extracted specs (mixed raw+derived)
          optional(:auth) => ws_auth_config(),
          optional(:subscription_pattern) => ws_subscription_pattern(),
          optional(:subscription_config) => map(),
          optional(:message_patterns) => ws_message_patterns(),
          optional(:channel_templates) => map(),
          optional(:watch_methods) => [String.t() | atom()]
        }

  @typedoc "Required credentials configuration"
  @type required_credentials :: %{
          api_key: boolean(),
          secret: boolean(),
          password: boolean(),
          uid: boolean()
        }

  @typedoc "Fee tier entry (volume-based fee schedule)"
  @type fee_tier :: %{
          volume: number(),
          fee: number()
        }

  @typedoc "Trading fee configuration"
  @type trading_fees :: %{
          optional(:maker) => number(),
          optional(:taker) => number(),
          optional(:tier_based) => boolean(),
          optional(:percentage) => boolean(),
          optional(:fee_side) => String.t(),
          optional(:tiers) => %{maker: [fee_tier()], taker: [fee_tier()]}
        }

  @typedoc "Funding fee configuration (withdraw/deposit fees by currency)"
  @type funding_fees :: %{
          optional(:tier_based) => boolean(),
          optional(:percentage) => boolean(),
          optional(:withdraw) => %{String.t() => number()},
          optional(:deposit) => %{String.t() => number()}
        }

  @typedoc "Market-type specific fee configuration"
  @type market_type_fees :: %{
          optional(:trading) => trading_fees()
        }

  @typedoc "Fee configuration (Task 106b: all 77 CCXT fee paths)"
  @type fees :: %{
          optional(:trading) => trading_fees(),
          optional(:funding) => funding_fees(),
          optional(:spot) => trading_fees() | market_type_fees(),
          optional(:swap) => trading_fees() | market_type_fees(),
          optional(:future) => trading_fees() | market_type_fees(),
          optional(:option) => trading_fees() | market_type_fees(),
          optional(:linear) => market_type_fees(),
          optional(:inverse) => market_type_fees(),
          optional(:tier_based) => boolean()
        }

  # Task 16c: Complete CCXT Metadata Extraction types

  @typedoc "Exception mappings (error code -> error type atom)"
  @type exceptions :: %{
          optional(:exact) => %{String.t() => atom()},
          optional(:broad) => %{String.t() => atom()},
          optional(:http) => %{integer() => atom()}
        }

  @typedoc "Detailed error code entry including type and description"
  @type error_code_detail :: %{
          type: atom(),
          description: String.t() | nil
        }

  @typedoc "Detailed error code mappings (error code -> detail map)"
  @type error_code_details :: %{(String.t() | integer()) => error_code_detail()}

  @typedoc """
  Parse method metadata extracted from CCXT TypeScript sources.

  This is the raw parse* method entry captured by
  `priv/extractor/extract-parse-methods.cjs`.
  """
  @type parse_method :: %{optional(String.t()) => term()}

  @typedoc "Parse method metadata for an exchange."
  @type parse_methods :: [parse_method()]

  @typedoc "Features configuration by market type"
  @type features :: %{
          optional(:default) => map(),
          optional(:spot) => map(),
          optional(:swap) => map(),
          optional(:future) => map(),
          optional(:option) => map(),
          optional(:margin) => map()
        }

  @typedoc "Exchange options configuration"
  @type options :: %{
          # String fields
          optional(:default_type) => String.t(),
          optional(:default_sub_type) => String.t(),
          optional(:default_settle) => String.t(),
          optional(:default_network) => String.t(),
          optional(:default_time_in_force) => String.t(),
          optional(:broker_id) => String.t(),
          # Number fields
          optional(:recv_window) => non_neg_integer(),
          optional(:time_difference) => integer(),
          # Boolean fields
          optional(:adjust_for_time_difference) => boolean(),
          optional(:sandbox_mode) => boolean(),
          optional(:create_market_buy_order_requires_price) => boolean(),
          # Map fields
          optional(:networks) => %{String.t() => String.t()},
          optional(:networks_by_id) => %{String.t() => String.t()},
          optional(:default_networks) => %{String.t() => String.t()},
          optional(:accounts_by_type) => %{String.t() => String.t()},
          optional(:accounts_by_id) => %{String.t() => String.t()},
          optional(:broker) => map(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @typedoc "Extended metadata"
  @type extended_metadata :: %{
          optional(:logo_url) => String.t(),
          optional(:fees_url) => String.t(),
          optional(:referral_url) => String.t(),
          optional(:referral_discount) => number(),
          optional(:precision_mode) => integer(),
          optional(:padding_mode) => integer(),
          optional(:timeout_ms) => integer(),
          optional(:dex) => boolean(),
          optional(:limits) => map(),
          optional(atom()) => term()
        }

  # Task 16d: HTTP client configuration
  @typedoc "HTTP client configuration for exchanges requiring specific headers/user agents"
  @type http_config :: %{
          optional(:headers) => %{String.t() => String.t()},
          optional(:user_agent) => String.t(),
          optional(:alias) => boolean(),
          optional(:comment) => String.t()
        }

  # Task 37: Body-level error response detection
  @typedoc """
  Response error detection configuration.

  Exchanges often return HTTP 200 with error information in the body.
  This config tells the HTTP client how to detect such errors.

  ## Pattern Types

  - `:success_code` - Error if code field != expected success values (Bybit, OKX, KuCoin)
  - `:error_present` - Error if specific field exists (Gate.io, Deribit)
  - `:error_array` - Error if array field is non-empty (Kraken)
  - `:error_field_present` - Error if field exists; success has no such field (Binance)

  ## Examples

      # Bybit: retCode must be "0"
      %{type: :success_code, field: "retCode", success_values: ["0"],
        code_field: "retCode", message_field: "retMsg"}

      # Gate.io: error if "label" field exists
      %{type: :error_present, field: "label",
        code_field: "label", message_field: "message"}

      # Kraken: error if "error" array non-empty
      %{type: :error_array, field: "error", message_field: "error"}

      # Binance: error if "code" field present
      %{type: :error_field_present, field: "code",
        code_field: "code", message_field: "msg"}
  """
  @type response_error_config :: %{
          required(:type) => atom(),
          required(:field) => String.t() | [String.t()] | atom() | [atom()],
          optional(:success_values) => [String.t() | atom() | integer()],
          optional(:code_field) => String.t() | [String.t()] | atom() | [atom()],
          optional(:message_field) => String.t() | [String.t()] | atom() | [atom()]
        }

  @typedoc "OHLCV timestamp resolution - whether exchange expects milliseconds or seconds"
  @type ohlcv_timestamp_resolution :: :milliseconds | :seconds | :unknown

  @typedoc "URL strategy pattern detection result"
  @type url_strategy :: %{
          optional(:pattern) => atom() | nil,
          optional(:prefix) => String.t() | nil,
          optional(:detected_from) => atom() | String.t() | nil,
          optional(:note) => String.t() | nil
        }

  @typedoc "Extraction metadata (when/how spec was extracted)"
  @type extracted_metadata :: %{
          optional(:ccxt_version) => String.t() | nil,
          optional(:extracted_at) => String.t() | nil,
          optional(atom()) => term()
        }

  @typedoc "Endpoint extraction statistics"
  @type endpoint_extraction_stats :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          exchange_id: atom() | nil,
          name: String.t(),
          countries: [String.t()] | nil,
          version: String.t() | nil,
          classification: :certified_pro | :pro | :supported,
          urls: url_map(),
          rate_limits: rate_limit() | nil,
          signing: signing_config() | nil,
          has: capabilities(),
          timeframes: %{String.t() => String.t()} | nil,
          symbol_format: symbol_format() | nil,
          symbol_formats: symbol_formats() | nil,
          symbol_patterns: symbol_patterns() | nil,
          order_mappings: order_mappings() | nil,
          currency_aliases: %{String.t() => String.t()},
          required_credentials: required_credentials() | nil,
          fees: fees() | nil,
          endpoints: [endpoint()],
          raw_endpoints: raw_endpoints() | nil,
          error_codes: %{(String.t() | integer()) => atom()},
          error_code_details: error_code_details(),
          parse_methods: parse_methods(),
          ws: ws_raw_config() | ws_config() | nil,
          # Task 16c: Complete metadata extraction
          exceptions: exceptions() | nil,
          features: features() | nil,
          options: options() | nil,
          extended_metadata: extended_metadata() | nil,
          # Task 16d: HTTP client configuration
          http_config: http_config() | nil,
          # Task 37: Body-level error response detection
          response_error: response_error_config() | nil,
          # OHLCV timestamp resolution (ms vs seconds)
          ohlcv_timestamp_resolution: ohlcv_timestamp_resolution(),
          # Task 26: Parameter mappings (symbol → instId, etc.)
          param_mappings: map() | nil,
          # Task 26: Path prefix for API versioning (e.g., "/api/v5" for OKX)
          path_prefix: String.t(),
          # New fields for complete CCXT data passthrough
          # Exchange metadata (previously lost after SpecBuilder)
          certified: boolean() | nil,
          pro: boolean() | nil,
          dex: boolean() | nil,
          status: map() | nil,
          enable_rate_limit: boolean(),
          # Options variants
          exchange_options: map() | nil,
          # Full market data (for reference/introspection)
          currencies: map() | nil,
          markets: map() | nil,
          # URL pattern detection metadata
          url_strategy: url_strategy() | nil,
          # Extraction metadata
          extracted_metadata: extracted_metadata() | nil,
          endpoint_extraction_stats: endpoint_extraction_stats() | nil,
          # Additional CCXT fields
          comment: String.t() | nil,
          requires_eddsa: boolean() | nil,
          quote_json_numbers: boolean() | nil,
          handle_content_type_application_zip: boolean() | nil,
          # Raw API param requirements (keep raw structure)
          api_param_requirements: map() | nil,
          # Error handler source (for debugging/analysis)
          handle_errors_source: String.t() | nil,
          # Spec format version for migration support
          spec_format_version: pos_integer()
        }

  @enforce_keys [:id, :name, :urls]
  defstruct [
    :id,
    :exchange_id,
    :name,
    :version,
    :signing,
    :rate_limits,
    :raw_endpoints,
    :symbol_format,
    :symbol_formats,
    :symbol_patterns,
    :order_mappings,
    :required_credentials,
    :fees,
    :ws,
    # Task 16c: Complete metadata extraction
    :exceptions,
    :features,
    :options,
    :extended_metadata,
    # Task 16d: HTTP client configuration
    :http_config,
    # Task 37: Body-level error response detection
    :response_error,
    # OHLCV timestamp resolution (ms vs seconds)
    :ohlcv_timestamp_resolution,
    # Task 26: Parameter mappings (symbol → instId, etc.)
    :param_mappings,
    # New fields for complete CCXT data passthrough
    # Exchange metadata (previously lost after SpecBuilder)
    :certified,
    :pro,
    :dex,
    :status,
    # Options variants
    :exchange_options,
    # Full market data (for reference/introspection)
    :currencies,
    :markets,
    # URL pattern detection metadata
    :url_strategy,
    # Extraction metadata
    :extracted_metadata,
    :endpoint_extraction_stats,
    # Additional CCXT fields
    :comment,
    :requires_eddsa,
    :quote_json_numbers,
    :handle_content_type_application_zip,
    # Raw API param requirements (keep raw structure)
    :api_param_requirements,
    # Error handler source (for debugging/analysis)
    :handle_errors_source,
    # Task 26: Path prefix for API versioning (e.g., "/api/v5" for OKX)
    path_prefix: "",
    countries: [],
    classification: :supported,
    urls: %{},
    has: %{},
    timeframes: %{},
    currency_aliases: %{},
    endpoints: [],
    error_codes: %{},
    error_code_details: %{},
    parse_methods: [],
    # Defaults for new fields
    enable_rate_limit: true,
    # Spec format version for migration support
    spec_format_version: @current_spec_format_version
  ]

  @doc """
  Returns the current spec format version.

  Used by the extractor to stamp new specs and by `load!/1` to validate
  that specs aren't from a newer (unsupported) format version.
  """
  @spec current_spec_format_version() :: pos_integer()
  def current_spec_format_version, do: @current_spec_format_version

  @doc """
  Loads a spec from a file path.

  The file should contain an Elixir term that can be evaluated to a Spec struct.
  Specs are migrated to the current format version at load time.

  Note: This function uses `Code.eval_file/1` which is safe here because paths
  are hardcoded at compile time from the library's own `priv/specs/` directory,
  not from user input.
  """
  # sobelow_skip ["RCE.CodeModule"]
  @spec load!(Path.t()) :: t()
  def load!(path) do
    {spec, _bindings} = Code.eval_file(path)

    case spec do
      %__MODULE__{} = s -> migrate(s)
      map when is_map(map) -> map |> from_map() |> migrate()
      _ -> raise ArgumentError, "Invalid spec file: #{path}"
    end
  end

  @doc """
  Creates a Spec from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: get_required(map, :id),
      name: get_required(map, :name),
      countries: Map.get(map, :countries, []),
      version: Map.get(map, :version),
      classification: Map.get(map, :classification, :supported),
      urls: get_required(map, :urls),
      rate_limits: Map.get(map, :rate_limits),
      signing: Map.get(map, :signing),
      has: Map.get(map, :has, %{}),
      timeframes: Map.get(map, :timeframes, %{}),
      symbol_format: Map.get(map, :symbol_format),
      symbol_formats: Map.get(map, :symbol_formats),
      symbol_patterns: Map.get(map, :symbol_patterns),
      order_mappings: Map.get(map, :order_mappings),
      currency_aliases: Map.get(map, :currency_aliases, %{}),
      required_credentials: Map.get(map, :required_credentials),
      fees: Map.get(map, :fees),
      endpoints: Map.get(map, :endpoints, []),
      raw_endpoints: Map.get(map, :raw_endpoints),
      error_codes: Map.get(map, :error_codes, %{}),
      error_code_details: Map.get(map, :error_code_details, %{}),
      parse_methods: Map.get(map, :parse_methods, []),
      ws: Map.get(map, :ws),
      # Task 16c: Complete metadata extraction
      exceptions: Map.get(map, :exceptions),
      features: Map.get(map, :features),
      options: Map.get(map, :options),
      extended_metadata: Map.get(map, :extended_metadata),
      # Task 16d: HTTP client configuration
      http_config: Map.get(map, :http_config),
      # Task 37: Body-level error response detection
      response_error: Map.get(map, :response_error),
      # OHLCV timestamp resolution (ms vs seconds) - defaults to :milliseconds
      ohlcv_timestamp_resolution: Map.get(map, :ohlcv_timestamp_resolution, :milliseconds),
      # Task 26: Parameter mappings (symbol → instId, etc.)
      param_mappings: Map.get(map, :param_mappings),
      # Task 26: Path prefix for API versioning (defaults to "" for exchanges without versioned paths)
      path_prefix: Map.get(map, :path_prefix, ""),
      # New fields for complete CCXT data passthrough
      # Exchange metadata (previously lost after SpecBuilder)
      certified: Map.get(map, :certified),
      pro: Map.get(map, :pro),
      dex: Map.get(map, :dex),
      status: Map.get(map, :status),
      enable_rate_limit: Map.get(map, :enable_rate_limit, true),
      # Options variants
      exchange_options: Map.get(map, :exchange_options),
      # Full market data (for reference/introspection)
      currencies: Map.get(map, :currencies),
      markets: Map.get(map, :markets),
      # URL pattern detection metadata
      url_strategy: Map.get(map, :url_strategy),
      # Extraction metadata
      extracted_metadata: Map.get(map, :extracted_metadata),
      endpoint_extraction_stats: Map.get(map, :endpoint_extraction_stats),
      # Additional CCXT fields
      comment: Map.get(map, :comment),
      requires_eddsa: Map.get(map, :requires_eddsa),
      quote_json_numbers: Map.get(map, :quote_json_numbers),
      handle_content_type_application_zip: Map.get(map, :handle_content_type_application_zip),
      # Raw API param requirements (keep raw structure)
      api_param_requirements: Map.get(map, :api_param_requirements),
      # Error handler source (for debugging/analysis)
      handle_errors_source: Map.get(map, :handle_errors_source),
      # Spec format version (defaults to 1 for backward compatibility)
      spec_format_version: Map.get(map, :spec_format_version, @current_spec_format_version)
    }
  end

  @doc """
  Returns the API URL for the spec, respecting sandbox mode.

  ## Usage

  - `api_url(spec, false)` - Returns production API URL
  - `api_url(spec, true)` - Returns default sandbox URL (backward compatible)
  - `api_url(spec, "fapiPrivate")` - Returns sandbox URL for specific api_section

  Multi-API exchanges (Binance, OKX) have different testnets per API section:
  - Spot endpoints → testnet.binance.vision
  - Futures endpoints → testnet.binancefuture.com

  The api_section parameter enables per-endpoint sandbox routing.
  """
  @spec api_url(t(), boolean() | String.t()) :: String.t() | nil
  def api_url(spec, sandbox_or_section \\ false)

  def api_url(%__MODULE__{urls: urls}, false), do: Map.fetch!(urls, :api)

  def api_url(%__MODULE__{urls: urls}, true) do
    # Legacy: boolean true = use default sandbox
    case urls[:sandbox] do
      sandbox when is_binary(sandbox) ->
        sandbox

      sandbox when is_map(sandbox) ->
        # For map-based sandbox URLs, prefer "default" or common fallbacks
        sandbox["default"] || sandbox["rest"] || sandbox["private"] || sandbox["public"] ||
          Map.fetch!(urls, :api)

      _ ->
        Map.fetch!(urls, :api)
    end
  end

  def api_url(%__MODULE__{urls: urls}, api_section) when is_binary(api_section) do
    # New: specific api_section = look up in sandbox map
    case urls[:sandbox] do
      sandbox when is_map(sandbox) ->
        sandbox[api_section] || sandbox["default"]

      sandbox when is_binary(sandbox) ->
        # Legacy single URL applies to all sections
        sandbox

      _ ->
        # No sandbox URL available
        nil
    end
  end

  @doc """
  Checks if the exchange supports a given capability.
  """
  @spec has?(t(), atom()) :: boolean()
  def has?(%__MODULE__{has: has}, capability) when is_atom(capability) do
    Map.get(has, capability, false)
  end

  @doc """
  Returns the list of supported capabilities.
  """
  @spec capabilities(t()) :: [atom()]
  def capabilities(%__MODULE__{has: has}) do
    has
    |> Enum.filter(fn {_k, v} -> v end)
    |> Enum.map(fn {k, _v} -> k end)
    |> Enum.sort()
  end

  defp get_required(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "Missing required field: #{key}"
    end
  end

  @doc false
  # Migrates a spec to the current format version.
  # v1 is the current version - passthrough.
  # Future versions will chain: v1→v2, v2→v3, etc.
  @spec migrate(t()) :: t()
  defp migrate(%__MODULE__{spec_format_version: @current_spec_format_version} = spec), do: spec

  defp migrate(%__MODULE__{spec_format_version: v}) when v > @current_spec_format_version do
    raise ArgumentError,
          "Spec format version #{v} is newer than supported version #{@current_spec_format_version}. " <>
            "Upgrade ccxt_ex to load this spec."
  end

  defp migrate(%__MODULE__{spec_format_version: v}) do
    raise ArgumentError,
          "Invalid spec format version: #{inspect(v)}. " <>
            "Expected a positive integer <= #{@current_spec_format_version}."
  end

  # ===========================================================================
  # Features Helper Functions (Task 107)
  # ===========================================================================

  @doc """
  Returns features for a specific market type.

  Features include capabilities, numeric limits, and nested configs organized
  by market type (spot, swap, future, option, margin).

  ## Parameters

  - `spec` - The exchange specification
  - `market_type` - Market type atom (:spot, :swap, :future, :option, :margin)

  ## Examples

      iex> CCXT.Spec.features_for_market(spec, :spot)
      %{
        fetch_my_trades: %{limit: 1000},
        margin_mode: false,
        trigger_price: true,
        time_in_force: %{ioc: true, fok: true, gtc: true}
      }

      iex> CCXT.Spec.features_for_market(spec, :unknown)
      nil

  """
  @spec features_for_market(t(), atom()) :: map() | nil
  def features_for_market(%__MODULE__{features: nil}, _market_type), do: nil

  def features_for_market(%__MODULE__{features: features}, market_type) when is_atom(market_type) do
    Map.get(features, market_type)
  end

  @doc """
  Returns the list of supported market types from features.

  ## Examples

      iex> CCXT.Spec.supported_market_types(spec)
      [:spot, :swap, :future]

  """
  @spec supported_market_types(t()) :: [atom()]
  def supported_market_types(%__MODULE__{features: nil}), do: []

  def supported_market_types(%__MODULE__{features: features}) when is_map(features) do
    features
    |> Map.keys()
    |> Enum.filter(&is_atom/1)
    |> Enum.sort()
  end

  @doc """
  Returns a specific feature value for a market type.

  Useful for checking numeric limits like `fetchMyTrades.limit: 1000`.

  ## Parameters

  - `spec` - The exchange specification
  - `market_type` - Market type atom (:spot, :swap, etc.)
  - `feature_key` - Feature key atom (e.g., :fetch_my_trades)

  ## Examples

      iex> CCXT.Spec.feature_value(spec, :spot, :fetch_my_trades)
      %{limit: 1000}

      iex> CCXT.Spec.feature_value(spec, :spot, :margin_mode)
      false

  """
  @spec feature_value(t(), atom(), atom()) :: term()
  def feature_value(%__MODULE__{features: nil}, _market_type, _feature_key), do: nil

  def feature_value(%__MODULE__{features: features}, market_type, feature_key) do
    features
    |> Map.get(market_type, %{})
    |> Map.get(feature_key)
  end

  # ===========================================================================
  # Fee Helper Functions (Task 107)
  # ===========================================================================

  @doc """
  Returns trading fees configuration.

  Returns the base trading fee structure including maker/taker rates,
  tier-based flag, and fee tiers if available.

  ## Examples

      iex> CCXT.Spec.trading_fees(spec)
      %{
        maker: 0.001,
        taker: 0.002,
        tier_based: true,
        percentage: true,
        fee_side: "quote",
        tiers: %{maker: [...], taker: [...]}
      }

      iex> CCXT.Spec.trading_fees(spec_without_fees)
      nil

  """
  @spec trading_fees(t()) :: trading_fees() | nil
  def trading_fees(%__MODULE__{fees: nil}), do: nil
  def trading_fees(%__MODULE__{fees: fees}), do: Map.get(fees, :trading)

  @doc """
  Returns fee tiers (volume-based fee schedules).

  Returns the tiers map containing maker and taker fee schedules
  based on trading volume.

  ## Examples

      iex> CCXT.Spec.fee_tiers(spec)
      %{
        maker: [%{volume: 0, fee: 0.001}, %{volume: 10000, fee: 0.0008}],
        taker: [%{volume: 0, fee: 0.002}, %{volume: 10000, fee: 0.0015}]
      }

  """
  @spec fee_tiers(t()) :: %{maker: [fee_tier()], taker: [fee_tier()]} | nil
  def fee_tiers(%__MODULE__{fees: nil}), do: nil

  def fee_tiers(%__MODULE__{fees: fees}) do
    case Map.get(fees, :trading) do
      nil -> nil
      trading -> Map.get(trading, :tiers)
    end
  end

  @doc """
  Returns fees for a specific market type.

  Some exchanges have different fee structures for different market types
  (spot, swap, future, option, linear, inverse).

  ## Examples

      iex> CCXT.Spec.fees_for_market(spec, :spot)
      %{maker: 0.001, taker: 0.002}

      iex> CCXT.Spec.fees_for_market(spec, :swap)
      %{trading: %{maker: 0.0002, taker: 0.0005}}

  """
  @spec fees_for_market(t(), atom()) :: map() | nil
  def fees_for_market(%__MODULE__{fees: nil}, _market_type), do: nil

  def fees_for_market(%__MODULE__{fees: fees}, market_type) when is_atom(market_type) do
    Map.get(fees, market_type)
  end

  @doc """
  Returns the maker fee rate.

  Checks trading fees first, then falls back to market-type specific fees.

  ## Examples

      iex> CCXT.Spec.maker_fee(spec)
      0.001

      iex> CCXT.Spec.maker_fee(spec, :swap)
      0.0002

  """
  @spec maker_fee(t(), atom() | nil) :: float() | nil
  def maker_fee(spec, market_type \\ nil)

  def maker_fee(%__MODULE__{fees: nil}, _market_type), do: nil

  def maker_fee(%__MODULE__{fees: fees}, nil) do
    get_in(fees, [:trading, :maker])
  end

  def maker_fee(%__MODULE__{fees: fees} = spec, market_type) do
    # Try market-type specific first, fall back to base trading fees
    case get_in(fees, [market_type, :maker]) do
      nil ->
        case get_in(fees, [market_type, :trading, :maker]) do
          nil -> maker_fee(spec, nil)
          fee -> fee
        end

      fee ->
        fee
    end
  end

  @doc """
  Returns the taker fee rate.

  Checks trading fees first, then falls back to market-type specific fees.

  ## Examples

      iex> CCXT.Spec.taker_fee(spec)
      0.002

      iex> CCXT.Spec.taker_fee(spec, :swap)
      0.0005

  """
  @spec taker_fee(t(), atom() | nil) :: float() | nil
  def taker_fee(spec, market_type \\ nil)

  def taker_fee(%__MODULE__{fees: nil}, _market_type), do: nil

  def taker_fee(%__MODULE__{fees: fees}, nil) do
    get_in(fees, [:trading, :taker])
  end

  def taker_fee(%__MODULE__{fees: fees} = spec, market_type) do
    # Try market-type specific first, fall back to base trading fees
    case get_in(fees, [market_type, :taker]) do
      nil ->
        case get_in(fees, [market_type, :trading, :taker]) do
          nil -> taker_fee(spec, nil)
          fee -> fee
        end

      fee ->
        fee
    end
  end
end
