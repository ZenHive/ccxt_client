defmodule CCXT.Signing.Deribit do
  @moduledoc """
  Deribit-style HMAC-SHA256 signing with custom Authorization header.

  Deribit uses a unique authentication format that differs from other exchanges:

  ## How it works

  1. Generate timestamp (milliseconds) and nonce (also milliseconds)
  2. Build request data: `METHOD\\npath?query\\nbody\\n`
  3. Build auth string: `timestamp\\nnonce\\nrequest_data`
  4. Sign with HMAC-SHA256 (hex encoded)
  5. Set Authorization header: `deri-hmac-sha256 id={key},ts={ts},sig={sig},nonce={nonce}`

  ## Configuration

      signing: %{
        pattern: :deribit
      }

  No additional configuration needed - the format is fixed.
  """

  @behaviour CCXT.Signing.Behaviour

  alias CCXT.Credentials
  alias CCXT.Signing

  @doc """
  Signs a request using Deribit's custom HMAC-SHA256 Authorization header format.
  """
  @impl true
  @spec sign(Signing.request(), Credentials.t(), Signing.config()) :: Signing.signed_request()
  def sign(request, credentials, _config) do
    timestamp = to_string(Signing.timestamp_ms())
    nonce = to_string(Signing.timestamp_ms())

    # Build query string
    query_string = Signing.urlencode(request.params)

    path_with_query =
      if query_string == "" do
        request.path
      else
        request.path <> "?" <> query_string
      end

    # Build auth payload: timestamp\nnonce\nMETHOD\npath\nbody\n
    method_upper = request.method |> to_string() |> String.upcase()
    # fail-loud:ignore - GET requests have nil body, empty string is correct for signature
    body = if request.body, do: request.body, else: ""
    request_data = "#{method_upper}\n#{path_with_query}\n#{body}\n"
    auth = "#{timestamp}\n#{nonce}\n#{request_data}"

    # Sign with HMAC-SHA256
    signature =
      auth
      |> Signing.hmac_sha256(credentials.secret)
      |> Signing.encode_hex()

    # Build Authorization header
    auth_header =
      "deri-hmac-sha256 id=#{credentials.api_key},ts=#{timestamp},sig=#{signature},nonce=#{nonce}"

    %{
      url: path_with_query,
      method: request.method,
      headers: [{"Authorization", auth_header}],
      body: request.body
    }
  end
end
