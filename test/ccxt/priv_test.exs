defmodule CCXT.PrivTest do
  use ExUnit.Case, async: true

  alias CCXT.Priv

  describe "dir/0" do
    test "returns a valid directory path" do
      dir = Priv.dir()
      assert is_binary(dir)
      assert File.dir?(dir)
    end

    test "returns path ending with priv" do
      dir = Priv.dir()
      assert String.ends_with?(dir, "priv")
    end

    test "contains expected subdirectories" do
      dir = Priv.dir()
      assert File.dir?(Path.join(dir, "extractor"))
      assert File.dir?(Path.join(dir, "specs"))
    end
  end

  describe "path/1" do
    test "joins subpath to priv directory" do
      path = Priv.path("extractor/ccxt_method_signatures.json")
      assert is_binary(path)
      assert String.contains?(path, "priv")
      assert String.ends_with?(path, "extractor/ccxt_method_signatures.json")
    end

    test "returns existing file path for known files" do
      path = Priv.path("extractor/ccxt_method_signatures.json")
      assert File.exists?(path)
    end

    test "handles nested paths" do
      path = Priv.path("specs/extracted")
      assert String.ends_with?(path, "specs/extracted")
    end
  end
end
