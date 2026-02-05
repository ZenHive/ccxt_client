defmodule CCXT.Credentials do
  @moduledoc """
  Credentials for authenticating with an exchange.

  All authenticated API calls require credentials. The specific fields needed
  vary by exchange:

  - `api_key` and `secret` are required for most exchanges
  - `password` is required by some exchanges (e.g., OKX, KuCoin)
  - `sandbox` controls whether to use testnet/sandbox URLs

  ## Example

      credentials = %CCXT.Credentials{
        api_key: "your_api_key",
        secret: "your_secret",
        sandbox: true
      }

      CCXT.Bybit.fetch_balance(credentials)

  """

  @type t :: %__MODULE__{
          api_key: String.t(),
          secret: String.t(),
          password: String.t() | nil,
          sandbox: boolean()
        }

  @enforce_keys [:api_key, :secret]
  defstruct [:api_key, :secret, :password, sandbox: false]

  @doc """
  Creates a new Credentials struct.

  ## Options

  - `:api_key` - Required. The API key from the exchange.
  - `:secret` - Required. The API secret from the exchange.
  - `:password` - Optional. API password/passphrase (required by some exchanges).
  - `:sandbox` - Optional. Whether to use sandbox/testnet URLs. Defaults to `false`.

  ## Example

      {:ok, creds} = CCXT.Credentials.new(
        api_key: "abc123",
        secret: "xyz789",
        sandbox: true
      )

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, :missing_api_key | :missing_secret}
  def new(opts) when is_list(opts) do
    api_key = Keyword.get(opts, :api_key)
    secret = Keyword.get(opts, :secret)
    password = Keyword.get(opts, :password)
    sandbox = Keyword.get(opts, :sandbox, false)

    cond do
      is_nil(api_key) -> {:error, :missing_api_key}
      is_nil(secret) -> {:error, :missing_secret}
      true -> {:ok, %__MODULE__{api_key: api_key, secret: secret, password: password, sandbox: sandbox}}
    end
  end

  @doc """
  Creates a new Credentials struct, raising on error.

  See `new/1` for options.
  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    case new(opts) do
      {:ok, credentials} -> credentials
      {:error, :missing_api_key} -> raise ArgumentError, "api_key is required"
      {:error, :missing_secret} -> raise ArgumentError, "secret is required"
    end
  end
end
