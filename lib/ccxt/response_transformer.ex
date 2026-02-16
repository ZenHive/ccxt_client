defmodule CCXT.ResponseTransformer do
  @moduledoc """
  Response transformers for converting raw exchange responses to unified format.

  Some exchanges return responses in formats that don't match the unified API expectations.
  For example:
  - BitMEX returns `[%{ticker}]` instead of `%{ticker}` for fetch_ticker
  - BitMEX returns flat order list instead of `%{bids: [], asks: []}` for fetch_order_book

  This module provides transformers that can be configured per-endpoint in specs.

  ## Usage

  Add a `response_transformer` field to an endpoint in the spec:

      %{
        name: :fetch_ticker,
        path: "/instrument",
        response_transformer: :unwrap_single_element_list
      }

  Available transformers:
  - `:unwrap_single_element_list` - Unwraps `[item]` to `item`
  - `:order_book_from_flat_list` - Converts flat order list to `%{bids: [], asks: []}`
  """

  require Logger

  @type transformer ::
          :unwrap_single_element_list
          | :order_book_from_flat_list
          | {:extract_path, [String.t()]}
          | {:extract_path_unwrap, [String.t()]}
          | nil

  @doc """
  Applies a transformer to the response body.

  Returns the transformed body, or the original body if no transformer is specified.
  """
  @spec transform(term(), transformer()) :: term()
  def transform(body, nil), do: body
  def transform(body, :unwrap_single_element_list), do: unwrap_single_element_list(body)
  def transform(body, :order_book_from_flat_list), do: order_book_from_flat_list(body)
  def transform(body, {:extract_path, path}) when is_list(path), do: extract_path(body, path)

  def transform(body, {:extract_path_unwrap, path}) when is_list(path) do
    case body |> extract_path(path) |> unwrap_single_element_list() do
      [] -> nil
      other -> other
    end
  end

  def transform(body, unknown) do
    Logger.warning("[ResponseTransformer] Unknown transformer: #{inspect(unknown)}, returning body unchanged")
    body
  end

  @doc """
  Unwraps a single-element list to its element.

  Used when an API returns `[item]` but the unified API expects `item`.

  ## Examples

      iex> CCXT.ResponseTransformer.unwrap_single_element_list([%{"symbol" => "BTC"}])
      %{"symbol" => "BTC"}

      iex> CCXT.ResponseTransformer.unwrap_single_element_list([])
      []

      iex> CCXT.ResponseTransformer.unwrap_single_element_list([%{a: 1}, %{b: 2}])
      [%{a: 1}, %{b: 2}]

  """
  @spec unwrap_single_element_list(term()) :: term()
  def unwrap_single_element_list([single]) when is_map(single), do: single
  def unwrap_single_element_list(other), do: other

  @doc """
  Converts a flat order list to structured order book format.

  BitMEX returns orders as a flat list with "side" field:
  `[%{"side" => "Sell", "price" => 100, "size" => 10}, %{"side" => "Buy", ...}]`

  This transforms it to unified format:
  `%{"bids" => [[price, size], ...], "asks" => [[price, size], ...]}`

  ## Examples

      iex> orders = [
      ...>   %{"side" => "Sell", "price" => 100.5, "size" => 10},
      ...>   %{"side" => "Buy", "price" => 99.5, "size" => 20}
      ...> ]
      iex> CCXT.ResponseTransformer.order_book_from_flat_list(orders)
      %{"bids" => [[99.5, 20]], "asks" => [[100.5, 10]]}

  """
  @spec order_book_from_flat_list(term()) :: term()
  def order_book_from_flat_list(orders) when is_list(orders) do
    {bids, asks} =
      Enum.reduce(orders, {[], []}, fn order, {bids, asks} ->
        price = order["price"]
        size = order["size"]

        case order["side"] do
          "Buy" -> {[[price, size] | bids], asks}
          "Sell" -> {bids, [[price, size] | asks]}
          # Skip unknown sides
          _ -> {bids, asks}
        end
      end)

    # Bids sorted descending (highest first), asks sorted ascending (lowest first)
    %{
      "bids" => Enum.sort_by(bids, fn [price, _] -> price end, :desc),
      "asks" => Enum.sort_by(asks, fn [price, _] -> price end, :asc)
    }
  end

  def order_book_from_flat_list(other), do: other

  @doc """
  Extracts nested data from a response envelope using a key path.

  Walks into nested maps following the given keys. Returns the data at the
  final key, or the current level's data if a key is not found (i.e., stops
  walking and returns whatever map it reached).

  ## Examples

      iex> body = %{"retCode" => 0, "result" => %{"list" => [[1, 2, 3]]}}
      iex> CCXT.ResponseTransformer.extract_path(body, ["result", "list"])
      [[1, 2, 3]]

      iex> CCXT.ResponseTransformer.extract_path(%{"data" => "test"}, [])
      %{"data" => "test"}

      iex> CCXT.ResponseTransformer.extract_path(%{"a" => 1}, ["missing"])
      %{"a" => 1}

      iex> CCXT.ResponseTransformer.extract_path(%{"result" => %{"data" => "test"}}, ["result", "missing"])
      %{"data" => "test"}

  """
  @spec extract_path(term(), [String.t()]) :: term()
  def extract_path(data, []), do: data

  def extract_path(%{} = data, [key | rest]) do
    case Map.get(data, key) do
      nil -> data
      value -> extract_path(value, rest)
    end
  end

  def extract_path(data, _path), do: data
end
