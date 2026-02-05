defmodule CCXT.Exchange.Discovery do
  @moduledoc """
  Cross-exchange discovery for capability queries and comparisons.

  Enables querying which exchanges support specific capabilities and comparing
  endpoint configurations across exchanges. Essential for trading bots that
  need to find exchanges supporting their required features.

  ## Usage

      # Find all exchanges supporting funding rates
      exchanges = Discovery.which_support(:fetch_funding_rate)

      # Find exchanges supporting multiple capabilities
      exchanges = Discovery.which_support_all([:fetch_positions, :fetch_funding_rate])

      # Compare capability across exchanges
      Discovery.compare([CCXT.Bybit, CCXT.Binance], :fetch_ticker)

      # List all available capabilities
      Discovery.all_capabilities()

  ## Performance Notes

  - Functions scan loaded modules at runtime (not compile-time)
  - Results are not cached; call sparingly in hot paths
  - For repeated queries, cache results at the application level
  """

  @doc """
  Returns exchange modules supporting a given capability.

  Scans all loaded exchange modules and returns those where `spec.has[capability]`
  is truthy.

  ## Parameters

  - `capability` - Capability atom (e.g., `:fetch_funding_rate`, `:create_order`)

  ## Examples

      iex> exchanges = CCXT.Exchange.Discovery.which_support(:fetch_ticker)
      iex> CCXT.Bybit in exchanges
      true

      iex> exchanges = CCXT.Exchange.Discovery.which_support(:fetch_funding_rate)
      iex> is_list(exchanges)
      true

  """
  @spec which_support(atom()) :: [module()]
  def which_support(capability) when is_atom(capability) do
    Enum.filter(available_exchange_modules(), fn module -> has_capability?(module, capability) end)
  end

  @doc """
  Returns exchanges supporting all given capabilities.

  Useful for finding exchanges that meet multiple requirements simultaneously.

  ## Parameters

  - `capabilities` - List of capability atoms

  ## Examples

      iex> exchanges = CCXT.Exchange.Discovery.which_support_all([:fetch_ticker, :fetch_balance])
      iex> is_list(exchanges)
      true

      # Empty list returns all exchanges
      iex> all = CCXT.Exchange.Discovery.which_support_all([])
      iex> length(all) > 0
      true

  """
  @spec which_support_all([atom()]) :: [module()]
  def which_support_all([]), do: available_exchange_modules()

  def which_support_all(capabilities) when is_list(capabilities) do
    Enum.filter(available_exchange_modules(), fn module ->
      Enum.all?(capabilities, &has_capability?(module, &1))
    end)
  end

  @doc """
  Returns exchanges supporting any of the given capabilities.

  Useful for finding exchanges that meet at least one requirement.

  ## Parameters

  - `capabilities` - List of capability atoms

  ## Examples

      iex> exchanges = CCXT.Exchange.Discovery.which_support_any([:fetch_funding_rate, :fetch_premium_index])
      iex> is_list(exchanges)
      true

  """
  @spec which_support_any([atom()]) :: [module()]
  def which_support_any([]), do: []

  def which_support_any(capabilities) when is_list(capabilities) do
    Enum.filter(available_exchange_modules(), fn module ->
      Enum.any?(capabilities, &has_capability?(module, &1))
    end)
  end

  @doc """
  Compares a capability or endpoint across multiple exchanges.

  Returns a map of exchange module to capability details. Useful for
  understanding differences in how exchanges implement features.

  ## Parameters

  - `modules` - List of exchange modules to compare
  - `capability_or_endpoint` - Capability atom to compare

  ## Examples

      iex> result = CCXT.Exchange.Discovery.compare([CCXT.Bybit, CCXT.Binance], :fetch_ticker)
      iex> is_map(result)
      true

  ## Return Value

  Returns a map where each key is an exchange module and values contain:
  - `:supported` - Whether the capability is supported
  - `:endpoint` - Endpoint details if it's a semantic endpoint
  - `:spec_id` - Exchange ID from spec

  """
  @spec compare([module()], atom()) :: %{module() => map()}
  def compare(modules, capability_or_endpoint) when is_list(modules) and is_atom(capability_or_endpoint) do
    modules
    |> Enum.filter(&exchange_module?/1)
    |> Map.new(fn module ->
      {module, get_capability_details(module, capability_or_endpoint)}
    end)
  end

  @doc """
  Lists all available capabilities across all exchanges.

  Scans all loaded exchange modules and collects all unique capability atoms
  from their specs.

  ## Examples

      iex> capabilities = CCXT.Exchange.Discovery.all_capabilities()
      iex> :fetch_ticker in capabilities
      true

      iex> capabilities = CCXT.Exchange.Discovery.all_capabilities()
      iex> is_list(capabilities)
      true

  """
  @spec all_capabilities() :: [atom()]
  def all_capabilities do
    available_exchange_modules()
    |> Enum.flat_map(&get_capabilities/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns all available exchange modules.

  Scans the `lib/ccxt/exchanges/` directory and returns modules that are
  loaded and have the `__ccxt_spec__/0` function.

  ## Examples

      iex> modules = CCXT.Exchange.Discovery.all_exchanges()
      iex> is_list(modules)
      true

  """
  @spec all_exchanges() :: [module()]
  def all_exchanges do
    available_exchange_modules()
  end

  @doc """
  Returns capability counts across all exchanges.

  Useful for understanding which capabilities are widely supported.

  ## Examples

      iex> counts = CCXT.Exchange.Discovery.capability_counts()
      iex> is_map(counts)
      true

      iex> counts = CCXT.Exchange.Discovery.capability_counts()
      iex> counts[:fetch_ticker] > 0
      true

  """
  @spec capability_counts() :: %{atom() => non_neg_integer()}
  def capability_counts do
    available_exchange_modules()
    |> Enum.flat_map(&get_capabilities/1)
    |> Enum.frequencies()
  end

  @doc """
  Returns exchange IDs for modules supporting a capability.

  Like `which_support/1` but returns exchange ID strings instead of modules.

  ## Examples

      iex> ids = CCXT.Exchange.Discovery.which_support_ids(:fetch_ticker)
      iex> "bybit" in ids or "binance" in ids
      true

  """
  @spec which_support_ids(atom()) :: [String.t()]
  def which_support_ids(capability) when is_atom(capability) do
    capability
    |> which_support()
    |> Enum.map(&get_exchange_id/1)
    |> Enum.filter(&(&1 != nil))
  end

  # ===========================================================================
  # Module Discovery (Runtime)
  # ===========================================================================

  @doc false
  # Discovers available exchange modules by scanning the exchanges directory.
  # Returns only modules that are loaded and have __ccxt_spec__/0.
  @spec available_exchange_modules() :: [module()]
  defp available_exchange_modules do
    exchanges_dir = Path.join([File.cwd!(), "lib", "ccxt", "exchanges"])

    if File.dir?(exchanges_dir) do
      exchanges_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".ex"))
      |> Enum.map(&Path.basename(&1, ".ex"))
      |> Enum.map(fn name ->
        module_name = Macro.camelize(name)
        Module.concat([CCXT, module_name])
      end)
      |> Enum.filter(fn module -> Code.ensure_loaded?(module) and exchange_module?(module) end)
    else
      []
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  @doc false
  @spec has_capability?(module(), atom()) :: boolean()
  defp has_capability?(module, capability) do
    case get_spec(module) do
      nil -> false
      spec -> Map.get(spec.has, capability, false) == true
    end
  end

  @doc false
  @spec get_capabilities(module()) :: [atom()]
  defp get_capabilities(module) do
    case get_spec(module) do
      nil -> []
      spec -> CCXT.Spec.capabilities(spec)
    end
  end

  @doc false
  @spec get_capability_details(module(), atom()) :: map()
  defp get_capability_details(module, capability) do
    case get_spec(module) do
      nil ->
        %{supported: false, spec_id: nil, endpoint: nil}

      spec ->
        supported = Map.get(spec.has, capability, false) == true
        endpoint = find_endpoint(spec, capability)

        %{
          supported: supported,
          spec_id: spec.id,
          endpoint: endpoint
        }
    end
  end

  @doc false
  @spec find_endpoint(CCXT.Spec.t(), atom()) :: map() | nil
  defp find_endpoint(spec, name) do
    Enum.find(spec.endpoints, fn ep -> ep[:name] == name end)
  end

  @doc false
  @spec get_spec(module()) :: CCXT.Spec.t() | nil
  defp get_spec(module) do
    if function_exported?(module, :__ccxt_spec__, 0) do
      module.__ccxt_spec__()
    end
  end

  @doc false
  @spec get_exchange_id(module()) :: String.t() | nil
  defp get_exchange_id(module) do
    case get_spec(module) do
      nil -> nil
      spec -> spec.id
    end
  end

  @doc false
  @spec exchange_module?(module()) :: boolean()
  defp exchange_module?(module) do
    function_exported?(module, :__ccxt_spec__, 0)
  end
end
