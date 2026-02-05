defmodule CCXT.Helpers.FundingTest do
  use ExUnit.Case, async: true

  alias CCXT.Helpers.Funding

  describe "next_funding/0" do
    test "returns positive hours" do
      result = Funding.next_funding()

      # Should always be between 0 and 8 hours
      assert result >= 0
      assert result <= 8
    end
  end

  describe "next_funding_at/0" do
    test "returns a DateTime in the future" do
      result = Funding.next_funding_at()

      assert DateTime.compare(result, DateTime.utc_now()) in [:gt, :eq]
    end

    test "returns a DateTime at a funding hour" do
      result = Funding.next_funding_at()

      assert result.hour in [0, 8, 16]
      assert result.minute == 0
      assert result.second == 0
    end
  end

  describe "next_funding_from/1" do
    test "returns hours until next funding from given time" do
      # 07:30 UTC - 30 minutes until 08:00 funding
      from = ~U[2025-01-15 07:30:00Z]

      result = Funding.next_funding_from(from)

      assert_in_delta result, 0.5, 0.001
    end

    test "returns 8 hours when exactly at funding time" do
      # Exactly at 08:00 - next funding is at 16:00
      from = ~U[2025-01-15 08:00:00Z]

      result = Funding.next_funding_from(from)

      assert_in_delta result, 8.0, 0.001
    end

    test "handles crossing midnight" do
      # 23:00 UTC - 1 hour until 00:00 funding
      from = ~U[2025-01-15 23:00:00Z]

      result = Funding.next_funding_from(from)

      assert_in_delta result, 1.0, 0.001
    end

    test "handles time just after funding" do
      # 08:01 UTC - ~8 hours until 16:00 funding
      from = ~U[2025-01-15 08:01:00Z]

      result = Funding.next_funding_from(from)

      # Should be just under 8 hours
      assert result > 7.9
      assert result < 8.0
    end
  end

  describe "next_funding_at_from/1" do
    test "returns 08:00 when before that funding" do
      from = ~U[2025-01-15 07:30:00Z]

      result = Funding.next_funding_at_from(from)

      assert result.hour == 8
      assert result.minute == 0
      assert result.second == 0
      assert result.day == 15
    end

    test "returns 16:00 when between 08:00 and 16:00" do
      from = ~U[2025-01-15 12:00:00Z]

      result = Funding.next_funding_at_from(from)

      assert result.hour == 16
      assert result.minute == 0
      assert result.day == 15
    end

    test "returns next day 00:00 when after 16:00" do
      from = ~U[2025-01-15 20:00:00Z]

      result = Funding.next_funding_at_from(from)

      assert result.hour == 0
      assert result.minute == 0
      assert result.day == 16
    end

    test "returns 16:00 when exactly at 08:00" do
      from = ~U[2025-01-15 08:00:00Z]

      result = Funding.next_funding_at_from(from)

      assert result.hour == 16
      assert result.day == 15
    end

    test "handles month boundaries" do
      # Last day of January at 20:00
      from = ~U[2025-01-31 20:00:00Z]

      result = Funding.next_funding_at_from(from)

      assert result.hour == 0
      assert result.day == 1
      assert result.month == 2
    end
  end
end
