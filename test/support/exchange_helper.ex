defmodule CCXT.Test.ExchangeHelper do
  @moduledoc """
  Helper functions for dynamically discovering available exchanges in tests.

  This enables tests to work with whatever exchanges are currently generated,
  supporting `--only` mode where only a subset of exchanges are available.
  """

  alias CCXT.Exchange.Classification
  alias CCXT.Sync.Paths

  @doc """
  Returns the first available spec file path, or nil if none exist.

  Checks both curated and extracted directories.
  """
  @spec first_available_spec_path() :: String.t() | nil
  def first_available_spec_path do
    curated_path = Path.join([File.cwd!(), "priv", "specs", "curated"])
    extracted_path = Path.join([File.cwd!(), "priv", "specs", "extracted"])

    curated_specs = list_spec_files(curated_path)
    extracted_specs = list_spec_files(extracted_path)

    case curated_specs ++ extracted_specs do
      [first | _] -> first
      [] -> nil
    end
  end

  @doc """
  Returns all available spec file paths.
  """
  @spec all_available_spec_paths() :: [String.t()]
  def all_available_spec_paths do
    curated_path = Path.join([File.cwd!(), "priv", "specs", "curated"])
    extracted_path = Path.join([File.cwd!(), "priv", "specs", "extracted"])

    list_spec_files(curated_path) ++ list_spec_files(extracted_path)
  end

  @doc """
  Returns the first available generated WS module, or nil if none exist.
  """
  @spec first_available_ws_module() :: module() | nil
  def first_available_ws_module do
    case available_ws_modules() do
      [first | _] -> first
      [] -> nil
    end
  end

  @doc """
  Returns all available generated WS modules.
  """
  @spec available_ws_modules() :: [module()]
  def available_ws_modules do
    ws_dir = Path.join([File.cwd!(), "lib", "ccxt", "ws", "generated"])

    if File.dir?(ws_dir) do
      ws_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".ex"))
      |> Enum.map(&Path.basename(&1, ".ex"))
      |> Enum.map(&module_name_from_file/1)
      |> Enum.filter(&Code.ensure_loaded?/1)
    else
      []
    end
  end

  @doc """
  Returns the first available generated REST exchange module, or nil if none exist.
  """
  @spec first_available_exchange_module() :: module() | nil
  def first_available_exchange_module do
    case available_exchange_modules() do
      [first | _] -> first
      [] -> nil
    end
  end

  @doc """
  Returns all available generated REST exchange modules.
  """
  @spec available_exchange_modules() :: [module()]
  def available_exchange_modules do
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
      |> Enum.filter(&Code.ensure_loaded?/1)
    else
      []
    end
  end

  @doc """
  Extracts the exchange ID from a spec file path.

  ## Examples

      iex> CCXT.Test.ExchangeHelper.exchange_id_from_path("/path/to/some_exchange.exs")
      "some_exchange"

  """
  @spec exchange_id_from_path(String.t()) :: String.t()
  def exchange_id_from_path(path) do
    path
    |> Path.basename()
    |> Path.rootname()
  end

  @doc """
  Returns the first available exchange ID (string), or nil if none exist.

  Checks the Classification module for available exchanges.
  """
  @spec first_available_exchange_id() :: String.t() | nil
  def first_available_exchange_id do
    List.first(Classification.all_exchanges())
  end

  @doc """
  Returns all available exchange IDs (strings).
  """
  @spec all_available_exchange_ids() :: [String.t()]
  def all_available_exchange_ids do
    Classification.all_exchanges()
  end

  @doc """
  Returns true when the last sync was a full --all run.

  Tests use this to decide whether to enforce strict completeness checks.
  """
  @spec strict_exchange_tests?() :: boolean()
  def strict_exchange_tests? do
    # Paths module is only available in ccxt_ex (not ccxt_client)
    # Use Function.capture to avoid compile-time warning about undefined module
    if Code.ensure_loaded?(Paths) do
      fun = Function.capture(Paths, :sync_state_path, 0)
      path = fun.()
      strict_exchange_tests?(path)
    else
      false
    end
  end

  @doc false
  @spec strict_exchange_tests?(String.t()) :: boolean()
  def strict_exchange_tests?(path) do
    case File.read(path) do
      {:ok, contents} -> String.trim(contents) == "all"
      {:error, _} -> false
    end
  end

  # Private helpers

  defp list_spec_files(dir) do
    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".exs"))
      |> Enum.map(&Path.join(dir, &1))
    else
      []
    end
  end

  defp module_name_from_file(filename) do
    module_name = Macro.camelize(filename)
    Module.concat([CCXT, WS, Generated, module_name])
  end
end
