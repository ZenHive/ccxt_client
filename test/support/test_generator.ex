defmodule CCXT.Test.Generator do
  @moduledoc """
  Macro that generates integration test cases from exchange specs at compile time.

  This follows the pattern established by hand-written integration tests in
  `test/ccxt/exchanges/integration/*_integration_test.exs`, generating equivalent
  test modules automatically from spec data.

  ## Usage

      defmodule CCXT.Exchanges.BybitGeneratedTest do
        use CCXT.Test.Generator, exchange: :bybit
      end

  This generates a test module with:
  - Module tags: `:integration`, `:exchange_bybit`, `:certified_pro`
  - Setup with `setup_credentials/2` using correct options
  - "generated module verification" tests (`@tag :introspection`)
  - "spec introspection" tests (`@tag :introspection`)
  - "signing verification" tests (`@tag :signing`)

  ## Options

  - `:exchange` - The exchange ID atom (e.g., `:bybit`). Required.
  - `:module` - The exchange module (default: `CCXT.{Exchange}`)
  - `:spec_id` - Override spec ID if different from exchange (rare)

  ## Generated Tags

  Each generated test module receives hierarchical tags:

  | Tag | Description |
  |-----|-------------|
  | `@moduletag :integration` | All tests are integration tests |
  | `@moduletag :exchange_{id}` | Exchange-specific tag |
  | `@moduletag :certified_pro` / `:pro` / `:supported` | CCXT classification from spec |
  | `@moduletag :tier1` / `:tier2` / `:tier3` / `:dex` / `:unclassified` | Priority tier |

  Individual test categories receive:

  | Tag | Test Category |
  |-----|---------------|
  | `@tag :introspection` | Module existence, spec validation |
  | `@tag :signing` | Signing verification (offline) |
  | `@tag :public` | Public endpoint tests |
  | `@tag :authenticated` | Private endpoint tests |

  ## Implementation

  The test generator is split into focused submodules:

  - `CCXT.Test.Generator.Config` - Configuration building at compile time
  - `CCXT.Test.Generator.Helpers` - Runtime helper functions for tests
  - `CCXT.Test.Generator.PublicTests` - Public endpoint test generation
  - `CCXT.Test.Generator.AuthenticatedTests` - Authenticated endpoint test generation

  """

  alias CCXT.Test.Generator.AuthenticatedTests
  alias CCXT.Test.Generator.Config
  alias CCXT.Test.Generator.PublicTests
  alias CCXT.Test.Generator.SigningTests

  @doc """
  Generates a test module from an exchange spec.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    exchange = Keyword.fetch!(opts, :exchange)

    quote do
      alias CCXT.Test.Generator

      require Generator

      Generator.__generate__(unquote(exchange), unquote(opts))
    end
  end

  @doc false
  defmacro __generate__(exchange, opts) do
    config = Config.build(exchange, opts)

    quote do
      use ExUnit.Case, async: false

      import CCXT.Test.IntegrationHelper

      alias unquote(config.module_name)

      require Logger

      @moduletag :integration
      @moduletag unquote(config.exchange_tag)
      @moduletag unquote(config.classification_tag)
      @moduletag unquote(config.priority_tier_tag)

      @exchange_id unquote(config.exchange_id)
      @module unquote(config.module_name)
      @credential_opts unquote(Macro.escape(config.credential_opts))
      @signing_pattern unquote(config.signing_pattern)
      @endpoint_names unquote(config.endpoint_names)
      @test_symbol unquote(config.test_symbol)
      @test_params unquote(Macro.escape(config.test_params))
      @public_methods unquote(Macro.escape(config.public_methods))
      @private_methods unquote(Macro.escape(config.private_methods))
      @has_passphrase unquote(config.has_passphrase)
      @default_timeframe unquote(config.default_timeframe)
      @default_derivatives_category unquote(config.default_derivatives_category)
      @default_account_type unquote(config.default_account_type)
      @default_settle_coin unquote(config.default_settle_coin)
      @uses_account_type_param unquote(config.uses_account_type_param)
      @symbol_formats unquote(Macro.escape(config.symbol_formats))
      @endpoint_map unquote(Macro.escape(config.endpoint_map))
      @endpoint_defaults unquote(Macro.escape(config.endpoint_defaults))
      @test_currency unquote(config.test_currency)

      unquote(generate_symbol_resolution_helpers())

      setup_all do
        # Ensure the exchange module is fully loaded before tests run
        Code.ensure_loaded!(@module)

        # Get exchange atom for credential lookups
        exchange_atom = String.to_existing_atom(@exchange_id)

        # Get spec and sandbox URLs map for per-endpoint routing
        spec = @module.__ccxt_spec__()
        sandbox_urls = spec.urls[:sandbox]
        sandbox = Keyword.get(@credential_opts, :sandbox, Keyword.get(@credential_opts, :testnet, false))

        # Default API URL for backward compatibility (used when api_section is nil)
        default_api_url = CCXT.Spec.api_url(spec, sandbox)

        # Get default credentials (for backward compat and single-sandbox exchanges)
        default_credentials = CCXT.Testnet.creds(exchange_atom, :default)

        # Check if this exchange has ANY credentials registered (any sandbox)
        # Tests will individually check for their specific sandbox credentials
        has_authenticated_tests = @private_methods != []
        has_any_credentials = exchange_atom in CCXT.Testnet.exchanges_with_creds()

        if not has_any_credentials and has_authenticated_tests do
          opts_with_url = Keyword.put(@credential_opts, :api_url, default_api_url)
          raise missing_credentials_message(@exchange_id, opts_with_url)
        end

        {:ok,
         exchange_atom: exchange_atom,
         credentials: default_credentials,
         api_url: default_api_url,
         sandbox_urls: sandbox_urls}
      end

      unquote(generate_module_verification_tests())
      unquote(generate_spec_introspection_tests())
      unquote(SigningTests.generate(config.signing_pattern, config.has_passphrase))
      unquote(PublicTests.generate(config.public_methods))
      unquote(AuthenticatedTests.generate(config.private_methods, config.has_passphrase))
    end
  end

  # Generate module verification tests
  defp generate_module_verification_tests do
    quote do
      describe "generated module verification" do
        @tag :introspection
        test "module exists and is loaded" do
          assert Code.ensure_loaded?(@module),
                 "Expected #{inspect(@module)} to be loaded"

          Logger.info("#{inspect(@module)} module loaded successfully")
        end

        @tag :introspection
        test "introspection functions exist" do
          assert function_exported?(@module, :__ccxt_spec__, 0),
                 "Expected #{inspect(@module)}.__ccxt_spec__/0 to exist"

          assert function_exported?(@module, :__ccxt_endpoints__, 0),
                 "Expected #{inspect(@module)}.__ccxt_endpoints__/0 to exist"

          assert function_exported?(@module, :__ccxt_classification__, 0),
                 "Expected #{inspect(@module)}.__ccxt_classification__/0 to exist"

          Logger.info("#{inspect(@module)} has all introspection functions")
        end

        @tag :introspection
        test "generated endpoint functions exist" do
          key_functions = [
            {:fetch_ticker, 2},
            {:fetch_order_book, 3},
            {:fetch_markets, 1}
          ]

          for {func, arity} <- key_functions do
            if func in @endpoint_names do
              assert function_exported?(@module, func, arity),
                     "Expected #{inspect(@module)}.#{func}/#{arity} to exist"
            end
          end

          Logger.info("#{inspect(@module)} has expected endpoint functions")
        end
      end
    end
  end

  # Generate spec introspection tests
  defp generate_spec_introspection_tests do
    quote do
      describe "spec introspection" do
        @tag :introspection
        test "spec returns valid data" do
          spec = @module.__ccxt_spec__()

          assert %CCXT.Spec{} = spec
          assert spec.id == @exchange_id
          assert is_binary(spec.name)
          assert is_map(spec.urls)
          assert is_binary(spec.urls.api)

          Logger.info(
            "Spec: id=#{spec.id}, name=#{spec.name}, " <>
              "api=#{spec.urls.api}"
          )
        end

        @tag :introspection
        test "endpoints list is populated" do
          [first_endpoint | _rest] = endpoints = @module.__ccxt_endpoints__()

          assert is_list(endpoints)

          # Validate first endpoint structure
          assert is_atom(first_endpoint.name), "endpoint name should be atom"
          assert is_atom(first_endpoint.method), "endpoint method should be atom"
          assert is_binary(first_endpoint.path), "path should be string"
          assert is_boolean(first_endpoint.auth), "auth should be boolean"

          # Spot check a few more
          Enum.each(Enum.take(endpoints, 5), fn ep ->
            assert is_atom(ep.name), "endpoint name should be atom"
            assert is_atom(ep.method), "endpoint method should be atom"
            assert is_binary(ep.path), "path should be string"
            assert is_boolean(ep.auth), "auth should be boolean"
          end)

          Logger.info("Spec has #{length(endpoints)} endpoints")
        end

        @tag :introspection
        test "classification returns expected value" do
          classification = @module.__ccxt_classification__()

          # Use Enum.member? to avoid type inference warnings when only one exchange is generated
          valid_classifications = [:certified_pro, :pro, :supported]

          assert Enum.member?(valid_classifications, classification),
                 "classification should be :certified_pro, :pro, or :supported, got: #{inspect(classification)}"

          Logger.info("Exchange classification: #{classification}")
        end
      end
    end
  end

  # Generate helper functions for test symbol resolution
  # Split into focused sub-generators to avoid long quote blocks
  defp generate_symbol_resolution_helpers do
    quote do
      unquote(generate_symbol_resolution_functions())
      unquote(generate_test_opts_functions())
      unquote(generate_sandbox_url_functions())
    end
  end

  # Symbol resolution: gets the RAW exchange market ID (e.g., "PI_XBTUSD") for an endpoint
  # Split into multiple small quote blocks to reduce cyclomatic complexity per block
  defp generate_symbol_resolution_functions do
    quote do
      unquote(generate_symbol_core_functions())
      unquote(generate_symbol_error_functions())
    end
  end

  defp generate_symbol_core_functions do
    quote do
      unquote(generate_symbol_entry_points())
      unquote(generate_symbol_lookup())
    end
  end

  defp generate_symbol_entry_points do
    quote do
      @doc false
      # Main entry point: looks up market_type from endpoint, resolves symbol
      defp test_symbol_for(endpoint_name) do
        market_type = get_endpoint_market_type(endpoint_name)
        resolve_test_symbol(endpoint_name, market_type)
      end

      @doc false
      # Extracts market_type from endpoint metadata (may be nil)
      defp get_endpoint_market_type(endpoint_name) do
        case Map.get(@endpoint_map, endpoint_name) do
          %{market_type: type} -> type
          _ -> nil
        end
      end

      @doc false
      # Lists available market types from symbol_formats (for error messages)
      defp available_market_types do
        @symbol_formats |> Map.keys() |> Enum.filter(&is_atom/1) |> Enum.join(", ")
      end
    end
  end

  defp generate_symbol_lookup do
    quote do
      @doc false
      # No symbol_formats at all - use default test symbol (spot-only exchanges)
      defp resolve_test_symbol(_endpoint_name, _market_type)
           when is_nil(@symbol_formats) or @symbol_formats == %{},
           do: @test_symbol

      @doc false
      # No market_type but symbol_formats exists - FAIL LOUD
      defp resolve_test_symbol(endpoint_name, nil), do: raise_no_market_type_error(endpoint_name)

      @doc false
      # Has market_type - look it up in formats
      defp resolve_test_symbol(endpoint_name, market_type),
        do: lookup_symbol_format(endpoint_name, market_type)

      @doc false
      defp lookup_symbol_format(endpoint_name, market_type) do
        case Map.get(@symbol_formats, market_type) do
          %{id: id} when not is_nil(id) -> id
          %{} -> raise_missing_id_error(endpoint_name, market_type)
          nil -> raise_unknown_market_type_error(endpoint_name, market_type)
        end
      end
    end
  end

  defp generate_symbol_error_functions do
    quote do
      @doc false
      defp raise_missing_id_error(endpoint_name, market_type) do
        raise """
        Missing raw market ID for #{endpoint_name} on #{@exchange_id}

        symbol_formats[#{inspect(market_type)}] exists but has no :id field.

        Fix: Regenerate symbol formats: mix ccxt.sync --check --force --symbols
        """
      end

      @doc false
      defp raise_no_market_type_error(endpoint_name) do
        raise """
        Cannot determine test symbol for #{endpoint_name} on #{@exchange_id}

        Endpoint has market_type: nil
        Available symbol_formats: #{available_market_types()}

        Fix: JS extractor needs to provide market_type for this endpoint.
        """
      end

      @doc false
      defp raise_unknown_market_type_error(endpoint_name, market_type) do
        raise """
        Cannot determine test symbol for #{endpoint_name} on #{@exchange_id}

        Endpoint has market_type: #{inspect(market_type)}
        Available symbol_formats: #{available_market_types()}

        Fix: Either extract #{market_type} format, or fix endpoint's market_type.
        """
      end
    end
  end

  # Test options building: merges endpoint-specific defaults with global test_params
  # Split into smaller quote blocks to reduce cyclomatic complexity
  defp generate_test_opts_functions do
    quote do
      unquote(generate_test_opts_attrs())
      unquote(generate_test_opts_builders())
    end
  end

  defp generate_test_opts_attrs do
    quote do
      # Timestamp params that need freshening - end times get "now", start times get "past"
      @end_timestamp_params ["end_timestamp", "end_time", "to", "endTime"]
      @start_timestamp_params ["start_timestamp", "start_time", "from", "startTime"]
      # Reasonable range for OHLCV and similar historical queries.
      # 2 hours is safe for exchanges with short timeframes (e.g., Gate's 10s = 720 candles < 1000 max)
      @timestamp_lookback_ms to_timeout(hour: 2)

      # Note: Timestamp conversion (ms → seconds) is now handled by the library
      # based on ohlcv_timestamp_resolution extracted into each exchange's spec.
      # See: lib/ccxt/extract/timestamp_resolution.ex
    end
  end

  defp generate_test_opts_builders do
    quote do
      @doc false
      defp build_test_opts(endpoint_name) do
        endpoint_defaults = Map.get(@endpoint_defaults, endpoint_name, %{})
        freshened = freshen_timestamp_params(endpoint_defaults)
        merged = Map.merge(freshened, @test_params)
        if merged == %{}, do: [], else: [params: merged]
      end

      @doc false
      # Replaces stale timestamp values with fresh ones at test runtime.
      defp freshen_timestamp_params(params) when is_map(params) do
        now = System.system_time(:millisecond)
        past = now - @timestamp_lookback_ms
        Map.new(params, fn {k, v} -> freshen_timestamp(k, v, now, past) end)
      end

      defp freshen_timestamp_params(params), do: params

      unquote(generate_freshen_timestamp_clauses())
    end
  end

  defp generate_freshen_timestamp_clauses do
    quote do
      @doc false
      # Freshens individual timestamp param if applicable
      defp freshen_timestamp(k, v, now, _past) when k in @end_timestamp_params and is_number(v),
        do: {k, now}

      defp freshen_timestamp(k, v, _now, past) when k in @start_timestamp_params and is_number(v),
        do: {k, past}

      defp freshen_timestamp(k, v, _now, _past), do: {k, v}
    end
  end

  # Sandbox URL resolution: handles multi-API exchanges with different testnets per API section
  defp generate_sandbox_url_functions do
    quote do
      @doc false
      # Resolves the correct sandbox URL for an endpoint based on its api_section.
      # Returns the per-section URL if available, otherwise falls back to default.
      #
      # Multi-API exchanges (Binance, OKX) have different testnets per API section:
      # - Spot: testnet.binance.vision
      # - Futures: testnet.binancefuture.com
      defp sandbox_url_for(endpoint_name, sandbox_urls, default_url) do
        case Map.get(@endpoint_map, endpoint_name) do
          %{api_section: api_section} when not is_nil(api_section) ->
            lookup_section_url(sandbox_urls, api_section, default_url)

          _ ->
            # No api_section for this endpoint, use default
            default_url
        end
      end

      unquote(generate_lookup_section_url())
      unquote(generate_sandbox_credential_functions())
    end
  end

  @doc false
  # Extracted to reduce cyclomatic complexity
  defp generate_lookup_section_url do
    quote do
      @doc false
      # Look up sandbox URL for a specific API section
      #
      # Fallback chain: api_section → "rest" → "default" → default_url
      # "rest" is a common fallback for single-testnet exchanges (e.g., Deribit)
      # where one URL serves all API sections (public + private)
      defp lookup_section_url(sandbox_urls, api_section, default_url) do
        case sandbox_urls do
          urls when is_map(urls) ->
            Map.get(urls, api_section) ||
              Map.get(urls, "rest") ||
              Map.get(urls, "default") ||
              default_url

          _ ->
            default_url
        end
      end
    end
  end

  # Sandbox credential helpers: multi-credential support for multi-API exchanges
  # Split into multiple quote blocks to reduce cyclomatic complexity
  defp generate_sandbox_credential_functions do
    quote do
      unquote(generate_sandbox_availability_check())
      unquote(generate_sandbox_credential_lookup())
    end
  end

  defp generate_sandbox_availability_check do
    quote do
      unquote(generate_sandbox_check_functions())
      unquote(generate_sandbox_check_helpers())
    end
  end

  defp generate_sandbox_check_functions do
    quote do
      @doc false
      # Checks that a sandbox exists for the endpoint's api_section.
      # Flunks with actionable message if api_section has no sandbox.
      #
      # This handles APIs like Binance SAPI which have no testnet.
      # Without this check, tests would fail with misleading "Invalid Api-Key" errors.
      defp check_sandbox_available!(endpoint_name, sandbox_urls, exchange_id) do
        api_section = get_api_section_for_endpoint(endpoint_name)
        do_check_sandbox_available!(endpoint_name, api_section, sandbox_urls, exchange_id)
      end

      @doc false
      # No api_section for this endpoint - default sandbox is fine
      defp do_check_sandbox_available!(_endpoint_name, nil, _sandbox_urls, _exchange_id), do: :ok

      # sandbox_urls is not a map - can't check, let it fall through
      defp do_check_sandbox_available!(_endpoint_name, _api_section, urls, _exchange_id)
           when not is_map(urls),
           do: :ok

      # Has api_section and map-based sandbox_urls - verify section exists or has fallback
      #
      # Two patterns for exchanges with testnets:
      # 1. Multi-testnet (Binance): separate URLs per api_section (spot, futures, sapi)
      # 2. Single-testnet (Deribit): one URL for all api_sections (rest covers public+private)
      #
      # For single-testnet exchanges, "rest" or "default" is the universal fallback.
      defp do_check_sandbox_available!(endpoint_name, api_section, sandbox_urls, exchange_id) do
        has_section = Map.has_key?(sandbox_urls, api_section)
        has_rest_fallback = Map.has_key?(sandbox_urls, "rest")
        has_default_fallback = Map.has_key?(sandbox_urls, "default")

        if has_section or has_rest_fallback or has_default_fallback do
          :ok
        else
          flunk(no_sandbox_message(endpoint_name, api_section, sandbox_urls, exchange_id))
        end
      end
    end
  end

  defp generate_sandbox_check_helpers do
    quote do
      @doc false
      defp no_sandbox_message(endpoint_name, api_section, sandbox_urls, exchange_id) do
        available = sandbox_urls |> Map.keys() |> Enum.join(", ")

        """
        No sandbox available for api_section '#{api_section}' on #{exchange_id}

        This endpoint (#{endpoint_name}) uses the #{api_section} API, which does not have a testnet.
        Available sandbox API sections: #{available}

        Skipping this test is expected behavior - this API cannot be tested without production credentials.
        """
      end

      @doc false
      # Gets the api_section for an endpoint from endpoint_map
      defp get_api_section_for_endpoint(endpoint_name) do
        case Map.get(@endpoint_map, endpoint_name) do
          %{api_section: section} -> section
          _ -> nil
        end
      end
    end
  end

  defp generate_sandbox_credential_lookup do
    quote do
      @doc false
      # Sets up credentials for an authenticated endpoint test.
      # Handles sandbox availability check, URL routing, and credential lookup.
      # Returns {api_url, credentials} or flunks with actionable message.
      #
      # This is the single entry point for authenticated test credential setup,
      # combining: sandbox check → URL routing → credential lookup → validation
      defp setup_endpoint_credentials!(endpoint_name, exchange_atom, default_url, sandbox_urls) do
        # Check if sandbox exists for this endpoint's api_section
        check_sandbox_available!(endpoint_name, sandbox_urls, @exchange_id)

        # Per-endpoint sandbox URL routing for multi-API exchanges
        api_url = sandbox_url_for(endpoint_name, sandbox_urls, default_url)

        # Look up credentials for this endpoint's sandbox (multi-credential support)
        credentials = get_sandbox_credentials(exchange_atom, api_url)

        if is_nil(credentials) do
          flunk(missing_sandbox_credentials_message(exchange_atom, api_url))
        end

        require_credentials!(credentials, @exchange_id, Keyword.put(@credential_opts, :api_url, api_url))

        {api_url, credentials}
      end

      @doc false
      # Gets credentials for the sandbox that an endpoint routes to.
      # Returns nil if no credentials registered for that sandbox.
      defp get_sandbox_credentials(exchange_atom, sandbox_url) do
        sandbox_key = CCXT.Testnet.sandbox_key_from_url(sandbox_url)
        CCXT.Testnet.creds(exchange_atom, sandbox_key)
      end

      @doc false
      # Returns a skip message for missing sandbox credentials.
      defp missing_sandbox_credentials_message(exchange_atom, sandbox_url) do
        sandbox_key = CCXT.Testnet.sandbox_key_from_url(sandbox_url)
        env_prefix = CCXT.Testnet.env_var_prefix(exchange_atom, sandbox_key)

        """
        No credentials for #{exchange_atom}/#{sandbox_key} sandbox.

        Set these environment variables:
          export #{env_prefix}_API_KEY="your_key"
          export #{env_prefix}_API_SECRET="your_secret"
        """
      end
    end
  end
end
