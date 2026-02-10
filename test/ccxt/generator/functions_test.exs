defmodule CCXT.Generator.FunctionsTest do
  @moduledoc """
  Tests for Generator.Functions moduledoc generation.

  Covers format_authentication, format_signing_details, format_credentials,
  format_timeframes, format_status_line, format_capabilities_line,
  format_endpoints_line — all exercised via generate_moduledoc/1.
  """
  use ExUnit.Case, async: true

  alias CCXT.Generator.Functions
  alias CCXT.Spec

  # ===========================================================================
  # format_authentication
  # ===========================================================================

  describe "format_authentication" do
    test "signing nil shows no authentication" do
      doc = generate_doc(signing: nil)
      assert doc =~ "No authentication configured."
    end

    test "non-map signing shows format unknown" do
      doc = generate_doc(signing: "not_a_map")
      assert doc =~ "format unknown"
    end

    test "map with pattern shows signing pattern" do
      doc = generate_doc(signing: %{pattern: :hmac_sha256_query})
      assert doc =~ "`hmac_sha256_query`"
    end
  end

  # ===========================================================================
  # format_signing_details
  # ===========================================================================

  describe "format_signing_details" do
    test "includes passphrase when has_passphrase is true" do
      doc = generate_doc(signing: %{pattern: :hmac_sha256_iso_passphrase, has_passphrase: true})
      assert doc =~ "**Passphrase:** Required"
    end

    test "includes api_key_header when present" do
      doc = generate_doc(signing: %{pattern: :hmac, api_key_header: "X-API-Key"})
      assert doc =~ "API key header"
      assert doc =~ "`X-API-Key`"
    end

    test "includes signature_header when present" do
      doc = generate_doc(signing: %{pattern: :hmac, signature_header: "X-Sig"})
      assert doc =~ "Signature header"
      assert doc =~ "`X-Sig`"
    end

    test "includes timestamp_header when present" do
      doc = generate_doc(signing: %{pattern: :hmac, timestamp_header: "X-TS"})
      assert doc =~ "Timestamp header"
      assert doc =~ "`X-TS`"
    end
  end

  # ===========================================================================
  # format_credentials
  # ===========================================================================

  describe "format_credentials" do
    test "with required credentials lists them" do
      doc = generate_doc(required_credentials: %{"api_key" => true, "secret" => true})
      assert doc =~ "Required fields"
      assert doc =~ "`api_key`"
      assert doc =~ "`secret`"
    end

    test "with no required credentials shows public API" do
      doc = generate_doc(required_credentials: %{"api_key" => false})
      assert doc =~ "public API only"
    end

    test "with nil credentials shows not specified" do
      doc = generate_doc(required_credentials: nil)
      assert doc =~ "not specified"
    end

    test "with non-map credentials shows not specified" do
      doc = generate_doc(required_credentials: "invalid")
      assert doc =~ "not specified"
    end
  end

  # ===========================================================================
  # format_timeframes
  # ===========================================================================

  describe "format_timeframes" do
    test "nil timeframes shows not available" do
      doc = generate_doc(timeframes: nil)
      assert doc =~ "not available"
    end

    test "empty map shows no OHLCV timeframes" do
      doc = generate_doc(timeframes: %{})
      assert doc =~ "No OHLCV timeframes supported"
    end

    test "timeframes are sorted by duration" do
      doc = generate_doc(timeframes: %{"1d" => "1d", "1m" => "1m", "1h" => "1h"})
      assert doc =~ "Available intervals:"

      # Verify ordering: 1m < 1h < 1d
      pos_1m = doc |> :binary.match("`1m`") |> elem(0)
      pos_1h = doc |> :binary.match("`1h`") |> elem(0)
      pos_1d = doc |> :binary.match("`1d`") |> elem(0)
      assert pos_1m < pos_1h
      assert pos_1h < pos_1d
    end

    test "invalid timeframe format sorts to beginning" do
      doc = generate_doc(timeframes: %{"weird" => "x", "1m" => "1m"})
      assert doc =~ "Available intervals:"

      # "weird" has sort key 0 (same as 0 seconds), so it sorts before or equal to 1m
      pos_weird = doc |> :binary.match("`weird`") |> elem(0)
      pos_1m = doc |> :binary.match("`1m`") |> elem(0)
      assert pos_weird < pos_1m
    end
  end

  # ===========================================================================
  # format_status_line
  # ===========================================================================

  describe "format_status_line" do
    test "certified + pro" do
      doc = generate_doc(certified: true, pro: true)
      assert doc =~ "Certified + Pro"
    end

    test "certified only" do
      doc = generate_doc(certified: true, pro: false)
      assert doc =~ "**Status:** CCXT Certified"
      refute doc =~ "Certified + Pro"
    end

    test "pro only" do
      doc = generate_doc(certified: false, pro: true)
      assert doc =~ "CCXT Pro"
    end

    test "dex" do
      doc = generate_doc(certified: false, pro: false, dex: true)
      assert doc =~ "Decentralized Exchange"
    end

    test "none of the above produces no status line" do
      doc = generate_doc(certified: false, pro: false, dex: false)
      refute doc =~ "Status:"
    end
  end

  # ===========================================================================
  # format_capabilities_line
  # ===========================================================================

  describe "format_capabilities_line" do
    test "includes key capabilities when present" do
      doc =
        generate_doc(has: %{fetch_ticker: true, create_order: true, fetch_balance: true})

      assert doc =~ "Key capabilities:"
      assert doc =~ "`fetch_ticker`"
      assert doc =~ "`create_order`"
    end

    test "no capabilities line when has is empty" do
      doc = generate_doc(has: %{})
      refute doc =~ "Key capabilities:"
    end

    test "no capabilities line when none of the key capabilities are true" do
      doc = generate_doc(has: %{some_other_method: true})
      refute doc =~ "Key capabilities:"
    end

    test "excludes key capabilities set to false" do
      doc =
        generate_doc(has: %{fetch_ticker: false, create_order: true, fetch_balance: false})

      assert doc =~ "Key capabilities:"
      assert doc =~ "`create_order`"
      refute doc =~ "`fetch_ticker`"
      refute doc =~ "`fetch_balance`"
    end
  end

  # ===========================================================================
  # format_endpoints_line
  # ===========================================================================

  describe "format_endpoints_line" do
    test "shows endpoint count when endpoints present" do
      endpoints = [
        %{name: :fetch_ticker, method: :get, path: "/ticker", auth: false, params: [:symbol]},
        %{name: :fetch_balance, method: :get, path: "/balance", auth: true, params: []}
      ]

      doc = generate_doc(endpoints: endpoints)
      assert doc =~ "2 unified API methods"
    end

    test "no endpoints line when endpoints nil" do
      doc = generate_doc(endpoints: nil)
      refute doc =~ "unified API methods"
    end
  end

  # Helper to generate moduledoc from spec overrides
  defp generate_doc(overrides) do
    spec = build_spec(overrides)
    Functions.generate_moduledoc(spec)
  end

  defp build_spec(overrides) do
    %Spec{
      id: Keyword.get(overrides, :id, "test_exchange"),
      name: Keyword.get(overrides, :name, "Test Exchange"),
      classification: Keyword.get(overrides, :classification, :supported),
      urls: Keyword.get(overrides, :urls, %{api: "https://api.test.com"}),
      signing: Keyword.get(overrides, :signing, %{pattern: :none}),
      endpoints: Keyword.get(overrides, :endpoints, []),
      has: Keyword.get(overrides, :has, %{}),
      options: Keyword.get(overrides, :options, %{}),
      timeframes: Keyword.get(overrides, :timeframes, %{}),
      required_credentials: Keyword.get(overrides, :required_credentials, nil),
      certified: Keyword.get(overrides, :certified, false),
      pro: Keyword.get(overrides, :pro, false),
      dex: Keyword.get(overrides, :dex, false)
    }
  end
end
