defmodule CCXT.Generator.Functions.Parsers do
  @moduledoc """
  Generates parser mapping module attributes and introspection for exchange modules.

  Loads P1 mapping analysis data at compile time and generates `@ccxt_parser_*`
  module attributes containing instruction lists for each supported parse method.

  ## Generated Attributes

  - `@ccxt_parser_ticker` — Instructions for parseTicker (or nil)
  - `@ccxt_parser_trade` — Instructions for parseTrade (or nil)
  - `@ccxt_parser_order` — Instructions for parseOrder (or nil)
  - `@ccxt_parser_funding_rate` — Instructions for parseFundingRate (or nil)
  - `@ccxt_parser_position` — Instructions for parsePosition (or nil)
  - `@ccxt_parser_transaction` — Instructions for parseTransaction (or nil)
  - `@ccxt_parser_transfer` — Instructions for parseTransfer (or nil)
  - `@ccxt_parser_deposit_address` — Instructions for parseDepositAddress (or nil)
  - `@ccxt_parser_ledger_entry` — Instructions for parseLedgerEntry (or nil)
  - `@ccxt_parser_leverage` — Instructions for parseLeverage (or nil)
  - `@ccxt_parser_trading_fee` — Instructions for parseTradingFee (or nil)
  - `@ccxt_parser_deposit_withdraw_fee` — Instructions for parseDepositWithdrawFee (or nil)
  - `@ccxt_parser_margin_modification` — Instructions for parseMarginModification (or nil)
  - `@ccxt_parser_open_interest` — Instructions for parseOpenInterest (or nil)
  - `@ccxt_parser_margin_mode` — Instructions for parseMarginMode (or nil)
  - `@ccxt_parser_liquidation` — Instructions for parseLiquidation (or nil)
  - `@ccxt_parser_funding_rate_history` — Instructions for parseFundingRateHistory (or nil)
  - `@ccxt_parser_borrow_interest` — Instructions for parseBorrowInterest (or nil)
  - `@ccxt_parser_borrow_rate` — Instructions for parseBorrowRate (or nil)
  - `@ccxt_parser_conversion` — Instructions for parseConversion (or nil)
  - `@ccxt_parser_greeks` — Instructions for parseGreeks (or nil)
  - `@ccxt_parser_account` — Instructions for parseAccount (or nil)
  - `@ccxt_parser_option` — Instructions for parseOption (or nil)
  - `@ccxt_parser_funding_history` — Instructions for parseFundingHistory (or nil)
  - `@ccxt_parser_isolated_borrow_rate` — Instructions for parseIsolatedBorrowRate (or nil)
  - `@ccxt_parser_last_price` — Instructions for parseLastPrice (or nil)
  - `@ccxt_parser_long_short_ratio` — Instructions for parseLongShortRatio (or nil)
  - `@ccxt_parser_leverage_tier` — Instructions for parseLeverageTiers (or nil)
  - `@ccxt_parser_balance` — Instructions for parseBalance (or nil)

  ## Generated Functions

  - `__ccxt_parsers__/0` — Returns a map of available parser names to their instruction lists

  """

  alias CCXT.ResponseParser.MappingCompiler
  alias CCXT.Spec

  # Load P1 analysis data at compile time (same pattern as endpoints.ex)
  @analysis_path MappingCompiler.analysis_path()
  @external_resource @analysis_path
  @analysis MappingCompiler.load_analysis()

  # Parse methods to generate attributes for, with their attribute names and response type atoms
  @parser_methods [
    {"parseTicker", :ccxt_parser_ticker, :ticker},
    {"parseTrade", :ccxt_parser_trade, :trade},
    {"parseOrder", :ccxt_parser_order, :order},
    {"parseFundingRate", :ccxt_parser_funding_rate, :funding_rate},
    {"parsePosition", :ccxt_parser_position, :position},
    {"parseTransaction", :ccxt_parser_transaction, :transaction},
    {"parseTransfer", :ccxt_parser_transfer, :transfer},
    {"parseDepositAddress", :ccxt_parser_deposit_address, :deposit_address},
    {"parseLedgerEntry", :ccxt_parser_ledger_entry, :ledger_entry},
    {"parseLeverage", :ccxt_parser_leverage, :leverage},
    {"parseTradingFee", :ccxt_parser_trading_fee, :trading_fee},
    {"parseDepositWithdrawFee", :ccxt_parser_deposit_withdraw_fee, :deposit_withdraw_fee},
    {"parseMarginModification", :ccxt_parser_margin_modification, :margin_modification},
    {"parseOpenInterest", :ccxt_parser_open_interest, :open_interest},
    {"parseMarginMode", :ccxt_parser_margin_mode, :margin_mode},
    {"parseLiquidation", :ccxt_parser_liquidation, :liquidation},
    {"parseFundingRateHistory", :ccxt_parser_funding_rate_history, :funding_rate_history},
    {"parseBorrowInterest", :ccxt_parser_borrow_interest, :borrow_interest},
    {"parseBorrowRate", :ccxt_parser_borrow_rate, :borrow_rate},
    {"parseConversion", :ccxt_parser_conversion, :conversion},
    {"parseGreeks", :ccxt_parser_greeks, :greeks},
    {"parseAccount", :ccxt_parser_account, :account},
    {"parseOption", :ccxt_parser_option, :option},
    {"parseFundingHistory", :ccxt_parser_funding_history, :funding_history},
    {"parseIsolatedBorrowRate", :ccxt_parser_isolated_borrow_rate, :isolated_borrow_rate},
    {"parseLastPrice", :ccxt_parser_last_price, :last_price},
    {"parseLongShortRatio", :ccxt_parser_long_short_ratio, :long_short_ratio},
    {"parseLeverageTiers", :ccxt_parser_leverage_tier, :leverage_tier},
    {"parseBalance", :ccxt_parser_balance, :balance},
    {"parseOrderBook", :ccxt_parser_order_book, :order_book}
  ]

  @doc """
  Generates parser mapping attributes and introspection function for an exchange.

  Returns AST that:
  1. Defines `@ccxt_parser_*` module attributes with compiled instruction lists
  2. Defines `__ccxt_parsers__/0` introspection function
  """
  @spec generate_parsers(Spec.t()) :: Macro.t()
  def generate_parsers(spec) do
    exchange_id = spec.id

    # Compile mappings for each parse method at macro expansion time
    compiled =
      Enum.map(@parser_methods, fn {parse_method, attr_name, type_atom} ->
        instructions = MappingCompiler.compile_mapping(exchange_id, parse_method, @analysis)
        {attr_name, type_atom, instructions}
      end)

    # Generate module attribute definitions
    attr_asts =
      Enum.map(compiled, fn {attr_name, _type_atom, instructions} ->
        escaped = Macro.escape(instructions)

        quote do
          @doc false
          Module.put_attribute(__MODULE__, unquote(attr_name), unquote(escaped))
        end
      end)

    # Build parsers map for introspection (only non-nil entries)
    parsers_map =
      compiled
      |> Enum.reject(fn {_attr, _type, instructions} -> is_nil(instructions) end)
      |> Map.new(fn {_attr, type_atom, instructions} -> {type_atom, instructions} end)

    escaped_parsers = Macro.escape(parsers_map)

    introspection_ast =
      quote do
        @doc "Returns available response parser mappings for this exchange"
        @spec __ccxt_parsers__() :: %{atom() => [CCXT.ResponseParser.instruction()]}
        def __ccxt_parsers__, do: unquote(escaped_parsers)
      end

    quote do
      (unquote_splicing(attr_asts))
      unquote(introspection_ast)
    end
  end

  @doc """
  Returns the module attribute name for a given response type atom.

  Used by endpoint generation to reference the correct parser mapping.

  ## Examples

      iex> CCXT.Generator.Functions.Parsers.parser_attr_for_type(:ticker)
      :ccxt_parser_ticker

      iex> CCXT.Generator.Functions.Parsers.parser_attr_for_type(:unknown)
      nil

  """
  @spec parser_attr_for_type(atom()) :: atom() | nil
  def parser_attr_for_type(type_atom) do
    case Enum.find(@parser_methods, fn {_method, _attr, t} -> t == type_atom end) do
      {_method, attr_name, _type} -> attr_name
      nil -> nil
    end
  end
end
