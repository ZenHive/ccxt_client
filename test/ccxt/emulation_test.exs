defmodule CCXT.EmulationTest do
  use ExUnit.Case, async: true

  alias CCXT.Emulation
  alias CCXT.Exchange.Classification
  alias CCXT.Extract.EmulatedMethods
  alias CCXT.Spec

  defmodule ExchangeStub do
    @moduledoc false
  end

  describe "dispatch" do
    test "returns invalid_parameters when context is missing exchange module" do
      {exchange_id, method, scope} = sample_emulated_method()
      spec = build_spec(exchange_id)

      assert Emulation.emulated?(spec, method, scope)

      assert {:error, %CCXT.Error{type: :invalid_parameters}} =
               Emulation.dispatch(spec, method, scope, %{})
    end

    test "returns invalid_parameters when exchange_module is nil" do
      {exchange_id, method, scope} = sample_emulated_method()
      spec = build_spec(exchange_id)

      assert {:error, %CCXT.Error{type: :invalid_parameters, message: message}} =
               Emulation.dispatch(spec, method, scope, %{exchange_module: nil})

      assert String.contains?(message, "missing exchange module")
    end

    test "returns passthrough for non-emulated methods" do
      {exchange_id, _method, scope} = sample_emulated_method()
      spec = build_spec(exchange_id)

      refute Emulation.emulated?(spec, :__not_emulated__, scope)
      assert :passthrough == Emulation.dispatch(spec, :__not_emulated__, scope, %{})
    end
  end

  describe "dispatch for unimplemented methods" do
    test "returns not_supported with reason suffix when handler is missing" do
      case find_unimplemented_entry() do
        nil ->
          flunk("""
          No unimplemented emulated methods found.

          Either all emulated methods are implemented or extraction data is empty.
          Run: mix ccxt.sync --check --emulated-methods --force
          """)

        {exchange_id, method, scope, entry} ->
          spec = build_spec(exchange_id)

          assert {:error, %CCXT.Error{type: :not_supported, message: message}} =
                   Emulation.dispatch(spec, method, scope, %{
                     exchange_module: ExchangeStub,
                     params: %{},
                     opts: [],
                     credentials: nil
                   })

          assert String.contains?(message, Atom.to_string(method))

          reasons = Map.get(entry, "reasons", [])

          if reasons == [] do
            refute String.contains?(message, "(")
          else
            assert String.contains?(message, Enum.join(reasons, ", "))
          end
      end
    end
  end

  describe "generated emulated stubs" do
    test "exports emulated methods that have no HTTP endpoint mapping" do
      case find_exchange_with_emulated_stub() do
        nil ->
          flunk("""
          No exchange with emulated stub found.

          Ensure at least one generated exchange has emulated methods and run:
            mix ccxt.sync --tier1 --force
          """)

        {module, method, spec} ->
          functions = module.__info__(:functions)
          assert Enum.any?(functions, fn {name, _arity} -> name == method end)
          refute Enum.any?(spec.endpoints, &(&1[:name] == method))
      end
    end
  end

  @doc false
  # Builds a minimal Spec struct for emulation lookup.
  defp build_spec(exchange_id) do
    %Spec{
      id: exchange_id,
      exchange_id: String.to_atom(exchange_id),
      name: "emulation_test",
      urls: %{}
    }
  end

  @doc false
  # Returns {exchange_id, method_atom, scope_atom} for a sample emulated method.
  defp sample_emulated_method do
    exchange_id = List.first(EmulatedMethods.exchanges())

    if is_nil(exchange_id) do
      flunk("""
      No exchanges with emulated methods found.

      Run: mix ccxt.sync --check --emulated-methods --force
      """)
    end

    entry =
      exchange_id
      |> EmulatedMethods.methods_for()
      |> List.first()

    if is_nil(entry) do
      flunk("No emulated method entries for #{exchange_id}")
    end

    method =
      entry
      |> Map.get("name")
      |> Macro.underscore()
      |> String.to_atom()

    scope =
      case Map.get(entry, "scope") do
        "rest" -> :rest
        "ws" -> :ws
        other -> flunk("Unknown emulation scope: #{inspect(other)}")
      end

    {exchange_id, method, scope}
  end

  @doc false
  # Finds an exchange module with at least one emulated method missing from endpoints.
  defp find_exchange_with_emulated_stub do
    Enum.find_value(Classification.all_exchanges(), &check_exchange_for_emulated_stub/1)
  end

  @doc false
  # Checks if an exchange has an emulated stub method.
  defp check_exchange_for_emulated_stub(exchange_id) do
    module = module_for_exchange(exchange_id)

    with true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :__ccxt_spec__, 0),
         spec = module.__ccxt_spec__(),
         emulated_method when is_atom(emulated_method) <- find_emulated_stub(exchange_id, spec),
         true <- function_exported?(module, emulated_method, 2) do
      {module, emulated_method, spec}
    else
      _ -> nil
    end
  end

  @doc false
  # Finds an emulated method that exists in emulation data but not in spec endpoints.
  defp find_emulated_stub(exchange_id, spec) do
    endpoint_names = MapSet.new(spec.endpoints, & &1[:name])

    exchange_id
    |> EmulatedMethods.methods_for()
    |> Enum.filter(&(Map.get(&1, "scope") == "rest"))
    |> Enum.map(&emulated_entry_to_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.find(fn method -> not MapSet.member?(endpoint_names, method) end)
  end

  @doc false
  # Converts an emulated method entry to a snake_case atom.
  defp emulated_entry_to_name(%{"name" => name}) when is_binary(name) do
    name
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp emulated_entry_to_name(_), do: nil

  @doc false
  # Resolves exchange module name from exchange_id.
  defp module_for_exchange(exchange_id) do
    exchange_id
    |> Macro.camelize()
    |> String.to_atom()
    |> then(&Module.concat(CCXT, &1))
  end

  @doc false
  # Finds an emulated method entry that has no implementation handler.
  defp find_unimplemented_entry do
    implemented = Emulation.implemented_methods()

    Enum.find_value(EmulatedMethods.exchanges(), fn exchange_id ->
      find_unimplemented_in_exchange(exchange_id, implemented)
    end)
  end

  @doc false
  # Searches a single exchange's emulated methods for one missing from implemented set.
  defp find_unimplemented_in_exchange(exchange_id, implemented) do
    exchange_id
    |> EmulatedMethods.methods_for()
    |> Enum.find_value(fn entry ->
      method = entry_method(entry)
      scope = entry_scope(entry)

      if scope in [:rest, :ws] and is_atom(method) and not MapSet.member?(implemented, method) do
        {exchange_id, method, scope, entry}
      end
    end)
  end

  @doc false
  # Converts an entry's name field to a snake_case atom.
  defp entry_method(%{"name" => name}) when is_binary(name) do
    name
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp entry_method(_entry), do: nil

  @doc false
  # Converts an entry's scope field to an atom.
  defp entry_scope(%{"scope" => "rest"}), do: :rest
  defp entry_scope(%{"scope" => "ws"}), do: :ws
  defp entry_scope(_entry), do: :unknown
end
