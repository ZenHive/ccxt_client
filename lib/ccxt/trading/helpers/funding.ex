defmodule CCXT.Trading.Helpers.Funding do
  @moduledoc """
  Funding rate timing helpers for perpetual futures.

  Pure functions for calculating time until next funding payment.
  Most perpetual futures exchanges use 8-hour funding cycles at
  00:00, 08:00, and 16:00 UTC.

  ## Example

      CCXT.Trading.Helpers.Funding.next_funding()
      # => 2.5 (hours until next funding)

      CCXT.Trading.Helpers.Funding.next_funding_at()
      # => ~U[2025-01-15 16:00:00Z]

  """

  @funding_hours [0, 8, 16]
  @milliseconds_per_hour 3_600_000

  @doc """
  Returns hours until the next funding time.

  Standard funding cycles are at 00:00, 08:00, and 16:00 UTC.

  ## Example

      CCXT.Trading.Helpers.Funding.next_funding()
      # => 2.5 (hours until next funding)

  """
  @spec next_funding() :: float()
  def next_funding do
    now = DateTime.utc_now()
    next_dt = next_funding_at()
    diff_ms = DateTime.diff(next_dt, now, :millisecond)
    diff_ms / @milliseconds_per_hour
  end

  @doc """
  Returns the DateTime of the next funding time.

  Standard funding cycles are at 00:00, 08:00, and 16:00 UTC.

  ## Example

      CCXT.Trading.Helpers.Funding.next_funding_at()
      # => ~U[2025-01-15 16:00:00Z]

  """
  @spec next_funding_at() :: DateTime.t()
  def next_funding_at do
    now = DateTime.utc_now()
    current_hour = now.hour
    current_minute = now.minute
    current_second = now.second

    # Find the next funding hour
    next_hour = find_next_funding_hour(current_hour, current_minute, current_second)

    # Build the DateTime for next funding
    build_funding_datetime(now, next_hour, current_hour)
  end

  @doc """
  Returns hours until the next funding time from a given DateTime.

  Useful for backtesting or working with historical data.

  ## Example

      past_time = ~U[2025-01-15 07:30:00Z]
      CCXT.Trading.Helpers.Funding.next_funding_from(past_time)
      # => 0.5 (30 minutes until 08:00)

  """
  @spec next_funding_from(DateTime.t()) :: float()
  def next_funding_from(%DateTime{} = from) do
    next_dt = next_funding_at_from(from)
    diff_ms = DateTime.diff(next_dt, from, :millisecond)
    diff_ms / @milliseconds_per_hour
  end

  @doc """
  Returns the DateTime of the next funding time from a given DateTime.

  ## Example

      past_time = ~U[2025-01-15 07:30:00Z]
      CCXT.Trading.Helpers.Funding.next_funding_at_from(past_time)
      # => ~U[2025-01-15 08:00:00Z]

  """
  @spec next_funding_at_from(DateTime.t()) :: DateTime.t()
  def next_funding_at_from(%DateTime{} = from) do
    current_hour = from.hour
    current_minute = from.minute
    current_second = from.second

    next_hour = find_next_funding_hour(current_hour, current_minute, current_second)
    build_funding_datetime(from, next_hour, current_hour)
  end

  # Find the next funding hour after current time
  # When at or past a funding hour, returns the following funding time
  # E.g., at 08:00:00 or 08:30:00, returns 16; at 07:59:59, returns 8
  @doc false
  defp find_next_funding_hour(current_hour, _current_minute, _current_second) do
    Enum.find(@funding_hours, fn hour -> hour > current_hour end) || hd(@funding_hours) + 24
  end

  # Build the DateTime for the next funding time
  @doc false
  defp build_funding_datetime(base, next_hour, current_hour) do
    # Calculate hours to add
    hours_to_add =
      if next_hour > 23 do
        # Next funding is tomorrow at 00:00
        24 - current_hour + (next_hour - 24)
      else
        next_hour - current_hour
      end

    # Add hours and truncate to the start of the hour
    base
    |> DateTime.add(hours_to_add, :hour)
    |> DateTime.truncate(:second)
    |> Map.put(:minute, 0)
    |> Map.put(:second, 0)
  end
end
