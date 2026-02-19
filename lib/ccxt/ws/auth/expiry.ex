defmodule CCXT.WS.Auth.Expiry do
  @moduledoc """
  Pure functions for computing auth session expiry timing.

  Used by the generated WS Adapter to determine when to schedule
  `:auth_expired` timer messages. TTL sources (in priority order):

  1. **Response-level** — auth response includes `expires_in` (e.g., Deribit),
     returned as `{:ok, %{ttl_ms: N}}` from `handle_auth_response/2`
  2. **Config-level** — spec's `ws.auth.auth_ttl_ms` key (static override)
  3. **None** — no TTL available, no timer scheduled

  ## Example

      auth_meta = %{ttl_ms: 900_000}
      auth_config = %{pattern: :jsonrpc_linebreak}

      ttl_ms = Expiry.compute_ttl_ms(auth_meta, auth_config)
      # => 900_000

      delay = Expiry.schedule_delay_ms(ttl_ms)
      # => 720_000  (80% safety margin)

  """

  # Schedule re-auth at 80% of TTL to avoid racing the server's expiry
  @default_safety_margin 0.80

  # Cap at 24 hours — no auth session should go longer without refresh
  @max_auth_ttl_ms 86_400_000

  @doc """
  Resolves effective TTL in milliseconds from auth metadata and config.

  Response-level TTL (from `auth_meta.ttl_ms`) takes priority over
  config-level TTL (from `auth_config[:auth_ttl_ms]`).

  Returns `nil` when no TTL source is available.
  """
  @spec compute_ttl_ms(map() | nil, map() | nil) :: pos_integer() | nil
  def compute_ttl_ms(auth_meta, auth_config) do
    response_ttl =
      case auth_meta do
        %{ttl_ms: ttl} when is_integer(ttl) and ttl > 0 -> ttl
        _ -> nil
      end

    config_ttl =
      case auth_config do
        %{auth_ttl_ms: ttl} when is_integer(ttl) and ttl > 0 -> ttl
        _ -> nil
      end

    response_ttl || config_ttl
  end

  @doc """
  Computes the delay before scheduling `:auth_expired`, applying a safety margin.

  Applies `#{@default_safety_margin * 100}%` safety margin (re-auth before server expires)
  and caps at #{div(@max_auth_ttl_ms, 3_600_000)}h.

  Returns `nil` for `nil` or non-positive TTL inputs (no timer should be scheduled).
  """
  @spec schedule_delay_ms(pos_integer() | nil) :: pos_integer() | nil
  def schedule_delay_ms(nil), do: nil

  def schedule_delay_ms(ttl_ms) when is_integer(ttl_ms) and ttl_ms <= 0, do: nil

  def schedule_delay_ms(ttl_ms) when is_integer(ttl_ms) and ttl_ms > 0 do
    delay = trunc(ttl_ms * @default_safety_margin)
    min(delay, @max_auth_ttl_ms)
  end
end
