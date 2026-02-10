defmodule Mix.Tasks.Ccxt.Gen do
  @shortdoc "Generate exchange modules in your application namespace"

  @moduledoc """
  Scaffolds exchange modules that use `CCXT.Generator` in your app's namespace.

  ## Usage

      mix ccxt.gen binance kraken       # Generate specific exchanges
      mix ccxt.gen --list               # Show available specs with tier info
      mix ccxt.gen --tier1              # Generate all Tier 1 exchanges
      mix ccxt.gen --tier1 --tier2      # Combine tiers
      mix ccxt.gen --all                # All available exchanges
      mix ccxt.gen --force              # Overwrite existing files
      mix ccxt.gen --namespace Trading  # Custom module namespace

  ## Generated Files

  Each exchange gets a module file at `lib/{app}/exchanges/{id}.ex`:

      defmodule MyApp.Exchanges.Binance do
        use CCXT.Generator, spec: "binance"
      end

  ## Namespace

  By default, modules are placed under `{AppModule}.Exchanges`.
  Override with `--namespace`:

      mix ccxt.gen binance --namespace MyApp.Trading
      # => lib/my_app/exchanges/binance.ex
      # => defmodule MyApp.Trading.Binance do ...
  """

  use Mix.Task

  alias CCXT.Exchange.Classification
  alias CCXT.Exchange.Discovery

  @switches [
    list: :boolean,
    all: :boolean,
    force: :boolean,
    namespace: :string,
    tier1: :boolean,
    tier2: :boolean,
    tier3: :boolean,
    dex: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, exchange_ids} = OptionParser.parse!(args, strict: @switches)

    cond do
      opts[:list] ->
        list_available_specs()

      opts[:all] ->
        generate_exchanges(Discovery.available_specs(), opts)

      Classification.has_tier_flags?(opts) ->
        {exchanges, label} = Classification.collect_tier_exchanges(opts)
        Mix.shell().info("#{ansi(:cyan, "Generating")} #{label}")
        generate_exchanges(exchanges, opts)

      exchange_ids != [] ->
        generate_exchanges(exchange_ids, opts)

      true ->
        Mix.shell().info(@moduledoc)
    end
  end

  @doc false
  # Lists available specs with tier and classification info
  defp list_available_specs do
    specs = Discovery.available_specs()

    Mix.shell().info("\n#{ansi(:cyan, "Available exchange specs")} (#{length(specs)}):\n")
    Mix.shell().info("  #{String.pad_trailing("ID", 22)} #{String.pad_trailing("Tier", 14)} Classification")
    Mix.shell().info("  #{String.duplicate("-", 22)} #{String.duplicate("-", 14)} #{String.duplicate("-", 14)}")

    for spec_id <- specs do
      tier = Classification.get_priority_tier(spec_id)
      classification = Classification.get_classification(spec_id)

      tier_str = format_tier(tier)
      class_str = format_classification(classification)

      Mix.shell().info("  #{String.pad_trailing(spec_id, 22)} #{String.pad_trailing(tier_str, 14)} #{class_str}")
    end

    Mix.shell().info("")
  end

  @doc false
  defp generate_exchanges(exchange_ids, opts) do
    available = MapSet.new(Discovery.available_specs())
    force = opts[:force] || false
    namespace = resolve_namespace(opts)
    app_name = app_name()
    output_dir = Path.join(["lib", app_name, "exchanges"])

    # Validate all IDs exist
    {valid, invalid} = Enum.split_with(exchange_ids, &MapSet.member?(available, &1))

    for id <- invalid do
      Mix.shell().error("#{ansi(:red, "Unknown")} exchange: #{id}")
    end

    if invalid != [] do
      Mix.shell().info("\nRun #{ansi(:faint, "mix ccxt.gen --list")} to see available specs.")
    end

    if valid == [] do
      Mix.shell().error("No valid exchanges to generate.")
      return_early()
    end

    File.mkdir_p!(output_dir)
    {generated, skipped} = generate_files(valid, output_dir, namespace, force)

    Mix.shell().info("\n#{ansi(:green, "Done")}: #{generated} generated, #{skipped} skipped")
  end

  @doc false
  defp generate_files(exchange_ids, output_dir, namespace, force) do
    Enum.reduce(exchange_ids, {0, 0}, fn id, {gen, skip} ->
      filename = "#{id}.ex"
      path = Path.join(output_dir, filename)

      if File.exists?(path) && !force do
        Mix.shell().info("  #{ansi(:faint, "skip")} #{path} (exists, use --force)")
        {gen, skip + 1}
      else
        content = module_template(id, namespace)
        File.write!(path, content)
        Mix.shell().info("  #{ansi(:green, "create")} #{path}")
        {gen + 1, skip}
      end
    end)
  end

  @doc """
  Generates the module source code for an exchange.

  ## Parameters

  - `spec_id` - Exchange ID string (e.g., "binance")
  - `namespace` - Module namespace (e.g., "MyApp.Exchanges")

  ## Examples

      iex> Mix.Tasks.Ccxt.Gen.module_template("binance", "MyApp.Exchanges")
      ~s(defmodule MyApp.Exchanges.Binance do\\n  use CCXT.Generator, spec: "binance"\\nend\\n)

  """
  @spec module_template(String.t(), String.t()) :: String.t()
  def module_template(spec_id, namespace) do
    module_name = Macro.camelize(spec_id)

    """
    defmodule #{namespace}.#{module_name} do
      use CCXT.Generator, spec: "#{spec_id}"
    end
    """
  end

  @doc false
  defp resolve_namespace(opts) do
    case opts[:namespace] do
      nil ->
        app_module() <> ".Exchanges"

      ns ->
        ns
    end
  end

  @doc false
  defp app_module do
    Mix.Project.config()[:app]
    |> Atom.to_string()
    |> Macro.camelize()
  end

  @doc false
  defp app_name do
    Mix.Project.config()[:app]
    |> Atom.to_string()
    |> String.replace("_", "_")
  end

  @doc false
  defp format_tier(:tier1), do: "Tier 1"
  defp format_tier(:tier2), do: "Tier 2"
  defp format_tier(:tier3), do: "Tier 3"
  defp format_tier(:dex), do: "DEX"
  defp format_tier(:unclassified), do: "-"

  @doc false
  defp format_classification(:certified_pro), do: "Certified Pro"
  defp format_classification(:pro), do: "Pro"
  defp format_classification(:supported), do: "Supported"
  defp format_classification(:unknown), do: "-"

  @doc false
  defp return_early, do: :ok

  @doc false
  # Inline ANSI formatting (avoids dependency on CCXT.Sync.Output in ccxt_client)
  defp ansi(color, text) do
    [color, text] |> IO.ANSI.format() |> IO.iodata_to_binary()
  end
end
