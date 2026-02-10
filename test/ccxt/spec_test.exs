defmodule CCXT.SpecTest do
  use ExUnit.Case, async: true

  alias CCXT.Spec

  require Logger

  @valid_spec %{
    id: "test_exchange",
    name: "Test Exchange",
    urls: %{
      api: "https://api.test.com",
      sandbox: "https://sandbox.test.com"
    },
    has: %{
      fetch_ticker: true,
      fetch_balance: true,
      create_order: false
    }
  }

  describe "from_map/1" do
    test "creates spec from valid map" do
      spec = Spec.from_map(@valid_spec)

      assert spec.id == "test_exchange"
      assert spec.name == "Test Exchange"
      assert spec.urls.api == "https://api.test.com"
      assert spec.classification == :supported
    end

    test "uses default values for optional fields" do
      minimal = %{
        id: "minimal",
        name: "Minimal",
        urls: %{api: "https://api.minimal.com"}
      }

      spec = Spec.from_map(minimal)

      assert spec.countries == []
      assert spec.classification == :supported
      assert spec.has == %{}
      assert spec.endpoints == []
    end

    test "raises for missing required fields" do
      assert_raise ArgumentError, ~r/Missing required field: id/, fn ->
        Spec.from_map(%{name: "No ID", urls: %{api: "https://example.com"}})
      end
    end
  end

  describe "api_url/2" do
    test "returns production URL by default" do
      spec = Spec.from_map(@valid_spec)
      assert Spec.api_url(spec) == "https://api.test.com"
    end

    test "returns sandbox URL when requested" do
      spec = Spec.from_map(@valid_spec)
      assert Spec.api_url(spec, true) == "https://sandbox.test.com"
    end

    test "falls back to production URL if no sandbox" do
      spec =
        Spec.from_map(%{
          id: "no_sandbox",
          name: "No Sandbox",
          urls: %{api: "https://api.test.com"}
        })

      assert Spec.api_url(spec, true) == "https://api.test.com"
    end

    test "returns sandbox URL from map with 'rest' key" do
      spec =
        Spec.from_map(%{
          id: "rest_sandbox",
          name: "Rest Sandbox",
          urls: %{
            api: "https://api.test.com",
            sandbox: %{"rest" => "https://test.sandbox.com"}
          }
        })

      assert Spec.api_url(spec, true) == "https://test.sandbox.com"
    end

    # Sandbox map fallback chain: default → rest → private → public → api
    test "sandbox map prefers 'default' key" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{
            api: "https://api.test.com",
            sandbox: %{
              "default" => "https://default.sandbox.com",
              "rest" => "https://rest.sandbox.com"
            }
          }
        })

      assert Spec.api_url(spec, true) == "https://default.sandbox.com"
    end

    test "sandbox map falls back to 'private' when no default/rest" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{
            api: "https://api.test.com",
            sandbox: %{"private" => "https://private.sandbox.com"}
          }
        })

      assert Spec.api_url(spec, true) == "https://private.sandbox.com"
    end

    test "sandbox map falls back to 'public' when no default/rest/private" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{
            api: "https://api.test.com",
            sandbox: %{"public" => "https://public.sandbox.com"}
          }
        })

      assert Spec.api_url(spec, true) == "https://public.sandbox.com"
    end

    test "empty sandbox map falls back to production api" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{
            api: "https://api.test.com",
            sandbox: %{}
          }
        })

      assert Spec.api_url(spec, true) == "https://api.test.com"
    end

    # String api_section with map sandbox
    test "string api_section looks up in sandbox map" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{
            api: "https://api.test.com",
            sandbox: %{
              "fapiPrivate" => "https://fapi.sandbox.com",
              "default" => "https://default.sandbox.com"
            }
          }
        })

      assert Spec.api_url(spec, "fapiPrivate") == "https://fapi.sandbox.com"
    end

    test "string api_section falls back to 'default' in sandbox map" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{
            api: "https://api.test.com",
            sandbox: %{"default" => "https://default.sandbox.com"}
          }
        })

      assert Spec.api_url(spec, "fapiPrivate") == "https://default.sandbox.com"
    end

    test "string api_section returns nil when no match in sandbox map" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{
            api: "https://api.test.com",
            sandbox: %{"other" => "https://other.sandbox.com"}
          }
        })

      assert Spec.api_url(spec, "fapiPrivate") == nil
    end

    test "string api_section with string sandbox returns the sandbox URL" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{
            api: "https://api.test.com",
            sandbox: "https://sandbox.test.com"
          }
        })

      assert Spec.api_url(spec, "fapiPrivate") == "https://sandbox.test.com"
    end

    test "string api_section with no sandbox returns nil" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"}
        })

      assert Spec.api_url(spec, "fapiPrivate") == nil
    end
  end

  describe "has?/2" do
    test "returns true for supported capabilities" do
      spec = Spec.from_map(@valid_spec)
      assert Spec.has?(spec, :fetch_ticker)
      assert Spec.has?(spec, :fetch_balance)
    end

    test "returns false for unsupported capabilities" do
      spec = Spec.from_map(@valid_spec)
      refute Spec.has?(spec, :create_order)
      refute Spec.has?(spec, :unknown_method)
    end
  end

  describe "capabilities/1" do
    test "returns sorted list of supported capabilities" do
      spec = Spec.from_map(@valid_spec)
      caps = Spec.capabilities(spec)

      assert caps == [:fetch_balance, :fetch_ticker]
    end

    test "returns empty list when no capabilities" do
      spec =
        Spec.from_map(%{
          id: "empty",
          name: "Empty",
          urls: %{api: "https://api.test.com"}
        })

      assert Spec.capabilities(spec) == []
    end
  end

  describe "load!/1 - spec file validation" do
    @moduletag :unit

    # Find all spec files in priv/specs/
    @specs_dir [__DIR__, "..", "..", "priv", "specs"] |> Path.join() |> Path.expand()

    # Get all .exs files if directory exists
    @spec_files (if File.dir?(@specs_dir) do
                   @specs_dir
                   |> File.ls!()
                   |> Enum.filter(&String.ends_with?(&1, ".exs"))
                   |> Enum.sort()
                 else
                   []
                 end)

    test "all spec files in priv/specs/ load successfully" do
      # Skip if no specs exist yet (e.g., fresh clone before extraction)
      if @spec_files == [] do
        Logger.info("[skipped] No spec files found in #{@specs_dir}")
      else
        errors =
          @spec_files
          |> Enum.map(fn filename ->
            path = Path.join(@specs_dir, filename)

            try do
              spec = Spec.load!(path)
              validate_spec_structure(spec, filename)
            rescue
              e -> {:error, filename, Exception.message(e)}
            end
          end)
          |> Enum.filter(&match?({:error, _, _}, &1))

        if errors != [] do
          error_messages =
            Enum.map_join(errors, "\n", fn {:error, file, msg} ->
              "  - #{file}: #{msg}"
            end)

          flunk("#{length(errors)} spec file(s) failed to load:\n#{error_messages}")
        end

        assert @spec_files != [], "Expected spec files to exist"
      end
    end

    test "all spec files have required fields" do
      if @spec_files == [] do
        Logger.info("[skipped] No spec files found")
      else
        Enum.each(@spec_files, fn filename ->
          path = Path.join(@specs_dir, filename)
          spec = Spec.load!(path)

          # Required fields
          assert is_binary(spec.id), "#{filename}: id must be a string"
          assert spec.id != "", "#{filename}: id must not be empty"
          assert is_binary(spec.name), "#{filename}: name must be a string"
          assert is_map(spec.urls), "#{filename}: urls must be a map"
        end)
      end
    end

    test "all spec files have valid signing patterns" do
      if @spec_files == [] do
        Logger.info("[skipped] No spec files found")
      else
        valid_patterns = [
          :hmac_sha256_query,
          :hmac_sha256_headers,
          :hmac_sha256_iso_passphrase,
          :hmac_sha256_passphrase_signed,
          :hmac_sha512_nonce,
          :hmac_sha384_payload,
          :custom
        ]

        Enum.each(@spec_files, fn filename ->
          path = Path.join(@specs_dir, filename)
          spec = Spec.load!(path)

          if spec.signing do
            pattern = spec.signing[:pattern]

            assert pattern in valid_patterns,
                   "#{filename}: invalid signing pattern '#{pattern}', expected one of #{inspect(valid_patterns)}"
          end
        end)
      end
    end

    test "all spec files have valid classification values" do
      if @spec_files == [] do
        Logger.info("[skipped] No spec files found")
      else
        valid_classifications = [:certified_pro, :pro, :supported]

        Enum.each(@spec_files, fn filename ->
          path = Path.join(@specs_dir, filename)
          spec = Spec.load!(path)

          assert spec.classification in valid_classifications,
                 "#{filename}: classification must be one of #{inspect(valid_classifications)}, got #{spec.classification}"
        end)
      end
    end

    # Helper to validate spec structure
    defp validate_spec_structure(%Spec{} = spec, filename) do
      cond do
        spec.id == "" -> {:error, filename, "id is empty"}
        spec.name == "" -> {:error, filename, "name is empty"}
        not is_map(spec.urls) -> {:error, filename, "urls is not a map"}
        true -> :ok
      end
    end

    defp validate_spec_structure(other, filename) do
      {:error, filename, "Expected CCXT.Spec struct, got #{inspect(other)}"}
    end
  end

  # ===========================================================================
  # Spec Format Versioning (Phase 2: Stable Contracts)
  # ===========================================================================

  describe "spec format versioning" do
    test "from_map/1 defaults spec_format_version to 1 when absent" do
      spec = Spec.from_map(@valid_spec)
      assert spec.spec_format_version == 1
    end

    test "from_map/1 preserves explicit spec_format_version" do
      spec = Spec.from_map(Map.put(@valid_spec, :spec_format_version, 1))
      assert spec.spec_format_version == 1
    end

    test "current_spec_format_version/0 returns 1" do
      assert Spec.current_spec_format_version() == 1
    end

    test "load!/1 produces spec_format_version 1 for specs without version field" do
      # Find any existing spec file to test backward compatibility
      specs_dir = [__DIR__, "..", "..", "priv", "specs"] |> Path.join() |> Path.expand()

      if File.dir?(specs_dir) do
        case specs_dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".exs")) do
          [] ->
            Logger.info("[skipped] No spec files found for version backward compat test")

          [first | _] ->
            spec = Spec.load!(Path.join(specs_dir, first))
            assert spec.spec_format_version == 1
        end
      else
        Logger.info("[skipped] No specs directory for version backward compat test")
      end
    end

    test "load!/1 raises for spec with future version" do
      # Create a temp spec file with a future version
      tmp_dir = System.tmp_dir!()
      path = Path.join(tmp_dir, "future_version_spec.exs")

      content = """
      %{
        id: "future",
        name: "Future Exchange",
        urls: %{api: "https://api.future.com"},
        spec_format_version: 999
      }
      """

      File.write!(path, content)

      assert_raise ArgumentError, ~r/newer than supported/, fn ->
        Spec.load!(path)
      end

      File.rm(path)
    end

    test "load!/1 raises for spec with invalid version" do
      tmp_dir = System.tmp_dir!()
      path = Path.join(tmp_dir, "invalid_version_spec.exs")

      content = """
      %{
        id: "invalid",
        name: "Invalid Exchange",
        urls: %{api: "https://api.invalid.com"},
        spec_format_version: 0
      }
      """

      File.write!(path, content)

      assert_raise ArgumentError, ~r/Invalid spec format version/, fn ->
        Spec.load!(path)
      end

      File.rm(path)
    end
  end

  # ===========================================================================
  # Feature Helper Functions (Task 107)
  # ===========================================================================

  describe "features_for_market/2" do
    @spec_with_features %{
      id: "test",
      name: "Test",
      urls: %{api: "https://api.test.com"},
      features: %{
        spot: %{margin_mode: false, fetch_my_trades: %{limit: 1000}},
        swap: %{margin_mode: true, trigger_price: true}
      }
    }

    test "returns features for valid market type" do
      spec = Spec.from_map(@spec_with_features)

      spot_features = Spec.features_for_market(spec, :spot)
      assert spot_features[:margin_mode] == false
      assert spot_features[:fetch_my_trades] == %{limit: 1000}
    end

    test "returns nil for unknown market type" do
      spec = Spec.from_map(@spec_with_features)
      assert Spec.features_for_market(spec, :option) == nil
    end

    test "returns nil when no features" do
      spec = Spec.from_map(@valid_spec)
      assert Spec.features_for_market(spec, :spot) == nil
    end
  end

  describe "supported_market_types/1" do
    test "returns list of market types" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"},
          features: %{spot: %{}, swap: %{}, future: %{}}
        })

      types = Spec.supported_market_types(spec)
      assert types == [:future, :spot, :swap]
    end

    test "returns empty list when no features" do
      spec = Spec.from_map(@valid_spec)
      assert Spec.supported_market_types(spec) == []
    end
  end

  describe "feature_value/3" do
    test "returns specific feature value" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"},
          features: %{spot: %{fetch_my_trades: %{limit: 500}, margin_mode: false}}
        })

      assert Spec.feature_value(spec, :spot, :fetch_my_trades) == %{limit: 500}
      assert Spec.feature_value(spec, :spot, :margin_mode) == false
      assert Spec.feature_value(spec, :spot, :unknown) == nil
    end
  end

  # ===========================================================================
  # Fee Helper Functions (Task 107)
  # ===========================================================================

  describe "trading_fees/1" do
    @spec_with_fees %{
      id: "test",
      name: "Test",
      urls: %{api: "https://api.test.com"},
      fees: %{
        trading: %{maker: 0.001, taker: 0.002, tier_based: true}
      }
    }

    test "returns trading fees" do
      spec = Spec.from_map(@spec_with_fees)
      fees = Spec.trading_fees(spec)

      assert fees.maker == 0.001
      assert fees.taker == 0.002
      assert fees.tier_based == true
    end

    test "returns nil when no fees" do
      spec = Spec.from_map(@valid_spec)
      assert Spec.trading_fees(spec) == nil
    end
  end

  describe "fee_tiers/1" do
    test "returns fee tiers" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"},
          fees: %{
            trading: %{
              maker: 0.001,
              taker: 0.002,
              tiers: %{
                maker: [%{volume: 0, fee: 0.001}, %{volume: 10_000, fee: 0.0008}],
                taker: [%{volume: 0, fee: 0.002}, %{volume: 10_000, fee: 0.0015}]
              }
            }
          }
        })

      tiers = Spec.fee_tiers(spec)
      assert length(tiers.maker) == 2
      assert hd(tiers.maker).fee == 0.001
    end

    test "returns nil when no tiers" do
      spec = Spec.from_map(@spec_with_fees)
      assert Spec.fee_tiers(spec) == nil
    end
  end

  describe "fees_for_market/2" do
    test "returns market-type specific fees" do
      spec =
        Spec.from_map(%{
          id: "test",
          name: "Test",
          urls: %{api: "https://api.test.com"},
          fees: %{
            trading: %{maker: 0.001, taker: 0.002},
            swap: %{maker: 0.0002, taker: 0.0005}
          }
        })

      swap_fees = Spec.fees_for_market(spec, :swap)
      assert swap_fees.maker == 0.0002
      assert swap_fees.taker == 0.0005
    end

    test "returns nil for unknown market type" do
      spec = Spec.from_map(@spec_with_fees)
      assert Spec.fees_for_market(spec, :option) == nil
    end
  end

  describe "maker_fee/2 and taker_fee/2" do
    @spec_with_market_fees %{
      id: "test",
      name: "Test",
      urls: %{api: "https://api.test.com"},
      fees: %{
        trading: %{maker: 0.001, taker: 0.002},
        swap: %{maker: 0.0002, taker: 0.0005},
        linear: %{trading: %{maker: 0.0001, taker: 0.0003}}
      }
    }

    test "returns base trading fees" do
      spec = Spec.from_map(@spec_with_market_fees)

      assert Spec.maker_fee(spec) == 0.001
      assert Spec.taker_fee(spec) == 0.002
    end

    test "returns market-type specific fees" do
      spec = Spec.from_map(@spec_with_market_fees)

      assert Spec.maker_fee(spec, :swap) == 0.0002
      assert Spec.taker_fee(spec, :swap) == 0.0005
    end

    test "returns nested trading fees for market type" do
      spec = Spec.from_map(@spec_with_market_fees)

      assert Spec.maker_fee(spec, :linear) == 0.0001
      assert Spec.taker_fee(spec, :linear) == 0.0003
    end

    test "falls back to base fees when market type has none" do
      spec = Spec.from_map(@spec_with_market_fees)

      # :spot doesn't have specific fees, should fall back to trading
      assert Spec.maker_fee(spec, :spot) == 0.001
      assert Spec.taker_fee(spec, :spot) == 0.002
    end
  end
end
