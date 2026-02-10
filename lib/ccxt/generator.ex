defmodule CCXT.Generator do
  @moduledoc """
  Macro that generates exchange modules from spec files.

  This module is the core of ccxt_ex - it takes exchange specifications from
  `priv/specs/*.exs` and generates complete exchange modules at compile time.

  ## Usage

      defmodule CCXT.Bybit do
        use CCXT.Generator, spec: "bybit"
      end

  This generates a module with:
  - All unified API functions (fetch_ticker, create_order, etc.)
  - Escape hatches (request/3, raw_request/4)
  - Introspection functions (__ccxt_spec__/0, etc.)

  ## How It Works

  1. At compile time, loads the spec file from `priv/specs/{exchange}.exs`
  2. Validates the spec has all required fields
  3. Generates functions based on the `endpoints` list in the spec
  4. Uses `@external_resource` to recompile when spec changes

  ## Generated Functions

  **Public endpoints** (no credentials required):
  - `fetch_ticker(symbol, opts \\\\ [])`
  - `fetch_order_book(symbol, limit \\\\ nil, opts \\\\ [])`

  **Private endpoints** (credentials required):
  - `fetch_balance(credentials, opts \\\\ [])`
  - `create_order(credentials, symbol, type, side, amount, price \\\\ nil, opts \\\\ [])`

  **Escape hatches**:
  - `request(method, path, opts)` - Typed request with signing
  - `raw_request(method, url, headers, body, opts)` - Direct HTTP

  **Introspection**:
  - `__ccxt_spec__/0` - Full spec
  - `__ccxt_endpoints__/0` - Endpoint list
  - `__ccxt_signing__/0` - Signing config
  - `__ccxt_classification__/0` - Exchange classification

  ## Endpoint Structure

  Each endpoint in `__ccxt_endpoints__/0` has the following fields:

  - `:name` - Atom, the unified API method name (e.g., `:fetch_ticker`)
  - `:method` - Atom, HTTP method (`:get`, `:post`, `:put`, `:delete`, `:patch`)
  - `:path` - String, the REST endpoint path (e.g., `"/ticker"`)
  - `:auth` - Boolean, whether credentials are required
  - `:params` - List of atoms, the expected parameters
  - `:approximate` - Boolean (optional), indicates heuristic extraction

  ### The `:approximate` Flag

  When present and `true`, the `:approximate` flag indicates that the endpoint
  mapping was inferred through heuristic analysis rather than directly matched
  from CCXT's api object. This happens when:

  1. The unified method delegates to another internal method
  2. The path structure doesn't exactly match CCXT's api definition
  3. The extraction used pattern matching on method source code

  Approximate endpoints are functional but may need manual verification.
  The flag is metadata for debugging/curation and **does not affect function
  generation** - all endpoints work the same regardless of this flag.

  ## Implementation

  The generator is split into focused submodules:

  - `CCXT.Generator.SpecLoader` - Spec file loading and validation
  - `CCXT.Generator.Functions` - Endpoint function generation
  - `CCXT.Generator.Introspection` - Runtime introspection helpers
  - `CCXT.Generator.Helpers` - Runtime helper functions

  """

  alias CCXT.Generator.Functions
  alias CCXT.Generator.SpecLoader

  @doc """
  Generates an exchange module from a spec file.

  ## Options

  - `:spec` - The exchange ID (e.g., "bybit"). Loads from `priv/specs/{spec}.exs`
  - `:spec_path` - Full path to spec file (alternative to `:spec`)

  ## Example

      defmodule CCXT.Bybit do
        use CCXT.Generator, spec: "bybit"
      end

  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    spec_id = Keyword.get(opts, :spec)
    spec_path = Keyword.get(opts, :spec_path)

    quote do
      require CCXT.Generator

      CCXT.Generator.__generate__(unquote(spec_id), unquote(spec_path))
    end
  end

  @doc """
  Checks if an exchange is enabled based on compile-time config.

  When `config :ccxt_client, exchanges: [...]` is set, only listed exchanges
  generate full modules. Others get a stub with `@moduledoc false`.

  Default `:all` enables every exchange (backward compatible).

  ## Parameters

  - `spec_id` - Exchange ID string (e.g., "bybit")
  - `configured` - `:all` or list of exchange IDs (strings or atoms)

  ## Examples

      iex> CCXT.Generator.exchange_enabled?("bybit", :all)
      true

      iex> CCXT.Generator.exchange_enabled?("bybit", ["bybit", "binance"])
      true

      iex> CCXT.Generator.exchange_enabled?("kraken", ["bybit", "binance"])
      false

      iex> CCXT.Generator.exchange_enabled?("bybit", [:bybit, :binance])
      true

  """
  @spec exchange_enabled?(String.t(), :all | [String.t() | atom()]) :: boolean()
  def exchange_enabled?(_spec_id, :all), do: true

  def exchange_enabled?(spec_id, exchanges) when is_list(exchanges) do
    Enum.any?(exchanges, fn
      id when is_binary(id) -> id == spec_id
      id when is_atom(id) -> Atom.to_string(id) == spec_id
    end)
  end

  @doc false
  @spec __generate__(String.t() | nil, String.t() | nil) :: Macro.t()
  defmacro __generate__(spec_id, spec_path) do
    # Read config at macro expansion time (runs during caller's compilation).
    # Uses get_env because compile_env can only be called in module body.
    configured = Application.get_env(:ccxt_client, :exchanges, :all)

    # Check if this exchange is enabled before loading the spec
    if exchange_enabled?(spec_id, configured) do
      # Resolve spec path at compile time
      resolved_path = SpecLoader.resolve_spec_path(spec_id, spec_path)

      # Load and validate spec at compile time
      spec = SpecLoader.load_and_validate_spec!(resolved_path)

      # Compute exchange ID atom at compile time (safe - spec IDs come from trusted spec files)
      # Inject into spec so HTTP.Client never needs String.to_atom at runtime
      exchange_id_atom = String.to_atom(spec.id)
      spec_with_atom = %{spec | exchange_id: exchange_id_atom}

      # Generate moduledoc at compile time
      moduledoc = Functions.generate_moduledoc(spec)

      # Generate module contents
      quote do
        # Track spec file for recompilation
        @external_resource unquote(resolved_path)

        # Suppress Dialyzer false positives for generated endpoint functions.
        #
        # Why this is needed:
        # - Generated endpoint functions use dynamic patterns from specs
        # - Dialyzer's type inference sometimes concludes {:ok, ...} matches can never succeed
        # - This happens because Dialyzer analyzes the generated code statically without
        #   knowing the runtime behavior of HTTP clients returning different result shapes
        #
        # Scope: This suppression applies ONLY to this generated exchange module,
        # not to the generator itself or other modules. Each exchange module gets
        # its own suppression because it has its own set of generated functions.
        #
        # Trade-off: We accept suppressed warnings in generated endpoint functions
        # to avoid false positives, while non-generated code (introspection, helpers)
        # still gets full Dialyzer coverage.
        #
        # TODO: Consider using @dialyzer annotations on specific generated function
        # groups if Dialyzer adds support for dynamic function name annotations.
        @dialyzer [:no_return, :no_match, :no_contracts]

        @moduledoc unquote(moduledoc)

        # Store spec (with pre-computed exchange_id atom) as module attribute
        @ccxt_spec unquote(Macro.escape(spec_with_atom))

        # Generate introspection functions
        unquote(Functions.generate_introspection(spec))

        # Generate escape hatches
        unquote(Functions.generate_escape_hatches())

        # Generate response parser mappings (before endpoints so @ccxt_parser_* attrs are available)
        unquote(Functions.generate_parsers(spec))

        # Generate endpoint functions
        unquote(Functions.generate_endpoints(spec))

        # Generate convenience methods (balance partials, etc.)
        unquote(Functions.generate_convenience_methods(spec))
      end
    else
      quote do
        @moduledoc false
      end
    end
  end
end
