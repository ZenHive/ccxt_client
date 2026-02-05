defmodule CCXT.Error.Hints do
  @moduledoc """
  Generates contextual hints for exchange errors.

  Part of the Type-Safe API Bundle (Task 149). Provides two types of hints:

  1. **Static hints** (`for_type/2`) - Generic hints based on error type
  2. **Contextual hints** (`for_endpoint/2`) - Hints based on exchange spec

  ## Static Hints Example

      CCXT.Error.Hints.for_type(:rate_limited, retry_after: 1000)
      # => ["Wait 1000ms before retrying", "Too many requests - implement exponential backoff"]

  ## Contextual Hints Example

      # When fetch_balance fails on Bybit due to missing accountType
      hints = CCXT.Error.Hints.for_endpoint(bybit_spec, :fetch_balance)
      # => ["Bybit requires accountType parameter. Valid types: unified, contract, spot"]

  """

  alias CCXT.MethodCategories
  alias CCXT.Spec

  @type error_type :: CCXT.Error.error_type()

  # ===========================================================================
  # Static Hints (by error type)
  # ===========================================================================

  @doc """
  Generates hints for an error type.

  These are static hints based on the error type, useful for providing
  guidance when contextual information (spec, endpoint) is not available.

  ## Parameters

  - `type` - The error type atom
  - `opts` - Options from the error constructor (e.g., retry_after)

  ## Examples

      iex> CCXT.Error.Hints.for_type(:rate_limited, retry_after: 1000)
      ["Wait 1000ms before retrying", "Too many requests - implement exponential backoff"]

      iex> CCXT.Error.Hints.for_type(:invalid_credentials, [])
      ["Verify API key and secret are correct", ...]

  """
  @spec for_type(error_type(), keyword()) :: [String.t()]
  def for_type(:rate_limited, opts) do
    base = ["Too many requests - implement exponential backoff"]

    case Keyword.get(opts, :retry_after) do
      nil -> base
      ms -> ["Wait #{ms}ms before retrying" | base]
    end
  end

  def for_type(:insufficient_balance, _opts) do
    [
      "Check account balance",
      "Verify you're using the correct account type (spot, margin, futures)"
    ]
  end

  def for_type(:invalid_credentials, _opts) do
    [
      "Verify API key and secret are correct",
      "Check if API key has required permissions",
      "Ensure API key is not expired or revoked"
    ]
  end

  def for_type(:invalid_parameters, _opts) do
    [
      "Check parameter names and types match API documentation",
      "Verify required parameters are provided",
      "Check symbol format matches exchange requirements"
    ]
  end

  def for_type(:order_not_found, _opts) do
    [
      "Verify order ID is correct",
      "Order may have been canceled or filled",
      "Check if using correct account/subaccount"
    ]
  end

  def for_type(:invalid_order, _opts) do
    [
      "Check order parameters (price, amount, type)",
      "Verify price is within acceptable range",
      "Check minimum order size requirements"
    ]
  end

  def for_type(:market_closed, _opts) do
    [
      "Market is currently closed for trading",
      "Check exchange maintenance schedule",
      "Retry when market reopens"
    ]
  end

  def for_type(:network_error, _opts) do
    [
      "Check network connectivity",
      "Retry with exponential backoff",
      "Verify exchange API is accessible"
    ]
  end

  def for_type(:access_restricted, _opts) do
    [
      "Exchange may be geo-blocked in your region",
      "Check if VPN or proxy is required",
      "Verify IP is not rate-limited or banned"
    ]
  end

  def for_type(:not_supported, _opts) do
    [
      "This method is not available for this exchange",
      "Check exchange documentation for alternatives",
      "Consider using a different exchange for this feature"
    ]
  end

  def for_type(:circuit_open, opts) do
    exchange = Keyword.get(opts, :exchange)

    base = [
      "Circuit will auto-reset after configured timeout",
      "Check exchange status page for outages",
      "Use CCXT.CircuitBreaker.reset/1 to manually reset if needed"
    ]

    if exchange do
      ["Exchange #{exchange} has experienced multiple consecutive failures" | base]
    else
      base
    end
  end

  def for_type(:exchange_error, _opts) do
    [
      "Check exchange error code and message for details",
      "Consult exchange API documentation",
      "Contact exchange support if issue persists"
    ]
  end

  def for_type(_type, _opts), do: []

  @doc """
  Returns user-provided hints if any, otherwise returns auto-generated hints.

  When user provides custom hints, those are used exclusively (not merged).
  This allows callers to fully control the hints when needed.

  ## Examples

      iex> CCXT.Error.Hints.merge_hints(["Custom hint"], :rate_limited, retry_after: 1000)
      ["Custom hint", "Wait 1000ms before retrying", "Too many requests - implement exponential backoff"]

  """
  @spec merge_hints([String.t()], error_type(), keyword()) :: [String.t()]
  def merge_hints(user_hints, type, opts) when is_list(user_hints) do
    auto_hints = for_type(type, opts)
    user_hints ++ auto_hints
  end

  # ===========================================================================
  # Contextual Hints (by exchange spec and endpoint)
  # ===========================================================================

  @doc """
  Generates hints for an endpoint based on the exchange spec.

  Returns a list of hint strings that can help users understand
  what parameters might be required or how to resolve common issues.
  """
  @spec for_endpoint(Spec.t(), atom()) :: [String.t()]
  def for_endpoint(spec, endpoint_name) do
    []
    |> maybe_add_account_type_hint(spec, endpoint_name)
    |> maybe_add_derivatives_category_hint(spec, endpoint_name)
    |> maybe_add_param_mapping_hints(spec, endpoint_name)
  end

  @doc """
  Generates hints for an invalid parameters error.

  Takes the exchange spec, endpoint name, and the error message from
  the exchange to provide contextual suggestions.
  """
  @spec for_invalid_params(Spec.t(), atom(), String.t()) :: [String.t()]
  def for_invalid_params(spec, endpoint_name, _error_message) do
    for_endpoint(spec, endpoint_name)
  end

  @doc false
  # Adds hint about accountType parameter if endpoint requires it and spec has accounts_by_type
  defp maybe_add_account_type_hint(hints, spec, endpoint_name) do
    if endpoint_name in MethodCategories.account_type_methods() do
      options = spec.options || %{}
      accounts_by_type = options[:accounts_by_type] || %{}

      if map_size(accounts_by_type) > 0 do
        exchange_name = format_exchange_name(spec.id)
        types = accounts_by_type |> Map.keys() |> Enum.join(", ")

        hint =
          "#{exchange_name} requires accountType parameter. " <>
            "Valid types: #{types}"

        [hint | hints]
      else
        hints
      end
    else
      hints
    end
  end

  @doc false
  # Adds hint about category parameter for derivatives endpoints (linear, inverse, option)
  defp maybe_add_derivatives_category_hint(hints, spec, endpoint_name) do
    if endpoint_name in MethodCategories.derivatives_methods() do
      options = spec.options || %{}
      default_sub_type = options[:default_sub_type]

      if default_sub_type do
        exchange_name = format_exchange_name(spec.id)

        hint =
          "#{exchange_name} derivatives endpoints may require category parameter. " <>
            "Default: #{default_sub_type}. Options: linear, inverse, option"

        [hint | hints]
      else
        hints
      end
    else
      hints
    end
  end

  @doc false
  # Adds hints about parameter name mappings (e.g., "Bybit uses 'qty' instead of 'amount'")
  defp maybe_add_param_mapping_hints(hints, spec, _endpoint_name) do
    case spec.param_mappings do
      nil ->
        hints

      mappings when map_size(mappings) > 0 ->
        exchange_name = format_exchange_name(spec.id)

        mapping_hints =
          Enum.map(mappings, fn {unified, exchange_param} ->
            "#{exchange_name} uses '#{exchange_param}' instead of '#{unified}'"
          end)

        hints ++ mapping_hints

      _ ->
        hints
    end
  end

  @doc false
  # Formats exchange ID as human-readable name (e.g., :gate_io -> "Gate Io")
  defp format_exchange_name(id) when is_atom(id) do
    id
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc false
  defp format_exchange_name(id) when is_binary(id) do
    id
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
