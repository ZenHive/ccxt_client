defmodule CCXT.Signing do
  @moduledoc """
  Signing pattern library for exchange authentication.

  This module provides a unified interface for signing API requests across 100+
  cryptocurrency exchanges. Instead of per-exchange signing code, we implement
  7 parameterized patterns that cover 95%+ of all exchanges:

  | Pattern | Exchanges | Description |
  |---------|-----------|-------------|
  | `:hmac_sha256_query` | ~40 | Binance-style: sign query string |
  | `:hmac_sha256_headers` | ~30 | Bybit-style: sign body, headers |
  | `:hmac_sha256_iso_passphrase` | ~10 | OKX-style: ISO timestamp + passphrase |
  | `:hmac_sha256_passphrase_signed` | ~3 | KuCoin-style: HMAC-signed passphrase |
  | `:hmac_sha512_nonce` | ~3 | Kraken-style: SHA512 + nonce + base64 secret |
  | `:hmac_sha512_gate` | 1 | Gate.io-style: SHA512 + timestamp + newline payload |
  | `:hmac_sha384_payload` | ~3 | Bitfinex-style: payload signing |
  | `:custom` | <5% | Escape hatch for edge cases |

  ## Usage

  The signing is configured in the exchange spec:

      signing: %{
        pattern: :hmac_sha256_headers,
        api_key_header: "X-BAPI-API-KEY",
        timestamp_header: "X-BAPI-TIMESTAMP",
        signature_header: "X-BAPI-SIGN",
        recv_window_header: "X-BAPI-RECV-WINDOW",
        recv_window: 5000
      }

  Then used via the `sign/4` function:

      signed = CCXT.Signing.sign(
        :hmac_sha256_headers,
        %{method: :get, path: "/v5/account/wallet-balance", body: nil, params: %{}},
        credentials,
        signing_config
      )

  ## Custom Signing Patterns

  For exchanges that don't fit the standard patterns, implement
  `CCXT.Signing.Behaviour` and use the `:custom` pattern:

      defmodule MyApp.Signing.MyExchange do
        @behaviour CCXT.Signing.Behaviour

        @impl true
        def sign(request, credentials, config) do
          # Use helpers from this module:
          # timestamp_ms/0, hmac_sha256/2, encode_hex/1, etc.
          %{url: request.path, method: request.method, headers: [], body: request.body}
        end
      end

  See `CCXT.Signing.Behaviour` for the full contract and
  `CCXT.Signing.Custom` for wiring and validation.

  ### Helpers Available to Implementors

  | Function | Description |
  |----------|-------------|
  | `timestamp_ms/0` | Current time in milliseconds |
  | `timestamp_seconds/0` | Current time in seconds |
  | `timestamp_iso8601/0` | Current time as ISO 8601 string |
  | `hmac_sha256/2` | HMAC-SHA256 digest |
  | `hmac_sha384/2` | HMAC-SHA384 digest |
  | `hmac_sha512/2` | HMAC-SHA512 digest |
  | `sha256/1` | SHA256 hash |
  | `encode_hex/1` | Binary to lowercase hex string |
  | `encode_base64/1` | Binary to base64 string |
  | `decode_base64/1` | Base64 string to binary |
  | `urlencode/1` | Map to sorted URL-encoded query string |

  """

  alias CCXT.Credentials
  alias CCXT.Signing.Custom
  alias CCXT.Signing.Deribit
  alias CCXT.Signing.HmacSha256Headers
  alias CCXT.Signing.HmacSha256Iso
  alias CCXT.Signing.HmacSha256Kucoin
  alias CCXT.Signing.HmacSha256Query
  alias CCXT.Signing.HmacSha384Payload
  alias CCXT.Signing.HmacSha512Gate
  alias CCXT.Signing.HmacSha512Nonce

  @type method :: :get | :post | :put | :delete

  @type request :: %{
          method: method(),
          path: String.t(),
          body: String.t() | nil,
          params: map()
        }

  @type signed_request :: %{
          url: String.t(),
          method: method(),
          headers: [{String.t(), String.t()}],
          body: String.t() | nil
        }

  @type pattern ::
          :hmac_sha256_query
          | :hmac_sha256_headers
          | :hmac_sha256_iso_passphrase
          | :hmac_sha256_passphrase_signed
          | :hmac_sha512_nonce
          | :hmac_sha512_gate
          | :hmac_sha384_payload
          | :deribit
          | :custom

  @type config :: %{
          optional(:api_key_header) => String.t(),
          optional(:timestamp_header) => String.t(),
          optional(:signature_header) => String.t(),
          optional(:passphrase_header) => String.t(),
          optional(:recv_window_header) => String.t(),
          optional(:recv_window) => non_neg_integer(),
          optional(:timestamp_format) => :milliseconds | :seconds | :iso8601,
          optional(:signature_encoding) => :hex | :base64,
          optional(:sign_body) => boolean(),
          optional(:nonce_in_body) => boolean(),
          optional(:custom_module) => module(),
          optional(atom()) => term()
        }

  @doc """
  Signs a request using the specified pattern and configuration.

  ## Parameters

  - `pattern` - The signing pattern to use (e.g., `:hmac_sha256_headers`)
  - `request` - Map with `:method`, `:path`, `:body`, and `:params`
  - `credentials` - `CCXT.Credentials` struct with API key and secret
  - `config` - Pattern-specific configuration from the exchange spec

  ## Returns

  A signed request map with `:url`, `:method`, `:headers`, and `:body`.

  ## Example

      credentials = %CCXT.Credentials{api_key: "key", secret: "secret"}

      config = %{
        api_key_header: "X-BAPI-API-KEY",
        timestamp_header: "X-BAPI-TIMESTAMP",
        signature_header: "X-BAPI-SIGN"
      }

      request = %{
        method: :get,
        path: "/v5/market/tickers",
        body: nil,
        params: %{category: "spot"}
      }

      signed = CCXT.Signing.sign(:hmac_sha256_headers, request, credentials, config)

  """
  @spec sign(pattern(), request(), Credentials.t(), config()) :: signed_request()
  def sign(:hmac_sha256_query, request, credentials, config) do
    HmacSha256Query.sign(request, credentials, config)
  end

  def sign(:hmac_sha256_headers, request, credentials, config) do
    HmacSha256Headers.sign(request, credentials, config)
  end

  def sign(:hmac_sha256_iso_passphrase, request, credentials, config) do
    HmacSha256Iso.sign(request, credentials, config)
  end

  def sign(:hmac_sha256_passphrase_signed, request, credentials, config) do
    HmacSha256Kucoin.sign(request, credentials, config)
  end

  def sign(:hmac_sha512_nonce, request, credentials, config) do
    HmacSha512Nonce.sign(request, credentials, config)
  end

  def sign(:hmac_sha512_gate, request, credentials, config) do
    HmacSha512Gate.sign(request, credentials, config)
  end

  def sign(:hmac_sha384_payload, request, credentials, config) do
    HmacSha384Payload.sign(request, credentials, config)
  end

  def sign(:deribit, request, credentials, config) do
    Deribit.sign(request, credentials, config)
  end

  def sign(:custom, request, credentials, config) do
    Custom.sign(request, credentials, config)
  end

  @doc """
  Returns the list of supported signing patterns.
  """
  @spec patterns() :: [pattern()]
  def patterns do
    [
      :hmac_sha256_query,
      :hmac_sha256_headers,
      :hmac_sha256_iso_passphrase,
      :hmac_sha256_passphrase_signed,
      :hmac_sha512_nonce,
      :hmac_sha512_gate,
      :hmac_sha384_payload,
      :deribit,
      :custom
    ]
  end

  @doc """
  Checks if a pattern is supported.
  """
  @spec pattern?(atom()) :: boolean()
  def pattern?(pattern), do: pattern in patterns()

  @doc """
  Returns the signing module for a given pattern.

  Used by test generators to get the appropriate module for signing verification.
  """
  @spec module_for_pattern(pattern()) :: module() | nil
  def module_for_pattern(:hmac_sha256_query), do: HmacSha256Query
  def module_for_pattern(:hmac_sha256_headers), do: HmacSha256Headers
  def module_for_pattern(:hmac_sha256_iso_passphrase), do: HmacSha256Iso
  def module_for_pattern(:hmac_sha256_passphrase_signed), do: HmacSha256Kucoin
  def module_for_pattern(:hmac_sha512_nonce), do: HmacSha512Nonce
  def module_for_pattern(:hmac_sha512_gate), do: HmacSha512Gate
  def module_for_pattern(:hmac_sha384_payload), do: HmacSha384Payload
  def module_for_pattern(:deribit), do: Deribit
  def module_for_pattern(:custom), do: Custom
  def module_for_pattern(_), do: nil

  # Internal helpers used by pattern implementations

  @doc false
  @spec timestamp_ms() :: non_neg_integer()
  def timestamp_ms, do: System.system_time(:millisecond)

  @doc false
  @spec timestamp_seconds() :: non_neg_integer()
  def timestamp_seconds, do: System.system_time(:second)

  @doc false
  @spec timestamp_iso8601() :: String.t()
  def timestamp_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end

  @doc false
  @spec hmac_sha256(String.t(), String.t()) :: binary()
  def hmac_sha256(data, secret) do
    :crypto.mac(:hmac, :sha256, secret, data)
  end

  @doc false
  @spec hmac_sha384(String.t(), String.t()) :: binary()
  def hmac_sha384(data, secret) do
    :crypto.mac(:hmac, :sha384, secret, data)
  end

  @doc false
  @spec hmac_sha512(String.t(), binary()) :: binary()
  def hmac_sha512(data, secret) do
    :crypto.mac(:hmac, :sha512, secret, data)
  end

  @doc false
  @spec sha256(String.t()) :: binary()
  def sha256(data) do
    :crypto.hash(:sha256, data)
  end

  @doc false
  @spec encode_hex(binary()) :: String.t()
  def encode_hex(binary) do
    Base.encode16(binary, case: :lower)
  end

  @doc false
  @spec encode_base64(binary()) :: String.t()
  def encode_base64(binary) do
    Base.encode64(binary)
  end

  @doc false
  @spec decode_base64(String.t()) :: binary()
  def decode_base64(encoded) do
    Base.decode64!(encoded)
  end

  @doc false
  @spec urlencode(map() | nil) :: String.t()
  def urlencode(nil), do: ""
  def urlencode(params) when params == %{}, do: ""

  def urlencode(params) do
    params
    |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
    |> URI.encode_query()
  end

  @doc false
  @spec urlencode_raw(map() | nil) :: String.t()
  def urlencode_raw(nil), do: ""
  def urlencode_raw(params) when params == %{}, do: ""

  def urlencode_raw(params) do
    params
    |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
    |> Enum.map_join("&", fn {k, v} -> "#{k}=#{v}" end)
  end
end
