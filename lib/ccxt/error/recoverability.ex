defmodule CCXT.Error.Recoverability do
  @moduledoc """
  Error recoverability classification for exchange errors.

  Part of the Type-Safe API Bundle (Task 149). Classifies errors by whether
  they can be recovered from automatically (retry) or require user intervention.

  ## Recoverability Rules

  | Error Type | Recoverable | Reason |
  |------------|-------------|--------|
  | `:rate_limited` | `true` | Wait and retry after rate limit window |
  | `:network_error` | `true` | Transient connection/timeout issues |
  | `:market_closed` | `true` | Market will reopen, can retry later |
  | `:circuit_open` | `true` | Circuit will auto-reset after timeout |
  | `:insufficient_balance` | `false` | User must add funds |
  | `:invalid_credentials` | `false` | Wrong API keys, user must fix |
  | `:invalid_parameters` | `false` | Code bug, developer must fix |
  | `:invalid_order` | `false` | Order rejected by exchange rules |
  | `:order_not_found` | `false` | Order doesn't exist |
  | `:access_restricted` | `false` | Geo-block or IP restriction |
  | `:not_supported` | `false` | Method unavailable on exchange |
  | `:exchange_error` | `nil` | Unknown, analyze message for clues |

  ## Usage

      CCXT.Error.Recoverability.for_type(:rate_limited)
      # => true

      CCXT.Error.Recoverability.for_type(:invalid_credentials)
      # => false

  """

  @type error_type :: CCXT.Error.error_type()

  # Recoverable errors - can be retried automatically
  @recoverable_types [:rate_limited, :network_error, :market_closed, :circuit_open]

  # Non-recoverable errors - require user/developer intervention
  @non_recoverable_types [
    :insufficient_balance,
    :invalid_credentials,
    :invalid_parameters,
    :invalid_order,
    :order_not_found,
    :access_restricted,
    :not_supported
  ]

  @doc """
  Returns the recoverability classification for an error type.

  ## Parameters

  - `type` - The error type atom

  ## Returns

  - `true` - Error is recoverable (can retry automatically)
  - `false` - Error is not recoverable (requires intervention)
  - `nil` - Unknown recoverability (generic exchange_error)

  ## Examples

      iex> CCXT.Error.Recoverability.for_type(:rate_limited)
      true

      iex> CCXT.Error.Recoverability.for_type(:invalid_credentials)
      false

      iex> CCXT.Error.Recoverability.for_type(:exchange_error)
      nil

  """
  @spec for_type(error_type()) :: boolean() | nil
  def for_type(type) when type in @recoverable_types, do: true
  def for_type(type) when type in @non_recoverable_types, do: false
  def for_type(:exchange_error), do: nil
  def for_type(_), do: nil

  @doc """
  Returns all recoverable error types.

  Useful for implementing retry logic.

  ## Example

      if error.type in CCXT.Error.Recoverability.recoverable_types() do
        schedule_retry(error)
      end

  """
  @spec recoverable_types() :: [error_type()]
  def recoverable_types, do: @recoverable_types

  @doc """
  Returns all non-recoverable error types.

  Useful for implementing error handling that requires user intervention.
  """
  @spec non_recoverable_types() :: [error_type()]
  def non_recoverable_types, do: @non_recoverable_types

  @doc """
  Checks if an error type is recoverable.

  Returns true only if the error is definitively recoverable.
  Returns false for both non-recoverable and unknown (nil) types.

  ## Examples

      iex> CCXT.Error.Recoverability.recoverable?(:rate_limited)
      true

      iex> CCXT.Error.Recoverability.recoverable?(:invalid_credentials)
      false

      iex> CCXT.Error.Recoverability.recoverable?(:exchange_error)
      false

  """
  @spec recoverable?(error_type()) :: boolean()
  def recoverable?(type), do: for_type(type) == true
end
