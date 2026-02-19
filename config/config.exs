import Config

config :ccxt_client,
  pipeline: [
    coercer: CCXT.ResponseCoercer,
    parsers: CCXT.Generator.Functions.Parsers,
    normalizer: CCXT.WS.Normalizer,
    contract: CCXT.WS.Contract
  ]
