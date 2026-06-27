defmodule CruciblePolicy.SharedMemoryWrite do
  @moduledoc """
  Trace-backed shared memory write request.
  """

  alias CruciblePolicy.{GateDecision, SafeTerms}

  @derive Jason.Encoder
  defstruct memory_ref: nil,
            trace_id: nil,
            signal_refs: [],
            summary: %{},
            visibility: :run,
            retention: :ephemeral,
            required_capability: :shared_memory_write,
            metadata: %{}

  @type t :: %__MODULE__{}

  def new!(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)

    %__MODULE__{
      memory_ref: Map.fetch!(attrs, :memory_ref),
      trace_id: Map.fetch!(attrs, :trace_id),
      signal_refs: Map.get(attrs, :signal_refs, []),
      summary: Map.get(attrs, :summary, %{}),
      visibility: Map.get(attrs, :visibility, :run),
      retention: Map.get(attrs, :retention, :ephemeral),
      required_capability: Map.get(attrs, :required_capability, :shared_memory_write),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  def handoff(%__MODULE__{} = write, capabilities) do
    if supports?(capabilities, write.required_capability) or
         supports?(capabilities, :shared_memory) do
      {:ok,
       %{
         action: :memory_write_handoff,
         required_capability: write.required_capability,
         write: write
       }}
    else
      {:error, unsupported_decision(write)}
    end
  end

  defp unsupported_decision(%__MODULE__{} = write) do
    GateDecision.new!(
      trace_id: write.trace_id,
      action: :reject,
      reason: :unsupported_active_control,
      metadata: %{
        control_type: :shared_memory_write,
        control_ref: write.memory_ref,
        required_capability: write.required_capability
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

  defp normalize_capability(value) when is_binary(value), do: SafeTerms.atomize_existing(value)
  defp normalize_capability(value), do: value

  defp normalize_attrs(attrs), do: SafeTerms.normalize_attrs(attrs)
end
