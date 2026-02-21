defmodule CCXT.PipelineTest do
  use ExUnit.Case, async: true

  describe "default/0" do
    test "returns keyword list with all required pipeline keys" do
      pipeline = CCXT.Pipeline.default()

      assert is_list(pipeline)
      assert Keyword.has_key?(pipeline, :coercer)
      assert Keyword.has_key?(pipeline, :parsers)
      assert Keyword.has_key?(pipeline, :normalizer)
      assert Keyword.has_key?(pipeline, :contract)
    end

    test "all pipeline values are modules" do
      for {_key, mod} <- CCXT.Pipeline.default() do
        assert is_atom(mod)
        assert Code.ensure_loaded?(mod), "#{inspect(mod)} is not a loadable module"
      end
    end
  end
end
