defmodule CCXT.Generator.SpecLoader do
  @moduledoc """
  Compile-time spec loading and resolution for the generator.

  This module handles finding, loading, and validating exchange spec files
  at compile time. It's used internally by `CCXT.Generator`.
  """

  alias CCXT.Spec
  alias CCXT.Spec.Validator

  @doc """
  Resolves the path to a spec file.

  Checks curated specs first (hand-written Certified Pro), then extracted specs.

  ## Parameters

  - `spec_id` - Exchange ID (e.g., "bybit")
  - `spec_path` - Full path override (optional)

  ## Returns

  Absolute path to the spec file.
  """
  @spec resolve_spec_path(String.t() | nil, String.t() | nil) :: String.t()
  def resolve_spec_path(spec_id, spec_path) do
    cond do
      spec_path ->
        Path.expand(spec_path)

      spec_id ->
        priv_dir = find_priv_dir()

        # Check curated/ first (hand-written Certified Pro specs), then extracted/ (auto-generated)
        curated_path = Path.join([priv_dir, "specs", "curated", "#{spec_id}.exs"])
        extracted_path = Path.join([priv_dir, "specs", "extracted", "#{spec_id}.exs"])

        cond do
          File.exists?(curated_path) -> curated_path
          File.exists?(extracted_path) -> extracted_path
          true -> curated_path
        end

      true ->
        raise ArgumentError, "CCXT.Generator requires either :spec or :spec_path option"
    end
  end

  @doc """
  Loads and validates a spec from the given path.

  Raises `CompileError` if the file doesn't exist or validation fails.
  """
  @spec load_and_validate_spec!(String.t()) :: Spec.t()
  def load_and_validate_spec!(path) do
    if !File.exists?(path) do
      raise CompileError,
        description: "Spec file not found: #{path}",
        file: path,
        line: 1
    end

    spec = Spec.load!(path)
    Validator.validate!(spec, path)
    spec
  end

  @doc """
  Finds the priv directory for the ccxt_ex library.

  Works both during development (relative paths) and when installed as a dependency.
  Delegates to `CCXT.Priv.dir/0` which handles the fallback for compile-time resolution.

  Note: This is safe to call `CCXT.Priv.dir/0` here because this function is invoked
  at runtime during macro expansion (when `use CCXT.Generator` is processed), not as
  a module attribute. The distinction matters because module attributes create
  compile-time dependencies that cause cascading recompilation.
  """
  @spec find_priv_dir() :: String.t()
  def find_priv_dir do
    CCXT.Priv.dir()
  end
end
