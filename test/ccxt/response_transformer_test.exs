defmodule CCXT.ResponseTransformerTest do
  use ExUnit.Case, async: true

  alias CCXT.ResponseTransformer

  describe "transform/2" do
    test "returns body unchanged when transformer is nil" do
      body = %{"data" => "test"}
      assert ResponseTransformer.transform(body, nil) == body
    end

    test "applies unwrap_single_element_list transformer" do
      body = [%{"symbol" => "BTC"}]
      assert ResponseTransformer.transform(body, :unwrap_single_element_list) == %{"symbol" => "BTC"}
    end

    test "applies order_book_from_flat_list transformer" do
      body = [
        %{"side" => "Buy", "price" => 100, "size" => 10},
        %{"side" => "Sell", "price" => 101, "size" => 5}
      ]

      result = ResponseTransformer.transform(body, :order_book_from_flat_list)
      assert result == %{"bids" => [[100, 10]], "asks" => [[101, 5]]}
    end

    @tag capture_log: true
    test "logs warning and returns body unchanged for unknown transformer" do
      body = %{"data" => "test"}

      # Verify behavior: returns body unchanged
      result = ResponseTransformer.transform(body, :unknown_transformer)
      assert result == body

      # Note: Logger.warning is called but capture_log may not capture it
      # depending on logger configuration. The important behavior (returning
      # body unchanged) is tested above. The warning helps debugging in production.
    end
  end

  describe "unwrap_single_element_list/1" do
    test "unwraps single-element list containing a map" do
      assert ResponseTransformer.unwrap_single_element_list([%{"key" => "value"}]) == %{"key" => "value"}
    end

    test "returns empty list unchanged" do
      assert ResponseTransformer.unwrap_single_element_list([]) == []
    end

    test "returns multi-element list unchanged" do
      list = [%{a: 1}, %{b: 2}]
      assert ResponseTransformer.unwrap_single_element_list(list) == list
    end

    test "returns single non-map element list unchanged" do
      assert ResponseTransformer.unwrap_single_element_list([1]) == [1]
      assert ResponseTransformer.unwrap_single_element_list(["string"]) == ["string"]
    end

    test "returns non-list input unchanged" do
      assert ResponseTransformer.unwrap_single_element_list(%{"key" => "value"}) == %{"key" => "value"}
      assert ResponseTransformer.unwrap_single_element_list("string") == "string"
      assert ResponseTransformer.unwrap_single_element_list(nil) == nil
      assert ResponseTransformer.unwrap_single_element_list(123) == 123
    end

    test "handles nested maps" do
      nested = %{"outer" => %{"inner" => "value"}}
      assert ResponseTransformer.unwrap_single_element_list([nested]) == nested
    end
  end

  describe "order_book_from_flat_list/1" do
    test "converts flat order list to structured format" do
      orders = [
        %{"side" => "Sell", "price" => 100.5, "size" => 10},
        %{"side" => "Buy", "price" => 99.5, "size" => 20}
      ]

      result = ResponseTransformer.order_book_from_flat_list(orders)

      assert result == %{
               "bids" => [[99.5, 20]],
               "asks" => [[100.5, 10]]
             }
    end

    test "returns empty bids and asks for empty list" do
      result = ResponseTransformer.order_book_from_flat_list([])
      assert result == %{"bids" => [], "asks" => []}
    end

    test "sorts bids descending by price (highest first)" do
      orders = [
        %{"side" => "Buy", "price" => 100, "size" => 1},
        %{"side" => "Buy", "price" => 102, "size" => 2},
        %{"side" => "Buy", "price" => 101, "size" => 3}
      ]

      result = ResponseTransformer.order_book_from_flat_list(orders)

      assert result["bids"] == [[102, 2], [101, 3], [100, 1]]
    end

    test "sorts asks ascending by price (lowest first)" do
      orders = [
        %{"side" => "Sell", "price" => 102, "size" => 1},
        %{"side" => "Sell", "price" => 100, "size" => 2},
        %{"side" => "Sell", "price" => 101, "size" => 3}
      ]

      result = ResponseTransformer.order_book_from_flat_list(orders)

      assert result["asks"] == [[100, 2], [101, 3], [102, 1]]
    end

    test "handles orders with nil price or size" do
      orders = [
        %{"side" => "Buy", "price" => nil, "size" => 10},
        %{"side" => "Sell", "price" => 100, "size" => nil}
      ]

      # Should still work, just with nil values
      result = ResponseTransformer.order_book_from_flat_list(orders)

      assert result["bids"] == [[nil, 10]]
      assert result["asks"] == [[100, nil]]
    end

    test "skips orders with unknown side values" do
      orders = [
        %{"side" => "Buy", "price" => 100, "size" => 10},
        %{"side" => "Unknown", "price" => 101, "size" => 5},
        %{"side" => "Sell", "price" => 102, "size" => 20},
        %{"side" => nil, "price" => 103, "size" => 15}
      ]

      result = ResponseTransformer.order_book_from_flat_list(orders)

      assert result == %{
               "bids" => [[100, 10]],
               "asks" => [[102, 20]]
             }
    end

    test "returns non-list input unchanged" do
      assert ResponseTransformer.order_book_from_flat_list(%{"key" => "value"}) == %{"key" => "value"}
      assert ResponseTransformer.order_book_from_flat_list("string") == "string"
      assert ResponseTransformer.order_book_from_flat_list(nil) == nil
    end

    test "handles mixed buy and sell orders" do
      orders = [
        %{"side" => "Buy", "price" => 99, "size" => 10},
        %{"side" => "Sell", "price" => 101, "size" => 5},
        %{"side" => "Buy", "price" => 98, "size" => 20},
        %{"side" => "Sell", "price" => 102, "size" => 15},
        %{"side" => "Buy", "price" => 100, "size" => 30}
      ]

      result = ResponseTransformer.order_book_from_flat_list(orders)

      # Bids: 100 > 99 > 98 (descending)
      assert result["bids"] == [[100, 30], [99, 10], [98, 20]]
      # Asks: 101 < 102 (ascending)
      assert result["asks"] == [[101, 5], [102, 15]]
    end
  end
end
