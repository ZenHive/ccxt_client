defmodule CCXT.HTTP.RateLimitHeaders do
  @moduledoc """
  Parses rate limit status headers from exchange API responses.

  Exchanges return rate limit information with every response, not just 429s.
  This module detects the header pattern and extracts normalized rate limit data.

  ## Supported Patterns

  Patterns are tried in order; the first match wins:

  1. **Binance** — `x-mbx-used-weight-1m` or `x-sapi-used-ip-weight-1m`
  2. **Bybit** — `x-bapi-limit`, `x-bapi-limit-status`, `x-bapi-limit-reset-timestamp`
  3. **Standard** — `x-ratelimit-limit`, `x-ratelimit-remaining`, `x-ratelimit-reset`

  Exchanges without custom rate limit headers (OKX, Kraken) return `:none`.
  """

  alias CCXT.HTTP.RateLimitInfo

  @doc """
  Parses rate limit headers from a response.

  Headers are in Req format: `%{String.t() => [String.t()]}` with lowercase keys.

  `spec_rate_limits` is the `rate_limits` map from the exchange spec, used to
  derive `limit` when the exchange only reports `used` (e.g., Binance).

  Returns `{:ok, %RateLimitInfo{}}` if rate limit headers are found, `:none` otherwise.
  """
  @spec parse(atom(), %{String.t() => [String.t()]}, map() | nil) ::
          {:ok, RateLimitInfo.t()} | :none
  def parse(exchange, headers, spec_rate_limits \\ nil) when is_atom(exchange) and is_map(headers) do
    with :none <- parse_binance(exchange, headers, spec_rate_limits),
         :none <- parse_bybit(exchange, headers) do
      parse_standard(exchange, headers)
    end
  end

  # =============================================================================
  # Binance Pattern
  #
  # Binance reports weight used in the current 1-minute window:
  # - x-mbx-used-weight-1m: Main API (api.binance.com)
  # - x-sapi-used-ip-weight-1m: SAPI endpoints (sapi.binance.com)
  #
  # Only `used` is reported; `limit` comes from spec.rate_limits.requests.
  # =============================================================================

  @binance_headers ["x-mbx-used-weight-1m", "x-sapi-used-ip-weight-1m"]

  @doc false
  defp parse_binance(exchange, headers, spec_rate_limits) do
    case find_header(headers, @binance_headers) do
      {header_name, used_str} ->
        used = parse_int(used_str)
        limit = get_spec_limit(spec_rate_limits)

        remaining =
          if is_integer(used) and is_integer(limit) do
            max(limit - used, 0)
          end

        raw = collect_raw_headers(headers, @binance_headers)

        {:ok,
         %RateLimitInfo{
           exchange: exchange,
           limit: limit,
           used: used,
           remaining: remaining,
           reset_at: nil,
           source: :binance_weight,
           raw_headers: Map.put(raw, "matched", header_name)
         }}

      nil ->
        :none
    end
  end

  # =============================================================================
  # Bybit Pattern
  #
  # Bybit provides all three pieces:
  # - x-bapi-limit: Maximum requests allowed
  # - x-bapi-limit-status: Remaining requests
  # - x-bapi-limit-reset-timestamp: Unix ms when window resets
  # =============================================================================

  @bybit_limit_header "x-bapi-limit"
  @bybit_remaining_header "x-bapi-limit-status"
  @bybit_reset_header "x-bapi-limit-reset-timestamp"
  @bybit_headers [@bybit_limit_header, @bybit_remaining_header, @bybit_reset_header]

  @doc false
  defp parse_bybit(exchange, headers) do
    case get_header(headers, @bybit_limit_header) do
      nil ->
        :none

      limit_str ->
        limit = parse_int(limit_str)
        remaining = parse_int(get_header(headers, @bybit_remaining_header))
        reset_at = parse_int(get_header(headers, @bybit_reset_header))

        used =
          if is_integer(limit) and is_integer(remaining) do
            max(limit - remaining, 0)
          end

        {:ok,
         %RateLimitInfo{
           exchange: exchange,
           limit: limit,
           used: used,
           remaining: remaining,
           reset_at: reset_at,
           source: :bybit_bapi,
           raw_headers: collect_raw_headers(headers, @bybit_headers)
         }}
    end
  end

  # =============================================================================
  # Standard Pattern (RFC-style)
  #
  # Common headers used by KuCoin and others:
  # - x-ratelimit-limit: Maximum requests in window
  # - x-ratelimit-remaining: Remaining requests
  # - x-ratelimit-reset: Unix timestamp (seconds) when window resets
  # =============================================================================

  @standard_limit_header "x-ratelimit-limit"
  @standard_remaining_header "x-ratelimit-remaining"
  @standard_reset_header "x-ratelimit-reset"
  @standard_headers [@standard_limit_header, @standard_remaining_header, @standard_reset_header]

  @doc false
  defp parse_standard(exchange, headers) do
    case get_header(headers, @standard_limit_header) do
      nil ->
        :none

      limit_str ->
        limit = parse_int(limit_str)
        remaining = parse_int(get_header(headers, @standard_remaining_header))
        reset_seconds = parse_int(get_header(headers, @standard_reset_header))

        # Convert seconds to ms for consistency
        reset_at = if is_integer(reset_seconds), do: reset_seconds * 1000

        used =
          if is_integer(limit) and is_integer(remaining) do
            max(limit - remaining, 0)
          end

        {:ok,
         %RateLimitInfo{
           exchange: exchange,
           limit: limit,
           used: used,
           remaining: remaining,
           reset_at: reset_at,
           source: :standard,
           raw_headers: collect_raw_headers(headers, @standard_headers)
         }}
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  @doc false
  # Gets first matching header value from a list of header names
  defp find_header(headers, names) do
    Enum.find_value(names, fn name ->
      case get_header(headers, name) do
        nil -> nil
        value -> {name, value}
      end
    end)
  end

  @doc false
  # Gets a single header value (Req headers are %{String.t() => [String.t()]})
  defp get_header(headers, name) do
    case Map.get(headers, name) do
      [value | _] -> value
      _ -> nil
    end
  end

  @doc false
  # Parses a string to integer, returns nil on failure
  defp parse_int(nil), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  @doc false
  # Extracts the requests-per-window limit from spec.rate_limits
  defp get_spec_limit(nil), do: nil
  defp get_spec_limit(%{requests: requests}) when is_integer(requests), do: requests
  defp get_spec_limit(_), do: nil

  @doc false
  # Collects raw header values for the given header names
  defp collect_raw_headers(headers, names) do
    Enum.reduce(names, %{}, fn name, acc ->
      case get_header(headers, name) do
        nil -> acc
        value -> Map.put(acc, name, value)
      end
    end)
  end
end
