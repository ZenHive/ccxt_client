defmodule CCXT.Test.Generator.Helpers do
  @moduledoc """
  Runtime helper functions for generated tests.

  These functions are called at test runtime, not at compile time.
  They handle response validation, signature verification, and error reporting.

  ## Submodules

  - `CCXT.Test.Generator.Helpers.Signature` - Signature format validation
  - `CCXT.Test.Generator.Helpers.PublicResponse` - Public endpoint response validation
  - `CCXT.Test.Generator.Helpers.AuthenticatedResponse` - Authenticated endpoint response validation
  """

  alias CCXT.Test.Generator.Helpers.AuthenticatedResponse
  alias CCXT.Test.Generator.Helpers.PublicResponse
  alias CCXT.Test.Generator.Helpers.Signature

  @doc """
  Validates signature format based on encoding type.

  Delegates to `CCXT.Test.Generator.Helpers.Signature.validate_signature_format/2`.
  """
  @spec validate_signature_format(String.t() | nil, map()) :: :ok
  defdelegate validate_signature_format(signature, signing), to: Signature

  @doc """
  Asserts that a public endpoint response is valid.

  Handles both success and known error cases without hiding failures.

  Delegates to `CCXT.Test.Generator.Helpers.PublicResponse.assert_public_response/4`.
  """
  @spec assert_public_response(term(), atom(), String.t(), String.t() | nil) :: :ok
  defdelegate assert_public_response(result, method, exchange_id, symbol), to: PublicResponse

  @doc """
  Asserts that an authenticated endpoint response is valid.

  Handles both success and known error cases without hiding failures.
  Similar to `assert_public_response/4` but with auth-specific error handling.

  ## Options

    * `:allow_not_found` - If true, treats "order not found" errors as acceptable (for fetch_order tests)
    * `:allow_invalid_order` - If true, treats "invalid order format" errors as acceptable (for invalid ID tests)

  Delegates to `CCXT.Test.Generator.Helpers.AuthenticatedResponse.assert_authenticated_response/6`.
  """
  @spec assert_authenticated_response(term(), atom(), String.t(), String.t() | nil, keyword(), keyword()) ::
          :ok
  def assert_authenticated_response(result, method, exchange_id, symbol, credential_opts, opts \\ []) do
    AuthenticatedResponse.assert_authenticated_response(result, method, exchange_id, symbol, credential_opts, opts)
  end
end
