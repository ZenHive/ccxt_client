defmodule CCXTTest do
  use ExUnit.Case, async: true

  doctest CCXT

  describe "module" do
    test "exists and has moduledoc" do
      assert {:docs_v1, _, :elixir, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(CCXT)
      assert moduledoc =~ "Pure Elixir library for cryptocurrency exchange trading"
    end
  end
end
