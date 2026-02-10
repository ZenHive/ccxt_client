# CCXT Types System

This directory contains Elixir type modules auto-generated from CCXT's TypeScript definitions.

## Architecture

```
priv/ccxt/ts/src/base/types.ts     (CCXT TypeScript source)
        │
        ▼ node priv/extractor/extract-types.cjs
priv/extractor/ccxt_types.json     (Normalized AST)
        │
        ▼ mix ccxt.gen.types
lib/ccxt/types/schema/*.ex         (Schema modules - defstruct + from_map)
lib/ccxt/types/*.ex                (Wrapper modules - use Schema + helpers)
```

## Stability Policy

The 6 core types (Ticker, Order, Position, OrderBook, Trade, Balance) follow
an **additive-only** contract between minor versions:

- **Fields**: Never removed or renamed. New fields may be added with `nil` defaults.
- **Field types**: May be widened (e.g., `String.t()` → `String.t() | atom()`), never narrowed.
- **Helper functions**: Signatures are stable between minor versions. New helpers may be added.
- **Removals/renames**: Only permitted at **major** version bumps with migration guide.

This policy ensures that code written against `%CCXT.Types.Ticker{}` or
`Order.open?/1` continues to work across minor upgrades.

**Enforcement**: `test/ccxt/types_stability_test.exs` contains a contracted
field list for each core type. Removing a contracted field will fail CI.

## Module Categories

### Schema Modules (`schema/*.ex`)

**Always regenerated.** Contain:
- `@fields` - field definitions with types
- `@type t` - typespec for the struct
- `defstruct` - struct definition
- `from_map/1` - basic map-to-struct conversion (overridable)
- Field descriptions in `@moduledoc` for 8 core types (Ticker, Order, Trade, Position, OrderBook, FundingRate, MarketInterface, Transaction)

### Wrapper Modules (`*.ex`)

**Generated with type-specific helpers.** Contain:
- `use CCXT.Types.Schema.X` - imports schema
- `from_map/1` override - adds normalization (string→atom, camelCase fallbacks)
- Helper functions - `open?/1`, `best_bid/1`, `long?/1`, etc.
- Enriched `@moduledoc` for 5 core types (Ticker, Order, Trade, Position, OrderBook) with summaries, helper lists, and examples

### Helper Module (`helpers.ex`)

**Not auto-generated.** Shared normalization functions:
- `normalize_side/1` - "buy" → `:buy`
- `normalize_status/1` - "cancelled" → `:canceled`
- `normalize_order_type/1`, `normalize_margin_mode/1`, etc.
- `get_value/2`, `get_camel_value/3` - key lookup helpers

## Commands

```bash
# Regenerate types (extracts from TypeScript + generates modules)
mix ccxt.gen.types

# Regenerate with wrapper overwrite
mix ccxt.gen.types --force

# Skip TypeScript extraction, use existing JSON
mix ccxt.gen.types --skip-extract
```

## Field Descriptions

Schema moduledocs for 8 core types include human-readable field descriptions.
Descriptions are defined as static maps in `field_descriptions/1` within `types_generator.ex`.

To add or update descriptions:

1. Edit `field_descriptions/1` in `lib/ccxt/extract/types_generator.ex`
2. Add/modify entries in the `%{field_name: "description"}` map for the type
3. Run `mix ccxt.gen.types --force` to regenerate

Types without a `field_descriptions/1` clause use the original format (type only, no description).

## Adding New Type-Specific Helpers

Helper functions are generated from templates in `lib/ccxt/extract/types_generator.ex`.

To add helpers to a type:

1. Find or add the `custom_wrapper_body/1` clause for your type
2. Return the helper code as a string
3. Run `mix ccxt.gen.types --force` to regenerate

Example:
```elixir
# In types_generator.ex
defp custom_wrapper_body("Order") do
  """
  @spec open?(t()) :: boolean()
  def open?(%__MODULE__{status: :open}), do: true
  def open?(_), do: false
  """
end
```

## Type Conversion

The wrapper modules normalize string values to atoms:

| Field | Input | Output |
|-------|-------|--------|
| `order.status` | `"open"` | `:open` |
| `order.side` | `"buy"` | `:buy` |
| `order.status` | `"cancelled"` | `:canceled` |
| `position.side` | `"buy"` | `:long` |
| `position.margin_mode` | `"isolated"` | `:isolated` |

## Files

| File | Generated | Purpose |
|------|-----------|---------|
| `schema/*.ex` | Yes (always) | Struct definitions |
| `*.ex` (wrappers) | Yes (with --force) | Type + helpers |
| `helpers.ex` | No | Shared normalization |
| `types.ex` | Yes | Convenience aliases |

## Related Files

- `lib/ccxt/extract/types_generator.ex` - Generator implementation
- `lib/ccxt/extract/type_mapper.ex` - TypeScript→Elixir type mapping
- `lib/mix/tasks/ccxt.gen.types.ex` - Mix task
- `priv/extractor/extract-types.cjs` - TypeScript AST extractor
- `priv/extractor/ccxt_types.json` - Extracted type definitions
