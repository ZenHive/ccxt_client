defmodule CcxtClient.MixProject do
  use Mix.Project

  @version "0.2.1"
  @source_url "https://github.com/ZenHive/ccxt_client"

  def project do
    [
      app: :ccxt_client,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {CCXT.Application, []}
    ]
  end

  defp deps do
    [
      # HTTP client
      {:req, "~> 0.5"},
      {:req_fuse, "~> 0.3"},

      # JSON
      {:jason, "~> 1.4"},

      # Telemetry
      {:telemetry, "~> 1.0"},

      # WebSocket
      {:zen_websocket, "~> 0.3"},

      # SSL certificates
      {:castore, "~> 1.0"},

      # Development/test
      {:plug, "~> 1.0", only: [:dev, :test]},
      {:ex_unit_json, "~> 0.3", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.1", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},

      # Tidewave for Claude Code MCP integration
      {:tidewave, "~> 0.5", only: :dev},
      {:bandit, "~> 1.10", only: :dev}
    ]
  end

  def cli do
    [preferred_envs: ["test.json": :test, "dialyzer.json": :dev]]
  end

  defp description do
    "Elixir client for 100+ cryptocurrency exchanges"
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Issues" => "#{@source_url}/issues"
      },
      files: [
        "lib",
        "priv/specs",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "VERSION",
        "priv/extractor/ccxt_exchange_tiers.json",
        "priv/extractor/ccxt_method_signatures.json",
        "priv/extractor/ccxt_symbol_formats.json",
        "priv/extractor/ccxt_exception_names.json",
        "priv/extractor/ccxt_parse_methods.json",
        "priv/extractor/ccxt_error_codes.json",
        "priv/extractor/ccxt_emulated_methods.json",
        "priv/extractor/ccxt_mapping_analysis.json",
        "priv/extractor/ccxt_ws_handler_mappings.json",
        "priv/priority_tiers.exs"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4001) end)'"
      ]
    ]
  end
end
