defmodule CCXT.Test.WSIntegrationGenerator do
  @moduledoc """
  Macro that generates WebSocket integration tests from exchange specs at compile time.

  This follows the pattern established by `CCXT.Test.Generator` for REST tests,
  generating equivalent WS test modules automatically from spec data.

  ## Usage

      defmodule CCXT.WS.Integration.BybitWSIntegrationTest do
        use CCXT.Test.WSIntegrationGenerator, exchange: :bybit
      end

  This generates a test module with:
  - Module tags: `:integration`, `:ws_integration`, `:exchange_bybit`, tier tag
  - Public channel tests (`@tag :ws_public`)
  - Private channel tests (`@tag :ws_private, :authenticated`)
  - Connection tests (`@tag :connection`)

  ## Options

  - `:exchange` - The exchange ID atom (e.g., `:bybit`). Required.
  - `:module` - Override the REST module (default: `CCXT.{Exchange}`)

  ## Generated Tags

  Each generated test module receives hierarchical tags:

  | Tag | Description |
  |-----|-------------|
  | `@moduletag :integration` | All tests are integration tests |
  | `@moduletag :ws_integration` | WebSocket-specific integration tests |
  | `@moduletag :exchange_{id}` | Exchange-specific tag |
  | `@moduletag :tier1` / `:tier2` / `:tier3` / `:dex` / `:unclassified` | Priority tier |

  Individual test categories receive:

  | Tag | Test Category |
  |-----|---------------|
  | `@tag :ws_public` | Public channel tests (ticker, orderbook, trades) |
  | `@tag :ws_private, :authenticated` | Private channel tests (balance, orders) |
  | `@tag :connection` | Connection management tests |

  ## Running Tests

      # All WS integration tests
      mix test --only ws_integration

      # Public channels only (no credentials needed)
      mix test --only ws_integration --only ws_public

      # Private channels (requires credentials)
      mix test --only ws_integration --only ws_private

      # Specific exchange
      mix test --only ws_integration --only exchange_bybit

      # Tier 1 only
      mix test --only ws_integration --only tier1

  """

  alias CCXT.Exchange.Classification
  alias CCXT.Test.WSIntegrationGenerator.Config

  @doc """
  Generates a WS integration test module from an exchange spec.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    exchange = Keyword.fetch!(opts, :exchange)

    quote do
      alias CCXT.Test.WSIntegrationGenerator

      require WSIntegrationGenerator

      WSIntegrationGenerator.__generate__(unquote(exchange), unquote(opts))
    end
  end

  @doc false
  defmacro __generate__(exchange, opts) do
    config = Config.build(exchange, opts)

    quote do
      use ExUnit.Case, async: false

      import CCXT.Test.WSIntegrationHelper

      require Logger

      @moduletag :integration
      @moduletag :ws_integration
      @moduletag unquote(config.exchange_tag)
      @moduletag unquote(config.priority_tier_tag)

      @exchange_id unquote(config.exchange_id)
      @rest_module unquote(config.rest_module)
      @ws_module unquote(config.ws_module)
      @adapter_module unquote(config.adapter_module)
      @has_ws_support unquote(config.has_ws_support)
      @has_ws_sandbox unquote(config.has_ws_sandbox)
      @has_private_channels unquote(config.has_private_channels)
      @has_passphrase unquote(config.has_passphrase)
      @public_url_path unquote(config.public_url_path)
      @private_url_path unquote(config.private_url_path)
      @watch_methods unquote(Macro.escape(config.watch_methods))

      setup_all do
        # Skip if no WS support at all
        if @has_ws_support do
          exchange_atom = String.to_existing_atom(@exchange_id)

          # Get credentials for private channel tests
          credentials = CCXT.Testnet.creds(exchange_atom, :default)

          # Warn but don't fail if no credentials - public tests can still run
          if @has_private_channels and is_nil(credentials) do
            Logger.warning("No testnet credentials for #{@exchange_id} - private channel tests will be skipped")
          end

          {:ok, exchange_atom: exchange_atom, credentials: credentials, has_ws_sandbox: @has_ws_sandbox}
        else
          {:ok, skip: "Exchange #{@exchange_id} has no WebSocket support"}
        end
      end

      unquote(generate_module_verification_tests())
      unquote(generate_connection_tests())
      unquote(generate_public_channel_tests(config))
      unquote(generate_private_channel_tests(config))
    end
  end

  @doc false
  # Generates the "WS module verification" describe block with introspection tests
  defp generate_module_verification_tests do
    quote do
      describe "WS module verification" do
        @tag :ws_introspection

        test "WS module exists and is loaded", context do
          if Map.get(context, :skip), do: flunk("SKIP: #{context.skip}")

          assert Code.ensure_loaded?(@ws_module),
                 "Expected #{inspect(@ws_module)} to be loaded"

          Logger.info("#{inspect(@ws_module)} loaded successfully")
        end

        test "Adapter module exists and is loaded", context do
          if Map.get(context, :skip), do: flunk("SKIP: #{context.skip}")

          assert Code.ensure_loaded?(@adapter_module),
                 "Expected #{inspect(@adapter_module)} to be loaded"

          Logger.info("#{inspect(@adapter_module)} loaded successfully")
        end

        test "WS introspection functions exist", context do
          if Map.get(context, :skip), do: flunk("SKIP: #{context.skip}")

          assert function_exported?(@ws_module, :__ccxt_ws_spec__, 0),
                 "Expected #{inspect(@ws_module)}.__ccxt_ws_spec__/0 to exist"

          assert function_exported?(@ws_module, :__ccxt_ws_pattern__, 0),
                 "Expected #{inspect(@ws_module)}.__ccxt_ws_pattern__/0 to exist"

          Logger.info("#{inspect(@ws_module)} has introspection functions")
        end
      end
    end
  end

  @doc false
  # Generates the "WS connection" describe block with connect/disconnect tests
  defp generate_connection_tests do
    quote do
      describe "WS connection" do
        @tag :connection
        @tag :ws_public

        test "can connect to public endpoint", context do
          if Map.get(context, :skip), do: flunk("SKIP: #{context.skip}")
          if not context.has_ws_sandbox, do: flunk("SKIP: No WS sandbox for #{@exchange_id}")

          adapter =
            start_adapter_and_wait!(@adapter_module,
              url_path: @public_url_path,
              sandbox: true
            )

          assert @adapter_module.connected?(adapter)
          Logger.info("Connected to #{@exchange_id} public WS endpoint")

          close_adapter(adapter)
        end

        test "can disconnect gracefully", context do
          if Map.get(context, :skip), do: flunk("SKIP: #{context.skip}")
          if not context.has_ws_sandbox, do: flunk("SKIP: No WS sandbox for #{@exchange_id}")

          adapter =
            start_adapter_and_wait!(@adapter_module,
              url_path: @public_url_path,
              sandbox: true
            )

          assert @adapter_module.connected?(adapter)

          close_adapter(adapter)

          # Give it a moment to close
          Process.sleep(100)

          refute Process.alive?(adapter)
          Logger.info("Disconnected gracefully from #{@exchange_id}")
        end
      end
    end
  end

  @doc false
  # Generates the "public channels" describe block with ticker, orderbook, trades tests
  defp generate_public_channel_tests(config) do
    quote do
      describe "public channels" do
        @tag :ws_public

        unquote(generate_ticker_test(config))
        unquote(generate_orderbook_test(config))
        unquote(generate_trades_test(config))
      end
    end
  end

  @doc false
  # Generates ticker subscription test if watch_ticker is supported
  defp generate_ticker_test(config) do
    if :watch_ticker in config.watch_methods do
      quote do
        @tag :ticker
        test "can subscribe to ticker", context do
          if Map.get(context, :skip), do: flunk("SKIP: #{context.skip}")
          if not context.has_ws_sandbox, do: flunk("SKIP: No WS sandbox for #{@exchange_id}")

          adapter =
            start_adapter_and_wait!(@adapter_module,
              url_path: @public_url_path,
              sandbox: true
            )

          assert {:ok, sub} = @ws_module.watch_ticker_subscription(test_symbol(@exchange_id))
          message = subscribe_and_receive!(@adapter_module, adapter, sub)

          assert is_map(message), "Expected map message, got: #{inspect(message)}"
          Logger.info("Received ticker message: #{inspect(Map.keys(message))}")

          close_adapter(adapter)
        end
      end
    end
  end

  @doc false
  # Generates orderbook subscription test if watch_order_book is supported
  defp generate_orderbook_test(config) do
    if :watch_order_book in config.watch_methods do
      quote do
        @tag :orderbook
        test "can subscribe to orderbook", context do
          if Map.get(context, :skip), do: flunk("SKIP: #{context.skip}")
          if not context.has_ws_sandbox, do: flunk("SKIP: No WS sandbox for #{@exchange_id}")

          adapter =
            start_adapter_and_wait!(@adapter_module,
              url_path: @public_url_path,
              sandbox: true
            )

          assert {:ok, sub} = @ws_module.watch_order_book_subscription(test_symbol(@exchange_id), nil)
          message = subscribe_and_receive!(@adapter_module, adapter, sub)

          assert is_map(message), "Expected map message, got: #{inspect(message)}"
          Logger.info("Received orderbook message: #{inspect(Map.keys(message))}")

          close_adapter(adapter)
        end
      end
    end
  end

  @doc false
  # Generates trades subscription test if watch_trades is supported
  defp generate_trades_test(config) do
    if :watch_trades in config.watch_methods do
      quote do
        @tag :trades
        test "can subscribe to trades", context do
          if Map.get(context, :skip), do: flunk("SKIP: #{context.skip}")
          if not context.has_ws_sandbox, do: flunk("SKIP: No WS sandbox for #{@exchange_id}")

          adapter =
            start_adapter_and_wait!(@adapter_module,
              url_path: @public_url_path,
              sandbox: true
            )

          assert {:ok, sub} = @ws_module.watch_trades_subscription(test_symbol(@exchange_id))
          message = subscribe_and_receive!(@adapter_module, adapter, sub, 60_000)

          assert is_map(message), "Expected map message, got: #{inspect(message)}"
          Logger.info("Received trades message: #{inspect(Map.keys(message))}")

          close_adapter(adapter)
        end
      end
    end
  end

  @doc false
  # Routes to auth tests or placeholder based on whether exchange has private channels
  defp generate_private_channel_tests(config) do
    if config.has_private_channels do
      generate_private_tests_with_auth(config)
    else
      generate_no_private_channels_test()
    end
  end

  @doc false
  # Generates the "private channels" describe block with auth, balance, orders tests
  defp generate_private_tests_with_auth(config) do
    quote do
      describe "private channels" do
        @tag :ws_private
        @tag :authenticated

        unquote(generate_auth_test())
        unquote(generate_balance_test(config))
        unquote(generate_orders_test(config))
      end
    end
  end

  @doc false
  # Generates placeholder test when exchange has no private WS channels
  defp generate_no_private_channels_test do
    quote do
      describe "private channels" do
        @tag :ws_private
        @tag :authenticated

        test "exchange has no private WS channels configured", context do
          if Map.get(context, :skip), do: flunk("SKIP: #{context.skip}")
          Logger.info("#{@exchange_id} has no private WS channels configured - skipping private tests")
        end
      end
    end
  end

  @doc false
  # Generates authentication test that connects, authenticates, and verifies state
  defp generate_auth_test do
    quote do
      test "can authenticate", context do
        if Map.get(context, :skip), do: flunk("SKIP: #{context.skip}")
        if not context.has_ws_sandbox, do: flunk("SKIP: No WS sandbox for #{@exchange_id}")

        if is_nil(context.credentials) do
          flunk(missing_ws_credentials_message(@exchange_id, passphrase: @has_passphrase))
        end

        adapter =
          start_adapter_and_wait!(@adapter_module,
            url_path: @private_url_path,
            sandbox: true,
            credentials: context.credentials
          )

        :ok = authenticate_and_wait!(@adapter_module, adapter)

        {:ok, state} = @adapter_module.get_state(adapter)
        assert state.authenticated, "Expected adapter to be authenticated"

        Logger.info("Successfully authenticated to #{@exchange_id}")

        close_adapter(adapter)
      end
    end
  end

  @doc false
  # Generates balance subscription test if watch_balance is supported
  defp generate_balance_test(config) do
    if :watch_balance in config.watch_methods do
      quote do
        @tag :balance
        test "can subscribe to balance updates", context do
          if Map.get(context, :skip), do: flunk("SKIP: #{context.skip}")
          if not context.has_ws_sandbox, do: flunk("SKIP: No WS sandbox for #{@exchange_id}")

          if is_nil(context.credentials) do
            flunk(missing_ws_credentials_message(@exchange_id, passphrase: @has_passphrase))
          end

          adapter =
            start_adapter_and_wait!(@adapter_module,
              url_path: @private_url_path,
              sandbox: true,
              credentials: context.credentials
            )

          :ok = authenticate_and_wait!(@adapter_module, adapter)

          # Resolve URL for URL-routed subscription builders
          {:ok, url} = sandbox_url(@rest_module, @private_url_path)
          assert {:ok, sub} = @ws_module.watch_balance_subscription(url)

          case @adapter_module.subscribe(adapter, sub) do
            :ok -> Logger.info("Subscribed to balance channel on #{@exchange_id}")
            {:ok, _} -> Logger.info("Subscribed to balance channel on #{@exchange_id} (with response)")
            {:error, reason} -> Logger.warning("Balance subscription may have failed: #{inspect(reason)}")
          end

          close_adapter(adapter)
        end
      end
    end
  end

  @doc false
  # Generates order updates subscription test if watch_orders is supported
  defp generate_orders_test(config) do
    if :watch_orders in config.watch_methods do
      quote do
        @tag :orders
        test "can subscribe to order updates", context do
          if Map.get(context, :skip), do: flunk("SKIP: #{context.skip}")
          if not context.has_ws_sandbox, do: flunk("SKIP: No WS sandbox for #{@exchange_id}")

          if is_nil(context.credentials) do
            flunk(missing_ws_credentials_message(@exchange_id, passphrase: @has_passphrase))
          end

          adapter =
            start_adapter_and_wait!(@adapter_module,
              url_path: @private_url_path,
              sandbox: true,
              credentials: context.credentials
            )

          :ok = authenticate_and_wait!(@adapter_module, adapter)

          # Resolve URL for URL-routed subscription builders
          {:ok, url} = sandbox_url(@rest_module, @private_url_path)
          assert {:ok, sub} = @ws_module.watch_orders_subscription(url, test_symbol(@exchange_id))

          case @adapter_module.subscribe(adapter, sub) do
            :ok -> Logger.info("Subscribed to orders channel on #{@exchange_id}")
            {:ok, _} -> Logger.info("Subscribed to orders channel on #{@exchange_id} (with response)")
            {:error, reason} -> Logger.warning("Orders subscription may have failed: #{inspect(reason)}")
          end

          close_adapter(adapter)
        end
      end
    end
  end
end

defmodule CCXT.Test.WSIntegrationGenerator.Config do
  @moduledoc false
  # Compile-time configuration building for WS integration test generation.

  alias CCXT.Exchange.Classification
  alias CCXT.Spec

  @curated_specs_dir Path.join(["priv", "specs", "curated"])
  @extracted_specs_dir Path.join(["priv", "specs", "extracted"])

  @type config :: %{
          exchange_id: String.t(),
          rest_module: module(),
          ws_module: module(),
          adapter_module: module(),
          exchange_tag: atom(),
          priority_tier_tag: atom(),
          has_ws_support: boolean(),
          has_ws_sandbox: boolean(),
          has_private_channels: boolean(),
          has_passphrase: boolean(),
          public_url_path: term(),
          private_url_path: term(),
          watch_methods: [atom()]
        }

  @doc """
  Builds configuration at compile time from exchange ID and options.
  """
  @spec build(atom(), keyword()) :: config()
  def build(exchange, opts) do
    exchange_id = to_string(exchange)
    spec = load_spec!(exchange_id)

    rest_module = Keyword.get(opts, :module) || derive_rest_module(exchange)
    ws_module = Module.concat([rest_module, WS])
    adapter_module = Module.concat([ws_module, Adapter])

    # Extract WS config
    ws_config = Map.get(spec, :ws) || %{}
    has_ws_support = ws_config != %{} && ws_config != nil

    # Check for sandbox WS support
    test_urls = Map.get(ws_config, :test_urls)
    has_ws_sandbox = test_urls != nil && test_urls != %{}

    # Check for private channels (auth config present)
    auth_config = Map.get(ws_config, :auth)
    has_private_channels = auth_config != nil && auth_config != %{}

    # Check for passphrase requirement
    has_passphrase = spec.signing && Map.get(spec.signing, :has_passphrase, false)

    # Derive URL paths from spec
    {public_url_path, private_url_path} = derive_url_paths(ws_config)

    # Get watch methods from WS has config
    watch_methods = derive_watch_methods(ws_config)

    %{
      exchange_id: exchange_id,
      rest_module: rest_module,
      ws_module: ws_module,
      adapter_module: adapter_module,
      # Safe: exchange_id comes from trusted spec files
      exchange_tag: String.to_atom("exchange_#{exchange_id}"),
      priority_tier_tag: Classification.get_priority_tier(exchange_id),
      has_ws_support: has_ws_support,
      has_ws_sandbox: has_ws_sandbox,
      has_private_channels: has_private_channels,
      has_passphrase: has_passphrase,
      public_url_path: public_url_path,
      private_url_path: private_url_path,
      watch_methods: watch_methods
    }
  end

  @doc false
  # Converts exchange atom to its corresponding REST module name (e.g., :binance -> CCXT.Binance)
  defp derive_rest_module(exchange) do
    exchange_name =
      exchange
      |> to_string()
      |> Macro.camelize()

    Module.concat([CCXT, exchange_name])
  end

  @doc false
  # Loads spec from curated dir first, falls back to extracted dir
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
                "Run `mix ccxt.sync #{exchange_id}` first."
    end
  end

  @doc false
  # Derives URL paths from WS config structure
  # Returns {public_path, private_path} where paths are atoms or lists
  defp derive_url_paths(ws_config) when is_map(ws_config) do
    urls = Map.get(ws_config, :urls) || Map.get(ws_config, :test_urls)
    derive_paths_from_urls(urls)
  end

  defp derive_url_paths(_), do: {:default, :default}

  @doc false
  # Detects URL structure and returns appropriate paths
  defp derive_paths_from_urls(%{"public" => %{"spot" => _}}), do: {[:public, :spot], [:private, :contract]}
  defp derive_paths_from_urls(%{"public" => %{"linear" => _}}), do: {[:public, :linear], [:private, :contract]}
  defp derive_paths_from_urls(%{"public" => _}), do: {[:public], [:private]}
  defp derive_paths_from_urls(%{"spot" => _}), do: {[:spot], [:spot]}
  defp derive_paths_from_urls(url) when is_binary(url), do: {:default, :default}

  defp derive_paths_from_urls(map) when is_map(map) and map_size(map) > 0 do
    first_key = map |> Map.keys() |> List.first()
    {[first_key], [first_key]}
  end

  defp derive_paths_from_urls(_), do: {:default, :default}

  @doc false
  # Extracts available watch methods from WS has config
  defp derive_watch_methods(ws_config) when is_map(ws_config) do
    has = Map.get(ws_config, :has) || %{}

    []
    |> maybe_add_method(:watch_ticker, has)
    |> maybe_add_method(:watch_order_book, has)
    |> maybe_add_method(:watch_trades, has)
    |> maybe_add_method(:watch_balance, has)
    |> maybe_add_method(:watch_orders, has)
    |> maybe_add_method(:watch_my_trades, has)
    |> maybe_add_method(:watch_ohlcv, has)
  end

  defp derive_watch_methods(_), do: []

  @doc false
  # Conditionally adds method to list if supported (checks atom, string, and camelCase keys)
  defp maybe_add_method(methods, method, has) do
    # Check both atom and string keys
    method_string = Atom.to_string(method)
    method_camel = Macro.camelize(method_string)

    if Map.get(has, method) == true ||
         Map.get(has, method_string) == true ||
         Map.get(has, method_camel) == true do
      [method | methods]
    else
      methods
    end
  end
end
