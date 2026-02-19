defmodule CCXT.WS.Auth do
  @moduledoc """
  WebSocket authentication pattern library.

  This module provides a unified interface for WebSocket authentication across
  exchanges. Instead of per-exchange auth code, we implement parameterized
  patterns that cover all CCXT Pro exchanges with private WS channels.

  ## Auth Patterns

  | Pattern | Exchanges | Description |
  |---------|-----------|-------------|
  | `:direct_hmac_expiry` | Bybit, Bitmex | GET/realtime + expires, op: "auth" |
  | `:iso_passphrase` | OKX, Bitget | ISO timestamp + passphrase |
  | `:jsonrpc_linebreak` | Deribit | JSON-RPC with linebreak payload |
  | `:sha384_nonce` | Bitfinex | AUTH + nonce with SHA384 |
  | `:sha512_newline` | Gate | Newline-separated with SHA512 |
  | `:listen_key` | Binance | REST pre-auth for listen key |
  | `:rest_token` | Kraken | REST pre-auth for token |
  | `:inline_subscribe` | Coinbase | Auth in subscribe messages |

  ## Usage

  Auth is configured in the spec's ws.auth section and used via the adapter:

      # Authenticate before subscribing to private channels
      :ok = Adapter.authenticate(adapter)

      # Subscribe to private channel
      :ok = Adapter.subscribe(adapter, watch_balance_sub)

  For manual auth message building:

      config = spec.ws.auth
      {:ok, message} = CCXT.WS.Auth.build_auth_message(credentials, config)

  """

  alias CCXT.Credentials
  alias CCXT.WS.Auth.DirectHmacExpiry
  alias CCXT.WS.Auth.InlineSubscribe
  alias CCXT.WS.Auth.IsoPassphrase
  alias CCXT.WS.Auth.JsonrpcLinebreak
  alias CCXT.WS.Auth.ListenKey
  alias CCXT.WS.Auth.RestToken
  alias CCXT.WS.Auth.Sha384Nonce
  alias CCXT.WS.Auth.Sha512Newline

  @type pattern ::
          :direct_hmac_expiry
          | :iso_passphrase
          | :jsonrpc_linebreak
          | :sha384_nonce
          | :sha512_newline
          | :htx_variant
          | :listen_key
          | :rest_token
          | :inline_subscribe
          | :generic_hmac

  @type config :: map()
  @type auth_message :: map()
  @type pre_auth_result :: {:ok, map()} | {:error, term()}
  @type build_result :: {:ok, auth_message()} | :no_message | {:error, term()}

  @doc """
  Performs pre-authentication if the pattern requires it (REST call for token/key).

  Returns `{:ok, pre_auth_data}` with any data needed for WS connection,
  or `{:error, reason}` on failure.

  For patterns that don't need pre-auth, returns `{:ok, %{}}`.
  """
  @spec pre_auth(pattern(), Credentials.t(), config(), keyword()) :: pre_auth_result()
  def pre_auth(:listen_key, credentials, config, opts) do
    ListenKey.pre_auth(credentials, config, opts)
  end

  def pre_auth(:rest_token, credentials, config, opts) do
    RestToken.pre_auth(credentials, config, opts)
  end

  def pre_auth(_pattern, _credentials, _config, _opts) do
    {:ok, %{}}
  end

  @doc """
  Builds the WebSocket authentication message.

  Returns `{:ok, message}` with the JSON-encodable auth message,
  `:no_message` if no WS message is needed, or `{:error, reason}`.
  """
  @spec build_auth_message(pattern(), Credentials.t(), config(), keyword()) :: build_result()
  def build_auth_message(:direct_hmac_expiry, credentials, config, opts) do
    DirectHmacExpiry.build_auth_message(credentials, config, opts)
  end

  def build_auth_message(:iso_passphrase, credentials, config, opts) do
    IsoPassphrase.build_auth_message(credentials, config, opts)
  end

  def build_auth_message(:jsonrpc_linebreak, credentials, config, opts) do
    JsonrpcLinebreak.build_auth_message(credentials, config, opts)
  end

  def build_auth_message(:sha384_nonce, credentials, config, opts) do
    Sha384Nonce.build_auth_message(credentials, config, opts)
  end

  def build_auth_message(:sha512_newline, credentials, config, opts) do
    Sha512Newline.build_auth_message(credentials, config, opts)
  end

  def build_auth_message(:listen_key, _credentials, _config, _opts) do
    # Listen key pattern: auth via REST, no WS message needed
    :no_message
  end

  def build_auth_message(:rest_token, _credentials, _config, _opts) do
    # Rest token pattern: token sent in subscribe messages, no standalone auth
    :no_message
  end

  def build_auth_message(:inline_subscribe, _credentials, _config, _opts) do
    # Inline pattern: auth included in subscribe, no standalone auth
    :no_message
  end

  def build_auth_message(:generic_hmac, credentials, config, opts) do
    # Generic fallback - try to build based on config
    DirectHmacExpiry.build_auth_message(credentials, config, opts)
  end

  def build_auth_message(:htx_variant, _credentials, _config, _opts) do
    # TODO: HTX has market-specific auth formats (different for spot vs futures).
    # Implement CCXT.WS.Auth.HtxVariant when HTX WebSocket support is needed.
    {:error, {:not_implemented, :htx_variant}}
  end

  def build_auth_message(pattern, _credentials, _config, _opts) do
    {:error, {:unknown_pattern, pattern}}
  end

  @doc """
  Builds auth data to include in subscribe messages (for inline_subscribe pattern).
  """
  @spec build_subscribe_auth(pattern(), Credentials.t(), config(), String.t(), list()) ::
          map() | nil
  def build_subscribe_auth(:inline_subscribe, credentials, config, channel, symbols) do
    InlineSubscribe.build_subscribe_auth(credentials, config, channel, symbols)
  end

  def build_subscribe_auth(:rest_token, _credentials, config, _channel, _symbols) do
    # Include token from pre-auth in subscribe messages
    token = config[:token]
    if token, do: %{"token" => token}
  end

  def build_subscribe_auth(_pattern, _credentials, _config, _channel, _symbols) do
    nil
  end

  @doc """
  Handles the authentication response from the server.

  Returns `:ok` on successful auth, `{:ok, auth_meta}` with metadata
  (e.g., `%{ttl_ms: 900_000}` for session expiry scheduling), or
  `{:error, reason}` on failure.
  """
  @spec handle_auth_response(pattern(), map(), map()) :: :ok | {:ok, map()} | {:error, term()}
  def handle_auth_response(:direct_hmac_expiry, response, state) do
    DirectHmacExpiry.handle_auth_response(response, state)
  end

  def handle_auth_response(:iso_passphrase, response, state) do
    IsoPassphrase.handle_auth_response(response, state)
  end

  def handle_auth_response(:jsonrpc_linebreak, response, state) do
    JsonrpcLinebreak.handle_auth_response(response, state)
  end

  def handle_auth_response(:sha384_nonce, response, state) do
    Sha384Nonce.handle_auth_response(response, state)
  end

  def handle_auth_response(:sha512_newline, response, state) do
    Sha512Newline.handle_auth_response(response, state)
  end

  def handle_auth_response(_pattern, response, _state) do
    # Default: check for common success indicators
    cond do
      response["success"] == true -> :ok
      response["event"] == "auth" && response["status"] == "OK" -> :ok
      response["result"] && response["result"]["access_token"] -> :ok
      true -> {:error, {:auth_failed, response}}
    end
  end

  @doc """
  Returns the list of supported auth patterns.
  """
  @spec patterns() :: [pattern()]
  def patterns do
    [
      :direct_hmac_expiry,
      :iso_passphrase,
      :jsonrpc_linebreak,
      :sha384_nonce,
      :sha512_newline,
      :htx_variant,
      :listen_key,
      :rest_token,
      :inline_subscribe,
      :generic_hmac
    ]
  end

  @doc """
  Checks if a pattern requires pre-authentication.
  """
  @spec requires_pre_auth?(pattern()) :: boolean()
  def requires_pre_auth?(:listen_key), do: true
  def requires_pre_auth?(:rest_token), do: true
  def requires_pre_auth?(_), do: false

  @doc """
  Checks if a pattern uses inline authentication.
  """
  @spec inline_auth?(pattern()) :: boolean()
  def inline_auth?(:inline_subscribe), do: true
  def inline_auth?(_), do: false

  @doc """
  Returns the auth module for a pattern (for testing).
  """
  @spec module_for_pattern(pattern()) :: module() | nil
  def module_for_pattern(:direct_hmac_expiry), do: DirectHmacExpiry
  def module_for_pattern(:iso_passphrase), do: IsoPassphrase
  def module_for_pattern(:jsonrpc_linebreak), do: JsonrpcLinebreak
  def module_for_pattern(:sha384_nonce), do: Sha384Nonce
  def module_for_pattern(:sha512_newline), do: Sha512Newline
  def module_for_pattern(:listen_key), do: ListenKey
  def module_for_pattern(:rest_token), do: RestToken
  def module_for_pattern(:inline_subscribe), do: InlineSubscribe
  def module_for_pattern(_), do: nil
end
