defmodule CCXT.Signing.Behaviour do
  @moduledoc """
  Behaviour for signing pattern implementations.

  All signing patterns must implement the `sign/3` callback which takes
  a request, credentials, and pattern-specific config, returning a
  signed request with appropriate headers/params.

  ## Implementing a Pattern

  To create a new signing pattern:

      defmodule CCXT.Signing.MyPattern do
        @behaviour CCXT.Signing.Behaviour

        alias CCXT.Credentials
        alias CCXT.Signing

        @impl true
        def sign(request, credentials, config) do
          # Implementation...
          %{url: ..., method: ..., headers: ..., body: ...}
        end
      end

  ## Type Aliases

  This behaviour uses types defined in `CCXT.Signing`:

  - `t:CCXT.Signing.request/0` - Input request map
  - `t:CCXT.Credentials.t/0` - API credentials struct
  - `t:CCXT.Signing.config/0` - Pattern-specific configuration
  - `t:CCXT.Signing.signed_request/0` - Output signed request map
  """

  alias CCXT.Credentials
  alias CCXT.Signing

  @doc """
  Signs a request using the pattern's authentication method.

  ## Parameters

  - `request` - Map with `:method`, `:path`, `:body`, and `:params`
  - `credentials` - `CCXT.Credentials` struct with API key and secret
  - `config` - Pattern-specific configuration from the exchange spec

  ## Returns

  A signed request map with `:url`, `:method`, `:headers`, and `:body`.
  """
  @callback sign(
              request :: Signing.request(),
              credentials :: Credentials.t(),
              config :: Signing.config()
            ) :: Signing.signed_request()
end
