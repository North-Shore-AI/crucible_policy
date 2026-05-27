defmodule CruciblePolicy.ControlVector do
  @moduledoc """
  Contract for downstream vector steering.
  """

  alias CruciblePolicy.GateDecision

  @derive Jason.Encoder
  defstruct vector_id: nil,
            trace_id: nil,
            source_signal_refs: [],
            storage_ref: nil,
            target_tap: nil,
            projection_ref: nil,
            scale: 1.0,
            shape: nil,
            dtype: nil,
            required_capability: :inject,
            metadata: %{}

  @type t :: %__MODULE__{}

  def new!(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)

    %__MODULE__{
      vector_id: Map.fetch!(attrs, :vector_id),
      trace_id: Map.fetch!(attrs, :trace_id),
      source_signal_refs: Map.get(attrs, :source_signal_refs, []),
      storage_ref: Map.get(attrs, :storage_ref),
      target_tap: Map.get(attrs, :target_tap),
      projection_ref: Map.get(attrs, :projection_ref),
      scale: Map.get(attrs, :scale, 1.0),
      shape: Map.get(attrs, :shape),
      dtype: Map.get(attrs, :dtype),
      required_capability: Map.get(attrs, :required_capability, :inject),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  def handoff(%__MODULE__{} = vector, capabilities) do
    if supports?(capabilities, vector.required_capability) do
      {:ok,
       %{
         action: :active_control_handoff,
         control_type: :control_vector,
         required_capability: vector.required_capability,
         target_tap: vector.target_tap,
         vector: vector
       }}
    else
      {:error,
       unsupported_decision(vector.trace_id, vector.required_capability, vector.vector_id)}
    end
  end

  defp unsupported_decision(trace_id, capability, vector_id) do
    GateDecision.new!(
      trace_id: trace_id,
      action: :reject,
      reason: :unsupported_active_control,
      metadata: %{
        control_type: :control_vector,
        control_ref: vector_id,
        required_capability: capability
      }
    )
  end

  defp supports?(capabilities, capability) when is_list(capabilities) do
    capability in Enum.map(capabilities, &normalize_capability/1)
  end

  defp supports?(%MapSet{} = capabilities, capability),
    do: supports?(MapSet.to_list(capabilities), capability)

  defp supports?(capabilities, capability) when is_map(capabilities) do
    cond do
      Map.has_key?(capabilities, :capabilities) ->
        supports?(Map.get(capabilities, :capabilities), capability)

      Map.has_key?(capabilities, "capabilities") ->
        supports?(Map.get(capabilities, "capabilities"), capability)

      true ->
        Map.get(capabilities, capability) in [true, "true", 1]
    end
  end

  defp supports?(_capabilities, _capability), do: false

  defp normalize_capability(value) when is_binary(value), do: String.to_atom(value)
  defp normalize_capability(value), do: value

  defp normalize_attrs(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize_attrs()

  defp normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end
end
