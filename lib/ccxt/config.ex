defmodule CCXT.Config do
  @moduledoc """
  Canonical configuration spec for ccxt_ex.

  This module provides a single, machine-readable source of truth for all
  application configuration keys, defaults, and documentation. It is used to:

  - Generate README configuration docs for the ccxt_client package
  - Provide a structured spec that tools and LLMs can consume

  Default values are sourced from `CCXT.Defaults` and `CCXT.CircuitBreaker`
  to ensure consistency (no duplication).
  """

  @app :ccxt_client

  @type config_entry :: %{
          required(:key) => atom(),
          required(:path) => [atom()],
          required(:type) => atom(),
          required(:default) => term(),
          required(:description) => String.t(),
          required(:examples) => [String.t()],
          optional(:default_test) => term(),
          optional(:notes) => [String.t()]
        }

  @app_placeholder "{{app}}"

  @doc """
  Returns the configuration specification for the default app (`:ccxt_client`).

  Each entry includes key, path, type, default value, description, and examples.
  """
  @spec spec() :: [config_entry()]
  def spec do
    spec(@app)
  end

  @doc """
  Returns the configuration specification with app name placeholder replaced.

  The `app_name` is substituted into example config snippets.
  """
  @spec spec(atom()) :: [config_entry()]
  def spec(app_name) do
    Enum.map(base_spec(), &replace_app_placeholder(&1, app_name))
  end

  @doc false
  # Builds the config spec using raw defaults from source modules.
  # This ensures no duplication of default values.
  defp base_spec do
    defaults = CCXT.Defaults.raw_defaults()
    cb_defaults = CCXT.CircuitBreaker.raw_defaults()

    [
      %{
        key: :recv_window_ms,
        path: [:recv_window_ms],
        type: :pos_integer,
        default: defaults.recv_window_ms,
        description: "Request timestamp validity window (rejects stale requests).",
        examples: ["config #{@app_placeholder}, recv_window_ms: 10_000"]
      },
      %{
        key: :request_timeout_ms,
        path: [:request_timeout_ms],
        type: :pos_integer,
        default: defaults.request_timeout_ms,
        description: "HTTP request timeout in milliseconds.",
        examples: ["config #{@app_placeholder}, request_timeout_ms: 60_000"]
      },
      %{
        key: :extraction_timeout_ms,
        path: [:extraction_timeout_ms],
        type: :pos_integer,
        default: defaults.extraction_timeout_ms,
        description: "Per-exchange extraction timeout used by mix tasks.",
        examples: ["config #{@app_placeholder}, extraction_timeout_ms: 60_000"],
        notes: ["Only used by mix tasks, not runtime requests."]
      },
      %{
        key: :rate_limit_cleanup_interval_ms,
        path: [:rate_limit_cleanup_interval_ms],
        type: :pos_integer,
        default: defaults.rate_limit_cleanup_interval_ms,
        description: "Interval for cleaning up old rate limit timestamps.",
        examples: ["config #{@app_placeholder}, rate_limit_cleanup_interval_ms: 120_000"]
      },
      %{
        key: :rate_limit_max_age_ms,
        path: [:rate_limit_max_age_ms],
        type: :pos_integer,
        default: defaults.rate_limit_max_age_ms,
        description: "Maximum age for rate limit request timestamps.",
        examples: ["config #{@app_placeholder}, rate_limit_max_age_ms: 120_000"]
      },
      %{
        key: :retry_policy,
        path: [:retry_policy],
        type: :retry_policy,
        default: defaults.retry_policy,
        default_test: defaults.retry_policy_test,
        description: "Req retry policy for HTTP requests.",
        examples: ["config #{@app_placeholder}, retry_policy: :safe_transient"],
        notes: ["In :test, default is false (no retries)."]
      },
      %{
        key: :debug,
        path: [:debug],
        type: :boolean,
        default: false,
        description: "Log exceptions with full stack traces.",
        examples: ["config #{@app_placeholder}, debug: true"],
        notes: ["May log sensitive data; use only in development."]
      },
      %{
        key: :broker_id,
        path: [:broker_id],
        type: :string,
        default: nil,
        description: "Optional broker identifier appended to requests.",
        examples: ["config #{@app_placeholder}, broker_id: \"MY_APP_BROKER\""]
      },
      %{
        key: :circuit_breaker,
        path: [:circuit_breaker, :enabled],
        type: :boolean,
        default: cb_defaults.enabled,
        description: "Enable or disable the circuit breaker.",
        examples: ["config #{@app_placeholder}, :circuit_breaker, enabled: true"]
      },
      %{
        key: :circuit_breaker,
        path: [:circuit_breaker, :max_failures],
        type: :pos_integer,
        default: cb_defaults.max_failures,
        description: "Failures before circuit opens (0 disables).",
        examples: ["config #{@app_placeholder}, :circuit_breaker, max_failures: 5"]
      },
      %{
        key: :circuit_breaker,
        path: [:circuit_breaker, :window_ms],
        type: :pos_integer,
        default: cb_defaults.window_ms,
        description: "Time window for counting failures.",
        examples: ["config #{@app_placeholder}, :circuit_breaker, window_ms: 10_000"]
      },
      %{
        key: :circuit_breaker,
        path: [:circuit_breaker, :reset_ms],
        type: :pos_integer,
        default: cb_defaults.reset_ms,
        description: "Time before circuit resets (closes).",
        examples: ["config #{@app_placeholder}, :circuit_breaker, reset_ms: 15_000"]
      }
    ]
  end

  @doc """
  Returns the configuration specification as formatted JSON.

  Uses the default app name (`:ccxt_client`).
  """
  @spec spec_json() :: String.t()
  def spec_json do
    Jason.encode!(spec(), pretty: true)
  end

  @doc """
  Returns the configuration specification as formatted JSON for the given app.
  """
  @spec spec_json(atom()) :: String.t()
  def spec_json(app_name) do
    Jason.encode!(spec(app_name), pretty: true)
  end

  @doc """
  Generates a README-compatible markdown section documenting all configuration options.

  Includes example config blocks, tables for top-level and circuit breaker keys,
  and a machine-readable JSON spec.
  """
  @spec readme_section(atom()) :: String.t()
  def readme_section(app_name \\ @app) do
    entries = spec(app_name)

    """
    ## Configuration

    Configure the client via application config (#{inspect(app_name)}).

    ```elixir
    config #{inspect(app_name)},
      recv_window_ms: 10_000,
      request_timeout_ms: 60_000,
      rate_limit_cleanup_interval_ms: 120_000,
      rate_limit_max_age_ms: 120_000,
      retry_policy: :safe_transient,
      debug: false,
      broker_id: "MY_APP_BROKER"

    config #{inspect(app_name)}, :circuit_breaker,
      enabled: true,
      max_failures: 5,
      window_ms: 10_000,
      reset_ms: 15_000
    ```

    ### Top-level keys
    #{table_for_entries(top_level_entries(entries))}

    ### Circuit breaker keys
    #{table_for_entries(circuit_breaker_entries(entries))}

    ### Machine-readable config spec
    ```json
    #{spec_json(app_name)}
    ```
    """
  end

  @doc false
  # Filters spec entries to top-level (non-nested) config keys
  defp top_level_entries(entries) do
    Enum.filter(entries, fn entry -> length(entry.path) == 1 end)
  end

  @doc false
  # Filters spec entries to circuit_breaker nested keys
  defp circuit_breaker_entries(entries) do
    Enum.filter(entries, fn entry -> List.first(entry.path) == :circuit_breaker end)
  end

  @doc false
  # Substitutes the {{app}} placeholder in example strings with the actual app name
  defp replace_app_placeholder(entry, app_name) do
    app_string = inspect(app_name)

    examples =
      entry
      |> Map.get(:examples, [])
      |> Enum.map(&String.replace(&1, @app_placeholder, app_string))

    Map.put(entry, :examples, examples)
  end

  @doc false
  # Generates a markdown table from a list of config entries
  defp table_for_entries(entries) do
    rows = Enum.map(entries, &table_row/1)

    Enum.join(["| Key | Type | Default | Description |", "| --- | --- | --- | --- |"] ++ rows, "\n")
  end

  @doc false
  # Formats a single config entry as a markdown table row
  defp table_row(entry) do
    key = entry.path |> List.last() |> Atom.to_string()
    type = Atom.to_string(entry.type)
    default = format_default(entry)
    description = format_description(entry)

    "| `#{key}` | `#{type}` | `#{default}` | #{description} |"
  end

  @doc false
  # Formats default value, appending test-specific default if present
  defp format_default(%{default: default} = entry) do
    default_text = inspect(default)

    case Map.get(entry, :default_test) do
      nil -> default_text
      default_test -> "#{default_text} (test: #{inspect(default_test)})"
    end
  end

  @doc false
  # Formats description, appending any notes if present
  defp format_description(%{description: description} = entry) do
    notes = Map.get(entry, :notes, [])

    case notes do
      [] -> description
      _ -> "#{description} Notes: #{Enum.join(notes, " ")}"
    end
  end
end
