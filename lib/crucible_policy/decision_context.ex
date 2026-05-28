defmodule CruciblePolicy.DecisionContext do
  @moduledoc """
  Incremental policy state carried across token-boundary signal events.
  """

  alias Crucible.SignalRecord
  alias CruciblePolicy.{RunningScalar, Uncertainty}

  @derive Jason.Encoder
  defstruct trace_id: nil,
            runtime_profile: nil,
            surface_id: nil,
            token_index: nil,
            signal_window: [],
            accumulated_uncertainty: %Uncertainty{},
            running_entropy: %RunningScalar{},
            budget: %{max_tokens: nil, elapsed_ms: 0},
            decisions: [],
            metadata: %{}

  @type t :: %__MODULE__{}

  def new(attrs \\ []) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)

    %__MODULE__{
      trace_id: Map.get(attrs, :trace_id),
      runtime_profile: Map.get(attrs, :runtime_profile),
      surface_id: Map.get(attrs, :surface_id),
      token_index: Map.get(attrs, :token_index),
      signal_window: Map.get(attrs, :signal_window, []),
      accumulated_uncertainty:
        normalize_uncertainty(Map.get(attrs, :accumulated_uncertainty, %Uncertainty{})),
      running_entropy:
        normalize_running_scalar(Map.get(attrs, :running_entropy, %RunningScalar{})),
      budget: Map.get(attrs, :budget, %{max_tokens: nil, elapsed_ms: 0}),
      decisions: Map.get(attrs, :decisions, []),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  def put_signal(%__MODULE__{} = context, %SignalRecord{} = record, opts \\ []) do
    max_window = Keyword.get(opts, :max_window, 16)
    token_index = record.token_index || context.token_index

    %{
      context
      | token_index: token_index,
        signal_window: [record | context.signal_window] |> Enum.take(max_window)
    }
  end

  def update_uncertainty(%__MODULE__{} = context, %Uncertainty{} = uncertainty) do
    %{context | accumulated_uncertainty: uncertainty}
  end

  def update_running_entropy(%__MODULE__{} = context, entropy) when is_number(entropy) do
    %{context | running_entropy: RunningScalar.add(context.running_entropy, entropy)}
  end

  def update_running_entropy(%__MODULE__{} = context, _entropy), do: context

  def record_decision(%__MODULE__{} = context, decision) do
    %{context | decisions: [decision | context.decisions]}
  end

  def supports?(%__MODULE__{} = context, capability) do
    capability in capabilities(context)
  end

  def capabilities(%__MODULE__{} = context) do
    [
      capabilities_from(context.runtime_profile),
      capabilities_from(context.metadata),
      capabilities_from(Map.get(context.metadata, :surface_capabilities)),
      capabilities_from(Map.get(context.metadata, :capabilities))
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&normalize_capability/1)
    |> Enum.uniq()
  end

  defp capabilities_from(nil), do: []
  defp capabilities_from(value) when is_list(value), do: value
  defp capabilities_from(%MapSet{} = value), do: MapSet.to_list(value)

  defp capabilities_from(value) when is_map(value) do
    cond do
      Map.has_key?(value, :capabilities) ->
        capabilities_from(Map.get(value, :capabilities))

      Map.has_key?(value, "capabilities") ->
        capabilities_from(Map.get(value, "capabilities"))

      Map.has_key?(value, :supported_capabilities) ->
        capabilities_from(Map.get(value, :supported_capabilities))

      Map.has_key?(value, :supported_kinds) ->
        capabilities_from(Map.get(value, :supported_kinds))

      Map.has_key?(value, :tap_kinds) ->
        capabilities_from(Map.get(value, :tap_kinds))

      true ->
        truthy_capability_keys(value)
    end
  end

  defp capabilities_from(_value), do: []

  defp truthy_capability_keys(value) do
    value
    |> Enum.filter(fn {_key, enabled?} -> enabled? in [true, "true", 1] end)
    |> Enum.map(fn {key, _enabled?} -> key end)
  end

  defp normalize_capability(value) when is_binary(value), do: String.to_atom(value)
  defp normalize_capability(value), do: value

  defp normalize_uncertainty(%Uncertainty{} = uncertainty), do: uncertainty
  defp normalize_uncertainty(attrs), do: struct(Uncertainty, normalize_attrs(attrs))

  defp normalize_running_scalar(%RunningScalar{} = scalar), do: scalar
  defp normalize_running_scalar(attrs), do: RunningScalar.new(attrs)

  defp normalize_attrs(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize_attrs()

  defp normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end
end
