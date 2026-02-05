defmodule CCXT.Types.Helpers do
  @moduledoc false
  # Internal helpers for type parsing. Not part of public API.

  @doc """
  Gets a value from a map, trying both atom and string keys.

  Handles CCXT responses that may use either atom or string keys.
  """
  @spec get_value(map(), atom()) :: any()
  def get_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  @doc """
  Gets a value trying snake_case atom, then camelCase atom.

  Useful for fields like `entry_price` vs `entryPrice`.
  """
  @spec get_camel_value(map(), atom(), atom()) :: any()
  def get_camel_value(map, snake_key, camel_key) do
    get_value(map, snake_key) || get_value(map, camel_key)
  end

  @doc """
  Safely converts a string to an existing atom, or returns nil.

  Only converts to atoms that already exist in the runtime.
  """
  @spec to_atom_safe(String.t() | atom() | nil) :: atom() | nil
  def to_atom_safe(nil), do: nil
  def to_atom_safe(value) when is_atom(value), do: value

  def to_atom_safe(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  @doc """
  Normalizes side values to atoms.

  Handles buy/sell and long/short variants.
  """
  @spec normalize_side(String.t() | atom() | nil) :: atom() | nil
  def normalize_side(nil), do: nil
  def normalize_side(:buy), do: :buy
  def normalize_side(:sell), do: :sell
  def normalize_side(:long), do: :long
  def normalize_side(:short), do: :short
  def normalize_side("buy"), do: :buy
  def normalize_side("sell"), do: :sell
  def normalize_side("long"), do: :long
  def normalize_side("short"), do: :short
  def normalize_side(_other), do: nil

  @doc """
  Normalizes position side values to :long/:short atoms.

  Converts buy→long, sell→short for consistency.
  """
  @spec normalize_position_side(String.t() | atom() | nil) :: atom() | nil
  def normalize_position_side(nil), do: nil
  def normalize_position_side(:long), do: :long
  def normalize_position_side(:short), do: :short
  def normalize_position_side(:buy), do: :long
  def normalize_position_side(:sell), do: :short
  def normalize_position_side("long"), do: :long
  def normalize_position_side("short"), do: :short
  def normalize_position_side("buy"), do: :long
  def normalize_position_side("sell"), do: :short
  def normalize_position_side(_other), do: nil

  @doc """
  Normalizes order status, handling cancelled→canceled spelling.
  """
  @spec normalize_status(String.t() | atom() | nil) :: atom() | nil
  def normalize_status(nil), do: nil
  def normalize_status(:open), do: :open
  def normalize_status(:closed), do: :closed
  def normalize_status(:canceled), do: :canceled
  def normalize_status(:cancelled), do: :canceled
  def normalize_status("open"), do: :open
  def normalize_status("closed"), do: :closed
  def normalize_status("canceled"), do: :canceled
  def normalize_status("cancelled"), do: :canceled
  def normalize_status(_other), do: nil

  @doc """
  Normalizes order type to atom.
  """
  @spec normalize_order_type(String.t() | atom() | nil) :: atom() | nil
  def normalize_order_type(nil), do: nil
  def normalize_order_type(:limit), do: :limit
  def normalize_order_type(:market), do: :market
  def normalize_order_type("limit"), do: :limit
  def normalize_order_type("market"), do: :market
  def normalize_order_type(other) when is_binary(other), do: to_atom_safe(other)
  def normalize_order_type(other) when is_atom(other), do: other

  @doc """
  Normalizes taker_or_maker to atom.
  """
  @spec normalize_taker_or_maker(String.t() | atom() | nil) :: atom() | nil
  def normalize_taker_or_maker(nil), do: nil
  def normalize_taker_or_maker(:taker), do: :taker
  def normalize_taker_or_maker(:maker), do: :maker
  def normalize_taker_or_maker("taker"), do: :taker
  def normalize_taker_or_maker("maker"), do: :maker
  def normalize_taker_or_maker(_other), do: nil

  @doc """
  Normalizes margin mode to atom.
  """
  @spec normalize_margin_mode(String.t() | atom() | nil) :: atom() | nil
  def normalize_margin_mode(nil), do: nil
  def normalize_margin_mode(:isolated), do: :isolated
  def normalize_margin_mode(:cross), do: :cross
  def normalize_margin_mode("isolated"), do: :isolated
  def normalize_margin_mode("cross"), do: :cross
  def normalize_margin_mode(_other), do: nil
end
