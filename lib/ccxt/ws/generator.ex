defmodule CCXT.WS.Generator do
  @moduledoc """
  Macro that generates WebSocket subscription modules from spec files.

  This module generates `watch_*_subscription/2` functions that build
  subscription messages for WebSocket channels. The actual WebSocket
  connection management is handled by a separate GenServer adapter (W6).

  ## Usage

      defmodule CCXT.Bybit.WS do
        use CCXT.WS.Generator, spec: "bybit"
      end

  This generates:
  - Subscription builders for all `watch_*` methods in the spec
  - Introspection functions for pattern and channel info
  - Pure functions returning subscription message maps

  ## Generated Functions

  For each `watch_*` method in `spec.ws.has`:

      watch_ticker_subscription(symbol, opts \\\\ [])
      #=> {:ok, %{channel: "tickers.BTCUSDT", message: %{"op" => "subscribe", ...}}}

      watch_order_book_subscription(symbol, opts \\\\ [])
      watch_trades_subscription(symbol, opts \\\\ [])
      watch_balance_subscription(opts \\\\ [])  # auth required
      watch_orders_subscription(symbol, opts \\\\ [])  # auth required

  ## Return Format

  All subscription functions return:

      {:ok, %{
        channel: String.t(),
        message: map(),
        method: atom(),
        auth_required: boolean()
      }}

  The consumer (GenServer in W6) uses the message for the WebSocket send
  and the channel for routing incoming messages.

  ## Introspection

  - `__ccxt_ws_spec__/0` - WS portion of the spec
  - `__ccxt_ws_pattern__/0` - Subscription pattern atom
  - `__ccxt_ws_channels__/0` - Channel template map

  """

  alias CCXT.Generator.SpecLoader
  alias CCXT.WS.Generator.Adapter
  alias CCXT.WS.Generator.Functions

  @doc false
  # Derives the REST module from the WS module name
  # CCXT.Bybit.WS -> CCXT.Bybit
  @spec derive_rest_module(module()) :: module()
  def derive_rest_module(ws_module) do
    ws_module
    |> Module.split()
    |> List.delete_at(-1)
    |> Module.concat()
  end

  @doc """
  Generates a WebSocket module from a spec file.

  ## Options

  - `:spec` - The exchange ID (e.g., "bybit"). Loads from `priv/specs/{spec}.exs`
  - `:spec_path` - Full path to spec file (alternative to `:spec`)

  ## Example

      defmodule CCXT.Bybit.WS do
        use CCXT.WS.Generator, spec: "bybit"
      end

  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    spec_id = Keyword.get(opts, :spec)
    spec_path = Keyword.get(opts, :spec_path)

    quote do
      alias CCXT.WS.Generator

      require Generator

      Generator.__generate__(unquote(spec_id), unquote(spec_path))
    end
  end

  @doc false
  @spec __generate__(String.t() | nil, String.t() | nil) :: Macro.t()
  defmacro __generate__(spec_id, spec_path) do
    # Resolve spec path at compile time
    resolved_path = SpecLoader.resolve_spec_path(spec_id, spec_path)

    # Load spec at compile time (use same loader as REST)
    spec = SpecLoader.load_and_validate_spec!(resolved_path)

    # Extract WS config (use Map.get for struct access)
    ws_config = Map.get(spec, :ws) || %{}

    # Skip generation if no WS support
    if ws_config == %{} or ws_config == nil do
      quote do
        @moduledoc "WebSocket not supported for this exchange."
        def __ccxt_ws_spec__, do: nil
        def __ccxt_ws_pattern__, do: nil
        def __ccxt_ws_channels__, do: nil
      end
    else
      # Generate moduledoc
      moduledoc = Functions.generate_moduledoc(spec)

      # Derive REST module from WS module name (CCXT.Bybit.WS -> CCXT.Bybit)
      rest_module = derive_rest_module(__CALLER__.module)

      # Generate adapter AST (will be injected as nested module)
      adapter_ast = Adapter.generate_adapter(__CALLER__.module, rest_module, ws_config)

      quote do
        # Track spec file for recompilation
        @external_resource unquote(resolved_path)

        # Suppress Dialyzer for generated functions
        @dialyzer [:no_return, :no_match]

        @moduledoc unquote(moduledoc)

        # Store WS spec as module attribute
        @ws_spec unquote(Macro.escape(ws_config))

        # Generate introspection functions
        unquote(Functions.generate_introspection(ws_config))

        # Generate watch_* subscription functions
        unquote(Functions.generate_watch_functions(ws_config))

        # Generate the Adapter nested module
        defmodule Adapter do
          @moduledoc false
          unquote(adapter_ast)
        end
      end
    end
  end
end
