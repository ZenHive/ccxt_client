defmodule CcxtClient.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CCXT.HTTP.RateLimiter,
      CCXT.Testnet
    ]

    opts = [strategy: :one_for_one, name: CcxtClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
