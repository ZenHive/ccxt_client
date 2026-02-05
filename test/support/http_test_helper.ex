defmodule CCXT.Test.HTTPHelper do
  @moduledoc """
  Test helpers for HTTP request stubbing using Req.Test.

  ## Usage

      # In your test
      import CCXT.Test.HTTPHelper

      test "fetches ticker" do
        stub_json(:ticker_stub, %{"symbol" => "BTC/USDT", "last" => 50000})

        {:ok, response} = Client.request(spec, :get, "/ticker",
          plug: {Req.Test, :ticker_stub})

        assert response.body["symbol"] == "BTC/USDT"
      end

  ## Available Helpers

  - `stub_json/2` - Stub a successful JSON response
  - `stub_error/3` - Stub an error response with status code
  - `stub_rate_limited/2` - Stub a 429 rate limit response
  - `stub_html/3` - Stub an HTML response (simulates geo-blocking)

  """

  @doc """
  Stub a successful JSON response.

  ## Examples

      stub_json(:ticker_stub, %{"symbol" => "BTC/USDT", "last" => 50000})

  """
  @spec stub_json(atom(), map() | list()) :: :ok
  def stub_json(name, response) do
    Req.Test.stub(name, fn conn ->
      Req.Test.json(conn, response)
    end)
  end

  @doc """
  Stub an error response with status code.

  ## Examples

      stub_error(:not_found, 404, %{"message" => "Order not found"})
      stub_error(:server_error, 500)

  """
  @spec stub_error(atom(), integer(), map()) :: :ok
  def stub_error(name, status, body \\ %{}) do
    Req.Test.stub(name, fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(body)
    end)
  end

  @doc """
  Stub a rate limit response (HTTP 429).

  ## Examples

      stub_rate_limited(:rate_limit_stub)
      stub_rate_limited(:rate_limit_stub, 10)  # retry after 10 seconds

  """
  @spec stub_rate_limited(atom(), integer()) :: :ok
  def stub_rate_limited(name, retry_after_seconds \\ 5) do
    Req.Test.stub(name, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("retry-after", to_string(retry_after_seconds))
      |> Plug.Conn.put_status(429)
      |> Req.Test.json(%{"message" => "Rate limited"})
    end)
  end

  @doc """
  Stub an HTML response (simulates geo-blocking or access restrictions).

  ## Examples

      stub_html(:blocked_stub, "<html><title>Access Denied</title></html>")
      stub_html(:error_page, "<html><title>Error</title></html>", 403)

  """
  @spec stub_html(atom(), String.t(), integer()) :: :ok
  def stub_html(name, html_content, status \\ 200) do
    Req.Test.stub(name, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(status, html_content)
    end)
  end
end
