defmodule CCXT.Generator.Functions.Docs do
  @moduledoc """
  Documentation generation for endpoint functions.

  Generates @doc strings with parameter documentation, including
  fee information for order-related endpoints.
  """

  alias CCXT.Spec

  # Order-related methods that should show fee information
  @order_methods [
    :create_order,
    :create_orders,
    :edit_order,
    :create_market_order,
    :create_limit_order
  ]

  @doc """
  Generate documentation string for an endpoint function.

  For order-related endpoints, includes fee information from the spec
  when available.
  """
  @spec generate_doc(atom(), [atom()], boolean(), Spec.t()) :: String.t()
  def generate_doc(name, params, auth, spec) do
    param_docs =
      if auth do
        ["- `credentials` - CCXT.Credentials struct" | format_param_docs(params)]
      else
        format_param_docs(params)
      end

    param_section =
      if param_docs == [] do
        ""
      else
        "\n\n## Parameters\n\n#{Enum.join(param_docs, "\n")}"
      end

    fee_section = build_fee_section(name, spec)

    "Calls the #{name} endpoint.#{param_section}#{fee_section}\n\n## Options\n\n- `:params` - Additional parameters to include in the request"
  end

  @doc false
  # Builds the fee documentation section for order-related endpoints.
  # Returns empty string for non-order endpoints or when no fee data available.
  @spec build_fee_section(atom(), Spec.t()) :: String.t()
  defp build_fee_section(name, spec) when name in @order_methods do
    case Spec.trading_fees(spec) do
      nil ->
        ""

      fees ->
        fee_lines = build_fee_lines(fees, spec)

        if fee_lines == [] do
          ""
        else
          "\n\n## Fees\n\n#{Enum.join(fee_lines, "\n")}"
        end
    end
  end

  defp build_fee_section(_name, _spec), do: ""

  @doc false
  # Builds individual fee documentation lines from trading fees.
  @spec build_fee_lines(map(), Spec.t()) :: [String.t()]
  defp build_fee_lines(fees, spec) do
    # Use filter(&is_binary/1) to keep only string values (filters out nil AND false from &&)
    base_lines =
      Enum.filter(
        [
          fees[:maker] && "- Maker: #{format_fee_percentage(fees[:maker])}",
          fees[:taker] && "- Taker: #{format_fee_percentage(fees[:taker])}",
          fees[:tier_based] != nil && "- Tier-based: #{fees[:tier_based]}"
        ],
        &is_binary/1
      )

    # Add market-type specific fees if different from base
    base_lines ++ build_market_type_fee_lines(spec)
  end

  @doc false
  # Builds fee lines for market-type specific fees (swap, future, etc.)
  @spec build_market_type_fee_lines(Spec.t()) :: [String.t()]
  defp build_market_type_fee_lines(spec) do
    market_types = [:swap, :future, :linear, :inverse]

    Enum.flat_map(market_types, fn market_type ->
      spec
      |> Spec.fees_for_market(market_type)
      |> format_market_type_fee_line(market_type)
    end)
  end

  @doc false
  # Formats a single market type fee line from the fees map.
  @spec format_market_type_fee_line(map() | nil, atom()) :: [String.t()]
  defp format_market_type_fee_line(nil, _market_type), do: []

  defp format_market_type_fee_line(market_fees, market_type) when is_map(market_fees) do
    maker = market_fees[:maker]
    taker = market_fees[:taker]

    build_market_fee_line(maker, taker, market_type)
  end

  @doc false
  # Builds the fee line string from maker/taker values.
  @spec build_market_fee_line(number() | nil, number() | nil, atom()) :: [String.t()]
  defp build_market_fee_line(nil, nil, _market_type), do: []

  defp build_market_fee_line(maker, taker, market_type) do
    type_name = market_type |> Atom.to_string() |> String.capitalize()
    fee_parts = build_fee_parts(maker, taker)
    ["- #{type_name}: #{Enum.join(fee_parts, ", ")}"]
  end

  @doc false
  # Builds the list of fee parts (maker/taker) for display.
  @spec build_fee_parts(number() | nil, number() | nil) :: [String.t()]
  defp build_fee_parts(maker, taker) do
    []
    |> maybe_add_fee_part(maker, "maker")
    |> maybe_add_fee_part(taker, "taker")
  end

  @doc false
  # Conditionally adds a fee part to the list.
  @spec maybe_add_fee_part([String.t()], number() | nil, String.t()) :: [String.t()]
  defp maybe_add_fee_part(parts, nil, _label), do: parts
  defp maybe_add_fee_part(parts, fee, label), do: parts ++ ["#{label} #{format_fee_percentage(fee)}"]

  @doc false
  # Formats a fee as a percentage string (e.g., 0.001 -> "0.1%").
  # Uses float arithmetic - sufficient for display purposes in documentation.
  @spec format_fee_percentage(number()) :: String.t()
  defp format_fee_percentage(fee) when is_number(fee) do
    percentage = fee * 100
    formatted = :erlang.float_to_binary(percentage / 1, decimals: 4)
    # Trim trailing zeros for cleaner display (0.1000 -> 0.1)
    trimmed = String.replace(formatted, ~r/\.?0+$/, "")
    trimmed <> "%"
  end

  # Format parameter documentation lines
  @spec format_param_docs([atom()]) :: [String.t()]
  defp format_param_docs(params) do
    Enum.map(params, fn param ->
      "- `#{param}` - #{humanize_param(param)}"
    end)
  end

  # Human-readable descriptions for common parameters
  @spec humanize_param(atom()) :: String.t()
  defp humanize_param(:symbol), do: "Trading symbol (e.g., \"BTC/USDT\")"
  defp humanize_param(:symbols), do: "List of trading symbols (optional)"
  defp humanize_param(:limit), do: "Maximum number of results (optional)"
  defp humanize_param(:since), do: "Start timestamp in milliseconds (optional)"
  defp humanize_param(:order_id), do: "Order ID"
  defp humanize_param(:type), do: "Order type (:limit, :market)"
  defp humanize_param(:side), do: "Order side (:buy, :sell)"
  defp humanize_param(:amount), do: "Order amount"
  defp humanize_param(:price), do: "Order price (optional for market orders)"
  defp humanize_param(:interval), do: "OHLCV timeframe"
  defp humanize_param(:timeframe), do: ~s{OHLCV timeframe (e.g., "1m", "1h")}
  defp humanize_param(:code), do: "Currency code (e.g., \"BTC\")"
  defp humanize_param(:currency), do: "Currency code"
  defp humanize_param(:network), do: "Network/chain (optional)"
  defp humanize_param(:address), do: "Wallet address"
  defp humanize_param(:tag), do: "Memo/tag (optional)"
  defp humanize_param(param), do: "#{param} parameter"
end
