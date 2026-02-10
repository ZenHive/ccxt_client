defmodule CCXT.Types.HelpersTest do
  use ExUnit.Case, async: true

  alias CCXT.Types.Helpers

  # =============================================================================
  # get_value/2
  # =============================================================================

  describe "get_value/2" do
    test "finds value by atom key" do
      assert Helpers.get_value(%{price: 100}, :price) == 100
    end

    test "falls back to string key" do
      assert Helpers.get_value(%{"price" => 100}, :price) == 100
    end

    test "returns nil when key missing" do
      assert Helpers.get_value(%{}, :price) == nil
    end

    test "prefers atom key over string key" do
      map = Map.put(%{"price" => :string_val}, :price, :atom_val)
      assert Helpers.get_value(map, :price) == :atom_val
    end
  end

  # =============================================================================
  # get_camel_value/3
  # =============================================================================

  describe "get_camel_value/3" do
    test "finds value by snake_case key" do
      assert Helpers.get_camel_value(%{entry_price: 50_000}, :entry_price, :entryPrice) == 50_000
    end

    test "falls back to camelCase key" do
      assert Helpers.get_camel_value(%{entryPrice: 50_000}, :entry_price, :entryPrice) == 50_000
    end

    test "returns nil when both missing" do
      assert Helpers.get_camel_value(%{}, :entry_price, :entryPrice) == nil
    end
  end

  # =============================================================================
  # to_atom_safe/1
  # =============================================================================

  describe "to_atom_safe/1" do
    test "returns nil for nil" do
      assert Helpers.to_atom_safe(nil) == nil
    end

    test "passes through atoms" do
      assert Helpers.to_atom_safe(:open) == :open
    end

    test "converts valid string to existing atom" do
      # :open is already an existing atom
      assert Helpers.to_atom_safe("open") == :open
    end

    test "returns nil for non-existing atom string" do
      assert Helpers.to_atom_safe("this_atom_definitely_does_not_exist_xyz_987") == nil
    end
  end

  # =============================================================================
  # normalize_side/1
  # =============================================================================

  describe "normalize_side/1" do
    test "returns nil for nil" do
      assert Helpers.normalize_side(nil) == nil
    end

    test "normalizes atom values" do
      assert Helpers.normalize_side(:buy) == :buy
      assert Helpers.normalize_side(:sell) == :sell
      assert Helpers.normalize_side(:long) == :long
      assert Helpers.normalize_side(:short) == :short
    end

    test "normalizes string values" do
      assert Helpers.normalize_side("buy") == :buy
      assert Helpers.normalize_side("sell") == :sell
      assert Helpers.normalize_side("long") == :long
      assert Helpers.normalize_side("short") == :short
    end

    test "returns nil for unknown values" do
      assert Helpers.normalize_side(:unknown) == nil
      assert Helpers.normalize_side("other") == nil
      assert Helpers.normalize_side(42) == nil
    end
  end

  # =============================================================================
  # normalize_position_side/1
  # =============================================================================

  describe "normalize_position_side/1" do
    test "returns nil for nil" do
      assert Helpers.normalize_position_side(nil) == nil
    end

    test "normalizes long/short atoms" do
      assert Helpers.normalize_position_side(:long) == :long
      assert Helpers.normalize_position_side(:short) == :short
    end

    test "converts buy/sell atoms to long/short" do
      assert Helpers.normalize_position_side(:buy) == :long
      assert Helpers.normalize_position_side(:sell) == :short
    end

    test "normalizes string values" do
      assert Helpers.normalize_position_side("long") == :long
      assert Helpers.normalize_position_side("short") == :short
      assert Helpers.normalize_position_side("buy") == :long
      assert Helpers.normalize_position_side("sell") == :short
    end

    test "returns nil for unknown values" do
      assert Helpers.normalize_position_side(:unknown) == nil
      assert Helpers.normalize_position_side("other") == nil
    end
  end

  # =============================================================================
  # normalize_status/1
  # =============================================================================

  describe "normalize_status/1" do
    test "returns nil for nil" do
      assert Helpers.normalize_status(nil) == nil
    end

    test "normalizes atom values" do
      assert Helpers.normalize_status(:open) == :open
      assert Helpers.normalize_status(:closed) == :closed
      assert Helpers.normalize_status(:canceled) == :canceled
    end

    test "normalizes cancelled to canceled" do
      assert Helpers.normalize_status(:cancelled) == :canceled
      assert Helpers.normalize_status("cancelled") == :canceled
    end

    test "normalizes string values" do
      assert Helpers.normalize_status("open") == :open
      assert Helpers.normalize_status("closed") == :closed
      assert Helpers.normalize_status("canceled") == :canceled
    end

    test "returns nil for unknown values" do
      assert Helpers.normalize_status(:pending) == nil
      assert Helpers.normalize_status("expired") == nil
    end
  end

  # =============================================================================
  # normalize_order_type/1
  # =============================================================================

  describe "normalize_order_type/1" do
    test "returns nil for nil" do
      assert Helpers.normalize_order_type(nil) == nil
    end

    test "normalizes common atom values" do
      assert Helpers.normalize_order_type(:limit) == :limit
      assert Helpers.normalize_order_type(:market) == :market
    end

    test "normalizes common string values" do
      assert Helpers.normalize_order_type("limit") == :limit
      assert Helpers.normalize_order_type("market") == :market
    end

    test "converts unknown string to existing atom via to_atom_safe" do
      # :stop_limit is an existing atom (defined here to ensure it exists)
      _ = :stop_limit
      assert Helpers.normalize_order_type("stop_limit") == :stop_limit
    end

    test "returns nil for unknown string without existing atom" do
      assert Helpers.normalize_order_type("xyznonexistenttype999") == nil
    end

    test "passes through unknown atoms" do
      assert Helpers.normalize_order_type(:stop_loss) == :stop_loss
    end
  end

  # =============================================================================
  # normalize_taker_or_maker/1
  # =============================================================================

  describe "normalize_taker_or_maker/1" do
    test "returns nil for nil" do
      assert Helpers.normalize_taker_or_maker(nil) == nil
    end

    test "normalizes atom values" do
      assert Helpers.normalize_taker_or_maker(:taker) == :taker
      assert Helpers.normalize_taker_or_maker(:maker) == :maker
    end

    test "normalizes string values" do
      assert Helpers.normalize_taker_or_maker("taker") == :taker
      assert Helpers.normalize_taker_or_maker("maker") == :maker
    end

    test "returns nil for unknown values" do
      assert Helpers.normalize_taker_or_maker(:unknown) == nil
      assert Helpers.normalize_taker_or_maker("other") == nil
    end
  end

  # =============================================================================
  # normalize_margin_mode/1
  # =============================================================================

  describe "normalize_margin_mode/1" do
    test "returns nil for nil" do
      assert Helpers.normalize_margin_mode(nil) == nil
    end

    test "normalizes atom values" do
      assert Helpers.normalize_margin_mode(:isolated) == :isolated
      assert Helpers.normalize_margin_mode(:cross) == :cross
    end

    test "normalizes string values" do
      assert Helpers.normalize_margin_mode("isolated") == :isolated
      assert Helpers.normalize_margin_mode("cross") == :cross
    end

    test "returns nil for unknown values" do
      assert Helpers.normalize_margin_mode(:portfolio) == nil
      assert Helpers.normalize_margin_mode("other") == nil
    end
  end

  # =============================================================================
  # normalize_transfer_status/1
  # =============================================================================

  describe "normalize_transfer_status/1" do
    test "returns nil for nil" do
      assert Helpers.normalize_transfer_status(nil) == nil
    end

    test "normalizes atom values" do
      assert Helpers.normalize_transfer_status(:pending) == :pending
      assert Helpers.normalize_transfer_status(:ok) == :ok
      assert Helpers.normalize_transfer_status(:failed) == :failed
      assert Helpers.normalize_transfer_status(:canceled) == :canceled
    end

    test "normalizes string values" do
      assert Helpers.normalize_transfer_status("pending") == :pending
      assert Helpers.normalize_transfer_status("ok") == :ok
      assert Helpers.normalize_transfer_status("failed") == :failed
      assert Helpers.normalize_transfer_status("canceled") == :canceled
    end

    test "normalizes cancelled to canceled" do
      assert Helpers.normalize_transfer_status(:cancelled) == :canceled
      assert Helpers.normalize_transfer_status("cancelled") == :canceled
    end

    test "returns nil for unknown values" do
      assert Helpers.normalize_transfer_status(:open) == nil
      assert Helpers.normalize_transfer_status("expired") == nil
    end
  end

  # =============================================================================
  # normalize_transaction_type/1
  # =============================================================================

  describe "normalize_transaction_type/1" do
    test "returns nil for nil" do
      assert Helpers.normalize_transaction_type(nil) == nil
    end

    test "normalizes atom values" do
      assert Helpers.normalize_transaction_type(:deposit) == :deposit
      assert Helpers.normalize_transaction_type(:withdrawal) == :withdrawal
    end

    test "normalizes string values" do
      assert Helpers.normalize_transaction_type("deposit") == :deposit
      assert Helpers.normalize_transaction_type("withdrawal") == :withdrawal
    end

    test "returns nil for unknown values" do
      assert Helpers.normalize_transaction_type(:transfer) == nil
      assert Helpers.normalize_transaction_type("other") == nil
    end
  end

  # =============================================================================
  # normalize_direction/1
  # =============================================================================

  describe "normalize_direction/1" do
    test "returns nil for nil" do
      assert Helpers.normalize_direction(nil) == nil
    end

    test "normalizes atom values" do
      assert Helpers.normalize_direction(:in) == :in
      assert Helpers.normalize_direction(:out) == :out
    end

    test "normalizes string values" do
      assert Helpers.normalize_direction("in") == :in
      assert Helpers.normalize_direction("out") == :out
    end

    test "returns nil for unknown values" do
      assert Helpers.normalize_direction(:unknown) == nil
      assert Helpers.normalize_direction("other") == nil
    end
  end
end
