defmodule CCXT.Error do
  @moduledoc """
  Unified error types for exchange operations.

  All exchange errors are normalized to this struct, providing consistent
  error handling across different exchanges.

  ## Error Types

  - `:rate_limited` - Too many requests, retry after `retry_after` ms
  - `:insufficient_balance` - Not enough funds for the operation
  - `:invalid_credentials` - API key/secret rejected by exchange
  - `:order_not_found` - Order ID does not exist
  - `:invalid_order` - Order parameters are invalid
  - `:market_closed` - Market is not currently trading
  - `:network_error` - Connection or timeout issue
  - `:access_restricted` - Geographic/IP block or access restriction (HTML response)
  - `:not_supported` - Method not supported by this exchange class (CCXT inheritance quirk)
  - `:circuit_open` - Circuit breaker tripped due to consecutive failures
  - `:exchange_error` - Generic exchange error (see `code` and `message`)

  ## Example

      case CCXT.Bybit.create_order(creds, "BTC/USDT", :limit, :buy, 0.001, 50000) do
        {:ok, order} -> handle_order(order)
        {:error, %CCXT.Error{type: :insufficient_balance}} -> notify_low_balance()
        {:error, %CCXT.Error{type: :rate_limited, retry_after: ms}} -> Process.sleep(ms)
        {:error, %CCXT.Error{} = err} -> Logger.error("Exchange error: \#{err.message}")
      end

  """

  alias CCXT.Error.Hints
  alias CCXT.Error.Recoverability

  @type error_type ::
          :rate_limited
          | :insufficient_balance
          | :invalid_credentials
          | :invalid_parameters
          | :order_not_found
          | :invalid_order
          | :market_closed
          | :network_error
          | :access_restricted
          | :not_supported
          | :circuit_open
          | :exchange_error

  @type t :: %__MODULE__{
          type: error_type(),
          code: String.t() | integer() | nil,
          message: String.t(),
          exchange: atom() | nil,
          retry_after: non_neg_integer() | nil,
          raw: map() | nil,
          hints: [String.t()],
          recoverable: boolean() | nil
        }

  defstruct [:type, :code, :message, :exchange, :retry_after, :raw, :recoverable, hints: []]

  @doc """
  Creates a rate limited error.

  ## Options

  - `:retry_after` - Milliseconds until retry is allowed
  - `:exchange` - Exchange atom (e.g., `:binance`)
  - `:raw` - Original error response from exchange
  """
  @spec rate_limited(keyword()) :: t()
  def rate_limited(opts \\ []) do
    build_error(:rate_limited, "Rate limit exceeded", opts)
  end

  @doc """
  Creates an insufficient balance error.
  """
  @spec insufficient_balance(keyword()) :: t()
  def insufficient_balance(opts \\ []) do
    build_error(:insufficient_balance, "Insufficient balance", opts)
  end

  @doc """
  Creates an invalid credentials error.
  """
  @spec invalid_credentials(keyword()) :: t()
  def invalid_credentials(opts \\ []) do
    build_error(:invalid_credentials, "Invalid API credentials", opts)
  end

  @doc """
  Creates an order not found error.
  """
  @spec order_not_found(keyword()) :: t()
  def order_not_found(opts \\ []) do
    build_error(:order_not_found, "Order not found", opts)
  end

  @doc """
  Creates an invalid order error.
  """
  @spec invalid_order(keyword()) :: t()
  def invalid_order(opts \\ []) do
    build_error(:invalid_order, "Invalid order parameters", opts)
  end

  @doc """
  Creates an invalid parameters error.
  """
  @spec invalid_parameters(keyword()) :: t()
  def invalid_parameters(opts \\ []) do
    build_error(:invalid_parameters, "Invalid request parameters", opts)
  end

  @doc """
  Creates a market closed error.
  """
  @spec market_closed(keyword()) :: t()
  def market_closed(opts \\ []) do
    build_error(:market_closed, "Market is closed", opts)
  end

  @doc """
  Creates a network error.
  """
  @spec network_error(keyword()) :: t()
  def network_error(opts \\ []) do
    build_error(:network_error, "Network error", opts)
  end

  @doc """
  Creates an access restricted error.

  Used when exchange returns HTML instead of JSON, typically indicating
  geographic/IP restrictions, Cloudflare challenges, or access blocks.
  """
  @spec access_restricted(keyword()) :: t()
  def access_restricted(opts \\ []) do
    build_error(:access_restricted, "Access restricted - exchange returned HTML instead of JSON", opts)
  end

  @doc """
  Creates a not supported error.

  Used when a method exists in CCXT's capability list but cannot actually be
  called for this exchange class (e.g., inherited methods that only work for
  certain market types).
  """
  @spec not_supported(keyword()) :: t()
  def not_supported(opts \\ []) do
    build_error(:not_supported, "Method not supported by this exchange", opts)
  end

  @doc """
  Creates a circuit breaker open error.

  Used when an exchange's circuit breaker has tripped due to multiple consecutive
  failures. Requests are rejected fast to prevent cascade failures.

  ## Options

  - `:exchange` - Exchange atom (e.g., `:binance`)

  """
  @spec circuit_open(keyword()) :: t()
  def circuit_open(opts \\ []) do
    build_error(:circuit_open, "Circuit breaker is open", opts)
  end

  @doc """
  Creates a generic exchange error.

  Use this for errors that don't fit other categories.
  """
  @spec exchange_error(String.t(), keyword()) :: t()
  def exchange_error(message, opts \\ []) do
    build_error(:exchange_error, message, opts)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  @doc false
  # Builds an error struct with consistent field population.
  # Merges user-provided hints with auto-generated hints and sets recoverability.
  @spec build_error(error_type(), String.t(), keyword()) :: t()
  defp build_error(type, default_message, opts) do
    user_hints = Keyword.get(opts, :hints, [])

    %__MODULE__{
      type: type,
      message: Keyword.get(opts, :message, default_message),
      code: Keyword.get(opts, :code),
      retry_after: Keyword.get(opts, :retry_after),
      exchange: Keyword.get(opts, :exchange),
      raw: Keyword.get(opts, :raw),
      hints: Hints.merge_hints(user_hints, type, opts),
      recoverable: Recoverability.for_type(type)
    }
  end
end
