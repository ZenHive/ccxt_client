defmodule CCXT.WS.Subscription do
  @moduledoc """
  Dispatches subscription operations to pattern-specific modules.

  This module provides the main interface for building WebSocket subscription
  messages. It routes to the appropriate pattern module based on the exchange's
  `subscription_pattern` from the spec.

  ## Usage

      config = %{
        subscription_pattern: :op_subscribe,
        subscription_config: %{
          op_field: "op",
          args_field: "args",
          separator: "."
        }
      }

      # Build a subscribe message
      message = CCXT.WS.Subscription.build_subscribe(["tickers.BTCUSDT"], config)
      #=> %{"op" => "subscribe", "args" => ["tickers.BTCUSDT"]}

      # Format a channel from template
      template = %{channel_name: "tickers", separator: "."}
      channel = CCXT.WS.Subscription.format_channel(template, %{symbol: "BTC/USDT"}, config)
      #=> "tickers.BTCUSDT"

  """

  alias CCXT.WS.Patterns.ActionSubscribe
  alias CCXT.WS.Patterns.Custom
  alias CCXT.WS.Patterns.EventSubscribe
  alias CCXT.WS.Patterns.JsonRpc
  alias CCXT.WS.Patterns.MethodAsTopic
  alias CCXT.WS.Patterns.MethodParams
  alias CCXT.WS.Patterns.MethodSubscribe
  alias CCXT.WS.Patterns.MethodSubscription
  alias CCXT.WS.Patterns.MethodTopics
  alias CCXT.WS.Patterns.OpSubscribe
  alias CCXT.WS.Patterns.OpSubscribeObjects
  alias CCXT.WS.Patterns.ReqtypeSub
  alias CCXT.WS.Patterns.SubBased
  alias CCXT.WS.Patterns.TypeSubscribe

  @pattern_modules %{
    op_subscribe: OpSubscribe,
    op_subscribe_objects: OpSubscribeObjects,
    method_subscribe: MethodSubscribe,
    type_subscribe: TypeSubscribe,
    jsonrpc_subscribe: JsonRpc,
    event_subscribe: EventSubscribe,
    action_subscribe: ActionSubscribe,
    method_params_subscribe: MethodParams,
    method_subscription: MethodSubscription,
    method_as_topic: MethodAsTopic,
    method_topics: MethodTopics,
    sub_subscribe: SubBased,
    reqtype_sub: ReqtypeSub,
    custom: Custom
  }

  @typedoc "Subscription configuration from spec (ws_config portion of exchange spec)"
  @type config :: %{
          optional(:subscription_pattern) => atom(),
          optional(:subscription_config) => map(),
          optional(atom()) => term()
        }

  @doc """
  Returns the list of supported subscription patterns.
  """
  @spec patterns() :: [atom()]
  def patterns, do: Map.keys(@pattern_modules)

  @doc """
  Returns the pattern module for a given pattern atom.
  """
  @spec pattern_module(atom()) :: module() | nil
  def pattern_module(pattern), do: Map.get(@pattern_modules, pattern)

  @doc """
  Builds a subscribe message for the given channels.

  Uses the pattern from config to dispatch to the appropriate pattern module.

  ## Examples

      config = %{subscription_pattern: :op_subscribe, subscription_config: %{}}
      CCXT.WS.Subscription.build_subscribe(["tickers.BTCUSDT"], config)
      #=> %{"op" => "subscribe", "args" => ["tickers.BTCUSDT"]}

  """
  @spec build_subscribe([String.t() | map()], config()) :: map()
  def build_subscribe(channels, config) when is_list(channels) do
    pattern = config[:subscription_pattern] || :custom
    sub_config = config[:subscription_config] || %{}
    module = Map.get(@pattern_modules, pattern, Custom)

    module.subscribe(channels, sub_config)
  end

  @doc """
  Builds an unsubscribe message for the given channels.

  Uses the pattern from config to dispatch to the appropriate pattern module.

  ## Examples

      config = %{subscription_pattern: :op_subscribe, subscription_config: %{}}
      CCXT.WS.Subscription.build_unsubscribe(["tickers.BTCUSDT"], config)
      #=> %{"op" => "unsubscribe", "args" => ["tickers.BTCUSDT"]}

  """
  @spec build_unsubscribe([String.t() | map()], config()) :: map()
  def build_unsubscribe(channels, config) when is_list(channels) do
    pattern = config[:subscription_pattern] || :custom
    sub_config = config[:subscription_config] || %{}
    module = Map.get(@pattern_modules, pattern, Custom)

    module.unsubscribe(channels, sub_config)
  end

  @doc """
  Formats a channel name from a template and parameters.

  Takes a channel template (from spec.ws.channel_templates), parameters
  (symbol, timeframe, etc.), and config, then produces the formatted
  channel string.

  ## Examples

      template = %{channel_name: "tickers", separator: "."}
      params = %{symbol: "BTC/USDT"}
      config = %{subscription_pattern: :op_subscribe, subscription_config: %{}}

      CCXT.WS.Subscription.format_channel(template, params, config)
      #=> "tickers.BTCUSDT"

  """
  @spec format_channel(map(), map(), config()) :: String.t() | map()
  def format_channel(template, params, config) do
    pattern = config[:subscription_pattern] || :custom
    sub_config = config[:subscription_config] || %{}
    module = Map.get(@pattern_modules, pattern, Custom)

    # Thread symbol_context into sub_config so pattern modules can access it
    sub_config =
      case config[:symbol_context] do
        nil -> sub_config
        ctx -> Map.put(sub_config, :symbol_context, ctx)
      end

    module.format_channel(template, params, sub_config)
  end
end
