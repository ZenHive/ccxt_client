defmodule CCXT.Signing.Behaviour do
  @moduledoc """
  Behaviour for signing pattern implementations.

  ## Public API

  This IS the contract for custom signing implementations. Any module that
  implements `sign/3` can be used as a custom signing pattern via
  `CCXT.Signing.Custom`.

  ## Implementing a Custom Signing Pattern

  1. Create a module that implements this behaviour:

      defmodule MyApp.Signing.MyExchange do
        @behaviour CCXT.Signing.Behaviour

        @impl true
        def sign(request, credentials, config) do
          timestamp = CCXT.Signing.timestamp_ms()
          signature = CCXT.Signing.hmac_sha256(
            request.path <> to_string(timestamp),
            credentials.secret
          )

          %{
            url: request.path,
            method: request.method,
            headers: [
              {"X-API-KEY", credentials.api_key},
              {"X-TIMESTAMP", to_string(timestamp)},
              {"X-SIGNATURE", CCXT.Signing.encode_hex(signature)}
            ],
            body: request.body
          }
        end
      end

  2. Wire it into a spec:

      %{
        id: "my_exchange",
        name: "My Exchange",
        urls: %{api: "https://api.myexchange.com"},
        signing: %{
          pattern: :custom,
          custom_module: MyApp.Signing.MyExchange
        }
      }

  3. Validate the module (optional but recommended):

      CCXT.Signing.Custom.validate_module(MyApp.Signing.MyExchange)
      #=> {:ok, MyApp.Signing.MyExchange}

  ## Available Helpers

  `CCXT.Signing` provides crypto and encoding helpers for implementors:

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

  ## Notes

  - Custom modules should use `@behaviour CCXT.Signing.Behaviour`
  - The `config` parameter contains the full signing config from the spec
  - Use `CCXT.Signing.Custom.validate_module/1` to verify a module at runtime
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
