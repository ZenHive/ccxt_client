defmodule CCXT.Pipeline do
  @moduledoc false

  # Single source of truth for the default normalization pipeline.
  # Referenced by both REST (CCXT.Generator) and WS (CCXT.WS.Generator) generators.
  # Hardcoded so it works when ccxt_client is compiled as a dependency
  # (dependency config files are not loaded by the parent app).
  # Override via `config :ccxt_client, pipeline: [...]` or `pipeline: []` to disable.
  @default [
    coercer: CCXT.ResponseCoercer,
    parsers: CCXT.Generator.Functions.Parsers,
    normalizer: CCXT.WS.Normalizer,
    contract: CCXT.WS.Contract
  ]

  @doc false
  @spec default() :: keyword()
  def default, do: @default
end
