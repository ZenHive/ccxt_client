defmodule CCXT.Test.IntegrationHelper do
  @moduledoc """
  Helper macros and functions for integration tests.

  Reduces duplication in credential checking and setup across all integration tests.

  ## Usage

      defmodule CCXT.Exchanges.BybitIntegrationTest do
        use ExUnit.Case, async: false
        import CCXT.Test.IntegrationHelper

        @moduletag :integration

        setup do
          setup_credentials("bybit", module: CCXT.Bybit, testnet: true)
        end

        test "private endpoint", %{credentials: credentials, api_url: api_url} do
          require_credentials!(credentials, "bybit", testnet: true, api_url: api_url)
          # ... test code
        end
      end
  """

  import ExUnit.Assertions

  @type credential_opts() :: [
          module: module(),
          testnet: boolean(),
          passphrase: boolean(),
          url: String.t() | map(),
          secret_suffix: String.t(),
          sandbox: boolean(),
          api_url: String.t() | map()
        ]

  @doc """
  Flunks with a helpful message if credentials are nil.

  ## Options

    * `:testnet` - If true, env var names include TESTNET prefix (default: false)
    * `:passphrase` - If true, mentions passphrase in error message (default: false)
    * `:url` - URL where to get credentials (optional)
    * `:api_url` - The API URL that tests will hit (shown in flunk message)

  ## Examples

      require_credentials!(credentials, "bybit", testnet: true, url: "https://testnet.bybit.com")
      require_credentials!(credentials, "okx", passphrase: true, url: "https://www.okx.com/account/my-api")
      require_credentials!(credentials, "bybit", api_url: api_url, testnet: true)
  """
  defmacro require_credentials!(credentials, exchange_name, opts \\ []) do
    quote bind_quoted: [credentials: credentials, exchange_name: exchange_name, opts: opts] do
      alias CCXT.Test.IntegrationHelper

      if is_nil(credentials) do
        IntegrationHelper.flunk_missing_credentials(exchange_name, opts)
      end
    end
  end

  @doc """
  Returns a formatted error message for missing credentials.

  Used by `flunk_missing_credentials/2` and `setup_all` early failure.
  """
  @spec missing_credentials_message(String.t(), credential_opts()) :: String.t()
  def missing_credentials_message(exchange_name, opts \\ []) do
    testnet = Keyword.get(opts, :testnet, false)
    passphrase = Keyword.get(opts, :passphrase, false)
    url = Keyword.get(opts, :url)
    api_url = Keyword.get(opts, :api_url)

    prefix = String.upcase(exchange_name)
    testnet_part = if testnet, do: "_TESTNET", else: ""

    env_vars =
      if passphrase do
        """
          export #{prefix}#{testnet_part}_API_KEY="your_key"
          export #{prefix}#{testnet_part}_API_SECRET="your_secret"
          export #{prefix}_PASSPHRASE="your_passphrase"
        """
      else
        """
          export #{prefix}#{testnet_part}_API_KEY="your_key"
          export #{prefix}#{testnet_part}_API_SECRET="your_secret"
        """
      end

    url_string = stringify_url(url)
    api_url_string = stringify_url(api_url)

    url_line = if url_string, do: "\nGet credentials at: #{url_string}", else: ""
    api_url_line = if api_url_string, do: "\nAPI URL: #{api_url_string}", else: ""

    """
    Missing #{if testnet, do: "testnet ", else: ""}credentials for #{exchange_name}!#{api_url_line}

    Set these environment variables:
    #{String.trim(env_vars)}#{url_line}
    """
  end

  @doc """
  Flunks with a formatted error message for missing credentials.

  Called by `require_credentials!/3` macro. Can also be called directly.
  """
  @spec flunk_missing_credentials(String.t(), credential_opts()) :: no_return()
  def flunk_missing_credentials(exchange_name, opts \\ []) do
    flunk(missing_credentials_message(exchange_name, opts))
  end

  @doc """
  Standard setup for integration tests that loads credentials from env.

  Returns `{:ok, credentials: credentials, api_key: api_key, secret: secret, api_url: api_url}`
  for use in ExUnit setup.

  ## Options

    * `:module` - The exchange module (required). Used to compute API URL.
    * `:testnet` - If true, env var names include TESTNET prefix (default: false)
    * `:passphrase` - If true, also loads passphrase from env (default: false)
    * `:sandbox` - Value for `credentials.sandbox` (default: value of `:testnet`)
    * `:secret_suffix` - Override the secret env var suffix (default: "API_SECRET")

  ## Examples

      # Bybit testnet (BYBIT_TESTNET_API_KEY, BYBIT_TESTNET_API_SECRET)
      setup_credentials("bybit", module: CCXT.Bybit, testnet: true)

      # OKX with passphrase (OKX_API_KEY, OKX_API_SECRET, OKX_PASSPHRASE)
      setup_credentials("okx", module: CCXT.Okx, passphrase: true)

      # Deribit testnet with custom secret suffix (DERIBIT_TESTNET_API_KEY, DERIBIT_TESTNET_SECRET_KEY)
      setup_credentials("deribit", module: CCXT.Deribit, testnet: true, secret_suffix: "SECRET_KEY")
  """
  @spec setup_credentials(String.t(), credential_opts()) ::
          {:ok,
           credentials: CCXT.Credentials.t() | nil,
           api_key: String.t() | nil,
           secret: String.t() | nil,
           api_url: String.t()}
  def setup_credentials(exchange_name, opts \\ []) do
    module = Keyword.fetch!(opts, :module)
    testnet = Keyword.get(opts, :testnet, false)
    passphrase_opt = Keyword.get(opts, :passphrase, false)
    sandbox = Keyword.get(opts, :sandbox, testnet)
    secret_suffix = Keyword.get(opts, :secret_suffix, "API_SECRET")

    prefix = String.upcase(exchange_name)
    testnet_part = if testnet, do: "_TESTNET", else: ""

    api_key = System.get_env("#{prefix}#{testnet_part}_API_KEY")
    secret = System.get_env("#{prefix}#{testnet_part}_#{secret_suffix}")
    passphrase = if passphrase_opt, do: System.get_env("#{prefix}_PASSPHRASE")

    credentials = build_credentials(api_key, secret, passphrase, sandbox)

    # Compute API URL from module's spec
    spec = module.__ccxt_spec__()
    api_url = CCXT.Spec.api_url(spec, sandbox)

    {:ok, credentials: credentials, api_key: api_key, secret: secret, api_url: api_url}
  end

  @doc false
  # Recursively unwraps map-type URLs (e.g., Gate.io sandbox URLs are nested maps)
  @spec stringify_url(String.t() | map() | nil) :: String.t() | nil
  defp stringify_url(nil), do: nil
  defp stringify_url(url) when is_binary(url), do: url
  defp stringify_url(%{} = map), do: map |> Map.values() |> List.first() |> stringify_url()

  @spec build_credentials(String.t() | nil, String.t() | nil, String.t() | nil, boolean()) ::
          CCXT.Credentials.t() | nil
  defp build_credentials(nil, _secret, _passphrase, _sandbox), do: nil
  defp build_credentials(_api_key, nil, _passphrase, _sandbox), do: nil

  defp build_credentials(api_key, secret, nil, sandbox) do
    %CCXT.Credentials{api_key: api_key, secret: secret, sandbox: sandbox}
  end

  defp build_credentials(api_key, secret, passphrase, sandbox) do
    %CCXT.Credentials{api_key: api_key, secret: secret, password: passphrase, sandbox: sandbox}
  end
end
