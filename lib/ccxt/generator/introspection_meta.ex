defmodule CCXT.Generator.IntrospectionMeta do
  @moduledoc """
  Single source of truth for introspection function metadata.

  This module defines all introspection functions available on generated exchange
  modules. The same metadata is used for:
  1. Generating the actual functions (in CCXT.Generator.Functions)
  2. Documenting them in the generated @moduledoc

  Add or remove functions here to update both code generation and documentation.
  """

  @typedoc "Introspection function definition"
  @type introspection_func :: {name :: atom(), arity :: non_neg_integer(), description :: String.t()}

  @doc """
  Core introspection functions available on all generated modules.
  """
  @spec core_functions() :: [introspection_func()]
  def core_functions do
    [
      {:__ccxt_spec__, 0, "Full exchange specification struct"},
      {:__ccxt_exchange_id__, 0, "Exchange identifier atom"},
      {:__ccxt_endpoints__, 0, "List of endpoint definitions"},
      {:__ccxt_signing__, 0, "Signing pattern and config"},
      {:__ccxt_classification__, 0, "Exchange tier (:certified_pro, :pro, :supported)"}
    ]
  end

  @doc """
  Endpoint introspection functions for querying specific endpoints.
  """
  @spec endpoint_functions() :: [introspection_func()]
  def endpoint_functions do
    [
      {:endpoint_info, 1, "Detailed info about an endpoint with contextual hints"},
      {:required_params, 1, "Required parameters beyond function signature"},
      {:account_types, 0, "Account type mappings (unified -> exchange-specific)"},
      {:options, 0, "Exchange-specific options from spec"}
    ]
  end

  @doc """
  Extended introspection functions for complete CCXT data passthrough.
  """
  @spec extended_functions() :: [introspection_func()]
  def extended_functions do
    [
      {:__ccxt_raw_endpoints__, 0, "Raw CCXT API endpoint structure"},
      {:__ccxt_extended_metadata__, 0, "Logo URLs, referral info, precision, limits"},
      {:__ccxt_required_credentials__, 0, "Credential requirements (api_key, secret, etc.)"},
      {:__ccxt_currencies__, 0, "Currency database"},
      {:__ccxt_markets__, 0, "Market definitions"},
      {:__ccxt_api_param_requirements__, 0, "Raw API parameter requirements"},
      {:__ccxt_url_strategy__, 0, "URL pattern detection result"},
      {:__ccxt_status__, 0, "Exchange operational status"},
      {:__ccxt_extraction_info__, 0, "CCXT version and extraction timestamp"},
      {:__ccxt_comment__, 0, "Exchange documentation/quirks"},
      {:__ccxt_exchange_options__, 0, "Runtime-modified exchange options"},
      {:__ccxt_endpoint_stats__, 0, "Endpoint extraction quality metrics"},
      {:__ccxt_certified__, 0, "Whether exchange is CCXT certified"},
      {:__ccxt_pro__, 0, "Whether exchange supports CCXT Pro (WebSocket)"},
      {:__ccxt_dex__, 0, "Whether exchange is a DEX"}
    ]
  end

  @doc """
  All introspection functions combined.
  """
  @spec all_functions() :: [introspection_func()]
  def all_functions do
    core_functions() ++ endpoint_functions() ++ extended_functions()
  end

  @doc """
  Generates a markdown table of all introspection functions.

  Used in generated module documentation.
  """
  @spec generate_table() :: String.t()
  def generate_table do
    header = "| Function | Description |\n|----------|-------------|"

    rows =
      Enum.map(all_functions(), fn {name, arity, desc} ->
        "| `#{name}/#{arity}` | #{desc} |"
      end)

    Enum.join([header | rows], "\n")
  end

  @doc """
  Returns the count of introspection functions.
  """
  @spec function_count() :: non_neg_integer()
  def function_count do
    length(all_functions())
  end
end
