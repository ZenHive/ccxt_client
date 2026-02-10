defmodule CCXT.Safe do
  @moduledoc """
  Safe accessor functions for exchange response parsing.

  Provides Elixir equivalents of CCXT's `safe*` family of functions
  (`safeString`, `safeNumber`, `safeInteger`, etc.) that follow CCXT's
  semantics:

  - Empty string `""` is treated as missing (returns nil)
  - Multi-key fallback: try keys in order until one has a value
  - Combined access + coercion in a single call
  - String keys tried first (JSON responses), then atom keys

  ## Usage

  These functions are primarily called by generated response parsers (P3),
  but can be used directly:

      iex> CCXT.Safe.number(%{"price" => "42000.50"}, "price")
      42000.50

      iex> CCXT.Safe.string(%{"side" => "buy"}, "side")
      "buy"

      iex> CCXT.Safe.number(%{"price" => nil}, "price", 0.0)
      0.0

      iex> CCXT.Safe.string(%{"type" => "limit"}, ["kind", "type"])
      "limit"

  ## CCXT Name Mapping

  Use `ccxt_to_elixir/1` to translate CCXT function names for code generation:

      iex> CCXT.Safe.ccxt_to_elixir("safeString2")
      {:string, 2}
  """

  # --- Property Access ---

  @doc false
  @spec prop(map(), String.t() | atom()) :: any()
  def prop(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) do
      "" -> nil
      nil -> prop_atom(map, key)
      val -> val
    end
  end

  def prop(map, key) when is_map(map) and is_atom(key) do
    case Map.get(map, key) do
      "" -> nil
      nil -> prop_string(map, key)
      val -> val
    end
  end

  @doc false
  @spec prop(map(), list()) :: any()
  def prop(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn key -> prop(map, key) end)
  end

  def prop(_map, _key), do: nil

  @doc false
  # Fallback: try atom version of a string key
  defp prop_atom(map, string_key) do
    atom_key =
      try do
        String.to_existing_atom(string_key)
      rescue
        ArgumentError -> nil
      end

    case atom_key && Map.get(map, atom_key) do
      "" -> nil
      val -> val
    end
  end

  @doc false
  # Fallback: try string version of an atom key
  defp prop_string(map, atom_key) do
    case Map.get(map, Atom.to_string(atom_key)) do
      "" -> nil
      val -> val
    end
  end

  # --- Coercion Helpers ---

  @doc false
  @spec to_number(any()) :: number() | nil
  def to_number(nil), do: nil
  def to_number(val) when is_number(val), do: val

  # Accepts partial parses (e.g., "42.5abc" → 42.5) to match CCXT's safeNumber behavior
  def to_number(val) when is_binary(val) do
    case Float.parse(val) do
      {num, ""} -> num
      {num, _rest} -> num
      :error -> nil
    end
  end

  def to_number(_), do: nil

  @doc false
  @spec to_integer(any()) :: integer() | nil
  def to_integer(nil), do: nil
  def to_integer(val) when is_integer(val), do: val
  def to_integer(val) when is_float(val), do: trunc(val)

  def to_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> int
      {_int, _rest} -> to_integer_via_float(val)
      :error -> nil
    end
  end

  def to_integer(_), do: nil

  @doc false
  defp to_integer_via_float(val) do
    case Float.parse(val) do
      {num, _} -> trunc(num)
      :error -> nil
    end
  end

  @doc false
  @spec to_string_safe(any()) :: String.t() | nil
  def to_string_safe(nil), do: nil
  def to_string_safe(val) when is_binary(val), do: val
  def to_string_safe(val) when is_number(val), do: Kernel.to_string(val)
  def to_string_safe(val) when is_atom(val), do: Atom.to_string(val)
  def to_string_safe(_), do: nil

  @doc false
  @spec to_bool(any()) :: boolean() | nil
  def to_bool(val) when is_boolean(val), do: val
  def to_bool(_), do: nil

  # --- Composed Public Functions ---

  @doc """
  Safely access a string value from a map.

  Returns nil if the key is missing, nil, or empty string.
  Coerces numbers and atoms to strings.

  ## Examples

      iex> CCXT.Safe.string(%{"side" => "buy"}, "side")
      "buy"

      iex> CCXT.Safe.string(%{"code" => 200}, "code")
      "200"

      iex> CCXT.Safe.string(%{}, "missing", "default")
      "default"

      iex> CCXT.Safe.string(%{"a" => nil, "b" => "found"}, ["a", "b"])
      "found"
  """
  @spec string(map(), String.t() | atom() | list(), any()) :: String.t() | nil
  def string(map, key_or_keys, default \\ nil) do
    map |> prop(key_or_keys) |> to_string_safe() |> with_default(default)
  end

  @doc """
  Safely access a number value from a map.

  Parses string numbers. Returns nil for non-numeric values.

  ## Examples

      iex> CCXT.Safe.number(%{"price" => "42000.50"}, "price")
      42000.50

      iex> CCXT.Safe.number(%{"price" => 42000}, "price")
      42000

      iex> CCXT.Safe.number(%{}, "price", 0.0)
      0.0
  """
  @spec number(map(), String.t() | atom() | list(), any()) :: number() | nil
  def number(map, key_or_keys, default \\ nil) do
    map |> prop(key_or_keys) |> to_number() |> with_default(default)
  end

  @doc """
  Safely access an integer value from a map.

  Parses string integers, truncates floats.

  ## Examples

      iex> CCXT.Safe.integer(%{"count" => "42"}, "count")
      42

      iex> CCXT.Safe.integer(%{"count" => 42.7}, "count")
      42
  """
  @spec integer(map(), String.t() | atom() | list(), any()) :: integer() | nil
  def integer(map, key_or_keys, default \\ nil) do
    map |> prop(key_or_keys) |> to_integer() |> with_default(default)
  end

  @doc """
  Safely access a boolean value from a map.

  Returns the value only if it is a boolean, nil otherwise (strict like CCXT).

  ## Examples

      iex> CCXT.Safe.bool(%{"active" => true}, "active")
      true

      iex> CCXT.Safe.bool(%{"active" => "yes"}, "active")
      nil
  """
  @spec bool(map(), String.t() | atom() | list(), any()) :: boolean() | nil
  def bool(map, key_or_keys, default \\ nil) do
    map |> prop(key_or_keys) |> to_bool() |> with_default(default)
  end

  @doc """
  Safely access a raw value from a map without coercion.

  ## Examples

      iex> CCXT.Safe.value(%{"data" => [1, 2, 3]}, "data")
      [1, 2, 3]

      iex> CCXT.Safe.value(%{"data" => ""}, "data")
      nil
  """
  @spec value(map(), String.t() | atom() | list(), any()) :: any()
  def value(map, key_or_keys, default \\ nil) do
    map |> prop(key_or_keys) |> with_default(default)
  end

  @doc """
  Safely access a timestamp value from a map.

  If the value looks like seconds (< 1e12), multiplies by 1000 and truncates
  to get milliseconds. Otherwise returns as integer.

  ## Examples

      iex> CCXT.Safe.timestamp(%{"ts" => "1700000000"}, "ts")
      1700000000

      iex> CCXT.Safe.timestamp(%{"ts" => 1700000.0}, "ts")
      1700000000
  """
  @seconds_threshold 1.0e12

  @spec timestamp(map(), String.t() | atom() | list(), any()) :: integer() | nil
  def timestamp(map, key_or_keys, default \\ nil) do
    case map |> prop(key_or_keys) |> to_number() do
      nil -> default
      num when num < @seconds_threshold -> trunc(num * 1000)
      num -> trunc(num)
    end
  end

  @doc """
  Safely access a string value and downcase it.

  ## Examples

      iex> CCXT.Safe.string_lower(%{"side" => "BUY"}, "side")
      "buy"
  """
  @spec string_lower(map(), String.t() | atom() | list(), any()) :: String.t() | nil
  def string_lower(map, key_or_keys, default \\ nil) do
    case map |> prop(key_or_keys) |> to_string_safe() do
      nil -> default
      str -> String.downcase(str)
    end
  end

  @doc """
  Safely access a string value and upcase it.

  ## Examples

      iex> CCXT.Safe.string_upper(%{"currency" => "btc"}, "currency")
      "BTC"
  """
  @spec string_upper(map(), String.t() | atom() | list(), any()) :: String.t() | nil
  def string_upper(map, key_or_keys, default \\ nil) do
    case map |> prop(key_or_keys) |> to_string_safe() do
      nil -> default
      str -> String.upcase(str)
    end
  end

  @doc """
  Safely access a list value from a map.

  Returns the value only if it is a list, nil otherwise.

  ## Examples

      iex> CCXT.Safe.list(%{"items" => [1, 2]}, "items")
      [1, 2]

      iex> CCXT.Safe.list(%{"items" => "not a list"}, "items")
      nil
  """
  @spec list(map(), String.t() | atom() | list(), any()) :: list() | nil
  def list(map, key_or_keys, default \\ nil) do
    case prop(map, key_or_keys) do
      val when is_list(val) -> val
      _ -> default
    end
  end

  @doc """
  Safely access a map/dict value from a map.

  Returns the value only if it is a map, nil otherwise.

  ## Examples

      iex> CCXT.Safe.dict(%{"fee" => %{"cost" => 0.1}}, "fee")
      %{"cost" => 0.1}

      iex> CCXT.Safe.dict(%{"fee" => "not a map"}, "fee")
      nil
  """
  @spec dict(map(), String.t() | atom() | list(), any()) :: map() | nil
  def dict(map, key_or_keys, default \\ nil) do
    case prop(map, key_or_keys) do
      val when is_map(val) -> val
      _ -> default
    end
  end

  @doc """
  Safely access a number, multiply by a factor, and truncate to integer.

  Used for satoshi conversions and similar scaling operations.

  ## Examples

      iex> CCXT.Safe.integer_product(%{"satoshis" => "100000000"}, "satoshis", 1.0e-8)
      1

      iex> CCXT.Safe.integer_product(%{"amount" => 5}, "amount", 100)
      500
  """
  @spec integer_product(map(), String.t() | atom() | list(), number(), any()) :: integer() | nil
  def integer_product(map, key_or_keys, factor, default \\ nil) do
    case map |> prop(key_or_keys) |> to_number() do
      nil -> default
      num -> trunc(num * factor)
    end
  end

  # --- CCXT → Elixir Name Map (for P3 code generation) ---

  @doc """
  Maps a CCXT safe* function name to an Elixir function name and key count.

  Returns `{function_name, key_count}` where key_count is 1, 2, or :n.

  ## Examples

      iex> CCXT.Safe.ccxt_to_elixir("safeString")
      {:string, 1}

      iex> CCXT.Safe.ccxt_to_elixir("safeNumber2")
      {:number, 2}

      iex> CCXT.Safe.ccxt_to_elixir("safeStringN")
      {:string, :n}
  """
  @spec ccxt_to_elixir(String.t()) :: {atom(), 1 | 2 | :n} | nil

  # String variants
  def ccxt_to_elixir("safeString"), do: {:string, 1}
  def ccxt_to_elixir("safeString2"), do: {:string, 2}
  def ccxt_to_elixir("safeStringN"), do: {:string, :n}
  def ccxt_to_elixir("safeStringLower"), do: {:string_lower, 1}
  def ccxt_to_elixir("safeStringLower2"), do: {:string_lower, 2}
  def ccxt_to_elixir("safeStringLowerN"), do: {:string_lower, :n}
  def ccxt_to_elixir("safeStringUpper"), do: {:string_upper, 1}
  def ccxt_to_elixir("safeStringUpper2"), do: {:string_upper, 2}
  def ccxt_to_elixir("safeStringUpperN"), do: {:string_upper, :n}

  # Number variants (safeFloat = safeNumber in CCXT)
  def ccxt_to_elixir("safeNumber"), do: {:number, 1}
  def ccxt_to_elixir("safeNumber2"), do: {:number, 2}
  def ccxt_to_elixir("safeNumberN"), do: {:number, :n}
  def ccxt_to_elixir("safeFloat"), do: {:number, 1}
  def ccxt_to_elixir("safeFloat2"), do: {:number, 2}
  def ccxt_to_elixir("safeFloatN"), do: {:number, :n}

  # Integer variants
  def ccxt_to_elixir("safeInteger"), do: {:integer, 1}
  def ccxt_to_elixir("safeInteger2"), do: {:integer, 2}
  def ccxt_to_elixir("safeIntegerN"), do: {:integer, :n}
  def ccxt_to_elixir("safeIntegerProduct"), do: {:integer_product, 1}
  def ccxt_to_elixir("safeIntegerProduct2"), do: {:integer_product, 2}

  # Timestamp variants
  def ccxt_to_elixir("safeTimestamp"), do: {:timestamp, 1}
  def ccxt_to_elixir("safeTimestamp2"), do: {:timestamp, 2}
  def ccxt_to_elixir("safeTimestampN"), do: {:timestamp, :n}

  # Boolean
  def ccxt_to_elixir("safeBool"), do: {:bool, 1}
  def ccxt_to_elixir("safeBool2"), do: {:bool, 2}
  def ccxt_to_elixir("safeBoolN"), do: {:bool, :n}

  # Value (no coercion)
  def ccxt_to_elixir("safeValue"), do: {:value, 1}
  def ccxt_to_elixir("safeValue2"), do: {:value, 2}
  def ccxt_to_elixir("safeValueN"), do: {:value, :n}

  # List/Dict
  def ccxt_to_elixir("safeList"), do: {:list, 1}
  def ccxt_to_elixir("safeList2"), do: {:list, 2}
  def ccxt_to_elixir("safeDict"), do: {:dict, 1}
  def ccxt_to_elixir("safeDict2"), do: {:dict, 2}

  def ccxt_to_elixir(_unknown), do: nil

  # --- Private Helpers ---

  @doc false
  defp with_default(nil, default), do: default
  defp with_default(val, _default), do: val
end
