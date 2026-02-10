defmodule CCXT.Generator.SpecLoaderTest do
  use ExUnit.Case, async: true

  alias CCXT.Generator.SpecLoader

  describe "resolve_spec_path/2" do
    test "with spec_path provided returns expanded path" do
      path = SpecLoader.resolve_spec_path(nil, "some/relative/path.exs")

      assert Path.type(path) == :absolute
      assert String.ends_with?(path, "some/relative/path.exs")
    end

    test "spec_path takes precedence over spec_id" do
      path = SpecLoader.resolve_spec_path("bybit", "/tmp/custom.exs")

      assert path == "/tmp/custom.exs"
    end

    test "with spec_id for nonexistent spec returns curated path as fallback" do
      path = SpecLoader.resolve_spec_path("totally_fake_exchange_xyz", nil)

      assert String.contains?(path, "curated")
      assert String.ends_with?(path, "totally_fake_exchange_xyz.exs")
    end

    test "with both nil raises ArgumentError" do
      assert_raise ArgumentError, ~r/requires either/, fn ->
        SpecLoader.resolve_spec_path(nil, nil)
      end
    end
  end

  describe "resolve_spec_path/2 - existing specs" do
    test "with spec_id for existing extracted spec returns extracted path" do
      path = SpecLoader.resolve_spec_path("bybit", nil)

      assert String.contains?(path, "extracted")
      assert String.ends_with?(path, "bybit.exs")
      assert File.exists?(path)
    end

    test "with spec_id for existing curated spec returns curated path" do
      path = SpecLoader.resolve_spec_path("test_exchange", nil)

      assert String.contains?(path, "curated")
      assert String.ends_with?(path, "test_exchange.exs")
      assert File.exists?(path)
    end
  end

  describe "find_priv_dir/0" do
    test "returns a valid directory path" do
      dir = SpecLoader.find_priv_dir()

      assert is_binary(dir)
      assert File.dir?(dir)
    end

    test "returned path contains specs subdirectory" do
      dir = SpecLoader.find_priv_dir()

      assert File.dir?(Path.join(dir, "specs"))
    end
  end

  describe "load_and_validate_spec!/1" do
    test "raises CompileError for non-existent path" do
      assert_raise CompileError, ~r/Spec file not found/, fn ->
        SpecLoader.load_and_validate_spec!("/tmp/nonexistent_spec_xyz_12345.exs")
      end
    end

    test "loads and returns spec from valid path" do
      path = SpecLoader.resolve_spec_path("test_exchange", nil)
      spec = SpecLoader.load_and_validate_spec!(path)

      assert %CCXT.Spec{} = spec
      assert is_binary(spec.id)
    end
  end
end
