defmodule CCXT.Signing.Custom do
  @moduledoc """
  Custom signing escape hatch for exchanges with non-standard authentication.

  Used by: <5% of exchanges that don't fit the standard patterns.

  The primary contract for custom signing is `CCXT.Signing.Behaviour`. This
  module delegates to a user-provided module that implements `sign/3`.

  ## Configuration

      signing: %{
        pattern: :custom,
        custom_module: MyApp.CustomSigners.MyExchange
      }

  ## Custom Module Implementation

  Custom modules should implement `CCXT.Signing.Behaviour`:

      defmodule MyApp.CustomSigners.MyExchange do
        @behaviour CCXT.Signing.Behaviour

        @impl true
        def sign(request, credentials, config) do
          %{
            url: request.path,
            method: request.method,
            headers: [{"X-API-KEY", credentials.api_key}],
            body: request.body
          }
        end
      end

  ## Validation

  Use `validate_module/1` to verify a module at runtime:

      {:ok, _} = CCXT.Signing.Custom.validate_module(MyApp.CustomSigners.MyExchange)

  See `CCXT.Signing.Behaviour` for the full contract and available helpers.
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
  Validates that a module implements the signing contract (`sign/3`).

  Returns `{:ok, module}` if the module exports `sign/3`, or
  `{:error, reason}` with an actionable message.
  """
  @spec validate_module(module()) :: {:ok, module()} | {:error, String.t()}
  def validate_module(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, _} ->
        if function_exported?(module, :sign, 3) do
          {:ok, module}
        else
          {:error, "#{inspect(module)} must implement sign/3 (see CCXT.Signing.Behaviour)"}
        end

      {:error, reason} ->
        {:error, "Could not load #{inspect(module)}: #{reason} (see CCXT.Signing.Behaviour)"}
    end
  end

  @doc """
  Delegates signing to the custom module specified in config.

  Raises `ArgumentError` if `:custom_module` is not specified in config
  or if the module does not implement `sign/3`.
  """
  @impl true
  @spec sign(Signing.request(), Credentials.t(), Signing.config()) :: Signing.signed_request()
  def sign(request, credentials, config) do
    case Map.fetch(config, :custom_module) do
      {:ok, module} when is_atom(module) ->
        case validate_module(module) do
          {:ok, _} ->
            module.sign(request, credentials, config)

          {:error, reason} ->
            raise ArgumentError, reason
        end

      _ ->
        raise ArgumentError, """
        Custom signing pattern requires :custom_module in config.

        Example:
            signing: %{
              pattern: :custom,
              custom_module: MyApp.CustomSigners.MyExchange
            }
        """
    end
  end
end
