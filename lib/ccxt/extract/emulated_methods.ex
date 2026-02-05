defmodule CCXT.Extract.EmulatedMethods do
  @moduledoc """
  Loads emulated method sources extracted from CCXT TypeScript files.

  Data source: `priv/extractor/ccxt_emulated_methods.json`.
  """

  # Inline priv path resolution to avoid compile-time dependency on CCXT.Priv
  # (which would cause cascading recompilation of ~200 exchange modules)
  @json_path (case :code.priv_dir(:ccxt_client) do
                {:error, :bad_name} ->
                  [__DIR__, "..", "..", "priv", "extractor/ccxt_emulated_methods.json"] |> Path.join() |> Path.expand()

                priv when is_list(priv) ->
                  Path.join(List.to_string(priv), "extractor/ccxt_emulated_methods.json")
              end)

  @doc "Returns the JSON file path for emulated method extraction."
  @spec path() :: String.t()
  def path, do: @json_path

  @doc """
  Loads the emulated methods JSON with caching.

  Call `reload!/0` to force re-read.
  """
  @spec load() :: map()
  def load do
    case :persistent_term.get({__MODULE__, :data}, :missing) do
      :missing ->
        data = read_json!()
        :persistent_term.put({__MODULE__, :data}, data)
        data

      data ->
        data
    end
  end

  @doc "Reloads the emulated methods JSON (bypassing cache)."
  @spec reload!() :: map()
  def reload! do
    data = read_json!()
    :persistent_term.put({__MODULE__, :data}, data)
    data
  end

  @doc "Returns all exchange IDs with emulated methods."
  @spec exchanges() :: [String.t()]
  def exchanges do
    load()
    |> Map.get("emulated_methods", %{})
    |> Map.keys()
    |> Enum.sort()
  end

  @doc "Returns all emulated method entries for an exchange."
  @spec methods_for(String.t()) :: [map()]
  def methods_for(exchange_id) do
    load()
    |> Map.get("emulated_methods", %{})
    |> Map.get(exchange_id, [])
  end

  @doc "Returns emulated method names for an exchange."
  @spec method_names_for(String.t()) :: [String.t()]
  def method_names_for(exchange_id) do
    exchange_id
    |> methods_for()
    |> Enum.map(&Map.get(&1, "name"))
  end

  @doc "Returns an emulated method entry by name for an exchange."
  @spec method_for(String.t(), String.t()) :: map() | nil
  def method_for(exchange_id, method_name) do
    exchange_id
    |> methods_for()
    |> Enum.find(fn method -> Map.get(method, "name") == method_name end)
  end

  @doc ~s{Returns emulated method entries filtered by scope ("rest" or "ws").}
  @spec methods_for_scope(String.t(), String.t()) :: [map()]
  def methods_for_scope(exchange_id, scope) when is_binary(scope) do
    exchange_id
    |> methods_for()
    |> Enum.filter(fn method -> Map.get(method, "scope") == scope end)
  end

  @doc false
  # Reads and parses the emulated methods JSON file from disk
  defp read_json! do
    @json_path
    |> File.read!()
    |> Jason.decode!()
  end
end
