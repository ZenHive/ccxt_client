defmodule CCXT.Priv do
  @moduledoc """
  Internal module for resolving the priv directory path at runtime.

  Handles runtime resolution when ccxt_ex is used as a dependency.

  ## Important: Compile-time vs Runtime

  This module provides **runtime** functions only. For compile-time paths in module
  attributes, use the inline pattern directly to avoid creating compile-time
  dependencies that cause cascading recompilation:

      # In module attributes, use this pattern directly:
      @json_path (case :code.priv_dir(:ccxt_client) do
                    {:error, :bad_name} ->
                      Path.join([__DIR__, "..", "..", "priv", "extractor/file.json"]) |> Path.expand()
                    priv when is_list(priv) ->
                      Path.join(List.to_string(priv), "extractor/file.json")
                  end)

  Using a macro from this module would create a compile-time dependency, causing
  all modules that use the macro (and their dependents) to recompile when this
  module changes.
  """

  @doc """
  Returns the priv directory path at runtime.

  Works both during development (relative paths) and when installed as a dependency.
  The fallback handles the case where `:code.priv_dir(:ccxt_client)` returns
  `{:error, :bad_name}` at runtime when the app isn't loaded yet.
  """
  @spec dir() :: String.t()
  def dir do
    case :code.priv_dir(:ccxt_client) do
      {:error, :bad_name} ->
        # Fallback: resolve relative to lib/ccxt/ (where this module lives)
        [__DIR__, "..", "..", "priv"] |> Path.join() |> Path.expand()

      priv when is_list(priv) ->
        List.to_string(priv)
    end
  end

  @doc """
  Returns full path to a file in priv directory at runtime.

  ## Examples

      iex> CCXT.Priv.path("extractor/ccxt_method_signatures.json")
      "/path/to/ccxt_ex/priv/extractor/ccxt_method_signatures.json"

  """
  @spec path(String.t()) :: String.t()
  def path(subpath) do
    Path.join(dir(), subpath)
  end
end
