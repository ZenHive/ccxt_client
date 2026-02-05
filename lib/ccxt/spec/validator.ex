defmodule CCXT.Spec.Validator do
  @moduledoc """
  Validates CCXT exchange spec files at compile time.

  This module is used by `CCXT.Generator` to ensure spec files have all required
  fields and valid values before generating exchange modules.

  ## Validation Checks

  ### Structural Validation
  - Required fields: id, name, urls.api
  - Signing pattern: must be a valid atom from `CCXT.Signing`
  - Structure: endpoints must be a list, classification must be valid
  - Endpoints: each must have name, method, path, auth, params

  ### Semantic Validation (Task 111)
  - Capability/endpoint consistency: if `has.X: true`, endpoint X should exist
  - Market type consistency: if endpoint has `market_type`, that type should be in `features`
  - Fee structure: if fees present, should have at least `trading.maker` or `trading.taker`

  ## Usage

  This module is called automatically by the generator. Direct usage:

      spec = CCXT.Spec.load!("path/to/spec.exs")
      CCXT.Spec.Validator.validate!(spec, "path/to/spec.exs")

  """

  alias CCXT.Spec

  @doc """
  Validates a spec and raises CompileError if invalid.

  Returns `:ok` on success.
  """
  @spec validate!(Spec.t(), String.t()) :: :ok | no_return()
  def validate!(%Spec{} = spec, path) do
    errors =
      []
      |> validate_required_fields(spec)
      |> validate_urls(spec)
      |> validate_signing(spec)
      |> validate_structure(spec)
      |> validate_endpoints(spec)
      |> Enum.reverse()

    if errors != [] do
      error_msg = Enum.join(errors, "\n  - ")

      raise CompileError,
        description: "Invalid spec file:\n  - #{error_msg}",
        file: path,
        line: 1
    end

    :ok
  end

  @doc """
  Validates a spec and returns {:ok, spec} or {:error, errors}.

  Useful for non-compile-time validation.
  """
  @spec validate(Spec.t()) :: {:ok, Spec.t()} | {:error, [String.t()]}
  def validate(%Spec{} = spec) do
    errors =
      []
      |> validate_required_fields(spec)
      |> validate_urls(spec)
      |> validate_signing(spec)
      |> validate_structure(spec)
      |> validate_endpoints(spec)
      |> Enum.reverse()

    if errors == [] do
      {:ok, spec}
    else
      {:error, errors}
    end
  end

  # Note: @enforce_keys in CCXT.Spec guarantees :id, :name, :urls are present
  # These checks are defensive against empty values
  @spec validate_required_fields([String.t()], Spec.t()) :: [String.t()]
  defp validate_required_fields(errors, spec) do
    errors
    |> add_error_if(spec.id == "", "id is required")
    |> add_error_if(spec.name == "", "name is required")
  end

  @spec validate_urls([String.t()], Spec.t()) :: [String.t()]
  defp validate_urls(errors, spec) do
    api_url = Map.get(spec.urls, :api)

    add_error_if(errors, api_url == nil or api_url == "", "urls.api is required")
  end

  @spec validate_signing([String.t()], Spec.t()) :: [String.t()]
  defp validate_signing(errors, spec) do
    pattern = spec.signing && Map.get(spec.signing, :pattern)

    errors
    |> add_error_if(spec.signing && not is_atom(pattern), "signing.pattern must be an atom")
    |> add_error_if(
      spec.signing && is_atom(pattern) && not CCXT.Signing.pattern?(pattern),
      "signing.pattern '#{pattern}' is not a valid pattern"
    )
  end

  @spec validate_structure([String.t()], Spec.t()) :: [String.t()]
  defp validate_structure(errors, spec) do
    errors
    |> add_error_if(not is_list(spec.endpoints), "endpoints must be a list")
    |> add_error_if(
      spec.classification not in [:certified_pro, :pro, :supported],
      "classification must be :certified_pro, :pro, or :supported"
    )
  end

  @spec validate_endpoints([String.t()], Spec.t()) :: [String.t()]
  defp validate_endpoints(errors, spec) do
    endpoint_errors =
      spec.endpoints
      |> Enum.with_index()
      |> Enum.flat_map(fn {endpoint, idx} -> validate_endpoint(endpoint, idx) end)

    errors ++ endpoint_errors
  end

  # Validate a single endpoint definition
  @spec validate_endpoint(map(), non_neg_integer()) :: [String.t()]
  defp validate_endpoint(endpoint, idx) do
    prefix = "endpoints[#{idx}]"

    []
    |> add_error_if(!is_atom(endpoint[:name]), "#{prefix}.name must be an atom")
    |> add_error_if(
      endpoint[:method] not in [:get, :post, :put, :patch, :delete],
      "#{prefix}.method must be :get, :post, :put, :patch, or :delete"
    )
    |> add_error_if(!is_binary(endpoint[:path]), "#{prefix}.path must be a string")
    |> add_error_if(!is_boolean(endpoint[:auth]), "#{prefix}.auth must be a boolean")
    |> add_error_if(!is_list(endpoint[:params]), "#{prefix}.params must be a list")
  end

  @spec add_error_if([String.t()], boolean(), String.t()) :: [String.t()]
  defp add_error_if(errors, condition, message) do
    if condition, do: [message | errors], else: errors
  end

  # ===========================================================================
  # Semantic Validation (Task 111)
  # ===========================================================================
  # These validations check data quality but don't block compilation.
  # They return warnings that can be logged during extraction.

  @doc """
  Validates semantic consistency and returns warnings.

  Unlike `validate!/2`, this function does not raise errors. It returns
  a list of warning messages for data quality issues that don't prevent
  the spec from being used.

  Use this during extraction to identify potential issues.

  ## Checks

  - Capability/endpoint consistency: if `has.X: true`, endpoint X should exist
  - Market type/feature consistency: if endpoint has `market_type`, that type should be in `features`
  - Fee structure: if fees present, should have at least `trading.maker` or `trading.taker`
  """
  @spec semantic_warnings(Spec.t()) :: [String.t()]
  def semantic_warnings(%Spec{} = spec) do
    []
    |> check_capability_endpoint_consistency(spec)
    |> check_market_type_feature_consistency(spec)
    |> check_fee_structure(spec)
    |> Enum.reverse()
  end

  @doc false
  # Checks that capabilities in `has` have corresponding endpoints.
  @spec check_capability_endpoint_consistency([String.t()], Spec.t()) :: [String.t()]
  defp check_capability_endpoint_consistency(warnings, spec) do
    endpoint_names = MapSet.new(spec.endpoints, fn ep -> ep[:name] end)

    spec.has
    |> Enum.filter(fn {_cap, value} -> value == true end)
    |> Enum.reduce(warnings, fn {cap, _}, acc ->
      add_capability_warning(acc, cap, endpoint_names)
    end)
  end

  @doc false
  # Adds warning if capability should have an endpoint but doesn't.
  @spec add_capability_warning([String.t()], atom(), MapSet.t()) :: [String.t()]
  defp add_capability_warning(warnings, cap, endpoint_names) do
    has_endpoint = MapSet.member?(endpoint_names, cap)
    needs_endpoint = should_have_endpoint?(cap)

    if has_endpoint or not needs_endpoint do
      warnings
    else
      ["has.#{cap}: true but no endpoint with name :#{cap} exists" | warnings]
    end
  end

  @doc false
  # Determines if a capability should have a corresponding endpoint.
  @spec should_have_endpoint?(atom()) :: boolean()
  defp should_have_endpoint?(cap) do
    cap_str = Atom.to_string(cap)
    method_prefixes = ["fetch_", "create_", "cancel_", "edit_", "transfer_", "set_", "withdraw"]
    Enum.any?(method_prefixes, fn prefix -> String.starts_with?(cap_str, prefix) end)
  end

  @doc false
  # Checks that endpoints with market_type have that type in features.
  @spec check_market_type_feature_consistency([String.t()], Spec.t()) :: [String.t()]
  defp check_market_type_feature_consistency(warnings, %Spec{features: nil}), do: warnings
  defp check_market_type_feature_consistency(warnings, %Spec{features: f}) when map_size(f) == 0, do: warnings

  defp check_market_type_feature_consistency(warnings, spec) do
    feature_types = MapSet.new(Map.keys(spec.features))

    spec.endpoints
    |> Enum.filter(fn ep -> ep[:market_type] != nil end)
    |> Enum.reduce(warnings, fn ep, acc ->
      add_market_type_warning(acc, ep, feature_types)
    end)
  end

  @doc false
  # Adds warning if endpoint's market_type isn't in features.
  @spec add_market_type_warning([String.t()], map(), MapSet.t()) :: [String.t()]
  defp add_market_type_warning(warnings, ep, feature_types) do
    market_type = ep[:market_type]

    if MapSet.member?(feature_types, market_type) do
      warnings
    else
      ["endpoint :#{ep[:name]} has market_type :#{market_type} but features does not include :#{market_type}" | warnings]
    end
  end

  @doc false
  # Checks fee structure has required fields when present.
  @spec check_fee_structure([String.t()], Spec.t()) :: [String.t()]
  defp check_fee_structure(warnings, %Spec{fees: nil}), do: warnings
  defp check_fee_structure(warnings, %Spec{fees: f}) when map_size(f) == 0, do: warnings

  defp check_fee_structure(warnings, spec) do
    trading = Map.get(spec.fees, :trading, %{})
    has_maker = is_number(trading[:maker])
    has_taker = is_number(trading[:taker])

    if has_maker or has_taker do
      warnings
    else
      ["fees present but missing trading.maker and trading.taker" | warnings]
    end
  end
end
