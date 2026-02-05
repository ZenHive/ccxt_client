defmodule CCXT.WS.UrlRoutingTest do
  use ExUnit.Case, async: true

  alias CCXT.WS.UrlRouting

  describe "get_account_type/2" do
    @bybit_patterns [
      %{pattern: "spot", account_type: "spot"},
      %{pattern: "v5/private", account_type: "unified"},
      %{pattern: nil, account_type: "usdc"}
    ]

    test "matches spot URL" do
      assert UrlRouting.get_account_type(
               "wss://stream.bybit.com/spot/v3/ws",
               @bybit_patterns
             ) == "spot"
    end

    test "matches unified URL" do
      assert UrlRouting.get_account_type(
               "wss://stream.bybit.com/v5/private",
               @bybit_patterns
             ) == "unified"
    end

    test "returns default for non-matching URL" do
      assert UrlRouting.get_account_type(
               "wss://stream.bybit.com/usdc/v3/ws",
               @bybit_patterns
             ) == "usdc"
    end

    test "handles string-keyed patterns from JSON" do
      patterns = [
        %{"pattern" => "spot", "account_type" => "spot"},
        %{"pattern" => nil, "account_type" => "swap"}
      ]

      assert UrlRouting.get_account_type("wss://api.binance.com/spot", patterns) == "spot"
      assert UrlRouting.get_account_type("wss://api.binance.com/futures", patterns) == "swap"
    end

    test "returns nil for empty patterns" do
      assert UrlRouting.get_account_type("wss://any.url", []) == nil
    end
  end

  describe "get_topic/2" do
    test "returns topic for matching account type" do
      topic_dict = %{"spot" => "outboundAccountInfo", "unified" => "wallet"}

      assert UrlRouting.get_topic("spot", topic_dict) == "outboundAccountInfo"
      assert UrlRouting.get_topic("unified", topic_dict) == "wallet"
    end

    test "returns list of topics" do
      topic_dict = %{"spot" => ["order", "stopOrder"], "unified" => ["order"]}

      assert UrlRouting.get_topic("spot", topic_dict) == ["order", "stopOrder"]
    end

    test "returns nil for missing account type" do
      topic_dict = %{"spot" => "ticker"}

      assert UrlRouting.get_topic("usdc", topic_dict) == nil
    end
  end

  describe "resolve_topic/3" do
    @url_patterns [
      %{pattern: "spot", account_type: "spot"},
      %{pattern: "v5/private", account_type: "unified"},
      %{pattern: nil, account_type: "usdc"}
    ]

    @topic_dict %{
      "spot" => "outboundAccountInfo",
      "unified" => "wallet"
    }

    test "resolves topic for spot URL" do
      assert {:ok, "outboundAccountInfo"} =
               UrlRouting.resolve_topic(
                 "wss://stream.bybit.com/spot/v3/ws",
                 @url_patterns,
                 @topic_dict
               )
    end

    test "resolves topic for unified URL" do
      assert {:ok, "wallet"} =
               UrlRouting.resolve_topic(
                 "wss://stream.bybit.com/v5/private",
                 @url_patterns,
                 @topic_dict
               )
    end

    test "returns error when no topic for account type" do
      # usdc is matched but has no topic in dict
      assert {:error, {:no_topic_for_account_type, "usdc"}} =
               UrlRouting.resolve_topic(
                 "wss://stream.bybit.com/usdc/v3/ws",
                 @url_patterns,
                 @topic_dict
               )
    end

    test "returns error for no matching pattern" do
      assert {:error, :no_matching_url_pattern} =
               UrlRouting.resolve_topic(
                 "wss://any.url",
                 [],
                 @topic_dict
               )
    end
  end
end
