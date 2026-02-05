defmodule CCXT.Signing.Custom do
  @moduledoc """
  Custom signing escape hatch for exchanges with non-standard authentication.

  Used by: <5% of exchanges that don't fit the standard patterns.

  ## How it works

  Delegates to a user-provided module that implements the `sign/3` callback.

  ## Configuration

      signing: %{
        pattern: :custom,
        custom_module: MyApp.CustomSigners.GateIO
      }

  ## Custom Module Implementation

  The custom module must implement a `sign/3` function:

      defmodule MyApp.CustomSigners.GateIO do
        @behaviour CCXT.Signing.Custom

        @impl true
        def sign(request, credentials, config) do
          # Custom signing logic here
          %{
            url: request.path,
            method: request.method,
            headers: [...],
            body: ...
          }
        end
      end

  """

  @behaviour CCXT.Signing.Behaviour

  alias CCXT.Credentials
  alias CCXT.Signing

  @doc """
  Callback for custom signing implementations.

  ## Parameters

  - `request` - Map with `:method`, `:path`, `:body`, and `:params`
  - `credentials` - `CCXT.Credentials` struct
  - `config` - Exchange-specific signing configuration

  ## Returns

  A signed request map with `:url`, `:method`, `:headers`, and `:body`.
  """
  @callback sign(Signing.request(), Credentials.t(), Signing.config()) :: Signing.signed_request()

  @doc """
  Delegates signing to the custom module specified in config.

  Raises `ArgumentError` if `:custom_module` is not specified in config.
  """
  @impl true
  @spec sign(Signing.request(), Credentials.t(), Signing.config()) :: Signing.signed_request()
  def sign(request, credentials, config) do
    case Map.fetch(config, :custom_module) do
      {:ok, module} when is_atom(module) ->
        module.sign(request, credentials, config)

      _ ->
        raise ArgumentError, """
        Custom signing pattern requires :custom_module in config.

        Example:
            signing: %{
              pattern: :custom,
              custom_module: MyApp.CustomSigners.GateIO
            }
        """
    end
  end
end
