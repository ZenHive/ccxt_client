defmodule CCXT.WS.GeneratorTest.Bybit do
  @moduledoc false

  def __ccxt_spec__, do: %{}
end

defmodule CCXT.WS.GeneratorTest.Bybit.WS do
  @moduledoc false
  use CCXT.WS.Generator, spec: "bybit"
end

defmodule CCXT.WS.GeneratorTest.NoWS.WS do
  @moduledoc false
  use CCXT.WS.Generator, spec: "test_exchange"
end

defmodule CCXT.WS.GeneratorTest do
  use ExUnit.Case, async: true

  alias CCXT.WS.Generator

  @bybit_module CCXT.WS.GeneratorTest.Bybit.WS
  @no_ws_module CCXT.WS.GeneratorTest.NoWS.WS
  @expected_rest_module CCXT.WS.GeneratorTest.Bybit

  describe "derive_rest_module/1" do
    test "removes trailing WS segment" do
      assert Generator.derive_rest_module(@bybit_module) == @expected_rest_module
    end
  end

  describe "__ccxt_ws_spec__/0" do
    test "returns ws spec for ws-enabled exchange" do
      spec = @bybit_module.__ccxt_ws_spec__()

      assert is_map(spec)
      assert Map.has_key?(spec, :urls)
      assert is_atom(@bybit_module.__ccxt_ws_pattern__())
      assert is_map(@bybit_module.__ccxt_ws_channels__())
    end

    test "returns nil for no ws support" do
      assert @no_ws_module.__ccxt_ws_spec__() == nil
      assert @no_ws_module.__ccxt_ws_pattern__() == nil
      assert @no_ws_module.__ccxt_ws_channels__() == nil
    end
  end

  describe "generated watch functions" do
    test "generates at least one watch_*_subscription function" do
      functions = @bybit_module.__info__(:functions)

      subscription_functions =
        Enum.filter(functions, fn {name, _arity} ->
          String.ends_with?(Atom.to_string(name), "_subscription")
        end)

      refute Enum.empty?(subscription_functions)
    end

    test "watch_ticker_subscription returns valid subscription" do
      assert {:ok, sub} = @bybit_module.watch_ticker_subscription("BTC/USDT")
      assert is_binary(sub.channel)
      assert sub.method == :watch_ticker
      assert sub.auth_required == false
    end
  end
end
