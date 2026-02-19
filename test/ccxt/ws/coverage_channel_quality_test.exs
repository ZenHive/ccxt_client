defmodule CCXT.WS.CoverageChannelQualityTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CCXT.WS.Coverage

  describe "analyze_channel_quality/1 classification" do
    test "classifies non-nil channel_name as :ok" do
      result = Coverage.analyze_channel_quality("deribit")
      assert result

      trades = Enum.find(result.entries, &(&1.method == :watch_trades))
      assert trades.quality == :ok
      assert trades.channel_name == "trades"
    end

    test "classifies url_routed template as :url_routed" do
      result = Coverage.analyze_channel_quality("bybit")
      assert result

      balance = Enum.find(result.entries, &(&1.method == :watch_balance))
      assert balance.quality == :url_routed
      assert balance.channel_name == nil
    end

    test "classifies private family method as :private_channel" do
      result = Coverage.analyze_channel_quality("bybit")
      assert result

      positions = Enum.find(result.entries, &(&1.method == :watch_positions))
      assert positions.quality == :private_channel
      assert positions.channel_name == nil
    end

    test "classifies nil channel_name without justification as :unexpected_nil" do
      result = Coverage.analyze_channel_quality("bybit")
      assert result

      ohlcv = Enum.find(result.entries, &(&1.method == :watch_ohlcv))
      assert ohlcv.quality == :unexpected_nil
      assert ohlcv.channel_name == nil
    end

    test "returns nil for nonexistent exchange" do
      assert Coverage.analyze_channel_quality("nonexistent_exchange_xyz") == nil
    end

    test "counts are accurate" do
      result = Coverage.analyze_channel_quality("deribit")
      total = Enum.sum(Map.values(result.counts))
      assert total == length(result.entries)
    end
  end

  describe "analyze_channel_quality/1 with real exchanges" do
    test "deribit has no channel quality issues" do
      result = Coverage.analyze_channel_quality("deribit")
      assert result

      issue_qualities = [:unexpected_nil, :unresolved_var]

      issues =
        Enum.filter(result.entries, &(&1.quality in issue_qualities))

      assert issues == [],
             "Deribit has unexpected channel quality issues: #{inspect(issues)}"
    end

    test "bybit url_routed methods use topic_dict pattern" do
      result = Coverage.analyze_channel_quality("bybit")
      url_routed = Enum.filter(result.entries, &(&1.quality == :url_routed))

      assert url_routed != [], "Expected bybit to have url_routed channels"

      # url_routed methods should have nil channel_name (they use topic_dict)
      for entry <- url_routed do
        assert entry.channel_name == nil,
               "url_routed method #{entry.method} should have nil channel_name"
      end
    end
  end

  describe "channel_quality_summary/1" do
    test "returns results for multiple exchanges" do
      {results, missing} = Coverage.channel_quality_summary(["bybit", "deribit"])
      assert map_size(results) == 2
      assert Map.has_key?(results, "bybit")
      assert Map.has_key?(results, "deribit")
      assert missing == []
    end

    test "separates missing specs from results" do
      {results, missing} = Coverage.channel_quality_summary(["nonexistent_xyz"])
      assert results == %{}
      assert missing == ["nonexistent_xyz"]
    end

    test "handles mix of existing and missing exchanges" do
      {results, missing} = Coverage.channel_quality_summary(["deribit", "nonexistent_xyz"])
      assert map_size(results) == 1
      assert Map.has_key?(results, "deribit")
      assert missing == ["nonexistent_xyz"]
    end
  end

  describe "no JS variable name leaks in available exchanges" do
    @available_exchanges ["bybit", "deribit"]

    for exchange_id <- @available_exchanges do
      test "#{exchange_id} has no unresolved_var channel names" do
        result = Coverage.analyze_channel_quality(unquote(exchange_id))

        if result do
          unresolved =
            Enum.filter(result.entries, &(&1.quality == :unresolved_var))

          assert unresolved == [],
                 "#{unquote(exchange_id)} has unresolved JS variable names: " <>
                   inspect(Enum.map(unresolved, &{&1.method, &1.channel_name}))
        end
      end
    end
  end
end
