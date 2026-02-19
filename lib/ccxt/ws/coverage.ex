defmodule CCXT.WS.Coverage do
  @moduledoc """
  Pure WS extraction coverage analysis.

  Checks whether WS handler mappings have been extracted for each family
  that CCXT declares as supported. This is extraction-quality checking only —
  it does NOT check normalization or runtime behavior.

  ## Status Model

  | Status | Meaning |
  |--------|---------|
  | `:supported` | `ws.has` declares family AND handler mapping extracted |
  | `:no_handler` | `ws.has` declares family BUT handler missing |
  | `:unsupported` | Exchange doesn't offer this family |

  ## Channel Quality Model

  | Status | Meaning |
  |--------|---------|
  | `:ok` | Non-nil, non-empty channel_name string |
  | `:url_routed` | Template has `url_routed: true` (uses topic_dict, nil is legitimate) |
  | `:private_channel` | Private method (balance, orders, etc.) confirmed by ws.has |
  | `:unresolved_var` | Channel name matches a known JS variable name (extraction bug) |
  | `:unexpected_nil` | Nil channel_name with no structural justification |

  ## Dependencies

  - `CCXT.Extract.WsHandlerMappings` — handler mapping data
  - `CCXT.Spec` — exchange spec files (ws.has capabilities, channel templates)
  """

  alias CCXT.Extract.WsHandlerMappings

  @type status :: :supported | :no_handler | :unsupported

  @type channel_quality ::
          :ok | :url_routed | :private_channel | :unresolved_var | :unexpected_nil

  @typedoc "Per-method channel quality classification"
  @type channel_entry :: %{method: atom(), channel_name: String.t() | nil, quality: channel_quality()}

  @typedoc "Per-exchange channel quality result"
  @type channel_quality_result :: %{
          entries: [channel_entry()],
          counts: %{channel_quality() => non_neg_integer()}
        }

  @typedoc "Per-exchange coverage result"
  @type exchange_result :: %{
          statuses: %{atom() => status()},
          supported_count: non_neg_integer(),
          declared_count: non_neg_integer(),
          coverage_pct: float(),
          missing_families: [atom()],
          missing_spec: boolean()
        }

  @typedoc "Matrix of exchange_id => exchange_result"
  @type matrix :: %{String.t() => exchange_result()}

  @typedoc "Aggregated summary across all exchanges"
  @type summary :: %{
          total_exchanges: non_neg_integer(),
          exchanges_with_gaps: non_neg_integer(),
          exchanges_fully_covered: non_neg_integer(),
          missing_specs: non_neg_integer(),
          total_supported: non_neg_integer(),
          total_no_handler: non_neg_integer(),
          total_declared: non_neg_integer()
        }

  @percent_max 100.0

  @doc "Returns the 7 known WS families."
  @spec families() :: [atom()]
  def families, do: WsHandlerMappings.known_families()

  @doc """
  Pure core logic: computes per-family status from pre-loaded data.

  `families_supported` is a list of family atoms the exchange has handlers for.
  `ws_has` is the `spec.ws.has` map (or nil if no spec).

  Returns a map of `%{family => status}` for all 7 families.
  """
  @spec compute_exchange_status([atom()], map() | nil) :: %{atom() => status()}
  def compute_exchange_status(families_supported, ws_has) do
    supported_set = MapSet.new(families_supported)

    Map.new(families(), fn family ->
      {family, family_status(family, ws_has, supported_set)}
    end)
  end

  @doc """
  Computes a full result for a single exchange by loading real data.

  Loads the spec file and handler mappings, then delegates to pure logic.
  """
  @spec compute_result(String.t()) :: exchange_result()
  def compute_result(exchange_id) do
    case find_spec_path(exchange_id) do
      nil ->
        missing_spec_result()

      spec_path ->
        ws_has = load_ws_has(spec_path)
        families_supported = WsHandlerMappings.families_supported(exchange_id)
        statuses = compute_exchange_status(families_supported, ws_has)
        build_result(statuses, false)
    end
  end

  @doc """
  Computes coverage matrix for multiple exchanges.

  Returns `%{exchange_id => exchange_result}` sorted by exchange ID.
  """
  @spec compute_matrix([String.t()]) :: matrix()
  def compute_matrix(exchange_ids) do
    exchange_ids
    |> Enum.sort()
    |> Map.new(fn id -> {id, compute_result(id)} end)
  end

  @doc """
  Aggregates a matrix into a summary map.
  """
  @spec summarize(matrix()) :: summary()
  def summarize(matrix) do
    results = Map.values(matrix)

    %{
      total_exchanges: length(results),
      exchanges_with_gaps: Enum.count(results, &has_gaps?/1),
      exchanges_fully_covered: Enum.count(results, &fully_covered?/1),
      missing_specs: Enum.count(results, & &1.missing_spec),
      total_supported: results |> Enum.map(& &1.supported_count) |> Enum.sum(),
      total_no_handler: results |> Enum.map(&length(&1.missing_families)) |> Enum.sum(),
      total_declared: results |> Enum.map(& &1.declared_count) |> Enum.sum()
    }
  end

  # -- Channel Quality -------------------------------------------------------

  # JS variable names that indicate unresolved extraction from CCXT source
  @js_variable_names ~w(name channelName klineType topic stream channel)

  # Private WS method name prefixes — methods matching these AND declared in
  # ws.has are legitimately nil (they use auth tokens, not channel names)
  @private_prefixes ~w(watch_balance watch_orders watch_my_ watch_positions watch_position)

  @doc """
  Analyzes channel_name quality for all channel templates in an exchange spec.

  Loads the spec by exchange ID and classifies each template's channel_name.
  """
  @spec analyze_channel_quality(String.t()) :: channel_quality_result() | nil
  def analyze_channel_quality(exchange_id) do
    case find_spec_path(exchange_id) do
      nil ->
        nil

      spec_path ->
        spec = CCXT.Spec.load!(spec_path)
        ws_has = get_in(Map.from_struct(spec), [:ws, :has])
        templates = get_in(Map.from_struct(spec), [:ws, :channel_templates]) || %{}

        entries =
          templates
          |> Enum.map(fn {method, tmpl} ->
            cn = Map.get(tmpl, :channel_name)
            quality = classify_channel(method, tmpl, cn, ws_has)
            %{method: method, channel_name: cn, quality: quality}
          end)
          |> Enum.sort_by(& &1.method)

        counts = Enum.frequencies_by(entries, & &1.quality)
        %{entries: entries, counts: counts}
    end
  end

  @doc """
  Analyzes channel quality across multiple exchanges.

  Returns `{results, missing_specs}` where `results` maps exchange IDs to
  their channel quality data and `missing_specs` lists IDs with no spec file.
  """
  @spec channel_quality_summary([String.t()]) ::
          {%{String.t() => channel_quality_result()}, [String.t()]}
  def channel_quality_summary(exchange_ids) do
    all = exchange_ids |> Enum.sort() |> Map.new(fn id -> {id, analyze_channel_quality(id)} end)
    missing = all |> Enum.filter(fn {_id, result} -> result == nil end) |> Enum.map(&elem(&1, 0))
    results = all |> Enum.reject(fn {_id, result} -> result == nil end) |> Map.new()
    {results, missing}
  end

  # -- Private Helpers -------------------------------------------------------

  @doc false
  @spec family_status(atom(), map() | nil, MapSet.t()) :: status()
  defp family_status(family, ws_has, supported_set) do
    cond do
      not family_declared?(family, ws_has) -> :unsupported
      not MapSet.member?(supported_set, family) -> :no_handler
      true -> :supported
    end
  end

  @doc false
  # Only `true` counts as declared. `false`, `nil`, `"emulated"` do not.
  @spec family_declared?(atom(), map() | nil) :: boolean()
  defp family_declared?(_family, nil), do: false

  defp family_declared?(family, ws_has) do
    Map.get(ws_has, family) == true
  end

  @doc false
  @spec load_ws_has(String.t()) :: map() | nil
  defp load_ws_has(spec_path) do
    spec = CCXT.Spec.load!(spec_path)
    get_in(Map.from_struct(spec), [:ws, :has])
  end

  @doc false
  @spec find_spec_path(String.t()) :: String.t() | nil
  defp find_spec_path(exchange_id) do
    curated = Path.join([File.cwd!(), "priv", "specs", "curated", "#{exchange_id}.exs"])
    extracted = Path.join([File.cwd!(), "priv", "specs", "extracted", "#{exchange_id}.exs"])

    cond do
      File.exists?(curated) -> curated
      File.exists?(extracted) -> extracted
      true -> nil
    end
  end

  @doc false
  @spec build_result(%{atom() => status()}, boolean()) :: exchange_result()
  defp build_result(statuses, missing_spec) do
    declared_count = Enum.count(statuses, fn {_f, s} -> s != :unsupported end)
    supported_count = Enum.count(statuses, fn {_f, s} -> s == :supported end)

    missing_families =
      statuses
      |> Enum.filter(fn {_f, s} -> s == :no_handler end)
      |> Enum.map(fn {f, _s} -> f end)
      |> Enum.sort()

    coverage_pct =
      if declared_count == 0 do
        if missing_spec, do: 0.0, else: @percent_max
      else
        supported_count / declared_count * @percent_max
      end

    %{
      statuses: statuses,
      supported_count: supported_count,
      declared_count: declared_count,
      coverage_pct: coverage_pct,
      missing_families: missing_families,
      missing_spec: missing_spec
    }
  end

  @doc false
  @spec missing_spec_result() :: exchange_result()
  defp missing_spec_result do
    statuses = Map.new(families(), fn f -> {f, :unsupported} end)
    build_result(statuses, true)
  end

  @doc false
  @spec has_gaps?(exchange_result()) :: boolean()
  defp has_gaps?(result) do
    result.missing_spec or result.missing_families != []
  end

  @doc false
  @spec fully_covered?(exchange_result()) :: boolean()
  defp fully_covered?(result) do
    not result.missing_spec and result.missing_families == []
  end

  # -- Channel Classification ------------------------------------------------

  @doc false
  # Classifies a single channel template's channel_name quality
  @spec classify_channel(atom(), map(), String.t() | nil, map() | nil) :: channel_quality()
  defp classify_channel(method, tmpl, channel_name, ws_has)

  defp classify_channel(_method, _tmpl, cn, _ws_has) when is_binary(cn) and cn != "" do
    if cn in @js_variable_names, do: :unresolved_var, else: :ok
  end

  defp classify_channel(_method, %{url_routed: true}, _cn, _ws_has), do: :url_routed

  defp classify_channel(method, _tmpl, _cn, ws_has) do
    if private_method?(method) and method_declared?(method, ws_has) do
      :private_channel
    else
      :unexpected_nil
    end
  end

  @doc false
  @spec private_method?(atom()) :: boolean()
  defp private_method?(method) do
    method_str = Atom.to_string(method)
    Enum.any?(@private_prefixes, &String.starts_with?(method_str, &1))
  end

  @doc false
  # Check if ws.has declares this method (true means supported)
  @spec method_declared?(atom(), map() | nil) :: boolean()
  defp method_declared?(_method, nil), do: false
  defp method_declared?(method, ws_has), do: Map.get(ws_has, method) == true
end
